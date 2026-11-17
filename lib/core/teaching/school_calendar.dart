import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../app/l10n.dart';

/// Ein Semester (bzw. eine Zeitspanne für die Absenzenkontrolle).
class Semester {
  Semester({required this.id, required this.name, required this.start, required this.end});
  final String id;
  String name;
  DateTime start, end;

  bool contains(DateTime d) => !_day(d).isBefore(start) && !_day(d).isAfter(end);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'start': _fmt(start), 'end': _fmt(end)};
  static Semester? tryFromJson(Object? o) {
    try {
      final j = o as Map<String, dynamic>;
      return Semester(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        start: _parse(j['start'] as String),
        end: _parse(j['end'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Ferien (mehrere Tage) oder ein Feiertag – an diesen Tagen ist kein Unterricht.
class FreePeriod {
  FreePeriod({required this.id, required this.name, required this.start, required this.end, this.holiday = false});

  factory FreePeriod.create({required String name, required DateTime start, DateTime? end, bool holiday = false}) =>
      FreePeriod(id: const Uuid().v4(), name: name, start: _day(start), end: _day(end ?? start), holiday: holiday);

  final String id;
  String name;
  DateTime start, end;

  /// Feiertag (in der Tabelle „F“), sonst Ferien.
  bool holiday;

  bool contains(DateTime d) => !_day(d).isBefore(start) && !_day(d).isAfter(end);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': _fmt(start),
    'end': _fmt(end),
    if (holiday) 'holiday': true,
  };
  static FreePeriod? tryFromJson(Object? o) {
    try {
      final j = o as Map<String, dynamic>;
      return FreePeriod(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        start: _parse(j['start'] as String),
        end: _parse(j['end'] as String),
        holiday: j['holiday'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Schulkalender des Unterrichts: Semester sowie Ferien und Feiertage.
/// Gilt für alle Schüler:innen und wird zentral beim Stundenplan gepflegt.
///
/// Gespeichert als `Bibliothek/.volti/teaching.json` (Format `volti-teaching`
/// v1). Beim Sync gewinnt die jüngste Fassung als Ganzes.
class SchoolCalendar {
  SchoolCalendar({List<Semester>? semesters, List<FreePeriod>? free, this.modified})
    : semesters = semesters ?? [],
      free = free ?? [];

  final List<Semester> semesters;
  final List<FreePeriod> free;
  DateTime? modified;

  static const file = '.volti/teaching.json';

  void touch() => modified = DateTime.now().toUtc();

  /// Eingetragene Semester, sonst Herbst- und Frühlingssemester wie an
  /// Schweizer Schulen (August–Januar, Februar–Juli).
  List<Semester> get effectiveSemesters {
    final list = semesters.isEmpty ? defaultSemesters(DateTime.now()) : [...semesters];
    return list..sort((a, b) => a.start.compareTo(b.start));
  }

  static List<Semester> defaultSemesters(DateTime around) => [
    for (var y = around.year - 1; y <= around.year + 1; y++) ...[
      Semester(
        id: 'hs-$y',
        name: tr('Herbstsemester $y', 'Autumn term $y'),
        start: DateTime(y, 8, 1),
        end: DateTime(y + 1, 1, 31),
      ),
      Semester(
        id: 'fs-${y + 1}',
        name: tr('Frühlingssemester ${y + 1}', 'Spring term ${y + 1}'),
        start: DateTime(y + 1, 2, 1),
        end: DateTime(y + 1, 7, 31),
      ),
    ],
  ];

  /// Semester, in dem [d] liegt (sonst das nächste davor bzw. danach).
  Semester semesterFor(DateTime d) {
    final list = effectiveSemesters;
    for (final s in list) {
      if (s.contains(d)) return s;
    }
    for (final s in list) {
      if (s.start.isAfter(d)) return s;
    }
    return list.last;
  }

  /// Ferien oder Feiertag an diesem Tag (Feiertage zuerst).
  FreePeriod? freeOn(DateTime d) {
    FreePeriod? found;
    for (final f in free) {
      if (!f.contains(d)) continue;
      if (f.holiday) return f;
      found ??= f;
    }
    return found;
  }

  Map<String, dynamic> toJson() => {
    'format': 'volti-teaching',
    'version': 1,
    'modified': ?modified?.toUtc().toIso8601String(),
    'semesters': [for (final s in semesters) s.toJson()],
    'free': [for (final f in free) f.toJson()],
  };

  static SchoolCalendar fromJson(Map<String, dynamic> j) => SchoolCalendar(
    modified: j['modified'] == null ? null : DateTime.parse(j['modified'] as String),
    semesters: (j['semesters'] as List? ?? const []).map(Semester.tryFromJson).nonNulls.toList(),
    free: (j['free'] as List? ?? const []).map(FreePeriod.tryFromJson).nonNulls.toList(),
  );

  static Future<SchoolCalendar> load(String libraryRoot) async {
    try {
      final f = File(p.joinAll([libraryRoot, ...file.split('/')]));
      if (!await f.exists()) return SchoolCalendar();
      return fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return SchoolCalendar();
    }
  }

  Future<void> save(String libraryRoot) async {
    final f = File(p.joinAll([libraryRoot, ...file.split('/')]));
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(toJson()), flush: true);
    await tmp.rename(f.path);
  }
}

/// Unterrichtstage eines Semesters für den Wochentag [weekday] (1 = Montag).
List<DateTime> lessonDates(Semester s, int weekday) {
  var d = s.start;
  while (d.weekday != weekday) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return [for (; !d.isAfter(s.end); d = DateTime(d.year, d.month, d.day + 7)) d];
}

/// Kalenderwoche nach ISO 8601 (Woche mit dem ersten Donnerstag = 1).
int isoWeek(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final firstOfYear = DateTime.utc(thursday.year, 1, 1);
  return thursday.difference(firstOfYear).inDays ~/ 7 + 1;
}

/// Ostersonntag (gregorianisch, Gauss/Anonymer Algorithmus).
DateTime easterSunday(int year) {
  final a = year % 19, b = year ~/ 100, c = year % 100;
  final d = b ~/ 4, e = b % 4, f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4, k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = (h + l - 7 * m + 114) % 31 + 1;
  return DateTime(year, month, day);
}

/// Verbreitete Schweizer Feiertage zwischen [from] und [to] (kantonal kann es
/// abweichen; man kann sie danach einzeln löschen).
List<FreePeriod> swissHolidays(DateTime from, DateTime to) {
  final out = <FreePeriod>[];
  for (var y = from.year; y <= to.year; y++) {
    final easter = easterSunday(y);
    DateTime plus(int days) => DateTime(easter.year, easter.month, easter.day + days);
    final days = <(DateTime, String)>[
      (DateTime(y, 1, 1), tr('Neujahr', 'New Year')),
      (DateTime(y, 1, 2), tr('Berchtoldstag', 'St Berchtold’s Day')),
      (plus(-2), tr('Karfreitag', 'Good Friday')),
      (plus(1), tr('Ostermontag', 'Easter Monday')),
      (plus(39), tr('Auffahrt', 'Ascension Day')),
      (plus(50), tr('Pfingstmontag', 'Whit Monday')),
      (DateTime(y, 8, 1), tr('Bundesfeier', 'Swiss National Day')),
      (DateTime(y, 12, 25), tr('Weihnachten', 'Christmas Day')),
      (DateTime(y, 12, 26), tr('Stephanstag', 'St Stephen’s Day')),
    ];
    for (final (d, name) in days) {
      if (!d.isBefore(_day(from)) && !d.isAfter(_day(to))) {
        out.add(FreePeriod.create(name: name, start: d, holiday: true));
      }
    }
  }
  return out;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _parse(String s) {
  final x = s.split('-').map(int.parse).toList();
  return DateTime(x[0], x[1], x[2]);
}
