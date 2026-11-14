import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Einstellungen und Daten, die nur auf *diesem* Gerät gelten und nicht
/// synchronisiert werden, z. B. wann ein Stück zuletzt geöffnet wurde.
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

  /// Selbst gewählter Bibliotheksordner aus Version 0.1.2. Wird beim Start
  /// einmalig in Voltis Datenordner übernommen.
  String? get legacyLibraryRoot => _data['libraryRoot'] as String?;

  Future<void> clearLegacyLibraryRoot() async {
    _data.remove('libraryRoot');
    await _write();
  }

  /// Ordner, mit dem Volti seinen Datenordner abgleicht (z. B. in Proton Drive).
  String? get syncFolder => _data['syncFolder'] as String?;

  Future<void> setSyncFolder(String? path) async {
    if (path == null) {
      _data.remove('syncFolder');
    } else {
      _data['syncFolder'] = path;
    }
    await _write();
  }

  /// Einfache Ja/Nein-Einstellungen dieses Geräts (z. B. Vollbild).
  bool flag(String name, {required bool orElse}) => (_data['flags'] as Map?)?[name] as bool? ?? orElse;

  Future<void> setFlag(String name, bool value) async {
    final flags = (_data['flags'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    flags[name] = value;
    await _write();
  }

  /// Einfache Text-Einstellungen dieses Geräts.
  String? text(String name) => (_data['texts'] as Map?)?[name] as String?;

  Future<void> setText(String name, String value) async {
    final texts = (_data['texts'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    texts[name] = value;
    await _write();
  }

  Future<void> removeText(String name) async {
    (_data['texts'] as Map?)?.remove(name);
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
