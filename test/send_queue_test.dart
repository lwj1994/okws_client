import 'dart:async';
import 'dart:io';

import 'package:okws_client/okws_client.dart';
import 'package:test/test.dart';

void main() {
  group('OkWsClient Send Queue Tests', () {
    test('should queue message and send when reconnected', () async {
      // 1. Setup a delayed server
      HttpServer? server;
      final int port = 8084;
      final String wsUrl = 'ws://localhost:$port';
      final receivedMessages = <String>[];

      // Start client first (will fail to connect initially)
      OkWsClient.init(isLoggingEnable: true);
      final client = OkWsClient(wsUrl);
      
      // Start connecting (will fail)
      final connectFuture = client.connect();

      // Send message while disconnected (should be queued)
      print('Sending message while disconnected...');
      final sendFuture = client.send('queued message');

      // 2. Start server after a short delay
      await Future.delayed(Duration(seconds: 1));
      print('Starting server...');
      server = await HttpServer.bind('localhost', port);
      server.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then((socket) {
            socket.listen((message) {
              receivedMessages.add(message.toString());
            });
          });
        }
      });

      // 3. Wait for send to complete (it should succeed after reconnection)
      final result = await sendFuture;
      expect(result, isTrue);

      // Verify message received
      await Future.delayed(Duration(milliseconds: 500));
      expect(receivedMessages, contains('queued message'));

      client.dispose();
      await server.close(force: true);
    });

    test('should drop message after timeout', () async {
      // Client to non-existent server
      OkWsClient.init(isLoggingEnable: true);
      final client = OkWsClient('ws://localhost:9999'); // Invalid port
      
      client.connect(); // Will keep failing

      print('Sending message that should timeout...');
      final startTime = DateTime.now();
      final result = await client.send('timeout message');
      final duration = DateTime.now().difference(startTime);

      expect(result, isFalse);
      // Should wait at least 5 seconds
      expect(duration.inSeconds, greaterThanOrEqualTo(5));

      client.dispose();
    });
  });
}
