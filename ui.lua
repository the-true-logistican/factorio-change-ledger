-- =========================================
-- Change Ledger (Factorio 2.0) 
-- All GUI creation and interaction logic (buffer, transactions, export, reset, blueprint views).
--
-- version 0.1.0 first try
-- version 0.2.0 first opertional Version
--
-- =========================================

local M = require("config")
local Change = require("change")
local mod_gui = require("mod-gui")

local UI = {}

UI.version = "0.8.4"


-- Read current Change Viewer checkbox states.
-- Defaults to true if the GUI (or element) is missing.
function UI.get_chg_filters(player)
  local defaults = { player=true, robot=true, ghost=true, other=true }
  if not (player and player.valid) then return defaults end

  local screen = player.gui and player.gui.screen
  if not screen then return defaults end

  local frame = screen[M.GUI_CHG_FRAME]
  if not (frame and frame.valid) then return defaults end

  local top = frame["cl_chg_toolbar"]
  if not (top and top.valid) then return defaults end

  local function read_checkbox(name)
    local el = top[name]
    if el and el.valid and el.type == "checkbox" then
      return el.state == true
    end
    return true
  end

  return {
    player = read_checkbox("cl_chg_chk_player"),
    robot  = read_checkbox("cl_chg_chk_robot"),
    ghost  = read_checkbox("cl_chg_chk_ghost"),
    other  = read_checkbox("cl_chg_chk_other"),
  }
end

local function add_titlebar(frame, caption, close_name)
  local bar = frame.add{ type="flow", direction="horizontal" }
  bar.drag_target = frame

  bar.add{ type="label", caption=caption, style="frame_title" }

  bar.add{
    type="empty-widget",
    style="draggable_space_header"
  }.style.horizontally_stretchable = true

  bar.add{
    type="sprite-button",
    name = close_name,
    sprite="utility/close",
    style="frame_action_button"
  }
end

local function destroy_if_exists(parent, name)
  local el = parent and parent[name]
  if el and el.valid then el.destroy() end
end

function UI.build_topbar(player)
  if not (player and player.valid) then return end
  M.ensure_storage_defaults()

  local button_flow = mod_gui.get_button_flow(player)
  
  destroy_if_exists(button_flow, M.GUI_TOP_ROOT)

  -- Frame für unsere Buttons
  local frame = button_flow.add{
    type = "frame",
    name = M.GUI_TOP_ROOT,
    direction = "horizontal",
    style = "slot_button_deep_frame"
  }

  -- Flow für die Buttons
  local flow = frame.add{
    type = "flow",
    direction = "horizontal"
  }
  flow.style.horizontal_spacing = 0

  local rec_on = storage.cl.recording == true
  local rec_sprite = rec_on and "cl_stop_icon" or "cl_record_icon"

  local b1 = flow.add{
    type = "sprite-button",
    name = M.GUI_BTN_REC,
    sprite = rec_sprite,
    tooltip = M.L.top.rec_tooltip,
    style = "slot_button"
  }

  local b2 = flow.add{
    type = "sprite-button",
    name = M.GUI_BTN_LOG,
    sprite = "cl_log_icon",
    tooltip = M.L.top.log_tooltip,
    style = "slot_button"
  }

  local b3 = flow.add{
    type = "sprite-button",
    name = M.GUI_BTN_MORE,
    sprite = "cl_mark_icon",
    tooltip = M.L.top.more_tooltip,
    style = "slot_button"
  }
end

