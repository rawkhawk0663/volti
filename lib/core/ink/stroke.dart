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

enum InkTool {
  pen,
  highlighter;

  static InkTool fromName(String? name) =>
      InkTool.values.firstWhere((t) => t.name == name, orElse: () => InkTool.pen);
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

  DateTime get lastChange => modifiedAt ?? createdAt;

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
        points: (json['points'] as List<dynamic>? ?? const [])
            .map((p) => InkPoint.fromJson(p as List<dynamic>))
            .toList(),
      );
}
