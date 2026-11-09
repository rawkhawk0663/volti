import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../library/page_setup.dart';

/// Findet die weissen Ränder einer PDF-Seite und schlägt einen Ausschnitt vor
/// (null = Seite leer oder nicht lesbar). Rendert die Seite dafür klein.
Future<PageCrop?> autoCropPage(PdfDocument doc, int page) async {
  final p = doc.pages[page - 1];
  const w = 360;
  final h = (w * p.height / p.width).round();
  final image = await p.renderForDisplay(
    width: w,
    height: h,
    fullWidth: w.toDouble(),
    fullHeight: h.toDouble(),
    backgroundColor: 0xFFFFFFFF,
  );
  if (image == null) return null;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return findContentBounds(data.buffer.asUint8List(), image.width, image.height);
  } finally {
    image.dispose();
  }
}
