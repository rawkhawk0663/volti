import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../app/l10n.dart';
import 'cloud_auth.dart';
import 'sync_store.dart';

/// Eine Datei beim Cloud-Dienst.
class RemoteEntry {
  const RemoteEntry({required this.path, required this.rev, this.id});

  /// Relativer Pfad ('/' als Trenner), z. B. `Noten/x.pdf`.
  final String path;

  /// Kennzeichen des Inhalts: ändert sich bei jeder Änderung der Datei.
  final String rev;

  /// Kennung beim Dienst (Google Drive), sonst null.
  final String? id;
}

/// Was ein Cloud-Dienst können muss (Dropbox, Google Drive, in Tests ein
/// Speicher im Arbeitsspeicher).
abstract class CloudApi {
  /// Alle Dateien von Volti beim Dienst.
  Future<List<RemoteEntry>> listAll();
  Future<List<int>> download(RemoteEntry e);

  /// Hochladen; [existing] ist die bisherige Datei an diesem Pfad (oder null).
  Future<RemoteEntry> upload(String path, List<int> bytes, RemoteEntry? existing);
  Future<void> delete(RemoteEntry e);
}

/// Ein Cloud-Dienst als Sync-Ziel.
///
/// Der Abgleich liest bei jedem Durchgang die Infos und Anmerkungen aller
/// Stücke. Damit das über das Internet nicht jedes Mal alles herunterlädt,
/// werden kleine Dateien (.json) mit ihrem Kennzeichen ([RemoteEntry.rev]) auf
/// dem Gerät zwischengespeichert: Hat sich eine Datei nicht geändert, kommt
/// sie aus dem Zwischenspeicher.
class CloudSyncStore implements SyncStore {
  CloudSyncStore(this.api, {required this.cacheDir});

  final CloudApi api;
  final String cacheDir;

  Map<String, RemoteEntry>? _entries;

  Future<Map<String, RemoteEntry>> _listing() async {
    if (_entries != null) return _entries!;
    await list();
    return _entries!;
  }

  @override
  Future<Set<String>> list() async {
    final all = await api.listAll();
    _entries = {
      for (final e in all)
        if (isSyncedPath(e.path)) e.path: e,
    };
    return _entries!.keys.toSet();
  }

  @override
  Future<bool> exists(String rel) async => (await _listing()).containsKey(rel);

  @override
  String? localPath(String rel) => null;

  File _cacheFile(String rel) => File(p.join(cacheDir, '${sha1.convert(utf8.encode(rel))}.cache'));

  @override
  Future<String> readString(String rel) async {
    final e = (await _listing())[rel];
    if (e == null) throw FileSystemException(tr('Datei fehlt beim Dienst', 'File missing at the service'), rel);
    final cache = _cacheFile(rel);
    try {
      if (await cache.exists()) {
        final text = await cache.readAsString();
        final nl = text.indexOf('\n');
        if (nl > 0 && text.substring(0, nl) == e.rev) return text.substring(nl + 1);
      }
    } catch (_) {}
    final content = utf8.decode(await api.download(e));
    await _remember(rel, e.rev, content);
    return content;
  }

  Future<void> _remember(String rel, String rev, String content) async {
    try {
      await Directory(cacheDir).create(recursive: true);
      await _cacheFile(rel).writeAsString('$rev\n$content');
    } catch (_) {}
  }

  @override
  Stream<List<int>> openRead(String rel) async* {
    final e = (await _listing())[rel];
    if (e == null) throw FileSystemException(tr('Datei fehlt beim Dienst', 'File missing at the service'), rel);
    yield await api.download(e);
  }

  @override
  Future<void> writeString(String rel, String content) async {
    final e = await _upload(rel, utf8.encode(content));
    await _remember(rel, e.rev, content);
  }

  @override
  Future<void> writeStream(String rel, Stream<List<int>> data) async {
    final bytes = <int>[];
    await for (final chunk in data) {
      bytes.addAll(chunk);
    }
    await _upload(rel, bytes);
  }

  Future<RemoteEntry> _upload(String rel, List<int> bytes) async {
    final entries = await _listing();
    final e = await api.upload(rel, bytes, entries[rel]);
    entries[rel] = e;
    return e;
  }

