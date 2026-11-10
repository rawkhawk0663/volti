import 'dart:math' as math;

/// Wie eine Seite angezeigt wird: Ausschnitt, Drehung und Geraderichten.
///
/// Das PDF wird nie verändert. Anmerkungen bleiben in den Koordinaten der
/// ganzen, ungedrehten Seite gespeichert und damit genau an ihrem Platz.
class PageCrop {
  const PageCrop({this.left = 0, this.top = 0, this.right = 1, this.bottom = 1, this.quarterTurns = 0, this.skew = 0});

  /// Ausschnitt der ungedrehten Seite, normiert (0..1).
  final double left, top, right, bottom;

  /// Drehung in Vierteldrehungen im Uhrzeigersinn (0..3).
  final int quarterTurns;

  /// Geraderichten: kleine Drehung in Grad (schief eingescannte Seiten).
  final double skew;

  static const none = PageCrop();
  static const maxSkew = 5.0;

  bool get isNone => left == 0 && top == 0 && right == 1 && bottom == 1 && quarterTurns == 0 && skew == 0;
  double get width => right - left;
  double get height => bottom - top;

  /// Seitenverhältnis (Breite/Höhe) der angezeigten Seite, wenn die ganze
  /// Seite das Verhältnis [pageAspect] hat.
  double displayAspect(double pageAspect) {
    final a = pageAspect * width / height;
    return quarterTurns.isOdd ? 1 / a : a;
  }

  PageCrop copyWith({double? left, double? top, double? right, double? bottom, int? quarterTurns, double? skew}) =>
      PageCrop(
        left: left ?? this.left,
        top: top ?? this.top,
        right: right ?? this.right,
        bottom: bottom ?? this.bottom,
        quarterTurns: (quarterTurns ?? this.quarterTurns) % 4,
        skew: (skew ?? this.skew).clamp(-maxSkew, maxSkew),
      );

  /// Nur der Ausschnitt (ohne Drehung), auf gültige Werte gebracht.
  PageCrop normalized() {
    const minSize = 0.1;
    var l = left.clamp(0.0, 1.0 - minSize), t = top.clamp(0.0, 1.0 - minSize);
    var r = right.clamp(l + minSize, 1.0), b = bottom.clamp(t + minSize, 1.0);
    return PageCrop(left: l, top: t, right: r, bottom: b, quarterTurns: quarterTurns % 4, skew: skew);
  }

  @override
  bool operator ==(Object other) =>
      other is PageCrop &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.quarterTurns == quarterTurns &&
      other.skew == skew;

  @override
  int get hashCode => Object.hash(left, top, right, bottom, quarterTurns, skew);

  static double _r(double v) => (v * 10000).roundToDouble() / 10000;

  Map<String, dynamic> toJson() => {
    if (left != 0 || top != 0 || right != 1 || bottom != 1) 'crop': [_r(left), _r(top), _r(right), _r(bottom)],
    if (quarterTurns != 0) 'turns': quarterTurns,
    if (skew != 0) 'skew': _r(skew),
  };

  static PageCrop fromJson(Map<String, dynamic> j) {
    final c = (j['crop'] as List<dynamic>?)?.map((v) => (v as num).toDouble()).toList();
    return PageCrop(
      left: c?[0] ?? 0,
      top: c?[1] ?? 0,
      right: c?[2] ?? 1,
      bottom: c?[3] ?? 1,
      quarterTurns: (j['turns'] as int? ?? 0) % 4,
      skew: ((j['skew'] as num?)?.toDouble() ?? 0).clamp(-maxSkew, maxSkew),
    ).normalized();
  }
}

/// Reihenfolge und Zuschnitt der Seiten eines Stücks.
///
/// * [order]: welche PDF-Seiten in welcher Reihenfolge gezeigt werden
///   (1-basiert). Seiten dürfen fehlen (ausgeblendet) oder mehrfach vorkommen
///   (z. B. für eine Wiederholung). null = alle Seiten in PDF-Reihenfolge.
/// * [crops]: Zuschnitt pro PDF-Seite. Kommt eine Seite mehrfach vor, gilt
///   derselbe Zuschnitt – und dieselben Anmerkungen.
///
/// * Leere Seiten (zum Beschriften, z. B. Notizen als Music Director) stehen
///   als Nummern ab [blankBase] in [order]. Sie haben keine PDF-Seite; ihre
///   Anmerkungen liegen unter dieser Nummer. [blanks] zählt, wie viele je
///   angelegt wurden – so bekommt eine neue leere Seite nie die Nummer (und
///   damit die Notizen) einer früheren.
///
/// Beim Sync gewinnt die jüngste Fassung als Ganzes ([modified]).
class PageSetup {
  const PageSetup({this.order, this.crops = const {}, this.modified, this.blanks = 0});

  final List<int>? order;
  final Map<int, PageCrop> crops;
  final DateTime? modified;
  final int blanks;

  static const empty = PageSetup();

  /// Ab dieser Nummer ist eine Seite eine leere Seite (keine PDF-Seite).
  static const blankBase = 100000;
  static bool isBlank(int page) => page > blankBase;

  /// Seite, deren Grösse eine leere Seite übernimmt (die erste PDF-Seite).
  static int sizeSource(int page) => isBlank(page) ? 1 : page;

  bool get isDefault => order == null && crops.values.every((c) => c.isNone);

