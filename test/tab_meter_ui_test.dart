import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/tab_block.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/tab_layer.dart';
import 'package:volti/features/viewer/tool_controller.dart';
import 'package:volti/features/viewer/tool_popover.dart';

import 'helpers/tools.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_meterui'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('Im Fenster: Taktart nur für den Takt mit dem Cursor, Ebene „TABS“ angezeigt', (t) async {
    final tools = await t.runAsync(() => makeTools(dir)) as ToolController;
    final ink = InkController(pdfPath: '${dir.path}/x.pdf');
    // Zwei Ebenen, eine andere ist aktiv
    ink.addLayer('Fingersätze');
    tools.setMode(ToolMode.tab);
    t.view.physicalSize = const Size(1200, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 800,
                height: 1100,
                child: TabLayer(page: 1, controller: ink, tools: tools, onEditingChanged: (_) {}),
              ),
              SizedBox(
                width: ToolPopover.width,
                height: 1100,
                child: ListenableBuilder(
                  listenable: tools,
                  builder: (context, _) => ToolPopover(tools: tools, ink: ink, onDrag: (_) {}),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Ebene: TABS'), findsOneWidget, reason: 'Tabulaturen landen immer auf „TABS“');

    final g = await t.startGesture(const Offset(100, 200), kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(700, 203));
    await g.up();
    await t.pump();
    final id = ink.annotations.visibleTabsOn(1).single.id;
    for (var i = 0; i < 8; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.digit3);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    for (var i = 0; i < 3; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await t.pump();
    expect(find.text('Nur Takt 2'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, '2/4'));
    await t.pump();
    final tab = ink.annotations.tab(id)!;
    expect(tab.meter, '4/4', reason: 'die Zeile bleibt 4/4');
    expect([for (final b in tab.beats) if (b.bar) b.meter], ['2/4']);
    expect(measureLengths(tab.beats, tab.measure), [1.0, 0.5]);

    // Ganze Zeile: Taktart vorne, Taktstriche neu
    await t.tap(find.text('Ganze Zeile'));
    await t.pump();
    await t.tap(find.widgetWithText(ChoiceChip, '3/4'));
    await t.pump();
    expect(ink.annotations.tab(id)!.meter, '3/4');
    ink.dispose();
    await t.runAsync(() => tools.flush());
  });
}
