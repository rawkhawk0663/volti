import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'score_meta.dart';

/// Aufnahmen zu Stücken (zum Mitspielen).
///
/// Die Datei wird beim Zuordnen nach `Bibliothek/.volti/audio/<id>.<endung>`
/// kopiert; das Original bleibt unangetastet. Das Stück zeigt über das
/// Info-Feld [ScoreMeta.audio] darauf. Abgeglichen wird die Datei wie ein PDF
/// (neu oder gelöscht, nie verändert): Eine andere Aufnahme bekommt eine neue ID.
const audioDir = '.volti/audio';

/// Formate, die Volti abspielen kann.
const audioExtensions = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'];

bool isAudioFile(String rel) =>
    rel.startsWith('$audioDir/') && audioExtensions.contains(p.extension(rel).replaceFirst('.', '').toLowerCase());

bool canPlayAudio(String path) => audioExtensions.contains(p.extension(path).replaceFirst('.', '').toLowerCase());

/// Bibliotheksordner eines Stücks (die PDFs liegen in `Bibliothek/Noten/`).
String libraryRootOf(String pdfPath) => p.dirname(p.dirname(pdfPath));

/// Ganzer Pfad der Aufnahme eines Stücks, oder null.
String? audioPathOf(String pdfPath, ScoreMeta meta) {
  final f = meta.text(ScoreMeta.audio);
  if (f == null || f.contains('/') || f.contains(r'\')) return null;
  return p.join(libraryRootOf(pdfPath), '.volti', 'audio', f);
}

/// Kopiert [source] in die Bibliothek und liefert den neuen Dateinamen.
Future<String> importAudioFile(String libraryRoot, String source) async {
  if (!canPlayAudio(source)) {
    throw FormatException('unsupported audio format: ${p.extension(source)}');
  }
  final name = '${const Uuid().v4()}${p.extension(source).toLowerCase()}';
  final dir = Directory(p.join(libraryRoot, '.volti', 'audio'));
  await dir.create(recursive: true);
  final target = p.join(dir.path, name);
  final tmp = '$target.tmp';
  await File(source).copy(tmp);
  await File(tmp).rename(target);
  return name;
}

/// Löscht die Aufnahme eines Stücks (falls vorhanden).
Future<void> deleteAudioOf(String pdfPath, ScoreMeta meta) async {
  final path = audioPathOf(pdfPath, meta);
  if (path == null) return;
  final f = File(path);
  if (await f.exists()) await f.delete();
}
