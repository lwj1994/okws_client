import 'package:okws_client/okws_client.dart';

void main() async {
  OkWsClient.init(isLoggingEnable: true);

  final socket = OkWsClient('ws://localhost:8080');

  socket.onStateChange.listen((state) {
    print('State changed: $state');
  });

  socket.onReceive.listen((message) {
    print('Received: $message');
  });

  print('Connecting...');
  await socket.connect();

  print('Sending Hello');
  await socket.send('Hello');

  // Wait a bit
  await Future.delayed(Duration(seconds: 2));

  print('Triggering server-side close by sending "close"');
  await socket.send('close');

  // Wait to see reconnection happen
  await Future.delayed(Duration(seconds: 5));

  print('Sending Hello again (should be reconnected)');
  await socket.send('Hello Again');

  await Future.delayed(Duration(seconds: 2));

  print('Disconnecting manually');
  socket.disconnect();
}
