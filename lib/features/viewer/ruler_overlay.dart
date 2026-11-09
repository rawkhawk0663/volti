import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'tool_controller.dart';

/// Das Lineal: ein halbdurchsichtiger Streifen über den Noten.
///
/// * **Nur mit den Fingern** (oder der Maus) bewegen: ein Finger auf dem
///   Lineal verschiebt es, ein zweiter Finger dazu dreht es – wie ein echtes
///   Lineal unter zwei Fingern. Bei 0° und 90° rastet es leicht ein.
///   Am Computer: mit der Maus ziehen, mit dem Mausrad drehen.
/// * Der Stift bewegt das Lineal nie, er zeichnet daran entlang (das erledigt
///   die Stift-Ebene, auch wenn man auf dem Lineal selbst ansetzt).
///
/// Technisch: Eine durchlässige Fläche über allem beobachtet die Finger,
/// ohne etwas zu blockieren. Das Lineal selbst nimmt keine Berührungen an.
class RulerOverlay extends StatefulWidget {
  const RulerOverlay({super.key, required this.tools});
  final ToolController tools;

  @override
  State<RulerOverlay> createState() => _RulerOverlayState();
}

class _RulerOverlayState extends State<RulerOverlay> {
  ToolController get tools => widget.tools;

  /// Finger bzw. Maus, die das Lineal halten, mit ihrer letzten Position.
  final Map<int, Offset> _held = {};

  /// Ungerasteter Winkel (damit das Einrasten nicht "klebt").
  double _rawAngle = 0;

  /// Halten Finger das Lineal (und nicht die Maus)? Nur dann dreht ein zweiter.
  bool _byFinger = false;
  bool _showAngle = false;

  static const _thick = ToolController.rulerThickness;
  double get _len => tools.rulerLength;

  /// Rastet nahe 0°, 90°, 180° und 270° ein.
  static double _snap(double a) {
    const step = math.pi / 2, tolerance = 2.5 * math.pi / 180;
    final nearest = (a / step).round() * step;
    return (a - nearest).abs() < tolerance ? nearest : a;
  }

  /// Liegt der Punkt (Bildschirm-Koordinaten) auf dem Lineal (mit etwas Rand)?
  bool _onRuler(Offset global) {
    final c = tools.rulerCenter;
    if (c == null) return false;
    final a = tools.rulerAngle;
    final rel = global - c;
    final along = rel.dx * math.cos(a) + rel.dy * math.sin(a);
    final across = -rel.dx * math.sin(a) + rel.dy * math.cos(a);
    return along.abs() <= _len / 2 + 16 && across.abs() <= _thick / 2 + 16;
  }

  void _down(PointerDownEvent e) {
    final finger = e.kind == PointerDeviceKind.touch;
    final mouse = e.kind == PointerDeviceKind.mouse && e.buttons == kPrimaryMouseButton;
    if (!finger && !mouse) return;
    // Erster Finger muss auf dem Lineal liegen, ein zweiter darf irgendwo sein.
    final joins = finger && _held.length == 1 && _byFinger;
    if (!_onRuler(e.position) && !joins) return;
    if (_held.length >= 2) return;
    if (_held.isEmpty) {
      _rawAngle = tools.rulerAngle;
      _byFinger = finger;
    }
    _held[e.pointer] = e.position;
    tools.grabRuler(e.pointer);
    if (!_showAngle) setState(() => _showAngle = true);
  }

  void _move(PointerMoveEvent e) {
    final prev = _held[e.pointer];
    if (prev == null) return;
    final center = tools.rulerCenter!;
    if (_held.length == 1) {
      _held[e.pointer] = e.position;
      tools.moveRuler(center + (e.position - prev), tools.rulerAngle);
      return;
    }
    // Zwei Finger: Drehung und Verschiebung aus der Änderung seit dem letzten
    // Ereignis (Schritt für Schritt – so folgt das Lineal den Fingern genau).
    final other = _held.entries.firstWhere((x) => x.key != e.pointer).value;
    final before = prev - other, after = e.position - other;
    var turn = math.atan2(after.dy, after.dx) - math.atan2(before.dy, before.dx);
    if (turn > math.pi) turn -= 2 * math.pi;
    if (turn < -math.pi) turn += 2 * math.pi;
    _rawAngle += turn;
    // Ein Finger bewegt sich, der andere hält: Das Lineal dreht sich um den
    // haltenden Finger. (Bewegen sich beide, kommen ihre Ereignisse einzeln
    // nacheinander – zusammen ergibt das die ganze Bewegung.)
    final rel = center - other;
    final rotated = Offset(
      rel.dx * math.cos(turn) - rel.dy * math.sin(turn),
      rel.dx * math.sin(turn) + rel.dy * math.cos(turn),
    );
    _held[e.pointer] = e.position;
    tools.moveRuler(other + rotated, _snap(_rawAngle));
  }

  void _up(PointerEvent e) {
    if (_held.remove(e.pointer) == null) return;
    tools.releaseRuler(e.pointer);
    if (_held.isEmpty) {
      setState(() => _showAngle = false);
    } else {
      _rawAngle = tools.rulerAngle;
    }
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_onRuler(e.position)) return;
    final step = (e.scrollDelta.dy > 0 ? 1 : -1) * 2 * math.pi / 180;
    _rawAngle = tools.rulerAngle + step;
    tools.moveRuler(tools.rulerCenter!, _snap(_rawAngle));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        // Lang genug, um in jeder Drehung und von jeder Stelle aus über den
        // ganzen Bildschirm zu reichen.
        tools.rulerLength = 2 * screen.longestSide * math.sqrt2;
        final box = context.findRenderObject() as RenderBox?;
        // Mitte in Bildschirm-Koordinaten (die Stift-Ebene rechnet damit).
        tools.rulerCenter ??= box != null && box.hasSize
            ? box.localToGlobal(screen.center(Offset.zero))
            : screen.center(Offset.zero);
        return Stack(
          children: [
            // Beobachtet Finger und Maus, ohne etwas darunter zu blockieren.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                onPointerSignal: _wheel,
              ),
            ),
            ValueListenableBuilder<int>(
              valueListenable: tools.rulerChanged,
              builder: (context, _, _) {
                final local = box != null && box.hasSize ? box.globalToLocal(tools.rulerCenter!) : tools.rulerCenter!;
                return Positioned(
                  left: local.dx - _len / 2,
                  top: local.dy - _thick / 2,
                  width: _len,
                  height: _thick,
                  child: IgnorePointer(
                    child: Transform.rotate(
                      angle: tools.rulerAngle,
                      child: CustomPaint(
                        painter: _RulerPainter(showAngle: _showAngle, angle: tools.rulerAngle),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.showAngle, required this.angle});
  final bool showAngle;
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(r, Paint()..color = const Color(0x553BA796));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xCC1A8070),
    );
    // Skala an beiden Kanten
    final tick = Paint()
      ..color = const Color(0xAA1A8070)
      ..strokeWidth = 1;
    for (var x = 10.0; x < size.width - 4; x += 10) {
      final long = ((x - 10) / 10) % 5 == 0;
      final l = long ? 12.0 : 6.0;
      canvas.drawLine(Offset(x, 0), Offset(x, l), tick);
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - l), tick);
    }
    if (showAngle) {
      var deg = (angle * 180 / math.pi) % 180;
      if (deg < 0) deg += 180;
      final tp = TextPainter(
        text: TextSpan(
          text: '${deg.round()}°',
          style: const TextStyle(color: Color(0xFF0E4F45), fontSize: 15, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, size.center(Offset.zero) - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.showAngle != showAngle || old.angle != angle;
}
