import 'annotation_layer.dart';

/// Notenwerte für Tabulatur-Schläge (Nenner: 1 = ganze, 4 = Viertel …).
const tabValues = [1, 2, 4, 8, 16, 32];

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
  }) : at = null;

  /// Taktstrich; [at] = von Hand gesetzte Lage (sonst automatisch).
  const TabBeat.bar({this.at})
    : frets = const {},
      value = 4,
      dotted = false,
      bar = true,
      bends = const {},
      slides = const {};

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

  /// Notenwert als Nenner (1, 2, 4, 8, 16, 32).
  final int value;
  final bool dotted;

  /// Taktstrich statt Schlag.
  final bool bar;

  /// Schlag ohne Bundzahl = Pause.
  bool get isRest => !bar && frets.isEmpty;

  /// Dauer in ganzen Noten (Viertel = 0,25).
  double get length => bar ? 0 : (1 / value) * (dotted ? 1.5 : 1);

  TabBeat copyWith({Map<int, int>? frets, int? value, bool? dotted, Map<int, int>? bends, Set<int>? slides}) {
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
    );
  }

  Map<String, dynamic> toJson() => bar
      ? {'bar': true, if (at != null) 'at': at}
      : {
          if (frets.isNotEmpty) 'f': {for (final e in frets.entries) '${e.key}': e.value},
          'v': value,
          if (dotted) 'dot': true,
          if (bends.isNotEmpty) 'bend': {for (final e in bends.entries) '${e.key}': e.value},
          if (slides.isNotEmpty) 'slide': (slides.toList()..sort()),
        };

  static TabBeat fromJson(Map<String, dynamic> j) {
    if (j['bar'] == true) {
      final at = (j['at'] as num?)?.toDouble();
      return TabBeat.bar(at: at?.clamp(0.0, 1.0));
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
    );
  }

  static bool _sameMap(Map<int, int> a, Map<int, int> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  bool operator ==(Object other) =>
      other is TabBeat &&
      other.bar == bar &&
      other.at == at &&
      other.value == value &&
      other.dotted == dotted &&
      _sameMap(other.frets, frets) &&
      _sameMap(other.bends, bends) &&
      other.slides.length == slides.length &&
      other.slides.containsAll(slides);

  @override
  int get hashCode => Object.hash(
    bar,
    at,
    value,
    dotted,
    Object.hashAllUnordered(frets.entries.map((e) => e.key * 100 + e.value)),
    Object.hashAllUnordered(bends.entries.map((e) => e.key * 100 + e.value)),
    Object.hashAllUnordered(slides),
  );
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
  );

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
  );
}

/// Schreiben in einer Tabulatur: Cursor (Schlag und Saite) und alle
/// Änderungen. Rein rechnerisch, ohne Anzeige – die Notenansicht wendet das
/// Ergebnis ([beats]) auf die gespeicherte Tabulatur an.
///
/// Der Cursor darf einen Platz hinter dem letzten Eintrag stehen: Dort
/// Getipptes legt einen neuen Schlag an.
class TabEditor {
  TabEditor(List<TabBeat> beats, {this.beat = 0, this.string = 0}) : beats = [...beats];

  List<TabBeat> beats;

  /// Position des Cursors (0 … beats.length).
  int beat;

  /// Saite unter dem Cursor (0 = oberste Linie).
  int string;

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
      if (!beats[i].bar) return TabBeat(value: beats[i].value);
    }
    return const TabBeat();
  }

  /// Am Ende steht der Cursor auf einem neuen, leeren Platz – gibt es den
  /// Schlag noch nicht, wird er jetzt angelegt.
  TabBeat _ensureBeat() {
    if (beat >= beats.length) {
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

  /// Leeren Schlag vor dem Cursor einfügen.
  void insertBeat() {
    final at = beat.clamp(0, beats.length);
    beats.insert(at, _fresh());
    beat = at;
    _resetDigits();
  }

  /// Nach links/rechts (ein Platz hinter dem letzten Eintrag ist erlaubt).
  void move(int by) {
    beat = (beat + by).clamp(0, beats.length);
    _resetDigits();
  }

  /// Nach oben/unten (andere Saite).
  void moveString(int by) {
    string = (string + by).clamp(0, TabBlock.strings - 1);
    _resetDigits();
  }
}
