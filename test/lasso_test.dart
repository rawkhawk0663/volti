import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/selection.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/ink_layer.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_lasso'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Waagrechter Strich von x0 bis x1 auf Höhe y (normiert).
  void line(InkController c, double x0, double x1, double y, {int color = 0xFF000000, int page = 1}) => c.addStroke(
    page: page,
    tool: InkTool.pen,
    color: color,
    width: 0.004,
    points: [for (var i = 0; i <= 10; i++) InkPoint(x0 + (x1 - x0) * i / 10, y, 0.5)],
  );

  const square = [Offset(0.1, 0.1), Offset(0.5, 0.1), Offset(0.5, 0.5), Offset(0.1, 0.5)];
  Rect noText(_) => Rect.zero;

  group('Auswahl im Datenmodell', () {
    test('Punkt im Vieleck', () {
      expect(pointInPolygon(const Offset(0.3, 0.3), square), isTrue);
      expect(pointInPolygon(const Offset(0.7, 0.3), square), isFalse);
    });

    test('Lasso: Striche zur Hälfte drin, Stempel mit der Mitte', () {
      final c = InkController(pdfPath: '${dir.path}/x.pdf');
      line(c, 0.15, 0.45, 0.3); // ganz drin
      line(c, 0.3, 0.9, 0.4); // nur zu einem Drittel drin → nicht ausgewählt
      line(c, 0.15, 0.45, 0.8); // draussen
      c.addStamp(page: 1, x: 0.2, y: 0.2, glyph: 0xE520, size: 0.05, color: 0xFF000000);
      c.addStamp(page: 1, x: 0.8, y: 0.2, glyph: 0xE520, size: 0.05, color: 0xFF000000);
      final ids = lassoSelect(c.annotations, 1, square, textBounds: noText);
      final strokes = c.annotations.visibleStrokesOn(1);
      expect(ids.strokes, {strokes[0].id});
      expect(ids.stamps.length, 1);
      expect(lassoSelect(c.annotations, 2, square, textBounds: noText).isEmpty, isTrue, reason: 'andere Seite');
      c.dispose();
    });

    test('Verschieben und Vergrössern, rückgängig in einem Schritt', () {
      final c = InkController(pdfPath: '${dir.path}/x.pdf');
      line(c, 0.2, 0.4, 0.3);
      final st = c.addStamp(page: 1, x: 0.3, y: 0.3, glyph: 0xE520, size: 0.05, color: 0xFF000000);
      final s = c.annotations.visibleStrokesOn(1).single;
      final ids = SelectionIds(strokes: {s.id}, stamps: {st});

      c.transformSelection(ids, const SelectionTransform(delta: Offset(0.1, 0.2)));
      final moved = c.annotations[s.id]!;
      expect(moved.id, s.id, reason: 'derselbe Strich (für den Sync)');
      expect(moved.points.first.x, closeTo(0.3, 1e-9));
      expect(moved.points.first.y, closeTo(0.5, 1e-9));
      expect(c.annotations.stamp(st)!.y, closeTo(0.5, 1e-9));

      c.transformSelection(ids, const SelectionTransform(scale: 2, anchor: Offset(0.3, 0.5)));
      final big = c.annotations[s.id]!;
      expect(big.points.last.x, closeTo(0.3 + 0.2 * 2, 1e-9));
      expect(big.width, closeTo(0.008, 1e-9), reason: 'Strichbreite wächst mit');
      expect(c.annotations.stamp(st)!.size, closeTo(0.1, 1e-9));

      c.undo();
      expect(c.annotations[s.id]!.points.last.x, closeTo(0.5, 1e-9), reason: 'nur Vergrössern rückgängig');
      c.undo();
      expect(c.annotations[s.id]!.points.first.x, closeTo(0.2, 1e-9));
      expect(c.annotations.stamp(st)!.y, closeTo(0.3, 1e-9));
      c.redo();
      expect(c.annotations[s.id]!.points.first.y, closeTo(0.5, 1e-9));
      c.dispose();
    });

    test('Umfärben behält die Deckkraft; Löschen ist ein Schritt', () {
      final c = InkController(pdfPath: '${dir.path}/x.pdf');
      line(c, 0.2, 0.4, 0.3, color: 0x66FFEB3B); // Textmarker-artig
      line(c, 0.2, 0.4, 0.35);
      final all = c.annotations.visibleStrokesOn(1);
      final ids = SelectionIds(strokes: {for (final s in all) s.id});
      c.recolorSelection(ids, 0xFFD32F2F);
      expect(c.annotations[all[0].id]!.color, 0x66D32F2F);
      expect(c.annotations[all[1].id]!.color, 0xFFD32F2F);
      c.undo();
      expect(c.annotations[all[0].id]!.color, 0x66FFEB3B);

      c.deleteSelection(ids);
      expect(c.annotations.visibleStrokesOn(1), isEmpty);
      c.undo();
      expect(c.annotations.visibleStrokesOn(1).length, 2, reason: 'ein Rückgängig bringt beide zurück');
      c.dispose();
    });

    test('Kopieren und in ein anderes Stück einfügen: neue IDs, gleiche Stelle', () {
      final a = InkController(pdfPath: '${dir.path}/a.pdf');
      final b = InkController(pdfPath: '${dir.path}/b.pdf');
      line(a, 0.2, 0.4, 0.3);
      a.addText(page: 1, x: 0.25, y: 0.2, text: 'rit.', size: 0.03, color: 0xFF000000);
      final src = a.annotations.visibleStrokesOn(1).single;
      final clip = a.copySelection(SelectionIds(strokes: {src.id}, texts: {a.annotations.visibleTextsOn(1).single.id}));
      final pasted = b.paste(clip, 3);
      expect(pasted.count, 2);
      final copy = b.annotations.visibleStrokesOn(3).single;
      expect(copy.id, isNot(src.id));
      expect(copy.points.first.x, src.points.first.x);
      expect(b.annotations.visibleTextsOn(3).single.text, 'rit.');
      b.undo();
      expect(b.annotations.visibleStrokesOn(3), isEmpty);
      a.dispose();
      b.dispose();
    });
  });

  group('Auswahl mit der Werkzeug-Steuerung', () {
    testWidgets('Kopieren, Einfügen versetzt, Duplizieren, Werkzeugwechsel hebt auf', (t) async {
      final tools = await t.runAsync(() => makeTools(dir)) as ToolController;
      final c = InkController(pdfPath: '${dir.path}/x.pdf');
      line(c, 0.2, 0.4, 0.3);
      final s = c.annotations.visibleStrokesOn(1).single;
      tools.setMode(ToolMode.lasso);
      tools.select(InkSelection(c, 1, SelectionIds(strokes: {s.id})));
      tools.copySelection();
      tools.pasteInto(c, 1);
      final strokes = c.annotations.visibleStrokesOn(1);
      expect(strokes.length, 2);
      expect(strokes.last.points.first.x, closeTo(0.22, 1e-9), reason: 'auf derselben Seite leicht versetzt');
      expect(tools.selection.value!.ids.strokes, {strokes.last.id}, reason: 'Eingefügtes ist ausgewählt');

      tools.pasteInto(c, 2);
      expect(c.annotations.visibleStrokesOn(2).single.points.first.x, closeTo(0.2, 1e-9));

      tools.duplicateSelection();
      expect(c.annotations.visibleStrokesOn(2).length, 2);

      tools.setMode(ToolMode.pen);
      expect(tools.selection.value, isNull);
      await t.runAsync(() => tools.flush());
      c.dispose();
    });
  });

  group('Lasso auf der Seite', () {
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

    Future<void> drag(WidgetTester t, List<Offset> path, {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
      final g = await t.startGesture(path.first, kind: kind);
      for (final p in path.skip(1)) {
        await g.moveTo(p);
      }
      await g.up();
      await t.pump();
    }

    testWidgets('Einkreisen wählt aus, Ziehen verschiebt, Griff vergrössert', (t) async {
      await pump(t);
      line(c, 0.2, 0.4, 0.3); // Pixel: x 80..160, y 180
      line(c, 0.2, 0.4, 0.8); // weiter unten, nicht im Lasso
      tools.setMode(ToolMode.lasso);
      await t.pump();

      await drag(t, const [Offset(60, 150), Offset(180, 150), Offset(180, 210), Offset(60, 210), Offset(60, 152)]);
      final sel = tools.selection.value!;
      final top = c.annotations.visibleStrokesOn(1).first;
      expect(sel.ids.strokes, {top.id});

      // In der Auswahl ziehen → verschieben (um 40 px nach rechts, 60 px nach unten)
      await drag(t, const [Offset(120, 180), Offset(140, 210), Offset(160, 240)]);
      final moved = c.annotations[top.id]!;
      expect(moved.points.first.x, closeTo(0.3, 0.002));
      expect(moved.points.first.y, closeTo(0.4, 0.002));
      expect(tools.selection.value, isNotNull, reason: 'Auswahl bleibt bestehen');

      // Am Griff unten rechts ziehen → doppelt so gross
      final r = moved.bounds;
      final pad = 0.004 * 400 * 0.85 + 6;
      final handle = Offset(r.right * 400 + pad, r.bottom * 600 + pad);
      final w = (r.right - r.left) * 400 + 2 * (0.004 * 400 * 0.85);
      await drag(t, [handle, handle + Offset(w * 0.5, 0), handle + Offset(w, 0)]);
      final big = c.annotations[top.id]!;
      expect(big.points.last.x - big.points.first.x, greaterThan((r.right - r.left) * 1.6));

      // Daneben tippen hebt die Auswahl auf
      await drag(t, const [Offset(350, 550), Offset(351, 551)]);
      expect(tools.selection.value, isNull);

      // Finger wählt nie aus
      await drag(t, const [
        Offset(60, 150),
        Offset(180, 150),
        Offset(180, 210),
        Offset(60, 210),
      ], kind: PointerDeviceKind.touch);
      expect(tools.selection.value, isNull);
      await t.runAsync(() => tools.flush());
      c.dispose();
    });
  });
}
