import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/library/score_importer.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/core/sync/cloud_store.dart';
import 'package:volti/core/sync/sync_engine.dart';

/// Ein Cloud-Dienst im Arbeitsspeicher (wie Dropbox, aber ohne Internet).
class FakeCloud implements CloudApi {
  final files = <String, List<int>>{};
  final revs = <String, int>{};
  int downloads = 0;
  int _next = 1;

  @override
  Future<List<RemoteEntry>> listAll() async => [
    for (final e in files.entries) RemoteEntry(path: e.key, rev: '${revs[e.key]}'),
  ];

  @override
  Future<List<int>> download(RemoteEntry e) async {
    downloads++;
    final f = files[e.path];
    if (f == null) throw const FileSystemException('fehlt');
    return f;
  }

  @override
  Future<RemoteEntry> upload(String path, List<int> bytes, RemoteEntry? existing) async {
    files[path] = List.of(bytes);
    revs[path] = _next++;
    return RemoteEntry(path: path, rev: '${revs[path]}');
  }

  @override
  Future<void> delete(RemoteEntry e) async {
    files.remove(e.path);
    revs.remove(e.path);
  }
}

class Device {
  Device(this.dir, this.cloud);
  final Directory dir;
  final FakeCloud cloud;
  String get root => p.join(dir.path, 'Bibliothek');
  late final store = CloudSyncStore(cloud, cacheDir: p.join(dir.path, 'cache'));
  Future<SyncReport> sync() =>
      SyncEngine(localRoot: root, remote: store, baseFile: File(p.join(dir.path, 'base.json'))).run();
  String pdfPath(String name) => p.join(root, 'Noten', name);
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
  late FakeCloud cloud;
  late Device surface, desktop;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('volti_cloud');
    cloud = FakeCloud();
    surface = Device(Directory(p.join(tmp.path, 'surface')), cloud);
    desktop = Device(Directory(p.join(tmp.path, 'desktop')), cloud);
    await SyncEngine.initializeRemote(surface.store);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> importOn(Device d, String name) async {
    final src = File(p.join(tmp.path, 'quelle', name))
      ..createSync(recursive: true)
      ..writeAsStringSync('%PDF-1.4 $name');
    await ScoreImporter(d.root).importFiles([src.path]);
  }

  test('Noten und Anmerkungen gehen über den Dienst von Gerät zu Gerät', () async {
    await importOn(surface, 'Halleluja - C.pdf');
    await surface.sync();
    expect(cloud.files.keys, contains('Noten/Halleluja - C.pdf'));

    await desktop.sync();
    expect(File(desktop.pdfPath('Halleluja - C.pdf')).existsSync(), isTrue);

    // Auf beiden Geräten etwas schreiben: beides bleibt erhalten.
    final a = ScoreAnnotations()..put(stroke('vom-surface'));
    await const SidecarStore().save(surface.pdfPath('Halleluja - C.pdf'), annotations: a);
    final b = ScoreAnnotations()..put(stroke('vom-desktop'));
    await const SidecarStore().save(desktop.pdfPath('Halleluja - C.pdf'), annotations: b);
    await surface.sync();
    await desktop.sync();
    await surface.sync();
    for (final d in [surface, desktop]) {
      final s = await const SidecarStore().load(d.pdfPath('Halleluja - C.pdf'));
      expect(s.annotations.visibleStrokesOn(1).map((x) => x.id).toSet(), {'vom-surface', 'vom-desktop'});
    }
  });

  test('Unveränderte Infos werden nicht jedes Mal neu heruntergeladen', () async {
    for (final n in ['A.pdf', 'B.pdf', 'C.pdf']) {
      await importOn(surface, n);
    }
    await surface.sync();
    await desktop.sync();
    await desktop.sync(); // füllt den Zwischenspeicher
    final before = cloud.downloads;
    await desktop.sync();
    expect(cloud.downloads, before, reason: 'nichts geändert → nichts heruntergeladen');
  });

  test('Löschen kommt auf dem anderen Gerät an', () async {
    await importOn(surface, 'Weg.pdf');
    await importOn(surface, 'Bleibt.pdf');
    await surface.sync();
    await desktop.sync();
    await File(surface.pdfPath('Weg.pdf')).delete();
    await surface.sync();
    expect(cloud.files.keys, isNot(contains('Noten/Weg.pdf')));
    await desktop.sync();
    expect(File(desktop.pdfPath('Weg.pdf')).existsSync(), isFalse);
    expect(File(desktop.pdfPath('Bleibt.pdf')).existsSync(), isTrue);
  });

  test('Dropbox: Umlaute im Kopf der Anfrage werden umschrieben', () {
    final h = DropboxApi.headerJson({'path': '/Noten/Grösser – „Lied“.pdf'});
    expect(h.codeUnits.every((c) => c < 0x80), isTrue);
    expect(jsonDecode(h), {'path': '/Noten/Grösser – „Lied“.pdf'});
  });
}
