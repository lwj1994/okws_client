import 'dart:async';
import 'dart:io';

import 'package:okws_client/okws_client.dart';
import 'package:okws_client/src/backoff_strategy.dart';
import 'package:test/test.dart';

void main() {
  HttpServer? server;
  final int port = 8083;
  final String wsUrl = 'ws://localhost:$port';
  final List<WebSocket> connectedSockets = [];

  // Helper to start the server
  Future<void> startServer() async {
    // If server is already running, do nothing or maybe throw?
    // For this test we assume we call start after stop.
    if (server != null) return;

    try {
      server = await HttpServer.bind('localhost', port);
      server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((WebSocket socket) {
            connectedSockets.add(socket);
            socket.listen((message) {
              if (message == 'ping') {
                try {
                  socket.add('pong');
                } catch (e) {
                  print('Server error sending pong: $e');
                }
              }
            }, onDone: () {
              connectedSockets.remove(socket);
            });
          });
        }
      });
    } catch (e) {
      print('Error starting server: $e');
    }
  }

  // Helper to stop the server
  Future<void> stopServer() async {
    for (var socket in connectedSockets) {
      await socket.close();
    }
    connectedSockets.clear();
    await server?.close(force: true);
    server = null;
  }

  group('OkWsClient Instability Tests', () {
    late OkWsClient client;

    setUp(() {
      OkWsClient.init(isLoggingEnable: true);
    });

    tearDown(() async {
      client.dispose();
      await stopServer();
    });

    test('should survive multiple server restarts', () async {
      // 1. Start server
      await startServer();

      // Client with fast reconnect
      client = OkWsClient(
        wsUrl,
        backoffStrategy: LinearBackoff(Duration(milliseconds: 200)),
      );

      final stateChanges = <SocketState>[];
      client.onStateChange.listen(stateChanges.add);

      await client.connect();
      await Future.delayed(Duration(milliseconds: 100));
      expect(client.state, equals(SocketState.connected));

      // Cycle 1: Server goes down
      print('--- Cycle 1: Stopping Server ---');
      await stopServer();
      await Future.delayed(Duration(milliseconds: 500)); // Wait for detect
      expect(client.state, equals(SocketState.disconnected));

      // Server comes back
      print('--- Cycle 1: Starting Server ---');
      await startServer();
      await Future.delayed(Duration(milliseconds: 1000)); // Wait for reconnect
      expect(client.state, equals(SocketState.connected));

      // Verify communication
      final pongCompleter = Completer<void>();
      final sub = client.onReceive.listen((msg) {
        if (msg == 'pong') pongCompleter.complete();
      });
      await client.send('ping');
      await pongCompleter.future.timeout(Duration(seconds: 1));
      await sub.cancel();

      // Cycle 2: Server goes down again
      print('--- Cycle 2: Stopping Server ---');
      await stopServer();
      await Future.delayed(Duration(milliseconds: 500));
      expect(client.state, equals(SocketState.disconnected));

      // Server comes back again
      print('--- Cycle 2: Starting Server ---');
      await startServer();
      await Future.delayed(Duration(milliseconds: 1000));
      expect(client.state, equals(SocketState.connected));

      // Cycle 3: Server goes down again
      print('--- Cycle 3: Stopping Server ---');
      await stopServer();
      await Future.delayed(Duration(milliseconds: 500));
      expect(client.state, equals(SocketState.disconnected));

      // Server comes back again
      print('--- Cycle 3: Starting Server ---');
      await startServer();
      await Future.delayed(Duration(milliseconds: 1000));
      expect(client.state, equals(SocketState.connected));

      // Final check
      expect(stateChanges.where((s) => s == SocketState.connected).length,
          greaterThanOrEqualTo(4));
    });
  });
}
