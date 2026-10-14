import 'package:flutter/foundation.dart';

class ReadoraSelectorManager {
  static VoidCallback? _activeCloseCallback;

  static void registerOpen(VoidCallback closeCallback) {
    if (_activeCloseCallback != null && _activeCloseCallback != closeCallback) {
      try {
        _activeCloseCallback!();
      } catch (_) {}
    }
    _activeCloseCallback = closeCallback;
  }

  static void unregister(VoidCallback closeCallback) {
    if (_activeCloseCallback == closeCallback) {
      _activeCloseCallback = null;
    }
  }
}
