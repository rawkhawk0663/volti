import 'annotation_layer.dart';

/// Notenwerte für Tabulatur-Schläge (Nenner: 1 = ganze, 4 = Viertel …).
const tabValues = [1, 2, 4, 8, 16, 32];

/// Arten von Taktstrichen.
enum BarKind {
  normal,

  /// Wiederholung Anfang (dick, dünn, zwei Punkte).
  repeatStart,

  /// Wiederholung Ende (zwei Punkte, dünn, dick).
  repeatEnd,

  /// Ende und gleich wieder Anfang einer Wiederholung.
  repeatBoth,

  /// Schlussstrich (dünn, dick).
  last,

  /// Doppelter Taktstrich (zwei dünne, z. B. vor einem neuen Teil).
  doubleLine;

  static BarKind fromName(String? n) => BarKind.values.firstWhere((k) => k.name == n, orElse: () => normal);

  bool get startsRepeat => this == repeatStart || this == repeatBoth;
  bool get endsRepeat => this == repeatEnd || this == repeatBoth;
}

/// Bending-Stufen in Vierteltönen: ¼, ½, 1 (ganzer Ton) und 1½.
const tabBends = [1, 2, 4, 6];

/// Anzeige einer Bending-Stufe (über dem Pfeil).
String bendLabel(int quarters) => switch (quarters) {
  1 => '¼',
  2 => '½',
  4 => 'full',
  6 => '1½',
  _ => '',
};

/// Ghost Note: gedämpfter Ton ohne Tonhöhe, als „x“ auf der Linie. Steht
/// statt einer Bundzahl in [TabBeat.frets].
const ghostNote = -1;

/// Ein Eintrag in einer Tabulatur: ein Schlag (Bundzahlen auf einzelnen
/// Saiten, mit Notenwert) oder ein Taktstrich.
const _keepMeter = Object();

class TabBeat {
  const TabBeat({
    this.frets = const {},
    this.value = 4,
    this.dotted = false,
    this.doubleDot = false,
    this.bar = false,
    this.bends = const {},
    this.slides = const {},
    this.slideIns = const {},
    this.slideOuts = const {},
    this.ties = const {},
    this.tieIns = const {},
    this.legato = const {},
    this.graces = const {},
    this.highlight = 0,
    this.staccato = false,
    this.accent = false,
    this.palmMute = false,
    this.triplet = false,
    this.at,
  }) : kind = BarKind.normal,
       meter = null;

  /// Taktstrich; [at] = von Hand gesetzte Lage (sonst automatisch).
  const TabBeat.bar({this.at, this.kind = BarKind.normal, this.meter})
    : frets = const {},
      value = 4,
      dotted = false,
      doubleDot = false,
      bar = true,
      bends = const {},
      slides = const {},
      slideIns = const {},
      slideOuts = const {},
      ties = const {},
      tieIns = const {},
      legato = const {},
      graces = const {},
      highlight = 0,
      staccato = false,
      accent = false,
      palmMute = false,
      triplet = false;

  /// Art des Taktstrichs (Wiederholung, Schlussstrich …).
  final BarKind kind;

  /// Taktwechsel: Ab diesem Taktstrich gilt diese Taktart („2/4“ …), bis zum
  /// nächsten Wechsel. null = wie davor. Steht nach dem Taktstrich.
  final String? meter;

  /// Gleicher Eintrag mit von Hand gesetzter Lage [at] (siehe [at]).
  TabBeat withAt(double? at) => bar ? TabBeat.bar(at: at, kind: kind, meter: meter) : copyWith(at: at);

  /// Gleicher Eintrag ohne von Hand gesetzte Lage (wieder automatisch).
  TabBeat get withoutAt =>
      at == null ? this : (bar ? TabBeat.bar(kind: kind, meter: meter) : copyWith(at: null));

  /// Gleicher Taktstrich mit anderer Art bzw. Taktart (Lage bleibt).
  TabBeat barWith({BarKind? kind, Object? meter = _keepMeter}) => TabBeat.bar(
    at: at,
    kind: kind ?? this.kind,
    meter: identical(meter, _keepMeter) ? this.meter : meter as String?,
  );

  /// Von Hand gesetzte Lage, null = automatisch.
  ///
  /// Taktstrich: Lage im Schreibbereich der Tabulatur (0 = gleich nach
  /// „TAB“, 1 = rechtes Ende); die Schläge davor und danach verteilen sich
  /// auf den Platz dazwischen.
  ///
  /// Schlag: Lage innerhalb seines Takts (0 = gleich nach dem Taktstrich
  /// davor, 1 = vor dem Taktstrich danach). So wandert er mit, wenn ein
  /// Taktstrich verschoben wird; die Taktstriche selbst bleiben, wo sie sind.
  final double? at;

  /// Saite (0 = oberste Linie, hohe E-Saite) → Bund ([ghostNote] = „x“).
  final Map<int, int> frets;

  /// Bendings: Saite → Stufe in Vierteltönen ([tabBends]).
  final Map<int, int> bends;

  /// Slides: Saiten, deren Ton zur nächsten Bundzahl auf derselben Saite
  /// rutscht (gibt es keine, ein kurzer Slide nach unten).
  final Set<int> slides;

  /// Slide in den Ton hinein: Saite → +1 von unten, −1 von oben
  /// (eine kurze Linie vor der Bundzahl, ohne Ausgangston).
  final Map<int, int> slideIns;

  /// Slide aus dem Ton heraus: Saite → +1 nach oben, −1 nach unten
  /// (eine kurze Linie nach der Bundzahl, ohne Zielton).
  final Map<int, int> slideOuts;

  /// Haltebögen: Saiten, deren Ton zur nächsten Bundzahl auf derselben Saite
  /// gehalten wird (die gehaltene steht in Klammern).
  final Set<int> ties;

  /// Haltebögen von davor: Saiten, deren Ton von einer früheren Note gehalten
  /// wird (Bogen von links in die Zahl, die Zahl in Klammern). Für einen
  /// Haltebogen über einen Zeilenumbruch.
  final Set<int> tieIns;

  /// Hammer-on bzw. Pull-off zur nächsten Note auf derselben Saite (Bogen
  /// über den Zahlen). Ob „H“ oder „P“ dabeisteht, ergibt sich aus den Bünden:
  /// höher = Hammer-on, tiefer = Pull-off.
  final Set<int> legato;

  /// Vorschlagsnoten (Approach-Noten): Saite → Bund einer kleinen Note gleich
  /// vor der Hauptnote auf derselben Saite. Zählt nicht zum Rhythmus; ein
  /// Bogen mit „H“ bzw. „P“ führt in die Hauptnote.
  final Map<int, int> graces;

  /// Farbige Markierung hinter dem Schlag (ARGB mit Deckkraft, 0 = keine).
  /// Aufeinanderfolgende Schläge gleicher Farbe bilden eine Fläche.
  final int highlight;

  /// Staccato (Punkt über dem Schlag) und Akzent („>“).
  final bool staccato, accent;

  /// Palm Mute („P.M.“ über dem Schlag; aufeinanderfolgende mit gestrichelter
  /// Linie verbunden).
  final bool palmMute;

  /// Teil einer Triole (drei im Raum von zwei): dauert ⅔ so lange.
  final bool triplet;

