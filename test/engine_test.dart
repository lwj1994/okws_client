import 'dart:async';
import 'dart:io';

import 'package:okws_client/src/engine/okws_engine.dart';
import 'package:test/test.dart';

void main() {
  HttpServer? server;
  final int port = 8082;
  final String wsUrl = 'ws://localhost:$port';
  final List<WebSocket> connectedSockets = [];

  // Helper to start the server
  Future<void> startServer() async {
    server = await HttpServer.bind('localhost', port);
    server!.listen((HttpRequest request) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        WebSocketTransformer.upgrade(request).then((WebSocket socket) {
          connectedSockets.add(socket);

          // Verify headers if present
          final customHeader = request.headers.value('x-custom-header');
          if (customHeader != null) {
            socket.add('Header: $customHeader');
          }

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

  group('OkWsEngine Tests', () {
    setUp(() async {
      await startServer();
    });

    tearDown(() async {
      await stopServer();
    });

    test('should connect and send/receive messages', () async {
      final engine = await OkWsEngine.connect(wsUrl);

      final messages = <dynamic>[];
      final completer = Completer<void>();

      engine.stream.listen((message) {
        messages.add(message);
        if (messages.length >= 1) {
          completer.complete();
        }
      });

      engine.add('Hello Engine');

      await completer.future.timeout(Duration(seconds: 2));
      expect(messages.first, equals('Echo: Hello Engine'));

      await engine.close();
    });

    test('should send custom headers', () async {
      final engine = await OkWsEngine.connect(
        wsUrl,
        headers: {'x-custom-header': 'MyValue'},
      );

      final messages = <dynamic>[];
      final completer = Completer<void>();

      engine.stream.listen((message) {
        messages.add(message);
        if (messages.isNotEmpty) {
          // We expect the first message to be the header confirmation from our mock server
          completer.complete();
        }
      });

      await completer.future.timeout(Duration(seconds: 2));
      expect(messages.first, equals('Header: MyValue'));

      await engine.close();
    });

    test('should close connection', () async {
      final engine = await OkWsEngine.connect(wsUrl);

      bool isDone = false;
      engine.stream.listen(
        (_) {},
        onDone: () {
          isDone = true;
        },
      );

      await engine.close();

      // Wait a bit for the close event to propagate
      await Future.delayed(Duration(milliseconds: 100));
      expect(isDone, isTrue);
    });
  });
}
