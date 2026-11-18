import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/open_url.dart';
import '../../core/ink/text_marks.dart';
import '../viewer/rich_text.dart';

// ---------------------------------------------------------------- Listen

/// Aufzählungszeichen am Zeilenanfang („- “, „• “, „* “), mit Einrückung.
final _bulletLine = RegExp(r'^(\s*)([-•*]) ');

/// Nummer am Zeilenanfang („1. “, „2) “), mit Einrückung.
final _numberLine = RegExp(r'^(\s*)(\d+)[.)] ');

/// Neue Zeile in einer Liste: das nächste Aufzählungszeichen bzw. die nächste
/// Nummer kommt von selbst. Enter in einem leeren Listenpunkt beendet die Liste.
class ListContinuation extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final sel = oldValue.selection;
    if (!sel.isValid || !sel.isCollapsed) return newValue;
    final at = sel.start;
    if (newValue.text.length != oldValue.text.length + 1 ||
        at >= newValue.text.length ||
        newValue.text[at] != '\n' ||
        newValue.text.substring(0, at) != oldValue.text.substring(0, at)) {
      return newValue;
    }
    final lineStart = at <= 0 ? 0 : oldValue.text.lastIndexOf('\n', at - 1) + 1;
    final line = oldValue.text.substring(lineStart, at);
    String? prefix;
    int? prefixLength;
    final b = _bulletLine.firstMatch(line);
    final n = _numberLine.firstMatch(line);
    if (b != null) {
      prefix = '${b.group(1)}${b.group(2)} ';
      prefixLength = b.end;
    } else if (n != null) {
      prefix = '${n.group(1)}${int.parse(n.group(2)!) + 1}. ';
      prefixLength = n.end;
    }
    if (prefix == null) return newValue;
    // Leerer Listenpunkt: Aufzählung beenden (Zeichen entfernen, keine neue Zeile).
    if (line.substring(prefixLength!).trim().isEmpty) {
      final text = oldValue.text.replaceRange(lineStart, at, '');
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }
    final text = newValue.text.replaceRange(at + 1, at + 1, prefix);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: at + 1 + prefix.length),
    );
  }
}

// -------------------------------------------------------------- Editor

/// Text mit Formatierung pro Zeichen für Lektion, Hausaufgaben und Notizen.
/// Neu Getipptes übernimmt die Formatierung des Zeichens davor, ausser es
/// wurde ohne Markierung etwas gewählt (z. B. „Fett“), dann gilt das.
class RichEditController extends TextEditingController {
  RichEditController({String text = '', List<TextMark> marks = const []}) {
    load(text, marks);
  }

  List<CharStyle> _chars = const [];
  List<CharStyle> get chars => _chars;

  /// Formatierung für das nächste Getippte (ohne Markierung gewählt).
  CharStyle? _typing;

  /// Rückgängig und Wiederholen.
  final undo = UndoHistoryController();

  /// Zählt bei jedem [load] hoch: Das Textfeld wird dann neu aufgebaut,
  /// damit „Rückgängig“ nicht in den vorigen Text zurückspringt.
  int generation = 0;

  /// Formatierung früherer Fassungen des Textes. „Rückgängig“ stellt nur
  /// den Text wieder her, die Formatierung kommt von hier.
  final _seen = <String, List<CharStyle>>{};

  /// Text und Formatierung setzen (neue Lektion, Lektion bearbeiten).
  void load(String text, List<TextMark> marks) {
    _chars = charsFromMarks(marks, text.length);
    _typing = null;
    _seen.clear();
    generation++;
    super.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _remember();
  }

  /// Formatierung als Bereiche, passend zum Text ohne Leerzeichen am Ende.
  List<TextMark> marksFor(String trimmed) => clampMarks(marksFromChars(_chars), trimmed.length);

  @override
  set value(TextEditingValue v) {
    final before = super.value.text;
    if (v.text != before) {
      final known = _seen[v.text];
      if (known != null && known.length == v.text.length) {
        _chars = [...known];
      } else {
        _chars = adjustChars(_chars, before, v.text, insertStyle: _typing);
        if (v.text.length > before.length) _typing = null;
      }
    } else if (v.selection != super.value.selection) {
      _typing = null;
    }
    super.value = v;
    if (v.text != before) _remember();
  }

