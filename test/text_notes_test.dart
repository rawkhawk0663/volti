import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/text_note.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/ink_layer.dart';
import 'package:volti/features/viewer/text_layer.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

TextNote note(String id, String text, {DateTime? modified, bool deleted = false}) => TextNote(
  id: id,
  page: 1,
  x: 0.1,
  y: 0.2,
  text: text,
  size: 0.022,
  color: 0xFF000000,
  createdAt: DateTime.utc(2026, 1, 1),
  modifiedAt: modified,
  deleted: deleted,
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_text'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('Datenmodell', () {
    test('Speichern und Laden', () async {
      final pdf = '${dir.path}/x.pdf';
      await const SidecarStore().save(pdf, annotations: ScoreAnnotations(const [], [note('a', 'Bogen ab')]));
      final back = (await const SidecarStore().load(pdf)).annotations.visibleTextsOn(1);
      expect(back.single.text, 'Bogen ab');
      expect(back.single.x, closeTo(0.1, 1e-6));
    });

    test('Zusammenführen: jüngste Änderung gewinnt, gelöscht bleibt gelöscht', () {
      final a = ScoreAnnotations(const [], [note('n', 'alt'), note('m', 'bleibt')]);
      final b = ScoreAnnotations(const [], [
        note('n', 'neu', modified: DateTime.utc(2026, 2, 1)),
        note('m', 'bleibt', deleted: true, modified: DateTime.utc(2026, 1, 2)),
      ]);
      for (final m in [ScoreAnnotations.merge(a, b), ScoreAnnotations.merge(b, a)]) {
        expect(m.visibleTextsOn(1).map((t) => t.text), ['neu']);
      }
    });
  });

  group('Bearbeiten und Rückgängig', () {
    test('Hinzufügen, ändern, verschieben, löschen – alles rückgängig machbar', () {
      final c = InkController(pdfPath: '${dir.path}/x.pdf');
      final id = c.addText(page: 1, x: 0.5, y: 0.5, text: 'Atmen', size: 0.022, color: 0xFF000000)!;
      c.updateText(id, text: 'Atmen!');
      c.updateText(id, x: 0.6, y: 0.7);
      expect(c.annotations.text(id)!.x, 0.6);

      c.undo(); // verschieben
      expect(c.annotations.text(id)!.x, 0.5);
      c.undo(); // Text ändern
      expect(c.annotations.text(id)!.text, 'Atmen');
      c.redo();
      expect(c.annotations.text(id)!.text, 'Atmen!');

      c.deleteTexts(c.annotations.visibleTextsOn(1));
      expect(c.annotations.visibleTextsOn(1), isEmpty);
      c.undo(); // Löschen rückgängig → als Kopie zurück
      expect(c.annotations.visibleTextsOn(1).single.text, 'Atmen!');

      c.updateText(c.annotations.visibleTextsOn(1).single.id, text: '   ');
      expect(c.annotations.visibleTextsOn(1), isEmpty, reason: 'leerer Text löscht die Notiz');
      expect(c.addText(page: 1, x: 0, y: 0, text: '', size: 0.022, color: 0xFF000000), isNull);
      c.dispose();
    });
  });

  group('Bedienung', () {
    late InkController c;
    late ToolController tools;
    var editing = false;

    Future<void> pump(WidgetTester t) async {
      c = InkController(pdfPath: '${dir.path}/x.pdf');
      tools = await t.runAsync(() => makeTools(dir)) as ToolController;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InkLayer(page: 1, controller: c, tools: tools),
                    TextNotesLayer(page: 1, controller: c, tools: tools, onEditingChanged: (v) => editing = v),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Tippen, schreiben, Enter → Notiz an der getippten Stelle', (t) async {
      await pump(t);
      tools.setMode(ToolMode.text);
      await t.pump();
      final topLeft = t.getTopLeft(find.byType(TextNotesLayer));
      await t.tapAt(topLeft + const Offset(100, 300));
      await t.pumpAndSettle();
      expect(editing, isTrue);

      await t.enterText(find.byType(TextField), 'Bogen ab');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();

      final n = c.annotations.visibleTextsOn(1).single;
      expect(n.text, 'Bogen ab');
      expect(n.x, closeTo(0.25, 0.01));
      expect(n.y, closeTo(0.5, 0.01));
      expect(editing, isFalse);
      expect(find.text('Bogen ab'), findsOneWidget);
      c.dispose();
    });

    testWidgets('Esc bricht ab, ohne etwas anzulegen', (t) async {
      await pump(t);
      tools.setMode(ToolMode.text);
      await t.pump();
      await t.tapAt(t.getCenter(find.byType(TextNotesLayer)));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'weg damit');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(c.annotations.visibleTextsOn(1), isEmpty);
      c.dispose();
    });

    testWidgets('Notizen sind im Lese-Modus sichtbar; der Radierer löscht sie', (t) async {
      await pump(t);
      c.addText(page: 1, x: 0.4, y: 0.4, text: 'cresc.', size: 0.022, color: 0xFF000000);
      await t.pump();
      expect(find.text('cresc.'), findsOneWidget);

      tools.setMode(ToolMode.eraser);
      await t.pump();
      final pos = t.getTopLeft(find.byType(TextNotesLayer)) + const Offset(400 * 0.4 + 5, 600 * 0.4 + 5);
      final g = await t.startGesture(pos, kind: PointerDeviceKind.stylus);
      await g.moveBy(const Offset(2, 0));
      await g.up();
      await t.pump();
      expect(c.annotations.visibleTextsOn(1), isEmpty);
      c.dispose();
    });
  });
}
