import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/l10n.dart';
import '../../core/teaching/school_calendar.dart';
import '../../core/teaching/student.dart';
import '../library/library_controller.dart';
import 'attendance_table.dart' show attendanceLetter;
import 'homework_share.dart' show shortDate, voltiPdfTheme;
import 'student_dialog.dart' show weekdayName;

/// Eine Zeile der Absenzenliste: Person mit ihrem Unterrichtstag, ihrer
/// Zeit und ihrem Ort (bei Mitgliedern einer Gruppe die der Gruppe).
typedef AbsenceRow = ({Student student, int weekday, int minutes, String time, String place});

/// Was auf die Absenzenliste kommt (Gerätevorliebe `absenceExport`).
class AbsenceExportOptions {
  AbsenceExportOptions({
    Set<String>? excludedPlaces,
    this.reasons = true,
    this.grade = true,
    this.instrument = false,
    this.time = false,
    this.byName = false,
  }) : excludedPlaces = excludedPlaces ?? {};

  /// Eine Liste alphabetisch nach Nachnamen statt einer Tabelle pro
  /// Unterrichtstag.
  bool byName;

  /// Orte, die *nicht* auf die Liste kommen ('' = ohne Ort). So sind neue
  /// Orte von selbst dabei.
  final Set<String> excludedPlaces;

  /// Absenzen und Ausfälle mit Grund unter den Tabellen auflisten.
  bool reasons;

  /// Spalten Note, Instrument, Zeit.
  bool grade;
  bool instrument;
  bool time;

  String encode() => jsonEncode({
    'excluded': excludedPlaces.toList(),
    'reasons': reasons,
    'grade': grade,
    'instrument': instrument,
    'time': time,
    'byName': byName,
  });

  static AbsenceExportOptions decode(String? s) {
    try {
      final j = jsonDecode(s!) as Map<String, dynamic>;
      return AbsenceExportOptions(
        excludedPlaces: {for (final x in j['excluded'] as List? ?? const []) x as String},
        reasons: j['reasons'] as bool? ?? true,
        grade: j['grade'] as bool? ?? true,
        instrument: j['instrument'] as bool? ?? false,
        time: j['time'] as bool? ?? false,
        byName: j['byName'] as bool? ?? false,
      );
    } catch (_) {
      return AbsenceExportOptions();
    }
  }
}

/// Zeilen für die Absenzenliste: alle aktiven Personen (keine Gruppen) mit
/// Unterrichtstag, nach Tag, Zeit und Name.
List<AbsenceRow> absenceRows(List<Student> students, Student? Function(String id) groupOf) {
  final rows = <AbsenceRow>[];
  for (final s in students) {
    if (s.archived || s.isGroup) continue;
    final g = groupOf(s.id);
    final day = s.weekday ?? g?.weekday;
    if (day == null) continue;
    // Zeit und Ort: eigene Angaben, sonst die der Gruppe.
    final src = s.weekday != null ? s : g!;
    final time = src.time == null ? '' : '${src.time}–${src.endTime}';
    final place = s.place.trim().isNotEmpty ? s.place.trim() : (g?.place.trim() ?? '');
    rows.add((student: s, weekday: day, minutes: src.minutes, time: time, place: place));
  }
  rows.sort((a, b) {
    var c = a.weekday.compareTo(b.weekday);
    if (c != 0) return c;
    c = a.minutes.compareTo(b.minutes);
    return c != 0 ? c : a.student.name.toLowerCase().compareTo(b.student.name.toLowerCase());
  });
  return rows;
}

/// Vor- und Nachname aus dem Namen der Kartei: Steht ein Komma drin, ist
/// der Teil davor der Nachname („von Arx, Anna“), sonst das letzte Wort
/// („Levin Sägesser“ → Sägesser).
({String first, String last}) splitName(String name) {
  final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  final comma = n.indexOf(',');
  if (comma > 0) return (first: n.substring(comma + 1).trim(), last: n.substring(0, comma).trim());
  final space = n.lastIndexOf(' ');
  if (space < 0) return (first: '', last: n);
  return (first: n.substring(0, space), last: n.substring(space + 1));
}

/// „Sägesser Levin“: Nachname zuerst (für die alphabetische Liste).
String surnameFirst(String name) {
  final p = splitName(name);
  return p.first.isEmpty ? p.last : '${p.last} ${p.first}';
}

/// Zum Sortieren nach Nachnamen, dann Vornamen.
String surnameKey(String name) => surnameFirst(name).toLowerCase();