  void _remember() {
    _seen.remove(text);
    _seen[text] = _chars;
    while (_seen.length > 300) {
      _seen.remove(_seen.keys.first);
    }
  }

  TextRange get _range {
    final s = selection;
    if (!s.isValid || s.isCollapsed) return TextRange.empty;
    return TextRange(start: s.start.clamp(0, text.length), end: s.end.clamp(0, text.length));
  }

  bool get hasSelection => _range.isValid && !_range.isCollapsed;

  /// Formatierung an der Schreibmarke (ohne Markierung).
  CharStyle get _caretStyle {
    if (_typing != null) return _typing!;
    final at = selection.isValid ? selection.start.clamp(0, text.length) : text.length;
    return at > 0 && at <= _chars.length ? _chars[at - 1] : CharStyle.plain;
  }

  /// Gilt [test] für alles Markierte bzw. an der Schreibmarke?
  bool has(bool Function(CharStyle c) test) {
    final r = _range;
    if (!r.isValid || r.isCollapsed) return test(_caretStyle);
    for (var i = r.start; i < r.end; i++) {
      if (!test(_chars[i])) return false;
    }
    return true;
  }

  /// Markiertes ändern; ohne Markierung gilt es für das nächste Getippte.
  void apply(CharStyle Function(CharStyle c) change) {
    final r = _range;
    if (!r.isValid || r.isCollapsed) {
      _typing = change(_caretStyle);
    } else {
      final next = [..._chars];
      for (var i = r.start; i < r.end; i++) {
        next[i] = change(next[i]);
      }
      _chars = next;
      _remember();
    }
    notifyListeners();
  }

  bool get bold => has((c) => c.bold == true);
  bool get italic => has((c) => c.italic == true);
  bool get underline => has((c) => c.underline == true);
  bool get strike => has((c) => c.strike == true);

  void toggleBold() {
    final on = !bold;
    apply((c) => c.copyWith(bold: on ? true : null));
  }

  void toggleItalic() {
    final on = !italic;
    apply((c) => c.copyWith(italic: on ? true : null));
  }

  void toggleUnderline() {
    final on = !underline;
    apply((c) => c.copyWith(underline: on ? true : null));
  }

  void toggleStrike() {
    final on = !strike;
    apply((c) => c.copyWith(strike: on ? true : null));
  }

  void setColor(int? color) => apply((c) => c.copyWith(color: color));
  void setHighlight(int? color) => apply((c) => c.copyWith(highlight: color));

  /// Formatierung entfernen (Links bleiben).
  void clearFormatting() => apply((c) => CharStyle(link: c.link));

  /// Link des Markierten bzw. an der Schreibmarke.
  String? get link {
    final r = _range;
    if (r.isValid && !r.isCollapsed) return _chars[r.start].link;
    return _caretStyle.link;
  }

