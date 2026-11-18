import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/floating_actions.dart';
import '../../app/l10n.dart';
import '../../core/teaching/student.dart';
import '../library/library_actions.dart';
import '../library/library_controller.dart';
import '../library/sync_controller.dart';
import 'homework_share.dart' show shortDate;
import '../../core/teaching/school_level.dart';
import 'student_dialog.dart';
import 'attendance_table.dart' show absenceBackground;
import 'student_page.dart';
import 'absence_pdf.dart';
import 'dashboard.dart';
import 'timetable.dart';
import 'todo_widgets.dart';

/// Bereich „Unterricht“ (nur sichtbar, wenn unter ⚙ eingeschaltet).
///
/// Aufbau (Wunsch des Besitzers): eine zweite, schmale
/// Menüleiste mit Unterrichten, Schüler:innen, Stundenplan und Absenzen.
/// „Unterrichten“ zeigt eine Person über die ganze Breite, unten rechts
/// schwebt eine kleine Leiste mit Suche und ← → zur vorigen/nächsten Person.
class TeachingView extends StatefulWidget {
  const TeachingView({super.key, required this.library, required this.sync, required this.reset, required this.active});

  final LibraryController library;
  final SyncController sync;
  final ValueListenable<int> reset;
  final bool active;

  @override
  State<TeachingView> createState() => _TeachingViewState();
}

enum _Section { dashboard, teach, students, timetable, absences, todos }

class _TeachingViewState extends State<TeachingView> with LibraryActions {
  @override
  LibraryController get library => widget.library;
  @override
  SyncController get syncController => widget.sync;

  _Section _section = _Section.dashboard;

  /// Person in „Unterrichten“ (ID). Ohne Wahl: wer jetzt bzw. als Nächstes dran ist.
  String? _current;

