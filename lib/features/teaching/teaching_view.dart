import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/teaching/student.dart';
import '../library/library_actions.dart';
import '../library/library_controller.dart';
import '../library/sync_controller.dart';
import 'student_dialog.dart';
import 'student_page.dart';
import 'timetable.dart';

/// Bereich „Unterricht“ (nur sichtbar, wenn unter ⚙ eingeschaltet).
///
/// Bewusst schlicht: links eine zweite, schmale Leiste mit den
/// Schüler:innen (nach Wochentag, heute zuoberst) und dem Stundenplan,
/// rechts die Seite der gewählten Person.
class TeachingView extends StatefulWidget {
  const TeachingView({super.key, required this.library, required this.sync, required this.reset, required this.active});

  final LibraryController library;
  final SyncController sync;
  final ValueListenable<int> reset;
  final bool active;

  @override
  State<TeachingView> createState() => _TeachingViewState();
}

/// Was rechts gezeigt wird.
const _timetable = '#stundenplan';

class _TeachingViewState extends State<TeachingView> with LibraryActions {
  @override
  LibraryController get library => widget.library;
  @override
  SyncController get syncController => widget.sync;

  /// ID der gewählten Person oder [_timetable].
  String? _selected;
  String _query = '';
  final _search = TextEditingController();
  bool _showArchive = false;

  @override
  void initState() {
    super.initState();
    widget.reset.addListener(_onReset);
  }

  @override
  void dispose() {
    widget.reset.removeListener(_onReset);
    _search.dispose();
    super.dispose();
  }

  void _select(String id) => setState(() => _selected = id);
  void _setQuery(String q) => setState(() => _query = q);
  void _toggleArchive() => setState(() => _showArchive = !_showArchive);

  /// Nochmals auf „Unterricht“ getippt: in der schmalen Ansicht zurück zur Liste.
  void _onReset() => setState(() => _selected = null);

  Future<void> _add() async {
    final draft = Student.create('');
    if (!await showStudentDialog(context, draft, isNew: true)) return;
    final s = await library.saveStudent(draft);
    if (mounted) setState(() => _selected = s.id);
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final selected = _selected;
        final student = selected == null || selected == _timetable ? null : library.studentById(selected);
        Widget? detail;
        if (selected == _timetable) {
          detail = TimetableView(
            library: library,
            actions: headerActions(),
            onOpen: (s) => setState(() => _selected = s.id),
            onBack: wide ? null : () => setState(() => _selected = null),
          );
        } else if (student != null) {
          final order = _ordered;
          final i = order.indexWhere((x) => x.id == student.id);
          detail = StudentPage(
            key: ValueKey(student.id),
            library: library,
            studentId: student.id,
            actions: headerActions(),
            onPrevious: i > 0 ? () => setState(() => _selected = order[i - 1].id) : null,
            onNext: i >= 0 && i < order.length - 1 ? () => setState(() => _selected = order[i + 1].id) : null,
            onDeleted: () => setState(() => _selected = null),
            onBack: wide ? null : () => setState(() => _selected = null),
          );
        }
        final list = _StudentList(state: this, selected: selected, ordered: _ordered);
        if (!wide) {
          return PopScope(
            canPop: !widget.active || detail == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && widget.active) setState(() => _selected = null);
            },
            child: detail ?? list,
          );
        }
        return Row(
          children: [
            SizedBox(width: 270, child: list),
            const VerticalDivider(width: 1),
            Expanded(
              child: detail ?? _Welcome(actions: headerActions(), onAdd: _add, empty: library.students.isEmpty),
            ),
          ],
        );
      },
    );
  }
}

/// Die zweite Leiste: Stundenplan und alle Schüler:innen.
class _StudentList extends StatelessWidget {
  const _StudentList({required this.state, required this.selected, required this.ordered});
  final _TeachingViewState state;
  final String? selected;
  final List<Student> ordered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = state._query.trim().toLowerCase();
    bool matches(Student s) => q.isEmpty || s.name.toLowerCase().contains(q) || s.instrument.toLowerCase().contains(q);
    final today = DateTime.now();
    final active = ordered.where(matches).toList();
    final archived = state.library.students.where((s) => s.archived && matches(s)).toList();

