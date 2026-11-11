import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:volti/app/error_log.dart';
import 'package:volti/core/library/auto_backup.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('volti-auto'));
  tearDown(() => tmp.delete(recursive: true));

  test('fällig nach einer Woche', () {
    final now = DateTime(2026, 11, 11);
    expect(AutoBackup.isDue(null, now), isTrue);
    expect(AutoBackup.isDue(now.subtract(const Duration(days: 6)), now), isFalse);
    expect(AutoBackup.isDue(now.subtract(const Duration(days: 7)), now), isTrue);
  });

  test('sichert die Bibliothek und behält nur die jüngsten drei', () async {
    final root = p.join(tmp.path, 'Bibliothek');
    await File(p.join(root, 'Noten', 'a.pdf')).create(recursive: true);
    final dir = p.join(tmp.path, 'Sicherungen');
    await Directory(dir).create();
    // Von Hand erstellte Sicherung: bleibt immer.
    await File(p.join(dir, 'Volti-Sicherung-2020-01-01.zip')).writeAsString('x');
    for (final d in ['2026-10-01', '2026-10-08', '2026-10-15']) {
      await File(p.join(dir, '${AutoBackup.prefix}$d.zip')).writeAsString('x');
    }
    final path = await AutoBackup.run(root, dir, now: DateTime(2026, 11, 11));
    expect(File(path).lengthSync(), greaterThan(100));
    final names = Directory(dir).listSync().map((e) => p.basename(e.path)).toList()..sort();
    expect(names, [
      '${AutoBackup.prefix}2026-10-08.zip',
      '${AutoBackup.prefix}2026-10-15.zip',
      '${AutoBackup.prefix}2026-11-11.zip',
      'Volti-Sicherung-2020-01-01.zip',
    ]);
  });

  test('Fehlerprotokoll schreibt Fehler und fasst Wiederholungen zusammen', () async {
    ErrorLog.install(tmp.path);
    ErrorLog.record(StateError('kaputt'), StackTrace.current, where: 'Test');
    ErrorLog.record(StateError('kaputt'), StackTrace.current, where: 'Test');
    ErrorLog.record(StateError('anders'), null);
    final text = await ErrorLog.read();
    expect('kaputt'.allMatches(text), hasLength(1));
    expect(text, contains('noch 1-mal'));
    expect(text, contains('anders'));
    await ErrorLog.clear();
    expect(await ErrorLog.read(), isEmpty);
  });
}