/// Zeilenhöhen der Tabelle (Punkte).
const _row = 11.5;
const _head = 19.0;

String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

/// Absenzenliste eines Semesters als PDF (A4 quer): pro Unterrichtstag eine
/// Tabelle mit vollem Namen, einer Spalte pro Woche (Kalenderwoche und Datum)
/// und den Summen, danach alle Absenzen und Ausfälle mit Grund. Mit
/// [AbsenceExportOptions.byName] eine einzige Tabelle nach Nachnamen.
///
/// Kompakt, damit eine ganze Klasse auf eine Seite passt: schmale Zeilen,
/// kleine Schrift. [options] bestimmt Orte, Spalten und die Liste der Gründe.
Future<List<int>> buildAbsencePdf(
  List<AbsenceRow> allRows,
  SchoolCalendar cal,
  Semester sem, {
  AbsenceExportOptions? options,
}) async {
  final opt = options ?? AbsenceExportOptions();
  final rows = [
    for (final r in allRows)
      if (!opt.excludedPlaces.contains(r.place)) r,
  ];
  final places = {for (final r in rows) r.place}.where((p) => p.isNotEmpty).toList()..sort();
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
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    child: pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null),
    ),
  );

  /// Eine Tabelle: [title] oben links, eine Spalte pro Woche ([heads]:
  /// Datum im Kopf), [dateOf] liefert den Unterrichtstag einer Person in
  /// Woche i. [freeHead] färbt den Kopf einer Woche blau.
  pw.Widget table(
    String title,
    List<AbsenceRow> people,
    List<DateTime> heads,
    DateTime Function(AbsenceRow r, int i) dateOf,
    bool Function(int i) freeHead, {
    bool surname = false,
  }) {
    // Spalten: Name, [Instrument], [Zeit], Wochen, Anw., Abs., [Note].
    final lead = 1 + (opt.instrument ? 1 : 0) + (opt.time ? 1 : 0);
    final widths = <int, pw.TableColumnWidth>{0: const pw.FixedColumnWidth(104)};
    var col = 1;
    if (opt.instrument) widths[col++] = const pw.FixedColumnWidth(58);
    if (opt.time) widths[col++] = pw.FixedColumnWidth(surname ? 58 : 48);
    for (var i = 0; i < heads.length; i++) {
      widths[lead + i] = const pw.FlexColumnWidth();
    }
    widths[lead + heads.length] = const pw.FixedColumnWidth(22);
    widths[lead + heads.length + 1] = const pw.FixedColumnWidth(22);
    if (opt.grade) widths[lead + heads.length + 2] = const pw.FixedColumnWidth(26);
    return pw.Table(
      border: pw.TableBorder.all(color: border, width: 0.5),
      columnWidths: widths,
      children: [
        pw.TableRow(
          repeat: true,
          children: [
            cell(title, bold: true, size: 8, align: pw.Alignment.centerLeft, height: _head),
            if (opt.instrument) cell(tr('Instrument', 'Instrument'), size: 5.5, bold: true, height: _head),
            if (opt.time)
              cell(surname ? tr('Tag & Zeit', 'Day & time') : tr('Zeit', 'Time'), size: 5.5, bold: true, height: _head),
            for (var i = 0; i < heads.length; i++)
              cell(
                // Nur die Nummer, sonst bricht „KW 34“ in schmalen Spalten um.
                '${isoWeek(heads[i])}\n${_dm(heads[i]).substring(0, 5)}',
                size: 5.5,
                height: _head,
                color: freeHead(i) ? free : null,
              ),
            cell(tr('Anw.', 'Pres.'), size: 5.5, bold: true, height: _head),
            cell(tr('Abs.', 'Abs.'), size: 5.5, bold: true, height: _head),
            if (opt.grade) cell(tr('Note', 'Grade'), size: 5.5, bold: true, height: _head),
          ],
        ),
        for (final r in people)
          () {
            var present = 0, absent = 0;
            final cells = <pw.Widget>[];
            for (var i = 0; i < heads.length; i++) {
              final d = dateOf(r, i);
              if (!sem.contains(d)) {
                cells.add(cell('', height: _row));
                continue;
              }
              final f = cal.freeOn(d);
              if (f != null) {
                cells.add(cell(f.holiday ? 'F' : '', size: 6.5, color: free, height: _row));
                continue;
              }
              final l = r.student.lessonOn(d);
              if (l == null) {
                cells.add(cell('', height: _row));
                continue;
              }
              if (l.status == LessonStatus.held || l.status == LessonStatus.makeUp) present++;
              if (l.isAbsence) absent++;
              cells.add(
                cell(
                  attendanceLetter(l.status),
                  bold: true,
                  size: 6.5,
                  height: _row,
                  color: switch (l.status) {
                    LessonStatus.excused => excused,
                    LessonStatus.missed => missed,
                    LessonStatus.cancelled => cancelled,
                    _ => null,
                  },
                ),
              );
            }
            final day = weekdayName(r.weekday).substring(0, 2);
            return pw.TableRow(
              children: [
                cell(
                  surname ? surnameFirst(r.student.name) : r.student.name,
                  size: 6.5,
                  align: pw.Alignment.centerLeft,
                  height: _row,
                ),
                if (opt.instrument) cell(r.student.instrument, size: 6, align: pw.Alignment.centerLeft, height: _row),
                if (opt.time) cell(surname ? '$day ${r.time}'.trim() : r.time, size: 6, height: _row),
                ...cells,
                cell('$present', size: 6.5, height: _row),
                cell('$absent', size: 6.5, height: _row),
                if (opt.grade) cell(r.student.grades[sem.id] ?? '', size: 6.5, height: _row),
              ],
            );
          }(),
      ],
    );
  }

  /// Pro Unterrichtstag eine Tabelle mit den Daten dieses Tages.
  List<pw.Widget> byDay() => [
    for (final d in days) ...[
      () {
        final dates = lessonDates(sem, d);
        return table(
          weekdayName(d),
          rows.where((r) => r.weekday == d).toList(),
          dates,
          (r, i) => dates[i],
          (i) => cal.freeOn(dates[i]) != null,
        );
      }(),
      pw.SizedBox(height: 7),
    ],
  ];

  /// Eine Tabelle für alle, alphabetisch nach Nachnamen. Die Spalten sind
  /// die Wochen (Kopf: Montag), jede Person an ihrem Unterrichtstag.
  pw.Widget byName() {
    final mondays = <DateTime>[];
    var m = DateTime(sem.start.year, sem.start.month, sem.start.day - (sem.start.weekday - 1));
    final weekdays = {for (final r in rows) r.weekday};
    while (!m.isAfter(sem.end)) {
      // Nur Wochen, in denen jemand im Semester Unterricht hätte.
      final week = m;
      if (weekdays.any((d) => sem.contains(DateTime(week.year, week.month, week.day + d - 1)))) mondays.add(week);
      m = DateTime(m.year, m.month, m.day + 7);
    }
    final people = [...rows]..sort((a, b) => surnameKey(a.student.name).compareTo(surnameKey(b.student.name)));
    return table(
      tr('Name', 'Name'),
      people,
      mondays,
      (r, i) => DateTime(mondays[i].year, mondays[i].month, mondays[i].day + r.weekday - 1),
      // Ganze Woche frei (Montag bis Freitag): Kopf blau.
      (i) => cal.freeOn(mondays[i]) != null && cal.freeOn(mondays[i].add(const Duration(days: 4))) != null,
      surname: true,
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
        final c = surnameKey(a.student.name).compareTo(surnameKey(b.student.name));
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
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              tr('Absenzenliste', 'Attendance list'),
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              [
                '${sem.name} · ${shortDate(sem.start)} – ${shortDate(sem.end)}',
                if (opt.excludedPlaces.isNotEmpty && places.isNotEmpty) places.join(', '),
              ].join(' · '),
              style: const pw.TextStyle(fontSize: 10, color: grey),
            ),
            pw.Spacer(),
            pw.Text('${context.pageNumber}/${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: grey)),
          ],
        ),
      ),
      build: (_) => [
        if (rows.isEmpty) pw.Text(tr('Noch niemand mit festem Unterrichtstag.', 'Nobody with a fixed lesson day yet.')),
        if (opt.byName) ...[byName(), pw.SizedBox(height: 7)] else ...byDay(),
        if (rows.isNotEmpty)
          pw.Text(
            tr(
              'X = anwesend · E = entschuldigt · U = unentschuldigt · A = Ausfall · F = Feiertag · blau = Ferien und Feiertage',
              'X = present · E = excused · U = unexcused · A = cancelled · F = public holiday · blue = holidays',
            ),
            style: const pw.TextStyle(fontSize: 7, color: grey),
          ),
        // Die Gründe auf einer eigenen Seite (die Überschrift hing sonst allein unten).
        if (opt.reasons && reasons.isNotEmpty) ...[
          pw.NewPage(),
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
                    cell(
                      opt.byName ? surnameFirst(e.student.name) : e.student.name,
                      size: 7,
                      height: 13,
                      align: pw.Alignment.centerLeft,
                    ),
                    cell(
                      '${tr('KW', 'Wk')} ${isoWeek(e.lesson.date)} · ${shortDate(e.lesson.date)}',
                      size: 7,
                      height: 13,
                      align: pw.Alignment.centerLeft,
                    ),
                    cell(
                      kind(e.lesson.status),
                      size: 7,
                      height: 13,
                      align: pw.Alignment.centerLeft,
                      color: switch (e.lesson.status) {
                        LessonStatus.excused => excused,
                        LessonStatus.missed => missed,
                        _ => cancelled,
                      },
                    ),
                    cell(
                      e.lesson.reason.isEmpty ? '–' : e.lesson.reason,
                      size: 7,
                      height: 13,
                      align: pw.Alignment.centerLeft,
                    ),
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

/// Fenster vor dem Export: Semester, Unterrichtsorte, Spalten und ob die
/// Gründe aufgelistet werden. Die Wahl merkt sich das Gerät.
Future<({Semester semester, AbsenceExportOptions options})?> showAbsenceExportDialog(
  BuildContext context,
  LibraryController library,
) async {
  final cal = library.calendar;
  final semesters = cal.effectiveSemesters.reversed.toList();
  final current = cal.semesterFor(DateTime.now());
  final rows = absenceRows(library.students, library.groupOf);
  final places = {for (final r in rows) r.place}.toList()
    ..sort((a, b) {
      // „Ohne Ort“ zuletzt.
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  final opt = AbsenceExportOptions.decode(library.settings.text('absenceExport'));
  var sem = semesters.firstWhere((s) => s.id == current.id, orElse: () => semesters.first);
  int countAt(String place) => rows.where((r) => r.place == place).length;

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialog) {
        final theme = Theme.of(c);
        Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t, style: theme.textTheme.labelLarge),
        );
        final none = places.every(opt.excludedPlaces.contains);
        return AlertDialog(
          title: Text(tr('Absenzenliste als PDF', 'Attendance list as PDF')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading(tr('Ordnen nach', 'Order by')),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text(tr('Unterrichtstag', 'Lesson day')),
                        selected: !opt.byName,
                        onSelected: (_) => setDialog(() => opt.byName = false),
                      ),
                      ChoiceChip(
                        label: Text(tr('Nachname (alphabetisch)', 'Surname (alphabetical)')),
                        selected: opt.byName,
                        onSelected: (_) => setDialog(() => opt.byName = true),
                      ),
                    ],
                  ),
                  heading(tr('Semester', 'Term')),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final x in semesters)
                        ChoiceChip(
                          label: Text(x.name),
                          selected: x.id == sem.id,
                          onSelected: (_) => setDialog(() => sem = x),
                        ),
                    ],
                  ),
                  if (places.length > 1) ...[
                    heading(tr('Unterrichtsort', 'Place')),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in places)
                          FilterChip(
                            label: Text('${p.isEmpty ? tr('ohne Ort', 'no place') : p} (${countAt(p)})'),
                            selected: !opt.excludedPlaces.contains(p),
                            onSelected: (on) =>
                                setDialog(() => on ? opt.excludedPlaces.remove(p) : opt.excludedPlaces.add(p)),
                          ),
                      ],
                    ),
                  ],
                  heading(tr('Spalten', 'Columns')),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: opt.instrument,
                    title: Text(tr('Instrument', 'Instrument')),
                    onChanged: (v) => setDialog(() => opt.instrument = v ?? false),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: opt.time,
                    title: Text(opt.byName ? tr('Tag & Zeit', 'Day & time') : tr('Zeit', 'Time')),
                    onChanged: (v) => setDialog(() => opt.time = v ?? false),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: opt.grade,
                    title: Text(tr('Note', 'Grade')),
                    onChanged: (v) => setDialog(() => opt.grade = v ?? false),
                  ),
                  heading(tr('Darunter', 'Below')),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: opt.reasons,
                    title: Text(tr('Absenzen mit Grund auflisten', 'List absences with reason')),
                    onChanged: (v) => setDialog(() => opt.reasons = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton.icon(
              onPressed: places.isNotEmpty && none ? null : () => Navigator.of(c).pop(true),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(tr('PDF erstellen', 'Create PDF')),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true) return null;
  // Nur Orte merken, die es gibt (gelöschte Orte fallen weg).
  opt.excludedPlaces.retainAll(places);
  await library.settings.setText('absenceExport', opt.encode());
  return (semester: sem, options: opt);
}
