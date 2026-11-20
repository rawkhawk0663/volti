import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/library/score_audio.dart';
import 'package:volti/core/library/score_importer.dart';
import 'package:volti/core/library/score_meta.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/core/sync/sync_engine.dart';
import 'package:volti/core/sync/sync_store.dart';
import 'package:volti/features/viewer/score_audio_player.dart';

void main() {
  late Directory tmp;
  late String cloud;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('volti_audio');
    cloud = p.join(tmp.path, 'cloud');
    await SyncEngine.initializeRemote(FolderSyncStore(cloud));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String rootOf(String device) => p.join(tmp.path, device, 'Bibliothek');
  SyncEngine engine(String device) => SyncEngine(
    localRoot: rootOf(device),
    remote: FolderSyncStore(cloud),
    baseFile: File(p.join(tmp.path, device, 'sync_base.json')),
  );

  File source(String name, [String content = 'ID3 audio']) => File(p.join(tmp.path, 'quelle', name))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  test('Formate und Pfade', () {
    expect(canPlayAudio('/x/Lied.MP3'), isTrue);
    expect(canPlayAudio('/x/Memo.m4a'), isTrue);
    expect(canPlayAudio('/x/Noten.pdf'), isFalse);
    expect(isAudioFile('.volti/audio/abc.flac'), isTrue);
    expect(isAudioFile('.volti/stamps/abc.mp3'), isFalse);
    final pdf = p.join('/daten', 'Bibliothek', 'Noten', 'Lied.pdf');
    expect(libraryRootOf(pdf), p.join('/daten', 'Bibliothek'));
    final meta = ScoreMeta()..set(ScoreMeta.audio, 'abc.mp3');
    expect(audioPathOf(pdf, meta), p.join('/daten', 'Bibliothek', '.volti', 'audio', 'abc.mp3'));
    // Kein Ausbrechen aus dem Ordner über den Dateinamen.
    expect(audioPathOf(pdf, ScoreMeta()..set(ScoreMeta.audio, '../x.mp3')), isNull);
    expect(audioPathOf(pdf, ScoreMeta()), isNull);
  });

  test('Zuordnen kopiert die Datei, das Original bleibt', () async {
    final src = source('Probe.mp3');
    final name = await importAudioFile(rootOf('a'), src.path);
    expect(name, endsWith('.mp3'));
    expect(File(p.join(rootOf('a'), '.volti', 'audio', name)).readAsStringSync(), 'ID3 audio');
    expect(src.existsSync(), isTrue);
    await expectLater(importAudioFile(rootOf('a'), source('x.pdf').path), throwsFormatException);
  });

  test('Aufnahme kommt per Abgleich aufs andere Gerät und verschwindet beim Entfernen', () async {
    // Gerät A: Stück importieren und Aufnahme zuordnen.
    final pdfSrc = source('Lied.pdf', '%PDF-1.4 x');
    await ScoreImporter(rootOf('a')).importFiles([pdfSrc.path]);
    final pdfA = p.join(rootOf('a'), 'Noten', 'Lied.pdf');
    final name = await importAudioFile(rootOf('a'), source('Probe.mp3').path);
    await const SidecarStore().save(
      pdfA,
      meta: ScoreMeta()
        ..set(ScoreMeta.audio, name)
        ..set(ScoreMeta.audioName, 'Probe.mp3'),
    );
    await engine('a').run();

    // Gerät B bekommt Stück, Infos und Aufnahme.
    await engine('b').run();
    final pdfB = p.join(rootOf('b'), 'Noten', 'Lied.pdf');
    final metaB = (await const SidecarStore().load(pdfB)).meta;
    expect(metaB.text(ScoreMeta.audioName), 'Probe.mp3');
    final audioB = audioPathOf(pdfB, metaB)!;
    expect(File(audioB).readAsStringSync(), 'ID3 audio');

    // A entfernt die Aufnahme → nach dem Abgleich auch auf B weg.
    final metaA = (await const SidecarStore().load(pdfA)).meta;
    await deleteAudioOf(pdfA, metaA);
    await const SidecarStore().save(pdfA, meta: ScoreMeta(metaA.fields)..set(ScoreMeta.audio, ''));
    await engine('a').run();
    await engine('b').run();
    expect(File(audioB).existsSync(), isFalse);
    expect(audioPathOf(pdfB, (await const SidecarStore().load(pdfB)).meta), isNull);
  });

  test('Zeitanzeige', () {
    expect(formatTime(const Duration(seconds: 65)), '1:05');
    expect(formatTime(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');
    expect(formatTime(Duration.zero), '0:00');
  });
}
