import 'annotation_layer.dart';

/// Notenwerte für Tabulatur-Schläge (Nenner: 1 = ganze, 4 = Viertel …).
const tabValues = [1, 2, 4, 8, 16, 32];

/// Ein Eintrag in einer Tabulatur: ein Schlag (Bundzahlen auf einzelnen
/// Saiten, mit Notenwert) oder ein Taktstrich.
class TabBeat {
  const TabBeat({this.frets = const {}, this.value = 4, this.dotted = false, this.bar = false});

  const TabBeat.bar() : frets = const {}, value = 4, dotted = false, bar = true;

  /// Saite (0 = oberste Linie, hohe E-Saite) → Bund.
  final Map<int, int> frets;

  /// Notenwert als Nenner (1, 2, 4, 8, 16, 32).
  final int value;
  final bool dotted;

  /// Taktstrich statt Schlag.
  final bool bar;

  /// Schlag ohne Bundzahl = Pause.
  bool get isRest => !bar && frets.isEmpty;

  /// Dauer in ganzen Noten (Viertel = 0,25).
  double get length => bar ? 0 : (1 / value) * (dotted ? 1.5 : 1);

  TabBeat copyWith({Map<int, int>? frets, int? value, bool? dotted}) =>
      TabBeat(frets: frets ?? this.frets, value: value ?? this.value, dotted: dotted ?? this.dotted, bar: bar);

  Map<String, dynamic> toJson() => bar
      ? {'bar': true}
      : {
          if (frets.isNotEmpty) 'f': {for (final e in frets.entries) '${e.key}': e.value},
          'v': value,
          if (dotted) 'dot': true,
        };

  static TabBeat fromJson(Map<String, dynamic> j) {
    if (j['bar'] == true) return const TabBeat.bar();
    final f = j['f'] as Map<String, dynamic>? ?? const {};
    final v = j['v'] as int? ?? 4;
    return TabBeat(
      frets: {
        for (final e in f.entries)
          if (int.tryParse(e.key) case final s? when s >= 0 && s < TabBlock.strings) s: (e.value as num).toInt(),
      },
      value: tabValues.contains(v) ? v : 4,
      dotted: j['dot'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TabBeat &&
      other.bar == bar &&
      other.value == value &&
      other.dotted == dotted &&
      other.frets.length == frets.length &&
      other.frets.entries.every((e) => frets[e.key] == e.value);

  @override
  int get hashCode =>
      Object.hash(bar, value, dotted, Object.hashAllUnordered(frets.entries.map((e) => e.key * 100 + e.value)));
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