  /// Notenwert als Nenner (1, 2, 4, 8, 16, 32).
  final int value;
  final bool dotted;

  /// Doppelt punktiert (nur zusammen mit [dotted]): dauert 1¾-mal so lang.
  final bool doubleDot;

  /// Zahl der Punkte (0, 1 oder 2).
  int get dots => dotted ? (doubleDot ? 2 : 1) : 0;

  /// Taktstrich statt Schlag.
  final bool bar;

  /// Schlag ohne Bundzahl = Pause.
  bool get isRest => !bar && frets.isEmpty;

  /// Dauer in ganzen Noten (Viertel = 0,25).
  double get length => bar ? 0 : nominal * (triplet ? 2 / 3 : 1);

  /// Dauer ohne Triole (wie geschrieben).
  double get nominal => bar ? 0 : (1 / value) * (dotted ? (doubleDot ? 1.75 : 1.5) : 1);

  TabBeat copyWith({
    Map<int, int>? frets,
    int? value,
    bool? dotted,
    bool? doubleDot,
    Map<int, int>? bends,
    Set<int>? slides,
    Map<int, int>? slideIns,
    Map<int, int>? slideOuts,
    Set<int>? ties,
    Set<int>? tieIns,
    Set<int>? legato,
    Map<int, int>? graces,
    int? highlight,
    bool? staccato,
    bool? accent,
    bool? palmMute,
    bool? triplet,
    Object? at = _keepMeter,
  }) {
    final f = frets ?? this.frets;
    // Bendings und Slides nur dort, wo es eine Bundzahl gibt.
    return TabBeat(
      frets: f,
      value: value ?? this.value,
      dotted: dotted ?? this.dotted,
      doubleDot: (dotted ?? this.dotted) && (doubleDot ?? this.doubleDot),
      bar: bar,
      // Eine Ghost Note hat keine Tonhöhe, also kein Bending.
      bends: {
        for (final e in (bends ?? this.bends).entries)
          if ((f[e.key] ?? ghostNote) >= 0) e.key: e.value,
      },
      slides: {
        for (final st in slides ?? this.slides)
          if (f.containsKey(st)) st,
      },
      slideIns: {
        for (final e in (slideIns ?? this.slideIns).entries)
          if (f.containsKey(e.key)) e.key: e.value,
      },
      slideOuts: {
        for (final e in (slideOuts ?? this.slideOuts).entries)
          if (f.containsKey(e.key)) e.key: e.value,
      },
      ties: {
        for (final st in ties ?? this.ties)
          if (f.containsKey(st)) st,
      },
      legato: {
        for (final st in legato ?? this.legato)
          if (f.containsKey(st)) st,
      },
      // Vorschlag nur vor einer echten Note (nicht vor einer Ghost Note).
      graces: {
        for (final e in (graces ?? this.graces).entries)
          if ((f[e.key] ?? ghostNote) >= 0) e.key: e.value,
      },
      tieIns: {
        for (final st in tieIns ?? this.tieIns)
          if (f.containsKey(st)) st,
      },
      // Ohne Bundzahl (Pause) keine Artikulation.
      staccato: f.isNotEmpty && (staccato ?? this.staccato),
      accent: f.isNotEmpty && (accent ?? this.accent),
      palmMute: f.isNotEmpty && (palmMute ?? this.palmMute),
      highlight: highlight ?? this.highlight,
      triplet: triplet ?? this.triplet,
      at: identical(at, _keepMeter) ? this.at : at as double?,
    );
  }

  Map<String, dynamic> toJson() => bar
      ? {
          'bar': true,
          if (at != null) 'at': at,
          if (kind != BarKind.normal) 'k': kind.name,
          if (meter != null) 'm': meter,
        }
      : {
          if (frets.isNotEmpty) 'f': {for (final e in frets.entries) '${e.key}': e.value},
          'v': value,
          if (dotted) 'dot': true,
          if (dotted && doubleDot) 'dot2': true,
          if (bends.isNotEmpty) 'bend': {for (final e in bends.entries) '${e.key}': e.value},
          if (slides.isNotEmpty) 'slide': (slides.toList()..sort()),
          if (slideIns.isNotEmpty) 'sIn': {for (final e in slideIns.entries) '${e.key}': e.value},
          if (slideOuts.isNotEmpty) 'sOut': {for (final e in slideOuts.entries) '${e.key}': e.value},
          if (ties.isNotEmpty) 'tie': (ties.toList()..sort()),
          if (tieIns.isNotEmpty) 'tieIn': (tieIns.toList()..sort()),
          if (legato.isNotEmpty) 'hp': (legato.toList()..sort()),
          if (graces.isNotEmpty) 'gr': {for (final e in graces.entries) '${e.key}': e.value},
          if (staccato) 'stacc': true,
          if (accent) 'acc': true,
          if (palmMute) 'pm': true,
          if (triplet) 'tri': true,
          if (highlight != 0) 'hl': highlight,
          if (at != null) 'at': at,
        };

  static TabBeat fromJson(Map<String, dynamic> j) {
    if (j['bar'] == true) {
      final at = (j['at'] as num?)?.toDouble();
      final m = j['m'] as String?;
      return TabBeat.bar(
        at: at?.clamp(0.0, 1.0),
        kind: BarKind.fromName(j['k'] as String?),
        meter: meterLength(m) == null ? null : m,
      );
    }
    final f = j['f'] as Map<String, dynamic>? ?? const {};
    final v = j['v'] as int? ?? 4;
    Map<int, int> strings(Map<String, dynamic> m) => {
      for (final e in m.entries)
        if (int.tryParse(e.key) case final s? when s >= 0 && s < TabBlock.strings)
          s: (e.value as num).toInt().clamp(ghostNote, 99),
    };
    final frets = strings(f);
    // Richtungen: nur +1/−1 und nur, wo eine Bundzahl steht.
    Map<int, int> directions(Object? m) => {
      for (final e in strings(m is Map<String, dynamic> ? m : const {}).entries)
        if (frets.containsKey(e.key) && (e.value == 1 || e.value == -1)) e.key: e.value,
    };
    return TabBeat(
      frets: frets,
      value: tabValues.contains(v) ? v : 4,
      dotted: j['dot'] == true,
      doubleDot: j['dot'] == true && j['dot2'] == true,
      bends: {
        for (final e in strings(j['bend'] as Map<String, dynamic>? ?? const {}).entries)
          if ((frets[e.key] ?? ghostNote) >= 0 && tabBends.contains(e.value)) e.key: e.value,
      },
      slides: {
        for (final st in j['slide'] as List<dynamic>? ?? const [])
          if (st is int && frets.containsKey(st)) st,
      },
      slideIns: directions(j['sIn']),
      slideOuts: directions(j['sOut']),
      ties: {
        for (final st in j['tie'] as List<dynamic>? ?? const [])
          if (st is int && frets.containsKey(st)) st,
      },
      legato: {
        for (final st in j['hp'] as List<dynamic>? ?? const [])
          if (st is int && frets.containsKey(st)) st,
      },
      graces: {
        for (final e in strings(j['gr'] as Map<String, dynamic>? ?? const {}).entries)
          if ((frets[e.key] ?? ghostNote) >= 0 && e.value >= 0) e.key: e.value,
      },
      tieIns: {
        for (final st in j['tieIn'] as List<dynamic>? ?? const [])
          if (st is int && frets.containsKey(st)) st,
      },
      staccato: frets.isNotEmpty && j['stacc'] == true,
      accent: frets.isNotEmpty && j['acc'] == true,
      palmMute: frets.isNotEmpty && j['pm'] == true,
      triplet: j['tri'] == true,
      highlight: (j['hl'] as num?)?.toInt() ?? 0,
      at: (j['at'] as num?)?.toDouble().clamp(0.0, 1.0),
    );
  }

