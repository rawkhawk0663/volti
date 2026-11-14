import 'dart:io';

import 'package:flutter/services.dart';

/// Hält den Bildschirm wach, solange Noten offen sind (Wunsch des Besitzers:
/// beide Hände an der Gitarre, das Surface soll nicht abschalten oder sperren).
///
/// Windows: `SetThreadExecutionState` im Windows-Teil (`flutter_window.cpp`),
/// Android: `FLAG_KEEP_SCREEN_ON` (`MainActivity.kt`). Mitgezählt, damit
/// mehrere offene Notenansichten sich nicht gegenseitig ausschalten.
class KeepAwake {
  KeepAwake._();

  static const _channel = MethodChannel('volti/screen');
  static int _holders = 0;

  static Future<void> acquire() async {
    _holders++;
    if (_holders == 1) await _set(true);
  }

  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _set(false);
  }

  static Future<void> _set(bool on) async {
    if (!Platform.isWindows && !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('keepAwake', on);
    } catch (_) {
      // Ohne diese Möglichkeit läuft Volti normal weiter.
    }
  }
}