  /// Angezeigte Seiten (PDF-Seitennummern), für ein PDF mit [pdfPages] Seiten.
  List<int> pages(int pdfPages) {
    final o = order;
    if (o == null) return [for (var i = 1; i <= pdfPages; i++) i];
    final valid = [
      for (final p in o)
        if ((p >= 1 && p <= pdfPages) || (isBlank(p) && p <= blankBase + blanks)) p,
    ];
    // Nie ganz leer: sonst gäbe es nichts zum Anzeigen.
    return valid.isEmpty ? [for (var i = 1; i <= pdfPages; i++) i] : valid;
  }

  PageCrop cropOf(int pdfPage) => crops[pdfPage] ?? PageCrop.none;

  /// Neue Reihenfolge (null = wieder alle Seiten in PDF-Reihenfolge).
  PageSetup withOrder(List<int>? order, {DateTime? now, int? blanks}) => PageSetup(
    order: order == null ? null : List.unmodifiable(order),
    crops: crops,
    modified: now ?? _now(),
    blanks: blanks ?? this.blanks,
  );

  /// Eine neue leere Seite an Stelle [index] (0-basiert, in der Anzeige-
  /// Reihenfolge) einfügen. Gibt die neue Einrichtung und die Nummer der
  /// leeren Seite zurück.
  (PageSetup, int) withBlankAt(int index, int pdfPages, {DateTime? now}) {
    final list = [...pages(pdfPages)];
    final page = blankBase + blanks + 1;
    list.insert(index.clamp(0, list.length), page);
    return (withOrder(list, now: now, blanks: blanks + 1), page);
  }

  PageSetup withCrop(int pdfPage, PageCrop crop, {DateTime? now}) {
    final map = Map<int, PageCrop>.of(crops);
    if (crop.isNone) {
      map.remove(pdfPage);
    } else {
      map[pdfPage] = crop.normalized();
    }
    return PageSetup(order: order, crops: Map.unmodifiable(map), modified: now ?? _now(), blanks: blanks);
  }

  PageSetup withCrops(Map<int, PageCrop> all, {DateTime? now}) => PageSetup(
    order: order,
    blanks: blanks,
    crops: Map.unmodifiable({
      for (final e in all.entries)
        if (!e.value.isNone) e.key: e.value.normalized(),
    }),
    modified: now ?? _now(),
  );

  /// Alles zurück auf das PDF, wie es ist.
  PageSetup reset({DateTime? now}) => PageSetup(modified: now ?? _now(), blanks: blanks);

  static DateTime _now() => DateTime.now().toUtc();

  /// Die jüngere Fassung gewinnt.
  static PageSetup merge(PageSetup a, PageSetup b) {
    final ma = a.modified, mb = b.modified;
    if (ma == null) return b;
    if (mb == null) return a;
    return mb.isAfter(ma) ? b : a;
  }

  Map<String, dynamic>? toJson() {
    if (modified == null) return null;
    return {
      if (order != null) 'order': order,
      if (crops.isNotEmpty) 'crops': {for (final e in crops.entries) '${e.key}': e.value.toJson()},
      if (blanks > 0) 'blanks': blanks,
      'modified': modified!.toUtc().toIso8601String(),
    };
  }

  static PageSetup fromJson(Map<String, dynamic>? j) {
    if (j == null) return empty;
    final crops = <int, PageCrop>{};
    final raw = j['crops'] as Map<String, dynamic>? ?? const {};
    for (final e in raw.entries) {
      final page = int.tryParse(e.key);
      if (page != null) crops[page] = PageCrop.fromJson(e.value as Map<String, dynamic>);
    }
    return PageSetup(
      order: (j['order'] as List<dynamic>?)?.map((v) => v as int).toList(),
      crops: crops,
      modified: j['modified'] == null ? null : DateTime.parse(j['modified'] as String),
      blanks: j['blanks'] as int? ?? 0,
    );
  }
}

/// Sucht den Bereich mit Inhalt (nicht-weisse Pixel) in einem Graustufen-
/// bzw. RGBA-Bild und gibt ihn normiert mit etwas Rand zurück.
///
/// [rgba]: Bildpunkte, 4 Byte pro Punkt. Helle Punkte (>= [threshold] in
/// allen Farben) gelten als leer. Einzelne Staubkörner zählen nicht: Eine
/// Zeile/Spalte gilt erst als Inhalt, wenn genug dunkle Punkte darin sind.
PageCrop? findContentBounds(List<int> rgba, int width, int height, {int threshold = 235, double margin = 0.02}) {
  if (width <= 0 || height <= 0) return null;
  final rows = List<int>.filled(height, 0);
  final cols = List<int>.filled(width, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      if (rgba[i] < threshold || rgba[i + 1] < threshold || rgba[i + 2] < threshold) {
        rows[y]++;
        cols[x]++;
      }
    }
  }
  // Mindestens 0.5 % dunkle Punkte (und mindestens 2) – Staub zählt nicht.
  final minRow = math.max(2, (width * 0.005).ceil()), minCol = math.max(2, (height * 0.005).ceil());
  final top = rows.indexWhere((n) => n >= minRow);
  if (top < 0) return null; // leere Seite
  final bottom = rows.lastIndexWhere((n) => n >= minRow);
  final left = cols.indexWhere((n) => n >= minCol);
  final right = cols.lastIndexWhere((n) => n >= minCol);
  return PageCrop(
    left: math.max(0, left / width - margin),
    top: math.max(0, top / height - margin),
    right: math.min(1, (right + 1) / width + margin),
    bottom: math.min(1, (bottom + 1) / height + margin),
  ).normalized();
}
