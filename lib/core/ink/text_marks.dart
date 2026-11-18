/// Formatierung eines Teils einer Text-Notiz (z. B. ein Wort fett,
/// eines rot …). Was hier nicht gesetzt ist (null), kommt vom Stil der
/// ganzen Notiz.
class CharStyle {
  const CharStyle({this.bold, this.italic, this.underline, this.color, this.strike, this.highlight, this.link});

  final bool? bold;
  final bool? italic;
  final bool? underline;
  final int? color;

  /// Durchgestrichen (Texte im Unterricht).
  final bool? strike;

  /// Hintergrundfarbe zum Hervorheben (ARGB).
  final int? highlight;

  /// Verweis (Internetadresse).
  final String? link;

  static const plain = CharStyle();

  bool get isPlain =>
      bold == null &&
      italic == null &&
      underline == null &&
      color == null &&
      strike == null &&
      highlight == null &&
      link == null;

  CharStyle copyWith({
    Object? bold = _keep,
    Object? italic = _keep,
    Object? underline = _keep,
    Object? color = _keep,
    Object? strike = _keep,
    Object? highlight = _keep,
    Object? link = _keep,
  }) => CharStyle(
    bold: identical(bold, _keep) ? this.bold : bold as bool?,
    italic: identical(italic, _keep) ? this.italic : italic as bool?,
    underline: identical(underline, _keep) ? this.underline : underline as bool?,
    color: identical(color, _keep) ? this.color : color as int?,
    strike: identical(strike, _keep) ? this.strike : strike as bool?,
    highlight: identical(highlight, _keep) ? this.highlight : highlight as int?,
    link: identical(link, _keep) ? this.link : link as String?,
  );

  static const _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is CharStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.color == color &&
      other.strike == strike &&
      other.highlight == highlight &&
      other.link == link;

  @override
  int get hashCode => Object.hash(bold, italic, underline, color, strike, highlight, link);
}

/// Ein formatierter Bereich [start, end) einer Notiz.
class TextMark {
  const TextMark(this.start, this.end, this.style);
  final int start, end;
  final CharStyle style;

  Map<String, dynamic> toJson() => {
    's': start,
    'e': end,
    if (style.bold != null) 'b': style.bold,
    if (style.italic != null) 'i': style.italic,
    if (style.underline != null) 'u': style.underline,
    if (style.color != null) 'c': style.color,
    if (style.strike != null) 'x': style.strike,
    if (style.highlight != null) 'h': style.highlight,
    if (style.link != null) 'l': style.link,
  };

  static List<Map<String, dynamic>> listToJson(List<TextMark> marks) => [for (final m in marks) m.toJson()];

  static List<TextMark> listFromJson(Object? j) => [
    if (j is List)
      for (final x in j) ?TextMark.fromJson(x),
  ];

  static TextMark? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['s'], e = j['e'];
    if (s is! int || e is! int || e <= s || s < 0) return null;
    return TextMark(
      s,
      e,
      CharStyle(
        bold: j['b'] as bool?,
        italic: j['i'] as bool?,
        underline: j['u'] as bool?,
        color: j['c'] as int?,
        strike: j['x'] as bool?,
        highlight: j['h'] as int?,
        link: j['l'] as String?,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextMark && other.start == start && other.end == end && other.style == style;

  @override
  int get hashCode => Object.hash(start, end, style);
}

/// Formatierung Zeichen für Zeichen (für den Editor) …
List<CharStyle> charsFromMarks(List<TextMark> marks, int length) {
  final out = List<CharStyle>.filled(length, CharStyle.plain);
  for (final m in marks) {
    for (var i = m.start.clamp(0, length); i < m.end.clamp(0, length); i++) {
      out[i] = m.style;
    }
  }
  return out;
}

/// … und zurück in Bereiche (gleiche Nachbarn werden zusammengelegt).
List<TextMark> marksFromChars(List<CharStyle> chars) {
  final out = <TextMark>[];
  var i = 0;
  while (i < chars.length) {
    final st = chars[i];
    var j = i + 1;
    while (j < chars.length && chars[j] == st) {
      j++;
    }
    if (!st.isPlain) out.add(TextMark(i, j, st));
    i = j;
  }
  return out;
}

/// Bereiche, die zu einem Text der Länge [length] passen (z. B. nach dem
/// Abschneiden von Leerzeichen am Ende).
List<TextMark> clampMarks(List<TextMark> marks, int length) => [
  for (final m in marks)
    if (m.start < length) TextMark(m.start, m.end.clamp(0, length), m.style),
];

/// Formatierung nach einer Textänderung von [before] zu [after] anpassen:
/// Neu Getipptes übernimmt die Formatierung des Zeichens davor.
///
/// Mit [insertStyle] bekommt neu Getipptes diese Formatierung (z. B. nachdem
/// ohne Markierung „Fett“ gewählt wurde).
List<CharStyle> adjustChars(List<CharStyle> chars, String before, String after, {CharStyle? insertStyle}) {
  if (chars.length != before.length) chars = List<CharStyle>.filled(before.length, CharStyle.plain);
  var p = 0;
  final minLen = before.length < after.length ? before.length : after.length;
  while (p < minLen && before.codeUnitAt(p) == after.codeUnitAt(p)) {
    p++;
  }
  var s = 0;
  while (s < minLen - p && before.codeUnitAt(before.length - 1 - s) == after.codeUnitAt(after.length - 1 - s)) {
    s++;
  }
  final inserted = after.length - s - p;
  final inherit =
      insertStyle ??
      (p > 0 ? chars[p - 1] : (before.length - s < chars.length ? chars[before.length - s] : CharStyle.plain));
  return [...chars.sublist(0, p), for (var i = 0; i < inserted; i++) inherit, ...chars.sublist(before.length - s)];
}