  static bool _sameMap(Map<int, int> a, Map<int, int> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  bool operator ==(Object other) =>
      other is TabBeat &&
      other.bar == bar &&
      other.at == at &&
      other.kind == kind &&
      other.meter == meter &&
      other.value == value &&
      other.dotted == dotted &&
      other.doubleDot == doubleDot &&
      _sameMap(other.frets, frets) &&
      _sameMap(other.bends, bends) &&
      other.slides.length == slides.length &&
      other.slides.containsAll(slides) &&
      _sameMap(other.slideIns, slideIns) &&
      _sameMap(other.slideOuts, slideOuts) &&
      other.ties.length == ties.length &&
      other.ties.containsAll(ties) &&
      other.tieIns.length == tieIns.length &&
      other.tieIns.containsAll(tieIns) &&
      other.legato.length == legato.length &&
      other.legato.containsAll(legato) &&
      _sameMap(other.graces, graces) &&
      other.staccato == staccato &&
      other.accent == accent &&
      other.palmMute == palmMute &&
      other.highlight == highlight &&
      other.triplet == triplet;

  @override
  int get hashCode => Object.hashAll([
    bar,
    at,
    kind,
    meter,
    value,
    dotted,
    doubleDot,
    Object.hashAllUnordered(frets.entries.map((e) => e.key * 100 + e.value)),
    Object.hashAllUnordered(bends.entries.map((e) => e.key * 100 + e.value)),
    Object.hashAllUnordered(slides),
    Object.hashAllUnordered(slideIns.entries.map((e) => e.key * 10 + e.value)),
    Object.hashAllUnordered(slideOuts.entries.map((e) => e.key * 10 + e.value)),
    Object.hashAllUnordered(ties),
    Object.hashAllUnordered(tieIns),
    Object.hashAllUnordered(legato),
    Object.hashAllUnordered(graces.entries.map((e) => e.key * 100 + e.value)),
    staccato,
    accent,
    palmMute,
    highlight,
    triplet,
  ]);
}

/// Taktarten zur Auswahl.
const tabMeters = ['2/4', '3/4', '4/4', '5/4', '2/2', '3/8', '6/8', '7/8', '9/8', '12/8'];

/// Länge eines Takts in ganzen Noten („3/4“ → 0,75); ungültig → null.
double? meterLength(String? meter) {
  final m = RegExp(r'^(\d{1,2})/(1|2|4|8|16)$').firstMatch(meter ?? '');
  if (m == null) return null;
  final n = int.parse(m.group(1)!);
  if (n < 1) return null;
  return n / int.parse(m.group(2)!);
}

/// Pausen, die zusammen [length] (in ganzen Noten) ergeben – für einen leeren
/// Takt: möglichst wenige, punktierte erlaubt (3/4 = punktierte Halbe).
List<TabBeat> restsFor(double length) {
  final out = <TabBeat>[];
  var left = length;
  while (left > 1e-9 && out.length < 16) {
    TabBeat? pick;
    for (final v in tabValues) {
      for (final dot in [true, false]) {
        final b = TabBeat(value: v, dotted: dot);
        if (b.length <= left + 1e-9) {
          pick = b;
          break;
        }
      }
      if (pick != null) break;
    }
    if (pick == null) break;
    out.add(pick);
    left -= pick.length;
  }
  return out;
}

/// Taktstriche neu nach der Taktart setzen: alle bisherigen weg, dann nach
/// jedem vollen Takt einer (ein zu langer Schlag beendet seinen Takt).
/// Besondere Taktstriche bleiben erhalten: ein Wiederholungs-Anfang ganz
/// vorne, ein Taktstrich ganz am Ende (z. B. Schlussstrich), und die übrigen
/// Arten der Reihe nach.
List<TabBeat> rebar(List<TabBeat> beats, double measure) {
  // Die Takte ändern sich: von Hand gesetzte Lagen der Noten gelten nicht mehr.
  final notes = [for (final b in beats) if (!b.bar) b.at == null ? b : b.copyWith(at: null)];
  final first = beats.isNotEmpty && beats.first.bar ? beats.first : null;
  final last = beats.length > 1 && beats.last.bar ? beats.last : null;
  // Arten und Taktwechsel der Taktstriche in der Mitte, der Reihe nach.
  final middle = [
    for (var i = 0; i < beats.length; i++)
      if (beats[i].bar && i != 0 && i != beats.length - 1) beats[i],
  ];
  var k = 0;
  final out = <TabBeat>[if (first != null) TabBeat.bar(kind: first.kind, meter: first.meter)];
  var len = meterLength(first?.meter) ?? measure;
  var acc = 0.0;
  for (var i = 0; i < notes.length; i++) {
    out.add(notes[i]);
    acc += notes[i].length;
    if (acc >= len - 1e-9 && i < notes.length - 1) {
      final m = k < middle.length ? middle[k] : null;
      out.add(TabBeat.bar(kind: m?.kind ?? BarKind.normal, meter: m?.meter));
      len = meterLength(m?.meter) ?? len;
      k++;
      acc = 0;
    }
  }
  if (last != null && notes.isNotEmpty) out.add(TabBeat.bar(kind: last.kind, meter: last.meter));
  return out;
}

/// Takte als Bereiche [start, end) in der Liste (ohne den Taktstrich), dazu
/// ihre Länge in ganzen Noten.
List<({int start, int end, double length})> measuresOf(List<TabBeat> beats) {
  final out = <({int start, int end, double length})>[];
  var start = 0;
  var len = 0.0;
  for (var i = 0; i <= beats.length; i++) {
    if (i == beats.length || beats[i].bar) {
      out.add((start: start, end: i, length: len));
      start = i + 1;
      len = 0;
    } else {
      len += beats[i].length;
    }
  }
  return out;
}

/// Länge jedes Takts aus [measuresOf] (null = frei): [base] ist die Taktart
/// der Tabulatur, Taktwechsel an einem Taktstrich gelten ab dort.
List<double?> measureLengths(List<TabBeat> beats, double? base) {
  final out = <double?>[];
  var cur = base;
  for (final m in measuresOf(beats)) {
    if (m.start > 0) {
      final bar = beats[m.start - 1];
      if (bar.bar && bar.meter != null) cur = meterLength(bar.meter) ?? cur;
    }
    out.add(cur);
  }
  return out;
}

/// Taktart als Text, die im Takt [index] gilt (null = frei).
String? meterOfMeasure(List<TabBeat> beats, String? base, int index) {
  var cur = base;
  for (final (k, m) in measuresOf(beats).indexed) {
    if (m.start > 0) {
      final bar = beats[m.start - 1];
      if (bar.bar && bar.meter != null) cur = bar.meter;
    }
    if (k == index) return cur;
  }
  return cur;
}

/// Triolen-Gruppen: aufeinanderfolgende Triolen-Schläge, je drei im Raum von
/// zwei (z. B. drei Achtel = eine Viertel). [complete] = die Gruppe ist voll.
List<({int start, int end, bool complete})> tripletGroups(List<TabBeat> beats) {
  final out = <({int start, int end, bool complete})>[];
  int? start;
  var acc = 0.0, target = 0.0;
  for (var i = 0; i < beats.length; i++) {
    final b = beats[i];
    if (b.bar || !b.triplet) {
      if (start != null) out.add((start: start, end: i - 1, complete: false));
      start = null;
      continue;
    }
    if (start == null) {
      start = i;
      acc = 0;
      target = b.nominal * 3;
    }
    acc += b.nominal;
    if (acc >= target - 1e-9) {
      out.add((start: start, end: i, complete: true));
      start = null;
    }
  }
  if (start != null) out.add((start: start, end: beats.length - 1, complete: false));
  return out;
}

/// Eine Tabulatur auf einer Notenseite: sechs Linien mit Bundzahlen und
/// Rhythmus, mit der Tastatur oder dem Zahlenfeld geschrieben.
///
/// Position normiert wie Text-Notizen: [x]/[y] (oberste Linie) relativ zu
/// Breite und Höhe der Seite, [width] relativ zur Breite, [gap] (Abstand der
/// Linien) relativ zur Seitenbreite. Beim Zusammenführen gewinnt die jüngste
/// Fassung als Ganzes – auch beim Löschen, damit „Rückgängig“ eine gelöschte
/// Tabulatur zurückholen kann.
class TabBlock {
  TabBlock({
    required this.id,
    required this.page,
    required this.x,
    required this.y,
    required this.width,
    required this.gap,
    required this.createdAt,
    this.beats = const [],
    this.color = 0xFF000000,
    this.background = noBackground,
    this.modifiedAt,
    this.deleted = false,
    this.layer,
    this.meter,
  });

