import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/tab_block.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/tab_keys.dart';
import 'package:volti/features/viewer/tab_layer.dart';
import 'package:volti/features/viewer/tab_paint.dart';
import 'package:volti/features/viewer/tab_session.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

TabBlock block(String id, {List<TabBeat> beats = const [], DateTime? at, bool deleted = false}) => TabBlock(
  id: id,
  page: 1,
  x: 0.1,
  y: 0.2,
  width: 0.8,
  gap: TabBlock.defaultGap,
  createdAt: DateTime.utc(2026, 1, 1),
  modifiedAt: at,
  beats: beats,
  deleted: deleted,
);

void main() {
  group('Schreiben (ohne Anzeige)', () {
    test('Ziffern: einzeln, rasch zweistellig, über 24 neu', () {
      final e = TabEditor(const []);
      final t0 = DateTime(2026);
      e.digit(3, now: t0);
      expect(e.beats.single.frets, {0: 3});
      e.digit(1, now: t0.add(const Duration(seconds: 2)));
      e.digit(2, now: t0.add(const Duration(seconds: 2, milliseconds: 300)));
      expect(e.beats.single.frets, {0: 12}, reason: '1 und rasch 2 = 12');
      e.digit(3, now: t0.add(const Duration(seconds: 5)));
      e.digit(0, now: t0.add(const Duration(seconds: 5, milliseconds: 200)));
      expect(e.beats.single.frets, {0: 0}, reason: '30 gibt es nicht: die 0 gilt neu');
      e.digit(1, now: t0.add(const Duration(seconds: 9)));
      e.digit(5, now: t0.add(const Duration(seconds: 11)));
      expect(e.beats.single.frets, {0: 5}, reason: 'zu langsam: zwei einzelne Ziffern');
    });

    test('Akkord, Notenwert, Pause, Taktstrich, Löschen, Einfügen', () {
      final e = TabEditor(const []);
      e.setFret(3);
      e.moveString(5);
      e.setFret(0);
      expect(e.beats.single.frets, {0: 3, 5: 0});
      e.setValue(8);
      e.toggleDot();
      expect(e.beats.single.value, 8);
      expect(e.beats.single.dotted, isTrue);
      // Rechts vom letzten Schlag: neuer Schlag mit gleichem Notenwert
      e.move(1);
      expect(e.beat, 1);
      e.setFret(2);
      expect(e.beats.length, 2);
      expect(e.beats[1].value, 8);
      e.bar();
      expect(e.beats[2].bar, isTrue);
      expect(e.beat, 3);
      e.bar();
      expect(e.beats.where((b) => b.bar).length, 1, reason: 'kein doppelter Taktstrich');
      e.rest();
      expect(e.beats[3].isRest, isTrue);
      e.shorter();
      expect(e.beats[3].value, 16);
      e.shorter(-2);
      expect(e.beats[3].value, 4);
      e.move(-3);
      e.insertBeat();
      expect(e.beats.length, 5);
      expect(e.beats[0].isRest, isTrue, reason: "vor dem Cursor (Schlag 0) eingefügt");
      e.deleteBeat();
      expect(e.beats.length, 4);
      e.moveString(-10);
      expect(e.string, 0);
      e.beat = 0;
      e.clearNote();
      expect(e.beats[0].frets, {5: 0});
    });

    test('Speichern und Lesen', () {
      final b = block(
        'a',
        beats: const [
          TabBeat(frets: {0: 3, 5: 12}, value: 8, dotted: true),
          TabBeat.bar(),
          TabBeat(value: 2),
        ],
      ).copyWith(background: 0x99FFE066);
      final back = TabBlock.fromJson(b.toJson());
      expect(back.beats, b.beats);
      expect(back.background, 0x99FFE066);
      expect(back.gap, b.gap);
      final plain = TabBlock.fromJson(block('b').toJson());
      expect(plain.background, TabBlock.noBackground);
    });

    test('Balken: Achtel und kürzer innerhalb einer Viertel, Pause und Taktstrich trennen', () {
      final groups = beamGroups(const [
        TabBeat(frets: {0: 1}, value: 8),
        TabBeat(frets: {0: 1}, value: 8),
        TabBeat(frets: {0: 1}, value: 16),
        TabBeat(frets: {0: 1}, value: 16),
        TabBeat(frets: {0: 1}, value: 8),
        TabBeat(value: 8),
        TabBeat(frets: {0: 1}, value: 8),
        TabBeat.bar(),
        TabBeat(frets: {0: 1}, value: 8),
        TabBeat(frets: {0: 1}, value: 4),
      ]);
      expect(groups, [
        [0, 1],
        [2, 3, 4],
        [6],
        [8],
      ]);
    });
  });

  group('Slides und Bendings', () {
    test('Setzen, durchschalten, entfernen – nur wo eine Bundzahl steht', () {
      final e = TabEditor(const []);
      e.cycleBend();
      expect(e.beats, isEmpty, reason: 'ohne Bundzahl nichts');
      e.setFret(7);
      e.cycleBend();
      expect(e.beats.single.bends, {0: 1});
      e.cycleBend();
      e.cycleBend();
      e.cycleBend();
      expect(e.beats.single.bends, {0: 6});
      e.cycleBend();
      expect(e.beats.single.bends, isEmpty, reason: 'nach 1½ wieder aus');
      e.bend(4);
      expect(e.beats.single.bends, {0: 4});
      e.bend(4);
      expect(e.beats.single.bends, isEmpty, reason: 'gleiche Stufe nochmals = aus');
      e.toggleSlide();
      expect(e.beats.single.slides, {0});
      e.bend(2);
      e.clearNote();
      expect(e.beats.single.slides, isEmpty, reason: 'Bundzahl weg = Technik weg');
      expect(e.beats.single.bends, isEmpty);
    });

    test('Speichern und Lesen', () {
      const b = TabBeat(frets: {0: 7, 2: 5}, bends: {0: 6}, slides: {2});
      final back = TabBeat.fromJson(b.toJson());
      expect(back, b);
      expect(back.bends, {0: 6});
      expect(back.slides, {2});
      expect(bendLabel(4), 'full');
    });

    test('Slide in den Ton und aus dem Ton (Richtung wählbar)', () {
      final e = TabEditor(const []);
      e.slideIn(1);
      expect(e.beats, isEmpty, reason: 'ohne Bundzahl nichts');
      e.setFret(5);
      e.slideIn(1);
      expect(e.beats.single.slideIns, {0: 1});
      e.slideIn(-1);
      expect(e.beats.single.slideIns, {0: -1}, reason: 'andere Richtung ersetzt');
      e.slideIn(-1);
      expect(e.beats.single.slideIns, isEmpty, reason: 'gleiche Richtung nochmals = weg');
      // Durchschalten mit einer Taste: von unten → von oben → aus
      e.cycleSlideIn();
      expect(e.beats.single.slideIns, {0: 1});
      e.cycleSlideIn();
      expect(e.beats.single.slideIns, {0: -1});
      e.cycleSlideIn();
      expect(e.beats.single.slideIns, isEmpty);
      // Heraus: ersetzt den Slide zur nächsten Note und umgekehrt
      e.toggleSlide();
      e.slideOut(-1);
      expect(e.beats.single.slideOuts, {0: -1});
      expect(e.beats.single.slides, isEmpty);
      e.toggleSlide();
      expect(e.beats.single.slides, {0});
      expect(e.beats.single.slideOuts, isEmpty);
      // Davor und danach zugleich geht
      e.slideIn(1);
      e.slideOut(1);
      expect(e.beats.single.slideIns, {0: 1});
      expect(e.beats.single.slideOuts, {0: 1});
      e.clearNote();
      expect(e.beats.single.slideIns, isEmpty, reason: 'Bundzahl weg = Slide weg');
      expect(e.beats.single.slideOuts, isEmpty);
    });

    test('Ghost Note: x statt Bundzahl, ohne Bending, speichern und lesen', () {
      final e = TabEditor(const []);
      e.toggleGhost();
      expect(e.beats.single.frets, {0: ghostNote}, reason: 'legt auch einen neuen Schlag an');
      e.cycleBend();
      e.bend(2);
      expect(e.beats.single.bends, isEmpty, reason: 'kein Bending auf einer Ghost Note');
      e.toggleGhost();
      expect(e.beats.single.frets, isEmpty, reason: 'nochmals = weg');
      e.setFret(5);
      e.bend(2);
      e.toggleGhost();
      expect(e.beats.single.frets, {0: ghostNote}, reason: 'ersetzt die Bundzahl');
      expect(e.beats.single.bends, isEmpty, reason: 'Bending geht mit');
      e.setFret(7);
      expect(e.beats.single.frets, {0: 7}, reason: 'eine Zahl ersetzt das x');
      const b = TabBeat(frets: {2: ghostNote, 3: 5});
      expect(TabBeat.fromJson(b.toJson()), b);
      expect(TabKeymap.defaults.actionFor(LogicalKeyboardKey.keyX, ctrl: false, shift: true, alt: false), TabAction.ghost);
    });

    test('Slides davor/danach speichern, lesen und zeichnen', () {
      const b = TabBeat(frets: {1: 5, 3: 7}, slideIns: {1: -1}, slideOuts: {3: 1});
      final back = TabBeat.fromJson(b.toJson());
      expect(back, b);
      expect(back, isNot(const TabBeat(frets: {1: 5, 3: 7}, slideIns: {1: 1}, slideOuts: {3: 1})));
      // Ungültige Werte werden beim Lesen verworfen
      final odd = TabBeat.fromJson({
        'f': {'1': 5},
        'sIn': {'1': 3, '2': 1},
      });
      expect(odd.slideIns, isEmpty);
      // Platz für die Linie vor der Zahl
      final plain = layoutTab(
        block('a', beats: const [TabBeat(frets: {1: 5}), TabBeat(frets: {1: 7})]),
        const Size(1000, 1400),
      );
      final slid = layoutTab(
        block('a', beats: const [TabBeat(frets: {1: 5}), TabBeat(frets: {1: 7}, slideIns: {1: 1})]),
        const Size(1000, 1400),
      );
      expect(slid.xs[1] - slid.xs[0], greaterThan(plain.xs[1] - plain.xs[0]));
    });
  });

  group('Taktart und Takte', () {
    const q = TabBeat(frets: {0: 1});
    test('Taktart lesen, Ganztaktpausen', () {
      expect(meterLength('3/4'), 0.75);
      expect(meterLength('6/8'), 0.75);
      expect(meterLength('12/8'), 1.5);
      expect(meterLength('7/3'), isNull);
      expect(meterLength(null), isNull);
      double total(List<TabBeat> r) => r.fold(0.0, (a, b) => a + b.length);
      expect(restsFor(1.0), [const TabBeat(value: 1)]);
      expect(restsFor(0.75), [const TabBeat(value: 2, dotted: true)], reason: '3/4 = punktierte Halbe');
      expect(total(restsFor(1.25)), closeTo(1.25, 1e-9), reason: '5/4');
      expect(restsFor(1.25).every((b) => b.isRest), isTrue);
    });

    test('Beim Weiterschreiben kommt nach einem vollen Takt der Taktstrich von selbst', () {
      final e = TabEditor(const [], measure: 0.5); // 2/4
      e.setFret(1);
      e.move(1);
      e.setFret(2);
      e.move(1);
      e.setFret(3);
      expect(e.beats.map((b) => b.bar).toList(), [false, false, true, false]);
    });

    test('Taktstriche neu setzen, Takt einfügen und löschen – die anderen Takte bleiben', () {
      final beats = rebar([q, q, q, q, q, q, const TabBeat.bar(), q, q], 1.0);
      expect(beats.map((b) => b.bar).toList(), [false, false, false, false, true, false, false, false, false]);
      final e = TabEditor(beats, measure: 1.0);
      // Cursor im zweiten Takt
      e.beat = 6;
      e.insertMeasure();
      final m = measuresOf(e.beats);
      expect(m.length, 3);
      expect(e.beats[m[1].start].isRest, isTrue, reason: 'neuer leerer Takt vor dem zweiten');
      expect(m[1].length, 1.0);
      expect(m[2].length, 1.0, reason: 'der bisherige zweite Takt bleibt ganz');
      e.deleteMeasure();
      expect(measuresOf(e.beats).length, 2);
      expect(e.beats.where((b) => b.bar).length, 1);
      // Am Ende: ein Takt wird hinten angefügt
      e.beat = e.beats.length;
      e.insertMeasure();
      expect(measuresOf(e.beats).length, 3);
      expect(measuresOf(e.beats).last.length, 1.0);
    });

    test('Taktwechsel nur für einen Takt: eingeschobener 2/4-Takt', () {
      // Drei 4/4-Takte
      final beats = rebar([for (var i = 0; i < 12; i++) q], 1.0);
      final e = TabEditor(beats, meter: '4/4');
      e.beat = 5; // zweiter Takt
      expect(e.measureIndex, 1);
      e.setMeasureMeter('2/4');
      expect(e.currentMeter, '2/4');
      expect(measureLengths(e.beats, e.measure), [1.0, 0.5, 1.0], reason: 'nur der zweite Takt ist 2/4');
      expect(e.beats.length, beats.length, reason: 'nichts wird verschoben');
      final bars = [for (final b in e.beats) if (b.bar) b.meter];
      expect(bars, ['2/4', '4/4']);
      // Wieder 4/4 wählen: kein Taktwechsel mehr
      e.setMeasureMeter('4/4');
      expect([for (final b in e.beats) if (b.bar) b.meter], [null, null]);
      expect(measureLengths(e.beats, e.measure), [1.0, 1.0, 1.0]);
    });

    test('Taktwechsel: Weiterschreiben und Prüfen in der neuen Taktart', () {
      final e = TabEditor(rebar([q, q, q, q, q], 1.0), meter: '4/4');
      e.beat = e.beats.length - 1; // letzter Takt (nur eine Viertel)
      e.setMeasureMeter('2/4');
      e.beat = e.beats.length;
      e.setFret(3);
      e.move(1);
      e.setFret(5);
      final lengths = measureLengths(e.beats, e.measure);
      expect(lengths, [1.0, 0.5, 0.5], reason: 'nach vollem 2/4-Takt Taktstrich, weiter in 2/4');
      expect(measuresOf(e.beats)[1].length, 0.5);
    });

    test('Taktwechsel im ersten Takt ändert die Taktart der Tabulatur', () {
      final e = TabEditor(rebar([q, q, q, q, q, q, q, q], 1.0), meter: '4/4');
      e.beat = 0;
      e.setMeasureMeter('3/4');
      expect(e.meter, '3/4');
      expect(measureLengths(e.beats, e.measure), [0.75, 1.0], reason: 'zweiter Takt bleibt 4/4');
    });

    test('Taktwechsel wird gespeichert und bleibt beim Neusetzen der Taktstriche', () {
      const bar = TabBeat.bar(kind: BarKind.repeatStart, meter: '3/4');
      expect(TabBeat.fromJson(bar.toJson()), bar);
      expect(TabBeat.fromJson(const TabBeat.bar().toJson()).meter, isNull);
      expect(bar.barWith(kind: BarKind.normal).meter, '3/4');
      expect(bar.barWith(meter: null).meter, isNull);
      final beats = rebar([q, q, q, q, const TabBeat.bar(meter: '2/4'), q, q, const TabBeat.bar(), q, q, q, q], 1.0);
      expect(measureLengths(beats, 1.0), [1.0, 0.5, 0.5, 0.5], reason: 'ab dem Wechsel in 2/4');
      // Takt mit Wechsel löschen: der Wechsel danach gilt weiter
      final e = TabEditor(
        [q, q, q, q, const TabBeat.bar(meter: '2/4'), q, q, const TabBeat.bar(meter: '4/4'), q, q, q, q],
        meter: '4/4',
      );
      e.beat = 5;
      e.deleteMeasure();
      expect(measureLengths(e.beats, e.measure), [1.0, 1.0]);
    });

    test('Palm Mute: einzeln oder für Markiertes, nicht bei Pausen, gespeichert', () {
      final e = TabEditor([
        const TabBeat(frets: {5: 0}),
        const TabBeat(),
        const TabBeat.bar(),
        const TabBeat(frets: {5: 3}),
      ]);
      e.togglePalmMute();
      expect(e.beats[0].palmMute, isTrue);
      e.anchor = 0;
      e.beat = 3;
      e.togglePalmMute(); // nicht alle gedämpft → alle an
      expect([for (final b in e.beats) b.palmMute], [true, false, false, true]);
      e.togglePalmMute(); // alle gedämpft → alle aus
      expect(e.beats.any((b) => b.palmMute), isFalse);
      const pm = TabBeat(frets: {4: 2}, palmMute: true);
      expect(TabBeat.fromJson(pm.toJson()), pm);
      expect(pm.copyWith(frets: const {}).palmMute, isFalse, reason: 'Pause ohne P.M.');
    });

    test('Taktart wird gespeichert', () {
      final b = block('a').copyWith(meter: '6/8');
      expect(TabBlock.fromJson(b.toJson()).meter, '6/8');
      expect(TabBlock.fromJson(b.toJson()).measure, 0.75);
      expect(TabBlock.fromJson(block('b').toJson()).meter, isNull);
    });
  });

  group('Markieren, Kopieren, Einfügen', () {
    test('Bereich kopieren und an anderer Stelle einfügen, Markierung löschen', () {
      final e = TabEditor(const [
        TabBeat(frets: {0: 1}),
        TabBeat(frets: {0: 2}),
        TabBeat(frets: {0: 3}),
        TabBeat(frets: {0: 4}),
      ]);
      e.beat = 1;
      e.extend(1);
      expect(e.selection, (1, 2));
      final clip = e.copySelection();
      expect(clip.map((b) => b.frets[0]), [2, 3]);
      e.move(10); // ans Ende, Markierung weg
      expect(e.selection, isNull);
      e.paste(clip);
      expect(e.beats.map((b) => b.frets[0]), [1, 2, 3, 4, 2, 3]);
      expect(e.beat, 6);
      e.selectRange(0, 1);
      expect(e.deleteSelection(), isTrue);
      expect(e.beats.map((b) => b.frets[0]), [3, 4, 2, 3]);
      e.selectAll();
      e.paste(const [TabBeat(frets: {1: 9})]);
      expect(e.beats.single.frets, {1: 9}, reason: 'Einfügen ersetzt die Markierung');
    });
  });

  group('Wiederholungen, Haltebogen, Staccato, Akzent', () {
    const q = TabBeat(frets: {0: 1});
    test('Wiederholung Anfang und Ende hängen am Takt mit dem Cursor', () {
      final e = TabEditor(const [q, q, TabBeat.bar(), q, q]);
      e.beat = 3; // zweiter Takt
      e.repeatStart();
      expect(e.beats[2].kind, BarKind.repeatStart);
      e.repeatEnd(); // letzter Takt: Taktstrich hinten
      expect(e.beats.last.kind, BarKind.repeatEnd);
      e.beat = 0;
      e.repeatEnd(); // Ende des ersten Takts = Anfang des zweiten → beides
      expect(e.beats[2].kind, BarKind.repeatBoth);
      e.repeatEnd();
      expect(e.beats[2].kind, BarKind.repeatStart, reason: 'nochmals = Ende wieder weg');
      e.repeatStart(); // erster Takt: Zeichen ganz am Anfang
      expect(e.beats.first.bar, isTrue);
      expect(e.beats.first.kind, BarKind.repeatStart);
      expect(e.beat, 1, reason: 'Cursor bleibt beim selben Schlag');
      e.beat = e.beats.length - 2;
      e.finalBar();
      expect(e.beats.last.kind, BarKind.last);
      e.doubleBar();
      expect(e.beats.last.kind, BarKind.doubleLine, reason: 'Schlussstrich wird zum Doppelstrich');
      e.doubleBar();
      expect(e.beats.last.kind, BarKind.normal);
      expect(TabBeat.fromJson(const TabBeat.bar(kind: BarKind.doubleLine).toJson()).kind, BarKind.doubleLine);
      final back = TabBeat.fromJson(const TabBeat.bar(kind: BarKind.repeatBoth).toJson());
      expect(back.kind, BarKind.repeatBoth);
    });

    test('Haltebogen setzt die gleiche Bundzahl beim nächsten Schlag, gehaltene in Klammern', () {
      final e = TabEditor(const [TabBeat(frets: {2: 5}), TabBeat(frets: {0: 1})]);
      e.string = 2;
      e.toggleTie();
      expect(e.beats[0].ties, {2});
      expect(e.beats[1].frets, {0: 1, 2: 5});
      expect(tieTargets(e.beats), {(1, 2)});
      e.toggleTie();
      expect(e.beats[0].ties, isEmpty);
    });

    test('Staccato und Akzent pro Schlag, nicht bei Pausen, gespeichert', () {
      final e = TabEditor(const [TabBeat(frets: {0: 3}), TabBeat()]);
      e.toggleStaccato();
      e.toggleAccent();
      expect(e.beats[0].staccato, isTrue);
      expect(e.beats[0].accent, isTrue);
      e.beat = 1;
      e.toggleStaccato();
      expect(e.beats[1].staccato, isFalse, reason: 'Pause hat keine Artikulation');
      final back = TabBeat.fromJson(e.beats[0].toJson());
      expect(back, e.beats[0]);
      e.beat = 0;
      e.rest();
      expect(e.beats[0].staccato, isFalse, reason: 'zur Pause gemacht = weg');
    });
  });

  group('Einzelne Noten löschen, Noten übereinander markieren', () {
    const chord = TabBeat(frets: {0: 0, 1: 1, 2: 0, 3: 2});
    test('Ohne Markierung verschwindet nur die eine Note, der Schlag bleibt', () {
      final e = TabEditor(const [chord, TabBeat(frets: {0: 3})]);
      e.string = 1;
      e.deleteSelection() ? null : e.clearNote();
      expect(e.beats.length, 2);
      expect(e.beats[0].frets, {0: 0, 2: 0, 3: 2});
    });

    test('Einzelne Saiten markiert (Rechteck): Löschen trifft nur diese', () {
      final e = TabEditor(const [chord, chord]);
      e.string = 1;
      e.extendString(1);
      e.extendString(1); // Saiten 1–3
      expect(e.stringSelection, (1, 3));
      expect(e.selection, (0, 0));
      expect(e.deleteSelection(), isTrue);
      expect(e.beats.length, 2, reason: 'Schläge bleiben');
      expect(e.beats[0].frets, {0: 0});
      expect(e.beats[1].frets, chord.frets, reason: 'nur der markierte Schlag');
      // Rechteck über zwei Schläge
      e.beat = 0;
      e.string = 0;
      e.extendString(1);
      e.extend(1);
      expect(e.selection, (0, 1));
      e.deleteSelection();
      expect(e.beats[0].isRest, isTrue);
      expect(e.beats[1].frets, {2: 0, 3: 2});
    });

    test('Ganzen Schlag markieren: alle Noten übereinander, Taktstrich oder Pause; Entf löscht ihn', () {
      final e = TabEditor(const [chord, TabBeat.bar(), TabBeat(), TabBeat(frets: {0: 3})]);
      e.string = 3;
      e.selectColumn();
      expect(e.selection, (0, 0));
      expect(e.stringSelection, isNull, reason: 'alle Saiten');
      expect(e.deleteSelection(), isTrue);
      expect(e.beats.length, 3, reason: 'der ganze Akkord ist weg');
      expect(e.beats.first.bar, isTrue);
      // Taktstrich
      e.beat = 0;
      e.selectColumn();
      e.deleteSelection();
      expect(e.beats.first.isRest, isTrue);
      // Pause, dann mit → erweitern
      e.beat = 0;
      e.selectColumn();
      e.extend(1);
      expect(e.selection, (0, 1));
      e.deleteSelection();
      expect(e.beats, isEmpty);
    });

    test('Alte gespeicherte Belegung wird umgestellt', () {
      const old = '{"clearNote":{"k":4294967304},"deleteBeat":{"k":4294967423}}';
      final m = TabKeymap.fromJson(old);
      expect(m[TabAction.clearNote]!.key, LogicalKeyboardKey.delete);
      expect(m[TabAction.deleteBeat]!.ctrl, isTrue);
    });
  });

  group('Haltebogen von davor', () {
    test('Ein/aus, nur mit Bundzahl, speichern und lesen', () {
      final e = TabEditor(const []);
      e.toggleTieIn();
      expect(e.beats, isEmpty, reason: 'ohne Bundzahl nichts');
      e.setFret(7);
      e.toggleTieIn();
      expect(e.beats.single.tieIns, {0});
      final back = TabBeat.fromJson(e.beats.single.toJson());
      expect(back, e.beats.single);
      expect(back.tieIns, {0});
      e.toggleTieIn();
      expect(e.beats.single.tieIns, isEmpty);
      e.toggleTieIn();
      e.clearNote();
      expect(e.beats.single.tieIns, isEmpty, reason: 'Bundzahl weg = Bogen weg');
      expect(
        TabKeymap.defaults.actionFor(LogicalKeyboardKey.keyO, ctrl: false, shift: true, alt: false),
        TabAction.tieIn,
      );
    });
  });

  group('Besondere Taktstriche bleiben', () {
    test('Taktart neu setzen behält Wiederholung vorne, Arten in der Mitte und Schlussstrich hinten', () {
      const q = TabBeat(frets: {0: 1});
      final beats = [
        const TabBeat.bar(kind: BarKind.repeatStart),
        q, q, q, q,
        const TabBeat.bar(kind: BarKind.repeatEnd),
        q, q, q, q,
        const TabBeat.bar(kind: BarKind.last),
      ];
      final out = rebar(beats, 1.0);
      expect(out.first.kind, BarKind.repeatStart);
      expect(out[5].kind, BarKind.repeatEnd);
      expect(out.last.kind, BarKind.last);
    });
  });

  group('Triolen', () {
    test('Drei Achtel-Triolen = eine Viertel, die Triole geht beim Weiterschreiben weiter', () {
      final e = TabEditor(const [], measure: 0.25);
      e.setValue(8);
      e.setFret(1);
      e.toggleTriplet();
      e.move(1);
      e.setFret(2);
      e.move(1);
      e.setFret(3);
      expect(e.beats.where((b) => b.triplet).length, 3, reason: 'die angefangene Triole läuft weiter');
      expect(measuresOf(e.beats).first.length, closeTo(0.25, 1e-9));
      expect(tripletGroups(e.beats), [(start: 0, end: 2, complete: true)]);
      e.move(1);
      e.setFret(4);
      expect(e.beats.last.triplet, isFalse, reason: 'nach einer vollen Triole normal weiter');
      expect(e.beats.where((b) => b.bar).length, 1, reason: 'der Takt war voll');
      expect(beamGroups(e.beats).first, [0, 1, 2]);
      expect(TabBeat.fromJson(e.beats.first.toJson()).triplet, isTrue);
    });
  });

  group('Verschobene Taktstriche', () {
    const page = Size(1000, 1400);
    final beats = const [
      TabBeat(frets: {0: 1}),
      TabBeat(frets: {0: 2}),
      TabBeat.bar(),
      TabBeat(frets: {0: 3}),
      TabBeat(frets: {0: 4}),
    ];

    test('Taktstrich steht, wo er hingezogen wurde, die Schläge verteilen sich', () {
      final auto = layoutTab(block('a', beats: beats), page);
      final moved = [...beats]..[2] = const TabBeat.bar(at: 0.6);
      final l = layoutTab(block('a', beats: moved), page);
      expect(l.xs[2], closeTo(l.contentStart + 0.6 * (l.contentEnd - l.contentStart), 0.001));
      expect(l.xs[2], greaterThan(auto.xs[2]), reason: 'weiter rechts als automatisch');
      // Schläge davor gestreckt, in der richtigen Reihenfolge
      expect(l.xs[0], lessThan(l.xs[1]));
      expect(l.xs[1], lessThan(l.xs[2]));
      expect(l.xs[1] - l.xs[0], greaterThan(auto.xs[1] - auto.xs[0]));
      // Schläge danach rücken mit
      expect(l.xs[3], greaterThan(l.xs[2]));
      expect(l.xs[4], greaterThan(l.xs[3]));
      expect(l.fractionAt(l.xs[2]), closeTo(0.6, 0.001));
    });

    test('Lage wird gespeichert, ein automatischer Taktstrich bleibt automatisch', () {
      final back = TabBeat.fromJson(const TabBeat.bar(at: 0.42).toJson());
      expect(back.at, 0.42);
      expect(back, const TabBeat.bar(at: 0.42));
      expect(TabBeat.fromJson(const TabBeat.bar().toJson()).at, isNull);
      expect(const TabBeat.bar(at: 0.4) == const TabBeat.bar(), isFalse);
    });

    test('Grösse ändern: Linienabstand wächst mit', () {
      final small = layoutTab(block('a', beats: beats), page);
      final big = layoutTab(block('a', beats: beats).copyWith(gap: TabBlock.defaultGap * 2), page);
      expect(big.gap, closeTo(small.gap * 2, 1e-9));
      expect(big.bottom - big.top, closeTo((small.bottom - small.top) * 2, 1e-9));
    });
  });

  group('Zusammenführen und Rückgängig', () {
    test('Jüngste Fassung gewinnt als Ganzes, auch beim Löschen', () {
      final a = ScoreAnnotations()..putTab(block('t', beats: const [TabBeat(frets: {0: 1})], at: DateTime.utc(2026, 2)));
      final b = ScoreAnnotations()..putTab(block('t', deleted: true, at: DateTime.utc(2026, 1)));
      expect(ScoreAnnotations.merge(a, b).tab('t')!.deleted, isFalse, reason: 'später zurückgeholt');
      expect(ScoreAnnotations.merge(b, a).tab('t')!.deleted, isFalse);
      final c = ScoreAnnotations()..putTab(block('t', deleted: true, at: DateTime.utc(2026, 3)));
      expect(ScoreAnnotations.merge(a, c).tab('t')!.deleted, isTrue);
    });

    test('Zusatzdatei behält Tabulaturen', () async {
      final dir = Directory.systemTemp.createTempSync('volti_tab');
      addTearDown(() => dir.deleteSync(recursive: true));
      final pdf = '${dir.path}/x.pdf';
      await const SidecarStore().save(pdf, annotations: ScoreAnnotations()..putTab(block('t')));
      final back = await const SidecarStore().load(pdf);
      expect(back.annotations.tab('t'), isNotNull);
    });

    test('Tabulaturen landen immer auf der Ebene „TABS“ (je Bibliothek bzw. Setlist eine)', () async {
      final dir = Directory.systemTemp.createTempSync('volti_tab');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = InkController(pdfPath: '${dir.path}/x.pdf');
      final other = c.addLayer('Fingersätze');
      expect(c.activeLayer, other);
      final a = c.addTab(page: 1, x: 0.1, y: 0.1, width: 0.8);
      expect(c.annotations.tab(a)!.layer, 'tabs');
      expect(c.annotations.layer('tabs')!.name, 'TABS');
      expect(c.activeLayer, other, reason: 'die aktive Ebene bleibt');
      expect(c.layers.last.id, 'tabs', reason: 'ganz oben');
      // Ausgeblendet: die nächste Tabulatur blendet sie wieder ein.
      c.setLayerVisible('tabs', false);
      final b = c.addTab(page: 2, x: 0.1, y: 0.1, width: 0.8);
      expect(c.annotations.tab(b)!.layer, 'tabs');
      expect(c.annotations.layer('tabs')!.visible, isTrue);
      expect(c.layers.where((l) => l.name == 'TABS').length, 1, reason: 'keine zweite');
      // Ein Rückgängig-Schritt nimmt bei der ersten auch die Ebene mit.
      c.undo();
      c.undo();
      expect(c.annotations.visibleTabsOn(1), isEmpty);
      expect(c.layers.any((l) => l.id == 'tabs'), isFalse);
      // In einer Setlist: eigene Ebene, nur dort sichtbar.
      final s = InkController(pdfPath: '${dir.path}/y.pdf', scope: 'set1', scopeName: 'Probe');
      final t = s.addTab(page: 1, x: 0.1, y: 0.1, width: 0.8);
      expect(s.annotations.tab(t)!.layer, 'tabs-set1');
      expect(s.annotations.layer('tabs-set1')!.scope, 'set1');
    });

    test('Anlegen, Schreiben, Löschen – alles rückgängig machbar', () async {
      final dir = Directory.systemTemp.createTempSync('volti_tab');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = InkController(pdfPath: '${dir.path}/x.pdf');
      final id = c.addTab(page: 1, x: 0.1, y: 0.1, width: 0.8);
      c.updateTab(id, beats: const [TabBeat(frets: {0: 5})]);
      c.updateTab(id, gap: TabBlock.defaultGap * 1.5);
      expect(c.annotations.tab(id)!.gap, TabBlock.defaultGap * 1.5);
      c.undo();
      expect(c.annotations.tab(id)!.gap, TabBlock.defaultGap);
      c.deleteTab(id);
      expect(c.annotations.visibleTabsOn(1), isEmpty);
      expect(c.pageHasAnnotations(1), isFalse);
      c.undo();
      expect(c.annotations.tab(id)!.beats.single.frets, {0: 5});
      c.undo();
      expect(c.annotations.tab(id)!.beats, isEmpty);
      c.undo();
      expect(c.annotations.visibleTabsOn(1), isEmpty);
      c.redo();
      c.redo();
      expect(c.annotations.tab(id)!.beats.single.frets, {0: 5});
      // „Seite leeren“ nimmt Tabulaturen mit, Rückgängig holt sie zurück.
      c.clearPage(1);
      expect(c.annotations.visibleTabsOn(1), isEmpty);
      c.undo();
      expect(c.annotations.visibleTabsOn(1), hasLength(1));
      c.dispose();
    });
  });

  group('Tastenbelegung', () {
    test('Standard ohne Ziffernblock, Tauschen bei doppelter Belegung, Speichern', () {
      final d = TabKeymap.defaults;
      expect(d.actionFor(LogicalKeyboardKey.keyA, ctrl: false, shift: false, alt: false), TabAction.eighth);
      expect(d.actionFor(LogicalKeyboardKey.keyA, ctrl: true, shift: false, alt: false), isNull);
      expect(digitOf(LogicalKeyboardKey.digit7), 7);
      expect(digitOf(LogicalKeyboardKey.numpad7), 7);
      // Q für Achtel: Q gehörte niemandem
      final r = d.withBinding(TabAction.eighth, const KeyBinding(LogicalKeyboardKey.keyQ));
      expect(r.swapped, isNull);
      // S (Sechzehntel) für Achtel: getauscht, Sechzehntel bekommt Q
      final r2 = r.map.withBinding(TabAction.eighth, const KeyBinding(LogicalKeyboardKey.keyS));
      expect(r2.swapped, TabAction.sixteenth);
      expect(r2.map[TabAction.sixteenth]!.key, LogicalKeyboardKey.keyQ);
      final back = TabKeymap.fromJson(r2.map.toJson());
      expect(back[TabAction.eighth]!.key, LogicalKeyboardKey.keyS);
      expect(back[TabAction.sixteenth]!.key, LogicalKeyboardKey.keyQ);
      expect(back[TabAction.bar]!.key, LogicalKeyboardKey.keyT);
      expect(TabKeymap.fromJson('kaputt')[TabAction.rest]!.key, LogicalKeyboardKey.keyP);
      expect(const KeyBinding(LogicalKeyboardKey.keyK, ctrl: true).label, contains('K'));
      // Slides davor/danach: Umschalt+R und Strg+R, keine Taste doppelt
      expect(d.actionFor(LogicalKeyboardKey.keyR, ctrl: false, shift: true, alt: false), TabAction.slideIn);
      expect(d.actionFor(LogicalKeyboardKey.keyR, ctrl: true, shift: false, alt: false), TabAction.slideOut);
      final all = [for (final a in TabAction.values) d[a]].whereType<KeyBinding>().toList();
      for (var i = 0; i < all.length; i++) {
        for (var j = i + 1; j < all.length; j++) {
          expect(all[i].sameAs(all[j]), isFalse, reason: '${all[i].label} doppelt');
        }
      }
    });
  });

  group('Auf der Seite', () {
    late Directory dir;
    late InkController ink;
    late ToolController tools;

    setUp(() => dir = Directory.systemTemp.createTempSync('volti_tablayer'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> pump(WidgetTester t) async {
      tools = await t.runAsync(() => makeTools(dir)) as ToolController;
      ink = InkController(pdfPath: '${dir.path}/x.pdf');
      tools.setMode(ToolMode.tab);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 1100,
              child: TabLayer(page: 1, controller: ink, tools: tools, onEditingChanged: (_) {}),
            ),
          ),
        ),
      );
    }

    testWidgets('Mit der Maus anlegen und mit der Tastatur schreiben', (t) async {
      await pump(t);
      final g = await t.startGesture(const Offset(100, 200), kind: PointerDeviceKind.mouse);
      await g.moveTo(const Offset(400, 205));
      await g.moveTo(const Offset(700, 203));
      await g.up();
      await t.pump();
      final tab = ink.annotations.visibleTabsOn(1).single;
      expect(tab.x, closeTo(100 / 800, 0.01));
      expect(tab.width, closeTo(600 / 800, 0.01));
      expect(tools.tabSession.value, isNotNull, reason: 'gleich bereit zum Schreiben');
      await t.pump();
      // 3 auf der obersten Saite, Achtel, nächster Schlag, tiefer, 1 2 = 12
      for (final k in [
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.keyT,
      ]) {
        await t.sendKeyEvent(k);
      }
      final beats = ink.annotations.tab(tab.id)!.beats;
      expect(beats[0].frets, {0: 3});
      expect(beats[0].value, 8);
      expect(beats[1].frets, {1: 12});
      expect(beats[1].value, 8, reason: 'neuer Schlag übernimmt den Notenwert');
      expect(beats[2].bar, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(tools.tabSession.value, isNull);
      ink.dispose();
    });

    testWidgets('Taktstrich am Griff ziehen und mit langem Drücken zurücksetzen', (t) async {
      await pump(t);
      final id = ink.addTab(page: 1, x: 0.05, y: 0.1, width: 0.9);
      ink.updateTab(id, beats: const [TabBeat(frets: {0: 1}), TabBeat.bar(kind: BarKind.repeatEnd), TabBeat(frets: {0: 2})]);
      tools.tabSession.value = TabSession(ink: ink, id: id, page: 1);
      await t.pump();
      await t.pump();
      final handle = find.byTooltip('Taktstrich verschieben (lange drücken: wieder automatisch)');
      expect(handle, findsOneWidget);
      final before = layoutTab(ink.annotations.tab(id)!, const Size(800, 600)).xs[1];
      await t.drag(handle, const Offset(150, 0), kind: PointerDeviceKind.mouse);
      await t.pump();
      final bar = ink.annotations.tab(id)!.beats[1];
      expect(bar.at, isNotNull);
      expect(bar.kind, BarKind.repeatEnd, reason: 'Wiederholung bleibt beim Verschieben');
      final after = layoutTab(ink.annotations.tab(id)!, const Size(800, 600)).xs[1];
      expect(after, greaterThan(before + 100));
      await t.longPress(handle);
      await t.pump();
      expect(ink.annotations.tab(id)!.beats[1].at, isNull);
      expect(ink.annotations.tab(id)!.beats[1].kind, BarKind.repeatEnd);
      tools.tabSession.value = null;
      await t.pump();
      ink.dispose();
    });

    testWidgets('Umschalt+→ markiert, Strg+C/Strg+V kopiert, Takt einfügen mit Umschalt+N', (t) async {
      await pump(t);
      final id = ink.addTab(page: 1, x: 0.05, y: 0.1, width: 0.9);
      ink.updateTab(id, beats: const [TabBeat(frets: {0: 1}), TabBeat(frets: {0: 2})]);
      tools.tabSession.value = TabSession(ink: ink, id: id, page: 1);
      await t.pump();
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyC);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(tools.tabClip?.length, 2);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyV);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(ink.annotations.tab(id)!.beats.map((b) => b.frets[0]), [1, 2, 1, 2]);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyN);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(ink.annotations.tab(id)!.beats.length, 6, reason: 'Pause und Taktstrich dazu');
      tools.tabSession.value = null;
      await t.pump();
      ink.dispose();
    });

    testWidgets('Umschalt+↓ markiert sofort den ganzen Schlag, Entf löscht ihn', (t) async {
      await pump(t);
      final id = ink.addTab(page: 1, x: 0.05, y: 0.1, width: 0.9);
      ink.updateTab(id, beats: const [TabBeat(frets: {0: 1, 1: 3, 2: 2}), TabBeat(frets: {0: 5})]);
      tools.tabSession.value = TabSession(ink: ink, id: id, page: 1);
      await t.pump();
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(tools.tabSession.value!.selection, (0, 0));
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(ink.annotations.tab(id)!.beats.map((b) => b.frets), [
        {0: 5},
      ]);
      tools.tabSession.value = null;
      await t.pump();
      ink.dispose();
    });

    testWidgets('Der Finger legt keine Tabulatur an', (t) async {
      await pump(t);
      await t.tapAt(const Offset(200, 300), kind: PointerDeviceKind.touch);
      await t.pump();
      expect(ink.annotations.visibleTabsOn(1), isEmpty);
      ink.dispose();
    });
  });
}
