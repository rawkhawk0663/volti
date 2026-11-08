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
    tools.select(tools.presets.first);

    await drawLine(t, PointerDeviceKind.touch);
    expect(c.annotations.visibleStrokesOn(1), isEmpty);

    await drawLine(t, PointerDeviceKind.stylus);
    final strokes = c.annotations.visibleStrokesOn(1);
    expect(strokes.length, 1);
    expect(strokes.first.points.length, 6);
    expect(strokes.first.color, tools.presets.first.color);
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
    tools.select(tools.presets.first);
    await drawLine(t, PointerDeviceKind.stylus);
    expect(c.annotations.visibleStrokesOn(1).length, 1);

    tools.setMode(ToolMode.read);
    await drawLine(t, PointerDeviceKind.invertedStylus);
    expect(c.annotations.visibleStrokesOn(1), isEmpty);
    c.dispose();
  });

  testWidgets('Textmarker-Vorlage erzeugt einen Textmarker-Strich (auch mit Maus)', (t) async {
    await pump(t);
    tools.selectFirst(InkTool.highlighter);
    await drawLine(t, PointerDeviceKind.mouse);
    expect(c.annotations.visibleStrokesOn(1).single.tool, InkTool.highlighter);
    c.dispose();
  });
}