  static const strings = 6;

  /// Kein Hintergrund (durchsichtig).
  static const noBackground = 0;

  /// Linienabstand, wenn man nur tippt bzw. waagrecht zieht (wie die Form
  /// „Tabulatur“: 6 Linien auf 6 % der Seitenbreite).
  static const defaultGap = 0.012;

  final String id;
  final int page;
  final double x, y, width, gap;
  final List<TabBeat> beats;
  final int color;

  /// Hintergrundfarbe (ARGB); [noBackground] = durchsichtig.
  final int background;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final bool deleted;

  /// Ebene (null = Grund-Ebene [kDefaultLayer]).
  final String? layer;

  /// Taktart, z. B. „4/4“ (null = frei, Taktstriche nur von Hand).
  final String? meter;

  /// Länge eines Takts in ganzen Noten (null = frei).
  double? get measure => meterLength(meter);

  DateTime get lastChange => modifiedAt ?? createdAt;

  TabBlock copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? gap,
    List<TabBeat>? beats,
    int? color,
    int? background,
    DateTime? modifiedAt,
    bool? deleted,
    String? layer,
    Object? meter = _keep,
  }) => TabBlock(
    id: id ?? this.id,
    page: page,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    gap: gap ?? this.gap,
    beats: beats ?? this.beats,
    color: color ?? this.color,
    background: background ?? this.background,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    deleted: deleted ?? this.deleted,
    layer: layer ?? this.layer,
    meter: identical(meter, _keep) ? this.meter : meter as String?,
  );

  static const _keep = Object();

  Map<String, dynamic> toJson() => {
    'id': id,
    'page': page,
    'x': x,
    'y': y,
    'w': width,
    'gap': gap,
    'beats': [for (final b in beats) b.toJson()],
    if (color != 0xFF000000) 'color': color,
    if (background != noBackground) 'bg': background,
    'created': createdAt.toUtc().toIso8601String(),
    if (modifiedAt != null) 'modified': modifiedAt!.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
    if (layer != null && layer != kDefaultLayer) 'layer': layer,
    if (meter != null) 'meter': meter,
  };

  static TabBlock fromJson(Map<String, dynamic> j) => TabBlock(
    id: j['id'] as String,
    page: j['page'] as int,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    width: (j['w'] as num?)?.toDouble() ?? 0.8,
    gap: (j['gap'] as num?)?.toDouble() ?? defaultGap,
    beats: [for (final b in j['beats'] as List<dynamic>? ?? const []) TabBeat.fromJson(b as Map<String, dynamic>)],
    color: j['color'] as int? ?? 0xFF000000,
    background: j['bg'] as int? ?? noBackground,
    createdAt: DateTime.parse(j['created'] as String),
    modifiedAt: j['modified'] == null ? null : DateTime.parse(j['modified'] as String),
    deleted: j['deleted'] == true,
    layer: j['layer'] as String?,
    meter: meterLength(j['meter'] as String?) == null ? null : j['meter'] as String,
  );
}

/// Halbtöne zwischen Saite [s] + 1 (tiefer) und Saite [s] in
/// Standardstimmung (e-H-G-D-A-E): zwischen G und H vier, sonst fünf.
int _stringStep(int s) => s == 1 ? 4 : 5;

/// Ein Schlag um [semitones] Halbtöne verschoben, oder null, wenn ein Ton
/// nicht unterzubringen ist. Techniken wandern mit ihrer Note mit.
TabBeat? transposeBeat(TabBeat b, int semitones) {
  final target = <int, (int, int)>{}; // alte Saite → (neue Saite, Bund)
  for (final e in b.frets.entries) {
    if (e.value == ghostNote) {
      target[e.key] = (e.key, ghostNote);
      continue;
    }
    var st = e.key, fret = e.value + semitones;
    // Zu tief: auf die tiefere Saite (grösserer Index), zu hoch: auf die höhere.
    while (fret < 0 && st < TabBlock.strings - 1) {
      fret += _stringStep(st);
      st++;
    }
    while (fret > TabEditor.maxFret && st > 0) {
      st--;
      fret -= _stringStep(st);
    }
    if (fret < 0 || fret > TabEditor.maxFret) return null;
    target[e.key] = (st, fret);
  }
  final used = target.values.map((v) => v.$1).toList();
  if (used.toSet().length != used.length) return null; // zwei Töne auf einer Saite
  int to(int st) => target[st]!.$1;
  Map<int, int> remap(Map<int, int> m) => {for (final e in m.entries) if (target.containsKey(e.key)) to(e.key): e.value};
  Set<int> remapSet(Set<int> m) => {for (final st in m) if (target.containsKey(st)) to(st)};
  return b.copyWith(
    frets: {for (final v in target.values) v.$1: v.$2},
    bends: remap(b.bends),
    slides: remapSet(b.slides),
    slideIns: remap(b.slideIns),
    slideOuts: remap(b.slideOuts),
    ties: remapSet(b.ties),
    tieIns: remapSet(b.tieIns),
    legato: remapSet(b.legato),
    // Vorschläge gehen im gleichen Abstand zur Hauptnote mit (sonst weg).
    graces: {
      for (final e in b.graces.entries)
        if (target[e.key] case (final st, final fret)
            when e.value + fret - b.frets[e.key]! >= 0 && e.value + fret - b.frets[e.key]! <= TabEditor.maxFret)
          st: e.value + fret - b.frets[e.key]!,
    },
  );
}