function UI.show_chg_gui(player)
  if player.gui.screen[M.GUI_CHG_FRAME] then return end

  local frame = player.gui.screen.add{
    type = "frame",
    direction = "vertical",
    name = M.GUI_CHG_FRAME
  }
  frame.auto_center = true
  add_titlebar(frame, M.L.chg.title, M.GUI_CHG_CLOSE)

  local top = frame.add{
    type = "flow",
    name = "cl_chg_toolbar",
    direction = "horizontal"
  }

  top.add{ type="button", name=M.GUI_CHG_BTN_HOME,  style="tool_button", caption="<<", tooltip=M.L.chg.home_tt }
  top.add{ type="button", name=M.GUI_CHG_BTN_OLDER, style="tool_button", caption="<",  tooltip=M.L.chg.older_tt }
  top.add{ type="button", name=M.GUI_CHG_BTN_NEWER, style="tool_button", caption=">",  tooltip=M.L.chg.newer_tt }
  top.add{ type="button", name=M.GUI_CHG_BTN_END,   style="tool_button", caption=">>", tooltip=M.L.chg.end_tt }

  top.add{ type="empty-widget" }.style.width = 5

  top.add{ type="checkbox", name="cl_chg_chk_player",   state=true, caption=M.L.chg.filter_player }
  top.add{ type="checkbox", name="cl_chg_chk_robot",   state=true, caption=M.L.chg.filter_robot }
  top.add{ type="checkbox", name="cl_chg_chk_ghost",   state=true, caption=M.L.chg.filter_ghost }
  top.add{ type="checkbox", name="cl_chg_chk_other", state=true, caption=M.L.chg.filter_other }

  top.add{ type="empty-widget" }.style.width = 16

  top.add{ type="button", name=M.GUI_CHG_BTN_COPY,   caption=M.L.chg.copy }
  top.add{ type="button", name=M.GUI_CHG_BTN_EXPORT, caption=M.L.chg.export, tooltip=M.L.chg.export_tt }
  top.add{ type="button", name=M.GUI_CHG_BTN_RESET,  caption=M.L.chg.reset, tooltip=M.L.chg.reset_tt }
  top.add{ type="button", name=M.GUI_CHG_BTN_HIDE,   caption=M.L.chg.hide }

  local box = frame.add{ type="text-box", name=M.GUI_CHG_BOX, text="" }
  box.read_only = true
  box.word_wrap = false
  box.style.width  = M.GUI_BUFFER_WIDTH
  box.style.height = M.GUI_BUFFER_HEIGHT

  UI.refresh_chg_box(player)
end

function UI.close_chg_gui(player)
  local f = player.gui.screen[M.GUI_CHG_FRAME]
  if f and f.valid then f.destroy() end
end

-- -----------------------------------------
-- Export Dialog für Change Log
-- -----------------------------------------

local function add_titlebar(frame, caption, close_name)
  local bar = frame.add{ type="flow", direction="horizontal" }
  bar.drag_target = frame

  bar.add{ type="label", caption=caption, style="frame_title" }

  bar.add{
    type="empty-widget",
    style="draggable_space_header"
  }.style.horizontally_stretchable = true

  bar.add{
    type="sprite-button",
    name = close_name,
    sprite="utility/close",
    style="frame_action_button"
  }
end

function UI.show_export_dialog(player)
  -- Wenn schon offen, nur nach vorne holen
  local existing = player.gui.screen[M.GUI_CHG_EXPORT_FRAME]
  if existing and existing.valid then
    if existing.bring_to_front then existing.bring_to_front() end
    return
  end

  local frame = player.gui.screen.add{
    type = "frame",
    name = M.GUI_CHG_EXPORT_FRAME,
    direction = "vertical",
    caption = M.L.export.title
  }
  frame.auto_center = true

  local content = frame.add{ type = "flow", direction = "vertical" }
  content.style.vertical_spacing = 8
  content.style.padding = 12

  -- Info label
  content.add{
    type = "label",
    caption = M.L.export.info
  }

  -- Filename input
  local name_flow = content.add{ type = "flow", direction = "horizontal" }
  name_flow.add{
    type = "label",
    caption = M.L.export.filename_label
  }

  -- Generate default filename
  local function sanitize_filename(s)
    return (tostring(s):gsub("[^%w%._%-]", "_"))
  end

  M.ensure_storage_defaults()
  local session_id = storage.cl.chg_session_id or 0
  local tick = game.tick
  local version = sanitize_filename(Change.version or "0.2.0")

  local default_name = string.format(
    "change_ledger_session%03d_tick%09d_v%s",
    session_id, tick, version
  )

  local filename_field = name_flow.add{
    type = "textfield",
    name = M.GUI_CHG_EXPORT_FILENAME,
    text = default_name
  }
  filename_field.style.width = 400

  content.add{ type = "line" }

  -- Format selection
  content.add{
    type = "label",
    caption = M.L.export.format_label,
    style = "bold_label"
  }

  -- CSV option
  local csv_flow = content.add{ type = "flow", direction = "horizontal" }
  csv_flow.add{
    type = "button",
    name = M.GUI_CHG_BTN_EXPORT_CSV,
    caption = M.L.export.csv,
    style = "confirm_button",
    tooltip = M.L.export.csv_tooltip
  }
  csv_flow.add{
    type = "label",
    caption = M.L.export.csv_desc
  }

  -- JSON option
  local json_flow = content.add{ type = "flow", direction = "horizontal" }
  json_flow.add{
    type = "button",
    name = M.GUI_CHG_BTN_EXPORT_JSON,
    caption = M.L.export.json,
    style = "confirm_button",
    tooltip = M.L.export.json_tooltip
  }
  json_flow.add{
    type = "label",
    caption = M.L.export.json_desc
  }

  content.add{ type = "line" }

  -- Buttons
  local buttons = frame.add{ type = "flow", direction = "horizontal" }
  buttons.style.horizontal_align = "right"
  buttons.style.padding = 12
  buttons.style.horizontal_spacing = 8

  buttons.add{
    type = "button",
    name = M.GUI_CHG_EXPORT_CLOSE,
    caption = M.L.export.cancel
  }
