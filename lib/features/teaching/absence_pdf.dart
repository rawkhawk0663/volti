import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/l10n.dart';
import '../../core/teaching/school_calendar.dart';
import '../../core/teaching/student.dart';
import 'attendance_table.dart' show attendanceLetter;
import 'homework_share.dart' show shortDate, voltiPdfTheme;
import 'student_dialog.dart' show weekdayName;

/// Eine Zeile der Absenzenliste: Person mit ihrem Unterrichtstag und ihrer
/// Zeit (bei Mitgliedern einer Gruppe die der Gruppe).
typedef AbsenceRow = ({Student student, int weekday, int minutes});

/// Zeilen für die Absenzenliste: alle aktiven Personen (keine Gruppen) mit
/// Unterrichtstag, nach Tag, Zeit und Name.
List<AbsenceRow> absenceRows(List<Student> students, Student? Function(String id) groupOf) {
  final rows = <AbsenceRow>[];
  for (final s in students) {
    if (s.archived || s.isGroup) continue;
    final g = groupOf(s.id);
    final day = s.weekday ?? g?.weekday;
    if (day == null) continue;
    rows.add((student: s, weekday: day, minutes: s.weekday != null ? s.minutes : g!.minutes));
  }
  rows.sort((a, b) {
    var c = a.weekday.compareTo(b.weekday);
    if (c != 0) return c;
    c = a.minutes.compareTo(b.minutes);
    return c != 0 ? c : a.student.name.toLowerCase().compareTo(b.student.name.toLowerCase());
  });
  return rows;
}

String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

