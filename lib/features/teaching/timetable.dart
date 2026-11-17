import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/l10n.dart';
import '../../core/teaching/student.dart';
import '../library/library_controller.dart';
import 'calendar_dialog.dart';
import 'homework_share.dart';
import 'student_dialog.dart';

/// Wochentage, an denen jemand Unterricht hat (Mo–Fr immer, Sa/So nur wenn belegt).
List<int> timetableDays(List<Student> students) => [
  for (var d = 1; d <= 7; d++)
    if (d <= 5 || students.any((s) => s.weekday == d)) d,
];

/// Schüler:innen eines Tages, nach Zeit.
List<Student> studentsOn(List<Student> students, int day) =>
    students.where((s) => s.weekday == day).toList()..sort((a, b) => a.minutes.compareTo(b.minutes));

/// Stundenplan: eine Spalte pro Wochentag. Antippen öffnet die Kartei.
class TimetableView extends StatelessWidget {
  const TimetableView({super.key, required this.library, required this.actions, required this.onOpen, this.onBack});

  final LibraryController library;
  final List<Widget> actions;
  final void Function(Student s) onOpen;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final students = library.students.where((s) => !s.archived).toList();
    final days = timetableDays(students);
    final today = DateTime.now().weekday;
    final minutes = students.where((s) => s.weekday != null).fold<int>(0, (n, s) => n + s.duration);
    final count = students.where((s) => s.weekday != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            children: [
              if (onBack != null) IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Stundenplan', 'Timetable'),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      tr(
                        '$count ${count == 1 ? 'Schüler:in' : 'Schüler:innen'} · ${_hours(minutes)} pro Woche',
                        '$count ${count == 1 ? 'student' : 'students'} · ${_hours(minutes)} per week',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => showCalendarDialog(context, library),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(tr('Ferien & Semester', 'Holidays & terms')),
              ),
              TextButton.icon(
                onPressed: () => _openPdf(context, students),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(tr('Als PDF', 'As PDF')),
              ),
              const SizedBox(width: 4),
              ...actions,
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final colWidth = (box.maxWidth - 24) / days.length;
              final narrow = colWidth < 150;
              final columns = [
                for (final d in days)
                  SizedBox(
                    width: narrow ? 180 : colWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                            child: Text(
                              weekdayName(d),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: d == today ? scheme.primary : null,
                                fontWeight: d == today ? FontWeight.w700 : null,
                              ),
                            ),
                          ),
                          for (final s in studentsOn(students, d))
                            Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 6),
                              color: d == today
                                  ? scheme.primaryContainer.withValues(alpha: 0.5)
                                  : scheme.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: scheme.outlineVariant),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => onOpen(s),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.time == null ? '–' : '${s.time}–${s.endTime}',
                                        style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                                      ),
                                      Text(s.name, style: theme.textTheme.titleSmall),
                                      if (s.instrument.isNotEmpty || s.place.isNotEmpty)
                                        Text(
                                          [s.instrument, s.place].where((x) => x.isNotEmpty).join(' · '),
                                          style: theme.textTheme.bodySmall,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ];
              final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: columns);
              return SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: narrow ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row) : row,
              );
            },
          ),
        ),
      ],
    );
  }

  static String _hours(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    if (h == 0) return tr('$m Min.', '$m min');
    if (m == 0) return tr('$h Std.', '$h h');
    return tr('$h Std. $m Min.', '$h h $m min');
  }

  /// Stundenplan als PDF (A4 quer) im Standard-Programm öffnen (dort drucken
  /// oder speichern).
  Future<void> _openPdf(BuildContext context, List<Student> students) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildTimetablePdf(students);
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'volti-stundenplan'));
      await dir.create(recursive: true);
      final path = p.join(dir.path, tr('Stundenplan.pdf', 'Timetable.pdf'));
      await File(path).writeAsBytes(bytes, flush: true);
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', path], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [path], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Das PDF liess sich nicht erstellen: $e', 'The PDF could not be created: $e'))),
      );
    }
  }
}

/// Stundenplan als PDF: eine Spalte pro Tag.
Future<List<int>> buildTimetablePdf(List<Student> students) async {
  final days = timetableDays(students);
  final doc = pw.Document(title: tr('Stundenplan', 'Timetable'), creator: 'Volti');
  final theme = await voltiPdfTheme();
  doc.addPage(
    pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(tr('Stundenplan', 'Timetable'), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final d in days)
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 3),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Text(weekdayName(d), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 6),
                        for (final s in studentsOn(students, d))
                          pw.Container(
                            margin: const pw.EdgeInsets.only(bottom: 4),
                            padding: const pw.EdgeInsets.all(5),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: PdfColor.fromInt(0xFFBBBBBB), width: 0.6),
                              borderRadius: pw.BorderRadius.circular(3),
                            ),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  s.time == null ? '–' : '${s.time}–${s.endTime}',
                                  style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF666666)),
                                ),
                                pw.Text(s.name, style: const pw.TextStyle(fontSize: 10)),
                                if (s.instrument.isNotEmpty)
                                  pw.Text(s.instrument, style: const pw.TextStyle(fontSize: 8)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
