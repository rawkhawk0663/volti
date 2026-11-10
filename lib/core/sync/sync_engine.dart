import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../library/folders.dart';
import '../library/setlist.dart';
import '../library/sidecar_store.dart';
import 'sync_store.dart';

/// Was bei einem Abgleich passiert ist.
class SyncReport {
  int downloaded = 0;
  int uploaded = 0;
  int deletedHere = 0;
  int deletedThere = 0;
  int merged = 0;
  int conflictCopiesResolved = 0;

  /// Dateien, die diesmal nicht abgeglichen werden konnten (z. B. weil der
  /// Cloud-Dienst sie gerade selbst herunterlädt). Sie kommen beim nächsten
  /// Abgleich wieder dran; alles andere wurde trotzdem abgeglichen.
  final List<String> failed = [];

  /// Hat sich auf diesem Gerät etwas geändert (Bibliothek neu einlesen)?
  bool get changedLocally => downloaded > 0 || deletedHere > 0 || merged > 0;

  @override
  String toString() =>
      '↓$downloaded ↑$uploaded ✕hier $deletedHere ✕dort $deletedThere ⇄$merged Konflikte $conflictCopiesResolved';
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Gleicht Voltis Datenordner mit einem Sync-Ziel ab (in beide Richtungen).
///
/// Prinzip:
/// * **PDFs und Setlists** werden kopiert. Ob eine fehlende Datei neu ist oder
///   gelöscht wurde, entscheidet der Stand des letzten Abgleichs ("Basis"),
///   den jedes Gerät für sich speichert.
/// * **Infos und Anmerkungen** (`.volti.json`) werden immer zusammengeführt,
///   nie überschrieben. So geht nichts verloren, auch wenn auf zwei Geräten
///   gleichzeitig geschrieben wurde.
/// * **Konfliktkopien**, die ein Cloud-Dienst anlegt, werden erkannt,
///   zusammengeführt und aufgeräumt.
/// * **Sicherheitsbremse:** Fehlt der Sync-Ordner oder würde ein Abgleich
///   mehr als die Hälfte der Noten löschen, wird abgebrochen.
class SyncEngine {
  SyncEngine({required this.localRoot, required this.remote, required this.baseFile});

  final String localRoot;
  final SyncStore remote;

  /// Gerätespezifische Datei mit dem Stand des letzten Abgleichs.
  final File baseFile;

  late final FolderSyncStore _local = FolderSyncStore(localRoot);
  final _sidecars = const SidecarStore();

  static const markerPath = '.volti/library.json';

  /// Richtet ein leeres Sync-Ziel ein (Markierungsdatei).
  static Future<void> initializeRemote(SyncStore remote) async {
    if (await remote.exists(markerPath)) return;
    await remote.writeString(markerPath, jsonEncode({'format': 'volti-library', 'version': 1}));
  }

