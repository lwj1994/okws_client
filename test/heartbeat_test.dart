import 'dart:async';
import 'dart:io';

import 'package:okws_client/okws_client.dart';
import 'package:test/test.dart';

void main() {
  group('OkWsClient Heartbeat Tests', () {
    HttpServer? server;
    final int port = 8085;
    final String wsUrl = 'ws://localhost:$port';
    final List<WebSocket> connectedSockets = [];

    setUp(() async {
      OkWsClient.init(isLoggingEnable: true);
      server = await HttpServer.bind('localhost', port);
      server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((socket) {
            connectedSockets.add(socket);
            socket.listen((message) {
              if (message == 'ping') {
                socket.add('pong');
              }
            }, onDone: () {
              connectedSockets.remove(socket);
            });
          });
        }
      });
    });

    tearDown(() async {
      for (var socket in connectedSockets) {
        await socket.close();
      }
      connectedSockets.clear();
      await server?.close(force: true);
    });

    test('should send heartbeat and receive response', () async {
      final client = OkWsClient(
        wsUrl,
        heartbeat: OkWsHeartbeat(
          interval: Duration(seconds: 1),
          timeout: Duration(seconds: 1),
          request: 'ping',
          validator: (msg) => msg == 'pong',
        ),
      );

      // Verify that 'pong' is intercepted and not emitted to onReceive
      bool receivedPong = false;
      client.onReceive.listen((msg) {
        if (msg == 'pong') receivedPong = true;
      });

      await client.connect();

      // Wait for heartbeat interval + verify
      await Future.delayed(Duration(milliseconds: 1500));
      
      // Client should still be connected
      expect(client.state, equals(SocketState.connected));
      
      // Should NOT have received pong in the stream
      expect(receivedPong, isFalse);
      
      client.dispose();
    });

    test('should disconnect if heartbeat times out', () async {
      // Server that doesn't respond to ping
      final silentPort = 8086;
      final silentServer = await HttpServer.bind('localhost', silentPort);
      silentServer.listen((HttpRequest request) {
         if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((socket) {
             // Do nothing on message
             socket.listen((_) {});
          });
        }
      });

      final client = OkWsClient(
        'ws://localhost:$silentPort',
        heartbeat: OkWsHeartbeat(
          interval: Duration(seconds: 1),
          timeout: Duration(milliseconds: 500),
          request: 'ping',
          validator: (msg) => msg == 'pong',
        ),
      );
      
      final states = <SocketState>[];
      client.onStateChange.listen(states.add);

      await client.connect();
      expect(client.state, equals(SocketState.connected));

      // Wait for interval (1s) + timeout (0.5s)
      await Future.delayed(Duration(seconds: 2));

      // Should have disconnected and tried to reconnect
      expect(states, contains(SocketState.disconnected));
      expect(client.state, isNot(equals(SocketState.connected))); // It might be connecting or disconnected

      client.dispose();
      await silentServer.close(force: true);
    });

    test('should NOT intercept pong if configured', () async {
      final client = OkWsClient(
        wsUrl,
        heartbeat: OkWsHeartbeat(
          interval: Duration(seconds: 1),
          timeout: Duration(seconds: 1),
          request: 'ping',
          validator: (msg) => msg == 'pong',
          interceptResponse: false, // Don't intercept
        ),
      );

      bool receivedPong = false;
      client.onReceive.listen((msg) {
        if (msg == 'pong') receivedPong = true;
      });

      await client.connect();

      // Wait for heartbeat interval
      await Future.delayed(Duration(milliseconds: 1500));

      // Should have received pong in the stream
      expect(receivedPong, isTrue);

      client.dispose();
    });
  });
}
