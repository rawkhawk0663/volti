import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/pdf/paper.dart';

/// Vorlage wählen (leer, Notenlinien, Tabulatur …), mit kleinen Vorschauen.
/// Mit [name] gibt es zusätzlich ein Namensfeld (für ein neues Notizblatt).
/// Gibt null zurück, wenn abgebrochen wurde.
Future<({Paper paper, String name})?> showPaperPicker(
  BuildContext context, {
  required String title,
  required String confirm,
  Paper initial = Paper.blank,
  String? name,
}) => showDialog(
  context: context,
  builder: (_) => _PaperPicker(title: title, confirm: confirm, initial: initial, name: name),
);

class _PaperPicker extends StatefulWidget {
  const _PaperPicker({required this.title, required this.confirm, required this.initial, this.name});
  final String title, confirm;
  final Paper initial;
  final String? name;

  @override
  State<_PaperPicker> createState() => _PaperPickerState();
}

class _PaperPickerState extends State<_PaperPicker> {
  late Paper _paper = widget.initial;
  late final _name = widget.name == null ? null : TextEditingController(text: widget.name);

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  void _done() {
    final n = _name?.text.trim() ?? '';
    if (_name != null && n.isEmpty) return;
    Navigator.of(context).pop((paper: _paper, name: n));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_name != null) ...[
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(labelText: tr('Name', 'Name')),
                  onSubmitted: (_) => _done(),
                ),
                const SizedBox(height: 16),
              ],
              Text(tr('Vorlage', 'Template'), style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in Paper.values)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _paper = p),
                      onDoubleTap: () {
                        setState(() => _paper = p);
                        _done();
                      },
                      child: Container(
                        width: 136,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _paper == p ? scheme.primary : scheme.outlineVariant,
                            width: _paper == p ? 2.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            AspectRatio(
                              aspectRatio: 210 / 297,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: CustomPaint(painter: PaperPreviewPainter(p)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 40,
                              child: Center(child: Text(p.label, textAlign: TextAlign.center, maxLines: 2)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: _done, child: Text(widget.confirm)),
      ],
    );
  }
}

/// Kleine Vorschau einer Vorlage.
class PaperPreviewPainter extends CustomPainter {
  PaperPreviewPainter(this.paper);
  final Paper paper;

  @override
  void paint(Canvas canvas, Size size) => paintPaper(canvas, size, paper, minWidth: 0.6);

  @override
  bool shouldRepaint(PaperPreviewPainter old) => old.paper != paper;
}
