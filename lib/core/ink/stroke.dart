/// Datenmodell für Anmerkungen (Striche) auf einer Notenseite.
///
/// Wichtige Grundsätze:
/// * Koordinaten sind **normiert** (0..1 relativ zur Seitenbreite/-höhe).
///   Dadurch bleiben Anmerkungen bei Zoom, anderer Bildschirmgrösse oder
///   auf einem anderen Gerät exakt an derselben Stelle.
/// * Jeder Strich hat eine weltweit eindeutige [Stroke.id]. Das ist die
///   Grundlage für den späteren Sync: Striche von zwei Geräten können
///   zusammengeführt werden, ohne sich gegenseitig zu überschreiben.
/// * Gelöschte Striche werden nicht entfernt, sondern als [Stroke.deleted]
///   markiert ("Grabstein"). So "weiss" ein anderes Gerät, dass der Strich
///   absichtlich gelöscht wurde und bringt ihn beim Sync nicht zurück.
library;

import 'annotation_layer.dart';

enum InkTool {
  pen,
  highlighter;

  static InkTool fromName(String? name) => InkTool.values.firstWhere((t) => t.name == name, orElse: () => InkTool.pen);
}

/// Ein einzelner Punkt eines Strichs.
class InkPoint {
  const InkPoint(this.x, this.y, this.pressure);

  /// Normierte Position (0..1) auf der Seite.
  final double x;
  final double y;

  /// Normierter Stiftdruck (0..1). Ohne Drucksensor (Maus) = 0.5.
  final double pressure;

  List<double> toJson() => [_round(x), _round(y), _round(pressure)];

  static InkPoint fromJson(List<dynamic> json) => InkPoint(
    (json[0] as num).toDouble(),
    (json[1] as num).toDouble(),
    json.length > 2 ? (json[2] as num).toDouble() : 0.5,
  );

  // 5 Nachkommastellen reichen (1/100'000 der Seite) und halten Dateien klein.
  static double _round(double v) => (v * 100000).roundToDouble() / 100000;
}

class Stroke {
  Stroke({
    required this.id,
    required this.page,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    required this.createdAt,
    this.modifiedAt,
    this.deleted = false,
    this.layer,
    this.fill,
  });

  /// Eindeutige ID (UUID).
  final String id;

  /// Seitennummer im PDF, beginnend bei 1.
  final int page;

  final InkTool tool;

  /// Farbe als ARGB-Wert (z. B. 0xFF1A1A1A).
  final int color;

  /// Grundbreite des Strichs, relativ zur Seitenbreite (z. B. 0.002).
  final double width;

  final List<InkPoint> points;

  final DateTime createdAt;

  /// Zeitpunkt der letzten Änderung (z. B. Löschen). Entscheidet beim
  /// Zusammenführen, welche Version eines Strichs gewinnt.
  final DateTime? modifiedAt;

  final bool deleted;

  /// Ebene (null = Grund-Ebene [kDefaultLayer]).
  final String? layer;

  /// Füllfarbe (ARGB) einer geschlossenen Form, z. B. ein weisses Rechteck
  /// zum Abdecken oder eine Pfeilspitze. null = nicht gefüllt.
  final int? fill;

  DateTime get lastChange => modifiedAt ?? createdAt;

  /// Umgebendes Rechteck (normiert) – für schnelle Vorprüfungen beim Radieren.
  late final ({double left, double top, double right, double bottom}) bounds = () {
    if (points.isEmpty) return (left: 0.0, top: 0.0, right: 0.0, bottom: 0.0);
    var l = points.first.x, t = points.first.y, r = l, b = t;
    for (final p in points) {
      if (p.x < l) l = p.x;
      if (p.x > r) r = p.x;
      if (p.y < t) t = p.y;
      if (p.y > b) b = p.y;
    }
    return (left: l, top: t, right: r, bottom: b);
  }();

  Stroke copyWith({
    String? id,
    int? page,
    int? color,
    double? width,
    List<InkPoint>? points,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? layer,
  }) => Stroke(
    id: id ?? this.id,
    page: page ?? this.page,
    tool: tool,
    color: color ?? this.color,
    width: width ?? this.width,
    points: points ?? this.points,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    deleted: deleted,
    layer: layer ?? this.layer,
    fill: fill,
  );

  Stroke markDeleted(DateTime when) => Stroke(
    id: id,
    page: page,
    tool: tool,
    color: color,
    width: width,
    points: points,
    createdAt: createdAt,
    modifiedAt: when,
    deleted: true,
    layer: layer,
    fill: fill,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'page': page,
    'tool': tool.name,
    'color': color,
    'width': width,
    'created': createdAt.toUtc().toIso8601String(),
    if (modifiedAt != null) 'modified': modifiedAt!.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
    if (layer != null && layer != kDefaultLayer) 'layer': layer,
    if (fill != null) 'fill': fill,
    // Gelöschte Striche brauchen keine Punkte mehr – spart Platz.
    'points': deleted ? <List<double>>[] : points.map((p) => p.toJson()).toList(),
  };

  static Stroke fromJson(Map<String, dynamic> json) => Stroke(
    id: json['id'] as String,
    page: json['page'] as int,
    tool: InkTool.fromName(json['tool'] as String?),
    color: json['color'] as int,
    width: (json['width'] as num).toDouble(),
    createdAt: DateTime.parse(json['created'] as String),
    modifiedAt: json['modified'] == null ? null : DateTime.parse(json['modified'] as String),
    deleted: json['deleted'] == true,
    layer: json['layer'] as String?,
    fill: json['fill'] as int?,
    points: (json['points'] as List<dynamic>? ?? const []).map((p) => InkPoint.fromJson(p as List<dynamic>)).toList(),
  );
}
