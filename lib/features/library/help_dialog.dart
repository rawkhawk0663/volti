import 'package:flutter/material.dart';

import '../../core/app_settings.dart';

/// Kurzanleitung: ein paar Seiten zum Durchblättern. Erscheint beim ersten
/// Start und ist jederzeit im Einstellungsfenster zu finden.
Future<void> showHelpDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _HelpDialog());

/// Beim allerersten Start einmal zeigen.
Future<void> showHelpOnFirstStart(BuildContext context, AppSettings settings) async {
  if (settings.flag('helpShown', orElse: false)) return;
  await settings.setFlag('helpShown', true);
  if (context.mounted) await showHelpDialog(context);
}

class _HelpPage {
  const _HelpPage(this.icon, this.title, this.points);
  final IconData icon;
  final String title;
  final List<String> points;
}

const _pages = [
  _HelpPage(Icons.waving_hand_outlined, 'Willkommen bei Volti', [
    'Volti ist dein Notenständer: Noten lesen, umblättern und mit dem Stift hineinschreiben.',
    'Alles geht mit Finger und Stift. Langes Drücken ist wie ein Rechtsklick und öffnet das Menü.',
    'Diese Anleitung findest du jederzeit wieder unter ⚙ → Kurzanleitung.',
  ]),
  _HelpPage(Icons.library_music_outlined, 'Noten in die Bibliothek', [
    '„Importieren“ holt PDFs in die Bibliothek. Volti legt eine Kopie an, deine Originale bleiben unverändert.',
    'Mit Ordnern ordnest du deine Noten, z. B. nach Projekt. Jedes Stück liegt in genau einem Ordner.',
    'Lange auf eine Kachel drücken: Infos wie Titel, Tonart und Tempo, Ordner, Seiten anordnen und mehr.',
    'Die Suche findet Titel, Komponisten und Tonarten.',
  ]),
  _HelpPage(Icons.menu_book_outlined, 'Spielen', [
    'Rechts tippen blättert weiter, links zurück. In der Mitte tippen zeigt kurz die Leiste.',
    'Pedale und Pfeiltasten blättern ebenfalls.',
    'Zwei Finger zoomen. Vergrössert verschiebt ein Finger die Seite.',
    'Im Querformat stehen zwei Seiten nebeneinander, jedes Umblättern geht eine Seite weiter.',
  ]),
  _HelpPage(Icons.edit_outlined, 'Mit dem Stift schreiben', [
    'Mit dem Stift ziehen zeichnet sofort. Das Radierer-Ende und die Seitentaste radieren.',
    'Der Finger zeichnet nie, die Hand darf also aufliegen.',
    '„Bearbeiten“ öffnet die Werkzeugleiste: Stift, Leuchtstift, Radierer, Text, Stempel, Formen, '
        'Lasso, Verschieben und Sprungmarken. Jedes Werkzeug hat ein eigenes Fenster mit Einstellungen und Favoriten.',
    'Mit Ebenen trennst du z. B. Fingersätze von Probennotizen und blendest sie einzeln ein und aus.',
  ]),
  _HelpPage(Icons.queue_music_outlined, 'Setlists', [
    'Eine Setlist stellt Songs für einen Gottesdienst oder ein Konzert zusammen. Sie verhält sich beim Spielen wie ein einziges Heft.',
    'Ein Notizblatt in der Setlist ist eine leere Seite für deine Notizen.',
    'Ebenen, die du in einer Setlist anlegst, gibt es nur dort. Notizen aus der Bibliothek erscheinen überall.',
    'Das Metronom (oben in der Notenansicht) übernimmt das Tempo jedes Songs.',
  ]),
  _HelpPage(Icons.cloud_sync_outlined, 'Abgleichen und sichern', [
    'Unter ⚙ → Sync gleicht Volti alles über einen Ordner ab, z. B. in Proton Drive. So sind alle Geräte auf dem gleichen Stand.',
    'Volti sichert jede Woche automatisch alles in eine Datei. Unter ⚙ → Sicherung kannst du sie einspielen. Dabei wird nichts gelöscht.',
    'Neue Versionen installierst du unter ⚙ → Über Volti.',
  ]),
];

class _HelpDialog extends StatefulWidget {
  const _HelpDialog();

  @override
  State<_HelpDialog> createState() => _HelpDialogState();
}

class _HelpDialogState extends State<_HelpDialog> {
  final _pager = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _go(int i) => _pager.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _page == _pages.length - 1;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: (size.height - 32).clamp(300, 560)),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Schliessen',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pager,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final page in _pages)
                    ListView(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                      children: [
                        Icon(page.icon, size: 44, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        Text(page.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        for (final point in page.points)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 7, right: 10),
                                  child: Icon(Icons.circle, size: 6, color: theme.colorScheme.primary),
                                ),
                                Expanded(child: Text(point, style: theme.textTheme.bodyLarge)),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: _page == 0 ? null : TextButton(onPressed: () => _go(_page - 1), child: const Text('Zurück')),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          GestureDetector(
                            onTap: () => _go(i),
                            child: Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _page ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: FilledButton(
                      onPressed: last ? () => Navigator.pop(context) : () => _go(_page + 1),
                      child: Text(last ? 'Los geht’s' : 'Weiter'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
