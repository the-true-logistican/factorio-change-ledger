# Pickier Dollies Integration für Change-Ledger

## Übersicht

Diese Integration ermöglicht es Change-Ledger, Entitätsbewegungen und -rotationen zu erfassen, die mit dem Mod "Even Pickier Dollies" durchgeführt werden.

## Funktionsweise

### Event-Registrierung

Die Integration nutzt das Custom Event System von Even Pickier Dollies:

1. Beim Laden prüft die Integration, ob Pickier Dollies verfügbar ist (`remote.interfaces['PickerDollies']`)
2. Falls verfügbar, wird die Event-ID über `remote.call("PickerDollies", "dolly_moved_entity_id")` abgerufen
3. Ein Event-Handler wird für diese ID registriert

### Event-Daten

Pickier Dollies sendet bei jeder Bewegung/Rotation ein Event mit folgenden Daten:

- `player_index`: Spieler-Index
- `moved_entity`: Die bewegte/rotierte Entität (LuaEntity)
- `start_pos`: Startposition vor der Bewegung
- `start_direction`: Startrichtung vor der Rotation
- `start_unit_number`: Ursprüngliche Unit-Number (wichtig für Transporter-Modus)
- `tick`: Game Tick des Events
- `name`: Event-ID

### Erkannte Aktionen

Die Integration unterscheidet zwischen:

1. **MOVE** - Positionsänderung der Entität
   - Wird geloggt, wenn Position um mehr als 0.01 Tiles geändert wurde
   - Beispiel: `MOVE;entity=assembling-machine-1;from=10.5,20.5;via_dolly=1`

2. **ROTATE** - Richtungsänderung ohne Positionsänderung
   - Wird geloggt, wenn nur die Richtung geändert wurde
   - Beispiel: `ROTATE;entity=assembling-machine-1;prev_dir=2;via_dolly=1`

### Extra-Informationen

Jedes Event enthält zusätzliche Informationen im `extra`-Feld:

- `from=X,Y` - Ursprungsposition
- `prev_dir=N` - Ursprungsrichtung (falls geändert)
- `orig_unit=N` - Ursprüngliche Unit-Number (falls Entität im Transporter-Modus ersetzt wurde)
- `transporter_mode=1` - Kennzeichnung, dass die Entität neu erstellt wurde
- `via_dolly=1` - Kennzeichnung, dass die Änderung über Pickier Dollies erfolgte

### Transporter-Modus

Ab Version 2.5.0 kann Pickier Dollies Entitäten bewegen, die nicht teleportiert werden können, indem eine identische Kopie erstellt und das Original zerstört wird. Die Integration erkennt dies und loggt die ursprüngliche `unit_number`.

## Installation

Die Integration ist standardmäßig im Change-Ledger-Mod enthalten. Sie aktiviert sich automatisch, wenn Even Pickier Dollies installiert ist.

## Kompatibilität

- Kompatibel mit Even Pickier Dollies ab Version 2.5.0
- Nutzt die offizielle Pickier Dollies API
- Keine Dependencies in info.json erforderlich (optionale Integration)

## Beispiel-Log-Einträge

```
123;tick=54321;sess=1;act=MOVE;actor=PLAYER:player1;entity=assembling-machine-1;unit=4567;pos=15.5,22.5;extra=from=10.5,20.5,via_dolly=1
124;tick=54325;sess=1;act=ROTATE;actor=PLAYER:player1;entity=inserter;unit=4568;pos=12.0,18.0;extra=prev_dir=2,via_dolly=1
125;tick=54330;sess=1;act=MOVE;actor=PLAYER:player1;entity=steam-engine;unit=8901;pos=30.0,40.0;extra=from=25.0,35.0,orig_unit=8900,transporter_mode=1,via_dolly=1
```

## Technische Details

### Architektur

Die Integration folgt dem gleichen Muster wie `vanilla.lua`:

1. `is_available()` - Prüft Verfügbarkeit
2. `register(reg)` - Registriert Event-Handler über Registry-Objekt
3. Event-Handler nutzen `Change.make_entity_event()` zum Erstellen von Log-Einträgen

### Event-Registry-System

Das `event_registry.lua`-Modul ermöglicht es, mehrere Handler für dasselbe Event zu registrieren. Dies ist wichtig, da mehrere Integrationen möglicherweise auf dieselben Events reagieren müssen.

### Floating-Point-Toleranz

Beim Vergleich von Positionen wird eine Toleranz von 0.01 Tiles verwendet, um Floating-Point-Ungenauigkeiten zu berücksichtigen.

## Erweiterungsmöglichkeiten

Zukünftige Verbesserungen könnten umfassen:

- Erfassung von Blueprint-basierten Bewegungen
- Tracking von Bewegungsdistanzen
- Statistiken über häufig bewegte Entitäten
- Integration mit anderen Movement-Mods

## Fehlerbehandlung

Die Integration ist robust gegen:

- Fehlende oder ungültige Entitäten
- Unvollständige Event-Daten
- Pickier Dollies wird während des Spiels entfernt

Alle Prüfungen erfolgen defensiv mit Fallback-Werten.
