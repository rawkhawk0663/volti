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
    viewer/       Notenansicht (Spielansicht + Bearbeiten), Stift-Ebene, Text-Ebene, Werkzeug-Palette,
                  ToolController (Werkzeuge + Stift-Vorlagen app-weit, via ToolScope), Vollbild, Stift-Test
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

7. **Beim Spielen nicht stören:** Die Notenansicht startet als Spielansicht, ohne Leisten und im Vollbild (Gerätevorliebe). Tippen links oder rechts blättert, in der Mitte blendet es die Leiste kurz ein (4 s).
   Mit dem Stift *ziehen* zeichnet sofort. Ein Antippen unterhalb von `kTouchSlop` bleibt ein Antippen und erzeugt keinen Strich. Wischen mit dem Stift blättert nie.
   Beim Bearbeiten steht eine feste Werkzeugleiste am Seitenrand (`ToolOverlay`). Jedes Werkzeug hat ein eigenes, frei verschiebbares Einstellungsfenster (`ToolPopover`) mit Favoriten. Beim Werkzeugwechsel erscheint es an derselben Stelle (`ToolController.popoverOffset`). Das aktive Werkzeug nochmals antippen wählt es ab (`ToolMode.none`).
   Leiste und Fenster bleiben beim Zeichnen deckend (siehe 8). Das Fenster steht in einer `TextFieldTapRegion`, damit Stiländerungen eine gerade getippte Notiz nicht beenden.
   Einstellungen und Favoriten liegen in `Bibliothek/.volti/presets.json` (Format `volti-tools` v2; v1 `volti-presets` wird zu Favoriten) und werden synchronisiert (jüngste Fassung gewinnt).
   Text-Notizen haben eine eigene Text- und Hintergrundfarbe (`bg`, 0 = durchsichtig). Ältere Notizen ohne `bg` behalten den hellen Hintergrund `0xC8FFFFFF`.
   Vollbild gibt es nur von Hand (F11, Esc, Symbol), über `window_manager` **0.5.x** (0.6 baut auf einer neuen, ungeprüften Grundlage auf). Das automatische Vollbild beim Öffnen hat unter Windows nicht zuverlässig funktioniert und wurde auf Wunsch des Besitzers entfernt. Bitte nicht wieder einbauen. Ein maximiertes Fenster wird vor dem Vollbild auf normale Grösse gesetzt und danach wieder maximiert.
   Hinter der Notenseite liegt Anthrazit (`VoltiColors.anthracite`). Die Seite hat keinen Schatten, weil weiche Schatten beim Malen teuer sind.
   Radierer: „Ganze Elemente“ (Standard) oder „Teilweise“ (`eraserPartial`, `InkController.replaceStroke` teilt Striche). Das Radierer-Ende des Stifts nutzt dieselbe Einstellung. Ein Radier-Zug ist ein einziger Rückgängig-Schritt (`beginBatch`/`endBatch`).
   Text-Notizen: Schriften `VoltiSans` (Roboto), `VoltiSerif` (Noto Serif) und `VoltiMono` (Roboto Mono) liegen in `assets/fonts` (OFL). Es sind variable Schriften: Fett wird über `FontVariation.weight` eingestellt. Felder `font`, `b` und `i` in der Zusatzdatei.
8. **Flüssigkeit:** Notenseite, Strich-Ebenen, Text-Ebene, Leisten und Einstellungsfenster stehen jeweils in einer eigenen `RepaintBoundary`.
   **Wichtig:** Flutters Grafik-Technik malt alle Vektor-Zeichnungen bei *jedem* Bild neu (kein automatischer Zwischenspeicher). Deshalb werden fertige Striche und Stempel einer Seite in ein Bild umgewandelt (`_StrokesImage`). Kommt nur etwas dazu, wird es auf das bestehende Bild gemalt (`toImage`, nicht `toImageSync`, sonst hält jedes Bild alle früheren im Speicher fest). Nur wenn etwas verschwindet oder sich ändert, entsteht das Bild ganz neu. Speichern allein löst nichts aus (Vergleich über ID und Änderungszeit). Leiste und Fenster haben keinen Schatten. Auch der entstehende Strich legt seinen Anfang alle 24 Punkte als Bild ab. Messung auf dem Surface Pro 9 (i7-1255U) vorher: 75 ms Malen pro Bild, 12 Bilder/s.
   Keine Durchsichtigkeits-Animationen beim Zeichnen: Leiste und Fenster bleiben deckend, auf Wunsch des Besitzers und weil Durchsichtigkeit pro Bild Zeit kostet.
   Stift-Verzögerung: Im Windows-Runner (`flutter_window.cpp`, `DisablePenDelays`) sind die Windows-Stiftkomfortfunktionen abgeschaltet (Gedrückt-halten-Rechtsklick, Tipp-Kreise, Flicks). Der entstehende Strich malt pro Bild nur die neuen Teilstücke (Zwischenbild) und zeigt eine kurze Vorhersage (~18 ms, nur Anzeige). Die Messung steht im Stift-Test (`PerfMeter`: Verzögerung und Bild-Zeiten).
   Beim Ziehen des Einstellungsfensters ändert sich nur die Position (`ValueListenableBuilder`), nicht der Inhalt. Die Notenansicht baut sich bei Werkzeug-Änderungen nur neu auf, wenn sich das Werkzeug selbst ändert.

