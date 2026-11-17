import '../../app/l10n.dart';

/// Klassenstufe einer Schülerin / eines Schülers.
///
/// Primarschule P1–P6, danach Oberstufe mit drei Jahren in einem von drei
/// Zügen: R (Realschule), S (Sekundarschule) oder B (Bezirksschule).
/// Die Stufe steigt jedes Jahr am 15. Juli (in den Sommerferien) um eins.
///
/// Gespeichert wird die Stufe, die beim Eintragen galt, und das Schuljahr
/// dazu ([schoolYearOf]); die heutige Stufe wird daraus berechnet.
class SchoolLevel {
  SchoolLevel._();

  /// Züge der Oberstufe.
  static const tracks = ['R', 'S', 'B'];

  static String trackName(String t) => switch (t) {
    'R' => tr('Realschule', 'Realschule'),
    'S' => tr('Sekundarschule', 'Sekundarschule'),
    _ => tr('Bezirksschule', 'Bezirksschule'),
  };

  /// Schuljahr eines Datums: Es beginnt am 15. Juli (Jahr dieses Tages).
  static int schoolYearOf(DateTime d) => (d.month > 7 || (d.month == 7 && d.day >= 15)) ? d.year : d.year - 1;

  /// Stufe als Zahl: P1–P6 = 0–5, Oberstufe 1–3 = 6–8. null = unbekannt.
  static int? indexOf(String? code) {
    if (code == null || code.length < 2) return null;
    final n = int.tryParse(code.substring(1));
    if (n == null) return null;
    final kind = code[0].toUpperCase();
    if (kind == 'P' && n >= 1 && n <= 6) return n - 1;
    if ((tracks.contains(kind) || kind == 'O') && n >= 1 && n <= 3) return 5 + n;
    return null;
  }

  /// Kürzel einer Stufe; in der Oberstufe ohne bekannten Zug „O1“ … „O3“.
  static String codeOf(int index, String? track) {
    if (index < 6) return 'P${index + 1}';
    return '${track ?? 'O'}${index - 5}';
  }

  /// Heutige Stufe (Kürzel) aus der eingetragenen Stufe [code] im Schuljahr
  /// [year]. Nach der Oberstufe: „fertig“ (null mit [finished] = true).
  static ({String? code, bool finished}) current(String? code, int? year, String? track, DateTime now) {
    final start = indexOf(code);
    if (start == null || year == null) return (code: null, finished: false);
    final i = start + (schoolYearOf(now) - year);
    if (i > 8) return (code: null, finished: true);
    if (i < 0) return (code: null, finished: false);
    // Den Zug aus dem eingetragenen Kürzel übernehmen, falls dort einer steht.
    final t = track ?? (code!.length > 1 && tracks.contains(code[0].toUpperCase()) ? code[0].toUpperCase() : null);
    return (code: codeOf(i, t), finished: false);
  }
}

/// Alter am Tag [now] (ganze Jahre).
int ageOn(DateTime birthday, DateTime now) {
  var age = now.year - birthday.year;
  if (now.month < birthday.month || (now.month == birthday.month && now.day < birthday.day)) age--;
  return age;
}

/// Nächster Geburtstag ab [now] (heute zählt mit).
DateTime nextBirthday(DateTime birthday, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  // 29. Februar in einem gewöhnlichen Jahr: am 28. feiern.
  DateTime inYear(int y) {
    final d = DateTime(y, birthday.month, birthday.day);
    return d.month != birthday.month ? DateTime(y, birthday.month + 1, 0) : d;
  }

  final thisYear = inYear(now.year);
  return thisYear.isBefore(today) ? inYear(now.year + 1) : thisYear;
}

/// In wie vielen Tagen ist der nächste Geburtstag (0 = heute).
int daysUntilBirthday(DateTime birthday, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return nextBirthday(birthday, now).difference(today).inDays;
}