  /// Link auf das Markierte setzen (null = entfernen). Ohne Markierung wird
  /// [label] (oder die Adresse) eingefügt und verlinkt.
  void setLink(String? url, {String? label}) {
    if (hasSelection) {
      apply((c) => c.copyWith(link: url));
      return;
    }
    if (url == null) return;
    final at = selection.isValid ? selection.start.clamp(0, text.length) : text.length;
    final insert = (label == null || label.trim().isEmpty) ? url : label.trim();
    _typing = _caretStyle.copyWith(link: url);
    value = TextEditingValue(
      text: text.replaceRange(at, at, insert),
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
    // Nach dem Link wieder ohne Link weiterschreiben.
    _typing = _caretStyle.copyWith(link: null);
    notifyListeners();
  }

  /// Text an der Schreibmarke einfügen (z. B. ein Emoji).
  void insert(String s) {
    final sel = selection;
    final start = sel.isValid ? sel.start.clamp(0, text.length) : text.length;
    final end = sel.isValid ? sel.end.clamp(0, text.length) : text.length;
    value = TextEditingValue(
      text: text.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
    );
  }

  // ------------------------------------------------------------ Listen
  /// Zeilen der Markierung bzw. der Zeile mit der Schreibmarke: Anfänge.
  List<int> _selectedLineStarts() {
    final t = text;
    final sel = selection.isValid ? selection : TextSelection.collapsed(offset: t.length);
    final from = sel.start <= 0 ? 0 : t.lastIndexOf('\n', (sel.start - 1).clamp(0, t.length)) + 1;
    final to = sel.end.clamp(0, t.length);
    final starts = <int>[from];
    for (var i = from; i < to; i++) {
      if (t[i] == '\n' && i + 1 <= to) starts.add(i + 1);
    }
    if (starts.length > 1 && starts.last == to && !sel.isCollapsed) starts.removeLast();
    return starts;
  }

  /// Aufzählung (•) bzw. Nummerierung (1. 2. …) für die gewählten Zeilen
  /// ein- oder ausschalten.
  void toggleList({required bool numbered}) {
    final starts = _selectedLineStarts();
    String lineAt(int start) {
      final end = text.indexOf('\n', start);
      return text.substring(start, end < 0 ? text.length : end);
    }

    final pattern = numbered ? _numberLine : _bulletLine;
    final remove = starts.every((s) => pattern.hasMatch(lineAt(s)));
    final blockEnd = starts.last + lineAt(starts.last).length;
    // Von hinten nach vorne, damit die Anfänge davor gültig bleiben.
    // Jede Zeile ist eine eigene Änderung, so bleibt die Formatierung richtig.
    var shift = 0;
    for (var i = starts.length - 1; i >= 0; i--) {
      final start = starts[i];
      final line = lineAt(start);
      final other = (numbered ? _bulletLine : _numberLine).firstMatch(line);
      final own = pattern.firstMatch(line);
      var cut = 0;
      var add = '';
      if (remove) {
        cut = own!.end - own.group(1)!.length;
      } else {
        if (own != null) cut = own.end - own.group(1)!.length;
        if (other != null) cut = other.end - other.group(1)!.length;
        add = numbered ? '${i + 1}. ' : '• ';
      }
      final indent = (own ?? other)?.group(1)?.length ?? 0;
      final at = start + indent;
      value = value.copyWith(
        text: text.replaceRange(at, at + cut, add),
        selection: TextSelection.collapsed(offset: at),
      );
      shift += add.length - cut;
    }
    // Schreibmarke ans Ende der letzten Zeile.
    value = value.copyWith(selection: TextSelection.collapsed(offset: (blockEnd + shift).clamp(0, text.length)));
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (withComposing && value.composing.isValid && !value.composing.isCollapsed) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    return richSpan(text, _chars, style ?? const TextStyle());
  }

  @override
  void dispose() {
    undo.dispose();
    super.dispose();
  }
}

/// Textfeld mit Formatierung. Strg+B/I/U/K, Listen gehen von selbst weiter.
class RichEditorField extends StatelessWidget {
  const RichEditorField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hint,
    this.minLines = 7,
    this.maxLines = 16,
    this.autofocus = false,
    this.onLink,
  });

  final RichEditController controller;
  final FocusNode? focusNode;
  final String? hint;
  final int minLines;
  final int? maxLines;
  final bool autofocus;

  /// Strg+K: Link setzen (öffnet das Fenster der Werkzeugleiste).
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): controller.toggleBold,
      const SingleActivator(LogicalKeyboardKey.keyI, control: true): controller.toggleItalic,
      const SingleActivator(LogicalKeyboardKey.keyU, control: true): controller.toggleUnderline,
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): ?onLink,
    },
    child: TextField(
      key: ValueKey(controller.generation),
      controller: controller,
      undoController: controller.undo,
      focusNode: focusNode,
      autofocus: autofocus,
      minLines: minLines,
      maxLines: maxLines,
      inputFormatters: [ListContinuation()],
      decoration: InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.all(12),
      ),
    ),
  );
}

// -------------------------------------------------------- Werkzeugleiste

