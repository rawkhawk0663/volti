import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../app/l10n.dart';

/// Misst, wie flüssig Volti läuft – für den Stift-Test.
///
/// * **Verzögerung:** Zeit vom Stift-Ereignis bis zum Bild, in dem der Strich
///   gezeichnet wird.
/// * **Bildrate** und Zeit pro Bild (Aufbau / Malen).
class PerfMeter {
  PerfMeter._();
  static final instance = PerfMeter._();

  /// Geglättete Verzögerung in Millisekunden (null = noch nichts gemessen).
  final latencyMs = ValueNotifier<double?>(null);

  /// z. B. "58 Bilder/s · Aufbau 2.1 ms · Malen 4.3 ms"
  final frames = ValueNotifier<String>('–');

  bool _started = false;
  final List<FrameTiming> _recent = [];

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Aus dem Malen des entstehenden Strichs aufrufen (läuft im Bild-Takt).
  void recordStrokeFrame(Duration eventTimeStamp) {
    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final ms = (now - eventTimeStamp).inMicroseconds / 1000;
    if (ms < 0 || ms > 5000) return; // andere Uhr o. Ä. – ignorieren
    final prev = latencyMs.value;
    latencyMs.value = prev == null ? ms : prev * 0.85 + ms * 0.15;
  }

  void _onTimings(List<FrameTiming> timings) {
    _recent.addAll(timings);
    if (_recent.length > 120) _recent.removeRange(0, _recent.length - 120);
    if (_recent.length < 2) return;
    double avg(Duration Function(FrameTiming) f) =>
        _recent.map((t) => f(t).inMicroseconds).reduce((a, b) => a + b) / _recent.length / 1000;
    final span =
        _recent.last.timestampInMicroseconds(FramePhase.rasterFinish) -
        _recent.first.timestampInMicroseconds(FramePhase.vsyncStart);
    final fps = span > 0 ? (_recent.length - 1) / (span / 1e6) : 0;
    frames.value = tr(
      '${fps.toStringAsFixed(0)} Bilder/s · Aufbau ${avg((t) => t.buildDuration).toStringAsFixed(1)} ms · '
          'Malen ${avg((t) => t.rasterDuration).toStringAsFixed(1)} ms',
      '${fps.toStringAsFixed(0)} frames/s · build ${avg((t) => t.buildDuration).toStringAsFixed(1)} ms · '
          'raster ${avg((t) => t.rasterDuration).toStringAsFixed(1)} ms',
    );
  }
}
