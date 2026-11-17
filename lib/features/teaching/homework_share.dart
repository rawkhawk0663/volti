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
import '../../core/teaching/student.dart';
import '../library/library_controller.dart';
import '../viewer/page_export.dart';

/// Datum kurz, z. B. „17.11.2026“.
String shortDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Vornamen für die Anrede („Anna“, „Anna und Ben“, „Anna, Ben und Lea“).
String greetingNames(List<String> names) {
  final first = [for (final n in names) n.trim().split(' ').first];
  if (first.length <= 1) return first.isEmpty ? '' : first.first;
  return '${first.sublist(0, first.length - 1).join(', ')} ${tr('und', 'and')} ${first.last}';
}

/// Text der Hausaufgaben zum Verschicken. Bei einer Gruppe ([members])
/// werden alle Mitglieder angesprochen.
String homeworkText(Student s, Lesson l, {List<Student> members = const []}) {
  final group = members.length > 1;
  final names = greetingNames(members.isEmpty ? [s.name] : [for (final m in members) m.name]);
  return tr(
    'Hoi $names\n\nHier ${group ? 'eure' : 'deine'} Hausaufgaben vom ${shortDate(l.date)}:\n\n${l.homework.trim()}\n\nViel Spass beim Üben!',
    'Hi $names\n\nHere is your homework from ${shortDate(l.date)}:\n\n${l.homework.trim()}\n\nHappy practising!',
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
  return openUrl(Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(homeworkText(s, l, members: members))}'));
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
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto.ttf'));
    return pw.ThemeData.withFont(base: font, bold: font);
  } catch (_) {
    return null;
  }
}

Future<pw.Page> _homeworkPage(Student s, Lesson l) async {
  final theme = await voltiPdfTheme();
  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(56, 64, 56, 56),
    theme: theme,
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(tr('Hausaufgaben', 'Homework'), style: const pw.TextStyle(fontSize: 26)),
        pw.SizedBox(height: 6),
        pw.Text(
          '${s.name} · ${shortDate(l.date)}',
          style: const pw.TextStyle(fontSize: 13, color: PdfColor.fromInt(0xFF555555)),
        ),
        pw.SizedBox(height: 24),
        pw.Text(l.homework.trim(), style: const pw.TextStyle(fontSize: 14, lineSpacing: 4)),
      ],
    ),
  );
}