  @override
  Future<void> delete(String rel) async {
    final entries = await _listing();
    final e = entries.remove(rel);
    if (e != null) await api.delete(e);
    try {
      await _cacheFile(rel).delete();
    } catch (_) {}
  }
}

// ------------------------------------------------------------------- HTTP

class CloudHttpException implements Exception {
  CloudHttpException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => tr('Fehler beim Cloud-Dienst ($status): $body', 'Cloud service error ($status): $body');
}

/// Gemeinsame Anfragen: Zugangsschlüssel, nochmals versuchen bei
/// „zu viele Anfragen“ und Serverfehlern, neuer Schlüssel bei 401.
class _Http {
  _Http(this.auth);
  final OAuthClient auth;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  Future<(int, HttpHeaders, List<int>)> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final token = await auth.accessToken(force: attempt > 0 && _lastWas401);
      final req = await _client.openUrl(method, url);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      headers.forEach(req.headers.set);
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(const Duration(minutes: 5));
      final bytes = <int>[];
      await for (final c in res) {
        bytes.addAll(c);
      }
      _lastWas401 = res.statusCode == 401;
      final retry = res.statusCode == 401 || res.statusCode == 429 || res.statusCode >= 500;
      if (retry && attempt < 3) {
        final after = int.tryParse(res.headers.value('retry-after') ?? '');
        await Future<void>.delayed(Duration(seconds: after ?? (1 << attempt)));
        continue;
      }
      return (res.statusCode, res.headers, bytes);
    }
  }

  bool _lastWas401 = false;

  Future<dynamic> json(String method, Uri url, {Object? body, Map<String, String> headers = const {}}) async {
    final (status, _, bytes) = await send(
      method,
      url,
      headers: {if (body != null) 'Content-Type': 'application/json; charset=utf-8', ...headers},
      body: body == null ? null : utf8.encode(jsonEncode(body)),
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    if (status < 200 || status >= 300) throw CloudHttpException(status, text);
    return text.isEmpty ? null : jsonDecode(text);
  }
}

// ---------------------------------------------------------------- Dropbox

/// Dropbox: Volti hat einen eigenen Ordner (`Apps/<Name der App>`) und sieht nur diesen.
class DropboxApi implements CloudApi {
  DropboxApi(OAuthClient auth) : _http = _Http(auth);
  final _Http _http;

  static const _api = 'https://api.dropboxapi.com/2';
  static const _content = 'https://content.dropboxapi.com/2';

  /// Dropbox erwartet die Angaben im Kopf der Anfrage; dort sind nur
  /// ASCII-Zeichen erlaubt (Umlaute als \uXXXX).
  static String headerJson(Object value) {
    final s = jsonEncode(value);
    final b = StringBuffer();
    for (final c in s.codeUnits) {
      b.write(c < 0x80 ? String.fromCharCode(c) : '\\u${c.toRadixString(16).padLeft(4, '0')}');
    }
    return b.toString();
  }

  @override
  Future<List<RemoteEntry>> listAll() async {
    final out = <RemoteEntry>[];
    dynamic page;
    try {
      page = await _http.json(
        'POST',
        Uri.parse('$_api/files/list_folder'),
        body: {'path': '', 'recursive': true, 'include_deleted': false, 'limit': 2000},
      );
    } on CloudHttpException catch (e) {
      if (e.status == 409 && e.body.contains('not_found')) return out; // noch leer
      rethrow;
    }
    while (true) {
      for (final e in (page['entries'] as List).cast<Map<String, dynamic>>()) {
        if (e['.tag'] != 'file') continue;
        final display = (e['path_display'] as String).replaceFirst(RegExp('^/'), '');
        out.add(RemoteEntry(path: display, rev: e['rev'] as String? ?? e['content_hash'] as String? ?? ''));
      }
      if (page['has_more'] != true) break;
      page = await _http.json('POST', Uri.parse('$_api/files/list_folder/continue'), body: {'cursor': page['cursor']});
    }
    return out;
  }

  @override
  Future<List<int>> download(RemoteEntry e) async {
    final (status, _, bytes) = await _http.send(
      'POST',
      Uri.parse('$_content/files/download'),
      headers: {
        'Dropbox-API-Arg': headerJson({'path': '/${e.path}'}),
      },
    );
    if (status != 200) throw CloudHttpException(status, utf8.decode(bytes, allowMalformed: true));
    return bytes;
  }

