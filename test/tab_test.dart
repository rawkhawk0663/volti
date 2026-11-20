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
      // E für Achtel: E gehörte niemandem
      final r = d.withBinding(TabAction.eighth, const KeyBinding(LogicalKeyboardKey.keyE));
      expect(r.swapped, isNull);
      // S (Sechzehntel) für Achtel: getauscht, Sechzehntel bekommt E
      final r2 = r.map.withBinding(TabAction.eighth, const KeyBinding(LogicalKeyboardKey.keyS));
      expect(r2.swapped, TabAction.sixteenth);
      expect(r2.map[TabAction.sixteenth]!.key, LogicalKeyboardKey.keyE);
      final back = TabKeymap.fromJson(r2.map.toJson());
      expect(back[TabAction.eighth]!.key, LogicalKeyboardKey.keyS);
      expect(back[TabAction.sixteenth]!.key, LogicalKeyboardKey.keyE);
      expect(back[TabAction.bar]!.key, LogicalKeyboardKey.keyT);
      expect(TabKeymap.fromJson('kaputt')[TabAction.rest]!.key, LogicalKeyboardKey.keyP);
      expect(const KeyBinding(LogicalKeyboardKey.keyK, ctrl: true).label, contains('K'));
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
      ink.updateTab(id, beats: const [TabBeat(frets: {0: 1}), TabBeat.bar(), TabBeat(frets: {0: 2})]);
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
      final after = layoutTab(ink.annotations.tab(id)!, const Size(800, 600)).xs[1];
      expect(after, greaterThan(before + 100));
      await t.longPress(handle);
      await t.pump();
      expect(ink.annotations.tab(id)!.beats[1].at, isNull);
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
