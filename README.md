# OkWs Client

A lightweight, robust WebSocket client for Dart, built on top of `dart:io`. It provides automatic reconnection, configurable backoff strategies, and connection health monitoring.

## Features

- **Robust Reconnection**: Automatically reconnects when the connection is lost.
- **Configurable Backoff**: Supports `LinearBackoff` and `ExponentialBackoff` strategies for reconnection attempts.
- **Connection Health**: Built-in support for `pingInterval` and **Application-level Heartbeat** to keep connections alive and detect dead sockets.
- **Customization**: Support for custom HTTP headers and `HttpClient` (e.g., for self-signed certificates).
- **Message Buffering**: Automatically buffers messages for up to 5 seconds when disconnected and sends them upon reconnection.
- **Logging**: Detailed logging with support for custom `LogAdapter`.

## Usage

### Basic Usage

```dart
import 'package:okws_client/okws_client.dart';

void main() async {
  // Initialize logging (optional)
  OkWsClient.init(isLoggingEnable: true);

  // Create instance with configuration
  final socket = OkWsClient(
    'ws://localhost:8080',
    // Auto-reconnect with exponential backoff
    backoffStrategy: ExponentialBackoff(
      initial: Duration(seconds: 1),
      max: Duration(seconds: 30),
    ),
    // Send a ping every 10 seconds
    pingInterval: Duration(seconds: 10),
    // Application-level heartbeat (optional)
    heartbeat: OkWsHeartbeat(
      interval: Duration(seconds: 15),
      request: 'ping',
      validator: (msg) => msg == 'pong',
      timeout: Duration(seconds: 5),
    ),
    // Custom headers
    headers: {'Authorization': 'Bearer token'},
  );

  // Listen to state changes
  socket.onStateChange.listen((state) {
    print('State: $state');
  });

  // Listen to messages
  socket.onReceive.listen((message) {
    print('Received: $message');
  });

  // Connect
  await socket.connect();

  // Send message (returns true if sent or buffered successfully)
  final sent = await socket.send('Hello');
  if (sent) {
    print('Message sent or queued!');
  } else {
    print('Failed to send message (timeout).');
  }
  
  // Disconnect
  // socket.disconnect();
}
```

### Advanced Configuration

#### Custom Logging

Redirect internal logs to your own logging system (e.g., Crashlytics, logging package).

```dart
OkWsClient.init(
  isLoggingEnable: true,
  logAdapter: (message) {
    // Forward to your logger
    print('[MyLogger] $message');
  },
);
```

#### Self-Signed Certificates

Use a custom `HttpClient` to handle self-signed certificates or proxies.

```dart
import 'dart:io';
import 'package:okws_client/okws_client.dart';

final client = HttpClient()
  ..badCertificateCallback = (cert, host, port) => true;

final socket = OkWsClient(
  'wss://self-signed-server.com',
  customHttpClient: client,
);
```

## API

- `connect()`: Connect to the WebSocket server.
- `disconnect()`: Close the connection and stop reconnection attempts.
- `send(dynamic message)`: Send a String or List<int> message. Returns `Future<bool>`.
    - If connected: Sends immediately and returns `true`.
    - If disconnected: Waits up to 5 seconds for reconnection. Returns `true` if reconnected and sent, `false` if timed out.
- `onStateChange`: Stream of `SocketState` (connecting, connected, disconnected).
- `onReceive`: Stream of received messages (String or List<int>).
- `dispose()`: Closes the connection and releases all resources.