  @override
  Future<RemoteEntry> upload(String path, List<int> bytes, RemoteEntry? existing) async {
    final (status, _, body) = await _http.send(
      'POST',
      Uri.parse('$_content/files/upload'),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': headerJson({'path': '/$path', 'mode': 'overwrite', 'mute': true}),
      },
      body: bytes,
    );
    final text = utf8.decode(body, allowMalformed: true);
    if (status != 200) throw CloudHttpException(status, text);
    final j = jsonDecode(text) as Map<String, dynamic>;
    return RemoteEntry(path: path, rev: j['rev'] as String? ?? '');
  }

  @override
  Future<void> delete(RemoteEntry e) async {
    try {
      await _http.json('POST', Uri.parse('$_api/files/delete_v2'), body: {'path': '/${e.path}'});
    } on CloudHttpException catch (x) {
      if (x.status == 409 && x.body.contains('not_found')) return;
      rethrow;
    }
  }

  /// Name des Kontos (für die Anzeige).
  Future<String> accountName() async {
    // Ohne Angaben erwartet Dropbox den Text „null“.
    final (status, _, bytes) = await _http.send(
      'POST',
      Uri.parse('$_api/users/get_current_account'),
      headers: {'Content-Type': 'application/json'},
      body: utf8.encode('null'),
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    if (status != 200) throw CloudHttpException(status, text);
    final j = jsonDecode(text) as Map<String, dynamic>;
    final name = (j['name'] as Map?)?['display_name'] as String?;
    final email = j['email'] as String?;
    return [?name, if (email != null) '($email)'].join(' ');
  }
}

// ----------------------------------------------------------- Google Drive

/// Google Drive: Volti legt im Drive einen Ordner „Volti“ an und sieht nur
/// die Dateien, die es selbst angelegt hat. Gelöschtes landet im Papierkorb
/// von Google Drive.
class GoogleDriveApi implements CloudApi {
  GoogleDriveApi(OAuthClient auth, {this.rootId, this.onRoot}) : _http = _Http(auth);
  final _Http _http;

  /// Kennung des Ordners „Volti“ (wird gemerkt).
  String? rootId;
  final Future<void> Function(String id)? onRoot;

  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const _folderMime = 'application/vnd.google-apps.folder';

  /// Unterordner (relativer Pfad → Kennung), beim Auflisten gefüllt.
  final Map<String, String> _folders = {};

  Future<String> _root() async {
    if (rootId != null) return rootId!;
    final q = "name = 'Volti' and mimeType = '$_folderMime' and 'root' in parents and trashed = false";
    final res = await _http.json(
      'GET',
      Uri.parse('$_api/files')
          .replace(queryParameters: {'q': q, 'fields': 'files(id,createdTime)', 'orderBy': 'createdTime'}),
    );
    final files = (res['files'] as List).cast<Map<String, dynamic>>();
    final id = files.isNotEmpty
        ? files.first['id'] as String
        : (await _http.json(
                'POST',
                Uri.parse('$_api/files').replace(queryParameters: {'fields': 'id'}),
                body: {
                  'name': 'Volti',
                  'mimeType': _folderMime,
                  'parents': ['root'],
                },
              ))['id']
              as String;
    rootId = id;
    await onRoot?.call(id);
    return id;
  }

  @override
  Future<List<RemoteEntry>> listAll() async {
    final root = await _root();
    final all = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final res = await _http.json(
        'GET',
        Uri.parse('$_api/files').replace(
          queryParameters: {
            'q': 'trashed = false',
            'pageSize': '1000',
            'fields': 'nextPageToken,files(id,name,mimeType,parents,md5Checksum,modifiedTime)',
            'pageToken': ?pageToken,
          },
        ),
      );
      all.addAll((res['files'] as List).cast<Map<String, dynamic>>());
      pageToken = res['nextPageToken'] as String?;
    } while (pageToken != null);

    final byId = {for (final f in all) f['id'] as String: f};
    String? pathOf(Map<String, dynamic> f) {
      final parts = <String>[f['name'] as String];
      var parent = (f['parents'] as List?)?.cast<String>().firstOrNull;
      for (var depth = 0; parent != null && depth < 10; depth++) {
        if (parent == root) return parts.reversed.join('/');
        final pf = byId[parent];
        if (pf == null) return null;
        parts.add(pf['name'] as String);
        parent = (pf['parents'] as List?)?.cast<String>().firstOrNull;
      }
      return null;
    }

