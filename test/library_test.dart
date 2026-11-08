import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/app_settings.dart';
import 'package:volti/core/library/library_filter.dart';
import 'package:volti/core/library/library_scanner.dart';
import 'package:volti/core/library/score_importer.dart';
import 'package:volti/core/library/score_meta.dart';
import 'package:volti/core/library/setlist.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/features/library/library_controller.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_lib'));
  tearDown(() => dir.deleteSync(recursive: true));

  File pdf(String rel) => File(p.join(dir.path, rel))
    ..createSync(recursive: true)
    ..writeAsStringSync('%PDF-1.4 dummy');

  group('Infos (Metadaten)', () {
    test('Vorschlag aus dem Dateinamen', () {
      expect(guessFromFileName('/x/Bach - Cellosuite 1.pdf'), (title: 'Cellosuite 1', composer: 'Bach'));
      expect(guessFromFileName('/x/Ave_Maria.pdf'), (title: 'Ave Maria', composer: null));
      expect(guessFromFileName('/x/Schubert – Ave Maria - Arr. Cello.pdf').composer, 'Schubert');
    });

    test('Pro Feld gewinnt die jüngste Änderung (zwei Geräte)', () {
      final t0 = DateTime.utc(2026, 1, 1), t1 = DateTime.utc(2026, 1, 2);
      final surface = ScoreMeta()
        ..set(ScoreMeta.composer, 'J. S. Bach', at: t1)
        ..set(ScoreMeta.genre, 'Barock', at: t0);
      final laptop = ScoreMeta()
        ..set(ScoreMeta.composer, 'Bach', at: t0)
        ..set(ScoreMeta.genre, 'Klassik', at: t1);
      for (final m in [ScoreMeta.merge(surface, laptop), ScoreMeta.merge(laptop, surface)]) {
        expect(m.text(ScoreMeta.composer), 'J. S. Bach');
        expect(m.text(ScoreMeta.genre), 'Klassik');
      }
    });

    test('Tags werden bereinigt und sortiert; unveränderte Werte nicht neu gestempelt', () {
      final m = ScoreMeta()..set(ScoreMeta.tags, [' Konzert', 'Barock', 'Konzert', '']);
      expect(m.tagList, ['Barock', 'Konzert']);
      final stamp = m.fields[ScoreMeta.tags]!.changed;
      m.set(ScoreMeta.tags, ['Konzert', 'Barock'], at: DateTime.utc(2030));
      expect(m.fields[ScoreMeta.tags]!.changed, stamp);
    });

    test('Altes Dateiformat (nur Anmerkungen) wird weiterhin gelesen', () async {
      final f = pdf('alt.pdf');
      File('${f.path}${SidecarStore.suffix}').writeAsStringSync(
        jsonEncode({
          'format': 'volti-annotations',
          'version': 1,
          'strokes': [
            {
              'id': 'x',
              'page': 1,
              'tool': 'pen',
              'color': 0,
              'width': 0.002,
              'created': '2026-01-01T00:00:00Z',
              'points': [
                [0.1, 0.1, 0.5],
              ],
            },
          ],
        }),
      );
      final s = await const SidecarStore().load(f.path);
      expect(s.annotations.visibleStrokesOn(1).length, 1);
      expect(s.meta.isEmpty, isTrue);
    });

    test('Infos speichern lässt Anmerkungen unangetastet (und umgekehrt)', () async {
      const store = SidecarStore();
      final f = pdf('stueck.pdf');
      await store.save(f.path, annotations: ScoreAnnotations([_stroke()]));
      await store.save(f.path, meta: ScoreMeta()..set(ScoreMeta.composer, 'Bach'));
      final back = await store.load(f.path);
      expect(back.annotations.visibleStrokesOn(1).length, 1);
      expect(back.meta.text(ScoreMeta.composer), 'Bach');
    });

    test('Gleichzeitiges Speichern verliert nichts', () async {
      const store = SidecarStore();
      final f = pdf('parallel.pdf');
      await Future.wait([
        store.save(f.path, meta: ScoreMeta()..set(ScoreMeta.genre, 'Jazz')),
        store.save(f.path, meta: ScoreMeta()..set(ScoreMeta.key, 'F-Dur')),
        store.save(f.path, annotations: ScoreAnnotations([_stroke()])),
      ]);
      final back = await store.load(f.path);
      expect(back.meta.text(ScoreMeta.genre), 'Jazz');
      expect(back.meta.text(ScoreMeta.key), 'F-Dur');
      expect(back.annotations.visibleStrokesOn(1).length, 1);
    });
  });

  group('Bibliothek einlesen', () {
    test('Findet PDFs in Unterordnern, ignoriert versteckte Ordner und Nicht-PDFs', () async {
      pdf('Bach - Suite 1.pdf');
      pdf('Barock/Händel - Sonate.PDF');
      pdf('.volti/intern.pdf');
      File(p.join(dir.path, 'notizen.txt')).writeAsStringSync('x');
      await const SidecarStore().save(
        p.join(dir.path, 'Barock', 'Händel - Sonate.PDF'),
        meta: ScoreMeta()..set(ScoreMeta.genre, 'Barock'),
      );

      final scores = await const LibraryScanner().scan(dir.path);
      expect(scores.map((s) => s.relativePath).toSet(), {'Bach - Suite 1.pdf', 'Barock/Händel - Sonate.PDF'});
      final haendel = scores.firstWhere((s) => s.folder == 'Barock');
      expect(haendel.composer, 'Händel');
      expect(haendel.genre, 'Barock');
    });

    test('Suchen, filtern, sortieren', () async {
      pdf('Bach - Suite 1.pdf');
      pdf('Mozart - Rondo.pdf');
      pdf('Ohne Komponist.pdf');
      final scores = await const LibraryScanner().scan(dir.path);
      scores.firstWhere((s) => s.title == 'Rondo').meta.set(ScoreMeta.tags, ['Konzert']);

      expect(filterScores(scores, query: 'bach su').map((s) => s.title), ['Suite 1']);
      expect(filterScores(scores, tag: 'Konzert').map((s) => s.title), ['Rondo']);
      expect(filterScores(scores, sort: ScoreSort.composer).map((s) => s.composer), ['Bach', 'Mozart', null]);
      expect(filterScores(scores, query: 'zzz'), isEmpty);
    });
  });

  group('Setlists', () {
    test('Speichern, laden, löschen', () async {
      final store = SetlistStore(dir.path);
      final s = Setlist.create(' Konzert Mai ')
        ..items.addAll([SetlistItem.create('a.pdf'), SetlistItem.create('a.pdf')]);
      await store.save(s);
      // liegt im Bibliotheksordner, damit es mitsynchronisiert wird
      expect(File(p.join(dir.path, '.volti', 'setlists', '${s.id}.json')).existsSync(), isTrue);

      final loaded = await store.loadAll();
      expect(loaded.single.name, 'Konzert Mai');
      expect(loaded.single.items.map((i) => i.relativePath), ['a.pdf', 'a.pdf']);

      await store.delete(s);
      expect(await store.loadAll(), isEmpty);
    });
  });

  test('Geräte-Einstellungen bleiben erhalten', () async {
    final a = await AppSettings.loadFrom(dir);
    await a.recordOpened('/noten/x.pdf');
    final b = await AppSettings.loadFrom(dir);
    expect(b.lastOpened('/noten/x.pdf'), isNotNull);
    expect(b.lastOpened('/noten/y.pdf'), isNull);
  });

  group('Import in Voltis Datenordner', () {
    late Directory data;
    setUp(() => data = Directory(p.join(dir.path, 'volti-daten')));

    test('Kopiert PDFs samt Infos nach Noten/, Original bleibt unverändert', () async {
      final src = pdf('extern/Bach - Suite.pdf');
      await const SidecarStore().save(src.path, meta: ScoreMeta()..set(ScoreMeta.genre, 'Barock'));

      final r = await ScoreImporter(data.path).importFiles([src.path]);
      expect(r.added.values, ['Noten/Bach - Suite.pdf']);
      final copy = p.join(data.path, 'Noten', 'Bach - Suite.pdf');
      expect(File(copy).existsSync(), isTrue);
      expect((await const SidecarStore().load(copy)).meta.text(ScoreMeta.genre), 'Barock');
      expect(src.existsSync(), isTrue);
    });

    test('Gleiche Datei zweimal: wird erkannt; anderer Inhalt mit gleichem Namen: neuer Name', () async {
      final a = pdf('a/Stück.pdf');
      final b = File(p.join(dir.path, 'b', 'Stück.PDF'))
        ..createSync(recursive: true)
        ..writeAsStringSync('%PDF-1.4 anderer, längerer Inhalt');
      final importer = ScoreImporter(data.path);
      await importer.importFiles([a.path]);
      final again = await importer.importFiles([a.path]);
      expect(again.added, isEmpty);
      expect(again.alreadyThere.values, ['Noten/Stück.pdf']);

      final other = await importer.importFiles([b.path]);
      expect(other.added.values, ['Noten/Stück (2).pdf']);
    });

    test('Ganzen Ordner importieren findet PDFs in Unterordnern', () async {
      pdf('sammlung/eins.pdf');
      pdf('sammlung/Barock/zwei.pdf');
      pdf('sammlung/.versteckt/drei.pdf');
      final found = await ScoreImporter.findPdfs(p.join(dir.path, 'sammlung'));
      expect(found.map(p.basename).toSet(), {'eins.pdf', 'zwei.pdf'});
    });

    test('Bibliothek aus Version 0.1.2 wird übernommen (inkl. Setlists)', () async {
      final old = p.join(dir.path, 'alter-ordner');
      pdf('alter-ordner/Barock/Händel.pdf');
      pdf('alter-ordner/Bach.pdf');
      final s = Setlist.create('Konzert')
        ..items.addAll([SetlistItem.create('Barock/Händel.pdf'), SetlistItem.create('Bach.pdf')]);
      await SetlistStore(old).save(s);
      File(p.join(dir.path, 'einst', 'settings.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'libraryRoot': old}));

      final settings = await AppSettings.loadFrom(Directory(p.join(dir.path, 'einst')));
      final lib = LibraryController(settings, root: data.path);
      await lib.init();

      expect(lib.scores.map((e) => e.relativePath).toSet(), {'Noten/Händel.pdf', 'Noten/Bach.pdf'});
      expect(lib.setlists.single.items.map((i) => i.relativePath), ['Noten/Händel.pdf', 'Noten/Bach.pdf']);
      expect(settings.legacyLibraryRoot, isNull);
      expect(File(p.join(old, 'Bach.pdf')).existsSync(), isTrue); // Original bleibt
    });

    test('Löschen entfernt PDF, Zusatzdatei und Setlist-Einträge', () async {
      final lib = LibraryController(await AppSettings.loadFrom(Directory(p.join(dir.path, 'cfg'))), root: data.path);
      await lib.init();
      await lib.importPdfs([pdf('x/eins.pdf').path, pdf('x/zwei.pdf').path]);
      final eins = lib.scores.firstWhere((e) => e.title == 'eins');
      await lib.updateMeta(eins, {ScoreMeta.genre: 'Jazz'});
      final set = await lib.createSetlist('Probe');
      await lib.addToSetlist(set, lib.scores);

      await lib.deleteScore(eins);
      expect(File(eins.path).existsSync(), isFalse);
      expect(File('${eins.path}${SidecarStore.suffix}').existsSync(), isFalse);
      expect(lib.scores.map((e) => e.title), ['zwei']);
      expect((await SetlistStore(data.path).loadAll()).single.items.map((i) => i.relativePath), ['Noten/zwei.pdf']);
    });
  });
}

Stroke _stroke() => Stroke(
  id: 'strich-1',
  page: 1,
  tool: InkTool.pen,
  color: 0xFF000000,
  width: 0.002,
  points: const [InkPoint(0.1, 0.1, 0.5)],
  createdAt: DateTime.utc(2026, 1, 1),
);
