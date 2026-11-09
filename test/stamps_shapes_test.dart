import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/stamp.dart';
import 'package:volti/core/ink/stamp_catalog.dart';
import 'package:volti/core/ink/tool_settings.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/ink_layer.dart';
import 'package:volti/features/viewer/shapes.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

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
    test('Jede Form ergibt Linienzüge zwischen Start und Ende', () {
      for (final k in ShapeKind.values) {
        final pieces = shapeGeometry(k, const Offset(10, 50), const Offset(210, 80), 2);
        expect(pieces, isNotEmpty, reason: k.name);
        expect(pieces.every((p) => p.length >= 2), isTrue, reason: k.name);
      }
      expect(shapeGeometry(ShapeKind.arrow, Offset.zero, const Offset(100, 0), 2).length, 2, reason: 'Linie + Spitze');
      // Crescendo: Spitze am Anfang, Öffnung am Ende
      final cresc = shapeGeometry(ShapeKind.crescendo, Offset.zero, const Offset(100, 0), 2).single;
      expect(cresc[1], Offset.zero);
      expect(cresc.first.dx, 100);
      // Öffnung bleibt gleich weit, egal wie lang die Gabel ist
      double opening(double len) {
        final g = shapeGeometry(ShapeKind.crescendo, Offset.zero, Offset(len, 0), 2, pageWidth: 1000).single;
        return (g.first - g.last).distance;
      }

      expect(opening(100), closeTo(16, 0.01));
      expect(opening(600), closeTo(16, 0.01));
      final dim = shapeGeometry(ShapeKind.decrescendo, Offset.zero, const Offset(400, 0), 2, pageWidth: 1000).single;
      expect(dim[1], const Offset(400, 0), reason: 'Decrescendo: Spitze am Ende');
      expect((dim.first - dim.last).distance, closeTo(16, 0.01));
      // Zu kurz → keine Form
      expect(shapeGeometry(ShapeKind.line, Offset.zero, const Offset(1, 0), 2), isEmpty);
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
