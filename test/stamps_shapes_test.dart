import 'dart:math' as math;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/stamp.dart';
import 'package:volti/core/ink/stamp_catalog.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/ink/tool_settings.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/ink_layer.dart';
import 'package:volti/features/viewer/shapes.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

List<List<Offset>> geo(ShapeKind k, Offset a, Offset b, double w, {double? pageWidth}) =>
    shapeGeometry(k, a, b, w, pageWidth: pageWidth).map((p) => p.points).toList();

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_stamps'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('Stempel-Sammlung', () {
    test('Alle Gruppen haben Symbole mit gültiger Ausdehnung', () {
      expect(stampCatalog.length, greaterThanOrEqualTo(8));
      for (final c in stampCatalog) {
        expect(c.glyphs, isNotEmpty, reason: c.name);
        for (final g in c.glyphs) {
          expect(g.width, greaterThan(0), reason: g.label);
          expect(g.height, greaterThan(0), reason: g.label);
        }
      }
      expect(stampGlyph(0xE52D)!.label, 'mf');
    });
  });

  group('Stempel setzen, verschieben, löschen', () {
    test('Hinzufügen, verschieben, rückgängig, gespeichert und zusammengeführt', () async {
      final pdf = '${dir.path}/x.pdf';
      final c = InkController(pdfPath: pdf);
      final id = c.addStamp(page: 1, x: 0.3, y: 0.4, glyph: 0xE52D, size: 0.045, color: 0xFF1B1B1B);
      c.moveStamp(id, 0.6, 0.7);
      expect(c.annotations.stamp(id)!.x, 0.6);
      c.undo();
      expect(c.annotations.stamp(id)!.x, 0.3);
      c.deleteStamps(c.annotations.visibleStampsOn(1));
      expect(c.annotations.visibleStampsOn(1), isEmpty);
      c.undo();
      expect(c.annotations.visibleStampsOn(1).single.glyph, 0xE52D);
      await c.save();
      c.dispose();

      final back = (await const SidecarStore().load(pdf)).annotations;
      expect(back.visibleStampsOn(1).single.glyph, 0xE52D);

      // Zwei Geräte: jedes setzt einen Stempel → beide bleiben.
      final other = ScoreAnnotations(const [], const [], [
        Stamp(
          id: 'fremd',
          page: 1,
          x: 0.1,
          y: 0.1,
          glyph: 0xE4C0,
          size: 0.04,
          color: 0xFF000000,
          createdAt: DateTime.utc(2026),
        ),
      ]);
      expect(ScoreAnnotations.merge(back, other).visibleStampsOn(1).length, 2);
    });

    test('Seite leeren entfernt auch Stempel', () {
      final c = InkController(pdfPath: '${dir.path}/x.pdf');
      c.addStamp(page: 1, x: 0.5, y: 0.5, glyph: 0xE4A0, size: 0.04, color: 0xFF000000);
      expect(c.pageHasAnnotations(1), isTrue);
      c.clearPage(1);
      expect(c.pageHasAnnotations(1), isFalse);
      c.undo();
      expect(c.annotations.visibleStampsOn(1).length, 1);
      c.dispose();
    });
  });

  group('Formen', () {
    test('Notenlinien sind feiner als die eingestellte Breite', () {
      final lines = shapeGeometry(ShapeKind.staff, Offset.zero, const Offset(400, 0), 2, pageWidth: 1000);
      expect(lines.every((l) => l.widthFactor < 1), isTrue);
    });

    test('Pfeilspitze: gefüllt, Grösse nur von der Breite abhängig', () {
      double headLen(double len, double w) {
        final head = shapeGeometry(ShapeKind.arrow, Offset.zero, Offset(len, 0), w).last;
        expect(head.solid, isTrue);
        final xs = head.points.map((p) => p.dx);
        return xs.reduce(math.max) - xs.reduce(math.min);
      }

      expect(headLen(200, 2), closeTo(headLen(600, 2), 1e-9), reason: 'gleich gross bei jeder Länge');
      expect(headLen(600, 4), greaterThan(headLen(600, 2)), reason: 'breiter = grössere Spitze');
    });

    test('Rechteck und Ellipse lassen sich füllen, die Füllung wird gespeichert', () {
      expect(shapeGeometry(ShapeKind.rectangle, Offset.zero, const Offset(50, 40), 2).single.closed, isTrue);
      expect(shapeCanFill(ShapeKind.ellipse), isTrue);
      expect(shapeCanFill(ShapeKind.line), isFalse);
      final s = Stroke(
        id: 'r',
        page: 1,
        tool: InkTool.pen,
        color: 0xFFFFFFFF,
        width: 0.002,
        fill: 0xFFFFFFFF,
        points: const [InkPoint(0, 0, 0.5), InkPoint(1, 0, 0.5), InkPoint(1, 1, 0.5)],
        createdAt: DateTime.utc(2026),
      );
      expect(Stroke.fromJson(s.toJson()).fill, 0xFFFFFFFF);
      expect(s.markDeleted(DateTime.utc(2027)).fill, 0xFFFFFFFF);
      expect(Stroke.fromJson({...s.toJson()}..remove('fill')).fill, isNull, reason: 'alte Striche ohne Füllung');
    });

    test('Jede Form ergibt Linienzüge zwischen Start und Ende', () {
      for (final k in ShapeKind.values) {
        final pieces = geo(k, const Offset(10, 50), const Offset(210, 80), 2);
        expect(pieces, isNotEmpty, reason: k.name);
        expect(pieces.every((p) => p.length >= 2), isTrue, reason: k.name);
      }
      expect(geo(ShapeKind.arrow, Offset.zero, const Offset(100, 0), 2).length, 2, reason: 'Linie + Spitze');
      // Crescendo: Spitze am Anfang, Öffnung am Ende
      final cresc = geo(ShapeKind.crescendo, Offset.zero, const Offset(100, 0), 2).single;
      expect(cresc[1], Offset.zero);
      expect(cresc.first.dx, 100);
      // Öffnung bleibt gleich weit, egal wie lang die Gabel ist
      double opening(double len) {
        final g = geo(ShapeKind.crescendo, Offset.zero, Offset(len, 0), 2, pageWidth: 1000).single;
        return (g.first - g.last).distance;
      }

      expect(opening(100), closeTo(16, 0.01));
      expect(opening(600), closeTo(16, 0.01));
      // Ein Werkzeug für beide Richtungen: nach links gezogen = Decrescendo.
      final dim = geo(ShapeKind.crescendo, const Offset(400, 0), Offset.zero, 2, pageWidth: 1000).single;
      expect(dim[1], const Offset(400, 0), reason: 'Spitze dort, wo man anfängt');
      expect(dim.first.dx, 0, reason: 'offen nach links');
      expect((dim.first - dim.last).distance, closeTo(16, 0.01));
      // Alte Einstellung „decrescendo“ wird zur Gabel.
      expect(normalizeShapeKind(ShapeKind.decrescendo), ShapeKind.crescendo);
      expect(offeredShapeKinds, isNot(contains(ShapeKind.decrescendo)));
      // Notenlinien: 5 waagrechte Linien; nur waagrecht gezogen → übliche Höhe
      final flat = geo(ShapeKind.staff, const Offset(100, 200), const Offset(500, 203), 2, pageWidth: 1000);
      expect(flat.length, 5);
      expect(flat.every((l) => l.first.dy == l.last.dy), isTrue, reason: 'immer waagrecht');
      expect(flat.last.first.dy - flat.first.first.dy, closeTo(33, 0.01));
      expect(flat.first.first.dx, 100);
      expect(flat.first.last.dx, 500);
      final wobble = geo(ShapeKind.staff, const Offset(100, 200), const Offset(500, 250), 2, pageWidth: 1000);
      expect(wobble.last.first.dy, closeTo(233, 0.01), reason: '50 px nach unten reichen noch nicht');
      final tall = geo(ShapeKind.staff, const Offset(100, 200), const Offset(500, 300), 2, pageWidth: 1000);
      expect(tall.last.first.dy, 300, reason: 'Höhe aus dem Ziehen nach unten');
      expect(tall[1].first.dy, 225);
      // Tabulatur: 6 Linien, sonst gleich wie Notenlinien
      final tab = geo(ShapeKind.tab, const Offset(100, 200), const Offset(500, 203), 2, pageWidth: 1000);
      expect(tab.length, 6);
      expect(tab.every((l) => l.first.dy == l.last.dy), isTrue);
      expect(tab.last.first.dy - tab.first.first.dy, closeTo(60, 0.01));
      expect(tab[1].first.dy - tab[0].first.dy, closeTo(12, 0.01), reason: 'gleiche Abstände');
      final tabWobble = geo(ShapeKind.tab, const Offset(100, 200), const Offset(500, 270), 2, pageWidth: 1000);
      expect(tabWobble.last.first.dy, closeTo(260, 0.01), reason: '70 px nach unten reichen noch nicht');
      final tabTall = geo(ShapeKind.tab, const Offset(100, 200), const Offset(500, 300), 2, pageWidth: 1000);
      expect(tabTall.last.first.dy, 300);
      expect(offeredShapeKinds, contains(ShapeKind.tab));
      // Gabeln immer waagrecht
      final hairpin = geo(ShapeKind.crescendo, const Offset(0, 0), const Offset(300, 80), 2, pageWidth: 1000).single;
      expect(hairpin[1], Offset.zero);
      expect((hairpin.first.dy + hairpin.last.dy) / 2, closeTo(0, 1e-9), reason: 'Mitte auf der Höhe des Starts');
      expect(hairpin.first.dx, 300);
      // Zu kurz → keine Form
      expect(geo(ShapeKind.line, Offset.zero, const Offset(1, 0), 2), isEmpty);
    });
  });

  group('Bedienung auf der Seite', () {
    late InkController c;
    late ToolController tools;

    Future<void> pump(WidgetTester t) async {
      c = InkController(pdfPath: '${dir.path}/x.pdf');
      tools = await t.runAsync(() => makeTools(dir)) as ToolController;
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 600,
              child: InkLayer(page: 1, controller: c, tools: tools),
            ),
          ),
        ),
      );
    }

    testWidgets('Stempel: Tippen setzt ihn, Ziehen verschiebt ihn', (t) async {
      await pump(t);
      tools.setMode(ToolMode.stamp);
      await t.tapAt(const Offset(100, 150), kind: PointerDeviceKind.stylus);
      await t.pump();
      final st = c.annotations.visibleStampsOn(1).single;
      expect(st.x, closeTo(0.25, 0.01));
      expect(st.y, closeTo(0.25, 0.01));
      expect(tools.recentStamps.first, st.glyph);

      final g = await t.startGesture(const Offset(100, 150), kind: PointerDeviceKind.stylus);
      await g.moveTo(const Offset(300, 450));
      await g.up();
      await t.pump();
      final moved = c.annotations.visibleStampsOn(1).single;
      expect(moved.id, st.id, reason: 'derselbe Stempel, nur verschoben');
      expect(moved.x, closeTo(0.75, 0.01));
      await t.runAsync(() => tools.flush());
      c.dispose();
    });

    testWidgets('Form aufziehen erzeugt Striche (ein Rückgängig-Schritt)', (t) async {
      await pump(t);
      tools.setMode(ToolMode.shape);
      tools.setShapeKind(ShapeKind.arrow);
      final g = await t.startGesture(const Offset(50, 300), kind: PointerDeviceKind.stylus);
      await g.moveTo(const Offset(350, 300));
      await g.up();
      await t.pump();
      expect(c.annotations.visibleStrokesOn(1).length, 2);
      c.undo();
      expect(c.annotations.visibleStrokesOn(1), isEmpty);
      await t.runAsync(() => tools.flush());
      c.dispose();
    });

    testWidgets('Radierer löscht Stempel', (t) async {
      await pump(t);
      c.addStamp(page: 1, x: 0.5, y: 0.5, glyph: 0xE52D, size: 0.05, color: 0xFF000000);
      await t.pump();
      tools.setMode(ToolMode.eraser);
      final g = await t.startGesture(const Offset(200, 300), kind: PointerDeviceKind.stylus);
      await g.moveBy(const Offset(2, 0));
      await g.up();
      await t.pump();
      expect(c.annotations.visibleStampsOn(1), isEmpty);
      c.dispose();
    });

    testWidgets('Lineal: Stift an der Kante zeichnet eine gerade Linie', (t) async {
      await pump(t);
      tools.setMode(ToolMode.pen);
      tools.toggleRuler();
      tools.moveRuler(const Offset(200, 300), 0); // waagrecht, Mitte der Seite
      // Unterhalb der unteren Kante (Kante bei y = 332) wackelig zeichnen
      final g = await t.startGesture(const Offset(80, 345), kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset(80.0 + i * 20, 345.0 + (i.isEven ? 8 : -6)));
      }
      await g.up();
      await t.pump();
      final pts = c.annotations.visibleStrokesOn(1).single.points;
      final ys = pts.map((p) => p.y * 600).toSet();
      expect(ys.every((y) => (y - 334).abs() < 0.6), isTrue, reason: 'alle Punkte auf der Kante: $ys');
      c.dispose();
    });
  });
}
