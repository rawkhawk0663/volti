import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Unterricht (für Instrumental-Lehrpersonen): eine Schülerin oder ein
/// Schüler mit Stücken aus der Bibliothek (Repertoire) und dem
/// Lektions-Tagebuch.
///
/// Gespeichert als `Bibliothek/.volti/students/<id>.json` (Format
/// `volti-student` v1). Beim Sync wird zusammengeführt: die Angaben zur
/// Person als Ganzes (jüngste Fassung gewinnt), Stücke und Lektionen pro
/// Eintrag (jüngste Fassung gewinnt, gelöscht bleibt gelöscht). So geht
/// nichts verloren, wenn auf zwei Geräten Lektionen erfasst werden.
///
/// Notizen in den Noten gehören zur Ebene mit `scope` = [scope]. Sie sind
/// nur in dieser Kartei sichtbar, nie in der Bibliothek oder in Setlists.
class Student {
  Student({
    required this.id,
    required this.name,
    required this.modified,
    this.instrument = '',
    this.email = '',
    this.phone = '',
    this.weekday,
    this.time,
    this.duration = 45,
    this.place = '',
    this.group = '',
    this.notes = '',
    this.archived = false,
    Map<String, StudentPiece>? pieces,
    Map<String, Lesson>? lessons,
    Map<String, StudentNote>? memos,
  }) : pieces = pieces ?? {},
       lessons = lessons ?? {},
       memos = memos ?? {};

  factory Student.create(String name) =>
      Student(id: const Uuid().v4(), name: name.trim(), modified: DateTime.now().toUtc());

  final String id;
  String name;
  String instrument;
  String email;

  /// Für WhatsApp (mit Ländervorwahl, z. B. +41 79 …).
  String phone;

  /// Unterrichtstag (1 = Montag … 7 = Sonntag), null = kein fester Tag.
  int? weekday;

  /// Beginn als „HH:MM“, null = keine feste Zeit.
  String? time;

  /// Dauer in Minuten.
  int duration;
  String place;

  /// Gruppe, z. B. Musikschule oder Ensemble (frei, zum Filtern).
  String group;
  String notes;
  bool archived;

  /// Letzte Änderung der Angaben zur Person (nicht der Stücke/Lektionen).
  DateTime modified;

  final Map<String, StudentPiece> pieces;
  final Map<String, Lesson> lessons;

  /// Notiz-Karten (z. B. „Infos“: Geburtstag, Klasse …), pro Eintrag abgeglichen.
  final Map<String, StudentNote> memos;

  /// Notiz-Karten ohne gelöschte, älteste zuerst.
  List<StudentNote> get activeMemos =>
      memos.values.where((m) => !m.deleted).toList()..sort((a, b) => a.created.compareTo(b.created));

  void putMemo(StudentNote m) => memos[m.id] = m;

  /// Kennzeichen der Notiz-Ebenen dieser Kartei in den Noten.
  String get scope => scopeOf(id);
  static String scopeOf(String id) => 'student-$id';
  static bool isStudentScope(String? scope) => scope != null && scope.startsWith('student-');

  void touch() => modified = DateTime.now().toUtc();

  /// Stücke ohne gelöschte, älteste zuerst.
  List<StudentPiece> get activePieces =>
      pieces.values.where((x) => !x.deleted).toList()..sort((a, b) => a.added.compareTo(b.added));

