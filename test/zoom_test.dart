import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/features/viewer/tool_controller.dart';
import 'package:volti/features/viewer/zoom_area.dart';

import 'helpers/tools.dart';

void main() {
  late Directory dir;
  late ToolController tools;
  late PageZoom zoom;

  final taps = <Offset>[];

  Future<void> pump(WidgetTester t) async {
    taps.clear();
    dir = Directory.systemTemp.createTempSync('volti_zoom');
    tools = await t.runAsync(() => makeTools(dir)) as ToolController;
    zoom = PageZoom();
    await t.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: ZoomArea(
            zoom: zoom,
            tools: tools,
            onTap: (p, _) => taps.add(p),
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
  }

  tearDown(() {
    zoom.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<void> pinch(WidgetTester t, {double spread = 100}) async {
    final a = await t.createGesture(kind: PointerDeviceKind.touch, pointer: 1);
    final b = await t.createGesture(kind: PointerDeviceKind.touch, pointer: 2);
    await a.down(const Offset(350, 300));
    await b.down(const Offset(450, 300));
    for (var i = 1; i <= 5; i++) {
      await a.moveTo(Offset(350 - spread * i / 5, 300));
      await b.moveTo(Offset(450 + spread * i / 5, 300));
    }
    await a.up();
    await b.up();
  }

  testWidgets('Zwei Finger auseinander: vergrössert, Mitte bleibt', (t) async {
    await pump(t);
    await pinch(t);
    expect(zoom.scale, closeTo(3, 0.01));
    // Der Punkt zwischen den Fingern (400, 300) bleibt an seinem Platz.
    final m = zoom.matrix.value;
    final p = MatrixUtils.transformPoint(m, const Offset(400, 300));
    expect(p.dx, closeTo(400, 0.5));
    expect(p.dy, closeTo(300, 0.5));
    // Nach der Geste wird scharf gerendert.
    await t.pump(const Duration(milliseconds: 400));
    expect(zoom.renderScale.value, 3);
  });

  testWidgets('Nicht kleiner als die ganze Seite, nicht über den Rand', (t) async {
    await pump(t);
    await pinch(t, spread: -40);
    expect(zoom.scale, 1);
    await pinch(t);
    final finger = await t.createGesture(kind: PointerDeviceKind.touch, pointer: 3);
    await finger.down(const Offset(400, 300));
    await finger.moveBy(const Offset(2000, 2000));
    await finger.up();
    final topLeft = MatrixUtils.transformPoint(zoom.matrix.value, Offset.zero);
    expect(topLeft, Offset.zero);
    await t.pump(const Duration(milliseconds: 400));
  });

  testWidgets('Stift in der Nähe: Finger (Handballen) zoomen nicht', (t) async {
    await pump(t);
    final pen = await t.createGesture(kind: PointerDeviceKind.stylus, pointer: 9);
    await pen.addPointer(location: const Offset(100, 100));
    await pen.moveTo(const Offset(120, 110)); // schwebt darüber
    await pinch(t);
    expect(zoom.scale, 1);
    await pen.removePointer();
  });

  testWidgets('Antippen wird gemeldet, auch vergrössert – Zoomen nicht', (t) async {
    await pump(t);
    await pinch(t);
    expect(taps, isEmpty, reason: 'zwei Finger sind kein Antippen');
    await t.pump(const Duration(milliseconds: 400));
    final f = await t.createGesture(kind: PointerDeviceKind.touch, pointer: 5);
    await f.down(const Offset(400, 300));
    await f.moveBy(const Offset(3, 2));
    await f.up();
    expect(taps, [const Offset(403, 302)]);
  });
}
