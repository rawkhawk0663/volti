import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/ink/text_note.dart';
import 'package:volti/core/ink/tool_settings.dart';
import 'package:volti/core/sync/sync_engine.dart';
import 'package:volti/core/sync/sync_store.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_tools'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('Werkzeug wählen', () {
    test('Bearbeiten startet mit dem zuletzt benutzten Werkzeug', () async {
      final tools = await makeTools(dir);
      tools.startEditing();
      expect(tools.mode, ToolMode.pen);
      tools.tapTool(ToolMode.text);
      tools.finishEditing();
      expect(tools.mode, ToolMode.read);
      tools.startEditing();
      expect(tools.mode, ToolMode.text);
    });

    test('Aktives Werkzeug nochmals antippen wählt es ab (Fenster verschwindet)', () async {
      final tools = await makeTools(dir);
      tools.startEditing();
      tools.tapTool(ToolMode.highlighter);
      expect(tools.mode, ToolMode.highlighter);
      tools.tapTool(ToolMode.highlighter);
      expect(tools.mode, ToolMode.none);
      expect(tools.editing, isTrue, reason: 'bleibt im Bearbeiten-Modus');
    });

    test('Gezeichnet wird mit Textmarker nur im Textmarker-Modus, sonst mit dem Stift', () async {
      final tools = await makeTools(dir);
      expect(tools.strokeStyle.tool, InkTool.pen); // Spielansicht: Stift
      tools.setMode(ToolMode.highlighter);
      expect(tools.strokeStyle.tool, InkTool.highlighter);
    });
  });

  group('Einstellungen und Favoriten', () {
    test('Favorit speichern, anwenden, entfernen – bleibt gespeichert', () async {
      final tools = await makeTools(dir);
      await tools.load();
      final before = tools.favoritesFor(InkTool.pen).length;

      tools.setPen(tools.pen.copyWith(color: 0xFF6A1B9A, width: 0.005));
      tools.addCurrentAsFavorite(InkTool.pen);
      tools.addCurrentAsFavorite(InkTool.pen); // doppelt → nicht nochmals
      expect(tools.favoritesFor(InkTool.pen).length, before + 1);

      tools.applyFavorite(tools.favoritesFor(InkTool.pen).first);
      expect(tools.pen.color, isNot(0xFF6A1B9A));
      await tools.flush();

      final again = await makeTools(dir);
      await again.load();
      expect(again.favoritesFor(InkTool.pen).any((f) => f.color == 0xFF6A1B9A && f.width == 0.005), isTrue);
      again.removeFavorite(again.favoritesFor(InkTool.pen).last);
      expect(again.favoritesFor(InkTool.pen).length, before);
    });

    test('Text-Stil mit Hintergrund und Text-Favoriten', () async {
      final tools = await makeTools(dir);
      await tools.load();
      tools.setTextStyle(tools.textStyle.copyWith(color: 0xFF1565C0, background: 0x99FFE066));
      tools.addCurrentTextFavorite();
      await tools.flush();
      final again = await makeTools(dir);
      await again.load();
      expect(again.textStyle.background, 0x99FFE066);
      expect(again.textFavorites.any((f) => f.color == 0xFF1565C0 && f.background == 0x99FFE066), isTrue);
    });

    test('Taste 1–9 wählt den Favoriten des aktiven Werkzeugs', () async {
      final tools = await makeTools(dir);
      await tools.load();
      tools.setMode(ToolMode.highlighter);
      tools.applyFavoriteIndex(1);
      expect(tools.highlighter.color, tools.favoritesFor(InkTool.highlighter)[1].color);
    });

    test('Alte Stift-Vorlagen (Paket 1a) werden zu Favoriten', () async {
      final f = File(p.join(dir.path, 'bibliothek', '.volti', 'presets.json'))..createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({
          'format': 'volti-presets',
          'version': 1,
          'modified': '2026-11-08T10:00:00Z',
          'presets': [
            {'id': 'a', 'tool': 'pen', 'color': 0xFF123456, 'width': 0.004},
            {'id': 'b', 'tool': 'highlighter', 'color': 0x80ABCDEF, 'width': 0.02},
          ],
        }),
      );
      final tools = await makeTools(dir);
      await tools.load();
      expect(tools.favoritesFor(InkTool.pen).single.color, 0xFF123456);
      expect(tools.favoritesFor(InkTool.highlighter).single.color, 0x80ABCDEF);
      expect(tools.pen.color, 0xFF123456);
    });

    test('Geräte-Vorlieben: Vollbild und "sofort zeichnen" sind anfangs an', () async {
      final tools = await makeTools(dir);
      expect(tools.fullscreen, isTrue);
      expect(tools.instantPen, isTrue);
      await tools.setFullscreen(false);
      expect((await makeTools(dir)).fullscreen, isFalse);
    });
  });

  test('Werkzeug-Einstellungen werden zwischen Geräten abgeglichen (jüngste gewinnt)', () async {
    final cloud = p.join(dir.path, 'cloud');
    await SyncEngine.initializeRemote(FolderSyncStore(cloud));
    final a = p.join(dir.path, 'a'), b = p.join(dir.path, 'b');
    SyncEngine engine(String root) =>
        SyncEngine(localRoot: root, remote: FolderSyncStore(cloud), baseFile: File('$root-base.json'));

    final sa = ToolSettings.defaults()..pen = ToolSettings.defaults().pen.copyWith(color: 0xFF2E7D32);
    await ToolStore(a).save(sa);
    await engine(a).run();
    await engine(b).run();
    expect((await ToolStore(b).load()).pen.color, 0xFF2E7D32);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    final sb = await ToolStore(b).load()
      ..pen = ToolSettings.defaults().pen.copyWith(color: 0xFF1565C0);
    await ToolStore(b).save(sb);
    await engine(b).run();
    await engine(a).run();
    expect((await ToolStore(a).load()).pen.color, 0xFF1565C0);
  });

  group('Anmerkungen', () {
    test('Seite leeren entfernt Striche und Texte – und lässt sich rückgängig machen', () {
      final c = InkController(pdfPath: p.join(dir.path, 'x.pdf'));
      c.addStroke(page: 1, tool: InkTool.pen, color: 0xFF000000, width: 0.003, points: const [InkPoint(0.1, 0.1, 0.5)]);
      c.addText(page: 1, x: 0.2, y: 0.2, text: 'dolce', size: 0.022, color: 0xFF000000);
      c.addStroke(page: 2, tool: InkTool.pen, color: 0xFF000000, width: 0.003, points: const [InkPoint(0.1, 0.1, 0.5)]);

      c.clearPage(1);
      expect(c.pageHasAnnotations(1), isFalse);
      expect(c.pageHasAnnotations(2), isTrue, reason: 'andere Seiten bleiben');
      c.undo();
      expect(c.annotations.visibleStrokesOn(1).length, 1);
      expect(c.annotations.visibleTextsOn(1).single.text, 'dolce');
      c.dispose();
    });

    test('Text-Hintergrund: ändern, rückgängig; ältere Notizen behalten ihren hellen Hintergrund', () {
      final c = InkController(pdfPath: p.join(dir.path, 'x.pdf'));
      final id = c.addText(
        page: 1,
        x: 0.2,
        y: 0.2,
        text: 'Atmen',
        size: 0.022,
        color: 0xFF000000,
        background: TextNote.noBackground,
      )!;
      c.updateText(id, background: 0x99FFE066, color: 0xFFC62828);
      expect(c.annotations.text(id)!.background, 0x99FFE066);
      expect(c.annotations.text(id)!.color, 0xFFC62828);
      c.undo();
      expect(c.annotations.text(id)!.background, TextNote.noBackground);

      final legacy = TextNote.fromJson({
        'id': 'x',
        'page': 1,
        'x': 0.1,
        'y': 0.1,
        'text': 'alt',
        'size': 0.022,
        'color': 0xFF000000,
        'created': '2026-11-08T10:00:00Z',
      });
      expect(legacy.background, TextNote.legacyBackground);
      c.dispose();
    });
  });
}
