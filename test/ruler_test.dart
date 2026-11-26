import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/ink_layer.dart';
import 'package:volti/features/viewer/ruler_overlay.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_ruler'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ToolController> pump(WidgetTester t) async {
    final tools = await t.runAsync(() => makeTools(dir)) as ToolController;
    tools.toggleRuler();
    tools.moveRuler(const Offset(400, 300), 0);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RulerOverlay(tools: tools)),
      ),
    );
    return tools;
  }

  testWidgets('Mit sichtbarem Lineal zeichnet der Stift darunter (auch an der Kante)', (t) async {
    final tools = await t.runAsync(() => makeTools(dir)) as ToolController;
    tools.toggleRuler();
    tools.moveRuler(const Offset(400, 300), 0);
    tools.setMode(ToolMode.pen);
    final ink = InkController(pdfPath: '${dir.path}/x.pdf');
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: InkLayer(page: 1, controller: ink, tools: tools),
              ),
              // Wie in der Notenansicht: das Lineal liegt über der Seite.
              Positioned.fill(child: RulerOverlay(tools: tools)),
            ],
          ),
        ),
      ),
    );
    // Irgendwo auf der Seite
    var pen = await t.startGesture(const Offset(100, 100), kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(40, 30));
    await pen.moveBy(const Offset(40, 30));
    await pen.up();
    await t.pump();
    expect(ink.annotations.visibleStrokesOn(1).length, 1, reason: 'Stift zeichnet trotz Lineal');
    // Nahe der Kante: gerade daran entlang
    pen = await t.startGesture(
      const Offset(300, 300 + ToolController.rulerThickness / 2 + 10),
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveBy(const Offset(50, 6));
    await pen.moveBy(const Offset(50, -4));
    await pen.up();
    await t.pump();
    final s = ink.annotations.visibleStrokesOn(1).last;
    final ys = {for (final p in s.points) (p.y * 1000).round()};
    expect(ys.length, 1, reason: 'alle Punkte auf der Kante: $ys');
    await t.runAsync(() => tools.flush());
    ink.dispose();
  });

  testWidgets('Ein Finger verschiebt, der Stift nie', (t) async {
    final tools = await pump(t);
    final g = await t.startGesture(const Offset(450, 300), kind: PointerDeviceKind.touch);
    await g.moveBy(const Offset(30, 40));
    await g.moveBy(const Offset(20, 10));
    await g.up();
    expect(tools.rulerCenter, const Offset(450, 350));
    expect(tools.rulerAngle, 0);

    final pen = await t.startGesture(const Offset(450, 350), kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(100, 100));
    await pen.up();
    expect(tools.rulerCenter, const Offset(450, 350), reason: 'Stift bewegt das Lineal nicht');

    // Neben dem Lineal passiert nichts.
    final miss = await t.startGesture(const Offset(100, 100), kind: PointerDeviceKind.touch);
    await miss.moveBy(const Offset(50, 0));
    await miss.up();
    expect(tools.rulerCenter, const Offset(450, 350));
    await t.runAsync(() => tools.flush());
  });

  testWidgets('Zwei Finger drehen das Lineal wie unter echten Fingern', (t) async {
    final tools = await pump(t);
    // Linker Finger hält bei (300,300), rechter Finger wandert im Kreis um ihn herum nach unten.
    final hold = await t.startGesture(const Offset(300, 300), kind: PointerDeviceKind.touch, pointer: 1);
    final turn = await t.startGesture(const Offset(500, 300), kind: PointerDeviceKind.touch, pointer: 2);
    for (var i = 1; i <= 10; i++) {
      final a = i / 10 * math.pi / 6; // bis 30°
      await turn.moveTo(Offset(300 + 200 * math.cos(a), 300 + 200 * math.sin(a)));
    }
    expect(tools.rulerAngle, closeTo(math.pi / 6, 1e-6));
    // Mitte (400,300) hat sich um den haltenden Finger mitgedreht.
    expect(tools.rulerCenter!.dx, closeTo(300 + 100 * math.cos(math.pi / 6), 1e-6));
    expect(tools.rulerCenter!.dy, closeTo(300 + 100 * math.sin(math.pi / 6), 1e-6));
    await turn.up();
    await hold.up();
    expect(tools.rulerRecentlyUsed, isTrue, reason: 'kurz danach blättert ein Antippen nicht um');

    // Nahe 90° rastet es ein.
    tools.moveRuler(const Offset(400, 300), math.pi / 2 - 0.05);
    final a = await t.startGesture(const Offset(400, 300), kind: PointerDeviceKind.touch, pointer: 3);
    final b = await t.startGesture(const Offset(400, 500), kind: PointerDeviceKind.touch, pointer: 4);
    await b.moveTo(Offset(400 - 200 * math.sin(0.02), 300 + 200 * math.cos(0.02)));
    expect(tools.rulerAngle, closeTo(math.pi / 2, 1e-9));
    await a.up();
    await b.up();
    await t.runAsync(() => tools.flush());
  });

  testWidgets('Mausrad dreht das Lineal, wenn der Zeiger darauf liegt', (t) async {
    final tools = await pump(t);
    final mouse = TestPointer(9, PointerDeviceKind.mouse);
    // Daneben: nichts
    await t.sendEventToBinding(mouse.hover(const Offset(400, 100)));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    expect(tools.rulerAngle, 0);
    // Darauf: 3° pro Raste
    await t.sendEventToBinding(mouse.hover(const Offset(420, 300)));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    expect(tools.rulerAngle, closeTo(3 * math.pi / 180, 1e-9));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    expect(tools.rulerAngle, closeTo(-3 * math.pi / 180, 1e-9));
    await t.pump(const Duration(seconds: 2));
    await t.runAsync(() => tools.flush());
  });
}
