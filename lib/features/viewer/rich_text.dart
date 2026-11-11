import 'package:flutter/widgets.dart';

import '../../core/ink/text_marks.dart';

/// Stil eines formatierten Teils: Grundstil der Notiz plus Abweichungen.
TextStyle styleWithMark(TextStyle base, CharStyle m) {
  var s = base;
  if (m.bold != null) {
    s = s.copyWith(
      fontWeight: m.bold! ? FontWeight.w700 : FontWeight.w400,
      // Die Schriften sind "variabel": die Dicke wird hier eingestellt.
      fontVariations: [FontVariation.weight(m.bold! ? 700 : 400)],
    );
  }
  if (m.italic != null) s = s.copyWith(fontStyle: m.italic! ? FontStyle.italic : FontStyle.normal);
  if (m.underline == true) s = s.copyWith(decoration: TextDecoration.underline, decorationColor: s.color);
  if (m.color != null) s = s.copyWith(color: Color(m.color!), decorationColor: Color(m.color!));
  return s;
}

/// Text mit seinen formatierten Teilen als ein TextSpan.
TextSpan richSpan(String text, List<CharStyle> chars, TextStyle base) {
  if (chars.length != text.length || chars.every((c) => c.isPlain)) return TextSpan(text: text, style: base);
  final children = <TextSpan>[];
  var i = 0;
  while (i < text.length) {
    final st = chars[i];
    var j = i + 1;
    while (j < text.length && chars[j] == st) {
      j++;
    }
    children.add(TextSpan(text: text.substring(i, j), style: st.isPlain ? null : styleWithMark(base, st)));
    i = j;
  }
  return TextSpan(style: base, children: children);
}

/// Editor-Text mit Formatierung pro Zeichen. Neu Getipptes übernimmt die
/// Formatierung des Zeichens davor.
class RichNoteController extends TextEditingController {
  List<CharStyle> _chars = const [];
  List<CharStyle> get chars => _chars;

  /// Text und Formatierung setzen (beim Öffnen einer Notiz).
  void load(String text, List<TextMark> marks) {
    _chars = charsFromMarks(marks, text.length);
    super.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  List<TextMark> get marks => marksFromChars(_chars);

  @override
  set value(TextEditingValue v) {
    final before = super.value.text;
    if (v.text != before) _chars = adjustChars(_chars, before, v.text);
    super.value = v;
  }

  /// Markierter Bereich (leer = nichts markiert).
  TextRange get _range {
    final s = selection;
    if (!s.isValid || s.isCollapsed) return TextRange.empty;
    return TextRange(start: s.start.clamp(0, text.length), end: s.end.clamp(0, text.length));
  }

  bool get hasSelection => !_range.isCollapsed && _range.isValid;

  /// Gilt [test] für alle markierten Zeichen?
  bool allSelected(bool Function(CharStyle c) test) {
    final r = _range;
    if (!r.isValid || r.isCollapsed) return false;
    for (var i = r.start; i < r.end; i++) {
      if (!test(_chars[i])) return false;
    }
    return true;
  }

  /// Formatierung der markierten Zeichen ändern.
  void apply(CharStyle Function(CharStyle c) change) {
    final r = _range;
    if (!r.isValid || r.isCollapsed) return;
    final next = [..._chars];
    for (var i = r.start; i < r.end; i++) {
      next[i] = change(next[i]);
    }
    _chars = next;
    notifyListeners();
  }

  /// Ganze Notiz: alle Abweichungen einer Art entfernen (z. B. wenn die
  /// ganze Notiz fett gestellt wird, sollen keine Teile "nicht fett" bleiben).
  void clearAll(CharStyle Function(CharStyle c) change) {
    _chars = [for (final c in _chars) change(c)];
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    // Während der Eingabe mit Wortvorschlägen (IME) die Standard-Darstellung.
    if (withComposing && value.composing.isValid && !value.composing.isCollapsed) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    return richSpan(text, _chars, style ?? const TextStyle());
  }
}

/// Was das Text-Fenster an der gerade getippten Notiz ändern kann: Ist etwas
/// markiert, gelten Fett, Kursiv, Unterstrichen und Farbe nur dafür.
class RichTextTarget {
  RichTextTarget(this.controller, {required this.baseBold, required this.baseItalic});
  final RichNoteController controller;

  /// Stil der ganzen Notiz (für „ist alles Markierte fett?“).
  final bool Function() baseBold, baseItalic;

  bool get hasSelection => controller.hasSelection;

  bool get bold => controller.allSelected((c) => c.bold ?? baseBold());
  bool get italic => controller.allSelected((c) => c.italic ?? baseItalic());
  bool get underline => controller.allSelected((c) => c.underline == true);

  void toggleBold() {
    final on = !bold;
    controller.apply((c) => c.copyWith(bold: on == baseBold() ? null : on));
  }

  void toggleItalic() {
    final on = !italic;
    controller.apply((c) => c.copyWith(italic: on == baseItalic() ? null : on));
  }

  void toggleUnderline() {
    final on = !underline;
    controller.apply((c) => c.copyWith(underline: on ? true : null));
  }

  void setColor(int color) => controller.apply((c) => c.copyWith(color: color));
}
