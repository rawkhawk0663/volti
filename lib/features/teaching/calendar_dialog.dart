import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/teaching/school_calendar.dart';
import '../library/library_controller.dart';
import 'homework_share.dart' show shortDate;

/// Semester, Ferien und Feiertage für alle Schüler:innen bearbeiten.
/// Ferien und Feiertage erscheinen in jeder Absenzenkontrolle (blau bzw. „F“).
Future<void> showCalendarDialog(BuildContext context, LibraryController library) => showDialog<void>(
  context: context,
  builder: (_) => _CalendarDialog(library: library),
);

class _CalendarDialog extends StatefulWidget {
  const _CalendarDialog({required this.library});
  final LibraryController library;

  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends State<_CalendarDialog> {
  // Eine Kopie bearbeiten; gespeichert wird bei „Fertig“.
  late final SchoolCalendar _cal = SchoolCalendar.fromJson(widget.library.calendar.toJson());
  late final List<Semester> _semesters = _cal.semesters.isEmpty
      ? [
          for (final s in SchoolCalendar.defaultSemesters(DateTime.now()))
            if (!s.end.isBefore(DateTime.now())) s,
        ]
      : [..._cal.semesters];
  bool _changed = false;

  void _touch() => setState(() => _changed = true);

  Future<DateTimeRange?> _range(DateTime start, DateTime end) => showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    initialDateRange: DateTimeRange(start: start, end: end),
  );

  Future<void> _addSemester() async {
    final now = DateTime.now();
    final r = await _range(DateTime(now.year, now.month, now.day), DateTime(now.year, now.month + 5, now.day));
    if (r == null) return;
    _semesters.add(
      Semester(
        id: 'sem-${DateTime.now().microsecondsSinceEpoch}',
        name: tr('Semester', 'Term'),
        start: r.start,
        end: r.end,
      ),
    );
    _touch();
  }

  Future<void> _addFree({required bool holiday}) async {
    final now = DateTime.now();
    if (holiday) {
      final d = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (d == null) return;
      _cal.free.add(FreePeriod.create(name: tr('Feiertag', 'Public holiday'), start: d, holiday: true));
    } else {
      final r = await _range(DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day + 13));
      if (r == null) return;
      _cal.free.add(FreePeriod.create(name: tr('Ferien', 'Holidays'), start: r.start, end: r.end));
    }
    _touch();
  }

  void _addSwiss() {
    final list = _semesters..sort((a, b) => a.start.compareTo(b.start));
    final from = list.isEmpty ? DateTime(DateTime.now().year, 1, 1) : list.first.start;
    final to = list.isEmpty ? DateTime(DateTime.now().year, 12, 31) : list.last.end;
    for (final h in swissHolidays(from, to)) {
      final exists = _cal.free.any((f) => f.holiday && f.start == h.start);
      if (!exists) _cal.free.add(h);
    }
    _touch();
  }

  Future<void> _save() async {
    if (_changed) {
      _cal.semesters
        ..clear()
        ..addAll(_semesters);
      await widget.library.saveCalendar(_cal);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final free = [..._cal.free]..sort((a, b) => a.start.compareTo(b.start));
    String range(DateTime a, DateTime b) => a == b ? shortDate(a) : '${shortDate(a)} – ${shortDate(b)}';

    Widget nameField(String value, ValueChanged<String> onChanged) => TextFormField(
      initialValue: value,
      decoration: const InputDecoration(isDense: true, border: InputBorder.none),
      onChanged: (v) {
        onChanged(v);
        _changed = true;
      },
    );

    return AlertDialog(
      title: Text(tr('Semester, Ferien und Feiertage', 'Terms and holidays')),
      content: SizedBox(
        width: 560,
        height: 520,
        child: ListView(
          children: [
            Text(
              tr(
                'Gilt für alle Schüler:innen. Ferien und Feiertage erscheinen in jeder Absenzenkontrolle und '
                    'lassen sich dort nicht ändern.',
                'Applies to all students. Holidays appear in every attendance table and cannot be changed there.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text(tr('Semester', 'Terms'), style: theme.textTheme.titleSmall)),
                TextButton.icon(
                  onPressed: _addSemester,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Semester', 'Term')),
                ),
              ],
            ),
            for (final s in _semesters)
              Row(
                children: [
                  Expanded(child: nameField(s.name, (v) => s.name = v)),
                  TextButton(
                    onPressed: () async {
                      final r = await _range(s.start, s.end);
                      if (r == null) return;
                      s
                        ..start = r.start
                        ..end = r.end;
                      _touch();
                    },
                    child: Text(range(s.start, s.end)),
                  ),
                  IconButton(
                    tooltip: tr('Entfernen', 'Remove'),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _semesters.remove(s);
                      _touch();
                    },
                  ),
                ],
              ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(child: Text(tr('Ferien und Feiertage', 'Holidays'), style: theme.textTheme.titleSmall)),
                TextButton.icon(
                  onPressed: () => _addFree(holiday: false),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Ferien', 'Holidays')),
                ),
                TextButton.icon(
                  onPressed: () => _addFree(holiday: true),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Feiertag', 'Public holiday')),
                ),
              ],
            ),
            if (free.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  tr('Noch keine eingetragen.', 'None yet.'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            for (final f in free)
              Row(
                key: ValueKey(f.id),
                children: [
                  Container(
                    width: 26,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A90D9).withValues(alpha: f.holiday ? 0.35 : 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: f.holiday
                        ? const Text('F', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: nameField(f.name, (v) => f.name = v)),
                  TextButton(
                    onPressed: () async {
                      if (f.holiday) {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: f.start,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (d == null) return;
                        f
                          ..start = d
                          ..end = d;
                      } else {
                        final r = await _range(f.start, f.end);
                        if (r == null) return;
                        f
                          ..start = r.start
                          ..end = r.end;
                      }
                      _touch();
                    },
                    child: Text(range(f.start, f.end)),
                  ),
                  IconButton(
                    tooltip: tr('Entfernen', 'Remove'),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _cal.free.remove(f);
                      _touch();
                    },
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _addSwiss,
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Schweizer Feiertage eintragen', 'Add Swiss public holidays')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: _save, child: Text(tr('Fertig', 'Done'))),
      ],
    );
  }
}