  Future<SyncReport> run() async {
    final report = SyncReport();
    if (!await remote.exists(markerPath)) {
      throw SyncException(
        'Der Sync-Ordner ist nicht erreichbar. Läuft Proton Drive, und ist der Ordner noch vorhanden?',
      );
    }

    await _resolveRemoteConflictCopies(report);

    final localFiles = await _local.list();
    final remoteFiles = await remote.list();
    final base = await _loadBase();

    bool isPdf(String rel) => rel.startsWith('Noten/') && rel.toLowerCase().endsWith('.pdf');
    // Bilder eigener Stempel: wie PDFs (neu oder gelöscht, nie verändert).
    bool isStampImage(String rel) => rel.startsWith('.volti/stamps/') && rel.endsWith('.png');
    // Setlists, Stift-Vorlagen, Liste der eigenen Stempel: ganze Datei, die
    // jüngste Fassung gewinnt.
    bool isSetlist(String rel) =>
        rel.startsWith('.volti/setlists/') || rel == '.volti/presets.json' || rel == '.volti/stamps.json';
    // Ordner der Bibliothek: pro Ordner zusammengeführt.
    bool isFolders(String rel) => FolderStore.files.contains(rel);

    // ---------------------------------------------------- Sicherheitsbremse
    final localPdfs = localFiles.where(isPdf).toSet();
    final wouldDelete = localPdfs.where((r) => base.contains(r) && !remoteFiles.contains(r)).length;
    if (localPdfs.length > 3 && wouldDelete > localPdfs.length / 2) {
      throw SyncException(
        'Der Abgleich würde $wouldDelete von ${localPdfs.length} Stücken auf diesem Gerät löschen. '
        'Zur Sicherheit wurde nichts verändert. Prüfe bitte den Sync-Ordner.',
      );
    }

    final newBase = <String>{};

    // -------------------------------------------------- PDFs und Setlists
    final whole = {
      ...localFiles,
      ...remoteFiles,
      ...base,
    }.where((r) => isPdf(r) || isSetlist(r) || isStampImage(r) || isFolders(r));
    for (final rel in whole) {
      final l = localFiles.contains(rel), r = remoteFiles.contains(rel), b = base.contains(rel);
      if (l && r) {
        // Liegt auf beiden Seiten: bleibt in der Basis, auch wenn das
        // Zusammenführen diesmal nicht klappt.
        newBase.add(rel);
        await _safely(rel, report, () async {
          if (isSetlist(rel)) await _syncSetlist(rel, report);
          if (isFolders(rel)) await _syncFolders(rel, report);
        });
      } else if (l) {
        if (b) {
          await _safely(rel, report, () async {
            await _deleteLocal(rel);
            report.deletedHere++;
          });
        } else if (await _safely(rel, report, () => remote.writeStream(rel, _local.openRead(rel)))) {
          report.uploaded++;
          newBase.add(rel);
        }
      } else if (r) {
        if (b) {
          await _safely(rel, report, () async {
            await remote.delete(rel);
            if (isPdf(rel)) await remote.delete('$rel${SidecarStore.suffix}');
            report.deletedThere++;
          });
        } else if (await _safely(rel, report, () => _local.writeStream(rel, remote.openRead(rel)))) {
          report.downloaded++;
          newBase.add(rel);
        }
      }
    }

    // ------------------------------------------ Infos und Anmerkungen
    for (final pdf in newBase.where(isPdf)) {
      final rel = '$pdf${SidecarStore.suffix}';
      await _safely(rel, report, () => _syncSidecar(rel, report));
    }

    await _saveBase(newBase);
    return report;
  }