    final children = <Widget>[];
    int? lastDay = -1;
    for (final s in active) {
      if (s.weekday != lastDay) {
        lastDay = s.weekday;
        final label = s.weekday == null
            ? tr('Ohne festen Tag', 'No fixed day')
            : s.weekday == today.weekday
            ? tr('Heute · ${weekdayName(s.weekday!)}', 'Today · ${weekdayName(s.weekday!)}')
            : weekdayName(s.weekday!);
        children.add(_Header(label, highlight: s.weekday == today.weekday));
      }
      children.add(_tile(context, s, done: s.weekday == today.weekday && s.lessonOn(today) != null));
    }
    if (archived.isNotEmpty) {
      children.add(
        ListTile(
          dense: true,
          leading: Icon(state._showArchive ? Icons.expand_less : Icons.expand_more, size: 20),
          title: Text(tr('Archiv (${archived.length})', 'Archive (${archived.length})')),
          onTap: () => state._toggleArchive(),
        ),
      );
      if (state._showArchive) {
        for (final s in archived) {
          children.add(_tile(context, s, dim: true));
        }
      }
    }

    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                Expanded(child: Text(tr('Unterricht', 'Teaching'), style: theme.textTheme.titleLarge)),
                IconButton(
                  tooltip: tr('Neue:r Schüler:in', 'New student'),
                  icon: const Icon(Icons.person_add_alt),
                  onPressed: state._add,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: SearchBar(
              controller: state._search,
              hintText: tr('Suchen', 'Search'),
              elevation: const WidgetStatePropertyAll(0),
              constraints: const BoxConstraints(minHeight: 40),
              leading: const Icon(Icons.search, size: 20),
              trailing: [
                if (state._query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      state._search.clear();
                      state._setQuery('');
                    },
                  ),
              ],
              onChanged: state._setQuery,
            ),
          ),
          ListTile(
            dense: true,
            selected: selected == _timetable,
            selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.6),
            leading: const Icon(Icons.calendar_view_week_outlined),
            title: Text(tr('Stundenplan', 'Timetable'), style: theme.textTheme.titleSmall),
            onTap: () => state._select(_timetable),
          ),
          const Divider(height: 1),
          Expanded(
            child: state.library.students.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      tr(
                        'Noch niemand erfasst. Mit + legst du die erste Kartei an.',
                        'Nobody yet. Use + to add the first student.',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView(padding: const EdgeInsets.only(bottom: 24), children: children),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Student s, {bool done = false, bool dim = false}) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      selected: selected == s.id,
      selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.6),
      leading: SizedBox(
        width: 44,
        child: Text(
          s.time ?? '',
          style: TextStyle(fontFeatures: const [FontFeature.tabularFigures()], color: scheme.onSurfaceVariant),
        ),
      ),
      minLeadingWidth: 44,
      title: Text(
        s.name,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 15, color: dim ? scheme.onSurfaceVariant : null),
      ),
      subtitle: s.instrument.isEmpty ? null : Text(s.instrument, overflow: TextOverflow.ellipsis),
      // Heute schon erfasst: kleines Häkchen.
      trailing: done ? Icon(Icons.check_circle, size: 18, color: scheme.primary) : null,
      onTap: () => state._select(s.id),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, {this.highlight = false});
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: highlight ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Rechts, solange niemand gewählt ist.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.actions, required this.onAdd, required this.empty});
  final List<Widget> actions;
  final VoidCallback onAdd;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(children: [const Spacer(), ...actions]),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.school_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    empty
                        ? tr(
                            'Lege für jede Schülerin und jeden Schüler eine Kartei an: Lektionen, Hausaufgaben und Stücke aus deiner Bibliothek an einem Ort.',
                            'Create a record for each student: lessons, homework and pieces from your library in one place.',
                          )
                        : tr('Wähle links eine Schülerin oder einen Schüler.', 'Choose a student on the left.'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (empty) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.person_add_alt),
                      label: Text(tr('Erste Kartei anlegen', 'Create first record')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
