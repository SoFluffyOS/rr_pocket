class LogService {
  final void Function(String) _log;

  LogService(this._log);

  void call(String message) {
    _log(message);
  }

  void info(String message) {
    _log('[INFO] $message');
  }

  void error(String message, [Object? e, StackTrace? st]) {
    if (e != null) {
      if (st != null) {
        _log('[ERROR] $message: $e\n$st');
      } else {
        _log('[ERROR] $message: $e');
      }
    } else {
      _log('[ERROR] $message');
    }
  }

  void warn(String message) {
    _log('[WARN] $message');
  }
}
