import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo_task.dart';
import '../models/habit.dart';
import 'todo_service.dart';
import 'habit_service.dart';
import 'pomodoro_service.dart';
import 'behavior_insights_service.dart';
import 'alarm_scheduler_service.dart';
import 'data_sync.dart';

/// A local HTTP bridge so Claude (via a companion MCP server running on the
/// same Wi-Fi network — see `mcp-server/` at the repo root) can read and
/// manage InkList tasks. Off by default, bearer-token-gated, and only runs
/// while the app process is alive — deliberately no persistent background
/// service or internet exposure, since this is a network-reachable endpoint
/// on the phone. See lib/screens/settings_screen.dart's "Claude Connector"
/// section for where this is surfaced to the user.
class MCPBridgeService {
  MCPBridgeService._();

  static const port = 8787;
  static const _enabledKey = 'mcp_bridge_enabled';
  static const _tokenKey = 'mcp_bridge_token';

  static HttpServer? _server;

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_enabledKey, v);
    if (v) {
      await start();
    } else {
      await stop();
    }
  }

  static Future<String> getToken() => _ensureToken();

  /// Replaces the current token — any previously-configured MCP server will
  /// need updating. Restarts the server if running, so the new token takes
  /// effect immediately.
  static Future<String> regenerateToken() async {
    final p = await SharedPreferences.getInstance();
    final token = _generateToken();
    await p.setString(_tokenKey, token);
    if (_server != null) {
      await stop();
      await start();
    }
    return token;
  }

  static Future<String> _ensureToken() async {
    final p = await SharedPreferences.getInstance();
    var token = p.getString(_tokenKey);
    if (token == null) {
      token = _generateToken();
      await p.setString(_tokenKey, token);
    }
    return token;
  }

  static String _generateToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(24, (_) => rand.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// The phone's LAN IPv4 address, for display in Settings — the MCP server
  /// (on a computer on the same Wi-Fi) needs this to reach the bridge. Null
  /// if no non-loopback IPv4 interface is up (e.g. no Wi-Fi connection).
  static Future<String?> localAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }

  static Future<void> start() async {
    if (_server != null) return;
    final token = await _ensureToken();
    final handler = const Pipeline()
        .addMiddleware(_authMiddleware(token))
        .addHandler(_buildRouter().call);
    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    } catch (_) {
      // Port already in use, no network, etc. — the Settings toggle just
      // won't show a healthy address; never crash app startup over this.
      _server = null;
    }
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static bool get isRunning => _server != null;
}

Middleware _authMiddleware(String token) {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.url.path == 'health') return innerHandler(request);
      final header = request.headers['authorization'];
      if (header != 'Bearer $token') {
        return _jsonError('Missing or invalid token', status: 401);
      }
      return innerHandler(request);
    };
  };
}

Router _buildRouter() {
  final router = Router();

  router.get('/health', (Request req) => _json({'ok': true, 'app': 'InkList'}));

  router.get('/tasks', (Request req) async {
    final scope = req.url.queryParameters['scope'] ?? 'today';
    final all = await TodoService.getAll();
    final now = DateTime.now();
    final List<TodoTask> tasks;
    switch (scope) {
      case 'all':
        tasks = all;
      case 'overdue':
        tasks = TodoService.overdueTasks(all, asOf: now);
      default:
        tasks = [
          ...TodoService.tasksForDay(all, now),
          ...TodoService.overdueTasks(all, asOf: now),
        ];
    }
    return _json({'tasks': tasks.map(taskToJson).toList()});
  });

  router.post('/tasks', (Request req) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _jsonError('Invalid JSON body');
    }
    final title = (body['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      return _jsonError('"title" is required');
    }
    DateTime dueDate;
    try {
      dueDate = body['dueDate'] != null
          ? DateTime.parse(body['dueDate'] as String)
          : DateTime.now();
    } catch (_) {
      return _jsonError('"dueDate" must be an ISO date (yyyy-MM-dd)');
    }
    final time = _parseTime(body['time'] as String?);
    final description = (body['description'] as String?)?.trim();
    final task = TodoTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      description: description == null || description.isEmpty ? null : description,
      dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
      alarmTime: time,
      priority: (body['priority'] as String?) ?? 'medium',
      alarmEnabled: time != null,
      recurrenceRule: (body['recurrence'] as String?) ?? 'none',
      createdAt: DateTime.now(),
    );
    await TodoService.upsert(task);
    if (task.alarmEnabled) await AlarmSchedulerService.syncTaskAlarm(task);
    DataSync.notifyChanged();
    return _json({'task': taskToJson(task)}, status: 201);
  });

  // Idempotent by design: an MCP "complete" tool must not un-complete a
  // task it's called on twice, so this only toggles when not already done
  // (unlike TodoService.toggleOccurrence's raw flip semantics).
  router.post('/tasks/<id>/complete', (Request req, String id) async {
    Map<String, dynamic> body = const {};
    final raw = await req.readAsString();
    if (raw.isNotEmpty) {
      try {
        body = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    DateTime day;
    try {
      day = body['day'] != null ? DateTime.parse(body['day'] as String) : DateTime.now();
    } catch (_) {
      return _jsonError('"day" must be an ISO date (yyyy-MM-dd)');
    }
    final all = await TodoService.getAll();
    final task = all.where((t) => t.id == id).firstOrNull;
    if (task == null) return _jsonError('Task not found', status: 404);
    if (!task.isCompletedOn(day)) {
      await TodoService.toggleOccurrence(id, day);
      DataSync.notifyChanged();
    }
    return _json({'ok': true});
  });

  router.get('/habits', (Request req) async {
    final habits = await HabitService.getAll();
    final now = DateTime.now();
    return _json({'habits': habits.map((h) => habitToJson(h, now: now)).toList()});
  });

  router.get('/behavior', (Request req) async {
    final tasks = await TodoService.getAll();
    final habits = await HabitService.getAll();
    final sessions = await PomodoroService.getSessions();
    final snapshot = BehaviorInsightsService.summarize(
      tasks: tasks,
      habits: habits,
      sessions: sessions,
    );
    return _json(snapshot);
  });

  return router;
}

TimeOfDayMs? _parseTime(String? raw) {
  if (raw == null || !raw.contains(':')) return null;
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return TimeOfDayMs(hour: h, minute: m);
}

/// Pure — unit-tested in test/mcp_bridge_service_test.dart without a live
/// server.
Map<String, dynamic> taskToJson(TodoTask t) => {
      'id': t.id,
      'title': t.title,
      'description': t.description,
      'dueDate': t.dueDate.toIso8601String(),
      'priority': t.priority,
      'recurrence': t.recurrenceRule,
      'isRecurring': t.isRecurring,
      'alarmEnabled': t.alarmEnabled,
      'alarmTime': t.alarmTime == null
          ? null
          : '${t.alarmTime!.hour.toString().padLeft(2, '0')}:'
              '${t.alarmTime!.minute.toString().padLeft(2, '0')}',
      'completedToday': t.isCompletedOn(DateTime.now()),
    };

/// Pure — unit-tested in test/mcp_bridge_service_test.dart without a live
/// server.
Map<String, dynamic> habitToJson(Habit h, {required DateTime now}) => {
      'id': h.id,
      'title': h.title,
      'emoji': h.emoji,
      'currentStreak': h.currentStreak(now),
      'completedToday': h.isDoneOn(now),
    };

const _jsonHeaders = {'content-type': 'application/json'};

Response _json(Map<String, dynamic> body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: _jsonHeaders);

Response _jsonError(String message, {int status = 400}) =>
    _json({'error': message}, status: status);
