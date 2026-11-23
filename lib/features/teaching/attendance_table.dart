import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/teaching/school_calendar.dart';
import '../../core/teaching/student.dart';

/// Kürzel einer Lektion in der Absenzenkontrolle.
String attendanceLetter(LessonStatus s) => switch (s) {
  LessonStatus.held || LessonStatus.makeUp => 'X',
  LessonStatus.excused => 'E',
  LessonStatus.missed => 'U',
  LessonStatus.cancelled => 'A',
};

/// Hintergrund einer Absenz: entschuldigt gelb, unentschuldigt rot,
/// Ausfall grau (null = keiner).
Color? absenceBackground(LessonStatus s, Brightness b) {
  final dark = b == Brightness.dark;
  return switch (s) {
    LessonStatus.excused => dark ? const Color(0xFF4A4220) : const Color(0xFFFFF3C4),
    LessonStatus.missed => dark ? const Color(0xFF4D2626) : const Color(0xFFFDDCDC),
    LessonStatus.cancelled => dark ? const Color(0xFF34383A) : const Color(0xFFE9ECEE),
    _ => null,
  };
}

/// Grund einer Absenz oder eines Ausfalls erfragen (leer erlaubt).
/// Gibt null zurück, wenn abgebrochen wurde.
Future<String?> showAbsenceReasonDialog(
  BuildContext context, {
  required LessonStatus status,
  required DateTime day,
  String reason = '',
  String? who,
}) {
  final text = TextEditingController(text: reason);
  final kind = switch (status) {
    LessonStatus.excused => tr('Entschuldigt', 'Excused'),
    LessonStatus.missed => tr('Unentschuldigt', 'Unexcused'),
    _ => tr('Ausfall', 'Cancelled'),
  };
  final date = '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('$kind · $date'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (who != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(who)),
            TextField(
              controller: text,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: tr('Grund', 'Reason'),
                hintText: status == LessonStatus.cancelled
                    ? tr('z. B. Weiterbildung, Konzert', 'e.g. training, concert')
                    : tr('z. B. krank, Skilager', 'e.g. ill, school trip'),
              ),
              onSubmitted: (v) => Navigator.of(c).pop(v.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.of(c).pop(text.text.trim()), child: Text(tr('Speichern', 'Save'))),
      ],
    ),
  ).whenComplete(text.dispose);
}

/// Farbe für Ferien und Feiertage.
const _freeColor = Color(0xFF4A90D9);

/// Absenzenkontrolle: eine Spalte pro Unterrichtswoche des Semesters
/// (Kalenderwoche und Datum), darin X/E/U/A, eine Zeile pro Person (bei einer
/// Gruppe für jedes Mitglied, mit Namen). Ferien und Feiertage kommen aus dem
/// Schulkalender (blau bzw. „F“) und lassen sich hier nicht ändern.
/// Rechts: Anwesenheiten, Absenzen und die Note.
class AttendanceTable extends StatefulWidget {
  const AttendanceTable({
    super.key,
    required this.students,
    required this.weekday,
    required this.calendar,
    required this.onSet,
    required this.onGrade,
    required this.onEditStudent,
  });

  /// Eine Zeile pro Person.
  final List<Student> students;

  /// Unterrichtstag (1 = Montag), null = noch nicht eingetragen.
  final int? weekday;
  final SchoolCalendar calendar;

  /// Status einer Person an einem Tag setzen (null = leeren), bei Absenz
  /// und Ausfall mit Grund.
  final void Function(Student s, DateTime day, LessonStatus? status, String reason) onSet;
  final void Function(Student s, String semesterId, String grade) onGrade;
  final VoidCallback onEditStudent;

  @override
  State<AttendanceTable> createState() => _AttendanceTableState();
}

class _AttendanceTableState extends State<AttendanceTable> {
  late Semester _semester = widget.calendar.semesterFor(DateTime.now());

  /// Notenfelder pro Person und Semester (Schlüssel `id/semester`).
  final _grades = <String, TextEditingController>{};
  final _scroll = ScrollController();

  /// Semester und Tag, zu denen schon einmal gescrollt wurde.
  String? _scrolledFor;

