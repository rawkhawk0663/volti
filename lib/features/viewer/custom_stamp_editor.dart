import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/ink/custom_stamps.dart';
import 'custom_stamp_registry.dart';
import 'tool_controller.dart';
import '../../app/l10n.dart';

/// Längste Seite eines Stempel-Bildes in Bildpunkten (scharf genug, klein).
const _maxSide = 600;

/// Bild auswählen, aufbereiten, Mittelpunkt setzen und als eigenen Stempel
/// speichern. Danach ist er gleich ausgewählt.
Future<void> importCustomStamp(BuildContext context, ToolController tools) async {
  final registry = CustomStamps.instance;
  if (registry == null) return;
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(label: tr('Bilder', 'Images'), extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif']),
    ],
    confirmButtonText: tr('Als Stempel verwenden', 'Use as stamp'),
  );
  if (file == null || !context.mounted) return;
  final raw = await _decodeLimited(await file.readAsBytes());
  if (raw == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Dieses Bild konnte nicht gelesen werden.', 'This image could not be read.'))),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final name = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
  final result = await showDialog<_EditResult>(
    context: context,
    builder: (_) => _CustomStampEditor(source: raw, initialName: name),
  );
  if (result == null || result.pixels == null) return;
  final png = await _encodePng(result.pixels!);
  if (png == null) return;
  final s = await registry.add(
    name: result.name,
    png: png,
    anchorX: result.anchorX,
    anchorY: result.anchorY,
    aspect: result.pixels!.width / result.pixels!.height,
  );
  tools.setStamp(tools.stamp.copyWith(custom: s.id));
}

/// Mittelpunkt oder Namen eines eigenen Stempels ändern.
Future<void> editCustomStamp(BuildContext context, CustomStamp s) async {
  final registry = CustomStamps.instance;
  final img = registry?.image(s.id);
  if (registry == null || img == null) return;
  final result = await showDialog<_EditResult>(
    context: context,
    builder: (_) => _CustomStampEditor(existing: img, initialName: s.name, anchor: Offset(s.anchorX, s.anchorY)),
  );
  if (result == null) return;
  await registry.update(s.copyWith(name: result.name, anchorX: result.anchorX, anchorY: result.anchorY));
}

/// Rohbild (RGBA) zum Aufbereiten.
class _Raw {
  const _Raw(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width, height;
}

Future<_Raw?> _decodeLimited(Uint8List bytes) async {
  try {
    final probe = await ui.instantiateImageCodec(bytes);
    final first = (await probe.getNextFrame()).image;
    final w = first.width, h = first.height;
    first.dispose();
    probe.dispose();
    final scale = math.min(1.0, _maxSide / math.max(w, h));
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: (w * scale).round(),
      targetHeight: (h * scale).round(),
    );
    final img = (await codec.getNextFrame()).image;
    codec.dispose();
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = data == null ? null : _Raw(data.buffer.asUint8List(), img.width, img.height);
    img.dispose();
    return result;
  } catch (_) {
    return null;
  }
}

