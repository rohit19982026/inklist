import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inklist/services/mcp_bridge_service.dart';

/// Drives the real Node MCP server (mcp-server/index.js) over real stdio
/// JSON-RPC against a real MCPBridgeService HTTP instance — the full
/// vertical slice, not just the Dart side. Skips gracefully if `node` isn't
/// on PATH, since `flutter test` shouldn't hard-depend on a Node toolchain
/// being installed on every machine that runs this suite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mcp-server/index.js against a live MCPBridgeService', () {
    var nodeAvailable = false;

    setUpAll(() async {
      try {
        final result = await Process.run('node', ['--version']);
        nodeAvailable = result.exitCode == 0;
      } catch (_) {
        nodeAvailable = false;
      }
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      HttpOverrides.global = null;
    });

    tearDown(() async {
      await MCPBridgeService.stop();
    });

    test(
      'inklist_create_task then inklist_list_tasks round-trips over stdio MCP',
      () async {
        if (!nodeAvailable) {
          // ignore: avoid_print
          print('Skipping mcp-server integration test: node not found on PATH.');
          return;
        }

        await MCPBridgeService.start();
        final token = await MCPBridgeService.getToken();

        final serverPath = '${Directory.current.path}/mcp-server/index.js';
        expect(File(serverPath).existsSync(), isTrue,
            reason: 'mcp-server/index.js not found at $serverPath — run '
                'flutter test from the repo root.');

        final process = await Process.start(
          'node',
          [serverPath],
          environment: {'INKLIST_HOST': '127.0.0.1', 'INKLIST_TOKEN': token},
        );

        final responses = <Map<String, dynamic>>[];
        final stdoutSub = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (line.trim().isEmpty) return;
          try {
            responses.add(jsonDecode(line) as Map<String, dynamic>);
          } catch (_) {
            // Not JSON — ignore (shouldn't happen on stdout for this server).
          }
        });
        final stderrSub =
            process.stderr.transform(utf8.decoder).listen((s) {
          // ignore: avoid_print
          print('[mcp-server stderr] $s');
        });

        void send(Map<String, dynamic> message) {
          process.stdin.writeln(jsonEncode(message));
        }

        Future<Map<String, dynamic>> waitForId(int id) async {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (DateTime.now().isBefore(deadline)) {
            final match = responses.where((r) => r['id'] == id);
            if (match.isNotEmpty) return match.first;
            await Future.delayed(const Duration(milliseconds: 50));
          }
          throw TimeoutException('No MCP response for id $id');
        }

        try {
          send({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
            'params': {
              'protocolVersion': '2024-11-05',
              'capabilities': {},
              'clientInfo': {'name': 'inklist-test', 'version': '1.0.0'},
            },
          });
          await waitForId(1);
          send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});

          send({
            'jsonrpc': '2.0',
            'id': 2,
            'method': 'tools/call',
            'params': {
              'name': 'inklist_create_task',
              'arguments': {'title': 'Ping from MCP integration test'},
            },
          });
          final createResp = await waitForId(2);
          final createResult = createResp['result'] as Map<String, dynamic>;
          expect(createResult['isError'], isNot(true));
          final createText =
              (createResult['content'] as List).first['text'] as String;
          expect(createText, contains('Ping from MCP integration test'));

          send({
            'jsonrpc': '2.0',
            'id': 3,
            'method': 'tools/call',
            'params': {
              'name': 'inklist_list_tasks',
              'arguments': {'scope': 'all'},
            },
          });
          final listResp = await waitForId(3);
          final listResult = listResp['result'] as Map<String, dynamic>;
          final listText =
              (listResult['content'] as List).first['text'] as String;
          expect(listText, contains('Ping from MCP integration test'));
        } finally {
          await stdoutSub.cancel();
          await stderrSub.cancel();
          process.kill();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
