import '../../app/l10n.dart';

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
    this.parent,
    this.isGroup = false,
    this.scope,
  });

  /// ID der Ebene mit den Notizen einer Setlist (für alle Geräte gleich, so
  /// entsteht beim Abgleich keine zweite).
  static String forSetlist(String setlistId) => 'setlist-$setlistId';

  /// Die Grund-Ebene, solange sie nie verändert wurde.
  static AnnotationLayer standard() =>
      AnnotationLayer(id: kDefaultLayer, name: tr('Standard', 'Default'), order: 0, createdAt: DateTime.utc(2000));

  final String id;
  final String name;

  /// Reihenfolge von unten (klein) nach oben (gross).
  final double order;
  final bool visible;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final bool deleted;

  /// Gruppe, zu der die Ebene gehört (null = keine).
  final String? parent;

  /// Eine Gruppe fasst Ebenen zusammen. Auf ihr selbst liegt nichts; ist sie
  /// ausgeblendet, sind es alle Ebenen darin.
  final bool isGroup;

  /// Nur in dieser Setlist sichtbar (ID der Setlist, null = überall).
  /// So können Notizen zu einem Song je Setlist verschieden sein.
  final String? scope;

  DateTime get lastChange => modifiedAt ?? createdAt;
  bool get isDefault => id == kDefaultLayer;

  static const _keep = Object();

  /// [parent]: neue Gruppe; `null` = aus der Gruppe nehmen; weglassen = behalten.
  AnnotationLayer copyWith({
    String? name,
    double? order,
    bool? visible,
    DateTime? modifiedAt,
    bool? deleted,
    Object? parent = _keep,
  }) => AnnotationLayer(
    id: id,
    name: name ?? this.name,
    order: order ?? this.order,
    visible: visible ?? this.visible,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    deleted: deleted ?? this.deleted,
    parent: identical(parent, _keep) ? this.parent : parent as String?,
    isGroup: isGroup,
    scope: scope,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'order': order,
    if (!visible) 'visible': false,
    'created': createdAt.toUtc().toIso8601String(),
    if (modifiedAt != null) 'modified': modifiedAt!.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
    if (parent != null) 'parent': parent,
    if (isGroup) 'group': true,
    if (scope != null) 'scope': scope,
  };

  static AnnotationLayer fromJson(Map<String, dynamic> j) => AnnotationLayer(
    id: j['id'] as String,
    name: j['name'] as String? ?? tr('Ebene', 'Layer'),
    order: (j['order'] as num?)?.toDouble() ?? 0,
    visible: j['visible'] != false,
    createdAt: DateTime.parse(j['created'] as String),
    modifiedAt: j['modified'] == null ? null : DateTime.parse(j['modified'] as String),
    deleted: j['deleted'] == true,
    parent: j['parent'] as String?,
    isGroup: j['group'] == true,
    scope: j['scope'] as String?,
  );
}