/// Schreiben in einer Tabulatur: Cursor (Schlag und Saite) und alle
/// Änderungen. Rein rechnerisch, ohne Anzeige – die Notenansicht wendet das
/// Ergebnis ([beats]) auf die gespeicherte Tabulatur an.
///
/// Der Cursor darf einen Platz hinter dem letzten Eintrag stehen: Dort
/// Getipptes legt einen neuen Schlag an.
class TabEditor {
  TabEditor(List<TabBeat> beats, {this.beat = 0, this.string = 0, double? measure, this.meter})
    : measure = measure ?? meterLength(meter),
      beats = [...beats];

  /// Länge eines Takts (aus der Taktart der Tabulatur); null = frei.
  double? measure;

  /// Taktart der Tabulatur („4/4“ …), gilt im ersten Takt. Ändert
  /// [setMeasureMeter] sie, muss sie in die Tabulatur übernommen werden.
  String? meter;

  List<TabBeat> beats;

  /// Position des Cursors (0 … beats.length).
  int beat;

  /// Saite unter dem Cursor (0 = oberste Linie).
  int string;

  /// Markierung: Anfang (der Cursor ist das andere Ende). null = keine.
  int? anchor;

  /// Markierte Saiten: Anfang (die Saite des Cursors ist das andere Ende).
  /// null = alle Saiten der markierten Schläge.
  int? stringAnchor;

  /// Markierte Saiten (beide inklusive), null = alle.
  (int, int)? get stringSelection {
    final a = stringAnchor;
    if (a == null) return null;
    return a <= string ? (a, string) : (string, a);
  }

  /// Nur einzelne Saiten markiert (nicht ganze Schläge)?
  bool get _partialStrings {
    final s = stringSelection;
    return s != null && !(s.$1 == 0 && s.$2 == TabBlock.strings - 1);
  }

  /// Markierung nach oben/unten erweitern (mehrere Noten übereinander).
  void extendString(int by) {
    if (beats.isEmpty) return;
    anchor ??= beat.clamp(0, beats.length - 1);
    stringAnchor ??= string;
    string = (string + by).clamp(0, TabBlock.strings - 1);
    _resetDigits();
  }

  /// Den ganzen Schlag unter dem Cursor markieren (alle Noten übereinander,
  /// ebenso Taktstrich oder Pause). Löschen entfernt ihn dann ganz; mit
  /// Umschalt + ← / → wird die Markierung erweitert.
  void selectColumn() {
    if (beats.isEmpty) return;
    beat = beat.clamp(0, beats.length - 1);
    anchor ??= beat;
    stringAnchor = null;
    _resetDigits();
  }

  /// Markierte Einträge als Bereich [from, to] (beide inklusive), oder null.
  (int, int)? get selection {
    final a = anchor;
    if (a == null || beats.isEmpty) return null;
    final last = beats.length - 1;
    final x = a.clamp(0, last), y = beat.clamp(0, last);
    return x <= y ? (x, y) : (y, x);
  }

  /// Markierung um [by] Einträge erweitern bzw. verkleinern.
  void extend(int by) {
    if (beats.isEmpty) return;
    anchor ??= beat.clamp(0, beats.length - 1);
    beat = (beat.clamp(0, beats.length - 1) + by).clamp(0, beats.length - 1);
    _resetDigits();
  }

  /// Von [from] bis [to] markieren (z. B. mit dem Stift gezogen).
  void selectRange(int from, int to) {
    if (beats.isEmpty) return;
    stringAnchor = null;
    anchor = from.clamp(0, beats.length - 1);
    beat = to.clamp(0, beats.length - 1);
  }

  void selectAll() {
    if (beats.isEmpty) return;
    stringAnchor = null;
    anchor = 0;
    beat = beats.length - 1;
  }

  /// Markierte Einträge (ohne Markierung: der Eintrag unter dem Cursor).
  /// Sind nur einzelne Saiten markiert, nur deren Bundzahlen.
  List<TabBeat> copySelection() {
    final sel = selection;
    if (sel == null) return beat < beats.length ? [beats[beat]] : const [];
    final part = beats.sublist(sel.$1, sel.$2 + 1);
    final ss = stringSelection;
    if (!_partialStrings || ss == null) return part;
    return [
      for (final b in part)
        b.bar ? b : b.copyWith(frets: {for (final e in b.frets.entries) if (e.key >= ss.$1 && e.key <= ss.$2) e.key: e.value}),
    ];
  }

  /// Markierung löschen. Ganze Schläge werden entfernt; sind nur einzelne
  /// Saiten markiert, verschwinden nur deren Bundzahlen (die Schläge und der
  /// Rhythmus bleiben). Gibt false zurück, wenn nichts markiert war.
  bool deleteSelection() {
    final sel = selection;
    if (sel == null) return false;
    final ss = stringSelection;
    if (_partialStrings && ss != null) {
      for (var i = sel.$1; i <= sel.$2; i++) {
        final b = beats[i];
        if (b.bar) continue;
        beats[i] = b.copyWith(frets: {for (final e in b.frets.entries) if (e.key < ss.$1 || e.key > ss.$2) e.key: e.value});
      }
    } else {
      beats.removeRange(sel.$1, sel.$2 + 1);
      beat = sel.$1.clamp(0, beats.length);
    }
    anchor = null;
    stringAnchor = null;
    _resetDigits();
    return true;
  }

  /// Einfügen vor dem Cursor (eine Markierung wird ersetzt). Der Cursor steht
  /// danach hinter dem Eingefügten.
  void paste(List<TabBeat> clip) {
    if (clip.isEmpty) return;
    // Ohne Kenntnis der Anordnung: von Hand gesetzte Lagen wieder automatisch
    // (die Notenansicht fügt mit Anordnung ein, siehe TabSession.paste).
    insertPasted(preparePaste(), [for (final b in clip) b.withoutAt]);
  }

  /// Einfügen vorbereiten: eine Markierung wird ersetzt (bzw. bei einzelnen
  /// markierten Saiten wird davor eingefügt). Gibt die Einfügestelle zurück.
  int preparePaste() {
    if (_partialStrings) {
      // Nur Noten markiert: nichts ersetzen, vor dem markierten Bereich einfügen.
      beat = selection?.$1 ?? beat;
      anchor = null;
      stringAnchor = null;
    } else {
      deleteSelection();
    }
    return beat.clamp(0, beats.length);
  }

  /// Einträge an der Stelle [at] einfügen, der Cursor steht danach dahinter.
  void insertPasted(int at, List<TabBeat> items) {
    beats.insertAll(at, items);
    beat = at + items.length;
    _resetDigits();
  }

  /// Zuletzt getippte Ziffer (für zweistellige Bünde wie 12).
  int? _lastDigit;
  DateTime? _lastDigitAt;
  int? _lastDigitBeat, _lastDigitString;

  /// Zweistellige Bünde: Zweite Ziffer innerhalb dieser Zeit.
  static const digitPause = Duration(milliseconds: 900);
  static const maxFret = 24;

  TabBeat? get current => beat < beats.length ? beats[beat] : null;

  /// Notenwert für einen neuen Schlag: wie der Schlag davor (sonst Viertel).
  TabBeat _fresh() {
    for (var i = beat - 1; i >= 0; i--) {
      if (beats[i].bar) continue;
      // Eine angefangene Triole geht weiter, bis sie voll ist.
      final open = tripletGroups(beats.sublist(0, i + 1)).lastOrNull;
      final inOpen = open != null && open.end == i && !open.complete;
      return TabBeat(value: beats[i].value, triplet: inOpen);
    }
    return const TabBeat();
  }

