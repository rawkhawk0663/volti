import 'dart:math' as math;

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
      'Am Computer kannst du PDFs auch einfach aus dem Datei-Explorer ins Volti-Fenster ziehen.',
      'On a computer you can also simply drag PDFs from File Explorer into the Volti window.',
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
      'Unten zeigt die Bildleiste alle Seiten. Antippen springt hin. Der Knopf mit den vier Kästchen oben zeigt alle Seiten gross.',
      'The strip at the bottom shows every page. Tap one to jump there. The button with four squares at the top shows all pages large.',
    ),
    tr(
      'Zwei Finger zoomen. Vergrössert verschiebt ein Finger die Seite.',
      'Two fingers zoom. When zoomed in, one finger moves the page.',
    ),
    tr(
      'Im Querformat stehen zwei Seiten nebeneinander, jedes Umblättern geht eine Seite weiter.',
      'In landscape, two pages sit side by side, and each turn moves one page on.',
    ),
    tr(
      'Mit dem Kopfhörer-Knopf oben ordnest du einem Stück eine Aufnahme zu und spielst mit, auch langsamer oder '
          'als Schleife. Taste K startet und hält an. „Spuren trennen“ gibt dir ein Mischpult für Gesang, '
          'Instrumente, Bass und Schlagzeug.',
      'The headphones button at the top attaches a recording to a piece so you can play along, also slower or '
          'as a loop. The K key starts and stops it. “Separate tracks” gives you a mixer for vocals, '
          'instruments, bass and drums.',
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
      'Mit „TAB“ ziehst du eine Tabulatur auf und tippst Bundzahlen und Rhythmus mit der Tastatur oder dem '
          'Zahlenfeld (Tasten unter ⚙ → Noteneingabe).',
      'With “TAB” you drag out a tablature and type frets and rhythm with the keyboard or the keypad '
          '(keys under ⚙ → Note input).',
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
      'Ein Notizblatt in der Setlist ist eine Seite für deine Notizen, leer oder mit Notenlinien, Tabulatur oder Akkord-Kästchen.',
      'A note sheet in the setlist is a page for your notes, blank or with staff lines, tablature or chord boxes.',
    ),
    tr(
      'Ebenen, die du in einer Setlist anlegst, gibt es nur dort. Notizen aus der Bibliothek erscheinen überall.',
      'Layers you create in a setlist exist only there. Notes from the library appear everywhere.',
    ),
    tr(
      'Das Metronom (oben in der Notenansicht) übernimmt das Tempo jedes Songs. Daneben liegen Stimmgerät und Stimmton.',
      'The metronome (at the top of the music view) picks up the tempo of each song. Next to it are the tuner and pitch pipe.',
    ),
    tr(
      'Für Lehrpersonen: Unter ⚙ lässt sich der Bereich „Unterricht“ einschalten, mit einer Übersicht über den Tag, '
          'einer Kartei pro Schüler:in oder Gruppe und To-Dos. Notizen in den Noten gelten dort nur für diese Person.',
      'For teachers: under ⚙ you can switch on the “Teaching” area, with an overview of the day, '
          'a record per student or group, and to-dos. Notes in the music there apply only to that person.',
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
                                _Bullet(style: theme.textTheme.bodyLarge!, color: theme.colorScheme.primary),
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

/// Aufzählungspunkt, genau auf die Mitte der Kleinbuchstaben der ersten
/// Zeile ausgerichtet (aus der Schrift berechnet, passt bei jeder Grösse).
class _Bullet extends StatelessWidget {
  const _Bullet({required this.style, required this.color});
  final TextStyle style;
  final Color color;

  static const _size = 6.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final tp = TextPainter(
      text: TextSpan(text: 'x', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.dispose();
    // Höhe der Kleinbuchstaben (bei Roboto gut die Hälfte der Schriftgrösse).
    final xHeight = scaler.scale(style.fontSize ?? 16) * 0.53;
    final middle = baseline - xHeight / 2;
    return Padding(
      padding: EdgeInsets.only(top: math.max(0, middle - _size / 2), right: 12),
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