  /// Eine Datei abgleichen; klappt es nicht, nach kurzer Pause ein zweites
  /// Mal. Scheitert es wieder, wird sie übersprungen (und beim nächsten
  /// Abgleich erneut versucht) – der Rest läuft weiter.
  Future<bool> _safely(String rel, SyncReport report, Future<void> Function() action) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await action();
        return true;
      } catch (_) {
        if (attempt == 0) await Future<void>.delayed(retryDelay);
      }
    }
    report.failed.add(rel);
    return false;
  }

  /// Pause vor dem zweiten Versuch (in Tests kürzer).
  Duration retryDelay = const Duration(seconds: 2);

  Future<void> _deleteLocal(String rel) async {
    await _local.delete(rel);
    if (rel.toLowerCase().endsWith('.pdf')) await _local.delete('$rel${SidecarStore.suffix}');
  }

  /// Infos/Anmerkungen beider Seiten zusammenführen und überall speichern.
  Future<void> _syncSidecar(String rel, SyncReport report) async {
    final l = await _local.exists(rel), r = await remote.exists(rel);
    if (!l && !r) return;
    final localPdfPath = p.joinAll([
      localRoot,
      ...rel.substring(0, rel.length - SidecarStore.suffix.length).split('/'),
    ]);
    final localJson = l ? await _local.readString(rel) : null;
    final remoteJson = r ? await remote.readString(rel) : null;
    if (localJson != null && localJson == remoteJson) return;

    final local = localJson == null ? null : _parseSidecar(localJson);
    final rem = remoteJson == null ? null : _parseSidecar(remoteJson);
    final merged = local == null
        ? rem!
        : rem == null
        ? local
        : ScoreSidecar.merge(local, rem);
    final mergedJson = _encode(merged);

    if (localJson == null || _encode(local!) != mergedJson) {
      // Über den SidecarStore, damit gleichzeitiges Speichern aus der
      // Notenansicht nicht verloren geht.
      await _sidecars.save(localPdfPath, meta: merged.meta, annotations: merged.annotations, pages: merged.pages);
      report.merged++;
    }
    if (remoteJson == null || _encode(rem!) != mergedJson) {
      await remote.writeString(rel, mergedJson);
      if (remoteJson != null) report.merged++;
    }
  }

  static ScoreSidecar? _tryParseSidecar(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final format = map['format'];
      if (format != 'volti-score' && format != 'volti-annotations') return null;
      return ScoreSidecar.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static ScoreSidecar _parseSidecar(String json) => _tryParseSidecar(json) ?? ScoreSidecar();

  static String _encode(ScoreSidecar s) => const JsonEncoder.withIndent(' ').convert(s.toJson());

  /// Setlist oder Stift-Vorlagen: die zuletzt geänderte Fassung gewinnt
  /// (Feld `modified` in der Datei).
  Future<void> _syncSetlist(String rel, SyncReport report) async {
    final lj = await _local.readString(rel), rj = await remote.readString(rel);
    if (lj == rj) return;
    final lm = _modifiedOf(lj), rm = _modifiedOf(rj);
    if (rm == null) {
      await remote.writeString(rel, lj);
    } else if (lm == null || rm.isAfter(lm)) {
      await _local.writeString(rel, rj);
      report.merged++;
    } else if (lm.isAfter(rm)) {
      await remote.writeString(rel, lj);
    }
  }

  /// Ordnerliste: pro Ordner gewinnt die jüngste Fassung.
  Future<void> _syncFolders(String rel, SyncReport report) async {
    final lj = await _local.readString(rel), rj = await remote.readString(rel);
    if (lj == rj) return;
    List<ScoreFolder> parse(String j) {
      try {
        return FolderStore.decode(j);
      } catch (_) {
        return [];
      }
    }

    final l = parse(lj), r = parse(rj);
    final merged = mergeFolders(l, r);
    String key(List<ScoreFolder> f) => jsonEncode([for (final x in mergeFolders(f, const [])) x.toJson()]);
    final m = key(merged);
    final out = FolderStore.encode(merged);
    if (key(l) != m) {
      await _local.writeString(rel, out);
      report.merged++;
    }
    if (key(r) != m) await remote.writeString(rel, out);
  }

  static DateTime? _modifiedOf(String json) {
    try {
      final m = (jsonDecode(json) as Map<String, dynamic>)['modified'];
      return m is String ? DateTime.parse(m) : null;
    } catch (_) {
      return null;
    }
  }

  static Setlist? _tryParseSetlist(String json) {
    try {
      return Setlist.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Cloud-Dienste legen bei gleichzeitigen Änderungen manchmal Kopien an,
  /// z. B. "Stück.pdf.volti (Konflikt).json". Diese werden in die richtige
  /// Datei zusammengeführt und danach gelöscht.
  Future<void> _resolveRemoteConflictCopies(SyncReport report) async {
    final files = await remote.list();
    final pdfs = files.where((f) => f.startsWith('Noten/') && f.toLowerCase().endsWith('.pdf')).toList()
      ..sort((a, b) => b.length.compareTo(a.length)); // längster Name zuerst
    for (final f in files) {
      if (f.startsWith('Noten/') && f.endsWith('.json')) {
        if (pdfs.any((pdf) => f == '$pdf${SidecarStore.suffix}')) continue;
        final owner = pdfs.where((pdf) => f.startsWith(pdf)).firstOrNull;
        if (owner == null) continue;
        final copy = _tryParseSidecar(await remote.readString(f));
        if (copy == null) continue;
        final target = '$owner${SidecarStore.suffix}';
        final main = await remote.exists(target) ? _parseSidecar(await remote.readString(target)) : ScoreSidecar();
        await remote.writeString(target, _encode(ScoreSidecar.merge(main, copy)));
        await remote.delete(f);
        report.conflictCopiesResolved++;
      } else if (f.startsWith('.volti/setlists/')) {
        final s = _tryParseSetlist(await remote.readString(f));
        if (s == null || f == '.volti/setlists/${s.id}.json') continue;
        final target = '.volti/setlists/${s.id}.json';
        final main = await remote.exists(target) ? _tryParseSetlist(await remote.readString(target)) : null;
        if (main == null || s.modified.isAfter(main.modified)) {
          await remote.writeString(target, const JsonEncoder.withIndent(' ').convert(s.toJson()));
        }
        await remote.delete(f);
        report.conflictCopiesResolved++;
      }
    }
  }

  Future<Set<String>> _loadBase() async {
    if (!await baseFile.exists()) return {};
    try {
      return (jsonDecode(await baseFile.readAsString()) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveBase(Set<String> base) async {
    await baseFile.parent.create(recursive: true);
    final tmp = File('${baseFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(base.toList()..sort()), flush: true);
    await tmp.rename(baseFile.path);
  }
}
