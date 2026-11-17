import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/teaching/student.dart';
import '../library/library_controller.dart';
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

/// Dauer als „1 h 15 min“ bzw. „45 min“.
String durationText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')} min';
}

/// Übersicht über den Tag: heutige Lektionen (jetzt / als Nächstes),
/// Geburtstage, offene To-Dos und der nächste Unterrichtstag.
class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.library,
    required this.actions,
    required this.onOpen,
    required this.onAdd,
  });

  final LibraryController library;
  final List<Widget> actions;
  final void Function(Student s) onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final units = teachingUnits(library).toList();
    final free = library.calendar.freeOn(today);
    final lessons = lessonsOn(units, today);
    final minutes = lessons.fold<int>(0, (sum, s) => sum + s.duration);
    final todos = sortTodos(library.todos.where((t) => !t.done));
    final next = nextTeachingDay(units, now, isFree: (d) => library.calendar.freeOn(d) != null);

    void openId(String id) {
      final s = library.studentById(id);
      if (s != null) onOpen(s);
    }

    final header = [
      TeachingTopBar(
        title: tr('Übersicht', 'Overview'),
        subtitle: '${weekdayName(today.weekday)}, ${longDate(today)}',
        trailing: actions,
      ),
      const Divider(height: 1),
      BirthdayBanner(students: library.students, onOpen: onOpen),
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
                        'Hier siehst du jeden Tag, wer wann Unterricht hat, dazu Geburtstage und offene To-Dos.',
                        'Here you see each day who has a lesson when, plus birthdays and open to-dos.',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onAdd,
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

    // ------------------------------------------------ Heute
    final nowMinute = now.hour * 60 + now.minute;
    final nextIndex = lessons.indexWhere((s) => s.time != null && s.minutes > nowMinute);
    Widget lessonCard(Student s, int i) {
      final hasTime = s.time != null;
      final running = hasTime && s.minutes <= nowMinute && nowMinute < s.minutes + s.duration;
      final past = hasTime && s.minutes + s.duration <= nowMinute;
      final isNext =
          i == nextIndex &&
          !lessons.any((x) => x.time != null && x.minutes <= nowMinute && nowMinute < x.minutes + x.duration);
      final recorded = s.lessonOn(today) != null;
      final open = todos.where((t) => t.student == s.id).length;
      final badge = running
          ? tr('jetzt', 'now')
          : isNext
          ? tr(
              'als Nächstes · in ${durationText(s.minutes - nowMinute)}',
              'next · in ${durationText(s.minutes - nowMinute)}',
            )
          : null;
      final members = [for (final id in s.members) ?library.studentById(id)];
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: running ? scheme.primaryContainer.withValues(alpha: 0.55) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: running || isNext ? scheme.primary : scheme.outlineVariant, width: running ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onOpen(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.time ?? '–',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: past ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      if (s.endTime != null)
                        Text(s.endTime!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(
                  s.isGroup ? Icons.groups_outlined : Icons.person_outline,
                  color: past ? scheme.onSurfaceVariant : scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: theme.textTheme.titleMedium?.copyWith(color: past ? scheme.onSurfaceVariant : null),
                      ),
                      Text(
                        [
                          tr('${s.duration} Min.', '${s.duration} min'),
                          if (s.instrument.isNotEmpty) s.instrument,
                          if (s.place.isNotEmpty) s.place,
                          if (members.isNotEmpty) members.map((m) => m.name.split(' ').first).join(', '),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (open > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Tooltip(
                      message: tr('$open offene To-Dos', '$open open to-dos'),
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(Icons.checklist, size: 16, color: scheme.primary),
                        label: Text('$open'),
                      ),
                    ),
                  ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: running ? scheme.primary : scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: running ? scheme.onPrimary : scheme.primary,
                        ),
                      ),
                    ),
                  ),
                if (recorded)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Tooltip(
                      message: tr('Eingetragen', 'Recorded'),
                      child: Icon(Icons.check_circle, color: scheme.primary, size: 20),
                    ),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
    }

    final todaySection = <Widget>[
      _SectionTitle(
        tr('Heute', 'Today'),
        detail: lessons.isEmpty
            ? null
            : tr(
                '${lessons.length} ${lessons.length == 1 ? 'Lektion' : 'Lektionen'} · ${durationText(minutes)}'
                    '${lessons.first.time != null && lessons.last.endTime != null ? ' · ${lessons.first.time}–${lessons.last.endTime}' : ''}',
                '${lessons.length} ${lessons.length == 1 ? 'lesson' : 'lessons'} · ${durationText(minutes)}'
                    '${lessons.first.time != null && lessons.last.endTime != null ? ' · ${lessons.first.time}–${lessons.last.endTime}' : ''}',
              ),
      ),
      if (free != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF4A90D9).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.beach_access_outlined, color: Color(0xFF4A90D9)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  free.holiday
                      ? tr('Heute ist ${free.name}: kein Unterricht.', 'Today is ${free.name}: no lessons.')
                      : tr('${free.name}: heute kein Unterricht.', '${free.name}: no lessons today.'),
                ),
              ),
            ],
          ),
        ),
      if (free == null && lessons.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            tr('Heute hast du keinen Unterricht.', 'No lessons today.'),
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      if (free == null)
        for (var i = 0; i < lessons.length; i++) lessonCard(lessons[i], i),
      if (next != null) ...[
        const SizedBox(height: 18),
        _SectionTitle(
          next.day.difference(today).inDays == 1
              ? tr('Morgen', 'Tomorrow')
              : '${weekdayName(next.day.weekday)}, ${next.day.day}.${next.day.month}.',
          detail: tr(
            '${next.lessons.length} ${next.lessons.length == 1 ? 'Lektion' : 'Lektionen'}',
            '${next.lessons.length} ${next.lessons.length == 1 ? 'lesson' : 'lessons'}',
          ),
        ),
        for (final s in next.lessons)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 4, right: 4),
            leading: SizedBox(width: 48, child: Text(s.time ?? '–', style: theme.textTheme.titleSmall)),
            title: Text(s.name),
            subtitle: s.instrument.isEmpty ? null : Text(s.instrument),
            trailing: Icon(s.isGroup ? Icons.groups_outlined : Icons.person_outline, size: 18),
            onTap: () => onOpen(s),
          ),
      ],
      const SizedBox(height: 24),
    ];

    // ------------------------------------------------ To-Dos
    final todoSection = <Widget>[
      _SectionTitle(
        tr('To-Dos', 'To-dos'),
        detail: todos.isEmpty ? null : tr('${todos.length} offen', '${todos.length} open'),
        trailing: IconButton(
          tooltip: tr('Neues To-Do', 'New to-do'),
          icon: const Icon(Icons.add),
          onPressed: () => showTodoDialog(context, library, chooseStudent: true),
        ),
      ),
      if (todos.isEmpty)
        Text(
          tr('Nichts offen. 🎉', 'Nothing open. 🎉'),
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      for (final t in todos) TodoTile(todo: t, library: library, showStudent: true, onOpenStudent: openId),
      const SizedBox(height: 24),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...header,
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 900
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 24), children: todaySection),
                      ),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 380,
                        child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 16, 24), children: todoSection),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [...todaySection, ...todoSection],
                  ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.detail, this.trailing});
  final String title;
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (detail != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                detail!,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