/// Absenzenliste eines Semesters als PDF (A4 quer): pro Unterrichtstag eine
/// Tabelle mit vollem Namen, einer Spalte pro Woche (Kalenderwoche und Datum)
/// und den Summen, danach alle Absenzen und Ausfälle mit Grund.
Future<List<int>> buildAbsencePdf(List<AbsenceRow> rows, SchoolCalendar cal, Semester sem) async {
  final doc = pw.Document(title: tr('Absenzenliste', 'Attendance list'), creator: 'Volti');
  final theme = await voltiPdfTheme();
  const grey = PdfColor.fromInt(0xFF666666);
  const border = PdfColor.fromInt(0xFFBBBBBB);
  const free = PdfColor.fromInt(0xFFD6E6F7);
  const excused = PdfColor.fromInt(0xFFFFF3C4);
  const missed = PdfColor.fromInt(0xFFFDDCDC);
  const cancelled = PdfColor.fromInt(0xFFE9ECEE);
  final days = {for (final r in rows) r.weekday}.toList()..sort();

  pw.Widget cell(
    String text, {
    PdfColor? color,
    bool bold = false,
    double size = 7.5,
    pw.Alignment? align,
    double? height,
  }) => pw.Container(
    color: color,
    height: height,
    alignment: align ?? pw.Alignment.center,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null),
    ),
  );

  pw.Widget table(int weekday) {
    final dates = lessonDates(sem, weekday);
    final people = rows.where((r) => r.weekday == weekday).toList();
    return pw.Table(
      border: pw.TableBorder.all(color: border, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(120),
        for (var i = 0; i < dates.length; i++) i + 1: const pw.FlexColumnWidth(),
        dates.length + 1: const pw.FixedColumnWidth(26),
        dates.length + 2: const pw.FixedColumnWidth(26),
        dates.length + 3: const pw.FixedColumnWidth(30),
      },
      children: [
        pw.TableRow(
          repeat: true,
          children: [
            cell(weekdayName(weekday), bold: true, size: 9, align: pw.Alignment.centerLeft),
            for (final d in dates)
              cell(
                '${tr('KW', 'Wk')} ${isoWeek(d)}\n${_dm(d)}',
                size: 6,
                height: 24,
                color: cal.freeOn(d) == null ? null : free,
              ),
            cell(tr('Anw.', 'Pres.'), size: 6.5, bold: true),
            cell(tr('Abs.', 'Abs.'), size: 6.5, bold: true),
            cell(tr('Note', 'Grade'), size: 6.5, bold: true),
          ],
        ),
        for (final r in people)
          () {
            var present = 0, absent = 0;
            final cells = <pw.Widget>[];
            for (final d in dates) {
              final f = cal.freeOn(d);
              if (f != null) {
                cells.add(cell(f.holiday ? 'F' : '', color: free, height: 18));
                continue;
              }
              final l = r.student.lessonOn(d);
              if (l == null) {
                cells.add(cell('', height: 18));
                continue;
              }
              if (l.status == LessonStatus.held || l.status == LessonStatus.makeUp) present++;
              if (l.isAbsence) absent++;
              cells.add(
                cell(
                  attendanceLetter(l.status),
                  bold: true,
                  height: 18,
                  color: switch (l.status) {
                    LessonStatus.excused => excused,
                    LessonStatus.missed => missed,
                    LessonStatus.cancelled => cancelled,
                    _ => null,
                  },
                ),
              );
            }
            return pw.TableRow(
              children: [
                cell(r.student.name, size: 8, align: pw.Alignment.centerLeft, height: 18),
                ...cells,
                cell('$present', size: 8),
                cell('$absent', size: 8),
                cell(r.student.grades[sem.id] ?? '', size: 8),
              ],
            );
          }(),
      ],
    );
  }

  // Alle Absenzen und Ausfälle des Semesters mit Grund.
  final reasons =
      [
        for (final r in rows)
          for (final l in r.student.activeLessons)
            if (l.status != LessonStatus.held &&
                l.status != LessonStatus.makeUp &&
                sem.contains(l.date) &&
                cal.freeOn(l.date) == null)
              (student: r.student, lesson: l),
      ]..sort((a, b) {
        final c = a.student.name.toLowerCase().compareTo(b.student.name.toLowerCase());
        return c != 0 ? c : a.lesson.date.compareTo(b.lesson.date);
      });
  String kind(LessonStatus s) => switch (s) {
    LessonStatus.excused => tr('entschuldigt', 'excused'),
    LessonStatus.missed => tr('unentschuldigt', 'unexcused'),
    _ => tr('Ausfall', 'cancelled'),
  };

  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              tr('Absenzenliste', 'Attendance list'),
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              '${sem.name} · ${shortDate(sem.start)} – ${shortDate(sem.end)}',
              style: const pw.TextStyle(fontSize: 10, color: grey),
            ),
            pw.Spacer(),
            pw.Text('${context.pageNumber}/${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: grey)),
          ],
        ),
      ),
      build: (_) => [
        if (rows.isEmpty) pw.Text(tr('Noch niemand mit festem Unterrichtstag.', 'Nobody with a fixed lesson day yet.')),
        for (final d in days) ...[table(d), pw.SizedBox(height: 14)],
        if (rows.isNotEmpty)
          pw.Text(
            tr(
              'X = anwesend · E = entschuldigt · U = unentschuldigt · A = Ausfall · F = Feiertag · blau = Ferien und Feiertage',
              'X = present · E = excused · U = unexcused · A = cancelled · F = public holiday · blue = holidays',
            ),
            style: const pw.TextStyle(fontSize: 7, color: grey),
          ),
        if (reasons.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text(
            tr('Absenzen und Ausfälle', 'Absences and cancellations'),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: border, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(140),
              1: pw.FixedColumnWidth(90),
              2: pw.FixedColumnWidth(80),
              3: pw.FlexColumnWidth(),
            },
            children: [
              for (final e in reasons)
                pw.TableRow(
                  children: [
                    cell(e.student.name, size: 8, align: pw.Alignment.centerLeft),
                    cell(
                      '${tr('KW', 'Wk')} ${isoWeek(e.lesson.date)} · ${shortDate(e.lesson.date)}',
                      size: 8,
                      align: pw.Alignment.centerLeft,
                    ),
                    cell(
                      kind(e.lesson.status),
                      size: 8,
                      align: pw.Alignment.centerLeft,
                      color: switch (e.lesson.status) {
                        LessonStatus.excused => excused,
                        LessonStatus.missed => missed,
                        _ => cancelled,
                      },
                    ),
                    cell(e.lesson.reason.isEmpty ? '–' : e.lesson.reason, size: 8, align: pw.Alignment.centerLeft),
                  ],
                ),
            ],
          ),
        ],
      ],
    ),
  );
  return doc.save();
}
