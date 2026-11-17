import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../core/teaching/school_level.dart';
import '../../core/teaching/student.dart';
import '../library/library_controller.dart';
import 'homework_share.dart' show formatPhone;

/// Namen der Wochentage (1 = Montag).
String weekdayName(int d) => switch (d) {
  1 => tr('Montag', 'Monday'),
  2 => tr('Dienstag', 'Tuesday'),
  3 => tr('Mittwoch', 'Wednesday'),
  4 => tr('Donnerstag', 'Thursday'),
  5 => tr('Freitag', 'Friday'),
  6 => tr('Samstag', 'Saturday'),
  _ => tr('Sonntag', 'Sunday'),
};

/// „Dienstag, 11:25–11:50 · 25 Minuten · Gitarre“
String studentSummary(Student s) {
  final parts = <String>[
    if (s.weekday != null)
      s.time == null ? weekdayName(s.weekday!) : '${weekdayName(s.weekday!)}, ${s.time}–${s.endTime}',
    if (s.weekday != null || s.time != null) tr('${s.duration} Minuten', '${s.duration} minutes'),
    if (s.instrument.isNotEmpty) s.instrument,
    if (s.place.isNotEmpty) s.place,
    ?levelLabel(s.currentLevel()),
    if (s.birthday != null)
      tr('${ageOn(s.birthday!, DateTime.now())} Jahre', '${ageOn(s.birthday!, DateTime.now())} years'),
  ];
  return parts.join(' · ');
}

/// Klassenstufe zum Anzeigen („P4“, „S2“; ohne bekannten Zug „Oberstufe 1“).
String? levelLabel(String? code) {
  if (code == null) return null;
  if (code.startsWith('O')) return tr('Oberstufe ${code.substring(1)}', 'Upper school ${code.substring(1)}');
  return code;
}

/// Datum lang, z. B. „9. Dezember 2015“.
String longDate(DateTime d) {
  const de = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  const en = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return tr('${d.day}. ${de[d.month - 1]} ${d.year}', '${d.day} ${en[d.month - 1]} ${d.year}');
}

