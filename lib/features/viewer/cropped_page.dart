import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/library/page_setup.dart';

/// Zeigt einen Ausschnitt einer Seite, gedreht und geradegerichtet.
///
/// [page] baut die *ganze, ungedrehte* Seite in der übergebenen Grösse
/// (PDF-Bild, Striche, Text-Notizen). Diese Seite wird geradegerichtet
/// (um ihre Mitte gedreht), auf den Ausschnitt verschoben, abgeschnitten und
/// zuletzt in Vierteldrehungen gedreht. Weil Flutter Berührungen durch alle
/// diese Schritte zurückrechnet, landen Stift-Striche in den Koordinaten der
/// ganzen Seite – genau dort, wo sie hingehören.
class CroppedPage extends StatelessWidget {
  const CroppedPage({super.key, required this.crop, required this.size, required this.page});

  final PageCrop crop;

  /// Angezeigte Grösse (nach Zuschnitt und Drehung).
  final Size size;
  final Widget Function(Size fullPage) page;

  /// Grösse der ganzen, ungedrehten Seite, wenn der Ausschnitt in [size]
  /// angezeigt wird.
  static Size fullSizeFor(PageCrop crop, Size size) {
    final unrotated = crop.quarterTurns.isOdd ? Size(size.height, size.width) : size;
    return Size(unrotated.width / crop.width, unrotated.height / crop.height);
  }

  @override
  Widget build(BuildContext context) {
    if (crop.isNone) return SizedBox.fromSize(size: size, child: page(size));
    final unrotated = crop.quarterTurns.isOdd ? Size(size.height, size.width) : size;
    final full = fullSizeFor(crop, size);
    Widget child = SizedBox.fromSize(size: full, child: page(full));
    if (crop.skew != 0) {
      child = Transform.rotate(angle: crop.skew * math.pi / 180, child: child);
    }
    child = ClipRect(
      child: SizedBox.fromSize(
        size: unrotated,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: full.width,
          maxWidth: full.width,
          minHeight: full.height,
          maxHeight: full.height,
          child: Transform.translate(offset: Offset(-crop.left * full.width, -crop.top * full.height), child: child),
        ),
      ),
    );
    if (crop.quarterTurns != 0) child = RotatedBox(quarterTurns: crop.quarterTurns, child: child);
    return SizedBox.fromSize(size: size, child: child);
  }
}
