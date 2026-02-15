-- =========================================
-- Change Ledger (Factorio 2.0) 
-- Optional Circuit Change Tracking
-- Tracks pure circuit wire changes (without entity movement)
-- This is disabled by default due to performance considerations
--
-- version 0.1.0 first try
-- version 0.2.0 first opertional Version
--
-- =========================================

local M = require("config")
local Change = require("change")
local CircuitHelper = require("integrations.circuit_helper")

local CircuitTracking = {}

CircuitTracking.version = "0.2.0"

-- Enable/disable circuit change tracking
-- Set this to true to enable tracking of pure wire changes
local TRACK_CIRCUIT_CHANGES = false

function CircuitTracking.is_enabled()
  return TRACK_CIRCUIT_CHANGES
end

function CircuitTracking.is_available()
  -- Always available, but may be disabled
  return true
end

-- Returns a list of all actions/manipulations this integration tracks
function CircuitTracking.get_tracked_actions()
  if not TRACK_CIRCUIT_CHANGES then
    return {
      "(DEAKTIVIERT) WIRE_CHANGE - Reine Kabeländerungen ohne Entity-Bewegung"
    }
  end
  
  return {
    "WIRE_CHANGE - Kabelverbindungen werden geändert (via GUI)",
    "Erfasst: Hinzufügen/Entfernen von roten/grünen Kabeln",
    "Nur bei GUI-Interaktion (nicht bei Robotern)"
  }
end

function CircuitTracking.register(reg)
  if not TRACK_CIRCUIT_CHANGES then
    log("[Change Ledger] Circuit Change Tracking ist DEAKTIVIERT (Performance-Modus)")
    return
  end
  
  log("[Change Ledger] Circuit Change Tracking wird aktiviert")
  
  local function should_record()
    M.ensure_storage_defaults()
    return storage.cl.recording == true
  end
  
  -- Initialize circuit snapshots storage
  local function ensure_circuit_storage()
    M.ensure_storage_defaults()
    storage.cl.circuit_snapshots = storage.cl.circuit_snapshots or {}
  end
  
  -- When GUI is opened, take a snapshot of circuit connections
  reg:add(defines.events.on_gui_opened, function(e)
    if not should_record() then return end
    
    local ent = e.entity
    if not (ent and ent.valid) then return end
    
    -- Only track entities that support circuit connections
    if not ent.circuit_connection_definitions then return end
    
    ensure_circuit_storage()
    
    local player_index = e.player_index
    local signature = CircuitHelper.get_wire_signature(ent)
    
    storage.cl.circuit_snapshots[player_index] = {
      unit_number = ent.unit_number,
      signature = signature,
      tick = e.tick
    }
    
    log("[Change Ledger] Circuit Snapshot genommen: entity=" .. ent.name .. 
        ", unit=" .. tostring(ent.unit_number) .. 
        ", sig=" .. signature)
  end)
  
  -- When GUI is closed, compare and log changes
  reg:add(defines.events.on_gui_closed, function(e)
    if not should_record() then return end
    
    ensure_circuit_storage()
    
    local player_index = e.player_index
    local snapshot = storage.cl.circuit_snapshots[player_index]
    
    if not snapshot then return end
    
    local ent = e.entity
    if not (ent and ent.valid) then 
      storage.cl.circuit_snapshots[player_index] = nil
      return 
    end
    
    -- Only if it's the same entity
    if ent.unit_number ~= snapshot.unit_number then
      storage.cl.circuit_snapshots[player_index] = nil
      return
    end
    
    local new_signature = CircuitHelper.get_wire_signature(ent)
    
    if new_signature ~= snapshot.signature then
      log("[Change Ledger] Circuit Änderung erkannt!")
      log("[Change Ledger]   Vorher: " .. snapshot.signature)
      log("[Change Ledger]   Nachher: " .. new_signature)
      
      -- Count changes
      local old_red, old_green = CircuitHelper.count_wires_from_signature(snapshot.signature)
      local new_red, new_green = CircuitHelper.count_wires(ent)
      
      local extra = string.format("wire_change=1,before_R%d_G%d,after_R%d_G%d",
        old_red, old_green, new_red, new_green)
      
      Change.push_event(Change.make_entity_event("WIRE_CHANGE", e, ent, extra))
      
      log("[Change Ledger] WIRE_CHANGE Event geloggt")
    end
    
    storage.cl.circuit_snapshots[player_index] = nil
  end)
  
  log("[Change Ledger] Circuit Change Tracking erfolgreich aktiviert")
end

-- Helper: Count wires from a signature string (for comparison)
function CircuitHelper.count_wires_from_signature(sig)
  if not sig or sig == "" then return 0, 0 end
  
  local red = 0
  local green = 0
  
  for part in string.gmatch(sig, "[^,]+") do
    if string.sub(part, 1, 1) == "R" then
      red = red + 1
    elseif string.sub(part, 1, 1) == "G" then
      green = green + 1
    end
  end
  
  return red, green
end

return CircuitTracking
