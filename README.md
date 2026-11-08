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

**Notenansicht – Spielansicht**

Beim Öffnen siehst du nur die Noten, im Vollbild. Die Leiste erscheint kurz und verschwindet dann wieder.

| Aktion | So geht's |
|---|---|
| Umblättern | Pedal (iRig BlueTurn in jedem Modus), Pfeiltasten, Bild ↑/↓, Leertaste, im **rechten oder linken Drittel** tippen oder wischen |
| Leiste ein-/ausblenden | **In die Mitte tippen**. Am Computer genügt es auch, die Maus an den oberen Rand zu bewegen |
| Vollbild ein/aus | Symbol in der Leiste oder **F11**. Volti merkt sich die Einstellung |
| Sofort zeichnen | Mit dem **Stift aufsetzen und ziehen**. Kurz antippen blättert weiterhin. Ausschalten über ⋮ → „Mit dem Stift sofort zeichnen“ |
| Radieren mit dem Surface Pen | Radierer-Ende des Stifts benutzen oder Seitentaste gedrückt halten, auch in der Spielansicht |
| Seite springen | Leiste einblenden, dann den Regler unten ziehen |

**Notenansicht – Bearbeiten**

Tippe in der Leiste auf **Bearbeiten**. Am Rand erscheint die Werkzeug-Palette. Während du zeichnest, wird sie fast durchsichtig.

| Aktion | So geht's |
|---|---|
| Stift-Vorlage wählen | Antippen oder Taste **1–9**. **P** wählt den ersten Stift, **H** den ersten Textmarker |
| Vorlage anpassen | Die gewählte Vorlage nochmals antippen (oder lange drücken): Stift/Textmarker, Farbe, Breite und Deckkraft |
| Neue Vorlage | **+** in der Palette |
| Radierer | Symbol oder Taste **E**, dann eine von drei Grössen wählen |
| Text-Notiz | Symbol **Tт** oder Taste **T**, dann auf die Stelle tippen und schreiben. **Enter** = fertig, **Umschalt+Enter** = neue Zeile, **Esc** = abbrechen |
| Rückgängig / Wiederholen | Pfeile in der Palette oder **Strg+Z** / **Strg+Y** |
| Seite leeren | Papierkorb-Symbol in der Palette (lässt sich rückgängig machen) |
| Palette auf die andere Seite | Doppelpfeil unten in der Palette |
| Fertig | ✓ oben in der Palette oder **Esc** |

Die Vorlage „Abdecken“ (weiss) eignet sich, um Teile der Noten zu überdecken, zum Beispiel bei Wiederholungen. Stift-Vorlagen werden mit deinen anderen Geräten abgeglichen.

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

## Sync zwischen deinen Geräten

Wenn du Volti auf mehreren Geräten nutzt, etwa auf dem Surface und am Desktop-PC, kannst du alles abgleichen lassen:

1. Tippe auf das **Wolken-Symbol** oben oder auf ⚙ → **Sync einrichten …**
2. Wähle einen Ordner in **Proton Drive**, zum Beispiel einfach „Proton Drive“ selbst. Volti legt darin einen Unterordner **Volti** an.
3. Auf dem zweiten Gerät wählst du denselben Ordner beziehungsweise den Ordner „Volti“ darin.

Ab dann gleicht Volti beim Start, alle zwei Minuten und kurz nach jeder Änderung ab:
- Neue Noten, Infos, Anmerkungen und Setlists kommen auf alle Geräte.
- Anmerkungen von zwei Geräten werden **zusammengeführt**, nie überschrieben.
- Löschst du ein Stück auf einem Gerät, verschwindet es auch auf den anderen.
- Ist der Sync-Ordner nicht erreichbar, zum Beispiel weil Proton Drive nicht läuft, oder würde ein Abgleich mehr als die Hälfte deiner Noten löschen, bricht Volti zur Sicherheit ab. Das Wolken-Symbol wird dann rot.

## Fahrplan

- [x] **0** – Repository und automatischer Build
- [x] **1** – Stift-Prototyp: PDF, Blättern, Pedal, Stift, Radierer
- [x] **2** – Bibliothek mit Import, Metadaten (Komponist, Genre, Tags), Suche und Setlists *(zum Testen bereit)*
- [x] **3** – Sync zwischen Geräten über einen Ordner (z. B. Proton Drive) *(zum Testen bereit)*
- [ ] **4** – Android
- [ ] **5** – Halbe Seitenwechsel, Sprünge bei Wiederholungen, Metronom, Audio und mehr

## Für Entwickler

Flutter `3.47.9`. Siehe [`CLAUDE.md`](CLAUDE.md) für Aufbau und Konventionen.

```bash
flutter test
flutter run -d windows
```
