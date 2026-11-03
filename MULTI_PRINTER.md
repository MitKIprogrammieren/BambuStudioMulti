# Bambu Lab Studio Multi – Drucker pro Platte

Dieser Fork von Bambu Studio ergänzt eine Druckerzuteilung pro Platte. Jede Platte im Projekt kann einen eigenen Drucker bekommen. Danach slicet ein einziger Knopf alle Platten mit dem Profil ihres Druckers und schickt jede Platte an den zugeteilten Drucker.

## Bedienung

1. **Drucker zuteilen:** Klick im Tab „Vorbereiten“ auf das Zahnrad über einer Platte. Ganz oben im Dialog steht jetzt **Drucker**. Dort wählst du einen deiner Drucker (gebunden oder im LAN) oder „Kein Drucker zugeteilt“.
2. Der zugeteilte Drucker steht danach direkt über der Platte neben dem Plattennamen, mit der Größe seines Druckbetts (z. B. `→ P2S Büro · 256×256`).
   Ist das Druckbett kleiner als das des Projekt-Druckers, wird der Rest der Platte grau als Sperrbereich dargestellt. Objekte, die hineinragen, gelten sofort als „außerhalb“.
   Tipp: Wähle als Drucker des Projekts den mit dem größten Druckbett. Dann haben alle Platten genug Platz.
3. **Senden:** Öffne oben rechts das Menü am Druckknopf und wähle **An zugewiesene Drucker senden**. Klick dann auf den Knopf.

Ablauf pro Platte:

- Hat die Platte ein anderes Druckermodell als das aktuell gewählte Profil, schaltet Bambu Studio auf das passende Druckerprofil um. Die Objekte bleiben dabei auf ihren Platten liegen und werden nicht neu verteilt.
- Die Platte wird gesliced.
- Der normale Druckdialog öffnet sich, mit dem zugeteilten Drucker vorausgewählt. AMS-Zuordnung, Kalibrierung und Zeitraffer funktionieren wie gewohnt. Mit **Senden** geht die Platte an den Drucker, danach folgt automatisch die nächste.
- Zum Schluss zeigt eine Übersicht, welche Platten gesendet wurden und welche nicht (z. B. Drucker offline).

Unten rechts im 3D-Fenster zeigt ein Hinweis den Fortschritt pro Platte („wartet“, „wird gesliced“, „wartet auf ‚Senden‘“, „gesendet“) und hat einen Knopf zum Abbrechen. Nach dem Ablauf wechselt das Projekt zurück auf das Druckerprofil, das vorher gewählt war.

Platten werden nach Druckerprofil gruppiert. So wird das Profil so selten wie möglich gewechselt, und die Platten des aktuell gewählten Druckers kommen zuerst dran.

## App auf dem Mac bauen

Voraussetzungen: Xcode-Kommandozeilenwerkzeuge, [Homebrew](https://brew.sh) und etwa 25 GB freier Speicher.

```bash
git clone https://github.com/MitKIprogrammieren/BambuStudioMulti.git
cd BambuStudioMulti
./scripts/mac-installieren.sh
```

- Der **erste Lauf** baut alle Abhängigkeiten und dauert etwa 1–2 Stunden. Jeder weitere Lauf holt den neuesten Stand und baut nur die App neu, das dauert etwa 10–30 Minuten.
- Die fertige App liegt in **~/Applications/Bambu Lab Studio Multi.app**. Das offizielle Bambu Studio bleibt unverändert daneben.
- CMake 3.31 und Ninja installiert das Skript in den Ordner `.build-werkzeuge` im Repo. Deine Homebrew-Installation wird nicht umgestellt.
- Jeder Lauf schreibt ein Protokoll `build-DATUM.log` in den Repo-Ordner.

**Einfacher:** Doppelklick im Finder auf **„Bambu Lab Studio Multi aktualisieren.command“** im Repo-Ordner. Das öffnet das Terminal, holt den neuesten Stand, baut die App und startet sie danach.

Optionen: `--ohne-update` (kein git pull), `--sauber` (App-Build neu von vorn), `--abhaengigkeiten-neu` (Abhängigkeiten komplett neu bauen).

Bambu Lab Studio Multi nutzt dieselben Einstellungen, Druckerprofile und dieselbe Anmeldung wie das offizielle Bambu Studio. Öffne nicht beide Apps gleichzeitig.

## Gespeichert in der 3MF

Die Zuteilung wird pro Platte in `Metadata/model_settings.config` gespeichert:

```xml
<metadata key="assigned_dev_id" value="..."/>
<metadata key="assigned_dev_name" value="P2S Büro"/>
<metadata key="assigned_printer_preset" value="Bambu Lab P2S 0.4 nozzle"/>
```

Das offizielle Bambu Studio ignoriert diese Schlüssel, die Dateien bleiben also kompatibel.

## Hinweise

- Mischst du verschiedene Druckermodelle in einem Projekt, zeigt die Druckplatte im 3D-Fenster immer die Größe des aktuell gewählten Profils. Was nicht auf das kleinere Druckbett passt, meldet Bambu Studio beim Slicen als „außerhalb“.
- Die Prozess- und Filamentprofile folgen beim Profilwechsel den üblichen Regeln von Bambu Studio (passende Variante zum Drucker).

## Geänderte Dateien

| Datei | Änderung |
| --- | --- |
| `src/slic3r/GUI/PartPlate.*` | Zuteilung pro Platte, Anzeige neben dem Plattennamen, Undo/Redo |
| `src/libslic3r/Format/bbs_3mf.*` | Speichern und Laden in der 3MF |
| `src/slic3r/GUI/PlateSettingsDialog.*` | Auswahlfeld „Drucker“ |
| `src/slic3r/GUI/Plater.*` | Druckerprofil zum Gerät, Ablauf Slicen und Senden, Objekte bleiben beim Profilwechsel auf ihren Platten |
| `src/slic3r/GUI/MainFrame.*` | Menüpunkt „An zugewiesene Drucker senden“ |
| `src/slic3r/GUI/SelectMachine.hpp` | Vorauswahl des Druckers im Druckdialog |
| `bbl/i18n/de/BambuStudio_de.po` | Deutsche Texte |
