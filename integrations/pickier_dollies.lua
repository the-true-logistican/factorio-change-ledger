-- =========================================
-- Change Ledger (Factorio 2.0) 
-- Integration for Even Pickier Dollies mod
-- Logs entity movements and rotations performed via the Pickier Dollies mod
--
-- version 0.1.0 first try
-- version 0.2.0 first opertional Version
--
-- =========================================

local M = require("config")
local Change = require("change")
local CircuitHelper = require("integrations.circuit_helper")

local PickierDollies = {}

PickierDollies.version = "0.2.0"

-- Check if Even Pickier Dollies (EPD) is available
function PickierDollies.is_available()
  -- EPD registers its API under the name "PickerDollies" (for compatibility)
  local available = remote and remote.interfaces and remote.interfaces['PickerDollies'] ~= nil
  
  -- Debug output
  if available then
    log("[Change Ledger] Pickier Dollies API gefunden - Integration wird aktiviert")
  else
    log("[Change Ledger] Pickier Dollies API nicht gefunden - Integration übersprungen")
  end
  
  return available
end

-- Returns a list of all actions/manipulations this integration tracks
function PickierDollies.get_tracked_actions()
  return {
    "MOVE - Entität wird verschoben (via Pickier Dollies Alt+Pfeiltaste)",
    "ROTATE - Entität wird rotiert (via Pickier Dollies, bei oblongs)",
    "CIRCUIT_WIRES - Kabelverbindungen werden mit verschoben",
    "TRANSPORTER_MODE - Entität wird neu erstellt wenn nötig"
  }
end

