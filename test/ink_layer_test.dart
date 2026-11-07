import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/ink_layer.dart';

void main() {
  late Directory dir;
  late InkController c;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('volti_ink');
    c = InkController(pdfPath: '${dir.path}/x.pdf');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(WidgetTester t) => t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: SizedBox(width: 400, height: 600, child: InkLayer(page: 1, controller: c))),
      ));

  Future<void> drawLine(WidgetTester t, PointerDeviceKind kind, {int buttons = kPrimaryButton}) async {
    final center = t.getCenter(find.byType(InkLayer));
    final g = await t.startGesture(center, kind: kind, buttons: buttons);
    for (var i = 1; i <= 5; i++) {
      await g.moveBy(const Offset(10, 4));
    }
    await g.up();
    await t.pump();
  }

  testWidgets('Stift zeichnet, Finger nicht (Handballen)', (t) async {
    await pump(t);
    c.setMode(ToolMode.pen);

    await drawLine(t, PointerDeviceKind.touch);
    expect(c.annotations.visibleStrokesOn(1), isEmpty);

    await drawLine(t, PointerDeviceKind.stylus);
    final strokes = c.annotations.visibleStrokesOn(1);
    expect(strokes.length, 1);
    expect(strokes.first.points.length, 6);
    // Normierte Koordinaten: Mitte der Seite ≈ 0.5 / 0.5
    expect(strokes.first.points.first.x, closeTo(0.5, 0.01));
    expect(strokes.first.points.first.y, closeTo(0.5, 0.01));
    c.dispose();
  });

  testWidgets('Im Lese-Modus zeichnet der Stift nicht', (t) async {
    await pump(t);
    await drawLine(t, PointerDeviceKind.stylus);
    expect(c.annotations.visibleStrokesOn(1), isEmpty);
    c.dispose();
  });

  testWidgets('Radierer-Ende des Stifts löscht – auch im Lese-Modus', (t) async {
    await pump(t);
    c.setMode(ToolMode.pen);
    await drawLine(t, PointerDeviceKind.stylus);
    expect(c.annotations.visibleStrokesOn(1).length, 1);

    c.setMode(ToolMode.read);
    await drawLine(t, PointerDeviceKind.invertedStylus);
    expect(c.annotations.visibleStrokesOn(1), isEmpty);
    c.dispose();
  });

  testWidgets('Textmarker erzeugt einen Textmarker-Strich', (t) async {
    await pump(t);
    c.setMode(ToolMode.highlighter);
    await drawLine(t, PointerDeviceKind.mouse);
    expect(c.annotations.visibleStrokesOn(1).single.color, InkController.highlighterColor);
    c.dispose();
  });
}
