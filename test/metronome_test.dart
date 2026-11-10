import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:volti/features/viewer/metronome.dart';

void main() {
  test('Ein Takt hat genau die richtige Länge (das Tempo stimmt)', () {
    for (final (bpm, beats) in [(60, 4), (120, 3), (97, 4), (200, 6)]) {
      final wav = Metronome.buildBar(bpm, beats, ClickSound.soft);
      final bytes = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      final dataBytes = bytes.getUint32(40, Endian.little);
      final samples = dataBytes ~/ 2;
      expect(samples, (44100 * 60 / bpm).round() * beats);
    }
  });

  test('Die Eins klingt anders als die übrigen Schläge', () {
    final wav = ByteData.sublistView(Metronome.buildBar(60, 2, ClickSound.wood));
    int peak(int from) {
      var m = 0;
      for (var i = from; i < from + 2000; i++) {
        final v = wav.getInt16(44 + i * 2, Endian.little).abs();
        if (v > m) m = v;
      }
      return m;
    }

    expect(peak(0), greaterThan(1000));
    expect(peak(44100), greaterThan(1000));
    // Verschiedene Tonhöhe → verschiedene Wellenform am Anfang.
    final a = [for (var i = 100; i < 140; i++) wav.getInt16(44 + i * 2, Endian.little)];
    final b = [for (var i = 100; i < 140; i++) wav.getInt16(44 + (44100 + i) * 2, Endian.little)];
    expect(a, isNot(b));
  });

  test('Antippen ergibt das Tempo', () async {
    final m = Metronome();
    m.bpm = 60;
    // Vier Tipps im Abstand von 0,5 s → 120 BPM.
    for (var i = 0; i < 4; i++) {
      m.tap();
      if (i < 3) await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(m.bpm, inInclusiveRange(115, 125));
    m.dispose();
  });
}
