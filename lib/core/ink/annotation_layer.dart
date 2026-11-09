/// ID der Grund-Ebene. Elemente ohne Ebene (auch alle aus früheren
/// Versionen) liegen auf ihr.
const kDefaultLayer = 'standard';

/// Eine Ebene für Anmerkungen eines Stücks (gilt auf allen Seiten).
///
/// Wie alles andere sync-tauglich: eindeutige ID, Grabstein beim Löschen,
/// jüngste Änderung gewinnt (Name, Reihenfolge, Sichtbarkeit).
class AnnotationLayer {
  AnnotationLayer({
    required this.id,
    required this.name,
    required this.order,
    this.visible = true,
    required this.createdAt,
    this.modifiedAt,
    this.deleted = false,
  });

  /// Die Grund-Ebene, solange sie nie verändert wurde.
  static AnnotationLayer standard() =>
      AnnotationLayer(id: kDefaultLayer, name: 'Standard', order: 0, createdAt: DateTime.utc(2000));

  final String id;
  final String name;

  /// Reihenfolge von unten (klein) nach oben (gross).
  final double order;
  final bool visible;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final bool deleted;

  DateTime get lastChange => modifiedAt ?? createdAt;
  bool get isDefault => id == kDefaultLayer;

  AnnotationLayer copyWith({String? name, double? order, bool? visible, DateTime? modifiedAt, bool? deleted}) =>
      AnnotationLayer(
        id: id,
        name: name ?? this.name,
        order: order ?? this.order,
        visible: visible ?? this.visible,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'order': order,
    if (!visible) 'visible': false,
    'created': createdAt.toUtc().toIso8601String(),
    if (modifiedAt != null) 'modified': modifiedAt!.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static AnnotationLayer fromJson(Map<String, dynamic> j) => AnnotationLayer(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Ebene',
    order: (j['order'] as num?)?.toDouble() ?? 0,
    visible: j['visible'] != false,
    createdAt: DateTime.parse(j['created'] as String),
    modifiedAt: j['modified'] == null ? null : DateTime.parse(j['modified'] as String),
    deleted: j['deleted'] == true,
  );
}
