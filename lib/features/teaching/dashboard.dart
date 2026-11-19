import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/teaching/student.dart';
import '../library/library_controller.dart';
import 'attendance_table.dart' show absenceBackground;
import 'student_dialog.dart';
import 'teaching_view.dart';
import 'todo_widgets.dart';

/// Lektionen an einem Tag (nach Zeit; ohne Zeit zuletzt).
List<Student> lessonsOn(Iterable<Student> units, DateTime day) =>
    units.where((s) => s.weekday == day.weekday).toList()..sort((a, b) {
      final c = a.minutes.compareTo(b.minutes);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

/// Nächster Tag nach [now] mit Unterricht (höchstens eine Woche voraus;
/// Ferien und Feiertage werden übersprungen, wenn [isFree] sie meldet).
({DateTime day, List<Student> lessons})? nextTeachingDay(
  Iterable<Student> units,
  DateTime now, {
  bool Function(DateTime day)? isFree,
}) {
  for (var i = 1; i <= 7; i++) {
    final d = DateTime(now.year, now.month, now.day + i);
    if (isFree?.call(d) ?? false) continue;
    final l = lessonsOn(units, d);
    if (l.isNotEmpty) return (day: d, lessons: l);
  }
  return null;
}

/// Die nächste Lektion, die noch nicht begonnen hat: heute später, sonst am
/// nächsten Unterrichtstag.
({Student student, DateTime day})? nextLesson(
  Iterable<Student> units,
  DateTime now, {
  bool Function(DateTime day)? isFree,
}) {
  final today = DateTime(now.year, now.month, now.day);
  if (!(isFree?.call(today) ?? false)) {
    final minute = now.hour * 60 + now.minute;
    for (final s in lessonsOn(units, today)) {
      if (s.time != null && s.minutes > minute) return (student: s, day: today);
    }
  }
  final next = nextTeachingDay(units, now, isFree: isFree);
  return next == null ? null : (student: next.lessons.first, day: next.day);
}

/// Dauer als „1 h 15 min“ bzw. „45 min“.
String durationText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')} min';
}

/// Tipps, die in der Übersicht der Reihe nach erscheinen.
List<String> get _tips => [
  tr(
    'In „Unterrichten“ wechselst du mit den Pfeiltasten ← → zur vorigen oder nächsten Person.',
    'In “Teach”, the arrow keys ← → switch to the previous or next person.',
  ),
  tr(
    'Strg+S speichert die Lektion. Über den Feldern formatierst du den Text: fett, Farbe, Listen, Links, Emojis.',
    'Ctrl+S saves the lesson. Above the fields you can format text: bold, colour, lists, links, emojis.',
  ),
  tr(
    'Was du in den Noten einer Kartei notierst, sieht nur diese Person. Bibliothek und Setlists bleiben sauber.',
    'What you write in the music of a record is only seen there. Library and setlists stay clean.',
  ),
  tr(
    '„Speichern & senden“ schickt die Hausaufgaben per E-Mail oder WhatsApp, auf Wunsch als PDF mit den Noten.',
    '“Save & send” sends the homework by email or WhatsApp, or as a PDF with the music.',
  ),
  tr(
    'In der Absenzenkontrolle ein Feld antippen: X, E, U oder A. Bei Absenzen und Ausfällen kannst du einen Grund eintragen.',
    'Tap a box in the attendance table: X, E, U or A. For absences and cancellations you can add a reason.',
  ),
  tr(
    'Ferien und Feiertage trägst du einmal beim Stundenplan unter „Ferien & Semester“ ein.',
    'Enter holidays once in the timetable under “Holidays & terms”.',
  ),
  tr(
    'Unter „Absenzen“ gibt es die Absenzenliste eines Semesters als PDF.',
    'Under “Absences” you get the attendance list of a term as a PDF.',
  ),
  tr(
    'Unter „Schüler:innen“ fasst „Gruppe bilden“ mehrere Personen zu einer Kartei zusammen.',
    'Under “Students”, “Make group” combines several people into one record.',
  ),
];

/// Übersicht über den Tag: links „Heute“ als Zeitleiste, daneben die nächste
/// Lektion, Tipps, To-Dos und Geburtstage.
class DashboardView extends StatefulWidget {
  const DashboardView({
    super.key,
    required this.library,
    required this.actions,
    required this.onOpen,
    required this.onAdd,
    required this.onTimetable,
    required this.onTodos,
  });

  final LibraryController library;
  final List<Widget> actions;
  final void Function(Student s) onOpen;
  final VoidCallback onAdd;
  final VoidCallback onTimetable;
  final VoidCallback onTodos;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  LibraryController get library => widget.library;

  /// Neu zeichnen, damit „jetzt“ und die rote Linie mitlaufen.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final header = [
      TeachingTopBar(
        title: tr('Übersicht', 'Overview'),
        subtitle: '${weekdayName(today.weekday)}, ${longDate(today)}',
        trailing: widget.actions,
      ),
      const Divider(height: 1),
    ];

    if (library.students.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dashboard_outlined, size: 56, color: scheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      tr(
                        'Hier siehst du jeden Tag, wer wann Unterricht hat, dazu die nächste Lektion, To-Dos und Geburtstage.',
                        'Here you see each day who has a lesson when, plus the next lesson, to-dos and birthdays.',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: widget.onAdd,
                      icon: const Icon(Icons.person_add_alt),
                      label: Text(tr('Erste:n Schüler:in erfassen', 'Add first student')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final todayCard = _TodayCard(library: library, now: now, onOpen: widget.onOpen, onTimetable: widget.onTimetable);
    final nextCard = _NextLessonCard(library: library, now: now, onOpen: widget.onOpen);
    final todoCard = _TodosCard(library: library, onTodos: widget.onTodos);
    const tipsCard = _TipsCard();
    final birthdayCard = _BirthdaysCard(library: library, now: now, onOpen: widget.onOpen);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...header,
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              const gap = 14.0;
              if (box.maxWidth >= 900) {
                // Breit: „Heute“ links über die ganze Höhe, rechts zwei Reihen.
                final height = (box.maxHeight - 2 * 18).clamp(380.0, 540.0);
                const top = 150.0;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: SizedBox(
                    height: height,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: (box.maxWidth * 0.26).clamp(260.0, 360.0), child: todayCard),
                        const SizedBox(width: gap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: top, child: nextCard),
                              const SizedBox(height: gap),
                              const Expanded(child: tipsCard),
                            ],
                          ),
                        ),
                        const SizedBox(width: gap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: top, child: todoCard),
                              const SizedBox(height: gap),
                              Expanded(child: birthdayCard),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              // Schmal: untereinander.
              return ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  SizedBox(height: 420, child: todayCard),
                  const SizedBox(height: gap),
                  SizedBox(height: 140, child: nextCard),
                  const SizedBox(height: gap),
                  SizedBox(height: 150, child: todoCard),
                  const SizedBox(height: gap),
                  const SizedBox(height: 180, child: tipsCard),
                  const SizedBox(height: gap),
                  SizedBox(height: 180, child: birthdayCard),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Rahmen einer Karte: Symbol, Titel, rechts ein Knopf, darunter der Inhalt.
class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.child, this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = context.volti;
    return Material(
      color: v.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: v.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    // Symbol im Markenverlauf.
                    ShaderMask(
                      shaderCallback: (r) => LinearGradient(colors: v.brand).createShader(r),
                      child: Icon(icon, size: 20, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    ?trailing,
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Heute
class _TodayCard extends StatefulWidget {
  const _TodayCard({required this.library, required this.now, required this.onOpen, required this.onTimetable});
  final LibraryController library;
  final DateTime now;
  final void Function(Student s) onOpen;
  final VoidCallback onTimetable;

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard> {
  static const _perMinute = 1.15;
  static const _axis = 44.0;
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lib = widget.library;
    final now = widget.now;
    final today = DateTime(now.year, now.month, now.day);
    final free = lib.calendar.freeOn(today);
    final lessons = lessonsOn(teachingUnits(lib), today).where((s) => s.time != null).toList();
    final minute = now.hour * 60 + now.minute;

    final String status;
    if (free != null) {
      status = free.holiday ? tr('Feiertag: ${free.name}', 'Holiday: ${free.name}') : free.name;
    } else if (lessons.isEmpty) {
      status = tr('Heute kein Unterricht', 'No lessons today');
    } else if (lessons.every((s) => s.minutes + s.duration <= minute)) {
      status = tr('fertig für heute', 'done for today');
    } else {
      final left = lessons.where((s) => s.minutes + s.duration > minute).length;
      final total = lessons.fold<int>(0, (n, s) => n + s.duration);
      status = tr(
        'noch $left von ${lessons.length} ${lessons.length == 1 ? 'Lektion' : 'Lektionen'} · ${durationText(total)}',
        '$left of ${lessons.length} ${lessons.length == 1 ? 'lesson' : 'lessons'} left · ${durationText(total)}',
      );
    }

    Widget body;
    if (free != null || lessons.isEmpty) {
      body = Center(
        child: Icon(
          free != null ? Icons.beach_access_outlined : Icons.free_breakfast_outlined,
          size: 40,
          color: scheme.outlineVariant,
        ),
      );
    } else {
      final first = lessons.first.minutes ~/ 60 * 60;
      var last = ((lessons.map((s) => s.minutes + s.duration).reduce((a, b) => a > b ? a : b) + 59) ~/ 60) * 60;
      if (last - first < 180) last = first + 180;
      double y(int m) => (m - first) * _perMinute + 8;
      final height = y(last) + 8;
      // Beim ersten Anzeigen zur laufenden bzw. nächsten Lektion scrollen.
      if (!_scrolled) {
        _scrolled = true;
        final target = minute.clamp(first, last) - 30;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(y(target).clamp(0.0, _scroll.position.maxScrollExtent));
          }
        });
      }
      body = SingleChildScrollView(
        controller: _scroll,
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              for (var m = first; m <= last; m += 60) ...[
                Positioned(
                  left: 0,
                  top: y(m) - 8,
                  child: Text(
                    '${(m ~/ 60).toString().padLeft(2, '0')}:00',
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                Positioned(
                  left: _axis,
                  right: 0,
                  top: y(m),
                  child: Container(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
              ],
              for (final s in lessons) _block(context, s, today, minute, y(s.minutes), s.duration * _perMinute),
              // Rote Linie: jetzt.
              if (minute >= first && minute <= last)
                Positioned(
                  left: _axis - 4,
                  right: 0,
                  top: y(minute) - 1,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                      ),
                      Expanded(child: Container(height: 2, color: scheme.error)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return _Card(
      icon: Icons.today_outlined,
      title: tr('Heute', 'Today'),
      trailing: TextButton(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 28),
        ),
        onPressed: widget.onTimetable,
        child: Text(tr('Stundenplan', 'Timetable')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(status, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, Student s, DateTime today, int minute, double top, double height) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = s.lessonOn(today);
    final running = s.minutes <= minute && minute < s.minutes + s.duration;
    final done = entry != null && (entry.status == LessonStatus.held || entry.status == LessonStatus.makeUp);
    final v = context.volti;
    final absence = entry == null ? null : absenceBackground(entry.status, theme.brightness);
    // Eingetragen: Mint-Blau, jetzt: Markenverlauf, sonst Türkis-Blau (blass).
    final colors = done ? v.mint : (running ? v.brand : v.sky);
    final green = v.mint.first;
    final bg = absence ?? colors.first.withValues(alpha: done || running ? 0.16 : 0.08);
    final edge = running ? colors.last : colors.first.withValues(alpha: done ? 0.7 : 0.35);
    return Positioned(
      left: _axis,
      right: 0,
      top: top + 1,
      height: height - 2,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: edge, width: running ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onOpen(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: height >= 40 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: height >= 40 ? 5 : 0),
                    child: Text(
                      height >= 40 ? '${s.name}\n${s.time}–${s.endTime}' : s.name,
                      maxLines: height >= 40 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ),
                ),
                if (done) Icon(Icons.check, size: 16, color: green),
                if (running && !done) Icon(Icons.play_arrow_rounded, size: 18, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------- Nächste Lektion
class _NextLessonCard extends StatelessWidget {
  const _NextLessonCard({required this.library, required this.now, required this.onOpen});
  final LibraryController library;
  final DateTime now;
  final void Function(Student s) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final units = teachingUnits(library).toList();
    final next = nextLesson(units, now, isFree: (d) => library.calendar.freeOn(d) != null);
    final active = library.students.where((s) => !s.archived && !s.isGroup).length;
    final today = DateTime(now.year, now.month, now.day);
    String when(DateTime d, Student s) {
      final days = d.difference(today).inDays;
      final day = switch (days) {
        0 => tr('Heute', 'Today'),
        1 => tr('Morgen', 'Tomorrow'),
        _ => '${weekdayName(d.weekday)}, ${d.day}.${d.month}.',
      };
      return s.time == null ? day : tr('$day, ${s.time} Uhr', '$day, ${s.time}');
    }

    return _Card(
      icon: Icons.schedule,
      title: tr('Nächste Lektion', 'Next lesson'),
      onTap: next == null ? null : () => onOpen(next.student),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: next == null
                ? Text(
                    tr('In den nächsten 7 Tagen keine.', 'None in the next 7 days.'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            next.student.isGroup ? Icons.groups_outlined : Icons.person_outline,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              next.student.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(when(next.day, next.student), style: theme.textTheme.bodyMedium),
                      if (next.student.instrument.isNotEmpty)
                        Text(
                          next.student.instrument,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
            child: Text(tr('$active aktiv', '$active active'), style: theme.textTheme.labelMedium),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- To-Dos
class _TodosCard extends StatelessWidget {
  const _TodosCard({required this.library, required this.onTodos});
  final LibraryController library;
  final VoidCallback onTodos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final open = sortTodos(library.todos.where((t) => !t.done));
    final overdue = open.where((t) => t.overdue(now)).length;
    final due = open.where((t) => t.due != null && DateUtils.isSameDay(t.due, now)).length;
    return _Card(
      icon: Icons.check_box_outlined,
      title: tr('To-Dos', 'To-dos'),
      onTap: onTodos,
      trailing: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: tr('Neues To-Do', 'New to-do'),
        icon: const Icon(Icons.add, size: 20),
        onPressed: () => showTodoDialog(context, library, chooseStudent: true),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (open.isEmpty)
            Text(tr('Nichts offen 🎉', 'Nothing open 🎉'), style: theme.textTheme.bodyMedium)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Grosse, feine Zahl.
                Text(
                  '${open.length}',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w300, height: 1),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    tr(open.length == 1 ? 'offenes To-Do' : 'offene To-Dos', 'open'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          if (overdue > 0)
            Text(
              tr('$overdue überfällig', '$overdue overdue'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          if (due > 0)
            Text(
              tr('$due heute fällig', '$due due today'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary),
            ),
          if (open.isNotEmpty) ...[
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                open.take(3).map((t) => '· ${t.text}').join('\n'),
                overflow: TextOverflow.fade,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- Tipps
class _TipsCard extends StatefulWidget {
  const _TipsCard();

  @override
  State<_TipsCard> createState() => _TipsCardState();
}

class _TipsCardState extends State<_TipsCard> {
  final _pages = PageController();
  int _page = 0;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    // Alle 12 s der nächste Tipp.
    _auto = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted || !_pages.hasClients) return;
      final next = (_page + 1) % _tips.length;
      _pages.animateToPage(next, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tips = _tips;
    return _Card(
      icon: Icons.lightbulb_outline,
      title: tr('Tipps', 'Tips'),
      child: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final t in tips)
                  Align(
                    alignment: Alignment.topLeft,
                    child: Text(t, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < tips.length; i++)
                GestureDetector(
                  onTap: () =>
                      _pages.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                  child: Container(
                    width: i == _page ? 9 : 6,
                    height: i == _page ? 9 : 6,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? scheme.primary : scheme.outlineVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- Geburtstage
class _BirthdaysCard extends StatelessWidget {
  const _BirthdaysCard({required this.library, required this.now, required this.onOpen});
  final LibraryController library;
  final DateTime now;
  final void Function(Student s) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final list = upcomingBirthdays(library.students, now, days: 30);
    String when(int d) {
      if (d == 0) return tr('heute', 'today');
      if (d == 1) return tr('morgen', 'tomorrow');
      final day = DateTime(now.year, now.month, now.day + d);
      return d < 7 ? weekdayName(day.weekday) : '${day.day}.${day.month}.';
    }

    return _Card(
      icon: Icons.cake_outlined,
      title: tr('Geburtstage', 'Birthdays'),
      child: list.isEmpty
          ? Text(
              tr('In den nächsten 30 Tagen keine.', 'None in the next 30 days.'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final b in list)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => onOpen(library.groupOf(b.student.id) ?? b.student),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 84,
                            child: Text(
                              when(b.inDays),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: b.inDays == 0 ? scheme.primary : scheme.onSurfaceVariant,
                                fontWeight: b.inDays == 0 ? FontWeight.w700 : null,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              b.inDays == 0
                                  ? tr('${b.student.name} wird ${b.age}! 🎉', '${b.student.name} turns ${b.age}! 🎉')
                                  : tr('${b.student.name} wird ${b.age}', '${b.student.name} turns ${b.age}'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
