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

bool _wasMaximized = false;

/// Schaltet das Vollbild ein oder aus: am Computer verschwinden Titel- und
/// Taskleiste, auf Android die Statusleiste.
///
/// Unter Windows lässt die Vollbild-Funktion bei einem *maximierten* Fenster
/// die Titelleiste stehen. Deshalb wird das Fenster vorher auf normale Grösse
/// gesetzt und beim Verlassen wieder maximiert.
Future<void> setAppFullscreen(bool on) async {
  try {
    if (_isDesktop) {
      if (on) {
        if (await windowManager.isFullScreen()) return;
        _wasMaximized = await windowManager.isMaximized();
        if (_wasMaximized) await windowManager.unmaximize();
        await windowManager.setFullScreen(true);
      } else {
        if (!await windowManager.isFullScreen()) return;
        await windowManager.setFullScreen(false);
        if (_wasMaximized) await windowManager.maximize();
        _wasMaximized = false;
      }
    } else {
      await SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  } catch (_) {
    // Vollbild ist eine Annehmlichkeit – Fehler hier dürfen nichts blockieren.
  }
}