  @override
  void initState() {
    super.initState();
    widget.reset.addListener(_onReset);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    widget.reset.removeListener(_onReset);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// ← → wechseln in „Unterrichten“ zur vorigen bzw. nächsten Person,
  /// ausser während man tippt oder ein Fenster offen ist.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    final key = e.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft && key != LogicalKeyboardKey.arrowRight) return false;
    if (!mounted || !widget.active || _section != _Section.teach) return false;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed || keys.isShiftPressed) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText || focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final order = _ordered;
    final current = _currentStudent(order);
    if (current == null) return false;
    final i = order.indexWhere((x) => x.id == current.id);
    final j = key == LogicalKeyboardKey.arrowLeft ? i - 1 : i + 1;
    if (i < 0 || j < 0 || j >= order.length) return true;
    _open(order[j]);
    return true;
  }

  /// Nochmals auf „Unterricht“ getippt: zurück zur Übersicht.
  void _onReset() => setState(() => _section = _Section.dashboard);

  void _open(Student s) => setState(() {
    _current = s.id;
    _section = _Section.teach;
  });

  Future<void> _add() async {
    final draft = Student.create('');
    if (!await showStudentDialog(context, draft, isNew: true)) return;
    final s = await library.saveStudent(draft);
    if (mounted) _open(s);
  }

  /// Mehrere Schüler:innen zu einer Gruppe zusammenfassen (eine Kartei für alle).
  Future<void> _createGroup() async {
    final members = await showGroupMembersDialog(context, library);
    if (members == null || members.length < 2 || !mounted) return;
    final first = library.studentById(members.first)!;
    final group = Student.create(members.map((id) => library.studentById(id)!.name).join(' & '))
      ..members.addAll(members)
      ..instrument = first.instrument
      ..weekday = first.weekday
      ..time = first.time
      ..duration = first.duration
      ..place = first.place;
    if (!await showStudentDialog(context, group, isNew: true)) return;
    final saved = await library.saveStudent(group);
    if (mounted) _open(saved);
  }

  /// Reihenfolge wie im Stundenplan, beginnend mit heute.
  List<Student> get _ordered {
    final today = DateTime.now().weekday;
    int dayRank(Student s) => s.weekday == null ? 99 : (s.weekday! - today + 7) % 7;
    return teachingUnits(library).toList()..sort((a, b) {
      final c = dayRank(a).compareTo(dayRank(b));
      if (c != 0) return c;
      final t = a.minutes.compareTo(b.minutes);
      return t != 0 ? t : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  /// Wer jetzt bzw. als Nächstes Unterricht hat (sonst die erste Person).
  Student? _currentStudent(List<Student> order) {
    final chosen = _current == null ? null : library.studentById(_current!);
    if (chosen != null) return chosen;
    if (order.isEmpty) return null;
    final now = DateTime.now();
    final minute = now.hour * 60 + now.minute;
    for (final s in order) {
      if (s.weekday == now.weekday && s.minutes + s.duration > minute) return s;
    }
    return order.first;
  }

  Future<void> _search(List<Student> order) async {
    final picked = await showDialog<Student>(
      context: context,
      builder: (_) => _StudentSearch(students: [...order, ...library.students.where((s) => s.archived)]),
    );
    if (picked != null) _open(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final order = _ordered;
        final current = _currentStudent(order);
        Widget content;
        switch (_section) {
          case _Section.teach:
            if (current == null) {
              content = _Empty(actions: headerActions(), onAdd: _add, archivedOnly: library.students.isNotEmpty);
            } else {
              final i = order.indexWhere((x) => x.id == current.id);
              content = Stack(
                children: [
                  Positioned.fill(
                    child: StudentPage(
                      key: ValueKey(current.id),
                      library: library,
                      studentId: current.id,
                      actions: headerActions(),
                      onDeleted: () => setState(() => _current = null),
                      onOpen: _open,
                      banner: BirthdayBanner(students: library.students, onOpen: _open),
                    ),
                  ),
                  // Schwebende Leiste: suchen, vorige, nächste Person.
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: _NavPill(
                      onSearch: () => _search(order),
                      onPrevious: i > 0 ? () => _open(order[i - 1]) : null,
                      onNext: i >= 0 && i < order.length - 1 ? () => _open(order[i + 1]) : null,
                    ),
                  ),
                ],
              );
            }
          case _Section.students:
            content = _StudentsSection(state: this);
          case _Section.timetable:
            content = TimetableView(library: library, actions: headerActions(), onOpen: _open);
          case _Section.absences:
            content = _AbsencesSection(state: this);
          case _Section.dashboard:
            content = DashboardView(
              library: library,
              actions: headerActions(),
              onOpen: _open,
              onAdd: _add,
              onTimetable: () => setState(() => _section = _Section.timetable),
              onTodos: () => setState(() => _section = _Section.todos),
            );
          case _Section.todos:
            content = _TodosSection(state: this);
        }
        return Row(
          children: [
            // Zweite Menüleiste des Unterrichts.
            NavigationRail(
              backgroundColor: scheme.surfaceContainerLow.withValues(alpha: 0.6),
              minWidth: 76,
              selectedIndex: _section.index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _section = _Section.values[i]),
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: const Icon(Icons.dashboard),
                  label: Text(tr('Übersicht', 'Overview')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.co_present_outlined),
                  selectedIcon: const Icon(Icons.co_present),
                  label: Text(tr('Unterrichten', 'Teach')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.people_outline),
                  selectedIcon: const Icon(Icons.people),
                  label: Text(tr('Schüler:innen', 'Students')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.calendar_month_outlined),
                  selectedIcon: const Icon(Icons.calendar_month),
                  label: Text(tr('Stundenplan', 'Timetable')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.event_busy_outlined),
                  selectedIcon: const Icon(Icons.event_busy),
                  label: Text(tr('Absenzen', 'Absences')),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.checklist_outlined),
                  selectedIcon: const Icon(Icons.checklist),
                  label: Text(tr('To-Dos', 'To-dos')),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

/// Kopfzeile eines Unterrichts-Bereichs (Titel links, Knöpfe rechts).
class TeachingTopBar extends StatelessWidget {
  const TeachingTopBar({super.key, required this.title, this.subtitle, this.trailing = const []});
  final String title;
  final String? subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({required this.onSearch, this.onPrevious, this.onNext});
  final VoidCallback onSearch;
  final VoidCallback? onPrevious, onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget round(IconData icon, String tip, VoidCallback? onTap) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      // Gleiches Seegrün wie die schwebenden Knöpfe unten rechts.
      child: IconButton.filled(
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
        ),
      ),
    );
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            round(Icons.search, tr('Schüler:in suchen', 'Find student'), onSearch),
            const SizedBox(width: 18),
            round(Icons.arrow_back, tr('Vorherige:r', 'Previous'), onPrevious),
            round(Icons.arrow_forward, tr('Nächste:r', 'Next'), onNext),
          ],
        ),
      ),
    );
  }
}

