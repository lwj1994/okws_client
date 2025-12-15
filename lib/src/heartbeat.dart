/// Configuration for application-level heartbeat.
class OkWsHeartbeat {
  /// The interval between sending heartbeat messages.
  final Duration interval;

  /// The timeout to wait for a response before considering the connection dead.
  final Duration timeout;

  /// The message to send as a heartbeat (String or `List<int>`).
  final dynamic request;

  /// Optional validator to identify the heartbeat response.
  /// If provided, only messages returning true will reset the heartbeat timer.
  /// If not provided, ANY message received from the server will reset the timer (keep-alive mode).
  final bool Function(dynamic message)? validator;

  /// Whether to prevent the heartbeat response from being emitted to `OkWsClient.onReceive`.
  /// Default is true (consume the pong message).
  final bool interceptResponse;

  const OkWsHeartbeat({
    this.interval = const Duration(seconds: 15),
    this.timeout = const Duration(seconds: 10),
    required this.request,
    this.validator,
    this.interceptResponse = true,
  });
}