-- Register event handlers for Pickier Dollies
function PickierDollies.register(reg)
  log("[Change Ledger] Pickier Dollies Integration: register() wird aufgerufen")
  -- Helper to check if recording is enabled
  local function should_record()
    M.ensure_storage_defaults()
    return storage.cl.recording == true
  end

  -- Helper to log a change event
  local function log_change(action, e, ent, extra)
    if not should_record() then return end
    Change.push_event(Change.make_entity_event(action, e, ent, extra))
  end

  -- Get the custom event ID from Pickier Dollies API
  log("[Change Ledger] Versuche Event-ID von Pickier Dollies abzurufen...")
  
  local success, epd_event_id = pcall(function()
    return remote.call("PickerDollies", "dolly_moved_entity_id")
  end)
  
  if not success then
    log("[Change Ledger] FEHLER beim Abrufen der Event-ID: " .. tostring(epd_event_id))
    return
  end
  
  log("[Change Ledger] Event-ID erfolgreich abgerufen: " .. tostring(epd_event_id))
  
  -- Register handler for the Pickier Dollies move/rotate event
  -- Event data structure (from EPD API.md):
  --   player_index: uint - Player index
  --   moved_entity: LuaEntity - The entity that was moved
  --   start_pos: MapPosition - The start position from which the entity was moved
  --   start_direction: defines.direction - The start direction of the entity
  --   start_unit_number: integer? - The original unit number of the entity
  --   tick: number - The game tick of this event
  --   name: defines.event - The event id
  log("[Change Ledger] Registriere Event-Handler für Event-ID " .. tostring(epd_event_id))
  
  reg:add(epd_event_id, function(e)
    log("[Change Ledger] *** PICKIER DOLLIES EVENT EMPFANGEN ***")
    log("[Change Ledger] Event-Daten: player_index=" .. tostring(e.player_index) .. 
        ", tick=" .. tostring(e.tick) .. 
        ", entity=" .. tostring(e.moved_entity and e.moved_entity.name or "nil"))
    
    -- In-Game Nachricht beim ersten Event (nur für den Spieler)
    local player = game.get_player(e.player_index)
    if player and not storage.cl.epd_first_event_shown then
      player.print("[Change Ledger] Pickier Dollies Event empfangen - Integration aktiv!", {r=0.3, g=1, b=0.3})
      storage.cl.epd_first_event_shown = true
    end
    
    if not should_record() then 
      log("[Change Ledger] Recording ist AUSGESCHALTET - Event wird ignoriert")
      if player then
        player.print("[Change Ledger] Pickier Dollies Event ignoriert - Recording ist AUS", {r=1, g=0.5, b=0})
      end
      return 
    end
    
    log("[Change Ledger] Recording ist EINGESCHALTET - Event wird verarbeitet")
    
    local ent = e.moved_entity
    if not (ent and ent.valid) then 
      log("[Change Ledger] FEHLER: Entity ist ungültig oder nil")
      return 
    end
    
    log("[Change Ledger] Entity ist valide: " .. tostring(ent.name) .. " (unit=" .. tostring(ent.unit_number) .. ")")
    
    local start_pos = e.start_pos
    local start_direction = e.start_direction
    local current_pos = ent.position
    local current_direction = ent.direction
    
    -- Determine if this was a move, rotate, or both
    local position_changed = false
    local direction_changed = false
    
    -- Check if position changed (with small tolerance for floating point)
    if start_pos and current_pos then
      local dx = math.abs((start_pos.x or start_pos[1]) - current_pos.x)
      local dy = math.abs((start_pos.y or start_pos[2]) - current_pos.y)
      position_changed = (dx > 0.01 or dy > 0.01)
      log("[Change Ledger] Position-Änderung: dx=" .. string.format("%.3f", dx) .. 
          ", dy=" .. string.format("%.3f", dy) .. 
          " -> " .. (position_changed and "GEÄNDERT" or "GLEICH"))
    end
    
    -- Check if direction changed
    if start_direction and current_direction then
      direction_changed = (start_direction ~= current_direction)
      log("[Change Ledger] Richtungs-Änderung: " .. tostring(start_direction) .. 
          " -> " .. tostring(current_direction) .. 
          " -> " .. (direction_changed and "GEÄNDERT" or "GLEICH"))
    end
    
    -- Format extra information
    local extra_parts = {}
    
    -- Add start position
    if start_pos then
      local sx = start_pos.x or start_pos[1] or 0
      local sy = start_pos.y or start_pos[2] or 0
      table.insert(extra_parts, string.format("from=%.1f,%.1f", sx, sy))
    end
    
    -- Add start direction if it changed
    if direction_changed and start_direction then
      table.insert(extra_parts, "prev_dir=" .. tostring(start_direction))
    end
    
    -- Add unit number info if entity was replaced (transporter mode)
    if e.start_unit_number and ent.unit_number ~= e.start_unit_number then
      table.insert(extra_parts, "orig_unit=" .. tostring(e.start_unit_number))
      table.insert(extra_parts, "transporter_mode=1")
    end
    
    table.insert(extra_parts, "via_dolly=1")
    
    local extra = table.concat(extra_parts, ",")
    
    -- Add circuit wire information
    extra = CircuitHelper.append_wire_info(extra, ent)
    
    -- Log the appropriate event(s)
    -- We prioritize MOVE over ROTATE if both happened, since position change is more significant
    if position_changed then
      log("[Change Ledger] Logge MOVE Event: " .. extra)
      log_change("MOVE", e, ent, extra)
      log("[Change Ledger] MOVE Event erfolgreich geloggt")
    elseif direction_changed then
      log("[Change Ledger] Logge ROTATE Event: " .. extra)
      log_change("ROTATE", e, ent, extra)
      log("[Change Ledger] ROTATE Event erfolgreich geloggt")
    else
      -- Fallback: log as MOVE if we can't determine what happened
      -- This shouldn't normally occur, but it's a safety net
      log("[Change Ledger] FALLBACK: Logge MOVE Event (keine Änderung erkannt): " .. extra)
      log_change("MOVE", e, ent, extra)
      log("[Change Ledger] FALLBACK MOVE Event erfolgreich geloggt")
    end
  end)
  
  log("[Change Ledger] Pickier Dollies Integration erfolgreich registriert!")
end

return PickierDollies
