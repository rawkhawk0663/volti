import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/teaching/student.dart';
import '../library/library_actions.dart';
import '../library/library_controller.dart';
import '../library/sync_controller.dart';
import 'homework_share.dart' show shortDate;
import 'student_dialog.dart';
import 'student_page.dart';
import 'timetable.dart';

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

enum _Section { teach, students, timetable, absences }

class _TeachingViewState extends State<TeachingView> with LibraryActions {
  @override
  LibraryController get library => widget.library;
  @override
  SyncController get syncController => widget.sync;

  _Section _section = _Section.teach;

  /// Person in „Unterrichten“ (ID). Ohne Wahl: wer jetzt bzw. als Nächstes dran ist.
  String? _current;

  @override
  void initState() {
    super.initState();
    widget.reset.addListener(_onReset);
  }

  @override
  void dispose() {
    widget.reset.removeListener(_onReset);
    super.dispose();
  }

  /// Nochmals auf „Unterricht“ getippt: zurück zu „Unterrichten“.
  void _onReset() => setState(() => _section = _Section.teach);

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

  /// Reihenfolge wie im Stundenplan, beginnend mit heute.
  List<Student> get _ordered {
    final today = DateTime.now().weekday;
    int dayRank(Student s) => s.weekday == null ? 99 : (s.weekday! - today + 7) % 7;
    return library.students.where((s) => !s.archived).toList()..sort((a, b) {
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
              content = _Empty(actions: headerActions(), onAdd: _add);
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
      child: IconButton.filledTonal(tooltip: tip, onPressed: onTap, icon: Icon(icon)),
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
    final active = lib.students.where((s) => !s.archived).toList();
    final archived = lib.students.where((s) => s.archived).toList();
    final days = [
      for (var d = 1; d <= 7; d++)
        if (active.any((s) => s.weekday == d)) d,
    ];
    final noDay = active.where((s) => s.weekday == null).toList();
    Widget tile(Student s) => ListTile(
      title: Text(s.name),
      subtitle: Text(studentSummary(s)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => widget.state._open(s),
    );
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TeachingTopBar(
          title: tr('Schüler:innen', 'Students'),
          subtitle: tr('${active.length} aktiv', '${active.length} active'),
          trailing: [
            FilledButton.icon(
              onPressed: widget.state._add,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: Text(tr('Neue:r Schüler:in', 'New student')),
            ),
            const SizedBox(width: 8),
            ...widget.state.headerActions(),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
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
    );
  }
}

/// Absenzen aller Schüler:innen, jüngste zuerst.
class _AbsencesSection extends StatelessWidget {
  const _AbsencesSection({required this.state});
  final _TeachingViewState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = [
      for (final s in state.library.students)
        for (final l in s.activeLessons)
          if (l.status != LessonStatus.held) (student: s, lesson: l),
    ]..sort((a, b) => b.lesson.date.compareTo(a.lesson.date));
    final start = schoolYearStart();
    final thisYear = rows.where((r) => !r.lesson.date.isBefore(start)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TeachingTopBar(
          title: tr('Absenzen', 'Absences'),
          subtitle: tr('$thisYear seit August', '$thisYear since August'),
          trailing: state.headerActions(),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr(
                        'Keine Absenzen. Eintragen kannst du sie bei einer Person über ⋮ neben „Neue Lektion“.',
                        'No absences. You can add them for a person via ⋮ next to “New lesson”.',
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
  const _Empty({required this.actions, required this.onAdd});
  final List<Widget> actions;
  final VoidCallback onAdd;

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
                    tr(
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
