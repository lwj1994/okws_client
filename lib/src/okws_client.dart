import 'dart:async';
import 'dart:io';

import 'log.dart';
import 'backoff_strategy.dart';
import 'heartbeat.dart';
import 'engine/okws_engine.dart';

/// Define the states of the WebSocket connection.
enum SocketState {
  /// Connection is being established.
  connecting,

  /// Connection is successfully established.
  connected,

  /// Connection is disconnected.
  disconnected,
}

/// A simplified WebSocket client with robust reconnection logic.
class OkWsClient {
  /// Initialize the library.
  /// [isLoggingEnable]: Whether to enable logging.
  /// [logAdapter]: Optional custom logger adapter.
  static void init({bool isLoggingEnable = true, LogAdapter? logAdapter}) {
    initOkWsLog(enable: isLoggingEnable, adapter: logAdapter);
  }

  final String url;
  final Map<String, Object>? headers;
  final Duration? pingInterval;
  final BackoffStrategy _backoffStrategy;
  final HttpClient? customHttpClient;
  final OkWsHeartbeat? heartbeat;

  // Keep reconnectInterval for backward compatibility or simple usage
  // If provided in constructor, it creates a LinearBackoff

  OkWsEngine? _socket;
  final _stateController = StreamController<SocketState>.broadcast();
  final _messageController = StreamController<dynamic>.broadcast();

  bool _isExpectedDisconnect = false;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  SocketState _currentState = SocketState.disconnected;

  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;
  Timer? _reconnectTimer;

  /// Constructor
  /// [url]: The WebSocket server URL.
  /// [headers]: Optional HTTP headers to send with the connection request.
  /// [pingInterval]: Optional interval for sending ping signals to keep connection alive.
  /// [backoffStrategy]: Custom backoff strategy. Defaults to [LinearBackoff] with 3s interval.
  /// [customHttpClient]: Optional [HttpClient] for advanced configuration (e.g. badCertificateCallback).
  /// [heartbeat]: Optional application-level heartbeat configuration.
  OkWsClient(
    this.url, {
    this.headers,
    this.pingInterval,
    BackoffStrategy? backoffStrategy,
    this.customHttpClient,
    this.heartbeat,
  }) : _backoffStrategy =
            backoffStrategy ?? LinearBackoff(const Duration(seconds: 3));

  /// Listen to state changes.
  Stream<SocketState> get onStateChange => _stateController.stream;

  /// Listen to received messages.
  Stream<dynamic> get onReceive => _messageController.stream;

  /// Current state of the connection.
  SocketState get state => _currentState;

  /// Update the state and notify listeners.
  void _updateState(SocketState newState) {
    if (_currentState != newState) {
      wslog('State changed: $_currentState -> $newState');
      _currentState = newState;
      try {
        _stateController.add(newState);
      } catch (e) {
        wslog('Error updating state: $e');
      }
    }
  }

  /// Connect to the WebSocket server.
  Future<void> connect() async {
    if (_currentState == SocketState.connected ||
        _currentState == SocketState.connecting) {
      return;
    }

    _isExpectedDisconnect = false;
    await _connectInternal();
  }

  /// Internal connection logic.
  Future<void> _connectInternal() async {
    if (_currentState == SocketState.connected) return;

    wslog('Connecting to $url...');
    _updateState(SocketState.connecting);

    try {
      // Connect to the server
      _socket = await OkWsEngine.connect(
        url,
        headers: headers,
        pingInterval: pingInterval,
        customHttpClient: customHttpClient,
      );

      // Check if we were disconnected while waiting for connection
      if (_isExpectedDisconnect) {
        wslog('Connected but expected disconnect. Closing immediately.');
        _socket?.close();
        _socket = null;
        return;
      }

      wslog('Connected to $url');
      _updateState(SocketState.connected);
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _backoffStrategy.reset();
      _startHeartbeat();

      // Listen for messages
      _socket!.stream.listen(
        (data) {
          try {
            if (_handleHeartbeatResponse(data)) return;
            _messageController.add(data);
          } catch (e) {
            wslog('Error adding message to controller: $e');
          }
        },
        onDone: () {
          wslog('WebSocket connection closed by server');
          _handleDisconnect();
        },
        onError: (error) {
          wslog('WebSocket error: $error');
          _handleDisconnect();
        },
      );
    } catch (e) {
      wslog('Connection failed: $e');
      _isReconnecting = false;
      _handleDisconnect();
    }
  }