9. **Stempel, Formen, Lineal (Paket 1b):** Stempel sind eigene Elemente (`Stamp`, Feld `stamps` in der Zusatzdatei) mit Zeichen aus **Bravura** (SMuFL, `assets/fonts/Bravura.otf`, OFL). Die Sammlung `lib/core/ink/stamp_catalog.dart` wird mit `tool/make_stamps.py` erzeugt und enthält die Tinten-Ausdehnung jedes Zeichens, damit Stempel genau mittig sitzen (`paintGlyph`).
   Die Gruppen stehen im Fenster als Tabs, zwischen denen man wischen kann (`TabBarView`, auch mit Maus und Stift). Gespeicherte Stempel werden über den Codepunkt gefunden, Reihenfolge und Gruppen dürfen sich also ändern.
   Formen werden als gewöhnliche Striche gespeichert (`shapeGeometry`), eine Form ist ein Rückgängig-Schritt. Crescendo/Decrescendo haben eine feste Öffnung (`kHairpinOpening`, relativ zur Seitenbreite), unabhängig von der Länge. Notenlinien (`ShapeKind.staff`) sind fünf waagrechte Striche. Die Höhe kommt vom senkrechten Ziehen, fast waagrecht gezogen gilt `kStaffHeight`. Das Lineal (`RulerOverlay`) bewegen nur Finger (ein Finger verschiebt, ein zweiter dreht um den haltenden Finger; Einrasten bei 0°/90°) oder die Maus (ziehen, Mausrad dreht). Eine durchlässige Fläche beobachtet die Finger, das Lineal selbst nimmt keine Berührungen an. `ToolController.rulerPointers` sorgt dafür, dass die Maus dabei nicht zeichnet, und `rulerRecentlyUsed`, dass ein Antippen nicht umblättert. Gabeln sind immer waagrecht. Die Höhe der Notenlinien ändert sich erst ab `kStaffFreeHeight`. Der Stift zeichnet nahe einer Kante gerade daran entlang (`_nearRulerEdge`). Stempel werden ins Strich-Bild mitgemalt.

10. **Lasso (Paket 2a):** `ToolMode.lasso`. Die Auswahl (`InkSelection`: Stück, Seite, `SelectionIds`) und die Zwischenablage (`InkClip`) liegen app-weit im `ToolController`. So kann man in ein anderes Stück einfügen. Eingefügt wird auf die zuletzt berührte Seite.
   Verschieben und Vergrössern ändert die Elemente selbst und behält ihre IDs (`InkController.transformSelection`, `SelectionTransform`, Änderungszeit neu, damit der Sync die jüngste Fassung nimmt). Rückgängig über `strokesBefore`/`stampsBefore`/`textsBefore`. Einfügen und Duplizieren erzeugen neue IDs.
   Ausgewähltes wird nicht im Strich-Bild gemalt, sondern in der Auswahl-Ebene (`_SelectionPainter`), damit es sich beim Ziehen flüssig mitbewegt. Die Text-Ebene blendet ausgewählte Notizen aus. Der Finger wählt nie aus. Beim Blättern wird die Auswahl aufgehoben, weil sonst z. B. „Entf“ Unsichtbares löschen würde.
   Umfärben behält die Deckkraft (`recolorKeepingAlpha`), z. B. beim Textmarker.

11. **Ebenen (Paket 2b):** pro Stück, gelten auf allen Seiten (`AnnotationLayer`, Feld `layers` in der Zusatzdatei). Elemente tragen `layer`. Fehlt es, oder ist die Ebene gelöscht oder unbekannt, gilt die Grund-Ebene `kDefaultLayer` (`ScoreAnnotations.resolveLayer`). So bleiben alte Dateien gültig. Die Grund-Ebene lässt sich nicht löschen.
   Name, Reihenfolge und Sichtbarkeit werden synchronisiert (jüngste Fassung gewinnt, gelöscht bleibt gelöscht). Die aktive Ebene merkt sich nur das Gerät (`InkController.activeLayer`). Zeichnet man auf eine ausgeblendete aktive Ebene, wird sie eingeblendet.
   `visible…On(page)` liefert nur Elemente eingeblendeter Ebenen. Radierer, Lasso und Text-Ebene greifen deshalb nie auf Ausgeblendetes zu. Pro eingeblendeter Ebene gibt es ein eigenes Strich-Bild (`_StrokesImage(layer:)`). Ein-/Ausblenden geht so sofort, und Zeichnen auf einer unteren Ebene bleibt ein schnelles Dazumalen.
   **Leuchtstift immer zuunterst** (Wunsch des Besitzers): Alle Leuchtstift-Striche eingeblendeter Ebenen liegen in einem eigenen Bild unter allen Ebenen-Bildern (`_StrokesImage(highlights: true)`). Jeder Strich bleibt auf seiner Ebene. In diesem Bild wird *nicht* multipliziert, denn manche Grafikkarten zeigen beim Multiplizieren auf leeren Grund nichts, z. B. bei ganz waagrechten Strichen. Stattdessen wird es **einmal** auf das Seitenbild multipliziert (`InkLayer.pageImage` → `_StrokesImage(background:)`). Das Ergebnis ist ein fertiges, deckendes Bild. So bleiben schwarze Noten schwarz, und nichts muss pro Bild gemischt werden. Gemessen: Das Mischen bei jedem Bild hatte den Stift auf vollen Seiten von 57 auf 31 Bilder/s gebremst. Nur solange das Seitenbild fehlt, wird beim Anzeigen gemischt (`_MultiplyImagePainter`). Der entstehende Leuchtstift-Strich wird ebenfalls nicht gemischt.
   Ebenen-Änderungen selbst sind nicht rückgängig machbar. Das Verschieben von Elementen zwischen Ebenen und das Löschen ihres Inhalts aber schon (beim Zurückholen landet der Inhalt einer gelöschten Ebene auf der Grund-Ebene).

