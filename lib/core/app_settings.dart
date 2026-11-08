import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Einstellungen und Daten, die nur auf *diesem* Gerät gelten und nicht
/// synchronisiert werden: wo die Bibliothek liegt, wann ein Stück zuletzt
/// geöffnet wurde.
class AppSettings {
  AppSettings._(this._file, this._data);

  final File _file;
  final Map<String, dynamic> _data;

  /// Für Tests: Einstellungen in einem bestimmten Ordner.
  static Future<AppSettings> loadFrom(Directory dir) async {
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'settings.json'));
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      try {
        data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    return AppSettings._(file, data);
  }

  static Future<AppSettings> load() async => loadFrom(await getApplicationSupportDirectory());

  String? get libraryRoot => _data['libraryRoot'] as String?;

  Future<void> setLibraryRoot(String? path) async {
    _data['libraryRoot'] = path;
    await _write();
  }

  Map<String, dynamic> get _usage => (_data['usage'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  /// Wann das Stück zuletzt geöffnet wurde (null = nie).
  DateTime? lastOpened(String pdfPath) {
    final v = (_usage[pdfPath] as Map?)?['opened'];
    return v is String ? DateTime.tryParse(v) : null;
  }

  Future<void> recordOpened(String pdfPath) async {
    final u = (_usage[pdfPath] ??= <String, dynamic>{}) as Map<String, dynamic>;
    u['opened'] = DateTime.now().toUtc().toIso8601String();
    await _write();
  }

  Future<void> _write() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data), flush: true);
    await tmp.rename(_file.path);
  }
}
