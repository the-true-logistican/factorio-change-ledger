local M = require("config")
local Change = require("change")
local CircuitHelper = require("integrations.circuit_helper")

local Vanilla = {}

function Vanilla.is_available()
  return true
end

-- Returns a list of all actions/manipulations this integration tracks
function Vanilla.get_tracked_actions()
  return {
    "BUILD - Entität wird gebaut (Spieler, Roboter, Script)",
    "REMOVE - Entität wird abgebaut oder zerstört",
    "ROTATE - Entität wird gedreht",
    "FLIP - Entität wird gespiegelt",
    "MODULE_IN - Module werden eingefügt",
    "MODULE_OUT - Module werden entfernt",
    "MAT_TAKE - Materialien werden aus Container entnommen",
    "MARK_DECON - Entität für Abbau markiert",
    "MARK_UPGRADE - Entität für Upgrade markiert",
    "CIRCUIT_WIRES - Kabelverbindungen (bei BUILD/REMOVE/MOVE)"
  }
end

function Vanilla.register(reg)
  local function should_record()
    M.ensure_storage_defaults()
    return storage.cl.recording == true
  end

  local function log_change(action, e, ent, extra)
    if not should_record() then return end
    
    -- Add circuit wire information if entity supports it
    extra = CircuitHelper.append_wire_info(extra or "", ent)
    
    Change.push_event(Change.make_entity_event(action, e, ent, extra))
  end

