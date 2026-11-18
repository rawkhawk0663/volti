import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:volti/core/ink/text_marks.dart';
import 'package:volti/core/teaching/student.dart';
import 'package:volti/features/teaching/homework_share.dart';
import 'package:volti/features/teaching/rich_editor.dart';

TextEditingValue _v(String text, int caret) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Formatierung bleibt in Lektion und Notiz gespeichert', () {
    const bold = CharStyle(bold: true);
    const link = CharStyle(link: 'https://volti.ch');
    const mixed = CharStyle(strike: true, highlight: 0xFFFFF176, color: 0xFFD32F2F);
    final l = Lesson.create(DateTime(2026, 11, 18))
      ..content = 'Tonleiter G-Dur'
      ..contentMarks = [const TextMark(0, 9, bold)]
      ..homework = 'Video ansehen'
      ..homeworkMarks = [const TextMark(0, 5, link), const TextMark(6, 13, mixed)];
    final back = Lesson.tryFromJson(l.toJson())!;
    expect(back.contentMarks, [const TextMark(0, 9, bold)]);
    expect(back.homeworkMarks, [const TextMark(0, 5, link), const TextMark(6, 13, mixed)]);
    final n = StudentNote.create(text: 'Eltern')..marks = [const TextMark(0, 6, CharStyle(italic: true))];
    expect(StudentNote.tryFromJson(n.toJson())!.marks.single.style.italic, isTrue);
    // Alte Einträge ohne Formatierung bleiben gültig.
    final old = Lesson.tryFromJson({
      'id': 'x',
      'date': '2026-11-01',
      'status': 'held',
      'content': 'alt',
      'created': '2026-11-01T10:00:00Z',
      'modified': '2026-11-01T10:00:00Z',
    })!;
    expect(old.contentMarks, isEmpty);
  });

  test('Ohne Markierung gilt „Fett“ für das nächste Getippte', () {
    final c = RichEditController(text: 'Hallo ');
    c.toggleBold();
    expect(c.bold, isTrue);
    c.value = _v('Hallo Welt', 10);
    expect(c.marksFor(c.text), [const TextMark(6, 10, CharStyle(bold: true))]);
    // Markieren und Farbe setzen.
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    c.setColor(0xFFD32F2F);
    expect(c.chars[0].color, 0xFFD32F2F);
    expect(c.chars[7].color, isNull);
    c.clearFormatting();
    expect(c.chars[0].isPlain, isTrue);
    c.dispose();
  });

  test('Rückgängig stellt mit dem Text auch die Formatierung wieder her', () {
    final c = RichEditController(text: 'Takt 5');
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    c.toggleBold();
    c.value = _v('', 0); // alles gelöscht
    c.value = _v('Takt 5', 6); // so stellt „Rückgängig“ den Text zurück
    expect(c.chars.every((s) => s.bold == true), isTrue);
    c.dispose();
  });

  test('Listen: Enter setzt fort, leerer Punkt beendet', () {
    final f = ListContinuation();
    var r = f.formatEditUpdate(_v('• Tonleiter', 11), _v('• Tonleiter\n', 12));
    expect(r.text, '• Tonleiter\n• ');
    r = f.formatEditUpdate(_v('1. Etüde', 8), _v('1. Etüde\n', 9));
    expect(r.text, '1. Etüde\n2. ');
    r = f.formatEditUpdate(_v('• A\n• ', 6), _v('• A\n• \n', 7));
    expect(r.text, '• A\n');
    r = f.formatEditUpdate(_v('Normal', 6), _v('Normal\n', 7));
    expect(r.text, 'Normal\n');
  });

  test('Aufzählung und Nummerierung ein- und ausschalten', () {
    final c = RichEditController(text: 'Tonleiter\nEtüde\nLied');
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 20);
    c.toggleList(numbered: false);
    expect(c.text, '• Tonleiter\n• Etüde\n• Lied');
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    c.toggleList(numbered: true);
    expect(c.text, '1. Tonleiter\n2. Etüde\n3. Lied');
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    c.toggleList(numbered: true);
    expect(c.text, 'Tonleiter\nEtüde\nLied');
    // Nur die Zeile mit der Schreibmarke.
    c.selection = const TextSelection.collapsed(offset: 12);
    c.toggleList(numbered: false);
    expect(c.text, 'Tonleiter\n• Etüde\nLied');
    c.dispose();
  });

  test('Senden: WhatsApp mit *fett*, E-Mail mit Link-Adresse', () {
    const text = 'Übe G-Dur und schau das Video';
    final marks = [
      const TextMark(4, 9, CharStyle(bold: true)),
      const TextMark(24, 29, CharStyle(link: 'https://example.com/v')),
    ];
    expect(whatsAppText(text, marks), 'Übe *G-Dur* und schau das Video (https://example.com/v)');
    expect(plainTextWithLinks(text, marks), 'Übe G-Dur und schau das Video (https://example.com/v)');
    expect(whatsAppText('fett ', [const TextMark(0, 5, CharStyle(bold: true))]), '*fett* ');
    final s = Student.create('Anna Muster');
    final l = Lesson.create(DateTime(2026, 11, 18))
      ..homework = text
      ..homeworkMarks = marks;
    expect(homeworkText(s, l, whatsApp: true), contains('*G-Dur*'));
    expect(homeworkText(s, l), isNot(contains('*')));
  });

  test('Formatierte Hausaufgaben als PDF-Zeilen', () async {
    final lines = pdfRichLines('• Tonleiter\n\n1. Etüde', [
      const TextMark(2, 11, CharStyle(bold: true, highlight: 0xFFFFF176)),
    ], const pw.TextStyle());
    expect(lines.length, 3);
    final doc = pw.Document(theme: await voltiPdfTheme());
    doc.addPage(pw.MultiPage(build: (_) => lines));
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
