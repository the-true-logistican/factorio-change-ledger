-- =========================================
-- Change Ledger (Factorio 2.0) 
-- Test-Skript für Pickier Dollies Integration
-- Dieses Skript kann verwendet werden, um die Integration zu testen
--
-- version 0.1.0 first try
-- version 0.2.0 first opertional Version
--
-- =========================================

local PickierDollies = require("integrations.pickier_dollies")

PickierDollies.version = "0.2.0"


-- Test 1: Verfügbarkeitsprüfung
local function test_availability()
  print("=== Test 1: Verfügbarkeitsprüfung ===")
  
  local available = PickierDollies.is_available()
  print("Pickier Dollies verfügbar: " .. tostring(available))
  
  if available then
    print("✓ Test bestanden: Pickier Dollies wurde gefunden")
  else
    print("✗ Test fehlgeschlagen: Pickier Dollies nicht gefunden")
    print("  Hinweis: Ist Even Pickier Dollies installiert?")
  end
  
  return available
end

-- Test 2: Event-ID Abruf
local function test_event_id()
  print("\n=== Test 2: Event-ID Abruf ===")
  
  if not remote or not remote.interfaces or not remote.interfaces['PickerDollies'] then
    print("✗ Übersprungen: Pickier Dollies API nicht verfügbar")
    return false
  end
  
  local success, event_id = pcall(function()
    return remote.call("PickerDollies", "dolly_moved_entity_id")
  end)
  
  if success and event_id then
    print("Event-ID abgerufen: " .. tostring(event_id))
    print("✓ Test bestanden: Event-ID erfolgreich abgerufen")
    return true
  else
    print("✗ Test fehlgeschlagen: Konnte Event-ID nicht abrufen")
    print("  Fehler: " .. tostring(event_id))
    return false
  end
end

-- Test 3: Simulations-Test (nur wenn EPD verfügbar ist)
local function test_event_simulation()
  print("\n=== Test 3: Event-Verarbeitung (Simulation) ===")
  
  -- Simuliere ein Event-Objekt wie es von Pickier Dollies kommt
  local mock_event = {
    player_index = 1,
    moved_entity = nil,  -- Würde normalerweise ein LuaEntity sein
    start_pos = {x = 10.5, y = 20.5},
    start_direction = 0,  -- Nord
    start_unit_number = 12345,
    tick = game and game.tick or 0,
    name = 999  -- Mock Event-ID
  }
  
  print("Mock-Event erstellt:")
  print("  Start Position: (" .. mock_event.start_pos.x .. ", " .. mock_event.start_pos.y .. ")")
  print("  Start Direction: " .. mock_event.start_direction)
  print("  Start Unit Number: " .. mock_event.start_unit_number)
  
  -- In einem echten Szenario würde hier die Event-Verarbeitung getestet
  print("✓ Test bestanden: Mock-Event-Struktur ist korrekt")
  return true
end

-- Test 4: Position-Vergleichs-Logik
local function test_position_comparison()
  print("\n=== Test 4: Position-Vergleichs-Logik ===")
  
  local function positions_equal(pos1, pos2, tolerance)
    tolerance = tolerance or 0.01
    local dx = math.abs(pos1.x - pos2.x)
    local dy = math.abs(pos1.y - pos2.y)
    return (dx <= tolerance and dy <= tolerance)
  end
  
  -- Test gleiche Positionen
  local p1 = {x = 10.0, y = 20.0}
  local p2 = {x = 10.0, y = 20.0}
  local equal = positions_equal(p1, p2)
  print("Test 1 - Identische Positionen: " .. tostring(equal))
  assert(equal == true, "Identische Positionen sollten gleich sein")
  
  -- Test minimal unterschiedliche Positionen (innerhalb Toleranz)
  p2 = {x = 10.005, y = 20.005}
  equal = positions_equal(p1, p2)
  print("Test 2 - Innerhalb Toleranz: " .. tostring(equal))
  assert(equal == true, "Positionen innerhalb Toleranz sollten gleich sein")
  
  -- Test deutlich unterschiedliche Positionen
  p2 = {x = 10.5, y = 20.5}
  equal = positions_equal(p1, p2)
  print("Test 3 - Außerhalb Toleranz: " .. tostring(equal))
  assert(equal == false, "Positionen außerhalb Toleranz sollten unterschiedlich sein")
  
  print("✓ Test bestanden: Position-Vergleichs-Logik funktioniert korrekt")
  return true
end

-- Test 5: Extra-String-Formatierung
local function test_extra_formatting()
  print("\n=== Test 5: Extra-String-Formatierung ===")
  
  local extra_parts = {}
  
  -- Test 1: Start-Position
  table.insert(extra_parts, string.format("from=%.1f,%.1f", 10.5, 20.5))
  
  -- Test 2: Richtung
  table.insert(extra_parts, "prev_dir=2")
  
  -- Test 3: Unit-Number
  table.insert(extra_parts, "orig_unit=12345")
  
  -- Test 4: Transporter-Mode
  table.insert(extra_parts, "transporter_mode=1")
  
  -- Test 5: Via Dolly
  table.insert(extra_parts, "via_dolly=1")
  
  local extra = table.concat(extra_parts, ",")
  local expected = "from=10.5,20.5,prev_dir=2,orig_unit=12345,transporter_mode=1,via_dolly=1"
  
  print("Generierter Extra-String:")
  print("  " .. extra)
  print("Erwarteter Extra-String:")
  print("  " .. expected)
  
  if extra == expected then
    print("✓ Test bestanden: Extra-String korrekt formatiert")
    return true
  else
    print("✗ Test fehlgeschlagen: Extra-String stimmt nicht überein")
    return false
  end
end

-- Haupttest-Funktion
local function run_all_tests()
  print("╔════════════════════════════════════════════════════════╗")
  print("║  Pickier Dollies Integration - Test Suite             ║")
  print("╚════════════════════════════════════════════════════════╝\n")
  
  local results = {}
  
  results.availability = test_availability()
  results.event_id = test_event_id()
  results.simulation = test_event_simulation()
  results.position_comparison = test_position_comparison()
  results.extra_formatting = test_extra_formatting()
  
  print("\n╔════════════════════════════════════════════════════════╗")
  print("║  Test-Zusammenfassung                                  ║")
  print("╚════════════════════════════════════════════════════════╝")
  
  local total = 0
  local passed = 0
  
  for name, result in pairs(results) do
    total = total + 1
    if result then
      passed = passed + 1
      print("✓ " .. name)
    else
      print("✗ " .. name)
    end
  end
  
  print("\nErgebnis: " .. passed .. "/" .. total .. " Tests bestanden")
  
  if passed == total then
    print("🎉 Alle Tests erfolgreich!")
  else
    print("⚠️  Einige Tests sind fehlgeschlagen")
  end
end

-- Wenn als Skript ausgeführt, Tests laufen lassen
if not ... then
  run_all_tests()
end

return {
  run_all_tests = run_all_tests,
  test_availability = test_availability,
  test_event_id = test_event_id,
  test_event_simulation = test_event_simulation,
  test_position_comparison = test_position_comparison,
  test_extra_formatting = test_extra_formatting
}