/// Angaben zur Person bearbeiten. Gibt true zurück, wenn gespeichert werden soll.
Future<bool> showStudentDialog(BuildContext context, Student s, {bool isNew = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _StudentDialog(student: s, isNew: isNew),
    ) ??
    false;

class _StudentDialog extends StatefulWidget {
  const _StudentDialog({required this.student, required this.isNew});
  final Student student;
  final bool isNew;

  @override
  State<_StudentDialog> createState() => _StudentDialogState();
}

class _StudentDialogState extends State<_StudentDialog> {
  Student get s => widget.student;
  late final _name = TextEditingController(text: s.name);
  late final _instrument = TextEditingController(text: s.instrument);
  late final _place = TextEditingController(text: s.place);
  late final _email = TextEditingController(text: s.email);
  late final _phone = TextEditingController(text: formatPhone(s.phone));
  late int? _weekday = s.weekday;
  late TimeOfDay? _time = _parse(s.time);
  late int _duration = s.duration;
  late final _durationText = TextEditingController(text: '${s.duration}');
  late DateTime? _birthday = s.birthday;

  /// Heutige Klassenstufe (Kürzel), null = keine Angabe.
  late String? _level = s.currentLevel();

  static TimeOfDay? _parse(String? t) {
    if (t == null) return null;
    final parts = t.split(':');
    final h = int.tryParse(parts[0]), m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
  }

  static String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    for (final c in [_name, _instrument, _place, _email, _phone, _durationText]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    s
      ..name = _name.text.trim()
      ..instrument = _instrument.text.trim()
      ..place = _place.text.trim()
      ..email = _email.text.trim()
      ..phone = formatPhone(_phone.text)
      ..weekday = _weekday
      ..time = _time == null ? null : _fmt(_time!)
      ..duration = _duration
      ..birthday = _birthday
      ..touch();
    // Klassenstufe: die heutige mit dem heutigen Schuljahr speichern.
    final level = _level;
    if (level != s.currentLevel()) {
      s
        ..level = level
        ..levelYear = level == null ? null : SchoolLevel.schoolYearOf(DateTime.now());
      if (level != null && SchoolLevel.tracks.contains(level[0])) s.track = level[0];
      if (level == null) s.track = null;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration deco(String label, [String? hint]) => InputDecoration(labelText: label, hintText: hint);
    return AlertDialog(
      title: Text(
        widget.isNew
            ? (s.isGroup ? tr('Neue Gruppe', 'New group') : tr('Neue:r Schüler:in', 'New student'))
            : tr('Angaben', 'Details'),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: widget.isNew,
                decoration: deco(tr('Name', 'Name')),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              TextField(controller: _instrument, decoration: deco(tr('Instrument', 'Instrument'))),
              const SizedBox(height: 20),
              Text(tr('Unterricht', 'Lessons'), style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 6; d++)
                    ChoiceChip(
                      label: Text(weekdayName(d).substring(0, 2)),
                      tooltip: weekdayName(d),
                      selected: _weekday == d,
                      onSelected: (on) => setState(() => _weekday = on ? d : null),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_time == null ? tr('Zeit wählen', 'Choose time') : _fmt(_time!)),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _time ?? const TimeOfDay(hour: 14, minute: 0),
                        initialEntryMode: TimePickerEntryMode.input,
                        builder: (c, child) =>
                            MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
                      );
                      if (t != null) setState(() => _time = t);
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _durationText,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: deco(tr('Dauer (Minuten)', 'Length (minutes)')),
                      onChanged: (v) {
                        final m = int.tryParse(v);
                        if (m != null && m > 0) _duration = m;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _place,
                decoration: deco(tr('Ort', 'Place'), tr('z. B. Musikschule', 'e.g. music school')),
              ),
              // Bei einer Gruppe stehen Geburtstag, Klasse und Kontakt bei den Mitgliedern.
              if (!s.isGroup) ...[
                const SizedBox(height: 20),
                Text(tr('Geburtstag und Klasse', 'Birthday and class'), style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cake_outlined, size: 18),
                      label: Text(
                        _birthday == null ? tr('Geburtstag eintragen', 'Add birthday') : longDate(_birthday!),
                      ),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _birthday ?? DateTime(DateTime.now().year - 10, 1, 1),
                          firstDate: DateTime(1920),
                          lastDate: DateTime.now(),
                          initialDatePickerMode: DatePickerMode.year,
                        );
                        if (d != null) setState(() => _birthday = d);
                      },
                    ),
                    if (_birthday != null)
                      IconButton(
                        tooltip: tr('Entfernen', 'Remove'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _birthday = null),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    'Klasse heute (steigt jedes Jahr Mitte Juli von selbst um eine Stufe)',
                    'Class today (goes up by one every year in mid-July)',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(tr('keine', 'none')),
                      selected: _level == null,
                      onSelected: (_) => setState(() => _level = null),
                    ),
                    for (var i = 1; i <= 6; i++)
                      ChoiceChip(
                        label: Text('P$i'),
                        selected: _level == 'P$i',
                        onSelected: (_) => setState(() => _level = 'P$i'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final t in SchoolLevel.tracks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 120, child: Text(SchoolLevel.trackName(t), style: theme.textTheme.bodySmall)),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (var i = 1; i <= 3; i++)
                              ChoiceChip(
                                label: Text('$t$i'),
                                selected: _level == '$t$i',
                                onSelected: (_) => setState(() => _level = '$t$i'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Text(tr('Kontakt (für die Hausaufgaben)', 'Contact (for homework)'), style: theme.textTheme.labelLarge),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: deco(tr('E-Mail', 'Email')),
                ),
                const SizedBox(height: 8),
                // Beim Verlassen des Feldes schön schreiben (078 876 54 32).
                Focus(
                  onFocusChange: (has) {
                    final f = formatPhone(_phone.text);
                    if (!has && f != _phone.text) _phone.text = f;
                  },
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: deco(tr('Handy (WhatsApp)', 'Mobile (WhatsApp)'), '078 876 54 32'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: _save, child: Text(widget.isNew ? tr('Anlegen', 'Create') : tr('Speichern', 'Save'))),
      ],
    );
  }
}

/// Mitglieder einer Gruppe wählen (mindestens zwei). [group]: bestehende Gruppe
/// zum Bearbeiten. Gibt die IDs zurück oder null.
Future<List<String>?> showGroupMembersDialog(BuildContext context, LibraryController library, {Student? group}) {
  // Wählbar: einzelne, aktive Karteien, die nicht schon in einer anderen Gruppe sind.
  final candidates = library.students.where((s) {
    if (s.isGroup || s.archived) return false;
    final g = library.groupOf(s.id);
    return g == null || g.id == group?.id;
  }).toList();
  final chosen = {...?group?.members};
  return showDialog<List<String>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialog) => AlertDialog(
        title: Text(group == null ? tr('Gruppe bilden', 'Make group') : tr('Mitglieder', 'Members')),
        content: SizedBox(
          width: 400,
          child: candidates.length < 2 && group == null
              ? Text(
                  tr(
                    'Lege zuerst mindestens zwei Schüler:innen einzeln an. Dann kannst du sie hier zusammenfassen.',
                    'First create at least two students individually. Then you can combine them here.',
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      tr(
                        'Die Gruppe bekommt eine gemeinsame Kartei für Lektionen und Hausaufgaben. '
                            'Absenzen, Geburtstag und Klasse bleiben bei jeder Person.',
                        'The group gets a shared record for lessons and homework. '
                            'Absences, birthday and class stay with each person.',
                      ),
                      style: Theme.of(c).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    for (final s in candidates)
                      CheckboxListTile(
                        value: chosen.contains(s.id),
                        title: Text(s.name),
                        subtitle: Text(studentSummary(s)),
                        onChanged: (v) => setDialog(() => v == true ? chosen.add(s.id) : chosen.remove(s.id)),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(
            onPressed: chosen.length < 2
                ? null
                : () => Navigator.of(c).pop([
                    for (final s in candidates)
                      if (chosen.contains(s.id)) s.id,
                  ]),
            child: Text(group == null ? tr('Weiter', 'Next') : tr('Übernehmen', 'Apply')),
          ),
        ],
      ),
    ),
  );
}
