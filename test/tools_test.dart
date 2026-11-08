import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/ink/drawing_preset.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/sync/sync_engine.dart';
import 'package:volti/core/sync/sync_store.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_tools'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('Standard-Vorlagen, neue Vorlage, ändern, löschen – bleibt gespeichert', () async {
    final tools = await makeTools(dir);
    await tools.load();
    expect(tools.presets.length, DrawingPreset.defaults.length);

    final added = tools.addPreset();
    expect(tools.current.id, added.id);
    expect(tools.mode, ToolMode.draw);
    tools.updatePreset(added.copyWith(color: 0xFF6A1B9A, width: 0.005));
    tools.deletePreset(tools.presets.first);
    await tools.flush();

    final again = await makeTools(dir);
    await again.load();
    expect(again.presets.length, DrawingPreset.defaults.length);
    expect(again.presets.any((p) => p.color == 0xFF6A1B9A && p.width == 0.005), isTrue);
    expect(again.presets.any((p) => p.id == DrawingPreset.defaults.first.id), isFalse);
  });

  test('Die letzte Vorlage lässt sich nicht löschen', () async {
    final tools = await makeTools(dir);
    await tools.load();
    for (final p in List.of(tools.presets)) {
      tools.deletePreset(p);
    }
    expect(tools.presets.length, 1);
    await tools.flush();
  });

  test('Tasten: P = erster Stift, H = erster Textmarker, Zahlen = Vorlage n', () async {
    final tools = await makeTools(dir);
    await tools.load();
    tools.selectFirst(InkTool.highlighter);
    expect(tools.current.tool, InkTool.highlighter);
    tools.selectFirst(InkTool.pen);
    expect(tools.current.tool, InkTool.pen);
    tools.selectIndex(2);
    expect(tools.current.id, tools.presets[2].id);
  });

  test('Geräte-Vorlieben: Vollbild und "sofort zeichnen" sind anfangs an', () async {
    final tools = await makeTools(dir);
    expect(tools.fullscreen, isTrue);
    expect(tools.instantPen, isTrue);
    await tools.setFullscreen(false);
    expect((await makeTools(dir)).fullscreen, isFalse);
  });

  test('Stift-Vorlagen werden zwischen Geräten abgeglichen (jüngste gewinnt)', () async {
    final cloud = p.join(dir.path, 'cloud');
    await SyncEngine.initializeRemote(FolderSyncStore(cloud));
    final a = p.join(dir.path, 'a'), b = p.join(dir.path, 'b');
    SyncEngine engine(String root) =>
        SyncEngine(localRoot: root, remote: FolderSyncStore(cloud), baseFile: File('$root-base.json'));

    await PresetStore(a).save([DrawingPreset.defaults.first.copyWith(color: 0xFF2E7D32)]);
    await engine(a).run();
    await engine(b).run();
    expect((await PresetStore(b).load()).single.color, 0xFF2E7D32);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await PresetStore(b).save([DrawingPreset.defaults.first.copyWith(color: 0xFF1565C0)]);
    await engine(b).run();
    await engine(a).run();
    expect((await PresetStore(a).load()).single.color, 0xFF1565C0);
  });

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
}
