import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Ein eigener Stempel: ein Bild, das man selbst importiert hat.
///
/// Das Bild liegt als PNG in `Bibliothek/.volti/stamps/<id>.png` und wird nie
/// verändert oder gelöscht (gesetzte Stempel brauchen es weiterhin). Name und
/// Mittelpunkt stehen in `Bibliothek/.volti/stamps.json`.
class CustomStamp {
  CustomStamp({
    required this.id,
    required this.name,
    required this.anchorX,
    required this.anchorY,
    required this.aspect,
    required this.createdAt,
    this.modifiedAt,
    this.deleted = false,
  });

  final String id;
  final String name;

  /// Punkt im Bild (0..1), der genau unter dem Stift liegt – z. B. die Mitte
  /// des Notenkopfs.
  final double anchorX, anchorY;

  /// Breite / Höhe des Bildes.
  final double aspect;
  final DateTime createdAt;
  final DateTime? modifiedAt;

  /// Aus der Auswahl entfernt (das Bild bleibt für gesetzte Stempel erhalten).
  final bool deleted;

  String get file => '$id.png';

  CustomStamp copyWith({String? name, double? anchorX, double? anchorY, bool? deleted, DateTime? modifiedAt}) =>
      CustomStamp(
        id: id,
        name: name ?? this.name,
        anchorX: anchorX ?? this.anchorX,
        anchorY: anchorY ?? this.anchorY,
        aspect: aspect,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ax': anchorX,
    'ay': anchorY,
    'aspect': aspect,
    'created': createdAt.toUtc().toIso8601String(),
    if (modifiedAt != null) 'modified': modifiedAt!.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static CustomStamp fromJson(Map<String, dynamic> j) => CustomStamp(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Stempel',
    anchorX: (j['ax'] as num?)?.toDouble() ?? 0.5,
    anchorY: (j['ay'] as num?)?.toDouble() ?? 0.5,
    aspect: (j['aspect'] as num?)?.toDouble() ?? 1,
    createdAt: DateTime.parse(j['created'] as String),
    modifiedAt: j['modified'] == null ? null : DateTime.parse(j['modified'] as String),
    deleted: j['deleted'] == true,
  );
}

/// Liest und schreibt die Liste der eigenen Stempel und ihre Bilder.
///
/// Sync: Die Bilder werden wie PDFs abgeglichen (neu/gelöscht), die Liste
/// als Ganzes – die jüngste Fassung gewinnt (Feld `modified`).
class CustomStampStore {
  CustomStampStore(this.libraryRoot);
  final String libraryRoot;

  static const listFile = '.volti/stamps.json';
  static const imageDir = '.volti/stamps';

  File get _list => File(p.joinAll([libraryRoot, ...listFile.split('/')]));
  String imagePath(CustomStamp s) => p.joinAll([libraryRoot, ...imageDir.split('/'), s.file]);

  Future<List<CustomStamp>> load() async {
    try {
      if (!await _list.exists()) return [];
      final j = jsonDecode(await _list.readAsString()) as Map<String, dynamic>;
      return [
        for (final e in j['stamps'] as List<dynamic>? ?? const []) CustomStamp.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<CustomStamp> stamps) async {
    await _list.parent.create(recursive: true);
    final tmp = File('${_list.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'format': 'volti-stamps',
        'version': 1,
        'modified': DateTime.now().toUtc().toIso8601String(),
        'stamps': [for (final s in stamps) s.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_list.path);
  }

  Future<void> writeImage(CustomStamp s, Uint8List png) async {
    final f = File(imagePath(s));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(png, flush: true);
  }

  Future<Uint8List?> readImage(CustomStamp s) async {
    final f = File(imagePath(s));
    return await f.exists() ? f.readAsBytes() : null;
  }
}

/// Ergebnis der Bild-Aufbereitung: RGBA-Punkte mit Breite und Höhe.
class StampPixels {
  const StampPixels(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width, height;
}

/// Bereitet ein Bild für einen Stempel auf:
/// * [whiteToClear]: Weisser (heller) Hintergrund wird durchsichtig – mit
///   weichem Übergang, damit die Kanten nicht ausfransen.
/// * Durchsichtige Ränder werden weggeschnitten (der Stempel ist so gross wie
///   sein Inhalt; das macht die Grösse und den Mittelpunkt verlässlich).
/// Gibt null zurück, wenn nichts übrig bleibt.
StampPixels? prepareStampPixels(Uint8List rgba, int width, int height, {bool whiteToClear = true}) {
  final out = Uint8List.fromList(rgba);
  if (whiteToClear) {
    const clear = 235, solid = 170; // ab hier ganz durchsichtig bzw. ganz deckend
    for (var i = 0; i < out.length; i += 4) {
      final lum = (out[i] * 299 + out[i + 1] * 587 + out[i + 2] * 114) ~/ 1000;
      if (lum >= clear) {
        out[i + 3] = 0;
      } else if (lum > solid) {
        out[i + 3] = (out[i + 3] * (clear - lum) / (clear - solid)).round();
      }
    }
  }
  var l = width, t = height, r = -1, b = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (out[(y * width + x) * 4 + 3] > 16) {
        l = math.min(l, x);
        r = math.max(r, x);
        t = math.min(t, y);
        b = math.max(b, y);
      }
    }
  }
  if (r < 0) return null;
  // 1 Punkt Rand, damit die Kanten weich bleiben.
  l = math.max(0, l - 1);
  t = math.max(0, t - 1);
  r = math.min(width - 1, r + 1);
  b = math.min(height - 1, b + 1);
  final w = r - l + 1, h = b - t + 1;
  final cropped = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    final src = ((t + y) * width + l) * 4;
    cropped.setRange(y * w * 4, (y + 1) * w * 4, out, src);
  }
  return StampPixels(cropped, w, h);
}
