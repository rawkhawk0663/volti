/// Eine getippte Notiz auf einer Notenseite (z. B. "Bogen ab", "Atmen!").
///
/// Wie bei Strichen: normierte Position (0..1), eindeutige ID, gelöschte
/// Notizen bleiben als Grabstein erhalten. Wird der Text geändert, gewinnt
/// beim Zusammenführen die jüngste Fassung.
class TextNote {
  TextNote({
    required this.id,
    required this.page,
    required this.x,
    required this.y,
    required this.text,
    required this.size,
    required this.color,
    required this.createdAt,
    this.background = legacyBackground,
    this.modifiedAt,
    this.deleted = false,
  });

  /// Kein Hintergrund (durchsichtig).
  static const noBackground = 0;

  /// Heller Hintergrund, den Notizen vor dem Hintergrund-Wähler hatten.
  static const legacyBackground = 0xC8FFFFFF;

  final String id;
  final int page;

  /// Linke obere Ecke, normiert (0..1).
  final double x;
  final double y;

  final String text;

  /// Schriftgrösse relativ zur Seitenbreite (z. B. 0.022).
  final double size;

  final int color;

  /// Hintergrundfarbe (ARGB); [noBackground] = durchsichtig.
  final int background;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final bool deleted;

  DateTime get lastChange => modifiedAt ?? createdAt;

  TextNote copyWith({
    String? id,
    double? x,
    double? y,
    String? text,
    double? size,
    int? color,
    int? background,
    DateTime? modifiedAt,
    bool? deleted,
  }) => TextNote(
    id: id ?? this.id,
    page: page,
    x: x ?? this.x,
    y: y ?? this.y,
    text: text ?? this.text,
    size: size ?? this.size,
    color: color ?? this.color,
    background: background ?? this.background,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    deleted: deleted ?? this.deleted,
  );

  static double _round(double v) => (v * 100000).roundToDouble() / 100000;

  Map<String, dynamic> toJson() => {
    'id': id,
    'page': page,
    'x': _round(x),
    'y': _round(y),
    'text': deleted ? '' : text,
    'size': size,
    'color': color,
    'bg': background,
    'created': createdAt.toUtc().toIso8601String(),
    if (modifiedAt != null) 'modified': modifiedAt!.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static TextNote fromJson(Map<String, dynamic> json) => TextNote(
    id: json['id'] as String,
    page: json['page'] as int,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    text: json['text'] as String? ?? '',
    size: (json['size'] as num?)?.toDouble() ?? 0.022,
    color: json['color'] as int? ?? 0xFF1B1B1B,
    // Ältere Notizen ohne Angabe behalten ihren hellen Hintergrund.
    background: json['bg'] as int? ?? legacyBackground,
    createdAt: DateTime.parse(json['created'] as String),
    modifiedAt: json['modified'] == null ? null : DateTime.parse(json['modified'] as String),
    deleted: json['deleted'] == true,
  );
}
