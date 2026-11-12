import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Einmal beim Start aufrufen (nötig für das Vollbild am Computer).
Future<void> initFullscreenSupport() async {
  if (!_isDesktop) return;
  try {
    await windowManager.ensureInitialized();
    windowManager.addListener(_LeaveOnSwitch());
  } catch (_) {
    // Ohne Fenster-Unterstützung (z. B. in Tests) geht es auch ohne Vollbild.
  }
}

bool _wasMaximized = false;

/// Ist Volti gerade im Vollbild? (Die Notenansicht passt ihr Symbol an.)
final appFullscreen = ValueNotifier<bool>(false);

/// Wechselt man zu einer anderen App (Alt+Tab, Taskleiste, Wischen vom Rand),
/// verlässt Volti das Vollbild. Beim Besitzer blieb Volti sonst hängen,
/// wenn er aus dem Vollbild weggewechselt hat.
class _LeaveOnSwitch with WindowListener {
  @override
  void onWindowBlur() => _leaveIfSwitchedAway();

  @override
  void onWindowMinimize() {
    if (appFullscreen.value) _leave();
  }

  @override
  void onWindowFocus() {
    // Zurück in Volti: ein vorher maximiertes Fenster wieder maximieren.
    if (!_maximizeOnReturn) return;
    _maximizeOnReturn = false;
    windowManager.maximize().catchError((_) {});
  }
}

/// Wann zuletzt ins Vollbild oder heraus geschaltet wurde.
DateTime _changedAt = DateTime(2000);

/// Beim Wegwechseln nicht sofort maximieren (das holt Volti unter Windows
/// wieder nach vorne), sondern erst, wenn man zurückkommt.
bool _maximizeOnReturn = false;

Future<void> _leaveIfSwitchedAway() async {
  if (!appFullscreen.value) return;
  // Beim Umschalten selbst meldet Windows manchmal kurz „nicht mehr vorne“.
  // Deshalb kurz warten und nachsehen, ob Volti wirklich nicht mehr vorne ist.
  await Future<void>.delayed(const Duration(milliseconds: 400));
  if (!appFullscreen.value) return;
  if (DateTime.now().difference(_changedAt) < const Duration(milliseconds: 1500)) return;
  try {
    if (await windowManager.isFocused()) return;
  } catch (_) {}
  await _leave();
}

Future<void> _leave() async {
  final maximize = _wasMaximized;
  _wasMaximized = false; // nicht jetzt maximieren, erst beim Zurückkommen
  await setAppFullscreen(false);
  _maximizeOnReturn = maximize;
}

/// Schaltet das Vollbild ein oder aus: am Computer verschwinden Titel- und
/// Taskleiste, auf Android die Statusleiste.
///
/// Unter Windows lässt die Vollbild-Funktion bei einem *maximierten* Fenster
/// die Titelleiste stehen. Deshalb wird das Fenster vorher auf normale Grösse
/// gesetzt und beim Verlassen wieder maximiert.
Future<void> setAppFullscreen(bool on) async {
  _changedAt = DateTime.now();
  _maximizeOnReturn = false;
  try {
    if (_isDesktop) {
      if (on) {
        if (await windowManager.isFullScreen()) {
          appFullscreen.value = true;
          return;
        }
        _wasMaximized = await windowManager.isMaximized();
        if (_wasMaximized) await windowManager.unmaximize();
        await windowManager.setFullScreen(true);
        appFullscreen.value = true;
      } else {
        appFullscreen.value = false;
        if (!await windowManager.isFullScreen()) return;
        await windowManager.setFullScreen(false);
        if (_wasMaximized) await windowManager.maximize();
        _wasMaximized = false;
      }
    } else {
      await SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
      appFullscreen.value = on;
    }
  } catch (_) {
    // Vollbild ist eine Annehmlichkeit – Fehler hier dürfen nichts blockieren.
  }
}
