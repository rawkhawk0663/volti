# Volti – Hinweise für die Entwicklung

Volti ist ein PDF-Notenleser mit Stift-Anmerkungen. Hauptziel ist Windows (Surface Pro 9 mit Surface Pen), danach Android. Der Besitzer ist Berufsmusiker und programmiert nicht selbst. Erkläre Änderungen deshalb in einfacher Sprache und ohne Fachjargon.

## Sprache
- Die Oberfläche und die Code-Kommentare sind auf **Deutsch**, mit Schweizer Schreibweise: „ss“ statt „ß“ in Texten, die der Nutzer sieht.
- Bezeichner im Code sind auf Englisch.

## Technik
- Flutter `3.47.9` (in `.github/workflows/build.yml` festgelegt), Material 3, Akzentfarbe Terrakotta `#B5593A`.
- PDF-Darstellung über `pdfrx` (PDFium). Seiten werden selbst gerendert und gecacht (`lib/core/pdf/page_image_cache.dart`), damit das Umblättern sofort geht.
- Builds laufen über GitHub Actions. Jeder Push auf `main` erzeugt ein Release mit `Volti-Windows.zip` und `Volti-Android.apk`.

## Aufbau
```
lib/
  app/            Theme, Markenfarben
  core/           Logik ohne UI: Anmerkungsmodell, Speicherung, PDF-Cache
  features/       Bildschirme: home/, viewer/
assets/brand/     Logo (erzeugt mit tool/extract_brand.py)
```

## Grundsätze, die nicht gebrochen werden dürfen
1. **PDFs werden nie verändert.** Anmerkungen liegen in `<datei>.pdf.volti.json` neben dem PDF.
2. **Koordinaten sind normiert** (0..1 relativ zur Seite).
3. **Sync-taugliches Datenmodell:** Jeder Strich hat eine UUID. Gelöschte Striche werden als Grabstein (`deleted: true`) behalten. Beim Speichern wird mit dem Stand auf der Festplatte zusammengeführt (`ScoreAnnotations.merge`). „Rückgängig“ beim Löschen erzeugt eine Kopie mit neuer ID.
4. **Mit dem Finger wird nie gezeichnet** (Handballenerkennung). Das Radierer-Ende und die Seitentaste des Stifts radieren.
5. Pedale senden Tastendrücke. Alle Pfeiltasten, Bild auf/ab und die Leertaste blättern. Buttons in der Werkzeugleiste stehen in `ExcludeFocus`, damit sie keine Tastendrücke abfangen.

## Prüfen
```bash
flutter analyze
flutter test
```