  /// Lektionen ohne gelöschte, jüngste zuerst.
  List<Lesson> get activeLessons => lessons.values.where((l) => !l.deleted).toList()
    ..sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.created.compareTo(a.created);
    });

  /// Lektion an diesem Tag (falls schon erfasst).
  Lesson? lessonOn(DateTime day) {
    for (final l in activeLessons) {
      if (sameDay(l.date, day)) return l;
    }
    return null;
  }

  /// Minuten seit Mitternacht (zum Sortieren), ohne Zeit ganz hinten.
  int get minutes {
    final t = time;
    if (t == null) return 24 * 60;
    final parts = t.split(':');
    return (int.tryParse(parts[0]) ?? 24) * 60 + (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
  }

  /// Ende der Lektion als „HH:MM“.
  String? get endTime {
    if (time == null) return null;
    final m = minutes + duration;
    return '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  void putPiece(StudentPiece piece) => pieces[piece.id] = piece;
  void putLesson(Lesson lesson) => lessons[lesson.id] = lesson;

  Map<String, dynamic> toJson() => {
    'format': 'volti-student',
    'version': 1,
    'id': id,
    'name': name,
    'modified': modified.toUtc().toIso8601String(),
    if (instrument.isNotEmpty) 'instrument': instrument,
    if (email.isNotEmpty) 'email': email,
    if (phone.isNotEmpty) 'phone': phone,
    'weekday': ?weekday,
    'time': ?time,
    'duration': duration,
    if (place.isNotEmpty) 'place': place,
    if (group.isNotEmpty) 'group': group,
    if (notes.isNotEmpty) 'notes': notes,
    if (archived) 'archived': true,
    'pieces': [for (final x in pieces.values) x.toJson()],
    'lessons': [for (final l in lessons.values) l.toJson()],
    if (memos.isNotEmpty) 'memos': [for (final m in memos.values) m.toJson()],
  };

  static Student fromJson(Map<String, dynamic> j) => Student(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    modified: DateTime.parse(j['modified'] as String),
    instrument: j['instrument'] as String? ?? '',
    email: j['email'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    weekday: (j['weekday'] as num?)?.toInt(),
    time: j['time'] as String?,
    duration: (j['duration'] as num?)?.toInt() ?? 45,
    place: j['place'] as String? ?? '',
    group: j['group'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    archived: j['archived'] as bool? ?? false,
    pieces: {
      for (final piece in (j['pieces'] as List? ?? const []).map(StudentPiece.tryFromJson).nonNulls) piece.id: piece,
    },
    lessons: {
      for (final lesson in (j['lessons'] as List? ?? const []).map(Lesson.tryFromJson).nonNulls) lesson.id: lesson,
    },
    memos: {for (final m in (j['memos'] as List? ?? const []).map(StudentNote.tryFromJson).nonNulls) m.id: m},
  );

  /// Zwei Fassungen derselben Kartei zusammenführen (Sync).
  static Student merge(Student a, Student b) {
    final newer = b.modified.isAfter(a.modified) ? b : a;
    final out = Student.fromJson(newer.toJson())
      ..pieces.clear()
      ..lessons.clear()
      ..memos.clear();
    // Sortiert, damit das Ergebnis auf beiden Geräten gleich aussieht.
    for (final id in ({...a.pieces.keys, ...b.pieces.keys}.toList()..sort())) {
      out.pieces[id] = _newest(a.pieces[id], b.pieces[id], (x) => x.modified)!;
    }
    for (final id in ({...a.lessons.keys, ...b.lessons.keys}.toList()..sort())) {
      out.lessons[id] = _newest(a.lessons[id], b.lessons[id], (x) => x.modified)!;
    }
    for (final id in ({...a.memos.keys, ...b.memos.keys}.toList()..sort())) {
      out.memos[id] = _newest(a.memos[id], b.memos[id], (x) => x.modified)!;
    }
    return out;
  }

  static T? _newest<T>(T? a, T? b, DateTime Function(T) at) {
    if (a == null) return b;
    if (b == null) return a;
    return at(b).isAfter(at(a)) ? b : a;
  }
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Wie weit ein Stück ist.
enum PieceStatus { practising, learned, done }

/// Ein Stück aus der Bibliothek in der Kartei (Repertoire).
class StudentPiece {
  StudentPiece({
    required this.id,
    required this.relativePath,
    required this.added,
    required this.modified,
    this.bookmark,
    this.label,
    this.status = PieceStatus.practising,
    this.deleted = false,
  });

  factory StudentPiece.create(String relativePath, {String? bookmark, String? label}) {
    final now = DateTime.now().toUtc();
    return StudentPiece(
      id: const Uuid().v4(),
      relativePath: relativePath,
      bookmark: bookmark,
      label: label,
      added: now,
      modified: now,
    );
  }

  final String id;

  /// Pfad relativ zur Bibliothek (z. B. `Noten/x.pdf`), wie bei Setlists.
  final String relativePath;
  final String? bookmark;
  final String? label;
  PieceStatus status;
  final DateTime added;
  DateTime modified;
  bool deleted;

  void touch() => modified = DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': relativePath,
    'bookmark': ?bookmark,
    'label': ?label,
    'status': status.name,
    'added': added.toUtc().toIso8601String(),
    'modified': modified.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static StudentPiece? tryFromJson(Object? o) {
    try {
      final j = o as Map<String, dynamic>;
      return StudentPiece(
        id: j['id'] as String,
        relativePath: j['path'] as String,
        bookmark: j['bookmark'] as String?,
        label: j['label'] as String?,
        status: PieceStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => PieceStatus.practising),
        added: DateTime.parse(j['added'] as String),
        modified: DateTime.parse(j['modified'] as String),
        deleted: j['deleted'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Wie eine Lektion stattgefunden hat (Absenzenkontrolle).
enum LessonStatus {
  /// Normal gehalten.
  held,

  /// Schüler:in hat sich abgemeldet (entschuldigt).
  excused,

  /// Schüler:in fehlte ohne Abmeldung.
  missed,

  /// Lehrperson hat abgesagt.
  cancelled,

  /// Nachgeholte Lektion.
  makeUp,
}

/// Eine Lektion im Tagebuch.
class Lesson {
  Lesson({
    required this.id,
    required this.date,
    required this.created,
    required this.modified,
    this.status = LessonStatus.held,
    this.reason = '',
    this.content = '',
    this.homework = '',
    List<String>? pieces,
    this.deleted = false,
  }) : pieces = pieces ?? [];

  factory Lesson.create(DateTime date) {
    final now = DateTime.now().toUtc();
    return Lesson(id: const Uuid().v4(), date: DateTime(date.year, date.month, date.day), created: now, modified: now);
  }

  final String id;

  /// Tag der Lektion (lokal, ohne Uhrzeit).
  DateTime date;
  LessonStatus status;

  /// Grund bei einer Absenz.
  String reason;

  /// Was gemacht wurde.
  String content;
  String homework;

  /// IDs der Stücke ([StudentPiece.id]), die drankamen.
  final List<String> pieces;
  final DateTime created;
  DateTime modified;
  bool deleted;

  bool get isAbsence => status == LessonStatus.excused || status == LessonStatus.missed;

  void touch() => modified = DateTime.now().toUtc();

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': _day(date),
    'status': status.name,
    if (reason.isNotEmpty) 'reason': reason,
    if (content.isNotEmpty) 'content': content,
    if (homework.isNotEmpty) 'homework': homework,
    if (pieces.isNotEmpty) 'pieces': pieces,
    'created': created.toUtc().toIso8601String(),
    'modified': modified.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static Lesson? tryFromJson(Object? o) {
    try {
      final j = o as Map<String, dynamic>;
      final d = (j['date'] as String).split('-').map(int.parse).toList();
      return Lesson(
        id: j['id'] as String,
        date: DateTime(d[0], d[1], d[2]),
        status: LessonStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => LessonStatus.held),
        reason: j['reason'] as String? ?? '',
        content: j['content'] as String? ?? '',
        homework: j['homework'] as String? ?? '',
        pieces: [for (final x in j['pieces'] as List? ?? const []) x as String],
        created: DateTime.parse(j['created'] as String),
        modified: DateTime.parse(j['modified'] as String),
        deleted: j['deleted'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Eine Notiz-Karte (Titel und Text), z. B. „Infos“.
class StudentNote {
  StudentNote({
    required this.id,
    required this.created,
    required this.modified,
    this.title = '',
    this.text = '',
    this.deleted = false,
  });

  factory StudentNote.create({String title = '', String text = ''}) {
    final now = DateTime.now().toUtc();
    return StudentNote(id: const Uuid().v4(), created: now, modified: now, title: title, text: text);
  }

  final String id;
  String title;
  String text;
  final DateTime created;
  DateTime modified;
  bool deleted;

  void touch() => modified = DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
    'id': id,
    if (title.isNotEmpty) 'title': title,
    if (text.isNotEmpty) 'text': text,
    'created': created.toUtc().toIso8601String(),
    'modified': modified.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static StudentNote? tryFromJson(Object? o) {
    try {
      final j = o as Map<String, dynamic>;
      return StudentNote(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        created: DateTime.parse(j['created'] as String),
        modified: DateTime.parse(j['modified'] as String),
        deleted: j['deleted'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Speichert die Karteien als einzelne Dateien in `.volti/students`.
class StudentStore {
  StudentStore(this.libraryRoot);
  final String libraryRoot;

  static const dir = '.volti/students';

  Directory get _dir => Directory(p.join(libraryRoot, '.volti', 'students'));
  File _file(String id) => File(p.join(_dir.path, '$id.json'));

  Future<List<Student>> loadAll() async {
    if (!await _dir.exists()) return [];
    final result = <Student>[];
    await for (final f in _dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        result.add(Student.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // Unlesbare Datei überspringen, nicht löschen.
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// Speichern; liegt auf der Festplatte inzwischen eine andere Fassung
  /// (z. B. vom Sync), wird zusammengeführt. Gibt die gespeicherte Fassung zurück.
  Future<Student> save(Student s) async {
    await _dir.create(recursive: true);
    final file = _file(s.id);
    var out = s;
    try {
      if (await file.exists()) {
        final disk = Student.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
        out = Student.merge(disk, s);
      }
    } catch (_) {}
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encode(out), flush: true);
    await tmp.rename(file.path);
    return out;
  }

  Future<void> delete(Student s) async {
    final f = _file(s.id);
    if (await f.exists()) await f.delete();
  }

  static String encode(Student s) => const JsonEncoder.withIndent(' ').convert(s.toJson());
}
