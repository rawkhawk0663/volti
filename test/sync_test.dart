import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/library/score_importer.dart';
import 'package:volti/core/library/score_meta.dart';
import 'package:volti/core/library/setlist.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/core/sync/sync_engine.dart';
import 'package:volti/core/sync/sync_store.dart';

/// Ein simuliertes Gerät mit eigenem Datenordner und eigenem Sync-Stand.
class Device {
  Device(this.dir, this.cloud);
  final Directory dir;
  final String cloud;
  String get root => p.join(dir.path, 'Bibliothek');
  SyncEngine get engine =>
      SyncEngine(localRoot: root, remote: FolderSyncStore(cloud), baseFile: File(p.join(dir.path, 'sync_base.json')));
  Future<SyncReport> sync() => engine.run();

  String pdfPath(String name) => p.join(root, 'Noten', name);
  bool has(String name) => File(pdfPath(name)).existsSync();
  Future<ScoreSidecar> sidecar(String name) => const SidecarStore().load(pdfPath(name));
}

Stroke stroke(String id) => Stroke(
  id: id,
  page: 1,
  tool: InkTool.pen,
  color: 0xFF000000,
  width: 0.002,
  points: const [InkPoint(0.1, 0.1, 0.5)],
  createdAt: DateTime.utc(2026, 1, 1),
);

void main() {
  late Directory tmp;
  late String cloud;
  late Device surface, desktop;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('volti_sync');
    cloud = p.join(tmp.path, 'Proton Drive', 'Volti');
    surface = Device(Directory(p.join(tmp.path, 'surface')), cloud);
    desktop = Device(Directory(p.join(tmp.path, 'desktop')), cloud);
    await SyncEngine.initializeRemote(FolderSyncStore(cloud));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> importOn(Device d, String name, [String content = '%PDF-1.4 x']) async {
    final src = File(p.join(tmp.path, 'quelle', name))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    await ScoreImporter(d.root).importFiles([src.path]);
  }

  test('Import auf dem Surface erscheint auf dem Desktop', () async {
    await importOn(surface, 'Bach.pdf');
    await const SidecarStore().save(surface.pdfPath('Bach.pdf'), meta: ScoreMeta()..set(ScoreMeta.genre, 'Barock'));

    expect((await surface.sync()).uploaded, 1);
    final r = await desktop.sync();
    expect(r.downloaded, 1);
    expect(desktop.has('Bach.pdf'), isTrue);
    expect((await desktop.sidecar('Bach.pdf')).meta.text(ScoreMeta.genre), 'Barock');
  });

  test('Anmerkungen von beiden Geräten werden zusammengeführt', () async {
    await importOn(surface, 'Bach.pdf');
    await surface.sync();
    await desktop.sync();

    // Beide schreiben "gleichzeitig" (offline), dann wird abgeglichen.
    await const SidecarStore().save(surface.pdfPath('Bach.pdf'), annotations: ScoreAnnotations([stroke('s')]));
    await const SidecarStore().save(desktop.pdfPath('Bach.pdf'), annotations: ScoreAnnotations([stroke('d')]));
    await surface.sync();
    await desktop.sync();
    await surface.sync();

    for (final d in [surface, desktop]) {
      final ids = (await d.sidecar('Bach.pdf')).annotations.visibleStrokesOn(1).map((s) => s.id).toSet();
      expect(ids, {'s', 'd'});
    }
  });

  test('Löschen auf einem Gerät löscht auf dem anderen – neu importiert bleibt', () async {
    await importOn(surface, 'Alt.pdf');
    await surface.sync();
    await desktop.sync();
    expect(desktop.has('Alt.pdf'), isTrue);

    await File(surface.pdfPath('Alt.pdf')).delete();
    await importOn(desktop, 'Neu.pdf'); // auf dem Desktop neu, noch nie abgeglichen
    expect((await surface.sync()).deletedThere, 1);
    final r = await desktop.sync();
    expect(r.deletedHere, 1);
    expect(desktop.has('Alt.pdf'), isFalse);
    expect(desktop.has('Neu.pdf'), isTrue);
    await surface.sync();
    expect(surface.has('Neu.pdf'), isTrue);
  });

  test('Setlist: die zuletzt geänderte Fassung gewinnt, Löschen wird übernommen', () async {
    final s = Setlist.create('Konzert');
    await SetlistStore(surface.root).save(s);
    await surface.sync();
    await desktop.sync();

    final onDesktop = (await SetlistStore(desktop.root).loadAll()).single
      ..name = 'Konzert Mai'
      ..modified = DateTime.now().toUtc().add(const Duration(seconds: 1));
    await SetlistStore(desktop.root).save(onDesktop);
    await desktop.sync();
    await surface.sync();
    expect((await SetlistStore(surface.root).loadAll()).single.name, 'Konzert Mai');

    await SetlistStore(surface.root).delete(s);
    await surface.sync();
    await desktop.sync();
    expect(await SetlistStore(desktop.root).loadAll(), isEmpty);
  });

  test('Konfliktkopie des Cloud-Dienstes wird zusammengeführt und aufgeräumt', () async {
    await importOn(surface, 'Bach.pdf');
    await const SidecarStore().save(surface.pdfPath('Bach.pdf'), annotations: ScoreAnnotations([stroke('a')]));
    await surface.sync();
    // So etwa sieht eine Konfliktkopie aus:
    final copy = File(p.join(cloud, 'Noten', 'Bach.pdf.volti (Konflikt 2026-11-08).json'));
    final other = ScoreSidecar(annotations: ScoreAnnotations([stroke('b')]));
    await const SidecarStore().save(p.join(tmp.path, 'x.pdf'), annotations: other.annotations);
    File(p.join(tmp.path, 'x.pdf${SidecarStore.suffix}')).copySync(copy.path);

    final r = await desktop.sync();
    expect(r.conflictCopiesResolved, 1);
    expect(copy.existsSync(), isFalse);
    expect((await desktop.sidecar('Bach.pdf')).annotations.visibleStrokesOn(1).map((s) => s.id).toSet(), {'a', 'b'});
  });

  test('Sicherheitsbremse: fehlender Sync-Ordner löscht nichts', () async {
    for (final n in ['1.pdf', '2.pdf', '3.pdf', '4.pdf']) {
      await importOn(surface, n);
    }
    await surface.sync();
    Directory(cloud).deleteSync(recursive: true); // z. B. Proton Drive nicht gestartet

    await expectLater(surface.sync(), throwsA(isA<SyncException>()));
    expect(surface.has('1.pdf'), isTrue);
  });

  test('Sicherheitsbremse: Massenlöschung wird gestoppt', () async {
    for (final n in ['1.pdf', '2.pdf', '3.pdf', '4.pdf']) {
      await importOn(surface, n);
    }
    await surface.sync();
    for (final n in ['1.pdf', '2.pdf', '3.pdf']) {
      File(p.join(cloud, 'Noten', n)).deleteSync();
    }
    await expectLater(surface.sync(), throwsA(isA<SyncException>()));
    expect(surface.has('1.pdf'), isTrue);
  });

  test('Ein zweiter Abgleich ohne Änderungen tut nichts', () async {
    await importOn(surface, 'Bach.pdf');
    await const SidecarStore().save(surface.pdfPath('Bach.pdf'), meta: ScoreMeta()..set(ScoreMeta.key, 'G-Dur'));
    await surface.sync();
    final r = await surface.sync();
    expect([r.uploaded, r.downloaded, r.merged, r.deletedHere, r.deletedThere], [0, 0, 0, 0, 0]);
  });
}
