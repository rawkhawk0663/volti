import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// Erzeugt kleine Vorschaubilder der ersten Seite und speichert sie auf
/// diesem Gerät (nicht in der Bibliothek, damit der Cloud-Ordner sauber
/// bleibt). Ein Vorschaubild wird nur einmal erzeugt, ausser das PDF ändert
/// sich.
class ThumbnailCache {
  ThumbnailCache._(this._dir);

  static ThumbnailCache? _instance;
  static Future<ThumbnailCache> instance() async {
    if (_instance != null) return _instance!;
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'thumbs'));
    await dir.create(recursive: true);
    return _instance = ThumbnailCache._(dir);
  }

  final Directory _dir;
  final Map<String, Future<File?>> _pending = {};

  // Höchstens zwei PDFs gleichzeitig rendern, damit die App flüssig bleibt.
  static const _maxParallel = 2;
  int _running = 0;
  final List<Completer<void>> _queue = [];

  static const int width = 360;

  Future<File?> thumbnailFor(String pdfPath) async {
    FileStat stat;
    try {
      stat = await File(pdfPath).stat();
    } catch (_) {
      return null;
    }
    final key = _hash('$pdfPath|${stat.size}|${stat.modified.millisecondsSinceEpoch}');
    final file = File(p.join(_dir.path, '$key.png'));
    if (await file.exists()) return file;
    // Achtung: Block-Körper nötig. `() => _pending.remove(key)` würde die
    // entfernte Future zurückgeben, und whenComplete würde auf sich selbst warten.
    return _pending[key] ??= _render(pdfPath, file).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<File?> _render(String pdfPath, File target) async {
    await _acquire();
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      if (doc.pages.isEmpty) return null;
      final page = doc.pages.first;
      final h = (width * page.height / page.width).round();
      final image = await page.renderForDisplay(
        width: width,
        height: h,
        fullWidth: width.toDouble(),
        fullHeight: h.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (image == null) return null;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return null;
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await tmp.rename(target.path);
      return target;
    } catch (_) {
      return null; // z. B. beschädigtes PDF – dann eben ohne Vorschau
    } finally {
      await doc?.dispose();
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_running < _maxParallel) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _running--;
    }
  }

  /// Stabiler Kurz-Hash (FNV-1a, 64 Bit) als Dateiname.
  static String _hash(String s) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final b in utf8.encode(s)) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }
}
