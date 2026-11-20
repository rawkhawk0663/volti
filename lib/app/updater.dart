import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'open_url.dart';
import 'version.dart';
import 'l10n.dart';

/// Eine Version im öffentlichen Download-Projekt auf GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.number,
    required this.page,
    this.windowsZip,
    this.androidApk,
    this.notes = '',
  });
  final String tag;
  final int number;
  final Uri page;
  final Uri? windowsZip;
  final Uri? androidApk;
  final String notes;
}

/// Sucht nach neuen Versionen und installiert sie (unter Windows).
///
/// Die fertigen Downloads liegen in einem eigenen, öffentlichen Projekt
/// ([repo], ohne Programmcode) – das eigentliche Projekt bleibt privat.
class Updater {
  Updater._();

  static const repo = 'rawkhawk0663/volti-releases';

  /// Laufende Nummer aus „v0.1.42“ bzw. „v1.0.60“ (null = unbekannt, z. B.
  /// Testversion). Sie zählt bei jedem Build weiter, auch über den Wechsel
  /// von 0.1 auf 1.0 hinweg.
  static int? numberOf(String tag) => partsOf(tag)?.$3;

  /// Alle drei Teile einer Version („v1.0.60“ → 1, 0, 60).
  static (int, int, int)? partsOf(String tag) {
    final m = RegExp(r'v?(\d+)\.(\d+)\.(\d+)').firstMatch(tag);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// Ist Version [a] neuer als [b]? Unbekannte Versionen gelten als ganz alt.
  static bool newerThan(String a, String b) {
    final x = partsOf(a), y = partsOf(b);
    if (x == null) return false;
    if (y == null) return true;
    if (x.$1 != y.$1) return x.$1 > y.$1;
    if (x.$2 != y.$2) return x.$2 > y.$2;
    return x.$3 > y.$3;
  }

  static int get currentNumber => numberOf(voltiVersion) ?? 0;

  /// Neueste Version (null = keine gefunden). Wirft bei Netzwerkfehlern.
  static Future<UpdateInfo?> latest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$repo/releases/latest'));
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'Volti-App')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        throw HttpException(tr('GitHub antwortet mit ${res.statusCode}', 'GitHub replies with ${res.statusCode}'));
      }
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final tag = j['tag_name'] as String? ?? '';
      final number = numberOf(tag);
      if (number == null) return null;
      Uri? asset(String name) {
        for (final a in j['assets'] as List<dynamic>? ?? const []) {
          if (a is Map && a['name'] == name) return Uri.tryParse(a['browser_download_url'] as String? ?? '');
        }
        return null;
      }

      return UpdateInfo(
        tag: tag,
        number: number,
        page: Uri.parse(j['html_url'] as String? ?? 'https://github.com/$repo/releases/latest'),
        windowsZip: asset('Volti-Windows.zip'),
        androidApk: asset('Volti-Android.apk'),
        // Erste Zeile ist „**Neu / New:** …“ – ohne Formatierung und Vorsatz zeigen.
        notes: (j['body'] as String? ?? '').replaceAll('**', '').replaceFirst(RegExp(r'^\s*Neu / New:\s*'), '').trim(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool isNewer(UpdateInfo u) => newerThan(u.tag, voltiVersion);

  /// Kann sich Volti hier selbst ersetzen? (Windows, Ordner beschreibbar.)
  static Future<bool> canSelfInstall() async {
    if (!Platform.isWindows) return false;
    final dir = File(Platform.resolvedExecutable).parent;
    final probe = File(p.join(dir.path, '.volti-update-test'));
    try {
      await probe.writeAsString('x');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Windows: Update herunterladen, auspacken und Volti durch die neue
  /// Version ersetzen. Windows erlaubt, ein laufendes Programm umzubenennen:
  /// Volti schiebt seine Dateien beiseite ([swapFiles]), legt die neuen hin,
  /// startet die neue Version und beendet sich sofort. Kein Skript, kein
  /// schwarzes Fenster. Die Noten liegen in einem anderen Ordner und bleiben
  /// unberührt. [onProgress]: 0..1.
  static Future<void> installWindows(UpdateInfo u, {void Function(double)? onProgress}) async {
    final url = u.windowsZip;
    if (url == null) {
      throw FileSystemException(tr('In dieser Version fehlt die Windows-Datei.', 'This version has no Windows file.'));
    }
    final work = Directory(p.join((await getTemporaryDirectory()).path, 'volti-update-${u.number}'));
    if (await work.exists()) await work.delete(recursive: true);
    await work.create(recursive: true);
    final zip = File(p.join(work.path, 'Volti-Windows.zip'));

    // Herunterladen
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, 'Volti-App');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException(tr('Download fehlgeschlagen (${res.statusCode})', 'Download failed (${res.statusCode})'));
      }
      final total = res.contentLength;
      var done = 0;
      final sink = zip.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) onProgress?.call(done / total * 0.9);
      }
      await sink.close();
    } finally {
      client.close(force: true);
    }

    // Auspacken – im Hintergrund, damit Volti nicht einfriert („Keine Rückmeldung“).
    final unpacked = Directory(p.join(work.path, 'neu'));
    final zipPath = zip.path, outPath = unpacked.path;
    await Isolate.run(() => extractFileToDisk(zipPath, outPath));
    if (!await File(p.join(unpacked.path, 'Volti.exe')).exists()) {
      throw FileSystemException(
        tr('Das Update ist unvollständig (Volti.exe fehlt).', 'The update is incomplete (Volti.exe is missing).'),
      );
    }
    onProgress?.call(0.95);

    final target = File(Platform.resolvedExecutable).parent.path;
    final log = await _logFile();
    final lines = <String>['Update ${u.tag}', 'Ziel ${u.number}', 'Heruntergeladen und ausgepackt'];
    Future<void> writeLog() => log.writeAsString('${lines.join('\r\n')}\r\n');
    await writeLog();

    // Dateien austauschen (im Hintergrund). Geht etwas nicht, wird alles
    // zurückgestellt, und Volti läuft unverändert weiter.
    final swap = await Isolate.run(() => swapFiles(outPath, target));
    lines.addAll(swap.log);
    if (!swap.ok) {
      try {
        await log.delete();
      } catch (_) {}
      throw FileSystemException(
        tr(
          'Die neuen Dateien liessen sich nicht in den Volti-Ordner legen. ${swap.log.last}',
          'The new files could not be put into the Volti folder. ${swap.log.last}',
        ),
      );
    }
    lines.add('FERTIG');
    await writeLog();
    onProgress?.call(1);

    // Neue Version starten (ein Fensterprogramm, also ohne Konsole) …
    await Process.start(
      p.join(target, 'Volti.exe'),
      const [],
      workingDirectory: target,
      mode: ProcessStartMode.detached,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // … und diese hart beenden. Ein normales Beenden kann hängen bleiben
    // (z. B. wenn die Ton-Bibliothek noch aufräumt). Gespeichert ist längst alles.
    quitNow();
  }

  /// Volti sofort beenden (Windows: TerminateProcess).
  static Never quitNow() {
    try {
      Process.killPid(pid, ProcessSignal.sigkill);
    } catch (_) {}
    exit(0);
  }

  /// Endung der beiseitegeschobenen alten Dateien.
  static const oldSuffix = '.volti-alt';

  /// Legt alle Dateien aus [newDir] nach [targetDir]. Bestehende Dateien
  /// werden erst umbenannt (`<name>.<zeit>.volti-alt`, das geht auch, wenn
  /// Volti sie gerade benutzt), dann kommt die neue Datei an ihren Platz.
  /// Unveränderte Dateien bleiben, wie sie sind. Schlägt ein Schritt fehl,
  /// wird alles zurückgestellt (ok = false).
  static Future<({bool ok, List<String> log})> swapFiles(String newDir, String targetDir) async {
    final log = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final files = <String>[];
    await for (final e in Directory(newDir).list(recursive: true, followLinks: false)) {
      if (e is File) files.add(p.relative(e.path, from: newDir));
    }
    files.sort();
    // Was schon getan ist, für das Zurückstellen: (Ziel, beiseitegeschoben unter).
    final done = <(String, String?)>[];
    var skipped = 0;
    String? current;
    try {
      for (final rel in files) {
        current = rel;
        final src = File(p.join(newDir, rel));
        final dst = File(p.join(targetDir, rel));
        String? moved;
        if (await dst.exists()) {
          if (await _sameContent(src, dst)) {
            skipped++;
            continue;
          }
          moved = '${dst.path}.$stamp$oldSuffix';
          await dst.rename(moved);
        } else {
          await dst.parent.create(recursive: true);
        }
        done.add((dst.path, moved));
        await src.copy(dst.path);
      }
      log.add('Ausgetauscht: ${done.length} Dateien, unverändert: $skipped');
      return (ok: true, log: log);
    } catch (e) {
      log.add('Fehler bei $current: $e');
      for (final (path, moved) in done.reversed) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
          if (moved != null) await File(moved).rename(path);
        } catch (e2) {
          log.add('Zurückstellen von $path ging nicht: $e2');
        }
      }
      log.add('Alles zurückgestellt');
      return (ok: false, log: log);
    }
  }

  static Future<bool> _sameContent(File a, File b) async {
    try {
      if (await a.length() != await b.length()) return false;
      final x = await a.readAsBytes(), y = await b.readAsBytes();
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Beim Start: alte, beiseitegeschobene Dateien und heruntergeladene
  /// Updates wegräumen. Was noch benutzt wird, bleibt bis zum nächsten Mal.
  static Future<void> cleanUp() async {
    if (!Platform.isWindows) return;
    await cleanUpDir(File(Platform.resolvedExecutable).parent.path);
    try {
      await for (final e in (await getTemporaryDirectory()).list(followLinks: false)) {
        if (e is Directory && p.basename(e.path).startsWith('volti-update-')) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Löscht alle `*.volti-alt` unter [dir].
  static Future<void> cleanUpDir(String dir) async {
    try {
      await for (final e in Directory(dir).list(recursive: true, followLinks: false)) {
        if (e is File && e.path.endsWith(oldSuffix)) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<File> _logFile() async => File(p.join((await getApplicationSupportDirectory()).path, 'update.log'));

  /// Nach einem Update (beim Start): Hat es geklappt? Gibt eine Meldung
  /// zurück (null = es lief kein Update) und räumt das Protokoll weg.
  static Future<({bool ok, String message})?> lastUpdateResult() async {
    if (!Platform.isWindows) return null;
    try {
      final f = await _logFile();
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      await f.delete();
      final goal = int.tryParse(RegExp(r'Ziel (\d+)').firstMatch(text)?.group(1) ?? '');
      if (text.contains('FERTIG') && (goal == null || currentNumber >= goal)) {
        return (
          ok: true,
          message: tr(
            'Update installiert – jetzt läuft Volti $voltiVersion.',
            'Update installed – Volti $voltiVersion is now running.',
          ),
        );
      }
      final reason = text.contains('FERTIG')
          ? tr(
              'Die neuen Dateien sind da, aber es läuft noch die alte Version.',
              'The new files are there, but the old version is still running.',
            )
          : tr('Das Ersetzen wurde nicht abgeschlossen.', 'Replacing the files was not completed.');
      return (
        ok: false,
        message: tr(
          'Das Update ging nicht: $reason Bitte lade es von Hand herunter.',
          'The update didn’t work: $reason Please download it by hand.',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Seite mit dem Download im Browser öffnen (Android, oder wenn Volti sich
  /// nicht selbst ersetzen kann).
  static Future<void> openPage(UpdateInfo u) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [u.page.toString()]);
      } else {
        // Android: Browser bzw. System öffnet die Download-Seite.
        await openUrl(u.page);
      }
    } catch (_) {}
  }
}
