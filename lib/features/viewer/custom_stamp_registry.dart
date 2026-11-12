import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/ink/custom_stamps.dart';
import '../../app/l10n.dart';

/// Die eigenen Stempel mit ihren fertig geladenen Bildern (app-weit).
///
/// Malen geschieht an vielen Stellen ohne Zugriff auf Widgets (Strich-Bild,
/// Auswahl, Vorschau). Deshalb gibt es eine gemeinsame Instanz [instance].
class CustomStamps extends ChangeNotifier {
  CustomStamps(this.store);

  /// Gemeinsame Instanz (wird beim Start gesetzt).
  static CustomStamps? instance;

  final CustomStampStore store;
  List<CustomStamp> _all = [];
  final Map<String, ui.Image> _images = {};
  static const _uuid = Uuid();

  /// Meldet eine Änderung (für den Sync).
  VoidCallback? onLocalChange;

  /// Zur Auswahl angebotene Stempel (ohne entfernte), älteste zuerst.
  List<CustomStamp> get stamps => [
    for (final s in _all)
      if (!s.deleted && !s.snippet) s,
  ];

  /// Auch entfernte – gesetzte Stempel brauchen sie weiterhin.
  CustomStamp? byId(String id) {
    for (final s in _all) {
      if (s.id == id) return s;
    }
    return null;
  }

  ui.Image? image(String id) => _images[id];

  /// Liest die Liste und lädt fehlende Bilder (auch nach einem Sync).
  Future<void> load() async {
    _all = await store.load();
    for (final s in _all) {
      if (_images.containsKey(s.id)) continue;
      final bytes = await store.readImage(s);
      if (bytes == null) continue;
      final img = await _decode(bytes);
      if (img != null) _images[s.id] = img;
    }
    notifyListeners();
  }

  static Future<ui.Image?> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// Neuer Stempel aus einem fertigen PNG.
  Future<CustomStamp> add({
    required String name,
    required Uint8List png,
    required double anchorX,
    required double anchorY,
    required double aspect,
    bool snippet = false,
  }) async {
    final s = CustomStamp(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? tr('Stempel', 'Stamp') : name.trim(),
      anchorX: anchorX,
      anchorY: anchorY,
      aspect: aspect,
      createdAt: DateTime.now().toUtc(),
      snippet: snippet,
    );
    await store.writeImage(s, png);
    final img = await _decode(png);
    if (img != null) _images[s.id] = img;
    _all = [..._all, s];
    await store.save(_all);
    notifyListeners();
    onLocalChange?.call();
    return s;
  }

  Future<void> update(CustomStamp s) async {
    _all = [for (final x in _all) x.id == s.id ? s.copyWith(modifiedAt: DateTime.now().toUtc()) : x];
    await store.save(_all);
    notifyListeners();
    onLocalChange?.call();
  }

  /// Aus der Auswahl nehmen. Das Bild bleibt, damit gesetzte Stempel bleiben.
  Future<void> remove(String id) async {
    final s = byId(id);
    if (s != null) await update(s.copyWith(deleted: true));
  }
}
