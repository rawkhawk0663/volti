import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/library/setlist.dart';
import 'package:volti/core/sync/sync_engine.dart';
import 'package:volti/core/sync/sync_store.dart';
import 'package:volti/core/teaching/school_calendar.dart';
import 'package:volti/core/teaching/school_level.dart';
import 'package:volti/core/teaching/student.dart';
import 'package:volti/core/teaching/todo.dart';
import 'package:volti/features/teaching/absence_pdf.dart';
import 'package:volti/features/teaching/dashboard.dart';
import 'package:volti/features/teaching/homework_share.dart';
import 'package:volti/features/teaching/student_dialog.dart' show playingSinceText, instrumentLabel;
import 'package:volti/features/teaching/teaching_view.dart' show upcomingBirthdays;
import 'package:volti/features/teaching/timetable.dart';
import 'package:volti/features/viewer/ink_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('volti_teaching'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Student anna() => Student.create('Anna Muster')
    ..instrument = 'Gitarre'
    ..weekday = 2
    ..time = '11:25'
    ..duration = 25;

  test('Kartei wird gespeichert und wieder gelesen', () async {
    final store = StudentStore(tmp.path);
    final s = anna()
      ..putPiece(StudentPiece.create('Noten/Etüde.pdf'))
      ..putLesson(
        Lesson.create(DateTime(2026, 11, 17))
          ..content = 'Anschlag p-i-m'
          ..homework = 'S. 18 üben',
      );
    await store.save(s);
    final back = (await store.loadAll()).single;
    expect(back.name, 'Anna Muster');
    expect(back.endTime, '11:50');
    expect(back.activePieces.single.relativePath, 'Noten/Etüde.pdf');
    final l = back.activeLessons.single;
    expect(l.date, DateTime(2026, 11, 17));
    expect(l.homework, 'S. 18 üben');
    expect(back.lessonOn(DateTime(2026, 11, 17, 15)), isNotNull);
    expect(back.scope, 'student-${back.id}');
  });

  test('Zwei Geräte erfassen Lektionen: nichts geht verloren, gelöscht bleibt gelöscht', () {
    final base = anna()..putPiece(StudentPiece.create('Noten/a.pdf'));
    final gone = base.activePieces.single;
    final surface = Student.fromJson(base.toJson())..putLesson(Lesson.create(DateTime(2026, 11, 10))..homework = 'A');
    final desktop = Student.fromJson(base.toJson())..putLesson(Lesson.create(DateTime(2026, 11, 17))..homework = 'B');
    // Auf dem Desktop wird das Stück entfernt, etwas später.
    desktop.pieces[gone.id]!
      ..deleted = true
      ..modified = DateTime.now().toUtc().add(const Duration(seconds: 1));
    // Name auf dem Surface geändert (jüngste Fassung der Angaben gewinnt).
    surface
      ..name = 'Anna M.'
      ..modified = DateTime.now().toUtc().add(const Duration(seconds: 2));

    final merged = Student.merge(surface, desktop);
    expect(merged.activeLessons.map((l) => l.homework), ['B', 'A']);
    expect(merged.activePieces, isEmpty);
    expect(merged.name, 'Anna M.');
    expect(Student.merge(desktop, surface).toJson(), merged.toJson());
  });

  test('Notiz-Karten werden pro Karte zusammengeführt', () {
    final base = anna();
    final a = Student.fromJson(base.toJson())..putMemo(StudentNote.create(title: 'Infos', text: 'Geburtstag 9.12.'));
    final b = Student.fromJson(base.toJson())..putMemo(StudentNote.create(title: 'Ziele', text: 'Vorspiel'));
    final merged = Student.merge(a, b);
    expect(merged.activeMemos.map((m) => m.title).toSet(), {'Infos', 'Ziele'});
    final back = Student.fromJson(merged.toJson());
    expect(back.activeMemos.length, 2);
  });

  test('Sync gleicht Karteien pro Lektion ab', () async {
    final cloud = p.join(tmp.path, 'cloud');
    await SyncEngine.initializeRemote(FolderSyncStore(cloud));
    SyncEngine engine(String name) => SyncEngine(
      localRoot: p.join(tmp.path, name, 'Bibliothek'),
      remote: FolderSyncStore(cloud),
      baseFile: File(p.join(tmp.path, name, 'base.json')),
    );
    final a = StudentStore(p.join(tmp.path, 'surface', 'Bibliothek'));
    final b = StudentStore(p.join(tmp.path, 'desktop', 'Bibliothek'));

    final s = anna();
    await a.save(s);
    await engine('surface').run();
    await engine('desktop').run();
    expect((await b.loadAll()).single.name, 'Anna Muster');

    // Beide erfassen gleichzeitig eine Lektion.
    final onA = (await a.loadAll()).single..putLesson(Lesson.create(DateTime(2026, 11, 10))..content = 'Surface');
    await a.save(onA);
    final onB = (await b.loadAll()).single..putLesson(Lesson.create(DateTime(2026, 11, 17))..content = 'Desktop');
    await b.save(onB);
    await engine('surface').run();
    await engine('desktop').run();
    await engine('surface').run();
    for (final store in [a, b]) {
      expect((await store.loadAll()).single.activeLessons.map((l) => l.content), ['Desktop', 'Surface']);
    }

    // Löschen der Kartei kommt auf dem anderen Gerät an.
    await a.delete((await a.loadAll()).single);
    await engine('surface').run();
    await engine('desktop').run();
    expect(await b.loadAll(), isEmpty);
  });

  test('Notizen für eine:n Schüler:in sind nur in deren Kartei sichtbar', () async {
    final pdf = p.join(tmp.path, 'Lied.pdf');
    void line(InkController c) => c.addStroke(
      page: 1,
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 0.01,
      points: const [InkPoint(0.1, 0.1, 0.5), InkPoint(0.9, 0.1, 0.5)],
    );
    final s = anna();
    final forAnna = InkController(pdfPath: pdf, scope: s.scope, scopeName: s.name);
    await forAnna.load();
    expect(forAnna.annotations.layer(forAnna.activeLayer)!.name, contains('Anna'));
    line(forAnna);
    await forAnna.save();

    // Bibliothek, eine Setlist und eine andere Schülerin sehen nichts davon.
    for (final scope in [null, Setlist.create('Gottesdienst').id, Student.create('Ben').scope]) {
      final other = InkController(pdfPath: pdf, scope: scope, scopeName: 'x');
      await other.load();
      expect(other.annotations.visibleStrokesOn(1), isEmpty, reason: 'scope $scope');
      expect(other.layers.where((l) => l.scope == s.scope), isEmpty, reason: 'keine fremden Ebenen in der Liste');
      other.dispose();
    }
    forAnna.dispose();
  });

  test('Schulkalender: Wochen, Semester, Ferien und Feiertage', () {
    expect(isoWeek(DateTime(2026, 10, 12)), 42);
    expect(isoWeek(DateTime(2027, 1, 1)), 53);
    expect(isoWeek(DateTime(2026, 1, 1)), 1);
    expect(easterSunday(2026), DateTime(2026, 4, 5));
    expect(easterSunday(2027), DateTime(2027, 3, 28));

    final cal = SchoolCalendar(
      semesters: [
        Semester(id: 'hs', name: 'Herbstsemester 2026', start: DateTime(2026, 8, 10), end: DateTime(2027, 1, 31)),
      ],
      free: [
        FreePeriod.create(name: 'Herbstferien', start: DateTime(2026, 9, 26), end: DateTime(2026, 10, 11)),
        FreePeriod.create(name: 'Weihnachten', start: DateTime(2026, 12, 25), holiday: true),
      ],
    );
    final days = lessonDates(cal.semesterFor(DateTime(2026, 11, 17)), DateTime.tuesday);
    expect(days.first, DateTime(2026, 8, 11));
    expect(days.every((d) => d.weekday == DateTime.tuesday), isTrue);
    expect(days.last.isAfter(DateTime(2027, 1, 24)), isTrue);
    expect(cal.freeOn(DateTime(2026, 9, 29))!.name, 'Herbstferien');
    expect(cal.freeOn(DateTime(2026, 12, 25))!.holiday, isTrue);
    expect(cal.freeOn(DateTime(2026, 10, 13)), isNull);

    // JSON hin und zurück.
    final back = SchoolCalendar.fromJson(cal.toJson());
    expect(back.semesters.single.name, 'Herbstsemester 2026');
    expect(back.free.length, 2);

    // Ohne eingetragene Semester: Herbst- und Frühlingssemester.
    final def = SchoolCalendar().semesterFor(DateTime(2026, 11, 17));
    expect(def.start, DateTime(2026, 8, 1));
    expect(def.end, DateTime(2027, 1, 31));

    // Schweizer Feiertage im Herbstsemester.
    final swiss = swissHolidays(DateTime(2026, 8, 1), DateTime(2027, 1, 31)).map((f) => f.start).toList();
    expect(swiss, containsAll([DateTime(2026, 8, 1), DateTime(2026, 12, 25), DateTime(2027, 1, 2)]));
  });

  test('Schullektionen und Pensum', () {
    final cal = SchoolCalendar(lessonMinutes: 45, fullLoad: 28);
    // 12 Lektionen à 25 Minuten = 300 Minuten = 6,67 Schullektionen.
    expect(cal.schoolLessons(300), closeTo(6.67, 0.01));
    expect(cal.loadPercent(300), closeTo(23.8, 0.1));
    expect(cal.loadPercent(28 * 45), closeTo(100, 0.001));
    final back = SchoolCalendar.fromJson((cal..lessonMinutes = 50).toJson());
    expect(back.lessonMinutes, 50);
    expect(back.fullLoad, 28);
    // Ältere Datei ohne diese Angaben: Standardwerte.
    expect(SchoolCalendar.fromJson({'format': 'volti-teaching'}).lessonMinutes, 45);
  });

  test('Klassenstufe steigt jedes Jahr am 15. Juli', () {
    expect(SchoolLevel.schoolYearOf(DateTime(2026, 7, 14)), 2025);
    expect(SchoolLevel.schoolYearOf(DateTime(2026, 7, 15)), 2026);
    // Im Schuljahr 2026/27 in der P5 eingetragen.
    final s = anna()
      ..level = 'P5'
      ..levelYear = 2026;
    expect(s.currentLevel(DateTime(2026, 11, 17)), 'P5');
    expect(s.currentLevel(DateTime(2027, 7, 14)), 'P5');
    expect(s.currentLevel(DateTime(2027, 7, 15)), 'P6');
    // Nach der P6 ohne gewählten Zug: Oberstufe 1 (O1), mit Zug: S1 …
    expect(s.currentLevel(DateTime(2028, 9, 1)), 'O1');
    s.track = 'S';
    expect(s.currentLevel(DateTime(2028, 9, 1)), 'S1');
    expect(s.currentLevel(DateTime(2030, 9, 1)), 'S3');
    // Nach der Oberstufe keine Stufe mehr.
    expect(s.currentLevel(DateTime(2031, 9, 1)), isNull);
    // Direkt in der Oberstufe eingetragen: der Zug kommt aus dem Kürzel.
    final b = anna()
      ..level = 'B2'
      ..levelYear = 2026;
    expect(b.currentLevel(DateTime(2027, 8, 1)), 'B3');
    // Bleibt beim Speichern erhalten.
    final back = Student.fromJson(
      (s
            ..birthday = DateTime(2015, 12, 9)
            ..track = 'R')
          .toJson(),
    );
    expect(back.level, 'P5');
    expect(back.levelYear, 2026);
    expect(back.track, 'R');
    expect(back.birthday, DateTime(2015, 12, 9));
  });

  test('Geburtstage: Alter und Erinnerung', () {
    final bday = DateTime(2015, 12, 9);
    expect(ageOn(bday, DateTime(2026, 12, 8)), 10);
    expect(ageOn(bday, DateTime(2026, 12, 9)), 11);
    expect(daysUntilBirthday(bday, DateTime(2026, 12, 9)), 0);
    expect(daysUntilBirthday(bday, DateTime(2026, 12, 2)), 7);
    expect(nextBirthday(bday, DateTime(2026, 12, 10)), DateTime(2027, 12, 9));
    // 29. Februar in einem gewöhnlichen Jahr: am 28.
    expect(nextBirthday(DateTime(2016, 2, 29), DateTime(2027, 1, 1)), DateTime(2027, 2, 28));

    final students = [
      anna()..birthday = DateTime(2015, 12, 9),
      Student.create('Ben')..birthday = DateTime(2016, 12, 12),
      Student.create('Chloé')..birthday = DateTime(2016, 3, 1),
    ];
    final soon = upcomingBirthdays(students, DateTime(2026, 12, 9));
    expect(soon.map((b) => b.student.name), ['Anna Muster', 'Ben']);
    expect(soon.first.inDays, 0);
    expect(soon.first.age, 11);
    expect(soon.last.age, 10);
  });

  test('Noten pro Semester bleiben erhalten', () {
    final s = anna()..grades['hs-2026'] = '5.5';
    expect(Student.fromJson(s.toJson()).grades['hs-2026'], '5.5');
  });

  test('Hausaufgaben: Text und WhatsApp-Nummer', () {
    final s = anna()..phone = '079 123 45 67';
    final l = Lesson.create(DateTime(2026, 11, 17))..homework = 'S. 18 üben';
    final text = homeworkText(s, l);
    expect(text, contains('Anna'));
    expect(text, contains('17.11.2026'));
    expect(text, contains('S. 18 üben'));
    expect(whatsAppNumber('079 123 45 67'), '41791234567');
    expect(whatsAppNumber('+49 151 2345678'), '491512345678');
    expect(whatsAppNumber('0041 79 123 45 67'), '41791234567');
    expect(whatsAppNumber(''), '');
  });

  test('Stundenplan als PDF', () async {
    final students = [
      anna(),
      Student.create('Ben')
        ..weekday = 2
        ..time = '10:00',
      Student.create('Chloé')..weekday = 6,
    ];
    expect(timetableDays(students), [1, 2, 3, 4, 5, 6]);
    expect(studentsOn(students, 2).map((s) => s.name), ['Ben', 'Anna Muster']);
    final bytes = await buildTimetablePdf(students);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('Neue Kartei: 25 Minuten, Gruppe mit Mitgliedern bleibt erhalten', () async {
    expect(Student.create('Neu').duration, 25);
    final store = StudentStore(tmp.path);
    final a = anna(), b = Student.create('Ben Beispiel');
    final g = Student.create('Anna & Ben')..members.addAll([a.id, b.id]);
    expect(g.isGroup, isTrue);
    expect(a.isGroup, isFalse);
    for (final s in [a, b, g]) {
      await store.save(s);
    }
    final back = {for (final s in await store.loadAll()) s.id: s};
    expect(back[g.id]!.members, [a.id, b.id]);
    expect(back[a.id]!.members, isEmpty);
  });

  test('Hausaufgaben an eine Gruppe', () {
    expect(greetingNames(['Anna Muster']), 'Anna');
    expect(greetingNames(['Anna Muster', 'Ben Beispiel']), 'Anna und Ben');
    expect(greetingNames(['Anna', 'Ben', 'Lea']), 'Anna, Ben und Lea');
    final a = anna()..email = 'anna@example.com';
    final b = Student.create('Ben Beispiel')..email = 'ben@example.com';
    final c = Student.create('Lea');
    final g = Student.create('Gruppe')..members.addAll([a.id, b.id, c.id]);
    final l = Lesson.create(DateTime(2026, 11, 17))..homework = 'Tonleiter';
    final text = homeworkText(g, l, members: [a, b, c]);
    expect(text, startsWith('Hoi Anna, Ben und Lea'));
    expect(text, contains('eure Hausaufgaben'));
    expect(homeworkEmails(g, members: [a, b, c]), ['anna@example.com', 'ben@example.com']);
    expect(homeworkText(a, l), contains('deine Hausaufgaben'));
  });

  test('To-Dos: pro Eintrag zusammengeführt, überfällig', () {
    final t = Todo.create('Noten kopieren', due: DateTime(2026, 11, 10), student: 'x');
    final back = TodoStore.decode(TodoStore.encode({t.id: t}))[t.id]!;
    expect(back.text, 'Noten kopieren');
    expect(back.due, DateTime(2026, 11, 10));
    expect(back.student, 'x');
    expect(back.overdue(DateTime(2026, 11, 17, 9)), isTrue);
    expect(back.overdue(DateTime(2026, 11, 10, 9)), isFalse);

    // Gerät A hakt ab, Gerät B legt ein neues an: beides bleibt.
    final onA = TodoStore.decode(TodoStore.encode({t.id: t}));
    onA[t.id]!
      ..done = true
      ..modified = t.modified.add(const Duration(minutes: 1));
    final u = Todo.create('Elterngespräch');
    final onB = {t.id: t, u.id: u};
    final merged = TodoStore.merge(onA, onB);
    expect(merged.length, 2);
    expect(merged[t.id]!.done, isTrue);
  });

  test('To-Dos werden abgeglichen', () async {
    final cloud = p.join(tmp.path, 'cloud');
    await SyncEngine.initializeRemote(FolderSyncStore(cloud));
    SyncEngine engine(String name) => SyncEngine(
      localRoot: p.join(tmp.path, name, 'Bibliothek'),
      remote: FolderSyncStore(cloud),
      baseFile: File(p.join(tmp.path, name, 'base.json')),
    );
    final rootA = p.join(tmp.path, 'surface', 'Bibliothek');
    final rootB = p.join(tmp.path, 'desktop', 'Bibliothek');
    final t1 = Todo.create('Auf Surface');
    await TodoStore.save(rootA, {t1.id: t1});
    await engine('surface').run();
    final t2 = Todo.create('Auf Desktop');
    await TodoStore.save(rootB, {t2.id: t2});
    await engine('desktop').run();
    await engine('surface').run();
    for (final root in [rootA, rootB]) {
      final texts = (await TodoStore.load(root)).values.map((t) => t.text).toList()..sort();
      expect(texts, ['Auf Desktop', 'Auf Surface']);
    }
  });

  test('Übersicht: Lektionen des Tages und nächster Unterrichtstag', () {
    final a = anna(); // Dienstag 11:25
    final b = Student.create('Ben')
      ..weekday = 2
      ..time = '09:00';
    final c = Student.create('Cleo')..weekday = 4;
    final tuesday = DateTime(2026, 11, 17);
    expect(lessonsOn([a, b, c], tuesday).map((s) => s.name), ['Ben', 'Anna Muster']);
    final next = nextTeachingDay([a, b, c], tuesday)!;
    expect(next.day, DateTime(2026, 11, 19));
    expect(next.lessons.single.name, 'Cleo');
    // Donnerstag frei: dann erst der nächste Dienstag.
    final skip = nextTeachingDay([a, b, c], tuesday, isFree: (d) => d.weekday == 4)!;
    expect(skip.day, DateTime(2026, 11, 24));
    expect(durationText(25), '25 min');
    expect(durationText(130), '2 h 10 min');
  });

  test('Nächste Lektion: heute später, sonst am nächsten Unterrichtstag', () {
    final a = anna(); // Dienstag 11:25
    final b = Student.create('Ben')
      ..weekday = 2
      ..time = '15:00';
    final c = Student.create('Cleo')
      ..weekday = 4
      ..time = '07:45';
    expect(nextLesson([a, b, c], DateTime(2026, 11, 17, 9))!.student.name, 'Anna Muster');
    expect(nextLesson([a, b, c], DateTime(2026, 11, 17, 12))!.student.name, 'Ben');
    final later = nextLesson([a, b, c], DateTime(2026, 11, 17, 16))!;
    expect(later.student.name, 'Cleo');
    expect(later.day, DateTime(2026, 11, 19));
    // Heute frei: dann gar nicht heute.
    expect(nextLesson([a, b, c], DateTime(2026, 11, 17, 9), isFree: (d) => d.day == 17)!.student.name, 'Cleo');
  });

  test('Telefonnummern schön geschrieben', () {
    expect(formatPhone('0788765432'), '078 876 54 32');
    expect(formatPhone('078 876 54 32'), '078 876 54 32');
    expect(formatPhone('+41788765432'), '+41 78 876 54 32');
    expect(formatPhone('0041 78 876 54 32'), '+41 78 876 54 32');
    expect(formatPhone('+41 078 876 54 32'), '+41 78 876 54 32');
    expect(formatPhone('+49 151 1234567'), '+49 151 1234567');
    expect(formatPhone(''), '');
    expect(whatsAppNumber(formatPhone('0788765432')), '41788765432');
  });

  test('Stundenplan-PDF mit vielen Lektionen an einem Tag', () async {
    final many = [
      for (var i = 0; i < 20; i++)
        Student.create('Schüler:in $i')
          ..weekday = 2
          ..time = '${(8 + i ~/ 2).toString().padLeft(2, '0')}:${i.isEven ? '00' : '30'}',
    ];
    final bytes = await buildTimetablePdf(many);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('Absenzenliste: Zeilen mit Tag der Gruppe, PDF entsteht', () async {
    final a = anna()
      ..putLesson(
        Lesson.create(DateTime(2026, 11, 10))
          ..status = LessonStatus.excused
          ..reason = 'krank',
      );
    final lea = Student.create('Lea Graf');
    final group = Student.create('Gruppe')
      ..weekday = 4
      ..time = '15:00'
      ..members.add(lea.id);
    final nobody = Student.create('Ohne Tag');
    final rows = absenceRows([group, lea, a, nobody], (id) => id == lea.id ? group : null);
    expect(rows.map((r) => r.student.name), ['Anna Muster', 'Lea Graf']);
    expect(rows.last.weekday, 4);
    final cal = SchoolCalendar();
    final bytes = await buildAbsencePdf(rows, cal, cal.semesterFor(DateTime(2026, 11, 17)));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('Absenzenliste: Orte und Spalten wählbar, Wahl bleibt gespeichert', () async {
    final a = anna()..place = 'Zofingen';
    final b = Student.create('Ben')
      ..weekday = 3
      ..time = '14:00'
      ..place = 'Aarburg';
    final c = Student.create('Cleo')..weekday = 4;
    final rows = absenceRows([a, b, c], (_) => null);
    expect(rows.map((r) => r.place), ['Zofingen', 'Aarburg', '']);
    expect(rows.first.time, '11:25–11:50');
    final opt = AbsenceExportOptions(excludedPlaces: {'Aarburg', ''}, reasons: false, instrument: true);
    final back = AbsenceExportOptions.decode(opt.encode());
    expect(back.excludedPlaces, {'Aarburg', ''});
    expect(back.reasons, isFalse);
    expect(back.instrument, isTrue);
    expect(back.grade, isTrue);
    expect(AbsenceExportOptions.decode(null).reasons, isTrue);
    final cal = SchoolCalendar();
    final bytes = await buildAbsencePdf(rows, cal, cal.semesterFor(DateTime(2026, 11, 17)), options: back);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('Absenzenliste nach Nachnamen', () async {
    expect(splitName('Levin Sägesser'), (first: 'Levin', last: 'Sägesser'));
    expect(splitName('Joël Jonas Baumgaertner'), (first: 'Joël Jonas', last: 'Baumgaertner'));
    expect(splitName('von Arx, Anna'), (first: 'Anna', last: 'von Arx'));
    expect(splitName('Mia'), (first: '', last: 'Mia'));
    expect(surnameFirst('Levin Sägesser'), 'Sägesser Levin');
    final names = ['Levin Sägesser', 'Paul Damm', 'Anna Bellwald'];
    names.sort((a, b) => surnameKey(a).compareTo(surnameKey(b)));
    expect(names, ['Anna Bellwald', 'Paul Damm', 'Levin Sägesser']);
    final rows = absenceRows([anna(), Student.create('Ben Zürcher')..weekday = 1], (_) => null);
    final cal = SchoolCalendar();
    final opt = AbsenceExportOptions(byName: true, time: true);
    expect(AbsenceExportOptions.decode(opt.encode()).byName, isTrue);
    final bytes = await buildAbsencePdf(rows, cal, cal.semesterFor(DateTime(2026, 11, 17)), options: opt);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('Spielt seit: Dauer in Jahren und Monaten, gespeichert, angezeigt', () {
    final now = DateTime(2026, 11, 25);
    expect(playingFor(DateTime(2024, 8, 15), now), (years: 2, months: 3));
    expect(playingFor(DateTime(2024, 11, 26), now), (years: 1, months: 11), reason: 'der Tag zählt mit');
    expect(playingFor(DateTime(2026, 11, 3), now), (years: 0, months: 0));
    expect(playingFor(DateTime(2027, 1, 1), now), (years: 0, months: 0), reason: 'nie negativ');
    expect(playingSinceText(DateTime(2024, 8, 15), now), 'seit 2 Jahren und 3 Monaten');
    expect(playingSinceText(DateTime(2025, 11, 1), now), 'seit 1 Jahr');
    expect(playingSinceText(DateTime(2026, 10, 1), now), 'seit 1 Monat');
    expect(playingSinceText(DateTime(2026, 11, 20), now), 'seit diesem Monat');
    final s = Student.create('Mia')
      ..instrument = 'E-Gitarre'
      ..playingSince = DateTime(2024, 8, 15);
    final back = Student.fromJson(s.toJson());
    expect(back.playingSince, DateTime(2024, 8, 15));
    expect(instrumentLabel(back, now), 'E-Gitarre seit 2 Jahren und 3 Monaten');
    expect(instrumentLabel(back..instrument = '', now), 'spielt seit 2 Jahren und 3 Monaten');
    expect(instrumentLabel(Student.create('Noah')..instrument = 'Bass', now), 'Bass');
    expect(Student.fromJson(Student.create('Lea').toJson()).playingSince, isNull);
  });
}