  /// Handle disconnection and trigger reconnection if needed.
  void _handleDisconnect() {
    wslog(
        'Handling disconnect. Expected: $_isExpectedDisconnect, Reconnecting: $_isReconnecting');

    _stopHeartbeat();

    // Ensure we clean up the old socket
    _socket = null;

    // Update state to disconnected
    if (_currentState != SocketState.disconnected) {
      _updateState(SocketState.disconnected);
    }

    // If it was not an intentional disconnect, try to reconnect
    if (!_isExpectedDisconnect && !_isReconnecting) {
      _isReconnecting = true;
      _reconnectAttempts++;

      final delay = _backoffStrategy.next(_reconnectAttempts);
      wslog(
          'Reconnecting in ${delay.inMilliseconds}ms (attempt $_reconnectAttempts)...');

      // Wait for the interval before reconnecting
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () {
        _reconnectTimer = null;
        // Double check if we should still reconnect
        if (!_isExpectedDisconnect) {
          _connectInternal();
        } else {
          _isReconnecting = false;
        }
      });
    }
  }

  /// Disconnect from the server.
  Future<void> disconnect() async {
    wslog('Disconnecting manually...');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isExpectedDisconnect = true;
    _isReconnecting = false;
    _updateState(SocketState.disconnected);
    try {
      await _socket?.close().timeout(const Duration(seconds: 5), onTimeout: () {
        wslog('Socket close timeout after 5s.');
      });
    } catch (e) {
      wslog('Error closing socket: $e');
    }
    _socket = null;
  }

  /// Send a message to the server.
  /// [message] can be a String or `List<int>` (bytes).
  /// Returns [true] if sent successfully (or queued), [false] if dropped/failed.
  /// If disconnected, waits up to 5 seconds for reconnection before dropping.
  Future<bool> send(dynamic message) async {
    if (_stateController.isClosed) return false;

    if (_currentState == SocketState.connected && _socket != null) {
      try {
        if (message is String || message is List<int>) {
          _socket!.add(message);
          return true;
        } else {
          throw ArgumentError('Message must be String or List<int>');
        }
      } catch (e) {
        wslog('Error sending message: $e');
        return false;
      }
    } else {
      // Not connected, try to wait for connection
      wslog('Socket not connected, buffering message...');

      try {
        // Create a completer that completes when state becomes connected
        final completer = Completer<bool>();

        final subscription = onStateChange.listen((state) {
          if (state == SocketState.connected) {
            completer.complete(true);
          }
        });

        // Wait with timeout
        final isConnected = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );

        await subscription.cancel();

        if (isConnected) {
          // Reconnected! Send now.
          if (_socket != null) {
            if (message is String || message is List<int>) {
              _socket!.add(message);
              return true;
            }
          }
        } else {
          wslog('Message dropped: Connection timeout (5s)');
        }
      } catch (e) {
        wslog('Error buffering message: $e');
      }
      return false;
    }
  }

  /// Start the heartbeat timer if configured.
  void _startHeartbeat() {
    if (heartbeat == null) return;
    _stopHeartbeat();

    wslog('Starting heartbeat with interval ${heartbeat!.interval.inSeconds}s');
    _heartbeatTimer = Timer.periodic(heartbeat!.interval, (_) {
      _sendHeartbeat();
    });
  }

  /// Stop the heartbeat timers.
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;
  }

  /// Send a heartbeat message and start timeout timer.
  void _sendHeartbeat() {
    if (_currentState != SocketState.connected || _socket == null) {
      _stopHeartbeat();
      return;
    }

    try {
      wslog('Sending heartbeat...');
      _socket!.add(heartbeat!.request);

      // Start timeout timer
      _heartbeatTimeoutTimer?.cancel();
      _heartbeatTimeoutTimer = Timer(heartbeat!.timeout, () async {
        wslog('Heartbeat timeout! Disconnecting...');
        _isExpectedDisconnect = false;
        _handleDisconnect();
      });
    } catch (e) {
      wslog('Error sending heartbeat: $e');
      // If send fails, let the regular error handling take over,
      // or maybe trigger disconnect?
    }
  }

  /// Check if the message is a heartbeat response.
  /// Returns true if it is (and should be consumed), false otherwise.
  bool _handleHeartbeatResponse(dynamic data) {
    if (heartbeat == null) return false;

    bool isHeartbeat = false;
    if (heartbeat!.validator != null) {
      isHeartbeat = heartbeat!.validator!(data);
    } else {
      // If no validator, any message resets the timer (keep-alive)
      isHeartbeat = true;
    }

    if (isHeartbeat) {
      wslog('Heartbeat response received.');
      _heartbeatTimeoutTimer?.cancel();
      _heartbeatTimeoutTimer = null;
      return heartbeat!.interceptResponse;
    }

    return false;
  }

  /// Dispose the controller when no longer needed.
  void dispose() {
    wslog('Disposing OkWsClient...');
    disconnect();
    try {
      _stateController.close();
      _messageController.close();
    } catch (e) {
      wslog('Error disposing controllers: $e');
    }
  }
}