12. **Seiten anordnen und zuschneiden (Paket B):** `PageSetup` (Feld `pages` in der Zusatzdatei): `order` (PDF-Seiten in Anzeige-Reihenfolge, Lücken = ausgeblendet, doppelt erlaubt, `null` = natürlich) und `crops` pro PDF-Seite (`PageCrop`: Ausschnitt normiert, `quarterTurns`, `skew` ±5°). Beim Sync gewinnt die jüngste Fassung als Ganzes. Gespeichert über `SidecarStore.save(pages:)`.
   Die Notenansicht zählt in *angezeigten* Seiten (`PageSlot.page`, Seitenzahl, Regler). `_Piece.source(display)` liefert die PDF-Seite. Strich-Ebene, Text-Ebene, Rückgängig, Einfügen und „Seite leeren“ arbeiten immer mit der PDF-Seite (`_activePage`). Anmerkungen bleiben deshalb in Koordinaten der ganzen, ungedrehten Seite.
   `CroppedPage` baut die ganze Seite und zeigt sie geradegerichtet (Drehung um die Seitenmitte), verschoben, abgeschnitten und in Vierteldrehungen gedreht. Flutter rechnet Berührungen durch alle Schritte zurück. Bei einem Ausschnitt wird die ganze Seite entsprechend grösser gerendert, damit sie scharf bleibt.
   „Ränder automatisch“ (`autoCropPage`, `findContentBounds`) rendert die Seite klein und sucht dunkle Punkte, Staub zählt nicht.

## Prüfen
```bash
flutter analyze
flutter test
```

## Stolperfallen
- `future.whenComplete(() => map.remove(key))` wartet auf sich selbst, wenn die Map Futures enthält. Immer einen Block-Körper `{ map.remove(key); }` verwenden.
- Beim Einlesen der Bibliothek werden die PDFs nicht geöffnet, weil Cloud-Ordner sonst alles herunterladen würden. Vorschaubilder entstehen erst, wenn eine Kachel sichtbar wird.

## Offene Tests beim Besitzer
- **iRig BlueTurn** mit Paket 1a/1b testen, auch im Vollbild. Er hatte das Pedal noch nicht dabei, also später nachfragen.

## Offene Ideen (noch nicht umsetzen)
- **Hellmodus auf Weiss:** Der Besitzer findet den sehr sanften Seegrün-Ton im Hellmodus noch etwas komisch und überlegt, auf Weiss umzusteigen. Erst ändern, wenn er es bestätigt. Der Dunkelmodus gefällt ihm so, wie er ist.

## Vereinbarte Richtung für Bearbeitungsfunktionen (angelehnt an forScore, eigenes Design)
- Zuschneiden und Seiten umordnen verändern das PDF nicht. Volti speichert nur, wie die Seiten angezeigt werden, und Anmerkungen bleiben an ihrem Platz.
- Alles wird synchronisiert: Ebenen, Stempel, Vorlagen und Sprungmarken.
- Doppelseiten-Ansicht ist gebaut (vorgezogen aus Paket C): Im Querformat automatisch, umstellbar im ⋮-Menü (`PageLayout`). Sie geht über Songgrenzen (`PageFlow`, `PageSlot`), die Notenansicht hält dafür mehrere Stücke offen (`_Piece`). Regel (ausdrücklicher Wunsch): Die Setlist verhält sich wie **ein einziges PDF**, jedes Umblättern geht genau **eine** Seite weiter (die rechte Seite rutscht nach links). So sind jeder Song und jeder Übergang ganz sichtbar. Rechts bleibt nie eine leere Hälfte. Seiten tragen einen Schlüssel (`page/<stück>/<seite>`), damit sie beim Rutschen ihre Bilder behalten. Rückgängig und „Seite leeren“ wirken auf die zuletzt berührte Seite.
- Die App ist für alle Instrumente gedacht. Stempel deshalb in Gruppen (Streicher, Bläser/Gesang, Tasten, Gitarre …). Der Besitzer spielt Gitarre.
