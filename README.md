<p align="center"><img src="assets/brand/volti_mark.png" height="80"> &nbsp; <img src="assets/brand/volti_wordmark.png" height="60"></p>

**Volti** ist ein Notenleser für Musikerinnen und Musiker: Noten als PDF anzeigen, mit Pedal umblättern und mit dem Stift Anmerkungen machen. Die App läuft auf Windows, besonders auf dem Surface mit Stift, und später auch auf Android.

## Volti herunterladen und starten (Windows)

1. Öffne **[Releases → neueste Version](../../releases/latest)**.
2. Lade **`Volti-Windows.zip`** herunter.
3. Entpacke die ZIP-Datei, zum Beispiel nach `Dokumente\Volti`. Wichtig: Starte die App nicht direkt aus der ZIP-Datei.
4. Starte **`Volti.exe`**.
   Beim ersten Start meldet Windows eventuell „Der Computer wurde durch Windows geschützt“. Klicke auf **Weitere Informationen → Trotzdem ausführen**. Das kommt daher, dass die App nicht kostenpflichtig signiert ist.

Für ein Update lädst du einfach die neueste ZIP-Datei herunter und ersetzt den Ordner. Deine Anmerkungen bleiben erhalten, weil sie neben deinen PDFs gespeichert sind.

## Bedienung (Prototyp)

| Aktion | So geht's |
|---|---|
| Umblättern | Pedal (iRig BlueTurn in jedem Modus), Pfeiltasten, Bild ↑/↓, Leertaste, rechts/links tippen oder wischen |
| Stift / Textmarker / Radierer | Symbole oben oder Tasten **P** / **H** / **E**; zurück zum Lesen mit **Esc** |
| Radieren mit dem Surface Pen | Radierer-Ende des Stifts benutzen oder Seitentaste gedrückt halten, auch im Lese-Modus |
| Rückgängig / Wiederholen | Pfeil-Symbole oder **Strg+Z** / **Strg+Y** |
| Stift-Test | Symbol ((•)) oben zeigt Druck, Gerätetyp, Tasten und Ereignisrate |

Mit dem Finger wird nie gezeichnet. So hinterlässt der Handballen beim Schreiben keine Spuren.

## Wo werden die Anmerkungen gespeichert?

Direkt neben dem PDF, als kleine Zusatzdatei:

```
Bach - Suite 1.pdf
Bach - Suite 1.pdf.volti.json   ← deine Anmerkungen
```

Das PDF selbst wird nie verändert. Liegt der Ordner in einem Cloud-Ordner wie Proton Drive, OneDrive oder Dropbox, werden die Anmerkungen automatisch mitsynchronisiert. Änderungen von zwei Geräten werden zusammengeführt statt überschrieben.

## Fahrplan

- [x] **0** – Repository und automatischer Build
- [ ] **1** – Stift-Prototyp: PDF, Blättern, Pedal, Stift, Radierer *(zum Testen auf dem Surface bereit)*
- [ ] **2** – Bibliothek mit Ordnern, Metadaten (Komponist, Genre, Tags), Suche und Setlists
- [ ] **3** – Sync zwischen Geräten über einen Cloud-Ordner
- [ ] **4** – Android
- [ ] **5** – Halbe Seitenwechsel, Sprünge bei Wiederholungen, Metronom, Audio und mehr

## Für Entwickler

Flutter `3.47.9`. Siehe [`CLAUDE.md`](CLAUDE.md) für Aufbau und Konventionen.

```bash
flutter test
flutter run -d windows
```