  /// Am Ende steht der Cursor auf einem neuen, leeren Platz – gibt es den
  /// Schlag noch nicht, wird er jetzt angelegt.
  TabBeat _ensureBeat() {
    if (beat >= beats.length) {
      // Mit Taktart: Ist der letzte Takt voll, kommt zuerst der Taktstrich.
      final m = measureLengths(beats, measure).last;
      if (m != null && beats.isNotEmpty && !beats.last.bar && measuresOf(beats).last.length >= m - 1e-9) {
        beats.add(const TabBeat.bar());
      }
      beats.add(_fresh());
      beat = beats.length - 1;
    }
    if (beats[beat].bar) {
      // Auf einem Taktstrich: dahinter einen Schlag einfügen.
      beat++;
      beats.insert(beat, _fresh());
    }
    return beats[beat];
  }

  void _resetDigits() {
    _lastDigit = null;
    graceInput = false;
    _graceDigitAt = null;
  }

  /// Die nächste getippte Bundzahl wird zur Vorschlagsnote der Note unter
  /// dem Cursor (bis zu einer anderen Taste oder einer Pause).
  bool graceInput = false;
  DateTime? _graceDigitAt;

  /// Vorschlagsnote (Approach-Note) vor der Note unter dem Cursor: Gibt es
  /// schon eine, wird sie entfernt; sonst kommt die nächste Bundzahl dorthin.
  void toggleGrace() {
    final b = current;
    if (b == null || b.bar || (b.frets[string] ?? ghostNote) < 0) return;
    if (b.graces.containsKey(string)) {
      beats[beat] = b.copyWith(graces: {...b.graces}..remove(string));
      _resetDigits();
      return;
    }
    _resetDigits();
    graceInput = true;
  }

  /// Vorschlagsnote direkt setzen (Zahlenfeld, Tests).
  void _setGrace(int fret) {
    final b = beats[beat];
    beats[beat] = b.copyWith(graces: {...b.graces, string: fret.clamp(0, maxFret)});
  }

  /// Ziffer tippen. Kommt rasch eine zweite (z. B. 1 dann 2), entsteht 12.
  void digit(int d, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (graceInput) {
      // Vorschlagsnote: erste Ziffer, oder die zweite rasch danach.
      final at = _graceDigitAt;
      final cur = current;
      if ((at == null || t.difference(at) <= digitPause) && cur != null && !cur.bar && (cur.frets[string] ?? ghostNote) >= 0) {
        final last = _lastDigit;
        final fret = at != null && last != null && last * 10 + d <= maxFret ? last * 10 + d : d;
        _lastDigit = fret == d ? d : null;
        _setGrace(fret);
        _graceDigitAt = t;
        return;
      }
      _resetDigits();
    }
    final b = _ensureBeat();
    var fret = d;
    final last = _lastDigit, at = _lastDigitAt;
    if (last != null &&
        at != null &&
        _lastDigitBeat == beat &&
        _lastDigitString == string &&
        t.difference(at) <= digitPause &&
        last * 10 + d <= maxFret) {
      fret = last * 10 + d;
      _lastDigit = null; // dritte Ziffer beginnt neu
    } else {
      _lastDigit = d;
    }
    _lastDigitAt = t;
    _lastDigitBeat = beat;
    _lastDigitString = string;
    beats[beat] = b.copyWith(frets: {...b.frets, string: fret});
  }

  /// Bund direkt setzen (Zahlenfeld 0–24).
  void setFret(int fret) {
    final cur = current;
    if (graceInput && cur != null && !cur.bar && (cur.frets[string] ?? ghostNote) >= 0) {
      _setGrace(fret);
      _resetDigits();
      return;
    }
    final b = _ensureBeat();
    beats[beat] = b.copyWith(frets: {...b.frets, string: fret.clamp(0, maxFret)});
    _resetDigits();
  }

  /// Notenwert des Schlags unter dem Cursor.
  void setValue(int v) {
    if (!tabValues.contains(v)) return;
    final b = _ensureBeat();
    beats[beat] = b.copyWith(value: v);
    _resetDigits();
  }

  /// Kürzer (Viertel → Achtel) bzw. länger ([steps] negativ).
  void shorter([int steps = 1]) {
    final b = _ensureBeat();
    final i = (tabValues.indexOf(b.value) + steps).clamp(0, tabValues.length - 1);
    beats[beat] = b.copyWith(value: tabValues[i]);
    _resetDigits();
  }

  /// Punkte durchschalten: ohne → punktiert → doppelt punktiert → ohne.
  void toggleDot() => setDots((current?.dots ?? 0) == 2 ? 0 : (current?.dots ?? 0) + 1);

  /// Zahl der Punkte (0–2) für den Schlag unter dem Cursor.
  void setDots(int n) {
    final b = _ensureBeat();
    beats[beat] = b.copyWith(dotted: n >= 1, doubleDot: n >= 2);
    _resetDigits();
  }

  /// Schlag zur Pause machen (alle Bundzahlen weg, Notenwert bleibt).
  void rest() {
    final b = _ensureBeat();
    beats[beat] = b.copyWith(frets: const {});
    _resetDigits();
  }

  /// Taktstrich nach dem Schlag unter dem Cursor; der Cursor springt dahinter.
  void bar() {
    final at = beat >= beats.length ? beats.length : beat + 1;
    // Kein doppelter Taktstrich.
    if (at > 0 && at <= beats.length && beats[at - 1].bar) {
      beat = at;
      return;
    }
    beats.insert(at, const TabBeat.bar());
    beat = at + 1;
    _resetDigits();
  }

  /// Bundzahl auf der Saite unter dem Cursor entfernen.
  void clearNote() {
    final b = current;
    if (b == null || b.bar || !b.frets.containsKey(string)) return;
    beats[beat] = b.copyWith(frets: {...b.frets}..remove(string));
    _resetDigits();
  }

  /// Ghost Note („x“) auf der Saite unter dem Cursor setzen; steht schon
  /// eine, wird sie wieder entfernt. Ersetzt eine Bundzahl.
  void toggleGhost() {
    final cur = current;
    if (cur != null && !cur.bar && cur.frets[string] == ghostNote) {
      beats[beat] = cur.copyWith(frets: {...cur.frets}..remove(string));
    } else {
      final b = _ensureBeat();
      beats[beat] = b.copyWith(frets: {...b.frets, string: ghostNote});
    }
    _resetDigits();
  }

  /// Bending auf der Saite unter dem Cursor: setzen bzw. (gleiche Stufe
  /// nochmals) entfernen. Nur wo eine Bundzahl steht (keine Ghost Note).
  void bend(int quarters) {
    final b = current;
    if (b == null || b.bar || (b.frets[string] ?? ghostNote) < 0 || !tabBends.contains(quarters)) return;
    final bends = {...b.bends};
    bends[string] == quarters ? bends.remove(string) : bends[string] = quarters;
    beats[beat] = b.copyWith(bends: bends);
    _resetDigits();
  }

