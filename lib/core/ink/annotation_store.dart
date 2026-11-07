import 'dart:convert';
import 'dart:io';

import 'score_annotations.dart';

/// Speichert Anmerkungen als kleine JSON-Datei direkt neben dem PDF:
///
///     Bach - Suite 1.pdf
///     Bach - Suite 1.pdf.volti.json
///
/// Das PDF selbst wird nie verändert. Liegt der Ordner in einem
/// Cloud-Ordner (Proton Drive, OneDrive, Dropbox …), wandern die
/// Anmerkungen automatisch mit.
class AnnotationStore {
  const AnnotationStore();

  static const suffix = '.volti.json';

  File fileFor(String pdfPath) => File('$pdfPath$suffix');

  Future<ScoreAnnotations> load(String pdfPath) async {
    final file = fileFor(pdfPath);
    if (!await file.exists()) return ScoreAnnotations();
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return ScoreAnnotations.fromJson(json);
    } on FormatException {
      // Beschädigte Datei nicht überschreiben, sondern sichern.
      await file.copy('${file.path}.defekt-${DateTime.now().millisecondsSinceEpoch}');
      return ScoreAnnotations();
    }
  }

  /// Speichert sicher: zuerst in eine temporäre Datei, dann umbenennen.
  /// So entsteht nie eine halb geschriebene Datei (z. B. bei Akku leer).
  ///
  /// Hat ein anderes Gerät die Datei inzwischen geändert (Sync), wird
  /// deren Inhalt vorher zusammengeführt statt überschrieben.
  Future<ScoreAnnotations> save(String pdfPath, ScoreAnnotations annotations) async {
    final file = fileFor(pdfPath);
    var toWrite = annotations;
    if (await file.exists()) {
      final onDisk = await load(pdfPath);
      toWrite = ScoreAnnotations.merge(annotations, onDisk);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(toWrite.toJson()), flush: true);
    await tmp.rename(file.path);
    return toWrite;
  }
}
