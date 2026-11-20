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

/// Ein Eintrag in einer Tabulatur: ein Schlag (Bundzahlen auf einzelnen
/// Saiten, mit Notenwert) oder ein Taktstrich.
class TabBeat {
  const TabBeat({
    this.frets = const {},
    this.value = 4,
    this.dotted = false,
    this.bar = false,
    this.bends = const {},
    this.slides = const {},
    this.ties = const {},
    this.staccato = false,
    this.accent = false,
    this.triplet = false,
  }) : at = null,
       kind = BarKind.normal;

  /// Taktstrich; [at] = von Hand gesetzte Lage (sonst automatisch).
  const TabBeat.bar({this.at, this.kind = BarKind.normal})
    : frets = const {},
      value = 4,
      dotted = false,
      bar = true,
      bends = const {},
      slides = const {},
      ties = const {},
      staccato = false,
      accent = false,
      triplet = false;

  /// Art des Taktstrichs (Wiederholung, Schlussstrich …).
  final BarKind kind;

  /// Von Hand verschobener Taktstrich: Lage im Schreibbereich der Tabulatur
  /// (0 = gleich nach „TAB“, 1 = rechtes Ende). null = automatisch. Die
  /// Schläge davor und danach verteilen sich dann auf den Platz dazwischen.
  final double? at;

  /// Saite (0 = oberste Linie, hohe E-Saite) → Bund.
  final Map<int, int> frets;

  /// Bendings: Saite → Stufe in Vierteltönen ([tabBends]).
  final Map<int, int> bends;

  /// Slides: Saiten, deren Ton zur nächsten Bundzahl auf derselben Saite
  /// rutscht (gibt es keine, ein kurzer Slide nach unten).
  final Set<int> slides;

  /// Haltebögen: Saiten, deren Ton zur nächsten Bundzahl auf derselben Saite
  /// gehalten wird (die gehaltene steht in Klammern).
  final Set<int> ties;

  /// Staccato (Punkt über dem Schlag) und Akzent („>“).
  final bool staccato, accent;

  /// Teil einer Triole (drei im Raum von zwei): dauert ⅔ so lange.
  final bool triplet;

  /// Notenwert als Nenner (1, 2, 4, 8, 16, 32).
  final int value;
  final bool dotted;

  /// Taktstrich statt Schlag.
  final bool bar;

  /// Schlag ohne Bundzahl = Pause.
  bool get isRest => !bar && frets.isEmpty;

  /// Dauer in ganzen Noten (Viertel = 0,25).
  double get length => bar ? 0 : nominal * (triplet ? 2 / 3 : 1);

  /// Dauer ohne Triole (wie geschrieben).
  double get nominal => bar ? 0 : (1 / value) * (dotted ? 1.5 : 1);

  TabBeat copyWith({
    Map<int, int>? frets,
    int? value,
    bool? dotted,
    Map<int, int>? bends,
    Set<int>? slides,
    Set<int>? ties,
    bool? staccato,
    bool? accent,
    bool? triplet,
  }) {
    final f = frets ?? this.frets;
    // Bendings und Slides nur dort, wo es eine Bundzahl gibt.
    return TabBeat(
      frets: f,
      value: value ?? this.value,
      dotted: dotted ?? this.dotted,
      bar: bar,
      bends: {
        for (final e in (bends ?? this.bends).entries)
          if (f.containsKey(e.key)) e.key: e.value,
      },
      slides: {
        for (final st in slides ?? this.slides)
          if (f.containsKey(st)) st,
      },
      ties: {
        for (final st in ties ?? this.ties)
          if (f.containsKey(st)) st,
      },
      // Ohne Bundzahl (Pause) keine Artikulation.
      staccato: f.isNotEmpty && (staccato ?? this.staccato),
      accent: f.isNotEmpty && (accent ?? this.accent),
      triplet: triplet ?? this.triplet,
    );
  }

  Map<String, dynamic> toJson() => bar
      ? {'bar': true, if (at != null) 'at': at, if (kind != BarKind.normal) 'k': kind.name}
      : {
          if (frets.isNotEmpty) 'f': {for (final e in frets.entries) '${e.key}': e.value},
          'v': value,
          if (dotted) 'dot': true,
          if (bends.isNotEmpty) 'bend': {for (final e in bends.entries) '${e.key}': e.value},
          if (slides.isNotEmpty) 'slide': (slides.toList()..sort()),
          if (ties.isNotEmpty) 'tie': (ties.toList()..sort()),
          if (staccato) 'stacc': true,
          if (accent) 'acc': true,
          if (triplet) 'tri': true,
        };