    _folders
      ..clear()
      ..[''] = root;
    final out = <String, (RemoteEntry, String)>{};
    for (final f in all) {
      final path = pathOf(f);
      if (path == null) continue;
      if (f['mimeType'] == _folderMime) {
        _folders[path] = f['id'] as String;
        continue;
      }
      final modified = f['modifiedTime'] as String? ?? '';
      final e = RemoteEntry(path: path, id: f['id'] as String, rev: '${f['md5Checksum'] ?? ''}$modified');
      // Zwei Dateien mit gleichem Namen (zwei Geräte gleichzeitig): die jüngste gilt.
      final prev = out[path];
      if (prev == null || modified.compareTo(prev.$2) > 0) out[path] = (e, modified);
    }
    return [for (final v in out.values) v.$1];
  }

  Future<String> _folder(String dir) async {
    if (dir.isEmpty) return _root();
    final known = _folders[dir];
    if (known != null) return known;
    final parent = await _folder(dir.contains('/') ? dir.substring(0, dir.lastIndexOf('/')) : '');
    final res = await _http.json(
      'POST',
      Uri.parse('$_api/files').replace(queryParameters: {'fields': 'id'}),
      body: {
        'name': dir.split('/').last,
        'mimeType': _folderMime,
        'parents': [parent],
      },
    );
    return _folders[dir] = res['id'] as String;
  }

  @override
  Future<List<int>> download(RemoteEntry e) async {
    final (status, _, bytes) = await _http.send(
      'GET',
      Uri.parse('$_api/files/${e.id}').replace(queryParameters: {'alt': 'media'}),
    );
    if (status != 200) throw CloudHttpException(status, utf8.decode(bytes, allowMalformed: true));
    return bytes;
  }

  @override
  Future<RemoteEntry> upload(String path, List<int> bytes, RemoteEntry? existing) async {
    // Hochladen in zwei Schritten (geht auch bei grossen PDFs zuverlässig).
    final fields = {'uploadType': 'resumable', 'fields': 'id,md5Checksum,modifiedTime'};
    final Map<String, Object> meta;
    final Uri start;
    final String method;
    if (existing?.id != null) {
      start = Uri.parse('$_upload/files/${existing!.id}').replace(queryParameters: fields);
      method = 'PATCH';
      meta = {};
    } else {
      final dir = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
      start = Uri.parse('$_upload/files').replace(queryParameters: fields);
      method = 'POST';
      meta = {
        'name': path.split('/').last,
        'parents': [await _folder(dir)],
      };
    }
    final (s1, headers, b1) = await _http.send(
      method,
      start,
      headers: {'Content-Type': 'application/json; charset=utf-8', 'X-Upload-Content-Length': '${bytes.length}'},
      body: utf8.encode(jsonEncode(meta)),
    );
    final location = headers.value('location');
    if (s1 != 200 || location == null) throw CloudHttpException(s1, utf8.decode(b1, allowMalformed: true));
    final (s2, _, b2) = await _http.send(
      'PUT',
      Uri.parse(location),
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    final text = utf8.decode(b2, allowMalformed: true);
    if (s2 != 200 && s2 != 201) throw CloudHttpException(s2, text);
    final j = jsonDecode(text) as Map<String, dynamic>;
    return RemoteEntry(path: path, id: j['id'] as String, rev: '${j['md5Checksum'] ?? ''}${j['modifiedTime'] ?? ''}');
  }

  @override
  Future<void> delete(RemoteEntry e) async {
    try {
      await _http.json('PATCH', Uri.parse('$_api/files/${e.id}'), body: {'trashed': true});
    } on CloudHttpException catch (x) {
      if (x.status == 404) return;
      rethrow;
    }
  }

  /// Name des Kontos (für die Anzeige).
  Future<String> accountName() async {
    final j = await _http.json(
      'GET',
      Uri.parse('$_api/about').replace(queryParameters: {'fields': 'user(displayName,emailAddress)'}),
    );
    final u = j['user'] as Map? ?? const {};
    return [?u['displayName'] as String?, if (u['emailAddress'] != null) '(${u['emailAddress']})'].join(' ');
  }
}
