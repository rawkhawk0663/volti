import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'tool_controller.dart';

/// Das Lineal: ein halbdurchsichtiger Streifen über den Noten.
///
/// * Mit Finger oder Maus verschieben, mit zwei Fingern drehen – oder am
///   runden Griff drehen. Bei 0°, 45°, 90° … rastet es ein.
/// * Mit dem Stift nahe an einer Kante zeichnen ergibt eine gerade Linie
///   (das erledigt die Stift-Ebene). Der Stift bewegt das Lineal daher nicht.
class RulerOverlay extends StatefulWidget {
  const RulerOverlay({super.key, required this.tools});
  final ToolController tools;

  @override
  State<RulerOverlay> createState() => _RulerOverlayState();
}

class _RulerOverlayState extends State<RulerOverlay> {
  ToolController get tools => widget.tools;
  double _startAngle = 0, _gestureAngle = 0;
  bool _showAngle = false;

  static const _len = ToolController.rulerLength, _thick = ToolController.rulerThickness;

  /// Rastet in der Nähe von Vielfachen von 45° ein.
  static double _snap(double a) {
    const step = math.pi / 4, tolerance = 3 * math.pi / 180;
    final nearest = (a / step).round() * step;
    return (a - nearest).abs() < tolerance ? nearest : a;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final box = context.findRenderObject() as RenderBox?;
        // Mitte in Bildschirm-Koordinaten (die Stift-Ebene rechnet damit).
        tools.rulerCenter ??= box != null && box.hasSize
            ? box.localToGlobal(screen.center(Offset.zero))
            : screen.center(Offset.zero);
        return ValueListenableBuilder<int>(
          valueListenable: tools.rulerChanged,
          builder: (context, _, _) {
            final local = box != null && box.hasSize ? box.globalToLocal(tools.rulerCenter!) : tools.rulerCenter!;
            final angle = tools.rulerAngle;
            final handle = local + Offset(math.cos(angle), math.sin(angle)) * (_len / 2 - 22);
            return Stack(
              children: [
                Positioned(
                  left: local.dx - _len / 2,
                  top: local.dy - _thick / 2,
                  width: _len,
                  height: _thick,
                  child: Transform.rotate(
                    angle: angle,
                    child: GestureDetector(
                      // Nur Finger und Maus bewegen das Lineal – der Stift zeichnet daran entlang.
                      supportedDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                      onScaleStart: (_) => setState(() {
                        _startAngle = tools.rulerAngle;
                        _gestureAngle = 0;
                        _showAngle = true;
                      }),
                      onScaleUpdate: (d) {
                        _gestureAngle = d.rotation;
                        tools.moveRuler(tools.rulerCenter! + d.focalPointDelta, _snap(_startAngle + _gestureAngle));
                      },
                      onScaleEnd: (_) => setState(() => _showAngle = false),
                      child: CustomPaint(
                        painter: _RulerPainter(showAngle: _showAngle, angle: angle),
                      ),
                    ),
                  ),
                ),
                // Griff zum Drehen mit einem Finger, der Maus oder dem Stift.
                Positioned(
                  left: handle.dx - 16,
                  top: handle.dy - 16,
                  width: 32,
                  height: 32,
                  child: GestureDetector(
                    onPanStart: (_) => setState(() => _showAngle = true),
                    onPanUpdate: (d) {
                      final center = box?.globalToLocal(tools.rulerCenter!) ?? tools.rulerCenter!;
                      final v = d.localPosition + Offset(handle.dx - 16, handle.dy - 16) - center;
                      tools.moveRuler(tools.rulerCenter!, _snap(math.atan2(v.dy, v.dx)));
                    },
                    onPanEnd: (_) => setState(() => _showAngle = false),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.rotate_right, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
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
