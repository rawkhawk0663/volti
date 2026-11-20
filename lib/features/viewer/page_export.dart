import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../../core/ink/score_annotations.dart';
import '../../core/ink/stamp.dart';
import '../../core/ink/stroke.dart';
import '../../core/library/page_setup.dart';
import '../../core/library/sidecar_store.dart';
import '../../core/pdf/paper.dart';
import 'ink_layer.dart';
import 'stamp_paint.dart';
import 'tab_paint.dart';
import 'text_layer.dart';

/// Ein Stück für den Export: das geöffnete PDF, seine Anmerkungen und welche
/// Seiten (als PDF-Seiten, in Anzeige-Reihenfolge) hinein sollen.
class ExportPiece {
  const ExportPiece({required this.doc, required this.annotations, required this.setup, required this.pages});
  final PdfDocument doc;
  final ScoreAnnotations annotations;
  final PageSetup setup;
  final List<int> pages;
}

/// Angezeigte Seiten (PDF-Seiten in Anzeige-Reihenfolge) – bei einem
/// Lesezeichen nur dessen Bereich.
List<int> shownPages(PageSetup setup, int pdfPages, ScoreAnnotations annotations, String? bookmark) {
  final all = setup.pages(pdfPages);
  final b = bookmark == null ? null : annotations.bookmark(bookmark);
  if (b == null || b.deleted) return all;
  final start = all.indexOf(b.page);
  if (start < 0) return all;
  var end = all.indexOf(b.lastPage, start);
  if (end < 0) end = start;
  return all.sublist(start, end + 1);
}

/// Öffnet Stücke für den Export (PDF und Zusatzdatei). Die geöffneten
/// Dateien müssen danach mit [closeExportPieces] freigegeben werden.
Future<List<ExportPiece>> openExportPieces(List<({String path, String? bookmark, String? scope})> items) async {
  final result = <ExportPiece>[];
  for (final it in items) {
    final doc = await PdfDocument.openFile(it.path);
    final side = await const SidecarStore().load(it.path);
    // Aus einer Setlist: deren Notizen statt der anderer Setlists.
    side.annotations.viewScope = it.scope;
    result.add(
      ExportPiece(
        doc: doc,
        annotations: side.annotations,
        setup: side.pages,
        pages: shownPages(side.pages, doc.pages.length, side.annotations, it.bookmark),
      ),
    );
  }
  return result;
}

Future<void> closeExportPieces(List<ExportPiece> pieces) async {
  for (final p in pieces) {
    await p.doc.dispose();
  }
}

/// Malt alle eingeblendeten Anmerkungen einer PDF-Seite auf [canvas] der
/// Grösse [size] (ganze, ungedrehte Seite): zuerst den Leuchtstift
/// (multipliziert, schwarze Noten bleiben schwarz), dann die Ebenen in ihrer
/// Reihenfolge, zuletzt die Text-Notizen.
void paintAnnotations(Canvas canvas, Size size, ScoreAnnotations a, int page) {
  final strokes = a.visibleStrokesOn(page);
  for (final s in strokes.where((s) => s.tool == InkTool.highlighter)) {
    paintStroke(canvas, size, s.tool, Color(s.color), s.width, s.points, fill: s.fill);
  }
  final stamps = a.visibleStampsOn(page);
  for (final l in a.layers) {
    if (l.isGroup || !a.isLayerShown(l.id)) continue;
    final items = <Object>[
      for (final s in strokes)
        if (s.tool != InkTool.highlighter && a.resolveLayer(s.layer) == l.id) s,
      for (final st in stamps)
        if (a.resolveLayer(st.layer) == l.id) st,
    ]..sort((x, y) => _created(x).compareTo(_created(y)));
    for (final it in items) {
      if (it is Stroke) {
        paintStroke(canvas, size, it.tool, Color(it.color), it.width, it.points, fill: it.fill);
      } else if (it is Stamp) {
        paintStamp(canvas, size, it);
      }
    }
  }
  for (final t in a.visibleTextsOn(page)) {
    paintTextNote(canvas, t, size);
  }
  // Tabulaturen liegen wie in der Notenansicht zuoberst.
  for (final t in a.visibleTabsOn(page)) {
    paintTabBlock(canvas, t, size);
  }
}

DateTime _created(Object o) => o is Stroke ? o.createdAt : (o as Stamp).createdAt;

