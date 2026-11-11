import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/text_marks.dart';
import 'package:volti/core/ink/text_note.dart';
import 'package:volti/features/viewer/rich_text.dart';

void main() {
  test('Ein Wort fett machen, weitertippen übernimmt die Formatierung davor', () {
    final c = RichNoteController()..load('Bogen ab dolce', const []);
    final t = RichTextTarget(c, baseBold: () => false, baseItalic: () => false);
    c.selection = const TextSelection(baseOffset: 6, extentOffset: 8); // "ab"
    expect(t.bold, isFalse);
    t.toggleBold();
    expect(t.bold, isTrue);
    expect(c.marks, [const TextMark(6, 8, CharStyle(bold: true))]);

    // Hinter "ab" tippen: wird ebenfalls fett.
    c.value = const TextEditingValue(text: 'Bogen abc dolce', selection: TextSelection.collapsed(offset: 9));
    expect(c.marks, [const TextMark(6, 9, CharStyle(bold: true))]);
    // Davor tippen: nicht fett.
    c.value = const TextEditingValue(text: 'XBogen abc dolce', selection: TextSelection.collapsed(offset: 1));
    expect(c.marks, [const TextMark(7, 10, CharStyle(bold: true))]);
    // Löschen im fetten Teil.
    c.value = const TextEditingValue(text: 'XBogen ac dolce', selection: TextSelection.collapsed(offset: 8));
    expect(c.marks, [const TextMark(7, 9, CharStyle(bold: true))]);

    // Nochmals fett auf denselben Teil: wieder normal.
    c.selection = const TextSelection(baseOffset: 7, extentOffset: 9);
    t.toggleBold();
    expect(c.marks, isEmpty);
  });

  test('Ist die ganze Notiz fett, macht „fett“ auf einem Teil diesen normal', () {
    final c = RichNoteController()..load('forte piano', const []);
    final t = RichTextTarget(c, baseBold: () => true, baseItalic: () => false);
    c.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    expect(t.bold, isTrue);
    t.toggleBold();
    expect(c.marks, [const TextMark(6, 11, CharStyle(bold: false))]);
    t.setColor(0xFFC62828);
    t.toggleUnderline();
    expect(c.marks.single.style, const CharStyle(bold: false, color: 0xFFC62828, underline: true));
  });

  test('Formatierung wird gespeichert und wieder gelesen; alte Notizen bleiben gültig', () {
    final n = TextNote(
      id: 'n',
      page: 1,
      x: 0.1,
      y: 0.1,
      text: 'Atmen!',
      size: 0.02,
      color: 0xFF000000,
      createdAt: DateTime.utc(2026),
      marks: const [TextMark(0, 5, CharStyle(bold: true, italic: true))],
    );
    final back = TextNote.fromJson(n.toJson());
    expect(back.marks, n.marks);
    final old = Map<String, dynamic>.of(n.toJson())..remove('marks');
    expect(TextNote.fromJson(old).marks, isEmpty);
    // Bereiche, die über den Text hinausgehen, werden gekürzt.
    expect(clampMarks(const [TextMark(2, 9, CharStyle(bold: true))], 4), [const TextMark(2, 4, CharStyle(bold: true))]);
  });

  test('Darstellung: formatierte Teile als eigene Abschnitte', () {
    const base = TextStyle(fontSize: 12, color: Color(0xFF000000));
    final span = richSpan('ab cd', charsFromMarks(const [TextMark(3, 5, CharStyle(bold: true))], 5), base);
    expect(span.children!.length, 2);
    final second = span.children![1] as TextSpan;
    expect(second.text, 'cd');
    expect(second.style!.fontWeight, FontWeight.w700);
  });
}
