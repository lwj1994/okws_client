import 'dart:io';

void wslog(Object? message) {
  print('[${DateTime.now()}] $message');
}

void main() async {
  final server = await HttpServer.bind('localhost', 8080);
  wslog('WebSocket server listening on ws://localhost:8080');

  await for (HttpRequest request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocketTransformer.upgrade(request).then((socket) {
        wslog('Client connected');
        socket.listen((message) {
          wslog('Received: $message');
          socket.add('Echo: $message');
          if (message == 'close') {
            socket.close();
          }
        }, onDone: () {
          wslog('Client disconnected');
        });
      });
    } else {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.close();
    }
  }
}
