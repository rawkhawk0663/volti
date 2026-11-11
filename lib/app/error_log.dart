import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'version.dart';

/// Fehlerprotokoll: Was schiefgeht, landet in `fehler.log` im Datenordner
/// des Geräts. Der Besitzer kann es im Einstellungsfenster ansehen und
/// kopieren, so lassen sich Fehler finden, ohne zu raten.
class ErrorLog {
  ErrorLog._();

  static File? _file;
  static File? get file => _file;

  /// Grösser wird die Datei nicht: Dann bleibt nur der jüngere Teil.
  static const maxBytes = 512 * 1024;

  static String? _lastKey;
  static DateTime _lastAt = DateTime(2000);
  static int _repeats = 0;

  /// Protokoll in [dir] führen und alle unbehandelten Fehler auffangen.
  static void install(String dir) {
    _file = File(p.join(dir, 'fehler.log'));
    _trim();
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      record(d.exception, d.stack, where: d.context?.toDescription() ?? d.library);
      previous?.call(d);
    };
    PlatformDispatcher.instance.onError = (e, s) {
      record(e, s);
      return true;
    };
  }

  /// Einen Fehler aufschreiben. [where]: wobei er passiert ist (z. B. „Sync“).
  static void record(Object error, StackTrace? stack, {String? where}) {
    final f = _file;
    if (f == null) return;
    // Derselbe Fehler bei jedem Bild: nur einmal aufschreiben.
    final key = '$where|$error';
    final now = DateTime.now();
    if (key == _lastKey && now.difference(_lastAt) < const Duration(seconds: 10)) {
      _repeats++;
      _lastAt = now;
      return;
    }
    final b = StringBuffer();
    if (_repeats > 0) b.writeln('(vorheriger Fehler noch $_repeats-mal)');
    _lastKey = key;
    _lastAt = now;
    _repeats = 0;
    b.writeln('=== ${now.toIso8601String()} · Volti $voltiVersion · ${Platform.operatingSystem}');
    if (where != null && where.isNotEmpty) b.writeln('Bei: $where');
    b.writeln(error.toString().trim());
    final lines = (stack?.toString() ?? '').trim().split('\n').take(25).join('\n');
    if (lines.isNotEmpty) b.writeln(lines);
    b.writeln();
    try {
      f.writeAsStringSync(b.toString(), mode: FileMode.append);
    } catch (_) {}
  }

  /// Inhalt des Protokolls ('' = keine Fehler).
  static Future<String> read() async {
    final f = _file;
    if (f == null || !await f.exists()) return '';
    try {
      return await f.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    _lastKey = null;
    _repeats = 0;
    try {
      await _file?.delete();
    } catch (_) {}
  }

  static void _trim() {
    final f = _file;
    if (f == null) return;
    try {
      if (!f.existsSync() || f.lengthSync() <= maxBytes) return;
      final bytes = f.readAsBytesSync();
      var keep = bytes.sublist(bytes.length - maxBytes ~/ 2);
      // Am Anfang eines Eintrags weitermachen.
      final text = String.fromCharCodes(keep);
      final start = text.indexOf('=== ');
      if (start > 0) keep = keep.sublist(start);
      f.writeAsBytesSync(keep);
    } catch (_) {}
  }
}