  static const _cell = 46.0;
  static const _headHeight = 38.0;
  static const _rowHeight = 38.0;
  static const _nameWidth = 96.0;

  @override
  void dispose() {
    for (final c in _grades.values) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  TextEditingController _gradeOf(Student s, Semester sem) =>
      _grades.putIfAbsent('${s.id}/${sem.id}', () => TextEditingController(text: s.grades[sem.id] ?? ''));

  void _switch(int delta) {
    final list = widget.calendar.effectiveSemesters;
    final i = list.indexWhere((s) => s.id == _semester.id);
    final next = (i < 0 ? 0 : i + delta).clamp(0, list.length - 1);
    setState(() => _semester = list[next]);
  }

  Future<void> _choose(BuildContext cellContext, Student s, DateTime day, Lesson? lesson) async {
    final current = lesson?.status;
    final box = cellContext.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(0, box.size.height));
    PopupMenuItem<int> item(int v, String letter, String text) => PopupMenuItem(
      value: v,
      height: 40,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(text),
        ],
      ),
    );
    final v = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        item(0, 'X', tr('anwesend', 'present')),
        item(1, 'E', tr('entschuldigt', 'excused')),
        item(2, 'U', tr('unentschuldigt', 'unexcused')),
        item(3, 'A', tr('Ausfall', 'cancelled')),
        if (current != null) item(4, '–', tr('leeren', 'clear')),
      ],
    );
    if (v == null) return;
    final status = switch (v) {
      0 => LessonStatus.held,
      1 => LessonStatus.excused,
      2 => LessonStatus.missed,
      3 => LessonStatus.cancelled,
      _ => null,
    };
    var reason = '';
    if (status != null && status != LessonStatus.held) {
      if (!mounted) return;
      final r = await showAbsenceReasonDialog(
        context,
        status: status,
        day: day,
        reason: lesson?.reason ?? '',
        who: widget.students.length > 1 ? s.name : null,
      );
      if (r == null) return;
      reason = r;
    }
    widget.onSet(s, day, status, reason);
  }

  String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
  String _dmy(DateTime d) => '${_dm(d)}${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final people = widget.students;
    final weekday = widget.weekday;
    final cal = widget.calendar;
    // Semester könnte inzwischen geändert worden sein.
    final list = cal.effectiveSemesters;
    _semester = list.firstWhere((x) => x.id == _semester.id, orElse: () => cal.semesterFor(DateTime.now()));
    final sem = _semester;

    final header = Row(
      children: [
        Text(
          tr('Absenzenkontrolle', 'Attendance'),
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            '${sem.name} · ${_dmy(sem.start)} – ${_dmy(sem.end)}',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: tr('Voriges Semester', 'Previous term'),
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: list.first.id == sem.id ? null : () => _switch(-1),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: tr('Nächstes Semester', 'Next term'),
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: list.last.id == sem.id ? null : () => _switch(1),
        ),
      ],
    );

    Widget body;
    if (weekday == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                tr(
                  'Trag den Unterrichtstag ein, dann erscheinen hier die Wochen des Semesters.',
                  'Add the lesson day and the weeks of the term will appear here.',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: widget.onEditStudent, child: Text(tr('Tag eintragen …', 'Add day …'))),
          ],
        ),
      );
    } else {
      final days = lessonDates(sem, weekday);
      final today = DateTime.now();
      final withNames = people.length > 1;
      var scrollTo = 0.0;
      final heads = <Widget>[];
      for (var i = 0; i < days.length; i++) {
        final d = days[i];
        final free = cal.freeOn(d);
        final thisWeek = isoWeek(d) == isoWeek(today) && d.year == today.year;
        if (!d.isAfter(today)) scrollTo = i * _cell;
        heads.add(
          SizedBox(
            width: _cell,
            height: _headHeight,
            child: Tooltip(
              message: free?.name ?? '',
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: _cell - 4,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: free != null ? _freeColor.withValues(alpha: 0.85) : null,
                    borderRadius: BorderRadius.circular(4),
                    border: thisWeek ? Border.all(color: scheme.error, width: 1.5) : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${isoWeek(d)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: free != null ? Colors.white : scheme.onSurfaceVariant,
                          fontWeight: thisWeek ? FontWeight.w700 : null,
                        ),
                      ),
                      Text(
                        _dm(d),
                        style: TextStyle(fontSize: 9.5, color: free != null ? Colors.white : scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      // Eine Zeile pro Person, dazu ihre Summen.
      final rows = <Widget>[];
      final totals = <({int present, int absent})>[];
      for (final s in people) {
        var present = 0, absent = 0;
        final cells = <Widget>[];
        for (final d in days) {
          final free = cal.freeOn(d);
          final lesson = free == null ? s.lessonOn(d) : null;
          if (lesson != null) {
            if (lesson.status == LessonStatus.held || lesson.status == LessonStatus.makeUp) present++;
            if (lesson.isAbsence) absent++;
          }
          final letter = free != null
              ? (free.holiday ? 'F' : '')
              : (lesson == null ? '' : attendanceLetter(lesson.status));
          final letterColor = switch (letter) {
            'U' => scheme.error,
            'E' || 'A' => scheme.tertiary,
            _ => scheme.onSurface,
          };
          cells.add(
            SizedBox(
              width: _cell,
              height: _rowHeight,
              child: Center(
                child: Builder(
                  builder: (cellContext) => InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: free != null ? null : () => _choose(cellContext, s, d, lesson),
                    child: Container(
                      width: _cell - 10,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: free != null
                            ? _freeColor.withValues(alpha: 0.35)
                            : (lesson == null ? null : absenceBackground(lesson.status, theme.brightness)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: letter == 'U' || letter == 'E' ? letterColor : scheme.outlineVariant),
                      ),
                      child: Text(
                        letter,
                        style: TextStyle(fontWeight: FontWeight.w700, color: letterColor),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        rows.add(Row(children: cells));
        totals.add((present: present, absent: absent));
      }

      // Nur beim Öffnen und beim Wechsel des Semesters zur aktuellen Woche
      // scrollen, nie bei einem Eintrag: Sonst sprang die Tabelle zurück,
      // wenn man an den Anfang des Semesters gescrollt hatte.
      final scrollKey = '${sem.id}/$weekday';
      if (_scrolledFor != scrollKey) {
        _scrolledFor = scrollKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          _scroll.jumpTo((scrollTo - 3 * _cell).clamp(0, _scroll.position.maxScrollExtent));
        });
      }
      // Handy: schmalere Summen, damit mehr Wochen sichtbar bleiben.
      final sumWidth = MediaQuery.sizeOf(context).width < 600 ? 44.0 : 58.0;
      Widget total(Widget child) => SizedBox(
        width: sumWidth,
        height: _rowHeight,
        child: Center(child: child),
      );
      Widget label(String text) => SizedBox(
        width: sumWidth,
        height: _headHeight,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ),
      );
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (withNames)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: _headHeight),
                for (final s in people)
                  SizedBox(
                    width: _nameWidth,
                    height: _rowHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(s.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                    ),
                  ),
              ],
            ),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: heads),
                    ...rows,
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: _headHeight + people.length * _rowHeight, color: scheme.outlineVariant),
          const SizedBox(width: 6),
          Column(
            children: [
              Row(children: [label(tr('Anw.', 'Pres.')), label(tr('Abs.', 'Abs.')), label(tr('Note', 'Grade'))]),
              for (var i = 0; i < people.length; i++)
                Row(
                  children: [
                    total(Text('${totals[i].present}', style: theme.textTheme.titleMedium)),
                    total(Text('${totals[i].absent}', style: theme.textTheme.titleMedium)),
                    total(
                      SizedBox(
                        width: sumWidth - 8,
                        child: TextField(
                          controller: _gradeOf(people[i], sem),
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(vertical: 6),
                          ),
                          onChanged: (v) => widget.onGrade(people[i], sem.id, v.trim()),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          body,
          if (weekday != null)
            Text(
              tr(
                'X = anwesend · U = unentschuldigt · E = entschuldigt · A = Ausfall · F = Feiertag · blau = Ferien und Feiertage',
                'X = present · U = unexcused · E = excused · A = cancelled · F = public holiday · blue = holidays',
              ),
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
