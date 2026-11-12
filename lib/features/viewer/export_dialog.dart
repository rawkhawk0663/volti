import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'page_export.dart';
import '../../app/l10n.dart';

/// Noten als neues PDF speichern oder zum Drucken öffnen – auf Wunsch mit
/// allen eingeblendeten Anmerkungen, so wie die Seiten angezeigt werden.
///
/// [load] liefert die Stücke (öffnet sie bei Bedarf), [release] gibt
/// geöffnete Dateien wieder frei.
Future<void> showExportDialog(
  BuildContext context, {
  required String title,
  required Future<List<ExportPiece>> Function() load,
  Future<void> Function()? release,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(title: title, load: load),
  );
  await release?.call();
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.title, required this.load});
  final String title;
  final Future<List<ExportPiece>> Function() load;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _annotations = true;
  double? _progress;
  String? _message;

  bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  String get _fileName {
    final clean = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return '${clean.isEmpty ? tr('Noten', 'Music') : clean}${_annotations ? tr(' (mit Anmerkungen)', ' (with notes)') : ''}.pdf';
  }

  Future<List<int>?> _build() async {
    setState(() {
      _progress = 0;
      _message = null;
    });
    try {
      final pieces = await widget.load();
      final bytes = await buildExportPdf(
        pieces,
        withAnnotations: _annotations,
        onProgress: (d, t) {
          if (mounted) setState(() => _progress = t == 0 ? 1 : d / t);
        },
      );
      return bytes;
    } catch (e) {
      if (mounted) setState(() => _message = tr('Das ging nicht: $e', 'That didn’t work: $e'));
      return null;
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _save() async {
    String? path;
    if (_desktop) {
      final loc = await getSaveLocation(
        suggestedName: _fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF', extensions: ['pdf']),
        ],
      );
      if (loc == null) return;
      path = loc.path.toLowerCase().endsWith('.pdf') ? loc.path : '${loc.path}.pdf';
    }
    final bytes = await _build();
    if (bytes == null || !mounted) return;
    if (path == null) {
      // Android: in Voltis Dokumente-Ordner.
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'Export'));
      await dir.create(recursive: true);
      path = p.join(dir.path, _fileName);
    }
    await File(path).writeAsBytes(bytes, flush: true);
    if (mounted) setState(() => _message = tr('Gespeichert: $path', 'Saved: $path'));
  }

  Future<void> _print() async {
    final bytes = await _build();
    if (bytes == null || !mounted) return;
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'volti-druck'));
    await dir.create(recursive: true);
    final path = p.join(dir.path, _fileName);
    await File(path).writeAsBytes(bytes, flush: true);
    // Mit dem Standard-Programm öffnen (z. B. Edge oder Acrobat), dort drucken.
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', path], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [path], mode: ProcessStartMode.detached);
    } else {
      await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
    }
    if (mounted) {
      setState(
        () => _message = tr(
          'Geöffnet – drucke es im PDF-Programm (Strg+P).',
          'Opened – print it in your PDF program (Ctrl+P).',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    final hint = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return AlertDialog(
      title: Text(tr('«${widget.title}» als PDF', '«${widget.title}» as PDF')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                'Ein neues PDF, so wie du die Seiten siehst: in deiner Reihenfolge und zugeschnitten. '
                    'Das Original bleibt unverändert.',
                'A new PDF, just as you see the pages: in your order and cropped. '
                    'The original stays unchanged.',
              ),
              style: hint,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Mit Anmerkungen', 'With notes')),
              subtitle: Text(tr('Alle eingeblendeten Ebenen', 'All visible layers')),
              value: _annotations,
              onChanged: busy ? null : (v) => setState(() => _annotations = v),
            ),
            if (busy) ...[const SizedBox(height: 8), LinearProgressIndicator(value: _progress)],
            if (_message != null) ...[const SizedBox(height: 8), SelectableText(_message!, style: hint)],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.of(context).pop(), child: Text(tr('Schliessen', 'Close'))),
        if (_desktop)
          OutlinedButton.icon(
            onPressed: busy ? null : _print,
            icon: const Icon(Icons.print_outlined),
            label: Text(tr('Zum Drucken öffnen', 'Open for printing')),
          ),
        FilledButton.icon(
          onPressed: busy ? null : _save,
          icon: const Icon(Icons.save_alt),
          label: Text(_desktop ? tr('Speichern unter …', 'Save as …') : tr('Speichern', 'Save')),
        ),
      ],
    );
  }
}
