import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/ink_layer.dart';
import 'package:volti/features/viewer/ruler_overlay.dart';
import 'package:volti/features/viewer/tool_controller.dart';
import 'package:volti/features/viewer/zoom_area.dart';

import 'helpers/tools.dart';

void main() {
  late Directory dir;
  late InkController c;
  late ToolController tools;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('volti_ruler_stroke');
    c = InkController(pdfPath: '${dir.path}/x.pdf');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  for (final mode in [ToolMode.pen, ToolMode.highlighter]) {
    testWidgets('Strich am Lineal bleibt liegen ($mode)', (t) async {
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
      final center = t.getCenter(find.byType(InkLayer));
      tools.toggleRuler();
      tools.moveRuler(center, 0);
      tools.setMode(mode);
      await t.pump();

      // Knapp unter der unteren Kante des Lineals entlang ziehen, leicht wackelig.
      final g = await t.startGesture(center + const Offset(-120, 40), kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 12; i++) {
        await g.moveBy(Offset(20, i.isEven ? 3 : -3));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pump();

      final strokes = c.annotations.visibleStrokesOn(1);
      expect(strokes, hasLength(1), reason: 'Strich gespeichert');
      final ys = strokes.first.points.map((p) => p.y).toSet();
      expect(ys, hasLength(1), reason: 'ganz gerade');

      // Ist er auch im Bild der Seite?
      await t.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 20; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      final part = mode == ToolMode.highlighter ? 'highlights' : 'layer/standard';
      final img = (t.state(find.byType(InkLayer)) as dynamic).debugImageOf(part) as ui.Image?;
      expect(img, isNotNull, reason: 'Bild vorhanden');
      final bytes = (await t.runAsync(() => img!.toByteData()))!;
      final y = (ys.first * img!.height).round(), x = (0.5 * img.width).round();
      expect(bytes.getUint8((y * img.width + x) * 4 + 3), greaterThan(50), reason: 'im Bild sichtbar');
      c.dispose();
    });
  }

  testWidgets('Mit Finger am Lineal und Zoom-Fläche: Strich bleibt', (t) async {
    tools = await t.runAsync(() => makeTools(dir)) as ToolController;
    final zoom = PageZoom();
    await t.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: ZoomArea(
                zoom: zoom,
                tools: tools,
                onFingerSwipe: (_) {},
                child: Center(
                  child: SizedBox(
                    width: 400,
                    height: 600,
                    child: InkLayer(page: 1, controller: c, tools: tools),
                  ),
                ),
              ),
            ),
            Positioned.fill(child: RulerOverlay(tools: tools)),
          ],
        ),
      ),
    );
    final center = t.getCenter(find.byType(InkLayer));
    tools.toggleRuler();
    tools.moveRuler(center, 0);
    tools.setMode(ToolMode.pen);
    await t.pump();

    final finger = await t.startGesture(center + const Offset(150, 0), kind: PointerDeviceKind.touch, pointer: 5);
    await t.pump();
    final g = await t.startGesture(center + const Offset(-120, 40), kind: PointerDeviceKind.stylus, pointer: 9);
    for (var i = 1; i <= 12; i++) {
      await g.moveBy(Offset(20, i.isEven ? 3 : -3));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pump();
    await finger.up();
    await t.pump(const Duration(milliseconds: 600));
    expect(c.annotations.visibleStrokesOn(1), hasLength(1));
    expect(find.byType(InkLayer), findsOneWidget);
    zoom.dispose();
    c.dispose();
  });
}
