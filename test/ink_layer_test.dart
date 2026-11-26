import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/annotation_layer.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/ink_layer.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

void main() {
  late Directory dir;
  late InkController c;
  late ToolController tools;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('volti_ink');
    c = InkController(pdfPath: '${dir.path}/x.pdf');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(WidgetTester t) async {
    tools = await t.runAsync(() => makeTools(dir)) as ToolController;
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: InkLayer(page: 1, controller: c, tools: tools),
          ),
        ),
      ),
    );
  }

  Future<void> drawLine(
    WidgetTester t,
    PointerDeviceKind kind, {
    int buttons = kPrimaryButton,
    double step = 10,
  }) async {
    final center = t.getCenter(find.byType(InkLayer));
    final g = await t.startGesture(center, kind: kind, buttons: buttons);
    for (var i = 1; i <= 5; i++) {
      await g.moveBy(Offset(step, step * 0.4));
    }
    await g.up();
    await t.pump();
  }

  testWidgets('Beim Bearbeiten: Stift zeichnet, Finger nicht (Handballen)', (t) async {
    await pump(t);
    tools.setMode(ToolMode.pen);

    await drawLine(t, PointerDeviceKind.touch);
    expect(c.annotations.visibleStrokesOn(1), isEmpty);

    await drawLine(t, PointerDeviceKind.stylus);
    final strokes = c.annotations.visibleStrokesOn(1);
    expect(strokes.length, 1);
    expect(strokes.first.points.length, 6);
    expect(strokes.first.color, tools.pen.color);
    // Normierte Koordinaten: Mitte der Seite ≈ 0.5 / 0.5
    expect(strokes.first.points.first.x, closeTo(0.5, 0.01));
    expect(strokes.first.points.first.y, closeTo(0.5, 0.01));
    c.dispose();
  });

  testWidgets('Verschieben: Strich anfassen und ziehen, danach nichts ausgewählt', (t) async {
    await pump(t);
    c.addStroke(
      page: 1,
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 0.005,
      points: const [InkPoint(0.4, 0.5, 0.5), InkPoint(0.6, 0.5, 0.5)],
    );
    tools.setMode(ToolMode.move);
    await t.pump();
    final center = t.getCenter(find.byType(InkLayer));
    // Daneben angefasst: nichts passiert.
    var g = await t.startGesture(center + const Offset(0, 120), kind: PointerDeviceKind.stylus);
    await g.moveBy(const Offset(40, 0));
    await g.up();
    expect(c.annotations.visibleStrokesOn(1).single.points.first.x, closeTo(0.4, 0.001));
    // Am Strich anfassen und 40 px nach rechts, 60 px nach unten ziehen.
    g = await t.startGesture(center, kind: PointerDeviceKind.stylus);
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(10, 15));
    }
    await g.up();
    await t.pump();
    final p0 = c.annotations.visibleStrokesOn(1).single.points.first;
    expect(p0.x, closeTo(0.4 + 40 / 400, 0.002));
    expect(p0.y, closeTo(0.5 + 60 / 600, 0.002));
    expect(tools.selection.value, isNull);
    // Ein Schritt zurück: wieder am alten Ort.
    c.undo();
    expect(c.annotations.visibleStrokesOn(1).single.points.first.x, closeTo(0.4, 0.001));
    c.dispose();
  });

  testWidgets('Spielansicht: Stift ziehen zeichnet sofort', (t) async {
    await pump(t);
    expect(tools.mode, ToolMode.read);
    await drawLine(t, PointerDeviceKind.stylus);
    expect(c.annotations.visibleStrokesOn(1).length, 1);
    c.dispose();
  });

  testWidgets('Spielansicht: kurzes Antippen mit dem Stift hinterlässt keinen Punkt', (t) async {
    await pump(t);
    await drawLine(t, PointerDeviceKind.stylus, step: 1); // nur 5 px bewegt
    expect(c.annotations.visibleStrokesOn(1), isEmpty);
    c.dispose();
  });

  testWidgets('Spielansicht: Maus zeichnet nicht; "sofort zeichnen" lässt sich abschalten', (t) async {
    await pump(t);
    await drawLine(t, PointerDeviceKind.mouse);
    expect(c.annotations.visibleStrokesOn(1), isEmpty);

    await t.runAsync(() => tools.setInstantPen(false));
    await drawLine(t, PointerDeviceKind.stylus);
    expect(c.annotations.visibleStrokesOn(1), isEmpty);
    c.dispose();
  });

  testWidgets('Radierer-Ende des Stifts löscht – auch in der Spielansicht', (t) async {
    await pump(t);
    tools.setMode(ToolMode.pen);
    await drawLine(t, PointerDeviceKind.stylus);
    expect(c.annotations.visibleStrokesOn(1).length, 1);

    tools.setMode(ToolMode.read);
    await drawLine(t, PointerDeviceKind.invertedStylus);
    expect(c.annotations.visibleStrokesOn(1), isEmpty);
    c.dispose();
  });

  testWidgets('Textmarker erzeugt einen Textmarker-Strich (auch mit Maus)', (t) async {
    await pump(t);
    tools.setMode(ToolMode.highlighter);
    await drawLine(t, PointerDeviceKind.mouse);
    expect(c.annotations.visibleStrokesOn(1).single.tool, InkTool.highlighter);
    c.dispose();
  });

  testWidgets('Radierer "teilweise" trennt einen Strich, "ganze Elemente" löscht ihn', (t) async {
    await pump(t);
    final topLeft = t.getTopLeft(find.byType(InkLayer));
    // waagrechter Strich quer über die Seite
    c.addStroke(
      page: 1,
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 0.003,
      points: [for (var i = 1; i <= 9; i++) InkPoint(i / 10, 0.5, 0.5)],
    );
    await t.pump();

    tools.setEraserPartial(true);
    tools.setMode(ToolMode.eraser);
    final g = await t.startGesture(topLeft + const Offset(200, 290), kind: PointerDeviceKind.stylus);
    await g.moveTo(topLeft + const Offset(200, 310));
    await g.up();
    await t.pump();
    final pieces = c.annotations.visibleStrokesOn(1);
    expect(pieces.length, 2, reason: 'Strich in der Mitte getrennt');
    expect(pieces.every((s) => s.points.every((p) => (p.x - 0.5).abs() > 0.02)), isTrue);

    tools.setEraserPartial(false);
    final g2 = await t.startGesture(topLeft + const Offset(80, 300), kind: PointerDeviceKind.invertedStylus);
    await g2.moveBy(const Offset(2, 0));
    await g2.up();
    await t.pump();
    expect(c.annotations.visibleStrokesOn(1).length, 1, reason: 'linkes Stück ganz gelöscht (Radierer-Ende)');
    await t.runAsync(() => tools.flush());
    c.dispose();
  });

  testWidgets('Radierer "teilweise" schneidet aus einer gefüllten Fläche nur den Kreis heraus', (t) async {
    await pump(t);
    final topLeft = t.getTopLeft(find.byType(InkLayer));
    // Weisses Rechteck mit schwarzem Rand (x 0.2–0.8, y 0.3–0.7)
    const corners = [(0.2, 0.3), (0.8, 0.3), (0.8, 0.7), (0.2, 0.7), (0.2, 0.3)];
    c.addStroke(
      page: 1,
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 0.003,
      fill: 0xFFFFFFFF,
      points: [for (final (x, y) in corners) InkPoint(x, y, 0.5)],
    );
    await t.pump();
    tools.setEraserPartial(true);
    tools.setEraserRadius(10);
    tools.setMode(ToolMode.eraser);
    // Mitten in der Fläche radieren: ein Loch
    final g = await t.startGesture(topLeft + const Offset(200, 300), kind: PointerDeviceKind.stylus);
    await g.moveBy(const Offset(1, 0));
    await g.up();
    await t.pump();
    final all = c.annotations.visibleStrokesOn(1);
    final areas = all.where((s) => s.fill != null).toList();
    final outline = all.where((s) => s.fill == null).toList();
    expect(areas, isNotEmpty, reason: 'die Fläche ist nicht ganz weg');
    expect(outline.single.color, 0xFF000000, reason: 'der Rand bleibt ganz');
    bool covered(Offset p) => areas.any(
      (s) => (Path()..addPolygon([for (final q in s.points) Offset(q.x * 400, q.y * 600)], true)).contains(p),
    );
    expect(covered(const Offset(200, 300)), isFalse, reason: 'in der Mitte ein Loch');
    expect(covered(const Offset(200, 330)), isTrue, reason: 'daneben bleibt die Fläche');
    expect(covered(const Offset(100, 250)), isTrue);
    expect(covered(const Offset(300, 400)), isTrue);
    expect(areas.every((s) => s.color == 0xFFFFFFFF), isTrue, reason: 'Flächen ohne schwarzen Rand');
    // Rückgängig holt das Rechteck zurück
    c.undo();
    expect(c.annotations.visibleStrokesOn(1).single.fill, 0xFFFFFFFF);
    await t.runAsync(() => tools.flush());
    c.dispose();
  });

  testWidgets('Strich-Bild: Neues wird dazugemalt, Radiertes verschwindet', (t) async {
    await pump(t);
    void line(double y) => c.addStroke(
      page: 1,
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 0.01,
      points: [InkPoint(0.2, y, 0.5), InkPoint(0.8, y, 0.5)],
    );

    Future<int> alphaAt(double x, double y) async {
      // Warten, bis das Bild im Hintergrund fertig ist.
      // Neues kommt erst nach einer kurzen Pause ins Bild (beim Schreiben).
      await t.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      final img = (t.state(find.byType(InkLayer)) as dynamic).debugImageOf('layer/standard') as ui.Image;
      final bytes = (await t.runAsync(() => img.toByteData()))!;
      final px = (x * img.width).round(), py = (y * img.height).round();
      return bytes.getUint8((py * img.width + px) * 4 + 3);
    }

    line(0.25);
    await t.pump();
    expect(await alphaAt(0.5, 0.25), greaterThan(200));
    line(0.75);
    await t.pump();
    expect(await alphaAt(0.5, 0.75), greaterThan(200), reason: 'neuer Strich im Bild');
    expect(await alphaAt(0.5, 0.25), greaterThan(200), reason: 'alter Strich bleibt');

    c.eraseStrokes([c.annotations.visibleStrokesOn(1).first]);
    await t.pump();
    expect(await alphaAt(0.5, 0.25), 0, reason: 'radierter Strich ist weg');
    expect(await alphaAt(0.5, 0.75), greaterThan(200));
    c.dispose();
  });

  testWidgets('Leuchtstift liegt immer hinter allem anderen', (t) async {
    await pump(t);
    final hl = c.addLayer('Oben');
    c.addStroke(
      page: 1,
      tool: InkTool.highlighter,
      color: 0x66FFEB3B,
      width: 0.03,
      points: [InkPoint(0.2, 0.5, 0.5), InkPoint(0.8, 0.5, 0.5)],
    );
    c.activeLayer = kDefaultLayer;
    c.addStroke(
      page: 1,
      tool: InkTool.pen,
      color: 0xFF1565C0,
      width: 0.005,
      points: [InkPoint(0.5, 0.2, 0.5), InkPoint(0.5, 0.8, 0.5)],
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(c.annotations[c.annotations.visibleStrokesOn(1).first.id]!.layer, hl, reason: 'bleibt auf seiner Ebene');
    // Das Leuchtstift-Bild kommt vor (= unter) allen Ebenen-Bildern.
    final layer = t.state(find.byType(InkLayer)) as dynamic;
    expect((layer.debugOrder as List<String>).first, 'highlights');
    expect(layer.debugImageOf('highlights'), isNotNull, reason: 'das Leuchtstift-Bild ist da');
    expect(layer.debugImageOf('layer/$kDefaultLayer'), isNotNull, reason: 'der Stift ist im Bild der Grund-Ebene');
    c.dispose();
  });
}
