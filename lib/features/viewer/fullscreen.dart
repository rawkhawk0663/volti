import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Einmal beim Start aufrufen (nötig für das Vollbild am Computer).
Future<void> initFullscreenSupport() async {
  if (!_isDesktop) return;
  try {
    await windowManager.ensureInitialized();
  } catch (_) {
    // Ohne Fenster-Unterstützung (z. B. in Tests) geht es auch ohne Vollbild.
  }
}

/// Schaltet das Vollbild ein oder aus: am Computer verschwinden Titel- und
/// Taskleiste, auf Android die Statusleiste.
Future<void> setAppFullscreen(bool on) async {
  try {
    if (_isDesktop) {
      await windowManager.setFullScreen(on);
    } else {
      await SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  } catch (_) {
    // Vollbild ist eine Annehmlichkeit – Fehler hier dürfen nichts blockieren.
  }
}
