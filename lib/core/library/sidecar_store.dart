import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../ink/score_annotations.dart';
import 'page_setup.dart';
import 'score_meta.dart';

/// Alles, was Volti zu einem PDF speichert: Infos (Titel, Komponist …) und
/// Anmerkungen. Liegt als kleine Datei direkt neben dem PDF:
///
///     Bach - Suite 1.pdf
///     Bach - Suite 1.pdf.volti.json
class ScoreSidecar {
  ScoreSidecar({ScoreMeta? meta, ScoreAnnotations? annotations, this.pages = PageSetup.empty})
    : meta = meta ?? ScoreMeta(),
      annotations = annotations ?? ScoreAnnotations();

  final ScoreMeta meta;
  final ScoreAnnotations annotations;

  /// Reihenfolge und Zuschnitt der Seiten (das PDF bleibt unverändert).
  final PageSetup pages;

  static const formatVersion = 2;

  static ScoreSidecar merge(ScoreSidecar a, ScoreSidecar b) => ScoreSidecar(
    meta: ScoreMeta.merge(a.meta, b.meta),
    annotations: ScoreAnnotations.merge(a.annotations, b.annotations),
    pages: PageSetup.merge(a.pages, b.pages),
  );

  Map<String, dynamic> toJson() => {
    'format': 'volti-score',
    'version': formatVersion,
    'meta': meta.toJson(),
    'strokes': annotations.toJson()['strokes'],
    if (annotations.allTexts.isNotEmpty) 'texts': annotations.toJson()['texts'],
    if (annotations.allStamps.isNotEmpty) 'stamps': annotations.toJson()['stamps'],
    if (annotations.allLayers.isNotEmpty) 'layers': annotations.toJson()['layers'],
    if (annotations.allLinks.isNotEmpty) 'links': annotations.toJson()['links'],
    if (annotations.allBookmarks.isNotEmpty) 'bookmarks': annotations.toJson()['bookmarks'],
    if (annotations.allTabs.isNotEmpty) 'tabs': annotations.toJson()['tabs'],
    if (pages.toJson() != null) 'pages': pages.toJson(),
  };

  /// Liest auch das alte Format aus Meilenstein 1 (nur Anmerkungen).
  static ScoreSidecar fromJson(Map<String, dynamic> json) => ScoreSidecar(
    meta: ScoreMeta.fromJson(json['meta'] as Map<String, dynamic>?),
    annotations: ScoreAnnotations.fromJson(json),
    pages: PageSetup.fromJson(json['pages'] as Map<String, dynamic>?),
  );
}

/// Liest und schreibt die Zusatzdateien neben den PDFs.
///
/// Das PDF selbst wird nie verändert. Liegt der Ordner in einem
/// Cloud-Ordner (Proton Drive, OneDrive, Dropbox …), wandern die Daten
/// automatisch mit. Beim Speichern wird immer mit dem aktuellen Stand auf der
/// Festplatte zusammengeführt, damit Änderungen eines anderen Geräts (oder
/// eines anderen Bildschirms in Volti) nie überschrieben werden.
class SidecarStore {
  const SidecarStore();

  static const suffix = '.volti.json';

  // Schreibvorgänge pro Datei nacheinander ausführen, nie gleichzeitig.
  static final Map<String, Future<void>> _locks = {};

  File fileFor(String pdfPath) => File('$pdfPath$suffix');

  Future<ScoreSidecar> load(String pdfPath) async {
    final file = fileFor(pdfPath);
    if (!await file.exists()) return ScoreSidecar();
    try {
      return ScoreSidecar.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } on FormatException {
      // Beschädigte Datei nicht überschreiben, sondern sichern.
      await file.copy('${file.path}.defekt-${DateTime.now().millisecondsSinceEpoch}');
      return ScoreSidecar();
    } on TypeError {
      await file.copy('${file.path}.defekt-${DateTime.now().millisecondsSinceEpoch}');
      return ScoreSidecar();
    }
  }

  /// Speichert Infos, Anmerkungen und/oder die Seiten-Einrichtung,
  /// zusammengeführt mit dem Stand auf der Festplatte. Gibt den gespeicherten
  /// Gesamtstand zurück.
  Future<ScoreSidecar> save(String pdfPath, {ScoreMeta? meta, ScoreAnnotations? annotations, PageSetup? pages}) {
    final previous = _locks[pdfPath] ?? Future.value();
    final result = previous.then((_) => _save(pdfPath, meta, annotations, pages));
    final done = result.then<void>((_) {}, onError: (_) {});
    _locks[pdfPath] = done;
    done.then((_) {
      if (identical(_locks[pdfPath], done)) _locks.remove(pdfPath);
    });
    return result;
  }

  Future<ScoreSidecar> _save(String pdfPath, ScoreMeta? meta, ScoreAnnotations? annotations, PageSetup? pages) async {
    final onDisk = await load(pdfPath);
    final merged = ScoreSidecar.merge(
      onDisk,
      ScoreSidecar(meta: meta, annotations: annotations, pages: pages ?? PageSetup.empty),
    );
    final file = fileFor(pdfPath);
    // Erst in eine temporäre Datei schreiben, dann umbenennen: So entsteht nie
    // eine halb geschriebene Datei (z. B. wenn der Akku leer wird).
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(merged.toJson()), flush: true);
    await tmp.rename(file.path);
    return merged;
  }
}
