import 'annotation_layer.dart';

/// Ein gesetzter Stempel (Musiksymbol) auf einer Notenseite.
///
/// Wie Striche und Text-Notizen: normierte Position (Mitte des Symbols,
/// 0..1), eindeutige ID, Grabstein beim Löschen, jüngste Änderung gewinnt.
class Stamp {
  Stamp({
    required this.id,
    required this.page,
    required this.x,
    required this.y,
    required this.glyph,
    required this.size,
    required this.color,
    required this.createdAt,
    this.modifiedAt,
    this.deleted = false,
    this.layer,
    this.custom,
  });

  final String id;
  final int page;

  /// Mitte des Symbols, normiert (0..1).
  final double x;
  final double y;

  /// Zeichen in der Schrift Bravura (SMuFL-Codepunkt).
  final int glyph;

  /// Schriftgrösse relativ zur Seitenbreite.
  final double size;
  final int color;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final bool deleted;

  /// Ebene (null = Grund-Ebene [kDefaultLayer]).
  final String? layer;

  /// Eigener Stempel (ID in der Liste der eigenen Stempel) statt eines
  /// Zeichens aus Bravura. Dann ist [glyph] 0 und [color] ohne Bedeutung.
  final String? custom;

  DateTime get lastChange => modifiedAt ?? createdAt;

  Stamp copyWith({
    String? id,
    int? page,
    DateTime? createdAt,
    double? x,
    double? y,
    double? size,
    int? color,
    DateTime? modifiedAt,
    bool? deleted,
    String? layer,
  }) => Stamp(
    id: id ?? this.id,
    page: page ?? this.page,
    x: x ?? this.x,
    y: y ?? this.y,
    glyph: glyph,
    size: size ?? this.size,
    color: color ?? this.color,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    deleted: deleted ?? this.deleted,
    layer: layer ?? this.layer,
    custom: custom,
  );

  static double _round(double v) => (v * 100000).roundToDouble() / 100000;

  Map<String, dynamic> toJson() => {
    'id': id,
    'page': page,
    'x': _round(x),
    'y': _round(y),
    'glyph': glyph,
    'size': size,
    'color': color,
    'created': createdAt.toUtc().toIso8601String(),
    if (modifiedAt != null) 'modified': modifiedAt!.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
    if (layer != null && layer != kDefaultLayer) 'layer': layer,
    if (custom != null) 'custom': custom,
  };

  static Stamp fromJson(Map<String, dynamic> j) => Stamp(
    id: j['id'] as String,
    page: j['page'] as int,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    glyph: j['glyph'] as int,
    size: (j['size'] as num).toDouble(),
    color: j['color'] as int? ?? 0xFF1B1B1B,
    createdAt: DateTime.parse(j['created'] as String),
    modifiedAt: j['modified'] == null ? null : DateTime.parse(j['modified'] as String),
    deleted: j['deleted'] == true,
    layer: j['layer'] as String?,
    custom: j['custom'] as String?,
  );
}
