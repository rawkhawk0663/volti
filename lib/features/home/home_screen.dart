import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/recent_files.dart';
import '../viewer/viewer_screen.dart';

/// Startbildschirm: Logo, "Noten öffnen" und zuletzt geöffnete Stücke.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _recent = RecentFiles();
  List<String> _files = [];

  @override
  void initState() {
    super.initState();
    _recent.load().then((f) => mounted ? setState(() => _files = f) : null);
  }

  Future<void> _pick() async {
    const pdf = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
      uniformTypeIdentifiers: ['com.adobe.pdf'],
    );
    final file = await openFile(acceptedTypeGroups: const [pdf]);
    if (file != null) await _open(file.path);
  }

  Future<void> _open(String path) async {
    final files = await _recent.add(path);
    if (!mounted) return;
    setState(() => _files = files);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ViewerScreen(pdfPath: path)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Image.asset('assets/brand/volti_mark.png', height: 72),
                    const SizedBox(width: 14),
                    Image.asset(
                      'assets/brand/volti_wordmark.png',
                      height: 54,
                      color: dark ? Colors.white : null,
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.folder_open),
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Noten öffnen (PDF)')),
                ),
                const SizedBox(height: 32),
                if (_files.isNotEmpty) ...[
                  Text('Zuletzt geöffnet', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      for (final f in _files)
                        ListTile(
                          leading: const Icon(Icons.music_note_outlined),
                          title: Text(p.basenameWithoutExtension(f)),
                          subtitle: Text(p.dirname(f), maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _open(f),
                          trailing: IconButton(
                            tooltip: 'Aus der Liste entfernen',
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              final files = await _recent.remove(f);
                              if (mounted) setState(() => _files = files);
                            },
                          ),
                        ),
                    ]),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Prototyp – Meilenstein 1: PDF anzeigen, blättern, mit Stift schreiben.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
