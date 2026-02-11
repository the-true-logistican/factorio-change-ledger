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
  local ok, inv = pcall(ent.get_inventory, ent, defines.inventory.chest)
  if not (ok and inv and inv.valid and #inv > 0) then return {} end
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

function Change.capture_material_events(e, ent)
  ensure_defaults()
  if storage.cl.recording ~= true then return end
  if not (ent and ent.valid) then return end

  -- Use REMOVE base event just as "context carrier" for MAT_TAKE
  local base_ev = Change.make_entity_event("REMOVE", e, ent, "mat=probe")

  -- (1) Belts / splitters: try a small set of lines safely (nice-to-have)
  if ent.get_transport_line then
    local t = ent.type
    local max_lines = (t == "splitter") and 4 or 2
    if t == "transport-belt" or t == "underground-belt" or t == "splitter" or t == "linked-belt" then
      for i = 1, max_lines do
        local ok, line = pcall(ent.get_transport_line, ent, i)
        if ok and line and line.valid and line.get_contents then
          local contents = line.get_contents()
          for _, rec in ipairs(contents_to_pairs(contents)) do
            push_mat(base_ev, rec.item, rec.cnt, "belt_line_" .. i)
          end
        end
      end
    end
  end

  -- (2) Inserter held stack (robust: ONLY for inserters + pcall)
  if ent.type == "inserter" then
    local ok, hs = pcall(function() return ent.held_stack end)
    if ok and hs and hs.valid_for_read then
      push_mat(base_ev, hs.name, hs.count, "inserter_held")
    end
  end

  -- (3) Container contents (wooden chest, steel chest, logistic chests)
  if ent.type == "container" or ent.type == "logistic-container" then
    -- Primary: chest inventory
    local ok_ch, inv_ch = pcall(ent.get_inventory, ent, defines.inventory.chest)
    local logged_any = false

    if ok_ch and inv_ch and inv_ch.valid and #inv_ch > 0 then
      local c = inv_ch.get_contents()
      for _, rec in ipairs(contents_to_pairs(c)) do
        push_mat(base_ev, rec.item, rec.cnt, "chest")
        logged_any = true
      end
    end

    -- Fallback: some containers expose contents under other inventory ids (mods / edge cases)
    if not logged_any then
      local seen = {}
      for _, inv_id in pairs(defines.inventory) do
        if type(inv_id) == "number" and not seen[inv_id] then
          seen[inv_id] = true
          local ok, inv = pcall(ent.get_inventory, ent, inv_id)
          if ok and inv and inv.valid and #inv > 0 then
            local c = inv.get_contents()
            for _, rec in ipairs(contents_to_pairs(c)) do
              push_mat(base_ev, rec.item, rec.cnt, "inv_" .. tostring(inv_id))
              logged_any = true
            end
          end
        end
      end
    end
  end

  -- (4) Output inventory (some entities expose this)
  if ent.get_output_inventory then
    local ok, outinv = pcall(ent.get_output_inventory, ent)
    if ok and outinv and outinv.valid and #outinv > 0 then
      local c = outinv.get_contents()
      for _, rec in ipairs(contents_to_pairs(c)) do
        push_mat(base_ev, rec.item, rec.cnt, "output")
      end
    end
  end

  -- (5) Module inventory (explicit)
  if ent.get_module_inventory then
    local ok, minv = pcall(ent.get_module_inventory, ent)
    if ok and minv and minv.valid and #minv > 0 then
      local c = minv.get_contents()
      for _, rec in ipairs(contents_to_pairs(c)) do
        push_mat(base_ev, rec.item, rec.cnt, "modules")
      end
    end
  end
end

return Change