/// Farben für Text und Hervorheben.
const textColors = [0xFFD32F2F, 0xFFEF6C00, 0xFF2E7D32, 0xFF1A8070, 0xFF1565C0, 0xFF6A1B9A, 0xFF757575];
const highlightColors = [0xFFFFF176, 0xFFFFCC80, 0xFFC5E1A5, 0xFFB3E5FC, 0xFFF8BBD0, 0xFFE0E0E0];

/// Emojis für den Unterricht.
const teachingEmojis = [
  '😊', '😀', '😎', '🤩', '🥳', '😅', '🤔', '😴', //
  '👍', '👏', '💪', '🙌', '👀', '✌️', '🙏', '❤️', //
  '⭐', '🌟', '✨', '🔥', '🎉', '🏆', '🥇', '✅', //
  '❗', '❓', '⚠️', '⏰', '📅', '📝', '📌', '💡', //
  '🎵', '🎶', '🎸', '🎹', '🎻', '🥁', '🎺', '🎤', //
];

/// Werkzeugleiste für das gerade aktive Textfeld ([target]). Sie steht in
/// einer [TextFieldTapRegion], damit das Textfeld beim Antippen aktiv bleibt.
class RichToolbar extends StatelessWidget {
  const RichToolbar({super.key, required this.target});

  final ValueListenable<RichEditController?> target;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RichEditController?>(
    valueListenable: target,
    builder: (context, c, _) => c == null
        ? _bar(context, null)
        : ListenableBuilder(listenable: Listenable.merge([c, c.undo]), builder: (context, _) => _bar(context, c)),
  );

