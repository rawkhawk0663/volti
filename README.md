<p align="center"><img src="assets/brand/volti_mark.png" height="80"> &nbsp; <img src="assets/brand/volti_wordmark.png" height="60"></p>

**Volti** ist ein Notenleser für Musikerinnen und Musiker: Noten als PDF anzeigen, mit Pedal umblättern und mit dem Stift Anmerkungen machen. Die App läuft auf Windows, besonders auf dem Surface mit Stift, und später auch auf Android.

## Volti herunterladen und starten (Windows)

1. Öffne **[Releases → neueste Version](../../releases/latest)**.
2. Lade **`Volti-Windows.zip`** herunter.
3. Entpacke die ZIP-Datei, zum Beispiel nach `Dokumente\Volti`. Wichtig: Starte die App nicht direkt aus der ZIP-Datei.
4. Starte **`Volti.exe`**.
   Beim ersten Start meldet Windows eventuell „Der Computer wurde durch Windows geschützt“. Klicke auf **Weitere Informationen → Trotzdem ausführen**. Das kommt daher, dass die App nicht kostenpflichtig signiert ist.

Für ein Update lädst du einfach die neueste ZIP-Datei herunter und ersetzt den Ordner. Deine Anmerkungen bleiben erhalten, weil sie neben deinen PDFs gespeichert sind.

## Erster Start

Volti startet mit einer leeren Bibliothek. Über **Importieren** holst du deine Noten herein:
- **PDFs importieren …** fügt einzelne oder mehrere PDFs hinzu.
- **Ganzen Ordner importieren …** fügt alle PDFs eines Ordners hinzu, inklusive Unterordnern. Das ist praktisch, um eine bestehende Notensammlung auf einmal zu übernehmen.

Volti legt dabei eine **Kopie** in seinem eigenen Datenordner ab. Deine Originaldateien bleiben unverändert.

## Bedienung

**Bibliothek**
- **Suchen** findet Stücke nach Titel, Komponist, Genre oder Tag. Sortieren und filtern kannst du nach Genre und Tag.
- **⋮** an einer Kachel, ein Rechtsklick oder langes Drücken öffnet ein Menü mit **Infos bearbeiten** (Titel, Komponist, Genre, Tonart, Tags, Notizen), **Zu Setlist hinzufügen** und **Löschen**.
- Heisst eine Datei `Komponist - Titel.pdf`, schlägt Volti Komponist und Titel automatisch vor.
- Wird dieselbe Datei nochmals importiert, erkennt Volti das und legt sie nicht doppelt an.

**Setlists**
- Lege eine Setlist an, füge Stücke hinzu und ändere die Reihenfolge, indem du ein Stück am Griff ☰ ziehst.
- Mit **Spielen** geht es nach der letzten Seite eines Stücks direkt zum nächsten Stück, rückwärts genauso. Oben links springst du über „Stück 2/5 ▾“ direkt zu einem anderen Stück.

**Notenansicht**

| Aktion | So geht's |
|---|---|
| Umblättern | Pedal (iRig BlueTurn in jedem Modus), Pfeiltasten, Bild ↑/↓, Leertaste, rechts/links tippen oder wischen |
| Stift / Textmarker / Radierer | Symbole oben oder Tasten **P** / **H** / **E**; zurück zum Lesen mit **Esc** |
| Radieren mit dem Surface Pen | Radierer-Ende des Stifts benutzen oder Seitentaste gedrückt halten, auch im Lese-Modus |
| Rückgängig / Wiederholen | Pfeil-Symbole oder **Strg+Z** / **Strg+Y** |
| Stift-Test | Symbol ((•)) oben zeigt Druck, Gerätetyp, Tasten und Ereignisrate |

Mit dem Finger wird nie gezeichnet. So hinterlässt der Handballen beim Schreiben keine Spuren.

## Wo speichert Volti deine Daten?

Alles liegt in Voltis eigenem **Datenordner**. Du öffnest ihn über ⚙ → **Datenordner öffnen**, etwa für ein Backup:

```
Bibliothek/
├── Noten/
│   ├── Bach - Suite 1.pdf
│   └── Bach - Suite 1.pdf.volti.json   ← Infos und Anmerkungen zu diesem Stück
└── .volti/setlists/…                   ← deine Setlists
```

Die PDFs selbst werden nie verändert. Nur auf dem jeweiligen Gerät gespeichert werden „zuletzt geöffnet“ und die Vorschaubilder.

## Fahrplan

- [x] **0** – Repository und automatischer Build
- [x] **1** – Stift-Prototyp: PDF, Blättern, Pedal, Stift, Radierer
- [x] **2** – Bibliothek mit Import, Metadaten (Komponist, Genre, Tags), Suche und Setlists *(zum Testen bereit)*
- [ ] **3** – Sync des Datenordners zwischen Geräten
- [ ] **4** – Android
- [ ] **5** – Halbe Seitenwechsel, Sprünge bei Wiederholungen, Metronom, Audio und mehr

## Für Entwickler

Flutter `3.47.9`. Siehe [`CLAUDE.md`](CLAUDE.md) für Aufbau und Konventionen.

```bash
flutter test
flutter run -d windows
```
