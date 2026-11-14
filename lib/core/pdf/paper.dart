import 'dart:math' as math;
import 'dart:ui';

import '../../app/l10n.dart';

/// Vorlage für leere Seiten und Notizblätter.
enum Paper {
  blank,
  staff,
  tab,
  staffTab,
  chords,
  lined;

  static Paper fromName(String? n) => Paper.values.firstWhere((p) => p.name == n, orElse: () => blank);

  String get label => switch (this) {
    blank => tr('Leer', 'Blank'),
    staff => tr('Notenlinien', 'Staff paper'),
    tab => tr('Tabulatur', 'Tablature'),
    staffTab => tr('Noten + Tabulatur', 'Staff + tab'),
    chords => tr('Akkord-Kästchen', 'Chord boxes'),
    lined => tr('Liniert', 'Lined'),
  };
}

/// Eine Linie der Vorlage (in Punkten der Seite).
class PaperLine {
  const PaperLine(this.a, this.b, this.width, this.color);
  final Offset a, b;
  final double width;
  final Color color;
}

/// Eine Beschriftung (z. B. „TAB“), Grundlinie bei [at], linksbündig.
class PaperLabel {
  const PaperLabel(this.text, this.at, this.size);
  final String text;
  final Offset at;
  final double size;
}

const _ink = Color(0xFF3C3C3C);
const _light = Color(0xFFB8B8B8);

/// Linien und Beschriftungen der Vorlage [paper] für eine Seite der Grösse
/// [size]. Masse wie auf einem A4-Blatt (in Millimetern gedacht), auf die
/// Seitenbreite umgerechnet – so passt die Vorlage zu jeder Seitengrösse.
({List<PaperLine> lines, List<PaperLabel> labels}) paperLayout(Paper paper, Size size) {
  final mm = size.width / 210;
  final lines = <PaperLine>[];
  final labels = <PaperLabel>[];
  final left = 15 * mm, right = size.width - 15 * mm;
  final top = 20 * mm, bottom = size.height - 15 * mm;
  final usable = bottom - top;

  void line(double x1, double y1, double x2, double y2, double w, [Color c = _ink]) =>
      lines.add(PaperLine(Offset(x1, y1), Offset(x2, y2), w * mm, c));

  /// Linien eines Systems (n Linien im Abstand [gap]) ab [y], mit Strich links und rechts.
  void system(double y, int n, double gap) {
    for (var i = 0; i < n; i++) {
      line(left, y + i * gap, right, y + i * gap, 0.22);
    }
    line(left, y, left, y + (n - 1) * gap, 0.3);
    line(right, y, right, y + (n - 1) * gap, 0.3);
  }

  void tabLabel(double y, double gap) {
    // „TAB“ senkrecht am Anfang, wie in Gitarrennoten üblich.
    final h = gap * 1.45;
    for (final (i, ch) in ['T', 'A', 'B'].indexed) {
      labels.add(PaperLabel(ch, Offset(left + 1.6 * mm, y + gap * 0.55 + (i + 1) * h * 0.95), h));
    }
  }

  switch (paper) {
    case Paper.blank:
      break;
    case Paper.staff:
      const gap = 1.75, height = 4 * gap, pitch = 22.0;
      final n = math.max(1, ((usable / mm - height) / pitch).floor() + 1);
      for (var i = 0; i < n; i++) {
        system(top + i * pitch * mm, 5, gap * mm);
      }
    case Paper.tab:
      const gap = 2.5, height = 5 * gap, pitch = 26.0;
      final n = math.max(1, ((usable / mm - height) / pitch).floor() + 1);
      for (var i = 0; i < n; i++) {
        final y = top + i * pitch * mm;
        system(y, 6, gap * mm);
        tabLabel(y, gap * mm);
      }
    case Paper.staffTab:
      const sGap = 1.75, tGap = 2.5, between = 7.0, pitch = 38.0;
      const height = 4 * sGap + between + 5 * tGap;
      final n = math.max(1, ((usable / mm - height) / pitch).floor() + 1);
      for (var i = 0; i < n; i++) {
        final y = top + i * pitch * mm;
        final ty = y + (4 * sGap + between) * mm;
        system(y, 5, sGap * mm);
        system(ty, 6, tGap * mm);
        tabLabel(ty, tGap * mm);
        // Gemeinsamer Strich links verbindet Noten und Tabulatur.
        line(left, y, left, ty + 5 * tGap * mm, 0.3);
      }
    case Paper.chords:
      // Akkord-Kästchen: 6 Saiten, 5 Bünde, oben der Sattel; darüber Platz für den Namen.
      const cols = 5, strGap = 5.0, fretGap = 5.5, nameSpace = 9.0, rowGap = 8.0;
      const boxW = 5 * strGap, boxH = 5 * fretGap, pitchY = nameSpace + boxH + rowGap;
      final colW = (right - left) / cols;
      final rows = math.max(1, ((usable / mm + rowGap) / pitchY).floor());
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final x0 = left + c * colW + (colW - boxW * mm) / 2;
          final y0 = top + (r * pitchY + nameSpace) * mm;
          for (var s = 0; s < 6; s++) {
            line(x0 + s * strGap * mm, y0, x0 + s * strGap * mm, y0 + boxH * mm, 0.2);
          }
          for (var f = 0; f <= 5; f++) {
            line(x0, y0 + f * fretGap * mm, x0 + boxW * mm, y0 + f * fretGap * mm, f == 0 ? 0.9 : 0.2);
          }
        }
      }
    case Paper.lined:
      const pitch = 9.0;
      final n = (usable / mm / pitch).floor() + 1;
      for (var i = 0; i < n; i++) {
        line(left, top + i * pitch * mm, right, top + i * pitch * mm, 0.2, _light);
      }
  }
  return (lines: lines, labels: labels);
}

/// Malt die Vorlage auf eine (weisse) Seite der Grösse [size].
/// [minWidth]: Linien mindestens so dick (für kleine Vorschauen).
void paintPaper(Canvas canvas, Size size, Paper paper, {double minWidth = 0}) {
  if (paper == Paper.blank) return;
  final layout = paperLayout(paper, size);
  final paint = Paint()..strokeCap = StrokeCap.butt;
  for (final l in layout.lines) {
    paint
      ..color = l.color
      ..strokeWidth = math.max(l.width, minWidth);
    canvas.drawLine(l.a, l.b, paint);
  }
  for (final t in layout.labels) {
    final builder = ParagraphBuilder(ParagraphStyle(fontFamily: 'VoltiSans', fontSize: t.size, height: 1))
      ..pushStyle(
        TextStyle(
          color: _ink,
          fontSize: t.size,
          fontFamily: 'VoltiSans',
          fontVariations: const [FontVariation('wght', 700)],
        ),
      )
      ..addText(t.text);
    final p = builder.build()..layout(const ParagraphConstraints(width: double.infinity));
    canvas.drawParagraph(p, Offset(t.at.dx, t.at.dy - p.alphabeticBaseline));
    p.dispose();
  }
}
