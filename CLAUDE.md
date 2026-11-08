# Volti – Hinweise für die Entwicklung

Volti ist ein PDF-Notenleser mit Stift-Anmerkungen. Hauptziel ist Windows (Surface Pro 9 mit Surface Pen), danach Android. Der Besitzer ist Berufsmusiker und programmiert nicht selbst. Erkläre Änderungen deshalb in einfacher Sprache und ohne Fachjargon.

## Sprache
- Die Oberfläche und die Code-Kommentare sind auf **Deutsch**, mit Schweizer Schreibweise: „ss“ statt „ß“ in Texten, die der Nutzer sieht.
- Bezeichner im Code sind auf Englisch.

## Technik
- Flutter `3.47.9` (in `.github/workflows/build.yml` festgelegt), Material 3. Markenfarbe Seegrün `#3BA796` (`VoltiColors.seafoam`), für Knöpfe das tiefere `#1A8070` und im Dunkelmodus `#5CC8B4`. Bibliothek und Setlists haben einen sanften Hintergrundverlauf (`VoltiBackground`). Logo und Icons erzeugt `tool/extract_brand.py`.
- PDF-Darstellung über `pdfrx` (PDFium). Seiten werden selbst gerendert und gecacht (`lib/core/pdf/page_image_cache.dart`), damit das Umblättern sofort geht.
- Builds laufen über GitHub Actions. Jeder Push auf `main` erzeugt ein Release mit `Volti-Windows.zip` und `Volti-Android.apk`.

## Aufbau
```
lib/
  app/            Theme, Markenfarben
  core/           Logik ohne UI
    ink/          Anmerkungsmodell (Striche, Zusammenführen)
    library/      Infos (ScoreMeta), Zusatzdatei (SidecarStore), Import, Bibliothek einlesen, Filter, Setlists
    pdf/          Seiten-Cache, Vorschaubilder
    sync/         Abgleich mit einem Sync-Ziel (SyncEngine, SyncStore; heute Ordner, später evtl. Dropbox)
    app_settings.dart  Nur geräteeigene Einstellungen (zuletzt geöffnet)
  features/
    library/      Bibliothek, Infos-Dialog, Setlists (LibraryController hält den Zustand)
    viewer/       Notenansicht, Stift-Ebene, Stift-Test
assets/brand/     Logo (erzeugt mit tool/extract_brand.py)
```

## Grundsätze, die nicht gebrochen werden dürfen
1. **Volti verwaltet seine Noten selbst.** Es gibt keinen frei wählbaren Bibliotheksordner, das wollte der Besitzer ausdrücklich so. PDFs kommen über den Import (`ScoreImporter`) als Kopie in den Datenordner `<ApplicationSupport>/Bibliothek/Noten/`. Die Originale bleiben unangetastet.
   Infos und Anmerkungen liegen in `<datei>.pdf.volti.json` neben der Kopie (Format `volti-score` v2; v1 `volti-annotations` muss lesbar bleiben). Setlists liegen in `Bibliothek/.volti/setlists/<id>.json` und verweisen auf Stücke über den Pfad relativ zu `Bibliothek` (z. B. `Noten/x.pdf`).
   Die PDFs werden nie verändert. Ein alter Bibliotheksordner aus v0.1.2 (`libraryRoot` in den Einstellungen) wird beim Start einmalig übernommen (`migrateLegacyLibrary`).
2. **Koordinaten sind normiert** (0..1 relativ zur Seite). Das gilt für Striche und für Text-Notizen (`TextNote`, im Feld `texts` der Zusatzdatei; Textgrösse relativ zur Seitenbreite).
3. **Sync-taugliches Datenmodell:** Infos werden pro Feld zusammengeführt (jüngste Änderung gewinnt). Jeder Strich hat eine UUID. Gelöschte Striche werden als Grabstein (`deleted: true`) behalten. Beim Speichern wird mit dem Stand auf der Festplatte zusammengeführt (`ScoreAnnotations.merge`). „Rückgängig“ beim Löschen erzeugt eine Kopie mit neuer ID.
4. **Mit dem Finger wird nie gezeichnet** (Handballenerkennung). Das Radierer-Ende und die Seitentaste des Stifts radieren.
5. Während eine Text-Notiz getippt wird (`_editingText`), ignoriert die Notenansicht alle Tasten. Sonst würden z. B. „p“ oder die Leertaste Werkzeuge wechseln oder umblättern.
   Pedale senden Tastendrücke. Alle Pfeiltasten, Bild auf/ab und die Leertaste blättern. Buttons in der Werkzeugleiste stehen in `ExcludeFocus`, damit sie keine Tastendrücke abfangen.

6. **Sync:** Ob eine fehlende Datei neu ist oder gelöscht wurde, entscheidet die gerätespezifische Basis (`sync_base.json`, Stand des letzten Abgleichs). `.volti.json` wird immer zusammengeführt. Die Sicherheitsbremse (Markierungsdatei `.volti/library.json` fehlt, oder mehr als die Hälfte der Noten würde gelöscht) darf nicht entfernt werden.

## Prüfen
```bash
flutter analyze
flutter test
```

## Stolperfallen
- `future.whenComplete(() => map.remove(key))` wartet auf sich selbst, wenn die Map Futures enthält. Immer einen Block-Körper `{ map.remove(key); }` verwenden.
- Beim Einlesen der Bibliothek werden die PDFs nicht geöffnet, weil Cloud-Ordner sonst alles herunterladen würden. Vorschaubilder entstehen erst, wenn eine Kachel sichtbar wird.