  /// Nächste Bending-Stufe (¼ → ½ → 1 → 1½ → keine).
  void cycleBend() {
    final b = current;
    if (b == null || b.bar || (b.frets[string] ?? ghostNote) < 0) return;
    final now = b.bends[string];
    final i = now == null ? 0 : tabBends.indexOf(now) + 1;
    final bends = {...b.bends};
    i >= tabBends.length ? bends.remove(string) : bends[string] = tabBends[i];
    beats[beat] = b.copyWith(bends: bends);
    _resetDigits();
  }

  /// Slide zur nächsten Bundzahl auf dieser Saite: ein/aus. Ersetzt einen
  /// Slide aus dem Ton heraus (beides zugleich geht nicht).
  void toggleSlide() {
    final b = current;
    if (b == null || b.bar || !b.frets.containsKey(string)) return;
    final slides = {...b.slides};
    slides.contains(string) ? slides.remove(string) : slides.add(string);
    beats[beat] = b.copyWith(slides: slides, slideOuts: {...b.slideOuts}..remove(string));
    _resetDigits();
  }

  /// Slide in den Ton hinein setzen: [dir] +1 = von unten, −1 = von oben.
  /// Dieselbe Richtung nochmals entfernt ihn.
  void slideIn(int dir) {
    final b = current;
    if (b == null || b.bar || !b.frets.containsKey(string)) return;
    final ins = {...b.slideIns};
    ins[string] == dir ? ins.remove(string) : ins[string] = dir;
    beats[beat] = b.copyWith(slideIns: ins);
    _resetDigits();
  }

  /// Slide aus dem Ton heraus setzen: [dir] +1 = nach oben, −1 = nach unten.
  /// Dieselbe Richtung nochmals entfernt ihn; ersetzt einen Slide zur
  /// nächsten Bundzahl.
  void slideOut(int dir) {
    final b = current;
    if (b == null || b.bar || !b.frets.containsKey(string)) return;
    final outs = {...b.slideOuts};
    outs[string] == dir ? outs.remove(string) : outs[string] = dir;
    beats[beat] = b.copyWith(slideOuts: outs, slides: {...b.slides}..remove(string));
    _resetDigits();
  }

  /// Durchschalten (für eine einzige Taste): von unten → von oben → keiner.
  void cycleSlideIn() => _cycle(current?.slideIns[string], slideIn);

  /// Durchschalten: nach oben → nach unten → keiner.
  void cycleSlideOut() => _cycle(current?.slideOuts[string], slideOut);

  void _cycle(int? now, void Function(int) set) {
    if (now == null) {
      set(1);
    } else if (now == 1) {
      set(-1);
    } else {
      set(-1); // gleiche Richtung nochmals = weg
    }
  }

  /// Haltebogen zur nächsten Note auf dieser Saite ein/aus. Hat der nächste
  /// Schlag dort noch keine Bundzahl, bekommt er dieselbe.
  void toggleTie() {
    final b = current;
    if (b == null || b.bar) return;
    final fret = b.frets[string];
    if (fret == null) return;
    final ties = {...b.ties};
    if (ties.remove(string)) {
      beats[beat] = b.copyWith(ties: ties);
    } else {
      beats[beat] = b.copyWith(ties: ties..add(string));
      for (var k = beat + 1; k < beats.length; k++) {
        if (beats[k].bar) continue;
        if (!beats[k].frets.containsKey(string)) {
          beats[k] = beats[k].copyWith(frets: {...beats[k].frets, string: fret});
        }
        break;
      }
    }
    _resetDigits();
  }

  /// Farbige Markierung ([argb], 0 = entfernen) für die markierten Schläge
  /// bzw. den Schlag unter dem Cursor.
  void setHighlight(int argb) {
    if (beats.isEmpty) return;
    final sel = selection ?? (beat, beat);
    for (var i = sel.$1; i <= sel.$2 && i < beats.length; i++) {
      if (!beats[i].bar) beats[i] = beats[i].copyWith(highlight: argb);
    }
    _resetDigits();
  }

  /// Hammer-on bzw. Pull-off zur nächsten Note auf dieser Saite ein/aus.
  void toggleLegato() {
    final b = current;
    if (b == null || b.bar) return;
    final fret = b.frets[string];
    if (fret == null || fret == ghostNote) return;
    final l = {...b.legato};
    l.contains(string) ? l.remove(string) : l.add(string);
    beats[beat] = b.copyWith(legato: l);
    _resetDigits();
  }

  /// Transponieren: Bünde der markierten Schläge (ohne Markierung: des
  /// Schlags unter dem Cursor) um [semitones] Halbtöne verschieben. Geht ein
  /// Ton unter Bund 0 bzw. über [maxFret], wandert er auf die tiefere bzw.
  /// höhere Nachbarsaite (Standardstimmung), wenn sie in diesem Schlag frei
  /// ist; sonst bleibt der ganze Schlag, wie er ist. Ghost Notes bleiben.
  /// Gibt die Zahl der Schläge zurück, die nicht passten.
  int transpose(int semitones) {
    if (semitones == 0) return 0;
    final sel = selection ?? (beat, beat);
    var failed = 0;
    for (var i = sel.$1; i <= sel.$2 && i < beats.length; i++) {
      final b = beats[i];
      if (b.bar || b.frets.isEmpty) continue;
      final moved = transposeBeat(b, semitones);
      if (moved == null) {
        failed++;
      } else {
        beats[i] = moved;
      }
    }
    _resetDigits();
    return failed;
  }

  /// z. B. über einen Zeilenumbruch) auf dieser Saite ein/aus.
  void toggleTieIn() {
    final b = current;
    if (b == null || b.bar || !b.frets.containsKey(string)) return;
    final ins = {...b.tieIns};
    ins.contains(string) ? ins.remove(string) : ins.add(string);
    beats[beat] = b.copyWith(tieIns: ins);
    _resetDigits();
  }

  /// Triole für den Schlag unter dem Cursor ein/aus.
  void toggleTriplet() {
    final b = _ensureBeat();
    beats[beat] = b.copyWith(triplet: !b.triplet);
    _resetDigits();
  }

  /// Staccato bzw. Akzent für den Schlag unter dem Cursor ein/aus.
  void toggleStaccato() {
    final b = current;
    if (b == null || b.bar || b.frets.isEmpty) return;
    beats[beat] = b.copyWith(staccato: !b.staccato);
    _resetDigits();
  }

  /// Palm Mute ein/aus: für alle markierten Schläge (mit Bundzahl) bzw. den
  /// Schlag unter dem Cursor. Sind alle schon gedämpft, wird es entfernt.
  void togglePalmMute() {
    final sel = selection;
    final range = sel ?? (beat, beat);
    final idx = [
      for (var i = range.$1; i <= range.$2 && i < beats.length; i++)
        if (!beats[i].bar && beats[i].frets.isNotEmpty) i,
    ];
    if (idx.isEmpty) return;
    final on = !idx.every((i) => beats[i].palmMute);
    for (final i in idx) {
      beats[i] = beats[i].copyWith(palmMute: on);
    }
    _resetDigits();
  }

  void toggleAccent() {
    final b = current;
    if (b == null || b.bar || b.frets.isEmpty) return;
    beats[beat] = b.copyWith(accent: !b.accent);
    _resetDigits();
  }

  /// Ganzen Schlag (oder Taktstrich) unter dem Cursor entfernen.
  void deleteBeat() {
    if (beat >= beats.length) {
      if (beats.isEmpty) return;
      beat = beats.length - 1;
    }
    beats.removeAt(beat);
    beat = beat.clamp(0, beats.length);
    _resetDigits();
  }