end

function UI.close_export_dialog(player)
  local frame = player.gui.screen[M.GUI_CHG_EXPORT_FRAME]
  if frame and frame.valid then frame.destroy() end
end

-- -----------------------------------------
-- Reset Dialog für Change Log
-- -----------------------------------------

function UI.show_reset_dialog(player)
  if player.gui.screen[M.GUI_CHG_RESET_FRAME] then return end

  local frame = player.gui.screen.add{
    type = "frame",
    name = M.GUI_CHG_RESET_FRAME,
    direction = "vertical"
  }
  frame.auto_center = true

  add_titlebar(frame, M.L.reset.title, M.GUI_CHG_RESET_CANCEL)

  local content = frame.add{ type = "flow", direction = "vertical" }
  content.style.vertical_spacing = 8
  content.style.padding = 12

  content.add{ 
    type = "label", 
    caption = M.L.reset.question,
    style = "bold_label"
  }

  content.add{ type = "line" }

  -- Warning text
  local warning = content.add{
    type = "label",
    caption = M.L.reset.warning
  }
  warning.style.single_line = false
  warning.style.maximal_width = 400

  content.add{ type = "line" }

  -- Statistics info (if available)
  M.ensure_storage_defaults()
  local size = storage.cl.chg_size or 0
  local max = storage.cl.chg_max_events or 50000
  
  local stats_text = string.format(
    "[font=default-bold]%s[/font]\n%s: %d / %d\n%s: %d",
    {"change_ledger.reset_statistics_title"},
    {"change_ledger.reset_current_events"},
    size,
    max,
    {"change_ledger.reset_current_session"},
    storage.cl.chg_session_id or 0
  )
  
  local stats = content.add{
    type = "label",
    caption = stats_text
  }
  stats.style.single_line = false

  content.add{ type = "line" }

  local buttons = frame.add{ type = "flow", direction = "horizontal" }
  buttons.style.horizontal_align = "right"
  buttons.style.padding = 12
  buttons.style.horizontal_spacing = 8

  buttons.add{ 
    type = "button", 
    name = M.GUI_CHG_RESET_CANCEL, 
    caption = M.L.reset.cancel
  }
  
  buttons.add{ 
    type = "button", 
    name = M.GUI_CHG_RESET_OK, 
    caption = M.L.reset.confirm,
    style = "red_button"
  }
end

function UI.close_reset_dialog(player)
  local f = player.gui.screen[M.GUI_CHG_RESET_FRAME]
  if f and f.valid then f.destroy() end
end

