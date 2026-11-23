import 'dart:io';
import 'dart:math';

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
import 'teaching_view.dart';

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
    // Gruppen zählen einmal, ihre Mitglieder nicht noch einmal einzeln.
    final students = library.students.where((s) => !s.archived && library.groupOf(s.id) == null).toList();
    final days = timetableDays(students);
    final today = DateTime.now().weekday;
    final minutes = students.where((s) => s.weekday != null).fold<int>(0, (n, s) => n + s.duration);
    // Jedes Kind einzeln (auch in Gruppen), dazu die Zahl der Gruppen.
    final people = library.students.where((s) {
      if (s.archived || s.isGroup) return false;
      return (s.weekday ?? library.groupOf(s.id)?.weekday) != null;
    }).length;
    final groups = students.where((s) => s.isGroup && s.weekday != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TeachingTopBar(
          large: true,
          leading: onBack == null ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
          title: tr('Stundenplan', 'Timetable'),
          subtitle: tr(
            '$people ${people == 1 ? 'Schüler:in' : 'Schüler:innen'} mit festem Unterrichtstag'
                '${groups == 0 ? '' : ' · $groups ${groups == 1 ? 'Gruppe' : 'Gruppen'}'}',
            '$people ${people == 1 ? 'student' : 'students'} with a fixed lesson day'
                '${groups == 0 ? '' : ' · $groups ${groups == 1 ? 'group' : 'groups'}'}',
          ),
          buttons: [
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
          ],
          trailing: actions,
        ),
        // Schullektionen und Pensum (Angaben unter ⚙ → Unterricht). Auf dem
        // Handy kurz nebeneinander, sonst stünden die Kästchen untereinander.
        if (MediaQuery.sizeOf(context).width < 600)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: _Stat(compact: true, label: tr('Pro Woche', 'Per week'), value: _hours(minutes)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Stat(
                    compact: true,
                    label: tr('Lektionen', 'Lessons'),
                    value: _num(library.calendar.schoolLessons(minutes)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Stat(
                    compact: true,
                    label: tr('Pensum', 'Workload'),
                    value: '${_num(library.calendar.loadPercent(minutes))} %',
                    highlight: true,
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Stat(label: tr('Unterricht pro Woche', 'Teaching per week'), value: _hours(minutes)),
                _Stat(
                  label: tr(
                    'Schullektionen (à ${library.calendar.lessonMinutes} Min.)',
                    'School lessons (${library.calendar.lessonMinutes} min each)',
                  ),
                  value: _num(library.calendar.schoolLessons(minutes)),
                ),
                _Stat(
                  label: tr(
                    'Pensum (100 % = ${library.calendar.fullLoad} Lektionen)',
                    'Workload (100 % = ${library.calendar.fullLoad} lessons)',
                  ),
                  value: '${_num(library.calendar.loadPercent(minutes))} %',
                  highlight: true,
                ),
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

  /// Zahl mit einer Stelle nach dem Komma (deutsch mit Komma), ganze Zahlen ohne.
  static String _num(double v) {
    final r = (v * 10).round() / 10;
    final text = r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
    return L10n.isEnglish ? text : text.replaceAll('.', ',');
  }

  static String _hours(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    if (h == 0) return tr('$m Min.', '$m min');
    if (m == 0) return tr('$h Std.', '$h h');
    return tr('$h Std. $m Min.', '$h h $m min');
  }

  /// Stundenplan als PDF (A4 quer) im Standard-Programm öffnen (dort drucken
  /// oder speichern).
  Future<void> _openPdf(BuildContext context, List<Student> students) =>
      openPdfBytes(context, () => buildTimetablePdf(students), tr('Stundenplan.pdf', 'Timetable.pdf'));
}

/// Ein selbst erzeugtes PDF im Standard-Programm öffnen (dort drucken oder
/// speichern). Fehler erscheinen als Hinweis.
Future<void> openPdfBytes(BuildContext context, Future<List<int>> Function() build, String fileName) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await build();
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'volti-pdf'));
    await dir.create(recursive: true);
    final path = p.join(dir.path, fileName);
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

/// Stundenplan als PDF (A4 quer): eine Spalte pro Tag mit einem Zeitraster.
/// Die Stunden werden so eng gesetzt, dass immer alles auf eine Seite passt.
Future<List<int>> buildTimetablePdf(List<Student> students) async {
  final days = timetableDays(students);
  final timed = students.where((s) => s.weekday != null && s.time != null).toList();
  final untimed = students.where((s) => s.weekday != null && s.time == null).toList()
    ..sort((a, b) => a.weekday!.compareTo(b.weekday!));
  final doc = pw.Document(title: tr('Stundenplan', 'Timetable'), creator: 'Volti');
  final theme = await voltiPdfTheme();
  // Ganze Stunden vom frühesten Beginn bis zum spätesten Ende.
  var first = 8 * 60, last = 12 * 60;
  if (timed.isNotEmpty) {
    first = timed.map((s) => s.minutes).reduce(min) ~/ 60 * 60;
    last = ((timed.map((s) => s.minutes + s.duration).reduce(max) + 59) ~/ 60) * 60;
  }
  const grey = PdfColor.fromInt(0xFF666666);
  const line = PdfColor.fromInt(0xFFDDDDDD);
  const accent = PdfColor.fromInt(0xFF7A3CF0);
  const axis = 34.0, headHeight = 18.0;
  String hhmm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  doc.addPage(
    pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      build: (context) {
        // Seite ohne den Rand von 28 Punkten ringsum.
        final page = context.page.pageFormat;
        final width = page.width - 56;
        final footer = untimed.isEmpty ? 0.0 : 22.0;
        final gridHeight = page.height - 56 - 34 - headHeight - footer - 4;
        final perMinute = gridHeight / (last - first);
        final column = (width - axis) / days.length;
        double y(int minute) => (minute - first) * perMinute;

        pw.Widget block(Student s) {
          final h = s.duration * perMinute;
          return pw.Positioned(
            left: 2,
            right: 2,
            top: y(s.minutes),
            child: pw.Container(
              height: h - 1,
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF0EAFE),
                border: const pw.Border(left: pw.BorderSide(color: accent, width: 2)),
              ),
              child: pw.ClipRect(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      h >= 17 ? '${s.time}–${s.endTime}  ${s.name}' : s.name,
                      style: pw.TextStyle(fontSize: h >= 12 ? 7.5 : 6, fontWeight: pw.FontWeight.bold),
                      maxLines: 1,
                    ),
                    if (h >= 22 && s.instrument.isNotEmpty)
                      pw.Text(s.instrument, style: const pw.TextStyle(fontSize: 6.5, color: grey), maxLines: 1),
                  ],
                ),
              ),
            ),
          );
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              height: 34,
              child: pw.Text(
                tr('Stundenplan', 'Timetable'),
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Row(
              children: [
                pw.SizedBox(width: axis),
                for (final d in days)
                  pw.SizedBox(
                    width: column,
                    height: headHeight,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 3),
                      child: pw.Text(weekdayName(d), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            pw.SizedBox(
              height: gridHeight,
              child: pw.Stack(
                overflow: pw.Overflow.visible,
                children: [
                  // Stundenlinien mit Uhrzeit.
                  for (var m = first; m <= last; m += 60) ...[
                    pw.Positioned(
                      left: axis,
                      right: 0,
                      top: y(m),
                      child: pw.Container(height: 0.5, color: line),
                    ),
                    pw.Positioned(
                      left: 0,
                      top: y(m) - 4,
                      child: pw.Text(hhmm(m), style: const pw.TextStyle(fontSize: 7, color: grey)),
                    ),
                  ],
                  for (var i = 0; i < days.length; i++)
                    pw.Positioned(
                      left: axis + i * column,
                      top: 0,
                      child: pw.SizedBox(
                        width: column,
                        height: gridHeight,
                        child: pw.Stack(
                          children: [
                            pw.Positioned(left: 0, top: 0, bottom: 0, child: pw.Container(width: 0.5, color: line)),
                            for (final s in studentsOn(timed, days[i])) block(s),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (untimed.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Text(
                  '${tr('Ohne Zeit', 'No time')}: '
                  '${untimed.map((s) => '${s.name} (${weekdayName(s.weekday!)})').join(', ')}',
                  style: const pw.TextStyle(fontSize: 8, color: grey),
                  maxLines: 1,
                ),
              ),
          ],
        );
      },
    ),
  );
  return doc.save();
}

/// Kleines Kästchen mit einer Kennzahl (Stundenplan).
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.highlight = false, this.compact = false});
  final String label, value;
  final bool highlight;

  /// Kleiner (Handy).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: BoxConstraints(minWidth: compact ? 0 : 180),
      padding: compact ? const EdgeInsets.fromLTRB(10, 6, 8, 8) : const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: highlight ? scheme.primaryContainer.withValues(alpha: 0.6) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            style: (compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
