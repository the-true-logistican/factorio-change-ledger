-- =========================================
-- Change Ledger (Factorio 2.0) 
-- Record the activities ahile modifying the factory
--
-- version 0.1.0 first try
-- version 0.2.0 first opertional Version
--
-- =========================================

local Config = require("config")

local Change = {}
Change.version = "0.2.0"

local function ensure_defaults()
  Config.ensure_storage_defaults()
end

local function safe_name(ent)
  if not (ent and ent.valid) then return "-" end
  return ent.name or "-"
end

local function safe_unit(ent)
  if not (ent and ent.valid) then return "-" end
  return ent.unit_number or "-"
end

local function safe_pos(ent)
  if not (ent and ent.valid) then return nil end
  return ent.position
end

local function safe_surface(ent, fallback)
  if ent and ent.valid and ent.surface then return ent.surface.name end
  if type(fallback) == "string" then return fallback end
  if fallback and fallback.valid then return fallback.name end
  return "?"
end

local function safe_force(ent, fallback)
  if ent and ent.valid and ent.force then return ent.force.name end
  if type(fallback) == "string" then return fallback end
  if fallback and fallback.valid then return fallback.name end
  return "?"
end

local function actor_from_event(e)
  if e and e.player_index then
    local p = game and game.get_player(e.player_index)
    if p and p.valid then
      return "PLAYER", p.name, p.index
    end
    return "PLAYER", "?", e.player_index
  end
  if e and e.robot then
    return "ROBOT", safe_name(e.robot), e.robot.unit_number
  end
  return "SCRIPT", "script", 0
end

-- ---------------- Ringbuffer ----------------

local function rb_ensure()
  ensure_defaults()
  local cl = storage.cl

  cl.chg_events = cl.chg_events or {}
  cl.chg_max_events = tonumber(cl.chg_max_events) or Config.CHG_MAX_EVENTS or 50000

  cl.chg_seq   = tonumber(cl.chg_seq)   or 0
  cl.chg_head  = tonumber(cl.chg_head)  or 1
  cl.chg_size  = tonumber(cl.chg_size)  or 0
  cl.chg_write = tonumber(cl.chg_write) or 1

  local max = cl.chg_max_events
  if cl.chg_head < 1 or cl.chg_head > max then cl.chg_head = 1 end
  if cl.chg_write < 1 or cl.chg_write > max then cl.chg_write = 1 end
  if cl.chg_size < 0 then cl.chg_size = 0 end
  if cl.chg_size > max then cl.chg_size = max end
end

local function rb_get_event(i)
  rb_ensure()
  local cl = storage.cl
  local size = cl.chg_size or 0
  if not i or i < 1 or i > size then return nil end
  local max  = cl.chg_max_events
  local head = cl.chg_head
  local phys = ((head + (i - 1) - 1) % max) + 1
  return cl.chg_events[phys]
end

function Change.push_event(ev)
  rb_ensure()
  local cl = storage.cl

  cl.chg_seq = (cl.chg_seq or 0) + 1
  ev.id = cl.chg_seq

  local t   = cl.chg_events
  local max = cl.chg_max_events
  local w   = cl.chg_write
  local size= cl.chg_size or 0

  t[w] = ev

  if size < max then
    cl.chg_size = size + 1
  else
    cl.chg_head = (cl.chg_head % max) + 1
  end

  cl.chg_write = (w % max) + 1
end

-- Expose raw events for UI-level formatting/aggregation.
function Change.peek_event(i)
  return rb_get_event(i)
end

local function fmt_pos(pos)
  if not pos then return "?,?" end
  return string.format("%.1f,%.1f", pos.x or 0, pos.y or 0)
end

local function format_event(ev, extra_override)
  if not ev then return "" end
  local actor = tostring(ev.actor_type or "?")
  if ev.actor_name then actor = actor .. ":" .. tostring(ev.actor_name) end

  return string.format(
    "%d;tick=%d;sess=%s;act=%s;actor=%s;entity=%s;unit=%s;pos=%s;extra=%s",
    tonumber(ev.id or 0),
    tonumber(ev.tick or 0),
    tostring(ev.session or ""),
    tostring(ev.action or "?"),
    actor,
    tostring(ev.entity_name or "-"),
    tostring(ev.unit_number or "-"),
    fmt_pos(ev.position),
    tostring(extra_override ~= nil and extra_override or (ev.extra or ""))
  )