function UI.refresh_chg_box(player)
  local f = player.gui.screen[M.GUI_CHG_FRAME]
  if not (f and f.valid) then return end

  local box = f[M.GUI_CHG_BOX]
  if not (box and box.valid) then return end

  local v = storage.cl.viewer[player.index] or { anchor = 0 }
  storage.cl.viewer[player.index] = v

  local size = Change.size()
  -- page_lines counts ONLY event-list rows (header is static)
  local page_lines = M.GUI_MAX_LINES
  local start_i

  if size <= 0 then
    box.text = "# CHG\n# id;tick;sess;act;actor;entity;unit;pos;extra\n"
    return
  end

  if v.anchor == 0 then
    start_i = math.max(1, size - page_lines + 1)
  else
    start_i = math.max(1, math.min(v.anchor, size))
  end

  local lines = {}
  lines[#lines+1] = Change.get_line(1, player.surface)
  lines[#lines+1] = Change.get_line(2, player.surface)

  local filters = UI.get_chg_filters(player)

  local function is_visible(ev)
    if not ev then return false end

    -- Ghost filtering (extra contains "ghost=1")
    if type(ev.extra) == "string" and string.find(ev.extra, "ghost=1", 1, true) then
      if not (filters and filters.ghost) then
        return false
      end
    end

    local f = filters or { player=true, robot=true, ghost=true, other=true }
    local at = tostring(ev.actor_type or "?")
    if at == "PLAYER" then
      return f.player == true
    elseif at == "ROBOT" then
      return f.robot == true
    elseif at == "SCRIPT" then
      return f.other == true
    else
      return f.other == true
    end
  end

  local function extra_get(extra, key)
    if type(extra) ~= "string" then return nil end
    local pat = key .. "=([^,]+)"
    return string.match(extra, pat)
  end

  local function same_pos(a, b)
    if not (a and b) then return false end
    if not (a.position and b.position) then return false end
    return a.position.x == b.position.x and a.position.y == b.position.y
  end

  local function same_robot_material(a, b)
    if not (a and b) then return false end
    if a.action ~= "MAT_TAKE" or b.action ~= "MAT_TAKE" then return false end
    if a.actor_type ~= "ROBOT" or b.actor_type ~= "ROBOT" then return false end
    if tostring(a.actor_name or "") ~= tostring(b.actor_name or "") then return false end
    if tostring(a.entity_name or "") ~= tostring(b.entity_name or "") then return false end
    if tostring(a.unit_number or "") ~= tostring(b.unit_number or "") then return false end
    if not same_pos(a, b) then return false end

    local a_item = extra_get(a.extra, "item")
    local b_item = extra_get(b.extra, "item")
    if tostring(a_item or "") ~= tostring(b_item or "") then return false end

    local a_src = extra_get(a.extra, "src")
    local b_src = extra_get(b.extra, "src")
    if tostring(a_src or "") ~= tostring(b_src or "") then return false end

    return true
  end

  local function extra_replace_cnt(extra, new_cnt)
    if type(extra) ~= "string" then return extra end
    -- Replace first occurrence of cnt=...
    local out, n = string.gsub(extra, "cnt=[^,]+", "cnt=" .. tostring(new_cnt), 1)
    return out
  end

  local shown = 0
  local idx = start_i
  while idx <= size and shown < page_lines do
    local ev = Change.peek_event(idx)

    if is_visible(ev) then
      if ev.actor_type == "ROBOT" and ev.action == "MAT_TAKE" then
        local ev2 = Change.peek_event(idx + 1)
        if is_visible(ev2) and same_robot_material(ev, ev2) then
          local c1 = tonumber(extra_get(ev.extra, "cnt") or "0") or 0
          local c2 = tonumber(extra_get(ev2.extra, "cnt") or "0") or 0
          local diff = c1 - c2

          -- If only the count changed, output the delta (current - next) in the CURRENT line.
          -- Do NOT skip the next line; it will become the next "current" line in the next iteration.
          if diff > 0 then
            local extra_new = extra_replace_cnt(ev.extra, diff)
            lines[#lines+1] = Change.format_event(ev, extra_new)
            shown = shown + 1
            idx = idx + 1
          else
            lines[#lines+1] = Change.format_event(ev)
            shown = shown + 1
            idx = idx + 1
          end
        else
          lines[#lines+1] = Change.format_event(ev)
          shown = shown + 1
          idx = idx + 1
        end
      else
        lines[#lines+1] = Change.format_event(ev)
        shown = shown + 1
        idx = idx + 1
      end
    else
      idx = idx + 1
    end
  end

  box.text = table.concat(lines, "\n")
end

return UI
