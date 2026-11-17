import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/teaching/school_level.dart';
import '../../core/teaching/student.dart';

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
  late final _phone = TextEditingController(text: s.phone);
  late int? _weekday = s.weekday;
  late TimeOfDay? _time = _parse(s.time);
  late int _duration = s.duration;
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
    for (final c in [_name, _instrument, _place, _email, _phone]) {
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
      ..phone = _phone.text.trim()
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
      title: Text(widget.isNew ? tr('Neue:r Schüler:in', 'New student') : tr('Angaben', 'Details')),
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
                    child: DropdownButtonFormField<int>(
                      initialValue: [20, 25, 30, 40, 45, 50, 60, 90].contains(_duration) ? _duration : null,
                      decoration: deco(tr('Dauer', 'Length')),
                      items: [
                        for (final m in [20, 25, 30, 40, 45, 50, 60, 90])
                          DropdownMenuItem(value: m, child: Text(tr('$m Minuten', '$m minutes'))),
                      ],
                      onChanged: (v) => setState(() => _duration = v ?? _duration),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _place,
                decoration: deco(tr('Ort', 'Place'), tr('z. B. Musikschule', 'e.g. music school')),
              ),
              const SizedBox(height: 20),
              Text(tr('Geburtstag und Klasse', 'Birthday and class'), style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cake_outlined, size: 18),
                    label: Text(_birthday == null ? tr('Geburtstag eintragen', 'Add birthday') : longDate(_birthday!)),
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
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: deco(tr('Handy (WhatsApp)', 'Mobile (WhatsApp)'), '079 123 45 67'),
              ),
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
