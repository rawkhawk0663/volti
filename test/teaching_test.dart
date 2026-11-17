import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/library/setlist.dart';
import 'package:volti/core/sync/sync_engine.dart';
import 'package:volti/core/sync/sync_store.dart';
import 'package:volti/core/teaching/student.dart';
import 'package:volti/features/teaching/homework_share.dart';
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
}
