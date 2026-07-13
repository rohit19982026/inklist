import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:inklist/services/mcp_bridge_service.dart';
import 'package:inklist/services/todo_service.dart';
import 'package:inklist/models/todo_task.dart';
import 'package:inklist/models/habit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('taskToJson / habitToJson (pure, no server)', () {
    test('taskToJson includes the expected fields', () {
      final task = TodoTask(
        id: 't1',
        title: 'Write report',
        priority: 'high',
        dueDate: DateTime(2026, 7, 13),
        alarmTime: const TimeOfDayMs(hour: 9, minute: 30),
        alarmEnabled: true,
        createdAt: DateTime(2026, 7, 1),
      );
      final json = taskToJson(task);
      expect(json['id'], 't1');
      expect(json['title'], 'Write report');
      expect(json['priority'], 'high');
      expect(json['alarmTime'], '09:30');
      expect(json['alarmEnabled'], isTrue);
      expect(json['completedToday'], isFalse);
    });

    test('taskToJson omits alarmTime when unset', () {
      final task = TodoTask(
        id: 't2',
        title: 'Simple',
        dueDate: DateTime(2026, 7, 13),
        createdAt: DateTime(2026, 7, 1),
      );
      expect(taskToJson(task)['alarmTime'], isNull);
      expect(taskToJson(task)['alarmEnabled'], isFalse);
    });

    test('habitToJson reports current streak and today completion', () {
      final today = DateTime(2026, 7, 13);
      final habit = Habit(
        id: 'h1',
        title: 'Drink water',
        colorValue: 0xFFCDEFD8,
        completedDates: {Habit.dateKey(today)},
        createdAt: DateTime(2026, 1, 1),
      );
      final json = habitToJson(habit, now: today);
      expect(json['currentStreak'], 1);
      expect(json['completedToday'], isTrue);
    });
  });

  group('MCPBridgeService HTTP bridge (live local server)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // flutter_test's TestWidgetsFlutterBinding installs a fake HttpClient
      // that returns 400 for everything, for test determinism — this suite
      // deliberately wants real local-network calls against the real shelf
      // server (unaffected either way, since HttpOverrides only intercepts
      // HttpClient creation, not HttpServer).
      HttpOverrides.global = null;
    });

    tearDown(() async {
      await MCPBridgeService.stop();
    });

    Uri uri(String path) =>
        Uri.parse('http://127.0.0.1:${MCPBridgeService.port}$path');

    test('/health responds without a token', () async {
      await MCPBridgeService.start();
      final resp = await http.get(uri('/health'));
      expect(resp.statusCode, 200);
      expect(jsonDecode(resp.body)['ok'], isTrue);
    });

    test('rejects requests without a valid token', () async {
      await MCPBridgeService.start();
      final noAuth = await http.get(uri('/tasks'));
      expect(noAuth.statusCode, 401);

      final wrongAuth = await http.get(
        uri('/tasks'),
        headers: {'authorization': 'Bearer not-the-real-token'},
      );
      expect(wrongAuth.statusCode, 401);
    });

    test('creates a task via POST /tasks and lists it via GET /tasks', () async {
      await MCPBridgeService.start();
      final token = await MCPBridgeService.getToken();
      final headers = {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      };

      final createResp = await http.post(
        uri('/tasks'),
        headers: headers,
        body: jsonEncode(
            {'title': 'Buy groceries', 'priority': 'high', 'time': '18:30'}),
      );
      expect(createResp.statusCode, 201);
      final created = jsonDecode(createResp.body)['task'] as Map<String, dynamic>;
      expect(created['title'], 'Buy groceries');
      expect(created['alarmTime'], '18:30');

      final listResp = await http.get(uri('/tasks?scope=all'), headers: headers);
      expect(listResp.statusCode, 200);
      final tasks = jsonDecode(listResp.body)['tasks'] as List;
      expect(tasks.any((t) => t['title'] == 'Buy groceries'), isTrue);
    });

    test('rejects a task with no title', () async {
      await MCPBridgeService.start();
      final token = await MCPBridgeService.getToken();
      final resp = await http.post(
        uri('/tasks'),
        headers: {'authorization': 'Bearer $token', 'content-type': 'application/json'},
        body: jsonEncode({'title': '   '}),
      );
      expect(resp.statusCode, 400);
    });

    test('completing a task is idempotent', () async {
      await MCPBridgeService.start();
      final token = await MCPBridgeService.getToken();
      final headers = {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      };

      final createResp = await http.post(
        uri('/tasks'),
        headers: headers,
        body: jsonEncode({'title': 'One-off task'}),
      );
      final id = (jsonDecode(createResp.body)['task'] as Map)['id'] as String;

      for (var i = 0; i < 2; i++) {
        final resp = await http.post(uri('/tasks/$id/complete'), headers: headers);
        expect(resp.statusCode, 200);
      }

      final all = await TodoService.getAll();
      final task = all.firstWhere((t) => t.id == id);
      expect(task.isCompleted, isTrue);
    });

    test('completing an unknown task returns 404', () async {
      await MCPBridgeService.start();
      final token = await MCPBridgeService.getToken();
      final resp = await http.post(
        uri('/tasks/does-not-exist/complete'),
        headers: {'authorization': 'Bearer $token'},
      );
      expect(resp.statusCode, 404);
    });

    test('GET /behavior returns the 14-day snapshot shape', () async {
      await MCPBridgeService.start();
      final token = await MCPBridgeService.getToken();
      final resp =
          await http.get(uri('/behavior'), headers: {'authorization': 'Bearer $token'});
      expect(resp.statusCode, 200);
      expect(jsonDecode(resp.body)['windowDays'], 14);
    });

    test('GET /habits returns an empty list when there are no habits', () async {
      await MCPBridgeService.start();
      final token = await MCPBridgeService.getToken();
      final resp =
          await http.get(uri('/habits'), headers: {'authorization': 'Bearer $token'});
      expect(resp.statusCode, 200);
      expect(jsonDecode(resp.body)['habits'], isEmpty);
    });
  });
}
