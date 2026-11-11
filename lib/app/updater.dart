import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'version.dart';

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

  /// Laufende Nummer aus „v0.1.42“ (null = unbekannt, z. B. Testversion).
  static int? numberOf(String tag) {
    final m = RegExp(r'v?\d+\.\d+\.(\d+)').firstMatch(tag);
    return m == null ? null : int.tryParse(m.group(1)!);
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
      if (res.statusCode != 200) throw HttpException('GitHub antwortet mit ${res.statusCode}');
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
        notes: (j['body'] as String? ?? '').trim(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool isNewer(UpdateInfo u) => u.number > currentNumber;

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
  /// Version ersetzen lassen. Ein kleines Skript wartet, bis Volti beendet
  /// ist, kopiert die neuen Dateien und startet Volti neu. Die Noten liegen in
  /// einem anderen Ordner und bleiben unberührt. [onProgress]: 0..1.
  static Future<void> installWindows(UpdateInfo u, {void Function(double)? onProgress}) async {
    final url = u.windowsZip;
    if (url == null) throw const FileSystemException('In dieser Version fehlt die Windows-Datei.');
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
      if (res.statusCode != 200) throw HttpException('Download fehlgeschlagen (${res.statusCode})');
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

    // Auspacken
    final unpacked = Directory(p.join(work.path, 'neu'));
    // Im Hintergrund auspacken, damit Volti nicht einfriert („Keine Rückmeldung“).
    final zipPath = zip.path, outPath = unpacked.path;
    await Isolate.run(() => extractFileToDisk(zipPath, outPath));
    if (!await File(p.join(unpacked.path, 'Volti.exe')).exists()) {
      throw const FileSystemException('Das Update ist unvollständig (Volti.exe fehlt).');
    }
    onProgress?.call(1);

    // Ersetzen, sobald Volti beendet ist – und neu starten. Ein einfaches
    // Windows-Skript (cmd) erledigt das und schreibt jeden Schritt ins
    // Protokoll; beim nächsten Start meldet Volti, ob es geklappt hat.
    final target = File(Platform.resolvedExecutable).parent.path;
    final log = await _logFile();
    await log.writeAsString('Update ${u.tag}\r\nHeruntergeladen und ausgepackt\r\n');
    final script = File(p.join(work.path, 'update.cmd'));
    final me = pid;
    await script.writeAsString(
      '@echo off\r\n'
      'chcp 65001 >nul\r\n'
      'set /a n=0\r\n'
      ':wait\r\n'
      // Warten, bis Volti beendet ist (höchstens rund eine Minute).
      'tasklist /FI "PID eq $me" 2>nul | find "$me" >nul\r\n'
      'if not errorlevel 1 (\r\n'
      '  set /a n+=1\r\n'
      '  if %n% GEQ 60 goto copy\r\n'
      '  ping -n 2 127.0.0.1 >nul\r\n'
      '  goto wait\r\n'
      ')\r\n'
      ':copy\r\n'
      'ping -n 2 127.0.0.1 >nul\r\n'
      'echo Volti beendet, kopiere >> "${log.path}"\r\n'
      'robocopy "${unpacked.path}" "$target" /E /R:10 /W:1 /NFL /NDL /NJH /NJS /NP >> "${log.path}"\r\n'
      'if %ERRORLEVEL% GEQ 8 (echo FEHLER beim Kopieren %ERRORLEVEL% >> "${log.path}") else (echo FERTIG >> "${log.path}")\r\n'
      'start "" "${p.join(target, 'Volti.exe')}"\r\n',
    );
    await Process.start('cmd.exe', ['/c', script.path], mode: ProcessStartMode.detached);
    // Kurz stehen lassen, damit man sieht, dass Volti absichtlich neu startet.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    exit(0);
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
      if (text.contains('FERTIG')) return (ok: true, message: 'Update installiert – jetzt läuft Volti $voltiVersion.');
      final reason = text.contains('FEHLER')
          ? 'Die neuen Dateien liessen sich nicht in den Volti-Ordner kopieren.'
          : 'Das Ersetzen wurde nicht abgeschlossen.';
      return (ok: false, message: 'Das Update ging nicht: $reason Bitte lade es von Hand herunter.');
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
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [u.page.toString()]);
      }
    } catch (_) {}
  }
}
