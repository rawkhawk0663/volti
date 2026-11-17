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

/// Farbe für Ferien und Feiertage.
const _freeColor = Color(0xFF4A90D9);

/// Absenzenkontrolle einer Person: eine Spalte pro Unterrichtswoche des
/// Semesters (Kalenderwoche und Datum), darin X/E/U/A. Ferien und Feiertage
/// kommen aus dem Schulkalender (blau bzw. „F“) und lassen sich hier nicht
/// ändern. Rechts: Anwesenheiten, Absenzen und die Note.
class AttendanceTable extends StatefulWidget {
  const AttendanceTable({
    super.key,
    required this.student,
    required this.calendar,
    required this.onSet,
    required this.onGrade,
    required this.onEditStudent,
  });

  final Student student;
  final SchoolCalendar calendar;

  /// Status an einem Tag setzen (null = leeren).
  final void Function(DateTime day, LessonStatus? status) onSet;
  final void Function(String semesterId, String grade) onGrade;
  final VoidCallback onEditStudent;

  @override
  State<AttendanceTable> createState() => _AttendanceTableState();
}

class _AttendanceTableState extends State<AttendanceTable> {
  late Semester _semester = widget.calendar.semesterFor(DateTime.now());
  final _grade = TextEditingController();
  final _scroll = ScrollController();
  String? _gradeFor;

  static const _cell = 46.0;

  @override
  void dispose() {
    _grade.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _switch(int delta) {
    final list = widget.calendar.effectiveSemesters;
    final i = list.indexWhere((s) => s.id == _semester.id);
    final next = (i < 0 ? 0 : i + delta).clamp(0, list.length - 1);
    setState(() => _semester = list[next]);
  }

  Future<void> _choose(BuildContext cellContext, DateTime day, LessonStatus? current) async {
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
    widget.onSet(day, switch (v) {
      0 => LessonStatus.held,
      1 => LessonStatus.excused,
      2 => LessonStatus.missed,
      3 => LessonStatus.cancelled,
      _ => null,
    });
  }

  String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
  String _dmy(DateTime d) => '${_dm(d)}${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.student;
    final cal = widget.calendar;
    // Semester könnte inzwischen geändert worden sein.
    final list = cal.effectiveSemesters;
    _semester = list.firstWhere((x) => x.id == _semester.id, orElse: () => cal.semesterFor(DateTime.now()));
    final sem = _semester;
    if (_gradeFor != '${s.id}/${sem.id}') {
      _gradeFor = '${s.id}/${sem.id}';
      _grade.text = s.grades[sem.id] ?? '';
    }

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
    if (s.weekday == null) {
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
      final days = lessonDates(sem, s.weekday!);
      final today = DateTime.now();
      var present = 0, absent = 0;
      final columns = <Widget>[];
      var scrollTo = 0.0;
      for (var i = 0; i < days.length; i++) {
        final d = days[i];
        final free = cal.freeOn(d);
        final lesson = free == null ? s.lessonOn(d) : null;
        if (lesson != null) {
          if (lesson.status == LessonStatus.held || lesson.status == LessonStatus.makeUp) present++;
          if (lesson.isAbsence) absent++;
        }
        final thisWeek = isoWeek(d) == isoWeek(today) && d.year == today.year;
        if (!d.isAfter(today)) scrollTo = i * _cell;
        final letter = free != null
            ? (free.holiday ? 'F' : '')
            : (lesson == null ? '' : attendanceLetter(lesson.status));
        final letterColor = switch (letter) {
          'U' => scheme.error,
          'E' || 'A' => scheme.tertiary,
          _ => scheme.onSurface,
        };
        final headerBg = free != null ? _freeColor.withValues(alpha: 0.85) : null;
        columns.add(
          SizedBox(
            width: _cell,
            child: Tooltip(
              message: free?.name ?? '',
              child: Column(
                children: [
                  Container(
                    width: _cell - 4,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: headerBg,
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
                  const SizedBox(height: 6),
                  Builder(
                    builder: (cellContext) => InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: free != null ? null : () => _choose(cellContext, d, lesson?.status),
                      child: Container(
                        width: _cell - 10,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: free != null ? _freeColor.withValues(alpha: 0.35) : null,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: letter == 'U' || letter == 'E' ? letterColor : scheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          letter,
                          style: TextStyle(fontWeight: FontWeight.w700, color: letterColor),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      // Beim ersten Anzeigen zur aktuellen Woche scrollen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _scroll.offset == 0 && scrollTo > 0) {
          _scroll.jumpTo((scrollTo - 3 * _cell).clamp(0, _scroll.position.maxScrollExtent));
        }
      });
      Widget total(String label, Widget value) => SizedBox(
        width: 58,
        child: Column(
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            SizedBox(height: 30, child: Center(child: value)),
          ],
        ),
      );
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: columns),
              ),
            ),
          ),
          Container(width: 1, height: 64, color: scheme.outlineVariant),
          const SizedBox(width: 6),
          total(tr('Anw.', 'Pres.'), Text('$present', style: theme.textTheme.titleMedium)),
          total(tr('Abs.', 'Abs.'), Text('$absent', style: theme.textTheme.titleMedium)),
          total(
            tr('Note', 'Grade'),
            SizedBox(
              width: 48,
              child: TextField(
                controller: _grade,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
                onChanged: (v) => widget.onGrade(sem.id, v.trim()),
              ),
            ),
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
          if (s.weekday != null)
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