Future<ui.Image> _toImage(StampPixels px) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(px.rgba, px.width, px.height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

Future<Uint8List?> _encodePng(StampPixels px) async {
  final img = await _toImage(px);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data?.buffer.asUint8List();
}

class _EditResult {
  const _EditResult(this.name, this.anchorX, this.anchorY, this.pixels);
  final String name;
  final double anchorX, anchorY;
  final StampPixels? pixels;
}

class _CustomStampEditor extends StatefulWidget {
  const _CustomStampEditor({this.source, this.existing, required this.initialName, this.anchor});

  /// Neues Bild (wird aufbereitet) – oder ein schon gespeichertes.
  final _Raw? source;
  final ui.Image? existing;
  final String initialName;
  final Offset? anchor;

  @override
  State<_CustomStampEditor> createState() => _CustomStampEditorState();
}

class _CustomStampEditorState extends State<_CustomStampEditor> {
  late final _name = TextEditingController(text: widget.initialName);
  late Offset _anchor = widget.anchor ?? const Offset(0.5, 0.5);
  bool _whiteToClear = true;
  StampPixels? _pixels;
  ui.Image? _preview;

  @override
  void initState() {
    super.initState();
    _preview = widget.existing;
    if (widget.source != null) _prepare();
  }

  Future<void> _prepare() async {
    final s = widget.source!;
    final px = prepareStampPixels(s.rgba, s.width, s.height, whiteToClear: _whiteToClear);
    final img = px == null ? null : await _toImage(px);
    if (!mounted) {
      img?.dispose();
      return;
    }
    final old = _preview;
    setState(() {
      _pixels = px;
      _preview = img;
    });
    if (old != null && !identical(old, widget.existing)) old.dispose();
  }

  @override
  void dispose() {
    _name.dispose();
    if (_preview != null && !identical(_preview, widget.existing)) _preview!.dispose();
    super.dispose();
  }

  void _setAnchor(Offset local, Size box) {
    setState(() => _anchor = Offset((local.dx / box.width).clamp(0, 1), (local.dy / box.height).clamp(0, 1)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final img = _preview;
    return AlertDialog(
      title: Text(
        widget.source == null ? tr('Eigener Stempel', 'Own stamp') : tr('Neuer eigener Stempel', 'New own stamp'),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                'Tippe auf den Punkt, der beim Setzen genau unter dem Stift liegen soll – bei einer Note z. B. '
                    'die Mitte des Notenkopfs.',
                'Tap the point that should sit exactly under the pen when placing it – for a note, e.g. '
                    'the middle of the note head.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 280,
              child: img == null
                  ? Center(
                      child: widget.source != null && _pixels == null && _preview == null
                          ? Text(
                              tr(
                                'Im Bild ist nichts zu sehen. Versuche es ohne «Weiss entfernen».',
                                'There is nothing to see in the image. Try without «Remove white».',
                              ),
                            )
                          : const CircularProgressIndicator(),
                    )
                  : Center(
                      child: AspectRatio(
                        aspectRatio: img.width / img.height,
                        child: LayoutBuilder(
                          builder: (context, box) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) => _setAnchor(d.localPosition, box.biggest),
                            onPanUpdate: (d) => _setAnchor(d.localPosition, box.biggest),
                            child: CustomPaint(painter: _AnchorPainter(img, _anchor, scheme.primary)),
                          ),
                        ),
                      ),
                    ),
            ),
            if (widget.source != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Weissen Hintergrund entfernen', 'Remove white background')),
                value: _whiteToClear,
                onChanged: (v) {
                  setState(() => _whiteToClear = v);
                  _prepare();
                },
              ),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: tr('Name', 'Name')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(
          onPressed: img == null
              ? null
              : () => Navigator.of(context).pop(_EditResult(_name.text, _anchor.dx, _anchor.dy, _pixels)),
          child: Text(tr('Speichern', 'Save')),
        ),
      ],
    );
  }
}

/// Bild auf Karomuster (zeigt Durchsichtiges) mit Fadenkreuz am Mittelpunkt.
class _AnchorPainter extends CustomPainter {
  _AnchorPainter(this.image, this.anchor, this.color);
  final ui.Image image;
  final Offset anchor;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 10.0;
    final light = Paint()..color = const Color(0xFFFFFFFF), dark = Paint()..color = const Color(0xFFE6E6E6);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final odd = ((x / cell).floor() + (y / cell).floor()).isOdd;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), odd ? dark : light);
      }
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final c = Offset(anchor.dx * size.width, anchor.dy * size.height);
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), line..color = color.withValues(alpha: 0.5));
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), line);
    canvas.drawCircle(c, 7, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_AnchorPainter old) => old.image != image || old.anchor != anchor;
}