end

function Change.format_event(ev, extra_override)
  return format_event(ev, extra_override)
end


function Change.size()
  rb_ensure()
  return storage.cl.chg_size or 0
end

-- ---------------- Viewer paging ----------------

local function get_viewer_state(player_index)
  ensure_defaults()
  storage.cl.viewer = storage.cl.viewer or {}
  local v = storage.cl.viewer[player_index]
  if not v then
    v = { anchor = 0 } -- 0 = tail
    storage.cl.viewer[player_index] = v
  end
  return v
end

function Change.viewer_home(player_index)
  get_viewer_state(player_index).anchor = 1
end

function Change.viewer_end(player_index)
  get_viewer_state(player_index).anchor = 0
end

function Change.viewer_page_older(player_index, page_lines)
  page_lines = page_lines or M.GUI_MAX_LINES
  local v = get_viewer_state(player_index)
  local size = Change.size()
  if size <= 0 then v.anchor = 1; return end

  local anchor = v.anchor
  if anchor == 0 then
    anchor = math.max(1, size - page_lines + 1)
  else
    anchor = math.max(1, anchor - page_lines)
  end
  v.anchor = anchor
end

function Change.viewer_page_newer(player_index, page_lines)
  page_lines = page_lines or M.GUI_MAX_LINES
  local v = get_viewer_state(player_index)
  local size = Change.size()
  if size <= 0 then v.anchor = 1; return end
  if v.anchor == 0 then return end

  local anchor = v.anchor + page_lines
  if anchor >= size - page_lines + 1 then
    v.anchor = 0
  else
    v.anchor = anchor
  end
end

-- ---------------- Rendering ----------------

-- Render one viewer line.
-- `filters` is an optional table: {player=bool, robot=bool, ghost=bool, other=bool}
-- NOTE: Ghost lines are currently always suppressed (see filter rules below).
function Change.get_line(i, _surface, filters)
  if i == 1 then return "# CHG" end
  if i == 2 then return "# id;tick;sess;act;actor;entity;unit;pos;extra" end

  local page_i = i - 2
  if page_i < 1 then return "" end

  local ev = rb_get_event(page_i)
  if not ev then return "" end

  -- ---------------- Filter rules ----------------
  -- Ghost events are tagged via extra "ghost=1" by make_entity_event().
  if type(ev.extra) == "string" and string.find(ev.extra, "ghost=1", 1, true) then
    if not (filters and filters.ghost) then
      return nil
    end
  end

  local f = filters or { player=true, robot=true, ghost=true, other=true }
  local at = tostring(ev.actor_type or "?")
  if at == "PLAYER" then
    if f.player ~= true then return nil end
  elseif at == "ROBOT" then
    if f.robot ~= true then return nil end
  elseif at == "SCRIPT" then
    if f.other ~= true then return nil end
  else
    -- Unknown actor types are treated as "other".
    if f.other ~= true then return nil end
  end

  local actor = tostring(ev.actor_type or "?")
  if ev.actor_name then actor = actor .. ":" .. tostring(ev.actor_name) end

  return string.format(
    "%d;tick=%d;sess=%s;act=%s;actor=%s;entity=%s;unit=%s;pos=%s;extra=%s",
    tonumber(ev.id or 0),
    tonumber(ev.tick or 0),
    tostring(ev.session or ""),
    tostring(ev.action or "?"),
    actor,
    tostring(ev.entity_name or "-"),
    tostring(ev.unit_number or "-"),
    fmt_pos(ev.position),
    tostring(ev.extra or "")
  )
end

-- ---------------- Event builders ----------------

