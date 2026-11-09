/// Eine Sprungmarke: Ein Punkt auf einer Seite (z. B. beim "D.S."), der beim
/// Antippen zu einem Ziel springt (z. B. zum Segno), auch auf einer anderen
/// Seite desselben Stücks.
///
/// Wie alle Anmerkungen: normierte Koordinaten der ganzen PDF-Seite,
/// eindeutige ID, Grabstein beim Löschen, jüngste Änderung gewinnt.
class JumpLink {
  JumpLink({
    required this.id,
    required this.page,
    required this.x,
    required this.y,
    required this.toPage,
    required this.toX,
    required this.toY,
    required this.createdAt,
    this.modifiedAt,
    this.deleted = false,
  });

  final String id;

  /// PDF-Seite und Lage des blauen Punkts.
  final int page;
  final double x, y;

  /// PDF-Seite und Lage des Ziels.
  final int toPage;
  final double toX, toY;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final bool deleted;

  DateTime get lastChange => modifiedAt ?? createdAt;

  JumpLink copyWith({
    double? x,
    double? y,
    int? toPage,
    double? toX,
    double? toY,
    DateTime? modifiedAt,
    bool? deleted,
  }) => JumpLink(
    id: id,
    page: page,
    x: x ?? this.x,
    y: y ?? this.y,
    toPage: toPage ?? this.toPage,
    toX: toX ?? this.toX,
    toY: toY ?? this.toY,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    deleted: deleted ?? this.deleted,
  );

  static double _r(double v) => (v * 100000).roundToDouble() / 100000;

  Map<String, dynamic> toJson() => {
    'id': id,
    'page': page,
    'x': _r(x),
    'y': _r(y),
    'toPage': toPage,
    'toX': _r(toX),
    'toY': _r(toY),
    'created': createdAt.toUtc().toIso8601String(),
    if (modifiedAt != null) 'modified': modifiedAt!.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static JumpLink fromJson(Map<String, dynamic> j) => JumpLink(
    id: j['id'] as String,
    page: j['page'] as int,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    toPage: j['toPage'] as int,
    toX: (j['toX'] as num?)?.toDouble() ?? 0.5,
    toY: (j['toY'] as num?)?.toDouble() ?? 0.1,
    createdAt: DateTime.parse(j['created'] as String),
    modifiedAt: j['modified'] == null ? null : DateTime.parse(j['modified'] as String),
    deleted: j['deleted'] == true,
  );
}

/// Ein Lesezeichen: ein benannter Bereich eines Stücks, z. B. ein Lied in
/// einem Sammelband. Kann angesprungen und als eigenes Stück in eine Setlist
/// gelegt werden.
class Bookmark {
  Bookmark({
    required this.id,
    required this.name,
    required this.page,
    this.endPage,
    required this.createdAt,
    this.modifiedAt,
    this.deleted = false,
  });

  final String id;
  final String name;

  /// Erste und (optional) letzte PDF-Seite.
  final int page;
  final int? endPage;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final bool deleted;

  DateTime get lastChange => modifiedAt ?? createdAt;
  int get lastPage => endPage == null || endPage! < page ? page : endPage!;

  static const _keep = Object();

  /// [endPage]: `null` = nur eine Seite; weglassen = behalten.
  Bookmark copyWith({String? name, int? page, Object? endPage = _keep, DateTime? modifiedAt, bool? deleted}) =>
      Bookmark(
        id: id,
        name: name ?? this.name,
        page: page ?? this.page,
        endPage: identical(endPage, _keep) ? this.endPage : endPage as int?,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'page': page,
    if (endPage != null) 'endPage': endPage,
    'created': createdAt.toUtc().toIso8601String(),
    if (modifiedAt != null) 'modified': modifiedAt!.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static Bookmark fromJson(Map<String, dynamic> j) => Bookmark(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Lesezeichen',
    page: j['page'] as int,
    endPage: j['endPage'] as int?,
    createdAt: DateTime.parse(j['created'] as String),
    modifiedAt: j['modified'] == null ? null : DateTime.parse(j['modified'] as String),
    deleted: j['deleted'] == true,
  );
}