  /// Takt, in dem der Cursor steht.
  ({int start, int end, double length}) get _currentMeasure {
    final all = measuresOf(beats);
    for (final m in all) {
      if (beat >= m.start && beat <= m.end) return m;
    }
    return all.last;
  }

  /// Taktstrich mit einer anderen Art (Lage bleibt).
  TabBeat _withKind(TabBeat bar, BarKind kind) => bar.barWith(kind: kind);

  /// Wiederholung Anfang vor dem Takt mit dem Cursor ein/aus.
  void repeatStart() {
    final cur = _currentMeasure;
    final i = cur.start - 1;
    if (i >= 0 && beats[i].bar) {
      final k = beats[i].kind;
      beats[i] = _withKind(beats[i], switch (k) {
        BarKind.repeatStart => BarKind.normal,
        BarKind.repeatBoth => BarKind.repeatEnd,
        BarKind.repeatEnd => BarKind.repeatBoth,
        _ => BarKind.repeatStart,
      });
    } else {
      // Erster Takt: das Zeichen steht ganz am Anfang.
      beats.insert(cur.start, const TabBeat.bar(kind: BarKind.repeatStart));
      if (beat >= cur.start) beat++;
    }
    _resetDigits();
  }

  /// Wiederholung Ende nach dem Takt mit dem Cursor ein/aus.
  void repeatEnd() => _setEnd(BarKind.repeatEnd);

  /// Schlussstrich nach dem Takt mit dem Cursor ein/aus.
  void finalBar() => _setEnd(BarKind.last);

  /// Doppelter Taktstrich nach dem Takt mit dem Cursor ein/aus.
  void doubleBar() => _setEnd(BarKind.doubleLine);

  void _setEnd(BarKind want) {
    final cur = _currentMeasure;
    // Steht der Cursor im leeren Platz hinter dem letzten Taktstrich, gilt
    // dieser Taktstrich (der Takt davor endet dort).
    final idx = cur.end < beats.length ? cur.end : (cur.start == cur.end && cur.start > 0 ? cur.start - 1 : null);
    if (idx != null) {
      final k = beats[idx].kind;
      final BarKind next;
      if (want == BarKind.repeatEnd) {
        next = switch (k) {
          BarKind.repeatEnd => BarKind.normal,
          BarKind.repeatBoth => BarKind.repeatStart,
          BarKind.repeatStart => BarKind.repeatBoth,
          _ => BarKind.repeatEnd,
        };
      } else {
        next = k == want ? BarKind.normal : want;
      }
      beats[idx] = _withKind(beats[idx], next);
    } else {
      // Letzter Takt: Taktstrich hinten anfügen.
      beats.add(TabBeat.bar(kind: want));
    }
    _resetDigits();
  }

  /// Leeren Takt (Pausen) vor dem Takt mit dem Cursor einfügen. Alles danach
  /// rückt als Ganzes nach hinten.
  void insertMeasure() {
    final m = measureLengths(beats, measure)[measureIndex] ?? 1.0;
    final rests = restsFor(m);
    final cur = _currentMeasure;
    if (beat >= beats.length) {
      // Am Ende (hinter dem letzten Eintrag): neuer Takt hinten anfügen.
      if (beats.isNotEmpty && !beats.last.bar) beats.add(const TabBeat.bar());
      beat = beats.length;
      beats.addAll(rests);
    } else {
      beats.insertAll(cur.start, [...rests, const TabBeat.bar()]);
      beat = cur.start;
    }
    _resetDigits();
  }

  /// Ganzen Takt mit dem Cursor löschen (samt seinem Taktstrich).
  void deleteMeasure() {
    if (beats.isEmpty) return;
    final cur = _currentMeasure;
    var from = cur.start, to = cur.end; // to = Taktstrich danach (falls es ihn gibt)
    if (to < beats.length) {
      to++; // Taktstrich danach mitnehmen
    } else if (from > 0) {
      from--; // letzter Takt: Taktstrich davor mitnehmen
    }
    // Ein Taktwechsel am mitgelöschten Taktstrich danach gilt weiter.
    final keep = to > cur.end && beats[cur.end].bar ? beats[cur.end].meter : null;
    beats.removeRange(from, to);
    if (keep != null && from > 0 && from <= beats.length && beats[from - 1].bar) {
      beats[from - 1] = beats[from - 1].barWith(meter: keep);
    }
    beat = from.clamp(0, beats.length);
    _normalizeMeters();
    _resetDigits();
  }

  /// Nummer des Takts mit dem Cursor (in [measuresOf]).
  int get measureIndex {
    final all = measuresOf(beats);
    for (final (k, m) in all.indexed) {
      if (beat >= m.start && beat <= m.end) return k;
    }
    return all.length - 1;
  }

  /// Taktart, die im Takt mit dem Cursor gilt.
  String? get currentMeter => meterOfMeasure(beats, meter, measureIndex);

  /// Taktart nur für den Takt mit dem Cursor ändern (eingeschobener 2/4-Takt
  /// …). Die Takte danach behalten ihre Taktart; geschrieben wird am Ende in
  /// der neuen weiter. Im ersten Takt ändert sich [meter] der Tabulatur.
  /// Nichts wird verschoben: Passt der Inhalt nicht, zeigt die Prüfung es an.
  void setMeasureMeter(String m) {
    if (meterLength(m) == null) return;
    final k = measureIndex;
    final all = measuresOf(beats);
    final cur = all[k];
    final old = meterOfMeasure(beats, meter, k);
    if (old == m) return;
    // Der Takt danach (falls es ihn gibt) bleibt, wie er war.
    if (cur.end < beats.length && beats[cur.end].bar && beats[cur.end].meter == null && k + 1 < all.length) {
      beats[cur.end] = beats[cur.end].barWith(meter: old);
    }
    if (k == 0 || cur.start == 0 || !beats[cur.start - 1].bar) {
      meter = m;
      measure = meterLength(m);
    } else {
      beats[cur.start - 1] = beats[cur.start - 1].barWith(meter: m);
    }
    _normalizeMeters();
    _resetDigits();
  }

  /// Taktwechsel ohne Wirkung (gleich wie davor) entfernen.
  void _normalizeMeters() {
    var cur = meter;
    for (var i = 0; i < beats.length; i++) {
      final b = beats[i];
      if (!b.bar || b.meter == null) continue;
      if (b.meter == cur) {
        beats[i] = b.barWith(meter: null);
      } else {
        cur = b.meter;
      }
    }
  }

  /// Leeren Schlag vor dem Cursor einfügen.
  void insertBeat() {
    final at = beat.clamp(0, beats.length);
    beats.insert(at, _fresh());
    beat = at;
    _resetDigits();
  }

  /// Nach links/rechts (ein Platz hinter dem letzten Eintrag ist erlaubt).
  void move(int by) {
    anchor = null;
    stringAnchor = null;
    beat = (beat + by).clamp(0, beats.length);
    _resetDigits();
  }

  /// Nach oben/unten (andere Saite).
  void moveString(int by) {
    anchor = null;
    stringAnchor = null;
    string = (string + by).clamp(0, TabBlock.strings - 1);
    _resetDigits();
  }
}