/// Suchen und eine Person wählen.
class _StudentSearch extends StatefulWidget {
  const _StudentSearch({required this.students});
  final List<Student> students;

  @override
  State<_StudentSearch> createState() => _StudentSearchState();
}

class _StudentSearchState extends State<_StudentSearch> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final hits = widget.students
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q) || s.instrument.toLowerCase().contains(q))
        .toList();
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Name oder Instrument', 'Name or instrument'),
              ),
              onChanged: (v) => setState(() => _q = v),
              onSubmitted: (_) {
                if (hits.isNotEmpty) Navigator.of(context).pop(hits.first);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final s in hits)
                    ListTile(
                      title: Text(s.name),
                      subtitle: Text(studentSummary(s)),
                      trailing: s.archived ? Text(tr('Archiv', 'Archive')) : null,
                      onTap: () => Navigator.of(context).pop(s),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alle Schüler:innen nach Wochentag, mit „Neue:r Schüler:in“.
class _StudentsSection extends StatefulWidget {
  const _StudentsSection({required this.state});
  final _TeachingViewState state;

  @override
  State<_StudentsSection> createState() => _StudentsSectionState();
}

class _StudentsSectionState extends State<_StudentsSection> {
  bool _archive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lib = widget.state.library;
    final active = teachingUnits(lib).toList();
    final archived = lib.students.where((s) => s.archived).toList();
    // Jedes Kind einzeln zählen (auch in Gruppen), Gruppen extra.
    final people = lib.students.where((s) => !s.archived && !s.isGroup).length;
    final groups = active.where((s) => s.isGroup).length;
    final days = [
      for (var d = 1; d <= 7; d++)
        if (active.any((s) => s.weekday == d)) d,
    ];
    final noDay = active.where((s) => s.weekday == null).toList();
    Widget tile(Student s) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(s.isGroup ? Icons.groups_outlined : Icons.person_outline, color: scheme.primary),
          title: Text(s.name),
          subtitle: Text(studentSummary(s)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.state._open(s),
        ),
        // Mitglieder einer Gruppe eingerückt (für Geburtstag, Klasse, Kontakt).
        if (s.isGroup)
          for (final id in s.members)
            if (lib.studentById(id) case final m?)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 72, right: 16),
                title: Text(m.name),
                subtitle: Text(studentSummary(m)),
                onTap: () => widget.state._open(m),
              ),
      ],
    );
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
      ),
    );
    return FloatingActions(
      actions: [
        floatingAction(
          tag: 'group',
          icon: Icons.groups_outlined,
          label: tr('Gruppe bilden', 'Make group'),
          onPressed: widget.state._createGroup,
        ),
        floatingAction(
          tag: 'student',
          icon: Icons.add,
          label: tr('Neue:r Schüler:in', 'New student'),
          onPressed: widget.state._add,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeachingTopBar(
            title: tr('Schüler:innen', 'Students'),
            subtitle: tr(
              '$people aktiv${groups == 0 ? '' : ' · $groups ${groups == 1 ? 'Gruppe' : 'Gruppen'}'}',
              '$people active${groups == 0 ? '' : ' · $groups ${groups == 1 ? 'group' : 'groups'}'}',
            ),
            trailing: widget.state.headerActions(),
          ),
          const Divider(height: 1),
          BirthdayBanner(students: lib.students, onOpen: widget.state._open),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
              children: [
                if (lib.students.isEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text(tr('Noch niemand erfasst.', 'Nobody yet.'))),
                for (final d in days) ...[header(weekdayName(d)), for (final s in studentsOn(active, d)) tile(s)],
                if (noDay.isNotEmpty) ...[header(tr('Ohne festen Tag', 'No fixed day')), ...noDay.map(tile)],
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    leading: Icon(_archive ? Icons.expand_less : Icons.expand_more),
                    title: Text(tr('Archiv (${archived.length})', 'Archive (${archived.length})')),
                    onTap: () => setState(() => _archive = !_archive),
                  ),
                  if (_archive) ...archived.map(tile),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Absenzen aller Schüler:innen, jüngste zuerst.
class _AbsencesSection extends StatelessWidget {
  const _AbsencesSection({required this.state});
  final _TeachingViewState state;

  /// Semester, Orte und Spalten wählen, dann das PDF öffnen.
  Future<void> _exportPdf(BuildContext anchor) async {
    final lib = state.library;
    final choice = await showAbsenceExportDialog(anchor, lib);
    if (choice == null || !anchor.mounted) return;
    final sem = choice.semester;
    final rows = absenceRows(lib.students, lib.groupOf);
    await openPdfBytes(
      anchor,
      () => buildAbsencePdf(rows, lib.calendar, sem, options: choice.options),
      tr('Absenzenliste ${sem.name}.pdf', 'Attendance ${sem.name}.pdf').replaceAll(RegExp(r'[\\/:*?"<>|]'), ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = [
      for (final s in state.library.students)
        for (final l in s.activeLessons)
          if (l.status != LessonStatus.held && l.status != LessonStatus.makeUp) (student: s, lesson: l),
    ]..sort((a, b) => b.lesson.date.compareTo(a.lesson.date));
    final start = schoolYearStart();
    final thisYear = rows.where((r) => !r.lesson.date.isBefore(start)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TeachingTopBar(
          title: tr('Absenzen', 'Absences'),
          subtitle: tr('$thisYear seit August', '$thisYear since August'),
          trailing: [
            Builder(
              builder: (anchor) => TextButton.icon(
                onPressed: () => _exportPdf(anchor),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(tr('Absenzenliste als PDF', 'Attendance list as PDF')),
              ),
            ),
            const SizedBox(width: 4),
            ...state.headerActions(),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr(
                        'Keine Absenzen. Eintragen kannst du sie in der Absenzenkontrolle unter dem Namen einer Person.',
                        'No absences. You can add them in the attendance table below a person’s name.',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
                  children: [
                    for (final r in rows)
                      ListTile(
                        leading: SizedBox(
                          width: 92,
                          child: Text(shortDate(r.lesson.date), style: theme.textTheme.bodyMedium),
                        ),
                        tileColor: absenceBackground(r.lesson.status, theme.brightness),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        title: Text(r.student.name),
                        subtitle: r.lesson.reason.isEmpty ? null : Text(r.lesson.reason),
                        trailing: LessonStatusBadge(r.lesson),
                        onTap: () => state._open(r.student),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Noch niemand erfasst.
class _Empty extends StatelessWidget {
  const _Empty({required this.actions, required this.onAdd, this.archivedOnly = false});
  final List<Widget> actions;
  final VoidCallback onAdd;

  /// Es gibt Karteien, aber alle liegen im Archiv.
  final bool archivedOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TeachingTopBar(title: tr('Unterrichten', 'Teach'), trailing: actions),
        const Divider(height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.co_present_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    archivedOnly
                        ? tr(
                            'Alle Karteien liegen im Archiv. Unter „Schüler:innen“ findest du sie, oder lege eine neue an.',
                            'All records are archived. You find them under “Students”, or create a new one.',
                          )
                        : tr(
                            'Lege für jede Schülerin und jeden Schüler eine Kartei an: Lektionen, Hausaufgaben und Stücke aus deiner Bibliothek an einem Ort.',
                            'Create a record for each student: lessons, homework and pieces from your library in one place.',
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
}

/// Schüler:innen mit Geburtstag heute oder in den nächsten 7 Tagen.
List<({Student student, int inDays, int age})> upcomingBirthdays(List<Student> students, DateTime now, {int days = 7}) {
  final out = [
    for (final s in students)
      if (!s.archived && s.birthday != null && daysUntilBirthday(s.birthday!, now) <= days)
        (
          student: s,
          inDays: daysUntilBirthday(s.birthday!, now),
          age: ageOn(s.birthday!, nextBirthday(s.birthday!, now)),
        ),
  ]..sort((a, b) => a.inDays.compareTo(b.inDays));
  return out;
}

/// Hinweis auf Geburtstage dieser Woche (heute hervorgehoben). Antippen öffnet die Kartei.
class BirthdayBanner extends StatelessWidget {
  const BirthdayBanner({super.key, required this.students, required this.onOpen});
  final List<Student> students;
  final void Function(Student s) onOpen;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final list = upcomingBirthdays(students, now);
    if (list.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    String when(int d) {
      if (d == 0) return tr('heute', 'today');
      if (d == 1) return tr('morgen', 'tomorrow');
      final day = DateTime(now.year, now.month, now.day + d);
      return weekdayName(day.weekday);
    }

    return Container(
      color: scheme.tertiaryContainer.withValues(alpha: 0.45),
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
      child: Row(
        children: [
          Icon(Icons.cake_outlined, color: scheme.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final b in list)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: b.inDays == 0 ? scheme.tertiaryContainer : null,
                    label: Text(
                      b.inDays == 0
                          ? tr(
                              'Heute: ${b.student.name} wird ${b.age}! 🎉',
                              'Today: ${b.student.name} turns ${b.age}! 🎉',
                            )
                          : tr(
                              '${when(b.inDays)}: ${b.student.name} wird ${b.age}',
                              '${when(b.inDays)}: ${b.student.name} turns ${b.age}',
                            ),
                    ),
                    onPressed: () => onOpen(b.student),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Was im Unterricht als eigene Kartei erscheint: alle aktiven Karteien
/// ausser den Mitgliedern einer (aktiven) Gruppe – für sie gilt die Gruppe.
Iterable<Student> teachingUnits(LibraryController library) =>
    library.students.where((s) => !s.archived && library.groupOf(s.id) == null);

/// Alle To-Dos: offene nach Termin, erledigte eingeklappt.
class _TodosSection extends StatefulWidget {
  const _TodosSection({required this.state});
  final _TeachingViewState state;

  @override
  State<_TodosSection> createState() => _TodosSectionState();
}

class _TodosSectionState extends State<_TodosSection> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lib = widget.state.library;
    final all = sortTodos(lib.todos);
    final open = all.where((t) => !t.done).toList();
    final done = all.where((t) => t.done).toList();
    void openStudent(String id) {
      final s = lib.studentById(id);
      if (s != null) widget.state._open(s);
    }

    return FloatingActions(
      actions: [
        floatingAction(
          tag: 'todo',
          icon: Icons.add,
          label: tr('Neues To-Do', 'New to-do'),
          onPressed: () => showTodoDialog(context, lib, chooseStudent: true),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeachingTopBar(
            title: tr('To-Dos', 'To-dos'),
            subtitle: tr('${open.length} offen', '${open.length} open'),
            trailing: widget.state.headerActions(),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                if (open.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr('Nichts offen. 🎉', 'Nothing open. 🎉'), style: theme.textTheme.bodyLarge),
                  ),
                for (final t in open) TodoTile(todo: t, library: lib, showStudent: true, onOpenStudent: openStudent),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    leading: Icon(_showDone ? Icons.expand_less : Icons.expand_more),
                    title: Text(tr('Erledigt (${done.length})', 'Done (${done.length})')),
                    onTap: () => setState(() => _showDone = !_showDone),
                  ),
                  if (_showDone)
                    for (final t in done)
                      TodoTile(todo: t, library: lib, showStudent: true, onOpenStudent: openStudent),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
