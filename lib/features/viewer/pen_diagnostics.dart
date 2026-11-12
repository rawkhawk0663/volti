import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'ink_layer.dart';
import 'perf_meter.dart';
import '../../app/l10n.dart';

/// Sammelt Daten über die letzten Zeigereingaben (Stift, Finger, Maus).
///
/// Dient dem Stift-Test auf dem Surface: Damit sehen wir, ob Windows
/// Druckstärke, Radierer und Seitentaste korrekt an Volti weitergibt.
class PenDiagnostics extends ChangeNotifier {
  PointerEvent? last;
  double maxPressureSeen = 0;
  final List<int> _moveTimes = [];

  void record(PointerEvent e) {
    last = e;
    if (e is PointerDownEvent) maxPressureSeen = 0;
    maxPressureSeen = e.pressure > maxPressureSeen ? e.pressure : maxPressureSeen;
    if (e is PointerMoveEvent) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _moveTimes.add(now);
      _moveTimes.removeWhere((t) => now - t > 1000);
    }
    notifyListeners();
  }

  /// Wie viele Bewegungs-Ereignisse pro Sekunde ankommen (mehr = flüssiger).
  int get eventsPerSecond => _moveTimes.length;
}

String _kindName(PointerDeviceKind k) => switch (k) {
  PointerDeviceKind.stylus => tr('Stift', 'Pen'),
  PointerDeviceKind.invertedStylus => tr('Stift (Radierer-Ende)', 'Pen (eraser end)'),
  PointerDeviceKind.touch => tr('Finger', 'Finger'),
  PointerDeviceKind.mouse => tr('Maus', 'Mouse'),
  PointerDeviceKind.trackpad => tr('Trackpad', 'Trackpad'),
  _ => k.name,
};

class PenDiagnosticsPanel extends StatelessWidget {
  const PenDiagnosticsPanel({super.key, required this.diagnostics});
  final PenDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final perf = PerfMeter.instance..start();
    return ListenableBuilder(
      listenable: Listenable.merge([diagnostics, perf.latencyMs, perf.frames]),
      builder: (context, _) {
        final e = diagnostics.last;
        final rows = <(String, String)>[
          if (e == null)
            ('', tr('Berühre die Seite mit Stift, Finger oder Maus.', 'Touch the page with pen, finger or mouse.')),
          if (e != null) ...[
            (tr('Gerät', 'Device'), _kindName(e.kind)),
            (
              tr('Druck (roh)', 'Pressure (raw)'),
              '${e.pressure.toStringAsFixed(3)}  [${e.pressureMin}–${e.pressureMax}]',
            ),
            (tr('Druck (0–1)', 'Pressure (0–1)'), normalizedPressure(e).toStringAsFixed(2)),
            (tr('Max. Druck', 'Max. pressure'), diagnostics.maxPressureSeen.toStringAsFixed(3)),
            (tr('Tasten', 'Buttons'), '0b${e.buttons.toRadixString(2)}${isEraserEvent(e) ? '  → radiert' : ''}'),
            (tr('Neigung', 'Tilt'), '${(e.tilt * 57.2958).toStringAsFixed(0)}°'),
            ('Ereignisse/s', '${diagnostics.eventsPerSecond}'),
            (
              tr('Verzögerung', 'Latency'),
              perf.latencyMs.value == null
                  ? tr('mit dem Stift zeichnen', 'draw with the pen')
                  : '${perf.latencyMs.value!.toStringAsFixed(0)} ms',
            ),
            (tr('Bilder', 'Frames'), perf.frames.value),
          ],
        ];
        return Card(
          elevation: 0,
          color: Colors.black.withValues(alpha: 0.82),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Stift-Test', 'Pen test'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  for (final (k, v) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (k.isNotEmpty)
                            SizedBox(
                              width: 100,
                              child: Text(k, style: const TextStyle(color: Colors.white70)),
                            ),
                          Text(v),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
