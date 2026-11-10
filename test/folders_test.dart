import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/library/folders.dart';
import 'package:volti/core/sync/sync_engine.dart';
import 'package:volti/core/sync/sync_store.dart';

ScoreFolder folder(String id, {String? parent, bool deleted = false, int t = 0, String? name}) => ScoreFolder(
  id: id,
  name: name ?? id,
  parent: parent,
  deleted: deleted,
  modified: DateTime.utc(2026, 1, 1).add(Duration(seconds: t)),
);

void main() {
  group('FolderTree', () {
    test('Unterordner, Weg und Baum', () {
      final tree = FolderTree([folder('Projekte'), folder('Mai', parent: 'Projekte'), folder('Big Band')]);
      expect(tree.children(null).map((f) => f.id), ['Big Band', 'Projekte']);
      expect(tree.children('Projekte').map((f) => f.id), ['Mai']);
      expect(tree.pathTo('Mai').map((f) => f.id), ['Projekte', 'Mai']);
      expect(tree.outline().map((e) => '${e.$1.id}/${e.$2}'), ['Big Band/0', 'Projekte/0', 'Mai/1']);
      expect(tree.isInside('Mai', 'Projekte'), isTrue);
      expect(tree.isInside('Projekte', 'Mai'), isFalse);
    });

    test('Gelöschter Ordner: Inhalt rutscht eine Ebene höher', () {
      final tree = FolderTree([folder('A'), folder('B', parent: 'A', deleted: true), folder('C', parent: 'B')]);
      expect(tree.resolve('B'), 'A');
      expect(tree.resolve('C'), 'C');
      expect(tree.parentOf('C'), 'A');
      expect(tree.children('A').map((f) => f.id), ['C']);
      expect(tree.resolve('unbekannt'), isNull);
    });

    test('Kreis (zwei Geräte verschieben gleichzeitig) hängt nicht', () {
      final tree = FolderTree([folder('X', parent: 'Y'), folder('Y', parent: 'X')]);
      expect(tree.children(null).length, 2);
      expect(tree.pathTo('X').map((f) => f.id), ['X']);
    });
  });

  test('Zusammenführen: pro Ordner gewinnt die jüngste Fassung, auch Zurückholen', () {
    final a = [folder('A', name: 'Alt', t: 1), folder('B', deleted: true, t: 5)];
    final b = [folder('A', name: 'Neu', t: 2), folder('B', t: 9), folder('C', t: 1)];
    final m = {for (final f in mergeFolders(a, b)) f.id: f};
    expect(m['A']!.name, 'Neu');
    expect(m['B']!.deleted, isFalse);
    expect(m.keys.toSet(), {'A', 'B', 'C'});
  });

  test('Sync: Ordner beider Geräte kommen zusammen', () async {
    final tmp = Directory.systemTemp.createTempSync('volti_folders');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final cloud = p.join(tmp.path, 'cloud');
    await SyncEngine.initializeRemote(FolderSyncStore(cloud));
    SyncEngine engine(String name) => SyncEngine(
      localRoot: p.join(tmp.path, name, 'Bibliothek'),
      remote: FolderSyncStore(cloud),
      baseFile: File(p.join(tmp.path, name, 'sync_base.json')),
    );
    final s1 = FolderStore(p.join(tmp.path, 'surface', 'Bibliothek'));
    final s2 = FolderStore(p.join(tmp.path, 'desktop', 'Bibliothek'));
    await s1.save([folder('Hochzeiten', t: 1)]);
    await engine('surface').run();
    await s2.save([folder('Big Band', t: 2)]);
    await engine('desktop').run();
    await engine('surface').run();
    expect((await s1.load()).map((f) => f.id).toSet(), {'Hochzeiten', 'Big Band'});
    expect((await s2.load()).map((f) => f.id).toSet(), {'Hochzeiten', 'Big Band'});
  });
}
