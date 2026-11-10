import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/library/backup.dart';
import 'package:volti/core/library/folders.dart';
import 'package:volti/core/library/score_importer.dart';
import 'package:volti/core/library/sidecar_store.dart';

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
  test('Sicherung erstellen und einspielen: nichts geht verloren, Anmerkungen werden zusammengeführt', () async {
    final tmp = Directory.systemTemp.createTempSync('volti_backup');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final root = p.join(tmp.path, 'Bibliothek');
    final src = File(p.join(tmp.path, 'quelle', 'Lied.pdf'))
      ..createSync(recursive: true)
      ..writeAsStringSync('%PDF-1.4 x');
    await ScoreImporter(root).importFiles([src.path]);
    final pdf = p.join(root, 'Noten', 'Lied.pdf');
    await const SidecarStore().save(pdf, annotations: ScoreAnnotations()..put(stroke('a')));
    await FolderStore(root).save([ScoreFolder.create('Gottesdienst')]);

    final zip = p.join(tmp.path, 'Volti-Sicherung.zip');
    expect(await LibraryBackup.create(root, zip), 1);

    // Danach: ein neuer Strich auf diesem Gerät, und das Stück wird ganz gelöscht.
    await const SidecarStore().save(pdf, annotations: ScoreAnnotations()..put(stroke('b')));
    final other = File(p.join(root, 'Noten', 'Neu.pdf'))..writeAsStringSync('%PDF-1.4 y');

    // Einspielen in eine leere Bibliothek: alles ist wieder da.
    final fresh = p.join(tmp.path, 'Neu', 'Bibliothek');
    await LibraryBackup.restore(fresh, zip, tmp.path);
    expect(File(p.join(fresh, 'Noten', 'Lied.pdf')).existsSync(), isTrue);
    expect((await FolderStore(fresh).load()).single.name, 'Gottesdienst');
    final s = await const SidecarStore().load(p.join(fresh, 'Noten', 'Lied.pdf'));
    expect(s.annotations.visibleStrokesOn(1).map((x) => x.id), ['a']);

    // Einspielen in die bestehende: zusammengeführt, nichts gelöscht.
    await LibraryBackup.restore(root, zip, tmp.path);
    final merged = await const SidecarStore().load(pdf);
    expect(merged.annotations.visibleStrokesOn(1).map((x) => x.id).toSet(), {'a', 'b'});
    expect(other.existsSync(), isTrue);

    // Keine Volti-Sicherung → verständlicher Fehler.
    final bad = File(p.join(tmp.path, 'x.zip'))..writeAsBytesSync([1, 2, 3]);
    expect(() => LibraryBackup.restore(root, bad.path, tmp.path), throwsA(anything));
  });
}