  Widget _bar(BuildContext context, RichEditController? c) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String tip, VoidCallback? onTap, {bool active = false, Color? color}) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      isSelected: active,
      style: IconButton.styleFrom(backgroundColor: active ? scheme.primaryContainer : null, foregroundColor: color),
      onPressed: c == null ? null : onTap,
      icon: Icon(icon),
    );
    Widget gap() => Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: scheme.outlineVariant,
    );
    final undo = c?.undo.value;
    return TextFieldTapRegion(
      child: ExcludeFocus(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            button(Icons.format_bold, tr('Fett (Strg+B)', 'Bold (Ctrl+B)'), c?.toggleBold, active: c?.bold ?? false),
            button(
              Icons.format_italic,
              tr('Kursiv (Strg+I)', 'Italic (Ctrl+I)'),
              c?.toggleItalic,
              active: c?.italic ?? false,
            ),
            button(
              Icons.format_underlined,
              tr('Unterstrichen (Strg+U)', 'Underline (Ctrl+U)'),
              c?.toggleUnderline,
              active: c?.underline ?? false,
            ),
            button(
              Icons.format_strikethrough,
              tr('Durchgestrichen', 'Strikethrough'),
              c?.toggleStrike,
              active: c?.strike ?? false,
            ),
            gap(),
            button(
              Icons.link,
              tr('Link (Strg+K)', 'Link (Ctrl+K)'),
              c == null ? null : () => editLink(context, c),
              active: c?.link != null,
            ),
            Builder(
              builder: (anchor) => button(
                Icons.emoji_emotions_outlined,
                tr('Emoji', 'Emoji'),
                c == null ? null : () => _emoji(anchor, c),
              ),
            ),
            gap(),
            Builder(
              builder: (anchor) => button(
                Icons.format_color_text,
                tr('Textfarbe', 'Text colour'),
                c == null ? null : () => _colour(anchor, c, highlight: false),
                color: c == null ? null : _current(c, (s) => s.color),
              ),
            ),
            Builder(
              builder: (anchor) => button(
                Icons.border_color_outlined,
                tr('Hervorheben', 'Highlight'),
                c == null ? null : () => _colour(anchor, c, highlight: true),
              ),
            ),
            gap(),
            button(
              Icons.format_list_bulleted,
              tr('Aufzählung', 'Bullet list'),
              c == null ? null : () => c.toggleList(numbered: false),
            ),
            button(
              Icons.format_list_numbered,
              tr('Nummerierte Liste', 'Numbered list'),
              c == null ? null : () => c.toggleList(numbered: true),
            ),
            button(Icons.format_clear, tr('Formatierung entfernen', 'Clear formatting'), c?.clearFormatting),
            gap(),
            button(Icons.undo, tr('Rückgängig (Strg+Z)', 'Undo (Ctrl+Z)'), undo?.canUndo == true ? c!.undo.undo : null),
            button(
              Icons.redo,
              tr('Wiederholen (Strg+Y)', 'Redo (Ctrl+Y)'),
              undo?.canRedo == true ? c!.undo.redo : null,
            ),
          ],
        ),
      ),
    );
  }

  static Color? _current(RichEditController c, int? Function(CharStyle s) of) {
    int? found;
    final all = c.has((s) {
      found ??= of(s);
      return of(s) != null && of(s) == found;
    });
    return all && found != null ? Color(found!) : null;
  }

  static RelativeRect _below(BuildContext anchor) {
    final box = anchor.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(0, box.size.height));
    return RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1);
  }

  Future<void> _colour(BuildContext anchor, RichEditController c, {required bool highlight}) async {
    final colours = highlight ? highlightColors : textColors;
    final picked = await showMenu<int>(
      context: anchor,
      position: _below(anchor),
      items: [
        PopupMenuItem<int>(
          enabled: false,
          padding: const EdgeInsets.all(8),
          child: Builder(
            builder: (menu) => Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // „Ohne“: zurück zur normalen Farbe bzw. kein Hervorheben.
                _Swatch(color: null, onTap: () => Navigator.of(menu).pop(0)),
                for (final col in colours) _Swatch(color: Color(col), onTap: () => Navigator.of(menu).pop(col)),
              ],
            ),
          ),
        ),
      ],
    );
    if (picked == null) return;
    final value = picked == 0 ? null : picked;
    highlight ? c.setHighlight(value) : c.setColor(value);
  }

  Future<void> _emoji(BuildContext anchor, RichEditController c) async {
    final picked = await showMenu<String>(
      context: anchor,
      position: _below(anchor),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: const EdgeInsets.all(6),
          child: Builder(
            builder: (menu) => SizedBox(
              width: 8 * 38,
              child: Wrap(
                children: [
                  for (final e in teachingEmojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => Navigator.of(menu).pop(e),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (picked != null) c.insert(picked);
  }
}

/// Link setzen oder entfernen (Fenster mit Adresse und, ohne Markierung, Text).
Future<void> editLink(BuildContext context, RichEditController c) async {
  final selected = c.hasSelection;
  final url = TextEditingController(text: c.link ?? '');
  final label = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(tr('Link', 'Link')),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ohne Markierung zuerst der Text, dann die Adresse.
            if (!selected)
              TextField(
                controller: label,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: tr('Text', 'Text')),
              ),
            TextField(
              controller: url,
              autofocus: selected,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: tr('Adresse', 'Address'), hintText: 'https://…'),
              onSubmitted: (v) => Navigator.of(d).pop(v),
            ),
          ],
        ),
      ),
      actions: [
        if (c.link != null)
          TextButton(onPressed: () => Navigator.of(d).pop(''), child: Text(tr('Link entfernen', 'Remove link'))),
        TextButton(onPressed: () => Navigator.of(d).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.of(d).pop(url.text), child: Text(tr('OK', 'OK'))),
      ],
    ),
  );
  final text = label.text;
  url.dispose();
  label.dispose();
  if (result == null) return;
  var address = result.trim();
  if (address.isEmpty) {
    c.setLink(null);
    return;
  }
  if (!address.contains('://') && !address.startsWith('mailto:')) address = 'https://$address';
  c.setLink(address, label: text);
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.onTap});
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outline),
        ),
        child: color == null ? Icon(Icons.block, size: 16, color: scheme.onSurfaceVariant) : null,
      ),
    );
  }
}

// ------------------------------------------------------------ Anzeige

/// Gespeicherter Text mit Formatierung: Aufzählungen mit Punkt bzw. Nummer
/// und Einzug, Links antippbar.
class RichTextView extends StatefulWidget {
  const RichTextView({super.key, required this.text, this.marks = const [], this.style, this.empty = '—'});
  final String text;
  final List<TextMark> marks;
  final TextStyle? style;

  /// Anzeige, wenn der Text leer ist.
  final String empty;

