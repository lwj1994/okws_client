import 'dart:async';
import 'dart:io' as io;

/// Abstract wrapper for WebSocket connection to support different implementations (IO vs Web).
abstract class OkWsEngine {
  /// Connect to the WebSocket server.
  static Future<OkWsEngine> connect(
    String url, {
    Map<String, dynamic>? headers,
    Duration? pingInterval,
    io.HttpClient? customHttpClient,
  }) async {
    // For now, we only implement IO version.
    // In a real cross-platform scenario, we would use conditional imports.
    return _OkWsEngineIO.connect(
      url,
      headers: headers,
      pingInterval: pingInterval,
      customHttpClient: customHttpClient,
    );
  }

  /// The stream of incoming messages.
  Stream<dynamic> get stream;

  /// The sink for outgoing messages.
  void add(dynamic data);

  /// Close the connection.
  Future<void> close([int? code, String? reason]);
}

/// IO implementation of OkWsEngine using dart:io.
class _OkWsEngineIO implements OkWsEngine {
  final io.WebSocket _socket;

  _OkWsEngineIO(this._socket);

  static Future<OkWsEngine> connect(
    String url, {
    Map<String, dynamic>? headers,
    Duration? pingInterval,
    io.HttpClient? customHttpClient,
  }) async {
    final socket = await io.WebSocket.connect(
      url,
      headers: headers,
      customClient: customHttpClient,
    );
    if (pingInterval != null) {
      socket.pingInterval = pingInterval;
    }
    return _OkWsEngineIO(socket);
  }

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void add(dynamic data) {
    _socket.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) {
    return _socket.close(code, reason);
  }
}
