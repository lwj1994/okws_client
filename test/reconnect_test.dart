import 'dart:async';
import 'dart:io';

import 'package:okws_client/okws_client.dart';
import 'package:okws_client/src/backoff_strategy.dart';
import 'package:test/test.dart';

void main() {
  HttpServer? server;
  final int port = 8081;
  final String wsUrl = 'ws://localhost:$port';
  final List<WebSocket> connectedSockets = [];

  // Helper to start the server
  Future<void> startServer() async {
    server = await HttpServer.bind('localhost', port);
    // print('Test server listening on $wsUrl');
    server!.listen((HttpRequest request) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        WebSocketTransformer.upgrade(request).then((WebSocket socket) {
          connectedSockets.add(socket);
          socket.listen((message) {
            if (message == 'close') {
              socket.close();
            } else {
              socket.add('Echo: $message');
            }
          }, onDone: () {
            connectedSockets.remove(socket);
          });
        });
      }
    });
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

  group('OkWsClient Reconnection Tests', () {
    late OkWsClient client;

    setUp(() async {
      // Ensure no server is running initially if we want to test that
      // But for most tests we probably want a server
      OkWsClient.init(isLoggingEnable: false);
    });

    tearDown(() async {
      client.dispose();
      await stopServer();
    });

    test('should connect successfully', () async {
      await startServer();
      client = OkWsClient(wsUrl);

      final states = <SocketState>[];
      client.onStateChange.listen(states.add);

      await client.connect();

      // Wait a bit for connection to be established
      await Future.delayed(Duration(milliseconds: 100));

      expect(client.state, equals(SocketState.connected));
      expect(states, contains(SocketState.connected));
    });

    test('should reconnect when server closes connection', () async {
      await startServer();
      // Set a short reconnect interval for testing
      client = OkWsClient(wsUrl,
          backoffStrategy: LinearBackoff(Duration(milliseconds: 500)));

      await client.connect();
      await Future.delayed(Duration(milliseconds: 100));
      expect(client.state, equals(SocketState.connected));

      // Send 'close' to tell server to close the connection
      await client.send('close');

      // Wait for disconnect
      await Future.delayed(Duration(milliseconds: 200));
      expect(client.state, equals(SocketState.disconnected));

      // Wait for reconnect (interval is 500ms)
      await Future.delayed(Duration(milliseconds: 1000));
      expect(client.state, equals(SocketState.connected));
    });

    test('should reconnect when server restarts', () async {
      await startServer();
      client = OkWsClient(wsUrl,
          backoffStrategy: LinearBackoff(Duration(milliseconds: 500)));

      await client.connect();
      await Future.delayed(Duration(milliseconds: 100));
      expect(client.state, equals(SocketState.connected));

      // Stop the server
      await stopServer();

      // Wait for client to detect disconnect
      // Giving it more time to detect the socket close
      await Future.delayed(Duration(milliseconds: 1000));
      expect(client.state, equals(SocketState.disconnected));

      // Restart the server
      await startServer();

      // Wait for reconnect
      await Future.delayed(Duration(milliseconds: 1500));
      expect(client.state, equals(SocketState.connected));
    });
  });
}
