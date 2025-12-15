/// Callback type for custom logging.
typedef LogAdapter = void Function(String message);

bool _enableLog = false;
LogAdapter? _logAdapter;

/// Initialize logging for the library.
/// [enable]: Whether to enable logging.
/// [adapter]: Optional custom logger. If provided, logs will be sent to this function instead of print.
void initOkWsLog({bool enable = true, LogAdapter? adapter}) {
  _enableLog = enable;
  _logAdapter = adapter;
}

void wslog(Object? message) {
  if (_enableLog) {
    final logMessage = '[OkWs] ${DateTime.now()} $message';
    if (_logAdapter != null) {
      _logAdapter!(logMessage);
    } else {
      print(logMessage);
    }
  }
}
