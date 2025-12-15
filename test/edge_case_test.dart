import 'dart:async';
import 'dart:io';

import 'package:okws_client/okws_client.dart';
import 'package:test/test.dart';

void main() {
  group('OkWsClient Edge Case Tests', () {
    final int port = 8092;
    final String wsUrl = 'ws://localhost:$port';
    HttpServer? server;

    setUp(() async {
      OkWsClient.init(isLoggingEnable: true);
      server = await HttpServer.bind('localhost', port);
      server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((socket) {
            socket.listen((msg) {
              if (msg == 'ping') socket.add('pong');
            });
          });
        }
      });
    });

    tearDown(() async {
      await server?.close(force: true);
    });

    test('should fail safely when sending after dispose', () async {
      final client = OkWsClient(wsUrl);

      // Don't connect, just dispose immediately
      client.dispose();

      // Send message
      final result = await client.send('hello');

      // Should return false and NOT throw exception
      expect(result, isFalse);
    });

    test('should stop connection attempt if disconnected during connect',
        () async {
      // Use a non-existent port to force connection to take some time (or fail slowly)
      // Or use a proxy that delays handshake if possible.
      // But simplest is to call connect then immediately disconnect.

      final client = OkWsClient(wsUrl);

      // Start connection
      final connectFuture = client.connect();

      // Immediately disconnect
      client.disconnect();

      await connectFuture;

      // State should be disconnected
      expect(client.state, equals(SocketState.disconnected));

      // Wait a bit to ensure no late connection events occur
      await Future.delayed(Duration(milliseconds: 500));
      expect(client.state, equals(SocketState.disconnected));

      client.dispose();
    });

    test('should NOT double trigger disconnect on heartbeat timeout', () async {
      // Use a silent server (setUp already handles ping/pong, so we need a silent one or just block response)
      // We can use a custom client that intercepts pong? No.
      // Let's create a silent server on different port
      final silentServer = await HttpServer.bind('localhost', 0);
      final silentPort = silentServer.port;

      silentServer.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((socket) {
            socket.listen((_) {}); // Ignore everything
          });
        }
      });

      final client = OkWsClient(
        'ws://localhost:$silentPort',
        heartbeat: OkWsHeartbeat(
          interval: Duration(milliseconds: 200), // Increase interval
          timeout: Duration(
              milliseconds: 50), // Decrease timeout (Timeout < Interval)
          request: 'ping',
          validator: (msg) => msg == 'pong',
        ),
      );

      // Track state changes
      int disconnectCount = 0;
      client.onStateChange.listen((state) {
        if (state == SocketState.disconnected) {
          disconnectCount++;
        }
      });

      await client.connect();

      // Wait for timeout
      await Future.delayed(Duration(milliseconds: 500));

      // Disconnect should happen.
      // Ideally count should be 1 (for the initial timeout).
      // If logic was buggy, it might be 2 (one from timeout callback, one from stream close).
      // Note: Reconnection might trigger more disconnects if it fails fast,
      // so we should check the logs or ensure reconnect backoff is long enough.
      // Default backoff is 3s, so we are safe within 500ms.

      expect(disconnectCount, equals(1));

      client.dispose();
      await silentServer.close(force: true);
    });
  });
}
