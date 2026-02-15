-- =========================================
-- Change Ledger (Factorio 2.0) 
-- Circuit Network Helper
-- Provides utilities for tracking circuit wire connections
--
-- version 0.1.0 first try
-- version 0.2.0 first opertional Version
--
-- =========================================

local CircuitHelper = {}

CircuitHelper.version = "0.2.0"

-- Count red and green wire connections for an entity
function CircuitHelper.count_wires(entity)
  if not (entity and entity.valid) then return 0, 0 end
  
  -- Not all entities support circuit connections - use pcall to safely check
  local has_circuit, connections = pcall(function() 
    return entity.circuit_connection_definitions 
  end)
  
  -- If pcall failed or result is nil/empty, no circuit support
  if not (has_circuit and connections and type(connections) == "table") then 
    return 0, 0 
  end
  
  local red_count = 0
  local green_count = 0
  
  for _, conn in ipairs(connections) do
    if conn.wire == defines.wire_type.red then
      red_count = red_count + 1
    elseif conn.wire == defines.wire_type.green then
      green_count = green_count + 1
    end
  end
  
  return red_count, green_count
end

-- Get a wire summary string for logging
-- Returns: "R2,G1" or "R0,G0" or "" if no circuit support
function CircuitHelper.get_wire_summary(entity)
  local red, green = CircuitHelper.count_wires(entity)
  
  if red == 0 and green == 0 then
    return ""  -- No wires, don't clutter the log
  end
  
  return string.format("R%d,G%d", red, green)
end

-- Get detailed wire signature for comparison
-- Format: "R:unit1[1->1],G:unit2[1->1],..."
function CircuitHelper.get_wire_signature(entity)
  if not (entity and entity.valid) then return "" end
  
  -- Safely try to get circuit connections
  local has_circuit, connections = pcall(function() 
    return entity.circuit_connection_definitions 
  end)
  
  if not (has_circuit and connections and type(connections) == "table") then 
    return "" 
  end
  
  local parts = {}
  for _, conn in ipairs(connections) do
    local color = (conn.wire == defines.wire_type.red) and "R" or "G"
    local target = conn.target_entity
    local target_id = target and target.unit_number or "?"
    
    table.insert(parts, string.format("%s:%s[%d->%d]", 
      color, 
      tostring(target_id),
      conn.source_circuit_id or 0,
      conn.target_circuit_id or 0
    ))
  end
  
  table.sort(parts)  -- Consistent ordering for comparison
  return table.concat(parts, ",")
end

-- Append wire info to an existing extra string
function CircuitHelper.append_wire_info(extra, entity)
  local summary = CircuitHelper.get_wire_summary(entity)
  
  if summary == "" then
    return extra  -- No change
  end
  
  if extra and extra ~= "" then
    return extra .. ",wires=" .. summary
  else
    return "wires=" .. summary
  end
end

return CircuitHelper