/// Rendert eine Seite so, wie sie angezeigt wird: Zuschnitt, Drehung,
/// Geraderichten – und auf Wunsch mit Anmerkungen. [width]: Breite der
/// fertigen Seite in Bildpunkten.
Future<ui.Image?> renderPageAsShown(
  PdfDocument doc,
  ScoreAnnotations? annotations,
  PageCrop crop,
  int page, {
  int width = 1800,
  String? paper,
}) async {
  final p = doc.pages[PageSetup.sizeSource(page) - 1];
  final aspect = p.width / p.height;
  // Breite der ganzen Seite, so dass die fertige Seite [width] breit wird
  // (bei Vierteldrehung ist die Breite die Höhe des Ausschnitts).
  final fullW = (crop.quarterTurns.isOdd ? width * aspect / crop.height : width / crop.width).clamp(400, 4096).round();
  final fullH = (fullW / aspect).round();
  // Leere Seite (zum Beschriften): einfach weiss.
  final blank = PageSetup.isBlank(page);
  final pageImg = blank
      ? null
      : await p.renderForDisplay(
          width: fullW,
          height: fullH,
          fullWidth: fullW.toDouble(),
          fullHeight: fullH.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
  if (pageImg == null && !blank) return null;
  final full = Size(fullW.toDouble(), fullH.toDouble());

  // Ganze Seite mit Anmerkungen
  final r1 = ui.PictureRecorder();
  final c1 = Canvas(r1);
  c1.drawRect(Offset.zero & full, Paint()..color = const Color(0xFFFFFFFF));
  if (pageImg != null) c1.drawImage(pageImg, Offset.zero, Paint());
  if (blank) paintPaper(c1, full, Paper.fromName(paper));
  if (annotations != null) paintAnnotations(c1, full, annotations, page);
  final pic1 = r1.endRecording();
  final annotated = await pic1.toImage(fullW, fullH);
  pic1.dispose();
  pageImg?.dispose();
  if (crop.isNone) return annotated;

  // Zuschnitt, Geraderichten, Drehung – wie in der Notenansicht (CroppedPage).
  final cw = crop.width * full.width, ch = crop.height * full.height;
  final odd = crop.quarterTurns.isOdd;
  final ow = (odd ? ch : cw).round(), oh = (odd ? cw : ch).round();
  final r2 = ui.PictureRecorder();
  final c2 = Canvas(r2);
  c2.drawRect(Rect.fromLTWH(0, 0, ow.toDouble(), oh.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
  c2.translate(ow / 2, oh / 2);
  c2.rotate(crop.quarterTurns * math.pi / 2);
  c2.translate(-cw / 2, -ch / 2);
  c2.clipRect(Rect.fromLTWH(0, 0, cw, ch));
  c2.translate(-crop.left * full.width, -crop.top * full.height);
  if (crop.skew != 0) {
    c2.translate(full.width / 2, full.height / 2);
    c2.rotate(crop.skew * math.pi / 180);
    c2.translate(-full.width / 2, -full.height / 2);
  }
  c2.drawImage(annotated, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
  final pic2 = r2.endRecording();
  final out = await pic2.toImage(math.max(1, ow), math.max(1, oh));
  pic2.dispose();
  annotated.dispose();
  return out;
}

/// Baut aus den Stücken ein neues PDF (eine Seite = ein Bild). Das Original
/// bleibt unverändert. [onProgress] meldet (fertig, gesamt).
Future<Uint8List> buildExportPdf(
  List<ExportPiece> pieces, {
  bool withAnnotations = true,
  void Function(int done, int total)? onProgress,
  List<pw.Page> leading = const [],
}) async {
  final out = pw.Document(title: 'Volti', creator: 'Volti');
  // Vorangestellte Seiten (z. B. Hausaufgaben als Text).
  leading.forEach(out.addPage);
  final total = pieces.fold<int>(0, (n, p) => n + p.pages.length);
  var done = 0;
  for (final piece in pieces) {
    for (final page in piece.pages) {
      final crop = piece.setup.cropOf(page);
      final img = await renderPageAsShown(
        piece.doc,
        withAnnotations ? piece.annotations : null,
        crop,
        page,
        paper: piece.setup.paperOf(page),
      );
      if (img != null) {
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        // Seitengrösse in Punkten wie im Original (mit Zuschnitt und Drehung).
        final p = piece.doc.pages[PageSetup.sizeSource(page) - 1];
        final w = p.width * crop.width, h = p.height * crop.height;
        final format = crop.quarterTurns.isOdd ? PdfPageFormat(h, w) : PdfPageFormat(w, h);
        final raw = pw.RawImage(bytes: data!.buffer.asUint8List(), width: img.width, height: img.height);
        out.addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(raw, fit: pw.BoxFit.fill),
          ),
        );
        img.dispose();
      }
      onProgress?.call(++done, total);
    }
  }
  return out.save();
}
