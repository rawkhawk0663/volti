import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Hat Volti ein eigenes Fenster mit eigenen Fensterknöpfen? (Am Computer.)
/// Unter Windows ist die Titelleiste ausgeblendet ([hideNativeTitleBar]).
bool get hasWindowButtons => Platform.isWindows || Platform.isLinux;

/// Titelleiste von Windows ausblenden (der Rand zum Vergrössern bleibt).
Future<void> hideNativeTitleBar() async {
  if (!Platform.isWindows) return;
  try {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  } catch (_) {
    // Dann bleibt eben die normale Titelleiste.
  }
}

/// Schliessen, Minimieren, Maximieren – als drei runde Punkte wie bei macOS
/// (Wunsch des Besitzers). Beim Darüberfahren mit der Maus erscheinen die
/// Zeichen darin.
class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key, this.padding = const EdgeInsets.only(left: 6, right: 4)});
  final EdgeInsets padding;

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> {
  bool _hover = false;

  static const _red = Color(0xFFFF5F57), _yellow = Color(0xFFFEBC2E), _green = Color(0xFF28C840);

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      } else if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!hasWindowButtons) return const SizedBox.shrink();
    return ExcludeFocus(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Padding(
          padding: widget.padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(color: _red, glyph: _Glyph.close, hover: _hover, tooltip: 'Schliessen', onTap: windowManager.close),
              _Dot(
                color: _yellow,
                glyph: _Glyph.minimize,
                hover: _hover,
                tooltip: 'Minimieren',
                onTap: windowManager.minimize,
              ),
              _Dot(color: _green, glyph: _Glyph.maximize, hover: _hover, tooltip: 'Maximieren', onTap: _toggleMaximize),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Glyph { close, minimize, maximize }

class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.glyph,
    required this.hover,
    required this.tooltip,
    required this.onTap,
  });
  final Color color;
  final _Glyph glyph;
  final bool hover;
  final String tooltip;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Grosse Trefferfläche für Finger und Stift, kleiner sichtbarer Punkt.
        child: SizedBox(
          width: 26,
          height: 32,
          child: Center(
            child: CustomPaint(size: const Size(14, 14), painter: _DotPainter(color, hover ? glyph : null)),
          ),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color, this.glyph);
  final Color color;
  final _Glyph? glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = color);
    // Feiner, dunklerer Rand wie bei macOS.
    canvas.drawCircle(
      c,
      r - 0.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Color.lerp(color, Colors.black, 0.18)!,
    );
    final g = glyph;
    if (g == null) return;
    final p = Paint()
      ..color = const Color(0x99000000)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final d = r * 0.42;
    switch (g) {
      case _Glyph.close:
        canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), p);
        canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), p);
      case _Glyph.minimize:
        canvas.drawLine(c + Offset(-d * 1.2, 0), c + Offset(d * 1.2, 0), p);
      case _Glyph.maximize:
        canvas.drawLine(c + Offset(-d * 1.2, 0), c + Offset(d * 1.2, 0), p);
        canvas.drawLine(c + Offset(0, -d * 1.2), c + Offset(0, d * 1.2), p);
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color || old.glyph != glyph;
}

/// Fläche, an der man das Fenster verschiebt (ohne Titelleiste nötig);
/// doppelt antippen maximiert. Auf Tablets ohne Fenster: nur [child].
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child, this.doubleTapMaximizes = true, this.mouseOnly = false});
  final Widget child;

  /// Nur mit der Maus (z. B. an der Leiste der Notenansicht, wo ein Wischen
  /// mit dem Finger das Fenster sonst aus Versehen verschieben würde).
  final bool mouseOnly;

  /// Doppelt antippen = maximieren. Aus, wo darin auch angetippt wird
  /// (sonst würde jedes einfache Antippen kurz verzögert).
  final bool doubleTapMaximizes;

  @override
  Widget build(BuildContext context) {
    if (!hasWindowButtons) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      supportedDevices: mouseOnly ? const {PointerDeviceKind.mouse} : null,
      onPanStart: (_) async {
        try {
          if (await windowManager.isFullScreen()) return;
          await windowManager.startDragging();
        } catch (_) {}
      },
      onDoubleTap: doubleTapMaximizes
          ? () async {
              try {
                await (await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize());
              } catch (_) {}
            }
          : null,
      child: child,
    );
  }
}
