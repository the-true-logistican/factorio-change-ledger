# Change Ledger - Factorio Mod

Ein Factorio 2.0 Mod zur Erfassung und Protokollierung aller Änderungen in der Spielwelt während einer Factory-Umstellung.

## Übersicht

Change Ledger zeichnet automatisch alle relevanten Aktivitäten auf, die Veränderungen in deiner Factory darstellen:

- **Bauaktivitäten**: Platzierung und Abbau von Gebäuden
- **Rotationen & Spiegelungen**: Richtungsänderungen von Entitäten
- **Modulverwaltung**: Einfügen und Entfernen von Modulen
- **Materialfluss**: Entnahme von Materialien aus Containern
- **Markierungen**: Planung von Abbau und Upgrades
- **Bewegungen**: Integration mit Pickier Dollies für Entitätsbewegungen

## Features

### Kernfunktionalität

- **Session-basierte Aufzeichnung**: Start/Stop-Funktion für gezielte Aufzeichnung
- **Event-Kategorisierung**: Nach Akteur (Spieler, Roboter, Script) filterbar
- **Detaillierte Logs**: Position, Richtung, Unit-Number, Extra-Informationen
- **Ringbuffer**: Effiziente Speicherung mit konfigurierbarer Größe
- **Viewer-UI**: Integrierte Anzeige mit Paging-Funktionen

### Integrationen

#### Vanilla Factorio
Standardmäßig werden alle wichtigen Vanilla-Events erfasst:
- `on_built_entity`, `on_robot_built_entity`, `script_raised_built`
- `on_player_mined_entity`, `on_robot_mined_entity`, `on_entity_died`
- `on_player_rotated_entity`, `on_player_flipped_entity`
- `on_marked_for_deconstruction`, `on_marked_for_upgrade`
- Modul-Änderungen via GUI-Events

#### Pickier Dollies (Optional)
Wenn "Even Pickier Dollies" installiert ist:
- Erfassung von Entitätsbewegungen
- Rotationen durch Pickier Dollies
- Transporter-Modus-Unterstützung
- Siehe [integrations/PICKIER_DOLLIES_README.md](integrations/PICKIER_DOLLIES_README.md) für Details

## Installation

1. Entpacke den Mod-Ordner in dein Factorio mods-Verzeichnis
2. Starte Factorio und aktiviere den Mod
3. (Optional) Installiere "Even Pickier Dollies" für erweiterte Tracking-Funktionen

## Verwendung

### Grundlegende Bedienung

1. **Aufnahme starten**: Klicke auf den Record-Button in der Topbar
2. **Änderungen durchführen**: Baue, verschiebe, rotiere Gebäude
3. **Markierungen setzen**: Klicke auf den Mark-Button für Meilensteine
4. **Log ansehen**: Klicke auf den Log-Button zum Öffnen des Viewers
5. **Aufnahme stoppen**: Erneuter Klick auf den Record-Button

### Log-Viewer

Der Log-Viewer bietet:
- **Filter**: Player, Robot, Ghost, Other Events ein-/ausblenden
- **Navigation**: Home, End, Older, Newer Buttons
- **Export**: Kopier-Funktion für externe Analyse

### Log-Format

Jeder Log-Eintrag folgt diesem Format:
```
ID;tick=T;sess=S;act=ACTION;actor=TYPE:NAME;entity=NAME;unit=U;pos=X,Y;extra=INFO
```

Beispiel:
```
42;tick=12345;sess=1;act=BUILD;actor=PLAYER:player1;entity=assembling-machine-1;unit=567;pos=10.5,20.5;extra=
```

## Konfiguration

### Storage-Parameter (in config.lua)

- `CHG_MAX_EVENTS`: Maximale Anzahl gespeicherter Events (Standard: 50000)
- `GUI_MAX_LINES`: Zeilen pro Viewer-Seite (Standard: 50)

### Filter-Optionen

Im Viewer können folgende Event-Typen gefiltert werden:
- **Player**: Von Spielern ausgeführte Aktionen
- **Robot**: Von Robotern ausgeführte Aktionen
- **Ghost**: Ghost-bezogene Events
- **Other**: Script-Events und sonstige

## Architektur

### Modulare Struktur

```
change_ledger/
├── control.lua              # Hauptsteuerung & Event-Bindung
├── config.lua               # Konfiguration & Konstanten
├── event_registry.lua       # Event-Registry-System
├── change.lua               # Event-Verwaltung & Ringbuffer
├── ui.lua                   # GUI-Komponenten
├── integrations/
│   ├── vanilla.lua          # Vanilla Factorio Events
│   ├── pickier_dollies.lua  # Pickier Dollies Integration
│   └── ...                  # Zukünftige Integrationen
└── locale/
    ├── de/                  # Deutsche Übersetzungen
    └── en/                  # Englische Übersetzungen
```

### Event-Registry-Pattern

Das Event-Registry-System erlaubt modulare Integrationen:

1. Integration prüft Verfügbarkeit (`is_available()`)
2. Integration registriert Handler (`register(registry)`)
3. Registry bindet alle Handler zentral

Vorteile:
- Mehrere Handler pro Event möglich
- Saubere Trennung von Integrationen
- Einfaches Hinzufügen neuer Mods

## Entwicklung

### Neue Integration hinzufügen

1. Erstelle neue Datei in `integrations/your_mod.lua`
2. Implementiere `is_available()` und `register(reg)` Funktionen
3. Importiere und registriere in `control.lua`:
   ```lua
   local YourMod = require("integrations.your_mod")
   if YourMod and YourMod.is_available() then
     YourMod.register(reg)
   end
   ```

### Event-Typen

Nutze diese Aktionen in `Change.make_entity_event()`:
- `BUILD`, `REMOVE` - Bauaktivitäten
- `ROTATE`, `FLIP` - Richtungsänderungen
- `MOVE` - Positionsänderungen
- `MODULE_IN`, `MODULE_OUT` - Moduländerungen
- `MAT_TAKE` - Materialentnahme
- `MARK_DECON`, `MARK_UPGRADE` - Markierungen

### Testing

Nutze die Test-Suite:
```lua
local test = require("integrations.pickier_dollies_test")
test.run_all_tests()
```

## Kompatibilität

- **Factorio Version**: 2.0+
- **Abhängigkeiten**: 
  - base >= 2.0.0
  - (optional) even-pickier-dollies >= 2.5.0

## Bekannte Einschränkungen

- Ringbuffer-Größe ist fest konfiguriert
- Keine persistente Speicherung über Spielsitzungen
- Log-Export erfolgt manuell per Copy

