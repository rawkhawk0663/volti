import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/navigation_marks.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/library/setlist.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/features/viewer/ink_controller.dart';
import 'package:volti/features/viewer/links_layer.dart';
import 'package:volti/features/viewer/tool_controller.dart';

import 'helpers/tools.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_nav'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('Sprungmarken und Lesezeichen werden gespeichert und zusammengeführt', () async {
    final pdf = '${dir.path}/x.pdf';
    final c = InkController(pdfPath: pdf);
    final l = c.addLink(page: 3, x: 0.9, y: 0.8, toPage: 1, toX: 0.1, toY: 0.2);
    final b = c.addBookmark(name: 'Autumn Leaves', page: 23, endPage: 24);
    await c.save();
    final loaded = (await const SidecarStore().load(pdf)).annotations;
    expect(loaded.linksOn(3).single.toPage, 1);
    expect(loaded.bookmarks.single.name, 'Autumn Leaves');
    expect(loaded.bookmark(b)!.lastPage, 24);

    // Gerät B löscht die Marke, Gerät A benennt das Lesezeichen um → beides gilt.
    final a = ScoreAnnotations()
      ..putBookmark(loaded.bookmark(b)!.copyWith(name: 'Autumn', modifiedAt: DateTime.utc(2030)));
    final bDev = ScoreAnnotations()..putLink(loaded.link(l)!.copyWith(deleted: true, modifiedAt: DateTime.utc(2030)));
    final merged = ScoreAnnotations.merge(ScoreAnnotations.merge(loaded, a), bDev);
    expect(merged.linksOn(3), isEmpty);
    expect(merged.bookmarks.single.name, 'Autumn');
    c.dispose();
  });

  test('Lesezeichen in einer Setlist bleibt beim Speichern erhalten', () {
    final s = Setlist.create('Gig')
      ..items.add(SetlistItem.create('Noten/Realbook.pdf', bookmark: 'b1', label: 'Autumn'));
    final back = Setlist.fromJson(s.toJson());
    expect(back.items.single.bookmark, 'b1');
    expect(back.items.single.label, 'Autumn');
    expect(
      Setlist.fromJson((Setlist.create('x')..items.add(SetlistItem.create('a.pdf'))).toJson()).items.single.bookmark,
      isNull,
    );
  });

  testWidgets('Werkzeug Sprung: zwei Tipps setzen eine Marke, beim Spielen springt der Punkt', (t) async {
    final tools = await t.runAsync(() => makeTools(dir)) as ToolController;
    final c = InkController(pdfPath: '${dir.path}/x.pdf');
    final flash = ValueNotifier<JumpFlash?>(null);
    JumpLink? jumped;
    Widget layer(int page) => SizedBox(
      width: 400,
      height: 600,
      child: LinksLayer(page: page, controller: c, tools: tools, flash: flash, onJump: (l) => jumped = l),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: layer(2)),
        ),
      ),
    );

    tools.setMode(ToolMode.link);
    await t.pump();
    await t.tapAt(const Offset(360, 540)); // Startpunkt unten rechts auf Seite 2
    await t.pump();
    expect(tools.linkStart.value, isNotNull);
    await t.tapAt(const Offset(40, 60)); // Ziel (hier auf derselben Seite)
    await t.pump();
    final link = c.annotations.linksOn(2).single;
    expect(link.x, closeTo(0.9, 0.001));
    expect(link.toY, closeTo(0.1, 0.001));
    expect(tools.linkStart.value, isNull);

    tools.setMode(ToolMode.read);
    await t.pump();
    await t.tapAt(const Offset(360, 540));
    await t.pump();
    expect(jumped?.id, link.id, reason: 'Antippen des blauen Punkts springt');
    await t.runAsync(() => tools.flush());
    c.dispose();
  });
}
