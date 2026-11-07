import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// Rendert PDF-Seiten als Bilder und hält die letzten paar im Speicher.
///
/// Damit das Umblättern sofort geht, werden die Nachbarseiten im Voraus
/// gerendert ([preload]). Ändert sich die Fenstergrösse, wird in der neuen
/// Auflösung gerendert.
class PageImageCache extends ChangeNotifier {
  PageImageCache(this.document, {this.capacity = 7});

  final PdfDocument document;
  final int capacity;

  final LinkedHashMap<_Key, ui.Image> _images = LinkedHashMap();
  final Map<_Key, Future<void>> _pending = {};
  bool _disposed = false;

  /// Seiten, die gerade angezeigt werden und nicht verdrängt werden dürfen.
  Set<int> _visible = const {};

  void setVisiblePages(Set<int> pages) => _visible = pages;

  int get pageCount => document.pages.length;

  /// Seitenverhältnis (Breite / Höhe) der Seite.
  double aspectRatio(int page) {
    final p = document.pages[page - 1];
    return p.width / p.height;
  }

  /// Liefert das Bild einer Seite in der gewünschten Pixelbreite, falls schon
  /// vorhanden. Sonst `null` – und es wird im Hintergrund gerendert.
  /// Solange das genaue Bild fehlt, wird ein vorhandenes Bild derselben
  /// Seite in anderer Auflösung zurückgegeben (kurz unscharf statt leer).
  ui.Image? imageFor(int page, int pixelWidth) {
    final key = _Key(page, pixelWidth);
    final exact = _images.remove(key);
    if (exact != null) {
      _images[key] = exact; // als zuletzt benutzt markieren
      return exact;
    }
    _render(key);
    for (final e in _images.entries) {
      if (e.key.page == page) return e.value;
    }
    return null;
  }

  void preload(Iterable<int> pages, int pixelWidth) {
    for (final p in pages) {
      if (p >= 1 && p <= pageCount) _render(_Key(p, pixelWidth));
    }
  }

  Future<void> _render(_Key key) {
    if (_images.containsKey(key)) return Future.value();
    return _pending[key] ??= _doRender(key).whenComplete(() => _pending.remove(key));
  }

  Future<void> _doRender(_Key key) async {
    final page = document.pages[key.page - 1];
    final w = key.pixelWidth;
    final h = (w * page.height / page.width).round();
    final image = await page.renderForDisplay(
      width: w,
      height: h,
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
      backgroundColor: 0xFFFFFFFF,
    );
    if (image == null) return;
    if (_disposed) {
      image.dispose();
      return;
    }
    _images[key] = image;
    while (_images.length > capacity) {
      final victim = _images.keys.firstWhere(
        (k) => !_visible.contains(k.page),
        orElse: () => _images.keys.first,
      );
      if (_visible.contains(victim.page)) break;
      _images.remove(victim)!.dispose();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

@immutable
class _Key {
  const _Key(this.page, this.pixelWidth);
  final int page;
  final int pixelWidth;

  @override
  bool operator ==(Object other) => other is _Key && other.page == page && other.pixelWidth == pixelWidth;

  @override
  int get hashCode => Object.hash(page, pixelWidth);
}