  @override
  State<RichTextView> createState() => _RichTextViewState();
}

class _RichTextViewState extends State<RichTextView> {
  final _taps = <TapGestureRecognizer>[];

  void _clearTaps() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clearTaps();
    super.dispose();
  }

  TextSpan _span(String text, List<CharStyle> chars, TextStyle base) {
    final children = <InlineSpan>[];
    var i = 0;
    while (i < text.length) {
      final st = chars[i];
      var j = i + 1;
      while (j < text.length && chars[j] == st) {
        j++;
      }
      TapGestureRecognizer? tap;
      if (st.link != null) {
        final uri = Uri.tryParse(st.link!);
        if (uri != null) {
          tap = TapGestureRecognizer()..onTap = () => openUrl(uri);
          _taps.add(tap);
        }
      }
      children.add(
        TextSpan(
          text: text.substring(i, j),
          style: st.isPlain ? null : styleWithMark(base, st),
          recognizer: tap,
          mouseCursor: tap == null ? null : SystemMouseCursors.click,
        ),
      );
      i = j;
    }
    return TextSpan(style: base, children: children);
  }

  @override
  Widget build(BuildContext context) {
    _clearTaps();
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final text = widget.text.trimRight();
    if (text.trim().isEmpty) return Text(widget.empty, style: base);
    final chars = charsFromMarks(widget.marks, text.length);
    final lines = <Widget>[];
    var offset = 0;
    for (final raw in text.split('\n')) {
      final start = offset;
      offset += raw.length + 1;
      final lineChars = chars.sublist(start, start + raw.length);
      final b = _bulletLine.firstMatch(raw);
      final n = _numberLine.firstMatch(raw);
      final m = b ?? n;
      if (m == null) {
        lines.add(Text.rich(_span(raw, lineChars, base)));
        continue;
      }
      final indent = m.group(1)!.length;
      final marker = b != null ? (indent >= 2 ? '◦' : '•') : '${n!.group(2)}.';
      lines.add(
        Padding(
          padding: EdgeInsets.only(left: indent >= 2 ? 18 : 0, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: b != null ? 16 : 22,
                child: Text(marker, style: base),
              ),
              Expanded(child: Text.rich(_span(raw.substring(m.end), lineChars.sublist(m.end), base))),
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
  }
}

// ------------------------------------------------------------ Senden

/// Text für WhatsApp: *fett*, _kursiv_, ~durchgestrichen~; Links als Adresse
/// in Klammern dahinter.
String whatsAppText(String text, List<TextMark> marks) {
  final chars = charsFromMarks(marks, text.length);
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final st = chars[i];
    var j = i + 1;
    while (j < text.length && chars[j] == st && text[j] != '\n') {
      j++;
    }
    final part = text.substring(i, j);
    // Zeichen nur um Wörter, nicht um Leerzeichen am Rand.
    final lead = part.length - part.trimLeft().length;
    final core = part.trim();
    var wrapped = core;
    if (core.isNotEmpty) {
      if (st.strike == true) wrapped = '~$wrapped~';
      if (st.italic == true) wrapped = '_${wrapped}_';
      if (st.bold == true) wrapped = '*$wrapped*';
      if (st.link != null && st.link != core) wrapped = '$wrapped (${st.link})';
    }
    out
      ..write(part.substring(0, lead))
      ..write(wrapped)
      ..write(part.substring(lead + core.length));
    i = j;
  }
  return out.toString();
}

/// Text für E-Mails: unverändert, Links als Adresse in Klammern dahinter.
String plainTextWithLinks(String text, List<TextMark> marks) {
  if (marks.every((m) => m.style.link == null)) return text;
  final chars = charsFromMarks(marks, text.length);
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    out.write(text[i]);
    final link = chars[i].link;
    final endsHere = link != null && (i + 1 >= text.length || chars[i + 1].link != link);
    if (endsHere && link != text.substring(_linkStart(chars, i), i + 1)) out.write(' ($link)');
  }
  return out.toString();
}

int _linkStart(List<CharStyle> chars, int end) {
  var s = end;
  while (s > 0 && chars[s - 1].link == chars[end].link) {
    s--;
  }
  return s;
}
