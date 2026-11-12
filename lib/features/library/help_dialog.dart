import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../app/l10n.dart';

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

List<_HelpPage> get _pages => [
  _HelpPage(Icons.waving_hand_outlined, tr('Willkommen bei Volti', 'Welcome to Volti'), [
    tr(
      'Volti ist dein Notenständer: Noten lesen, umblättern und mit dem Stift hineinschreiben.',
      'Volti is your music stand: read your music, turn pages and write on it with the pen.',
    ),
    tr(
      'Alles geht mit Finger und Stift. Langes Drücken ist wie ein Rechtsklick und öffnet das Menü.',
      'Everything works with finger and pen. A long press is like a right-click and opens the menu.',
    ),
    tr(
      'Diese Anleitung findest du jederzeit wieder unter ⚙ → Kurzanleitung.',
      'You can find this guide again any time under ⚙ → Quick guide.',
    ),
  ]),
  _HelpPage(Icons.library_music_outlined, tr('Noten in die Bibliothek', 'Music into the library'), [
    tr(
      '„Importieren“ holt PDFs in die Bibliothek. Volti legt eine Kopie an, deine Originale bleiben unverändert.',
      '“Import” brings PDFs into the library. Volti makes a copy, your originals stay untouched.',
    ),
    tr(
      'Mit Ordnern ordnest du deine Noten, z. B. nach Projekt. Jedes Stück liegt in genau einem Ordner.',
      'Folders let you organise your music, e.g. by project. Each piece lives in exactly one folder.',
    ),
    tr(
      'Lange auf eine Kachel drücken: Infos wie Titel, Tonart und Tempo, Ordner, Seiten anordnen und mehr.',
      'Long-press a tile: details such as title, key and tempo, folder, arrange pages and more.',
    ),
    tr('Die Suche findet Titel, Komponisten und Tonarten.', 'The search finds titles, composers and keys.'),
  ]),
  _HelpPage(Icons.menu_book_outlined, tr('Spielen', 'Playing'), [
    tr(
      'Rechts tippen blättert weiter, links zurück. In der Mitte tippen zeigt kurz die Leiste.',
      'Tap on the right to turn forward, on the left to go back. Tapping in the middle briefly shows the toolbar.',
    ),
    tr('Pedale und Pfeiltasten blättern ebenfalls.', 'Pedals and arrow keys turn pages too.'),
    tr(
      'Zwei Finger zoomen. Vergrössert verschiebt ein Finger die Seite.',
      'Two fingers zoom. When zoomed in, one finger moves the page.',
    ),
    tr(
      'Im Querformat stehen zwei Seiten nebeneinander, jedes Umblättern geht eine Seite weiter.',
      'In landscape, two pages sit side by side, and each turn moves one page on.',
    ),
  ]),
  _HelpPage(Icons.edit_outlined, tr('Mit dem Stift schreiben', 'Writing with the pen'), [
    tr(
      'Mit dem Stift ziehen zeichnet sofort. Das Radierer-Ende und die Seitentaste radieren.',
      'Dragging with the pen draws right away. The eraser end and the side button erase.',
    ),
    tr(
      'Der Finger zeichnet nie, die Hand darf also aufliegen.',
      'Fingers never draw, so your hand can rest on the screen.',
    ),
    tr(
      '„Bearbeiten“ öffnet die Werkzeugleiste: Stift, Leuchtstift, Radierer, Text, Stempel, Formen, '
          'Lasso, Verschieben und Sprungmarken. Jedes Werkzeug hat ein eigenes Fenster mit Einstellungen und Favoriten.',
      '“Edit” opens the toolbar: pen, highlighter, eraser, text, stamps, shapes, '
          'lasso, move and jump links. Each tool has its own window with settings and favourites.',
    ),
    tr(
      'Mit Ebenen trennst du z. B. Fingersätze von Probennotizen und blendest sie einzeln ein und aus.',
      'Layers let you separate e.g. fingerings from rehearsal notes and show or hide them one by one.',
    ),
  ]),
  _HelpPage(Icons.queue_music_outlined, tr('Setlists', 'Setlists'), [
    tr(
      'Eine Setlist stellt Songs für einen Gottesdienst oder ein Konzert zusammen. Sie verhält sich beim Spielen wie ein einziges Heft.',
      'A setlist puts together the songs for a service or a concert. While playing, it behaves like a single book.',
    ),
    tr(
      'Ein Notizblatt in der Setlist ist eine leere Seite für deine Notizen.',
      'A note sheet in the setlist is a blank page for your notes.',
    ),
    tr(
      'Ebenen, die du in einer Setlist anlegst, gibt es nur dort. Notizen aus der Bibliothek erscheinen überall.',
      'Layers you create in a setlist exist only there. Notes from the library appear everywhere.',
    ),
    tr(
      'Das Metronom (oben in der Notenansicht) übernimmt das Tempo jedes Songs.',
      'The metronome (at the top of the music view) picks up the tempo of each song.',
    ),
  ]),
  _HelpPage(Icons.cloud_sync_outlined, tr('Abgleichen und sichern', 'Sync and backup'), [
    tr(
      'Unter ⚙ → Sync gleicht Volti alles über einen Ordner ab, z. B. in Proton Drive. So sind alle Geräte auf dem gleichen Stand.',
      'Under ⚙ → Sync, Volti syncs everything through a folder, e.g. in Proton Drive. That keeps all your devices up to date.',
    ),
    tr(
      'Volti sichert jede Woche automatisch alles in eine Datei. Unter ⚙ → Sicherung kannst du sie einspielen. Dabei wird nichts gelöscht.',
      'Volti automatically backs up everything into one file every week. Under ⚙ → Backup you can restore it. Nothing is deleted.',
    ),
    tr('Neue Versionen installierst du unter ⚙ → Über Volti.', 'You install new versions under ⚙ → About Volti.'),
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
                tooltip: tr('Schliessen', 'Close'),
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
                    child: _page == 0
                        ? null
                        : TextButton(onPressed: () => _go(_page - 1), child: Text(tr('Zurück', 'Back'))),
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
                      child: Text(last ? tr('Los geht’s', 'Let’s go') : tr('Weiter', 'Next')),
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