local function module_sig(ent)
  if not (ent and ent.valid and ent.get_module_inventory) then return "" end
  local inv = ent.get_module_inventory()
  if not (inv and inv.valid) then return "" end
  local parts = {}
  for i = 1, #inv do
    local st = inv[i]
    if st and st.valid_for_read then
      local q = (st.quality and st.quality.name) or "normal"
      parts[#parts+1] = st.name .. "@" .. q .. "x" .. tostring(st.count)
    end
  end
  return table.concat(parts, "|")
end

local function parse_module_sig(sig)
  local m = {}
  if type(sig) ~= "string" or sig == "" then return m end
  for token in string.gmatch(sig, "[^|]+") do
    local name, q, count = string.match(token, "^(.-)@([^x]+)x(%d+)$")
    if name and q and count then
      local key = name .. "@" .. q
      m[key] = (m[key] or 0) + tonumber(count)
    end
  end
  return m
end

local function diff_module_sigs(before_sig, after_sig)
  local b = parse_module_sig(before_sig)
  local a = parse_module_sig(after_sig)
  local added, removed = {}, {}

  local keys = {}
  for k in pairs(b) do keys[k] = true end
  for k in pairs(a) do keys[k] = true end

  for k in pairs(keys) do
    local d = (a[k] or 0) - (b[k] or 0)
    if d > 0 then
      added[#added+1] = { k = k, n = d }
    elseif d < 0 then
      removed[#removed+1] = { k = k, n = -d }
    end
  end

  local function sort_by_key(x, y) return x.k < y.k end
  table.sort(added, sort_by_key)
  table.sort(removed, sort_by_key)
  return added, removed
end

local function fmt_module_list(list)
  if not list or #list == 0 then return "-" end
  local parts = {}
  for i = 1, #list do
    local k = list[i].k
    local n = list[i].n
    local name, q = string.match(k, "^(.-)@(.+)$")
    if q and q ~= "normal" then
      parts[#parts+1] = string.format("%s@%sx%d", name, q, n)
    else
      parts[#parts+1] = string.format("%sx%d", name or k, n)
    end
  end
  return table.concat(parts, ",")
end

local function maybe_log_module_change(e, ent, before_sig, after_sig)
  if before_sig == after_sig then return end
  if not should_record() then return end

  local added, removed = diff_module_sigs(before_sig, after_sig)

  -- IMPORTANT: always log a single activity per event.
  -- If both directions happen in one user action, we emit TWO events:
  -- first MODULE_OUT, then MODULE_IN (same tick is fine).
  if removed and #removed > 0 then
    local extra_out = "mods_out=" .. fmt_module_list(removed)
    Change.push_event(Change.make_entity_event("MODULE_OUT", e, ent, extra_out))
  end

  if added and #added > 0 then
    local extra_in = "mods_in=" .. fmt_module_list(added)
    Change.push_event(Change.make_entity_event("MODULE_IN", e, ent, extra_in))
  end
end


  -- Build (Factorio 2.0: event.entity, fallback for safety)
  reg:add(defines.events.on_built_entity, function(e)
    log_change("BUILD", e, e.entity or e.created_entity)
  end)

  reg:add(defines.events.on_robot_built_entity, function(e)
    log_change("BUILD", e, e.entity or e.created_entity)
  end)

  reg:add(defines.events.script_raised_built, function(e)
    log_change("BUILD", e, e.entity, "raised=script")
  end)

  -- BEFORE mining: contents still exist (chests/machines/belts/inserters)
  reg:add(defines.events.on_pre_player_mined_item, function(e)
    Change.capture_material_events(e, e.entity)
  end)

  reg:add(defines.events.on_robot_pre_mined, function(e)
    Change.capture_material_events(e, e.entity)
  end)

  -- Remove / mined / destroyed
  reg:add(defines.events.on_player_mined_entity, function(e)
    Change.capture_material_events(e, e.entity)
    log_change("REMOVE", e, e.entity, "reason=mined")
  end)

  reg:add(defines.events.on_robot_mined_entity, function(e)
    Change.capture_material_events(e, e.entity)
    log_change("REMOVE", e, e.entity, "reason=mined")
  end)

  reg:add(defines.events.on_entity_died, function(e)
    Change.capture_material_events(e, e.entity)
    log_change("REMOVE", e, e.entity, "reason=died")
  end)

  reg:add(defines.events.script_raised_destroy, function(e)
    local ent = e.entity
    if ent and ent.valid then
      Change.capture_material_events(e, ent)
    end
    log_change("REMOVE", e, ent, "raised=script")
  end)

  -- Rotate / Flip
  reg:add(defines.events.on_player_rotated_entity, function(e)
    local prev = e.previous_direction
    local extra = prev and ("prev_dir=" .. tostring(prev)) or ""
    log_change("ROTATE", e, e.entity, extra)
  end)

  reg:add(defines.events.on_player_flipped_entity, function(e)
    local parts = {}
    if e.flip_direction ~= nil then parts[#parts+1] = "flip=" .. tostring(e.flip_direction) end
    if e.horizontal ~= nil then parts[#parts+1] = "h=" .. tostring(e.horizontal) end
    if e.vertical ~= nil then parts[#parts+1] = "v=" .. tostring(e.vertical) end
    log_change("FLIP", e, e.entity, table.concat(parts, ","))
  end)


-- Module changes in entity GUI (no dedicated runtime event):
-- We snapshot module inventory on GUI open and compare on cursor changes / GUI close.
reg:add(defines.events.on_gui_opened, function(e)
  local p = game.get_player(e.player_index)
  if not p then return end
  local ent = e.entity
  if not (ent and ent.valid) then
    storage.cl.open_gui = storage.cl.open_gui or {}
    storage.cl.open_gui[e.player_index] = nil
    return
  end

  local sig = module_sig(ent)
  if sig == "" then return end

  storage.cl.open_gui = storage.cl.open_gui or {}
  storage.cl.open_gui[e.player_index] = {
    unit = ent.unit_number,
    surface = ent.surface and ent.surface.index or nil,
    sig = sig,
    last_tick = -1
  }
end)

reg:add(defines.events.on_player_cursor_stack_changed, function(e)
  local og = storage.cl.open_gui and storage.cl.open_gui[e.player_index]
  if not og then return end
  local p = game.get_player(e.player_index)
  if not p then return end
  local ent = p.opened
  if not (ent and ent.valid and ent.unit_number == og.unit) then return end

  -- avoid double work in same tick
  if og.last_tick == e.tick then return end
  og.last_tick = e.tick

  local after = module_sig(ent)
  maybe_log_module_change(e, ent, og.sig, after)
  og.sig = after
end)

reg:add(defines.events.on_gui_closed, function(e)
  local og = storage.cl.open_gui and storage.cl.open_gui[e.player_index]
  if not og then return end
  local p = game.get_player(e.player_index)
  if not p then
    storage.cl.open_gui[e.player_index] = nil
    return
  end

  local ent = e.entity
  if not (ent and ent.valid and ent.unit_number == og.unit) then
    storage.cl.open_gui[e.player_index] = nil
    return
  end

  local after = module_sig(ent)
  maybe_log_module_change(e, ent, og.sig, after)
  storage.cl.open_gui[e.player_index] = nil
end)


  -- Mark (planned changes)
  reg:add(defines.events.on_marked_for_deconstruction, function(e)
    log_change("MARK_DECON", e, e.entity)
  end)

  reg:add(defines.events.on_marked_for_upgrade, function(e)
    local extra = ""
    if e.target and e.target.valid then
      extra = "target=" .. tostring(e.target.name)
    end
    log_change("MARK_UPGRADE", e, e.entity, extra)
  end)
end

return Vanilla
