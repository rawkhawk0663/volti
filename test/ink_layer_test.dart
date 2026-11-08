import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