local function contents_to_pairs(c)
  local out = {}
  if type(c) ~= "table" then return out end

  -- If it's an array-like list: { {name=..., count=...}, ... }
  if c[1] ~= nil and type(c[1]) == "table" then
    for _, rec in ipairs(c) do
      local name = rec.name or rec.item or rec[1]
      local cnt  = rec.count or rec.amount or rec[2]
      cnt = tonumber(cnt) or 0
      if name and name ~= "" and cnt > 0 then
        out[#out+1] = { item=tostring(name), cnt=cnt }
      end
    end
    return out
  end

  -- Otherwise treat as map: item -> number OR item -> (quality -> number)
  for item, v in pairs(c) do
    if type(v) == "number" then
      if v > 0 then out[#out+1] = { item=tostring(item), cnt=v } end
    elseif type(v) == "table" then
      -- quality map
      for qual, cnt in pairs(v) do
        cnt = tonumber(cnt) or 0
        if cnt > 0 then
          out[#out+1] = { item=tostring(item) .. "@" .. tostring(qual), cnt=cnt }
        end
      end
    end
  end

  return out
end

function Change.make_rec_event(player, action)
  ensure_defaults()
  -- Recording toggles are modeled as SCRIPT events ("3rd participant")
  -- but we keep the triggering player for traceability in extra.
  return Change.make_script_event(player, action, "")
end

-- SCRIPT events: meta-events like REC_START/REC_STOP/MARK
function Change.make_script_event(player, action, extra)
  ensure_defaults()
  local cl = storage.cl

  local p_name  = (player and player.valid) and player.name or "?"
  local p_index = (player and player.valid) and player.index or 0
  local surface = (player and player.valid and player.surface) and player.surface.name or "?"
  local force   = (player and player.valid and player.force) and player.force.name or "?"

  local extra2 = extra or ""
  if extra2 ~= "" then extra2 = extra2 .. "," end
  extra2 = extra2 .. "by=" .. tostring(p_name) .. ",pidx=" .. tostring(p_index)

  return {
    session = tonumber(cl.chg_session_id) or 0,
    tick = game and game.tick or 0,
    action = action,
    actor_type = "SCRIPT",
    actor_name = "script",
    actor_index = 0,
    surface = surface,
    force = force,
    entity_name = "-",
    unit_number = "-",
    position = nil,
    dir_before = nil,
    dir_after = nil,
    extra = extra2
  }
end

function Change.make_mark_event(player, label)
  -- label is optional free text to annotate a milestone
  local extra = ""
  if label and tostring(label) ~= "" then
    extra = "label=" .. tostring(label)
  end
  return Change.make_script_event(player, Config.SCRIPT_ACTIONS.MARK, extra)
end

function Change.make_entity_event(action, e, ent, extra)
  ensure_defaults()
  local cl = storage.cl
  local actor_type, actor_name, actor_index = actor_from_event(e or {})

  local entity_name = safe_name(ent)
  local unit_number = safe_unit(ent)
  local position    = safe_pos(ent)
  local extra2 = extra or ""

  -- Ghost handling: log intended entity name
  if ent and ent.valid and (ent.name == "entity-ghost" or ent.type == "entity-ghost") then
    local gname = ent.ghost_name
    entity_name = (gname and gname ~= "") and gname or "?"
    if extra2 ~= "" then extra2 = extra2 .. "," end
    extra2 = extra2 .. "ghost=1"
  end

  return {
    session = tonumber(cl.chg_session_id) or 0,
    tick = game and game.tick or 0,
    action = action,
    actor_type = actor_type,
    actor_name = actor_name,
    actor_index = actor_index,
    surface = safe_surface(ent, (e and e.surface) or nil),
    force = safe_force(ent, (e and e.force) or nil),
    entity_name = entity_name,
    unit_number = unit_number,
    position = position,
    dir_before = e and e.previous_direction or nil,
    dir_after = (ent and ent.valid) and ent.direction or nil,
    extra = extra2
  }
end

function Change.make_material_event(base_ev, item_name, count, src, extra)
  local extra2 = extra or ""
  if extra2 ~= "" then extra2 = extra2 .. "," end
  extra2 = extra2
    .. "src=" .. tostring(src or "?")
    .. ",item=" .. tostring(item_name or "?")
    .. ",cnt=" .. tostring(count or 0)

  return {
    session = base_ev.session,
    tick = base_ev.tick,
    action = "MAT_TAKE",
    actor_type = base_ev.actor_type,
    actor_name = base_ev.actor_name,
    actor_index = base_ev.actor_index,
    surface = base_ev.surface,
    force = base_ev.force,
    entity_name = base_ev.entity_name,
    unit_number = base_ev.unit_number,
    position = base_ev.position,
    dir_before = base_ev.dir_before,
    dir_after  = base_ev.dir_after,
    extra = extra2
  }
end

-- ---------------- Material capture ----------------
local function inv_contents(ent)
  -- nur Container für jetzt (logistic-container inklusive)
  local inv = ent.get_inventory(defines.inventory.chest)
  if not (inv and inv.valid and #inv > 0) then return {} end
  return inv.get_contents() or {}
end

local function diff_take(before, after)
  -- before/after: item->count
  local out = {}
  for item, b in pairs(before or {}) do
    local a = (after and after[item]) or 0
    local d = (tonumber(b) or 0) - (tonumber(a) or 0)
    if d > 0 then out[item] = d end
  end
  return out
end

function Change.robot_pre_snapshot(e, ent)
  ensure_defaults()
  if storage.cl.recording ~= true then return end
  if not (ent and ent.valid) then return end
  if ent.type ~= "container" and ent.type ~= "logistic-container" then return end

  storage.cl.rb_pre = storage.cl.rb_pre or {}
  -- key: unit_number reicht hier, weil es um dasselbe Entity geht
  local key = tostring(ent.unit_number or 0)

  storage.cl.rb_pre[key] = {
    tick = game.tick,
    pos = ent.position,
    contents = inv_contents(ent)
  }
end

function Change.robot_post_delta(e, ent)
  ensure_defaults()
  if storage.cl.recording ~= true then return end
  if not (ent and ent.valid) then return end
  if ent.type ~= "container" and ent.type ~= "logistic-container" then return end

  local pre = storage.cl.rb_pre and storage.cl.rb_pre[tostring(ent.unit_number or 0)]
  if not pre then return end

  local after = inv_contents(ent)
  local take = diff_take(pre.contents, after)

  if next(take) ~= nil then
    local base_ev = Change.make_entity_event("REMOVE", e, ent, "mat=delta")
    for item, cnt in pairs(take) do
      push_mat(base_ev, item, cnt, "robot_take_delta")
    end
  end
end

local function flatten__contents(c)
  local out = {}
  if type(c) ~= "table" then return out end
  for item, v in pairs(c) do
    if type(v) == "number" then
      out[#out+1] = { item=item, cnt=v }
    elseif type(v) == "table" then
      for qual, cnt in pairs(v) do
        out[#out+1] = { item=item .. "@" .. tostring(qual), cnt=cnt }
      end
    end
  end
  return out
end

local function push_mat(base_ev, item, cnt, src)
  cnt = tonumber(cnt) or 0
  if not item or item == "" or cnt <= 0 then return end
  Change.push_event(Change.make_material_event(base_ev, item, cnt, src))
end


-- Helper function: Get all inventories of an entity (based on Big Brother mod)
local function get_all_entity_inventories(ent)
  if not (ent and ent.valid) then return {} end
  
  local inventories = {}
  local seen_inventories = {}
  
  local inventory_types = {
    {type = defines.inventory.chest, slot_name = "chest"},
    {type = defines.inventory.furnace_source, slot_name = "input"},
    {type = defines.inventory.furnace_result, slot_name = "output"},
    {type = defines.inventory.furnace_modules, slot_name = "modules"},
    {type = defines.inventory.assembling_machine_input, slot_name = "input"},
    {type = defines.inventory.assembling_machine_output, slot_name = "output"},
    {type = defines.inventory.assembling_machine_modules, slot_name = "modules"},
    {type = defines.inventory.lab_input, slot_name = "input"},
    {type = defines.inventory.lab_modules, slot_name = "modules"},
    {type = defines.inventory.mining_drill_modules, slot_name = "modules"},
    {type = defines.inventory.rocket_silo_input, slot_name = "input"},
    {type = defines.inventory.rocket_silo_output, slot_name = "output"},
    {type = defines.inventory.rocket_silo_modules, slot_name = "modules"},
    {type = defines.inventory.beacon_modules, slot_name = "modules"},
    {type = defines.inventory.fuel, slot_name = "fuel"},
    {type = defines.inventory.burnt_result, slot_name = "burnt_result"},
  }
  
  log("[Change Ledger DEBUG] get_all_entity_inventories für " .. tostring(ent.name))
  log("[Change Ledger DEBUG]   Entity.valid=" .. tostring(ent.valid) .. ", type=" .. tostring(ent.type))
  
  for _, inv_data in pairs(inventory_types) do
    log("[Change Ledger DEBUG]   Teste Inventory: " .. tostring(inv_data.slot_name) .. " (type=" .. tostring(inv_data.type) .. ")")
    local inv = ent.get_inventory(inv_data.type)
    
    if not inv then
      log("[Change Ledger DEBUG]     -> get_inventory gab nil zurück")
    elseif not inv.valid then
      log("[Change Ledger DEBUG]     -> Inventory ist invalid")
    else
      local inv_index = inv.index
      log("[Change Ledger DEBUG]     -> GEFUNDEN! (index=" .. tostring(inv_index) .. ", #slots=" .. tostring(#inv) .. ")")
      
      if not seen_inventories[inv_index] then
        seen_inventories[inv_index] = true
        table.insert(inventories, {
          inventory = inv,
          type = inv_data.type,
          slot_name = inv_data.slot_name
        })
      else
        log("[Change Ledger DEBUG]       -> Aber Duplikat (index=" .. tostring(inv_index) .. ")")
      end
    end
  end
  
  log("[Change Ledger DEBUG]   Insgesamt " .. tostring(#inventories) .. " Inventories")
  return inventories
end

function Change.capture_material_events_at_mark(e, ent)
  ensure_defaults()
  if storage.cl.recording ~= true then return end
  if not (ent and ent.valid) then return end
  if not ent.unit_number then return end
  
  log("[Change Ledger DEBUG] capture_material_events_at_mark() für " .. tostring(ent.name) .. " unit=" .. tostring(ent.unit_number))
  
  storage.cl.marked_materials = storage.cl.marked_materials or {}
  local unit_key = tostring(ent.unit_number)
  local materials = {}
  
  local function collect_mat(item_name, item_count, item_quality, src)
    if not item_name or item_count <= 0 then return end
    local quality_str = (item_quality and item_quality ~= "normal") and ("@" .. item_quality) or ""
    log("[Change Ledger DEBUG]   - Material: src=" .. tostring(src) .. ", item=" .. tostring(item_name) .. quality_str .. ", cnt=" .. tostring(item_count))
    materials[#materials + 1] = { item = item_name .. quality_str, cnt = item_count, src = src }
  end
  
  log("[Change Ledger DEBUG] Entity-Typ: " .. tostring(ent.type))
  
  -- (1) Belts
  if ent.get_transport_line then
    local t = ent.type
    local max_lines = (t == "splitter") and 4 or 2
    if t == "transport-belt" or t == "underground-belt" or t == "splitter" or t == "linked-belt" then
      for i = 1, max_lines do
        local ok, line = pcall(ent.get_transport_line, ent, i)
        if ok and line and line.valid and line.get_contents then
          for _, rec in ipairs(contents_to_pairs(line.get_contents())) do
            collect_mat(rec.item, rec.cnt, nil, "belt_line_" .. i)
          end
        end
      end
    end
  end

  -- (2) Inserter
  if ent.type == "inserter" then
    local ok, hs = pcall(function() return ent.held_stack end)
    if ok and hs and hs.valid_for_read then
      collect_mat(hs.name, hs.count, hs.quality and hs.quality.name, "inserter_held")
    end
  end

  -- (3) Alle Inventories
  local inventories = get_all_entity_inventories(ent)
  for _, inv_data in pairs(inventories) do
    if inv_data.inventory and inv_data.inventory.valid then
      local ok_contents, contents = pcall(function() return inv_data.inventory.get_contents() end)
      if ok_contents and contents then
        local count = 0
        for _ in pairs(contents) do count = count + 1 end
        log("[Change Ledger DEBUG]     Slot '" .. inv_data.slot_name .. "': " .. tostring(count) .. " Items")
        for _, item_data in pairs(contents) do
          if type(item_data) == "table" and item_data.name then
            collect_mat(item_data.name, item_data.count, item_data.quality or "normal", inv_data.slot_name)
          end
        end
      end
    end
  end
  
  storage.cl.marked_materials[unit_key] = {
    tick = game.tick,
    materials = materials,
    entity_name = ent.name,
    position = ent.position
  }
  
  log("[Change Ledger DEBUG] Fertig: " .. tostring(#materials) .. " Materialien gespeichert")
  if #materials == 0 then
    log("[Change Ledger DEBUG] WARNUNG: Keine Materialien!")
  end
end

function Change.capture_material_events(e, ent)
  ensure_defaults()
  if storage.cl.recording ~= true then return end
  if not (ent and ent.valid) then return end

  log("[Change Ledger DEBUG] capture_material_events() aufgerufen für " .. tostring(ent.name) .. " unit=" .. tostring(ent.unit_number))

  local unit_key = tostring(ent.unit_number or "")
  local tick = game.tick or 0
  
  -- Use REMOVE base event just as "context carrier" for MAT_TAKE
  local base_ev = Change.make_entity_event("REMOVE", e, ent, "mat=probe")
  
  -- DELTA-TRACKING: Speichere "vorher" Snapshot beim ersten Roboter-Besuch
  storage.cl.robot_snapshots = storage.cl.robot_snapshots or {}
  
  -- Erfasse aktuellen Inventar-Zustand
  local current_snapshot = {}
  local inventories = get_all_entity_inventories(ent)
  
  for _, inv_data in pairs(inventories) do
    if inv_data.inventory and inv_data.inventory.valid then
      local contents = inv_data.inventory.get_contents()
      
      if contents then
        for _, item_data in pairs(contents) do
          if type(item_data) == "table" and item_data.name then
            local quality = item_data.quality or "normal"
            local quality_str = (quality ~= "normal") and ("@" .. quality) or ""
            local item_key = inv_data.slot_name .. "::" .. item_data.name .. quality_str
            
            current_snapshot[item_key] = item_data.count
          end
        end
      end
    end
  end
  
  -- Prüfe ob wir bereits einen Snapshot haben
  local previous_snapshot = storage.cl.robot_snapshots[unit_key]
  
  if not previous_snapshot then
    -- ERSTER Roboter-Besuch: Speichere Snapshot, logge aber NICHTS
    log("[Change Ledger DEBUG] Erster Roboter-Besuch - speichere Snapshot für Zukunft")
    storage.cl.robot_snapshots[unit_key] = {
      tick = tick,
      snapshot = current_snapshot
    }
    
    -- Bereinige alte Snapshots (älter als 600 Ticks)
    for key, data in pairs(storage.cl.robot_snapshots) do
      if tick - data.tick > 600 then
        storage.cl.robot_snapshots[key] = nil
      end
    end
    
    return -- Beim ersten Besuch NICHTS loggen
  end
  
  -- NACHFOLGENDE Roboter-Besuche: Berechne Delta und logge NUR Entnahmen
  log("[Change Ledger DEBUG] Nachfolgender Roboter-Besuch - berechne Delta")
  
  local prev = previous_snapshot.snapshot
  local deltas = {}
  
  -- Finde was entnommen wurde (vorher > jetzt)
  for item_key, prev_count in pairs(prev) do
    local curr_count = current_snapshot[item_key] or 0
    local delta = prev_count - curr_count
    
    if delta > 0 then
      -- Parse item_key zurück: "slot_name::item_name@quality"
      local slot_name, item_name = item_key:match("([^:]+)::(.+)")
      log("[Change Ledger DEBUG]   Delta gefunden: " .. item_key .. " = -" .. tostring(delta))
      
      push_mat(base_ev, item_name, delta, slot_name)
    end
  end
  
  -- Update Snapshot für nächsten Roboter
  storage.cl.robot_snapshots[unit_key] = {
    tick = tick,
    snapshot = current_snapshot
  }
  
  -- Wenn Snapshot leer ist, aufräumen (alles wurde entnommen)
  local is_empty = true
  for _ in pairs(current_snapshot) do
    is_empty = false
    break
  end
  
  if is_empty then
    log("[Change Ledger DEBUG] Inventar komplett leer - lösche Snapshot")
    storage.cl.robot_snapshots[unit_key] = nil
  end
end

return Change
