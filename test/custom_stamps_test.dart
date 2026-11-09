import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/ink/custom_stamps.dart';
import 'package:volti/core/ink/stamp.dart';
import 'package:volti/core/ink/tool_settings.dart';
import 'package:volti/core/sync/sync_engine.dart';
import 'package:volti/core/sync/sync_store.dart';

void main() {
  test('Weiss wird durchsichtig, leere Ränder werden weggeschnitten', () {
    const w = 20, h = 10;
    final px = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
    // schwarzer Block 5..9 × 2..5
    for (var y = 2; y <= 5; y++) {
      for (var x = 5; x <= 9; x++) {
        final i = (y * w + x) * 4;
        px[i] = px[i + 1] = px[i + 2] = 0;
      }
    }
    final out = prepareStampPixels(px, w, h)!;
    expect(out.width, 5 + 2, reason: 'Inhalt plus 1 Punkt Rand');
    expect(out.height, 4 + 2);
    expect(out.rgba[3], 0, reason: 'Ecke (weiss) ist durchsichtig');
    expect(out.rgba[((1 * out.width) + 1) * 4 + 3], 255, reason: 'Inhalt bleibt deckend');

    final white = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
    expect(prepareStampPixels(white, w, h), isNull, reason: 'nichts zu sehen');
    expect(prepareStampPixels(white, w, h, whiteToClear: false)!.width, w, reason: 'ohne Weiss entfernen bleibt alles');
  });

  test('Gesetzter eigener Stempel und Einstellung werden gespeichert', () {
    final st = Stamp(
      id: 's',
      page: 1,
      x: 0.5,
      y: 0.5,
      glyph: 0,
      size: 0.05,
      color: 0,
      createdAt: DateTime.utc(2030),
      custom: 'abc',
    );
    expect(Stamp.fromJson(st.toJson()).custom, 'abc');
    expect(st.copyWith(x: 0.2).custom, 'abc');

    const setting = StampSetting(glyph: 0xE52D, size: 0.04, color: 0xFF000000);
    final mine = setting.copyWith(custom: 'abc');
    expect(StampSetting.fromJson(mine.toJson()).custom, 'abc');
    expect(mine.copyWith(size: 0.06).custom, 'abc', reason: 'Grösse ändern behält den Stempel');
    expect(mine.copyWith(glyph: 0xE520).custom, isNull, reason: 'ein Zeichen wählen hebt den eigenen auf');
  });

  test('Eigene Stempel kommen per Sync auf das andere Gerät', () async {
    final tmp = Directory.systemTemp.createTempSync('volti_cstamps');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final cloud = p.join(tmp.path, 'cloud');
    await SyncEngine.initializeRemote(FolderSyncStore(cloud));
    SyncEngine engine(String dev) => SyncEngine(
      localRoot: p.join(tmp.path, dev, 'Bibliothek'),
      remote: FolderSyncStore(cloud),
      baseFile: File(p.join(tmp.path, dev, 'sync_base.json')),
    );

    final surface = CustomStampStore(p.join(tmp.path, 'surface', 'Bibliothek'));
    final s = CustomStamp(
      id: 'x1',
      name: 'Viertel',
      anchorX: 0.3,
      anchorY: 0.8,
      aspect: 0.5,
      createdAt: DateTime.utc(2030),
    );
    await surface.writeImage(s, Uint8List.fromList([137, 80, 78, 71]));
    await surface.save([s]);
    await engine('surface').run();
    await engine('desktop').run();

    final desktop = CustomStampStore(p.join(tmp.path, 'desktop', 'Bibliothek'));
    final got = await desktop.load();
    expect(got.single.name, 'Viertel');
    expect(got.single.anchorY, 0.8);
    expect(await desktop.readImage(got.single), isNotNull, reason: 'Bild ist mitgekommen');
  });
}
