import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'paper.dart';

/// Ein A4-Blatt mit der Vorlage [paper] als PDF (für Notizblätter). Die
/// Linien sind echte Linien im PDF, also auch gedruckt gestochen scharf.
Future<Uint8List> buildPaperPdf(Paper paper, {String? title}) async {
  final doc = pw.Document(title: title, creator: 'Volti');
  const format = PdfPageFormat.a4;
  final layout = paperLayout(paper, Size(format.width, format.height));
  final font = pw.Font.helveticaBold();
  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(
        children: [
          pw.CustomPaint(
            size: PdfPoint(format.width, format.height),
            painter: (canvas, size) {
              canvas.setLineCap(PdfLineCap.butt);
              for (final l in layout.lines) {
                canvas
                  ..setStrokeColor(PdfColor.fromInt(l.color.toARGB32()))
                  ..setLineWidth(l.width)
                  // PDF zählt von unten nach oben.
                  ..moveTo(l.a.dx, size.y - l.a.dy)
                  ..lineTo(l.b.dx, size.y - l.b.dy)
                  ..strokePath();
              }
            },
          ),
          for (final t in layout.labels)
            pw.Positioned(
              left: t.at.dx,
              top: t.at.dy - t.size * 0.78,
              child: pw.Text(
                t.text,
                style: pw.TextStyle(font: font, fontSize: t.size, color: PdfColor.fromInt(0xFF3C3C3C)),
              ),
            ),
        ],
      ),
    ),
  );
  return doc.save();
}
