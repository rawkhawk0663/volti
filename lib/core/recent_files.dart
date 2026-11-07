import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Merkt sich die zuletzt geöffneten Notenstücke.
///
/// Übergangslösung bis zur richtigen Bibliothek (Meilenstein 2).
class RecentFiles {
  static const _max = 20;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'recent.json'));
  }

  Future<List<String>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final list = (jsonDecode(await f.readAsString()) as List).cast<String>();
      return [for (final path in list) if (await File(path).exists()) path];
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> add(String path) async {
    final list = await load();
    list
      ..remove(path)
      ..insert(0, path);
    if (list.length > _max) list.removeRange(_max, list.length);
    await (await _file()).writeAsString(jsonEncode(list));
    return list;
  }

  Future<List<String>> remove(String path) async {
    final list = await load()
      ..remove(path);
    await (await _file()).writeAsString(jsonEncode(list));
    return list;
  }
}
