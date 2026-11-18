import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../app/l10n.dart';
import '../../app/open_url.dart';
import '../../core/ink/text_marks.dart';
import '../../core/teaching/student.dart';
import '../library/library_controller.dart';
import '../viewer/page_export.dart';
import 'rich_editor.dart' show listLevel, plainTextWithLinks, whatsAppText;

/// Datum kurz, z. B. „17.11.2026“.
String shortDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Vornamen für die Anrede („Anna“, „Anna und Ben“, „Anna, Ben und Lea“).
String greetingNames(List<String> names) {
  final first = [for (final n in names) n.trim().split(' ').first];
  if (first.length <= 1) return first.isEmpty ? '' : first.first;
  return '${first.sublist(0, first.length - 1).join(', ')} ${tr('und', 'and')} ${first.last}';
}

/// Text der Hausaufgaben zum Verschicken. Bei einer Gruppe ([members])
/// werden alle Mitglieder angesprochen. Für WhatsApp ([whatsApp]) mit
/// *fett*, _kursiv_ und ~durchgestrichen~, sonst ohne Formatierung.
String homeworkText(Student s, Lesson l, {List<Student> members = const [], bool whatsApp = false}) {
  final group = members.length > 1;
  final names = greetingNames(members.isEmpty ? [s.name] : [for (final m in members) m.name]);
  final text = l.homework.trimRight();
  final body = (whatsApp ? whatsAppText(text, l.homeworkMarks) : plainTextWithLinks(text, l.homeworkMarks)).trim();
  return tr(
    'Hoi $names\n\nHier ${group ? 'eure' : 'deine'} Hausaufgaben vom ${shortDate(l.date)}:\n\n$body\n\nViel Spass beim Üben!',
    'Hi $names\n\nHere is your homework from ${shortDate(l.date)}:\n\n$body\n\nHappy practising!',
  );
}

/// E-Mail-Adressen: die der Kartei bzw. aller Gruppenmitglieder.
List<String> homeworkEmails(Student s, {List<Student> members = const []}) => [
  for (final x in members.isEmpty ? [s] : members)
    if (x.email.trim().isNotEmpty) x.email.trim(),
];

/// Neue E-Mail mit den Hausaufgaben im Mailprogramm öffnen (bei einer
/// Gruppe an alle Mitglieder).
Future<void> sendHomeworkByEmail(Student s, Lesson l, {List<Student> members = const []}) => openUrl(
  Uri(
    scheme: 'mailto',
    path: homeworkEmails(s, members: members).join(','),
    // Uri kodiert Leerzeichen sonst als „+“, das zeigen manche Mailprogramme so an.
    query:
        'subject=${Uri.encodeComponent(tr('Hausaufgaben vom ${shortDate(l.date)}', 'Homework from ${shortDate(l.date)}'))}'
        '&body=${Uri.encodeComponent(homeworkText(s, l, members: members))}',
  ),
);

/// WhatsApp mit den Hausaufgaben öffnen (an [phone] bzw. die gespeicherte
/// Nummer, sonst wählt man den Kontakt in WhatsApp).
Future<void> sendHomeworkByWhatsApp(Student s, Lesson l, {List<Student> members = const [], String? phone}) {
  final digits = whatsAppNumber(phone ?? s.phone);
  return openUrl(
    Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(homeworkText(s, l, members: members, whatsApp: true))}',
    ),
  );
}

/// Telefonnummer schön geschrieben: „+41 78 876 54 32“ (mit Ländervorwahl)
/// bzw. „078 876 54 32“ (ohne). Andere Nummern bleiben, wie sie sind.
String formatPhone(String phone) {
  final t = phone.trim();
  var d = t.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.startsWith('00')) d = '+${d.substring(2)}';
  String group(String n) => '${n.substring(0, 2)} ${n.substring(2, 5)} ${n.substring(5, 7)} ${n.substring(7)}';
  if (d.startsWith('+41')) {
    var n = d.substring(3);
    if (n.startsWith('0')) n = n.substring(1); // „+41 078 …“
    if (n.length == 9 && !n.contains('+')) return '+41 ${group(n)}';
  } else if (d.length == 10 && d.startsWith('0') && !d.contains('+')) {
    return '0${group(d.substring(1))}';
  }
  return t;
}

/// Telefonnummer für WhatsApp: nur Ziffern, mit Ländervorwahl.
/// Eine Schweizer Nummer ohne Vorwahl (079 …) bekommt +41.
String whatsAppNumber(String phone) {
  var d = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.startsWith('+')) return d.substring(1);
  if (d.startsWith('00')) return d.substring(2);
  if (d.startsWith('0') && d.length >= 10) return '41${d.substring(1)}';
  return d;
}

/// PDF mit den Hausaufgaben (erste Seite) und den gewählten Stücken samt
/// den Notizen für diese:n Schüler:in, dann das Teilen-Fenster von Windows
/// (WhatsApp, Mail, Outlook …).
Future<void> shareHomeworkPdf(
  BuildContext context,
  LibraryController library,
  Student s,
  Lesson l,
  List<StudentPiece> pieces,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Expanded(child: Text(tr('PDF wird erstellt …', 'Creating PDF …'))),
        ],
      ),
    ),
  );
  List<ExportPiece>? opened;
  File? file;
  try {
    opened = await openExportPieces([
      for (final piece in pieces)
        if (library.byRelativePath(piece.relativePath) case final e?)
          (path: e.path, bookmark: piece.bookmark, scope: s.scope),
    ]);
    final bytes = await buildExportPdf(opened, leading: [await _homeworkPage(s, l)]);
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'volti-hausaufgaben'));
    await dir.create(recursive: true);
    final safe = s.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    final d = l.date;
    file = File(
      p.join(
        dir.path,
        'Hausaufgaben $safe ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.pdf',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('Das PDF liess sich nicht erstellen: $e', 'The PDF could not be created: $e'))),
    );
  } finally {
    if (opened != null) await closeExportPieces(opened);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (file == null) return;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        title: tr('Hausaufgaben', 'Homework'),
        subject: tr('Hausaufgaben vom ${shortDate(l.date)}', 'Homework from ${shortDate(l.date)}'),
        text: homeworkText(s, l),
        sharePositionOrigin: origin,
      ),
    );
  } catch (e) {
    // Ohne Teilen-Fenster: Datei im Explorer zeigen, dann kann man sie hineinziehen.
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', file.path]);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(tr('Gespeichert unter ${file.path}', 'Saved at ${file.path}'))));
    }
  }
}

