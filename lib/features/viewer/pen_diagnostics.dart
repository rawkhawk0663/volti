import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'ink_layer.dart';

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
  PointerDeviceKind.stylus => 'Stift',
  PointerDeviceKind.invertedStylus => 'Stift (Radierer-Ende)',
  PointerDeviceKind.touch => 'Finger',
  PointerDeviceKind.mouse => 'Maus',
  PointerDeviceKind.trackpad => 'Trackpad',
  _ => k.name,
};

class PenDiagnosticsPanel extends StatelessWidget {
  const PenDiagnosticsPanel({super.key, required this.diagnostics});
  final PenDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: diagnostics,
      builder: (context, _) {
        final e = diagnostics.last;
        final rows = <(String, String)>[
          if (e == null) ('', 'Berühre die Seite mit Stift, Finger oder Maus.'),
          if (e != null) ...[
            ('Gerät', _kindName(e.kind)),
            ('Druck (roh)', '${e.pressure.toStringAsFixed(3)}  [${e.pressureMin}–${e.pressureMax}]'),
            ('Druck (0–1)', normalizedPressure(e).toStringAsFixed(2)),
            ('Max. Druck', diagnostics.maxPressureSeen.toStringAsFixed(3)),
            ('Tasten', '0b${e.buttons.toRadixString(2)}${isEraserEvent(e) ? '  → radiert' : ''}'),
            ('Neigung', '${(e.tilt * 57.2958).toStringAsFixed(0)}°'),
            ('Ereignisse/s', '${diagnostics.eventsPerSecond}'),
          ],
        ];
        return Card(
          color: Colors.black.withValues(alpha: 0.82),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Stift-Test', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
