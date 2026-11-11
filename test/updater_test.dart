import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/app/updater.dart';

void main() {
  test('Versionsnummern werden richtig gelesen und verglichen', () {
    expect(Updater.numberOf('v0.1.42'), 42);
    expect(Updater.numberOf('0.1.7'), 7);
    expect(Updater.numberOf('Testversion'), isNull);
    final u = UpdateInfo(tag: 'v0.1.100', number: 100, page: Uri.parse('https://example.org'));
    // Eine lokal gebaute Testversion gilt als Nummer 0 – also ist alles neuer.
    expect(Updater.isNewer(u), isTrue);
  });

  group('Dateien austauschen', () {
    late Directory tmp, neu, app;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('volti-swap');
      neu = await Directory(p.join(tmp.path, 'neu')).create();
      app = await Directory(p.join(tmp.path, 'app')).create();
    });
    tearDown(() => tmp.delete(recursive: true));

    Future<void> put(Directory d, String rel, String text) async {
      final f = File(p.join(d.path, rel));
      await f.parent.create(recursive: true);
      await f.writeAsString(text);
    }

    String read(String rel) => File(p.join(app.path, rel)).readAsStringSync();
    List<String> leftovers() => app
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((n) => n.endsWith(Updater.oldSuffix))
        .toList();

    test('neue Dateien kommen hin, alte werden beiseitegeschoben, gleiche bleiben', () async {
      await put(app, 'Volti.exe', 'alt');
      await put(app, 'data/icudtl.dat', 'gleich');
      await put(app, 'data/app.so', 'alt');
      await put(neu, 'Volti.exe', 'neu');
      await put(neu, 'data/icudtl.dat', 'gleich');
      await put(neu, 'data/app.so', 'neu');
      await put(neu, 'data/flutter_assets/x.txt', 'dazu');

      final r = await Updater.swapFiles(neu.path, app.path);
      expect(r.ok, isTrue);
      expect(read('Volti.exe'), 'neu');
      expect(read('data/app.so'), 'neu');
      expect(read('data/icudtl.dat'), 'gleich');
      expect(read('data/flutter_assets/x.txt'), 'dazu');
      expect(leftovers(), hasLength(2));

      await Updater.cleanUpDir(app.path);
      expect(leftovers(), isEmpty);
      expect(read('Volti.exe'), 'neu');
    });

    test('geht ein Schritt nicht, wird alles zurückgestellt', () async {
      await put(app, 'Volti.exe', 'alt');
      await put(neu, 'Volti.exe', 'neu');
      await put(neu, 'neu.dll', 'neu');
      // Am Platz der letzten Datei steht ein Ordner: Das Kopieren schlägt fehl.
      await put(neu, 'zz', 'neu');
      await Directory(p.join(app.path, 'zz')).create();

      final r = await Updater.swapFiles(neu.path, app.path);
      expect(r.ok, isFalse);
      expect(read('Volti.exe'), 'alt');
      expect(File(p.join(app.path, 'neu.dll')).existsSync(), isFalse);
      expect(leftovers(), isEmpty);
    });
  });
}