/// Schrift für PDFs mit Text (Roboto aus Voltis Schriften, damit auch
/// Umlaute und Sonderzeichen in Namen stimmen). null = Standardschrift.
Future<pw.ThemeData?> voltiPdfTheme() async {
  try {
    // Feste Schnitte: Variable Schriften zeigen manche PDF-Programme nicht an.
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/RobotoPdf-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/RobotoPdf-Bold.ttf'));
    final italic = pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/RobotoPdf-Italic.ttf'));
    final boldItalic = pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/RobotoPdf-BoldItalic.ttf'));
    return pw.ThemeData.withFont(base: regular, bold: bold, italic: italic, boldItalic: boldItalic);
  } catch (_) {
    return null;
  }
}

Future<pw.Page> _homeworkPage(Student s, Lesson l) async {
  final theme = await voltiPdfTheme();
  // Mehrere Seiten, falls die Hausaufgaben lang sind (eine einzelne Seite
  // bliebe sonst leer).
  return pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(56, 64, 56, 56),
    theme: theme,
    build: (_) => [
      pw.Text(tr('Hausaufgaben', 'Homework'), style: const pw.TextStyle(fontSize: 26)),
      pw.SizedBox(height: 6),
      pw.Text(
        '${s.name} · ${shortDate(l.date)}',
        style: const pw.TextStyle(fontSize: 13, color: PdfColor.fromInt(0xFF555555)),
      ),
      pw.SizedBox(height: 24),
      ...pdfRichLines(l.homework.trimRight(), l.homeworkMarks, const pw.TextStyle(fontSize: 14, lineSpacing: 4)),
    ],
  );
}

/// Formatierter Text als PDF-Zeilen (fett, kursiv, unterstrichen,
/// durchgestrichen, Farbe, Hervorheben; Aufzählungen mit Punkt).
List<pw.Widget> pdfRichLines(String text, List<TextMark> marks, pw.TextStyle base) {
  final chars = charsFromMarks(marks, text.length);
  pw.TextSpan span(String t, List<CharStyle> cs) {
    final children = <pw.InlineSpan>[];
    var i = 0;
    while (i < t.length) {
      final st = cs[i];
      var j = i + 1;
      while (j < t.length && cs[j] == st) {
        j++;
      }
      final lines = [
        if (st.underline == true || st.link != null) pw.TextDecoration.underline,
        if (st.strike == true) pw.TextDecoration.lineThrough,
      ];
      final color = st.color ?? (st.link != null ? 0xFF1A73C8 : null);
      children.add(
        pw.TextSpan(
          text: t.substring(i, j),
          style: pw.TextStyle(
            fontWeight: st.bold == true ? pw.FontWeight.bold : null,
            fontStyle: st.italic == true ? pw.FontStyle.italic : null,
            decoration: lines.isEmpty ? null : pw.TextDecoration.combine(lines),
            color: color == null ? null : PdfColor.fromInt(color),
            background: st.highlight == null ? null : pw.BoxDecoration(color: PdfColor.fromInt(st.highlight!)),
          ),
        ),
      );
      i = j;
    }
    return pw.TextSpan(style: base, children: children);
  }

  final out = <pw.Widget>[];
  final bullet = RegExp(r'^(\s*)([-•*◦▪]|\d+[.)]) ');
  var offset = 0;
  for (final raw in text.split('\n')) {
    final cs = chars.sublist(offset, offset + raw.length);
    offset += raw.length + 1;
    final m = bullet.firstMatch(raw);
    if (m == null) {
      // Leere Zeile: Abstand wie eine Textzeile.
      out.add(raw.isEmpty ? pw.Text(' ', style: base) : pw.RichText(text: span(raw, cs)));
      continue;
    }
    final marker = m.group(2)!;
    final level = listLevel(m.group(1)!.length);
    final indent = level * 20.0;
    out.add(
      pw.Padding(
        padding: pw.EdgeInsets.only(left: indent, bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 20,
              child: RegExp(r'\d').hasMatch(marker) ? pw.Text(marker, style: base) : _pdfBullet(level, base),
            ),
            pw.Expanded(child: pw.RichText(text: span(raw.substring(m.end), cs.sublist(m.end)))),
          ],
        ),
      ),
    );
  }
  return out;
}

/// Aufzählungszeichen im PDF, selbst gezeichnet (die PDF-Schrift kennt nicht
/// alle Zeichen): Punkt, Kreis, Quadrat je nach Stufe.
pw.Widget _pdfBullet(int level, pw.TextStyle base) {
  final size = (base.fontSize ?? 12) * 0.36;
  final kind = level % 3;
  return pw.Padding(
    padding: pw.EdgeInsets.only(top: (base.fontSize ?? 12) * 0.42, left: 2),
    child: pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        shape: kind == 2 ? pw.BoxShape.rectangle : pw.BoxShape.circle,
        color: kind == 1 ? null : PdfColors.black,
        border: kind == 1 ? pw.Border.all(width: 0.8) : null,
      ),
    ),
  );
}
