import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/audio/pitch.dart';
import 'package:volti/core/library/page_setup.dart';
import 'package:volti/core/pdf/paper.dart';
import 'package:volti/core/pdf/paper_pdf.dart';

/// Abtastwerte aus einer WAV-Datei (16 Bit, mono) als Float32.
Float32List samplesOf(Uint8List wav, {int start = 0, int count = 2048}) {
  final bd = ByteData.sublistView(wav);
  return Float32List.fromList([
    for (var i = 0; i < count; i++) bd.getInt16(44 + (start + i) * 2, Endian.little) / 32768,
  ]);
}

Float32List sine(double hz, int rate, {int n = 2048, double amp = 0.3}) =>
    Float32List.fromList([for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * hz * i / rate)]);

double cents(double a, double b) => 1200 * math.log(a / b) / math.ln2;

void main() {
  group('Stimmgerät', () {
    test('erkennt Töne genau (auf 1 Cent)', () {
      for (final hz in [82.41, 110.0, 146.83, 196.0, 246.94, 329.63, 440.0, 880.0, 1200.0]) {
        final found = detectPitch(sine(hz, 22050), 22050);
        expect(found, isNotNull, reason: '$hz Hz');
        expect(cents(found!, hz).abs(), lessThan(0.5), reason: '$hz Hz → $found');
      }
    });

    test('Ton mit starken Obertönen (wie eine Saite) gibt den Grundton', () {
      const hz = 110.0, rate = 22050;
      final x = Float32List.fromList([
        for (var i = 0; i < 2048; i++)
          0.2 * math.sin(2 * math.pi * hz * i / rate) +
              0.3 * math.sin(2 * math.pi * 2 * hz * i / rate) +
              0.2 * math.sin(2 * math.pi * 3 * hz * i / rate),
      ]);
      final found = detectPitch(x, rate)!;
      expect(cents(found, hz).abs(), lessThan(2));
    });

    test('Stille und Rauschen ergeben nichts', () {
      expect(detectPitch(Float32List(2048), 22050), isNull);
      final r = math.Random(1);
      final noise = Float32List.fromList([for (var i = 0; i < 2048; i++) (r.nextDouble() * 2 - 1) * 0.3]);
      expect(detectPitch(noise, 22050), isNull);
    });

    test('Notenname und Abweichung', () {
      final a = nearestNote(440);
      expect(a.midi, 69);
      expect(a.cents.abs(), lessThan(0.01));
      final sharp = nearestNote(445);
      expect(sharp.midi, 69);
      expect(sharp.cents, closeTo(19.6, 0.2));
      expect(nearestNote(432, a4: 432).cents.abs(), lessThan(0.01));
      expect(noteName(69, english: false), 'A');
      expect(noteName(71, english: false), 'H');
      expect(noteName(70, english: false), 'B');
      expect(noteName(71, english: true), 'B');
      expect(noteName(70, english: true), 'B♭');
      expect(noteOctave(40), 2); // tiefes E der Gitarre
      expect(noteFrequency(40), closeTo(82.41, 0.01));
    });

    test('Glättung: Median, neuer Ton gilt sofort', () {
      final s = PitchSmoother(size: 5);
      for (final v in [440.0, 441.0, 439.0, 440.5]) {
        s.add(v);
      }
      expect(s.add(440.2), closeTo(440.2, 0.6));
      // Anderer Ton (eine Quinte höher): sofort übernommen.
      expect(s.add(660), 660);
      expect(s.add(null), isNull);
    });
  });

  group('Stimmton', () {
    test('weicher Ton ist genau gestimmt und als Schleife nahtlos', () {
      for (final midi in [40, 57, 69, 76]) {
        final hz = noteFrequency(midi);
        final wav = buildPipeTone(hz, PipeSound.soft);
        final n = (wav.length - 44) ~/ 2;
        // Erkannt mit derselben Tonerkennung (44,1 kHz).
        final found = detectPitch(samplesOf(wav, count: 4096), 44100)!;
        expect(cents(found, hz).abs(), lessThan(1), reason: 'midi $midi');
        // Nahtlos: Ende passt zum Anfang (kein Sprung).
        final bd = ByteData.sublistView(wav);
        final first = bd.getInt16(44, Endian.little), last = bd.getInt16(44 + (n - 1) * 2, Endian.little);
        final second = bd.getInt16(46, Endian.little);
        expect((first - last).abs(), lessThanOrEqualTo((second - first).abs() * 2 + 50));
      }
    });

    test('gezupfte Saite klingt im richtigen Ton', () {
      for (final midi in [40, 45, 50, 55, 59, 64]) {
        final hz = noteFrequency(midi);
        final wav = buildPipeTone(hz, PipeSound.guitar);
        final found = detectPitch(samplesOf(wav, start: 8000, count: 4096), 44100)!;
        expect(cents(found, hz).abs(), lessThan(1), reason: 'midi $midi: $found statt $hz');
      }
    });
  });

  group('Vorlagen', () {
    test('Notenlinien, Tabulatur und Kästchen füllen die Seite', () {
      const a4 = Size(595, 842);
      final staff = paperLayout(Paper.staff, a4);
      // 5 Linien pro System plus zwei Randstriche.
      expect(staff.lines.length % 7, 0);
      expect(staff.lines.length ~/ 7, greaterThanOrEqualTo(10));
      final tab = paperLayout(Paper.tab, a4);
      expect(tab.labels.length, (tab.lines.length ~/ 8) * 3); // „T“, „A“, „B“ pro System
      for (final p in Paper.values) {
        for (final l in paperLayout(p, a4).lines) {
          expect(l.a.dy, inInclusiveRange(0, a4.height));
          expect(l.b.dy, inInclusiveRange(0, a4.height));
          expect(l.a.dx, inInclusiveRange(0, a4.width));
        }
      }
      expect(paperLayout(Paper.blank, a4).lines, isEmpty);
      expect(Paper.fromName('gibt-es-nicht'), Paper.blank);
    });

    test('leere Seite merkt sich ihre Vorlage (auch nach dem Speichern)', () {
      final (setup, page) = PageSetup.empty.withBlankAt(1, 3, paper: Paper.tab.name);
      expect(setup.paperOf(page), 'tab');
      final again = PageSetup.fromJson(setup.toJson());
      expect(again.paperOf(page), 'tab');
      expect(again.pages(3), [1, page, 2, 3]);
      // Ändern der Reihenfolge oder des Zuschnitts behält die Vorlage.
      expect(again.withOrder([page, 1]).paperOf(page), 'tab');
      expect(again.withCrop(1, const PageCrop(left: 0.1)).paperOf(page), 'tab');
      // Ohne Vorlage: weiss.
      final (plain, p2) = again.withBlankAt(0, 3);
      expect(plain.paperOf(p2), isNull);
      expect(plain.paperOf(page), 'tab');
    });

    test('Notizblatt als PDF', () async {
      for (final p in Paper.values) {
        final bytes = await buildPaperPdf(p, title: 'Test');
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });
  });
}
