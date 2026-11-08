import 'package:flutter/material.dart';

import '../../core/library/library_scanner.dart';
import '../../core/library/score_meta.dart';

/// Dialog zum Bearbeiten von Titel, Komponist, Genre, Tonart, Tags und Notizen.
/// Gibt die geänderten Felder zurück (oder null bei "Abbrechen").
Future<Map<String, Object?>?> showEditMetaDialog(
  BuildContext context, {
  required ScoreEntry entry,
  required List<String> knownComposers,
  required List<String> knownGenres,
  required List<String> knownTags,
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) =>
        _EditMetaDialog(entry: entry, knownComposers: knownComposers, knownGenres: knownGenres, knownTags: knownTags),
  );
}

class _EditMetaDialog extends StatefulWidget {
  const _EditMetaDialog({
    required this.entry,
    required this.knownComposers,
    required this.knownGenres,
    required this.knownTags,
  });

  final ScoreEntry entry;
  final List<String> knownComposers;
  final List<String> knownGenres;
  final List<String> knownTags;

  @override
  State<_EditMetaDialog> createState() => _EditMetaDialogState();
}

class _EditMetaDialogState extends State<_EditMetaDialog> {
  late final ScoreMeta m = widget.entry.meta;
  late final guess = guessFromFileName(widget.entry.path);
  // Vorschlag aus dem Dateinamen gleich eintragen, damit man ihn sieht und
  // übernehmen oder ändern kann.
  late final _title = TextEditingController(text: m.text(ScoreMeta.title) ?? guess.title);
  late final _composer = TextEditingController(text: m.text(ScoreMeta.composer) ?? guess.composer ?? '');
  late final _genre = TextEditingController(text: m.text(ScoreMeta.genre) ?? '');
  late final _key = TextEditingController(text: m.text(ScoreMeta.key) ?? '');
  late final _notes = TextEditingController(text: m.text(ScoreMeta.notes) ?? '');
  late final List<String> _tags = [...m.tagList];
  final _tagInput = TextEditingController();

  @override
  void dispose() {
    for (final c in [_title, _composer, _genre, _key, _notes, _tagInput]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addTag(String t) {
    t = t.trim().replaceAll(',', '');
    if (t.isEmpty || _tags.contains(t)) return;
    setState(() => _tags.add(t));
    _tagInput.clear();
  }

  void _save() {
    if (_tagInput.text.trim().isNotEmpty) _addTag(_tagInput.text);
    Navigator.of(context).pop(<String, Object?>{
      ScoreMeta.title: _title.text,
      ScoreMeta.composer: _composer.text,
      ScoreMeta.genre: _genre.text,
      ScoreMeta.key: _key.text,
      ScoreMeta.notes: _notes.text,
      ScoreMeta.tags: _tags,
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.knownTags.where((t) => !_tags.contains(t)).take(12).toList();
    return AlertDialog(
      title: const Text('Infos bearbeiten'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Titel'),
              ),
              const SizedBox(height: 12),
              _Suggest(controller: _composer, label: 'Komponist', options: widget.knownComposers),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Suggest(controller: _genre, label: 'Genre', options: widget.knownGenres),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _key,
                      decoration: const InputDecoration(labelText: 'Tonart'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in _tags) InputChip(label: Text(t), onDeleted: () => setState(() => _tags.remove(t))),
                  ],
                ),
              ),
              TextField(
                controller: _tagInput,
                decoration: const InputDecoration(labelText: 'Tag hinzufügen', helperText: 'Mit Enter bestätigen'),
                onSubmitted: _addTag,
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in suggestions)
                        ActionChip(
                          label: Text(t),
                          avatar: const Icon(Icons.add, size: 16),
                          onPressed: () => _addTag(t),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Notizen'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}

/// Textfeld mit Vorschlägen aus bereits verwendeten Werten.
class _Suggest extends StatefulWidget {
  const _Suggest({required this.controller, required this.label, required this.options});
  final TextEditingController controller;
  final String label;
  final List<String> options;

  @override
  State<_Suggest> createState() => _SuggestState();
}

class _SuggestState extends State<_Suggest> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (v) {
        final q = v.text.toLowerCase().trim();
        if (q.isEmpty) return const [];
        return options.where((o) => o.toLowerCase().contains(q) && o.toLowerCase() != q).take(8);
      },
      fieldViewBuilder: (context, c, f, onSubmit) => TextField(
        controller: c,
        focusNode: f,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => onSubmit(),
      ),
      optionsViewBuilder: (context, onSelected, opts) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [for (final o in opts) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o))],
            ),
          ),
        ),
      ),
    );
  }
}