  static TabBeat fromJson(Map<String, dynamic> j) {
    if (j['bar'] == true) {
      final at = (j['at'] as num?)?.toDouble();
      return TabBeat.bar(at: at?.clamp(0.0, 1.0), kind: BarKind.fromName(j['k'] as String?));
    }
    final f = j['f'] as Map<String, dynamic>? ?? const {};
    final v = j['v'] as int? ?? 4;
    Map<int, int> strings(Map<String, dynamic> m) => {
      for (final e in m.entries)
        if (int.tryParse(e.key) case final s? when s >= 0 && s < TabBlock.strings) s: (e.value as num).toInt(),
    };
    final frets = strings(f);
    return TabBeat(
      frets: frets,
      value: tabValues.contains(v) ? v : 4,
      dotted: j['dot'] == true,
      bends: {
        for (final e in strings(j['bend'] as Map<String, dynamic>? ?? const {}).entries)
          if (frets.containsKey(e.key) && tabBends.contains(e.value)) e.key: e.value,
      },
      slides: {
        for (final st in j['slide'] as List<dynamic>? ?? const [])
          if (st is int && frets.containsKey(st)) st,
      },
      ties: {
        for (final st in j['tie'] as List<dynamic>? ?? const [])
          if (st is int && frets.containsKey(st)) st,
      },
      staccato: frets.isNotEmpty && j['stacc'] == true,
      accent: frets.isNotEmpty && j['acc'] == true,
      triplet: j['tri'] == true,
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
      other.value == value &&
      other.dotted == dotted &&
      _sameMap(other.frets, frets) &&
      _sameMap(other.bends, bends) &&
      other.slides.length == slides.length &&
      other.slides.containsAll(slides) &&
      other.ties.length == ties.length &&
      other.ties.containsAll(ties) &&
      other.staccato == staccato &&
      other.accent == accent &&
      other.triplet == triplet;

  @override
  int get hashCode => Object.hash(
    bar,
    at,
    kind,
    value,
    dotted,
    Object.hashAllUnordered(frets.entries.map((e) => e.key * 100 + e.value)),
    Object.hashAllUnordered(bends.entries.map((e) => e.key * 100 + e.value)),
    Object.hashAllUnordered(slides),
    Object.hashAllUnordered(ties),
    staccato,
    accent,
    triplet,
  );
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
List<TabBeat> rebar(List<TabBeat> beats, double measure) {
  final notes = [
    for (final b in beats)
      if (!b.bar) b,
  ];
  final out = <TabBeat>[];
  var acc = 0.0;
  for (var i = 0; i < notes.length; i++) {
    out.add(notes[i]);
    acc += notes[i].length;
    if (acc >= measure - 1e-9 && i < notes.length - 1) {
      out.add(const TabBeat.bar());
      acc = 0;
    }
  }
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

/// Schreiben in einer Tabulatur: Cursor (Schlag und Saite) und alle
/// Änderungen. Rein rechnerisch, ohne Anzeige – die Notenansicht wendet das
/// Ergebnis ([beats]) auf die gespeicherte Tabulatur an.
///
/// Der Cursor darf einen Platz hinter dem letzten Eintrag stehen: Dort
/// Getipptes legt einen neuen Schlag an.
class TabEditor {
  TabEditor(List<TabBeat> beats, {this.beat = 0, this.string = 0, this.measure}) : beats = [...beats];

  /// Länge eines Takts (aus der Taktart); null = frei.
  double? measure;

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
    if (_partialStrings) {
      // Nur Noten markiert: nichts ersetzen, vor dem markierten Bereich einfügen.
      beat = selection?.$1 ?? beat;
      anchor = null;
      stringAnchor = null;
    } else {
      deleteSelection();
    }
    final at = beat.clamp(0, beats.length);
    beats.insertAll(at, clip);
    beat = at + clip.length;
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
      final m = measure;
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

  void _resetDigits() => _lastDigit = null;

  /// Ziffer tippen. Kommt rasch eine zweite (z. B. 1 dann 2), entsteht 12.
  void digit(int d, {DateTime? now}) {
    final t = now ?? DateTime.now();
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

  void toggleDot() {
    final b = _ensureBeat();
    beats[beat] = b.copyWith(dotted: !b.dotted);
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

  /// Bending auf der Saite unter dem Cursor: setzen bzw. (gleiche Stufe
  /// nochmals) entfernen. Nur wo eine Bundzahl steht.
  void bend(int quarters) {
    final b = current;
    if (b == null || b.bar || !b.frets.containsKey(string) || !tabBends.contains(quarters)) return;
    final bends = {...b.bends};
    bends[string] == quarters ? bends.remove(string) : bends[string] = quarters;
    beats[beat] = b.copyWith(bends: bends);
    _resetDigits();
  }

  /// Nächste Bending-Stufe (¼ → ½ → 1 → 1½ → keine).
  void cycleBend() {
    final b = current;
    if (b == null || b.bar || !b.frets.containsKey(string)) return;
    final now = b.bends[string];
    final i = now == null ? 0 : tabBends.indexOf(now) + 1;
    final bends = {...b.bends};
    i >= tabBends.length ? bends.remove(string) : bends[string] = tabBends[i];
    beats[beat] = b.copyWith(bends: bends);
    _resetDigits();
  }

  /// Slide zur nächsten Bundzahl auf dieser Saite: ein/aus.
  void toggleSlide() {
    final b = current;
    if (b == null || b.bar || !b.frets.containsKey(string)) return;
    final slides = {...b.slides};
    slides.contains(string) ? slides.remove(string) : slides.add(string);
    beats[beat] = b.copyWith(slides: slides);
    _resetDigits();
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
  TabBeat _withKind(TabBeat bar, BarKind kind) => TabBeat.bar(at: bar.at, kind: kind);

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
    final m = measure ?? 1.0;
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
    beats.removeRange(from, to);
    beat = from.clamp(0, beats.length);
    _resetDigits();
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
