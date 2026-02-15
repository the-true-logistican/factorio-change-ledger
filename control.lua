-- =========================================
-- Change Ledger (Factorio 2.0) 
-- Main runtime controller: wires events, ticks, hotkeys and GUI actions together.
--
-- version 0.1.0 first try
-- version 0.2.0 first opertional Version
--
-- =========================================

local M  = require("config")
local UI = require("ui")
local Change = require("change")
local IntegrationInfo = require("integration_info")

storage = storage or script.storage

-- --- Integrations / event registry -------------------------------------------

local Registry = require("event_registry")
local Vanilla = require("integrations.vanilla")
local PickierDollies = require("integrations.pickier_dollies")
local CircuitTracking = require("integrations.circuit_tracking")

local function bind_integrations()
  log("[Change Ledger] bind_integrations() wird aufgerufen")
  local reg = Registry.new()

  -- Vanilla is always available.
  if Vanilla and Vanilla.is_available() then
    Vanilla.register(reg)
  end

  -- Pickier Dollies integration (if mod is loaded)
  if PickierDollies and PickierDollies.is_available() then
    PickierDollies.register(reg)
  end
  
  -- Circuit Change Tracking (optional, disabled by default)
  if CircuitTracking and CircuitTracking.is_available() and CircuitTracking.is_enabled() then
    CircuitTracking.register(reg)
  end

  reg:bind()
  log("[Change Ledger] Alle Integrationen gebunden")
  
  -- Print integration info to log
  IntegrationInfo.print_info(nil)
end


local function should_record()
  M.ensure_storage_defaults()
  return storage.cl.recording == true
end

local function rebuild_all_players()
  for _, p in pairs(game.players) do
    UI.build_topbar(p)
  end
end

script.on_init(function()
  log("[Change Ledger] on_init() aufgerufen")
  storage = storage or script.storage
  M.ensure_storage_defaults()
  rebuild_all_players()
  bind_integrations()  -- WICHTIG: Hier registrieren!
  
  -- Nachricht an alle Spieler
  for _, p in pairs(game.players) do
    p.print("[Change Ledger] Mod initialisiert", {r=0.3, g=1, b=0.3})
    if remote and remote.interfaces and remote.interfaces['PickerDollies'] then
      p.print("[Change Ledger] Pickier Dollies Integration aktiviert", {r=0.3, g=1, b=0.3})
    end
    
    -- Show summary
    local summary = IntegrationInfo.get_summary()
    p.print("[Change Ledger] " .. summary, {r=0.5, g=0.8, b=1})
  end
  
  log("[Change Ledger] on_init() abgeschlossen")
end)

script.on_load(function()
  log("[Change Ledger] on_load() aufgerufen")
  bind_integrations()  -- WICHTIG: Auch bei on_load registrieren!
  log("[Change Ledger] on_load() abgeschlossen")
end)

script.on_configuration_changed(function(_)
  storage = storage or script.storage
  M.ensure_storage_defaults()
  rebuild_all_players()
end)

script.on_event(defines.events.on_player_created, function(e)
  local p = game.get_player(e.player_index)
  if p then UI.build_topbar(p) end
end)

script.on_event(defines.events.on_gui_click, function(e)
  local p = game.get_player(e.player_index)
  if not p then return end
  local el = e.element
  if not (el and el.valid) then return end

  -- shorthand: script actions from config
  local SA = M.SCRIPT_ACTIONS

  -- Topbar
  if el.name == M.GUI_BTN_REC then
    M.ensure_storage_defaults()
    local cl = storage.cl

    -- IMPORTANT: create REC_START/REC_STOP first, then toggle
    -- so the session bracket is guaranteed to exist in the log.
    if cl.recording then
      Change.push_event(Change.make_rec_event(p, SA.REC_STOP))
      cl.recording = false
    else
      cl.chg_session_id = (tonumber(cl.chg_session_id) or 0) + 1
      Change.push_event(Change.make_rec_event(p, SA.REC_START))
      cl.recording = true
    end

    UI.build_topbar(p)
    if p.gui.screen[M.GUI_CHG_FRAME] then
      UI.refresh_chg_box(p)
    end
    return
  end

  if el.name == M.GUI_BTN_LOG then
    if p.gui.screen[M.GUI_CHG_FRAME] then
      UI.close_chg_gui(p)
    else
      UI.show_chg_gui(p)
    end
    return
  end

  if el.name == M.GUI_BTN_MORE then
    -- MARK: insert a milestone marker into the change log (SCRIPT event)
    if should_record() then
      -- make_mark_event should already use SA.MARK internally; this keeps control.lua clean too.
      Change.push_event(Change.make_mark_event(p))
      if p.gui.screen[M.GUI_CHG_FRAME] then
        UI.refresh_chg_box(p)
      end
    else
      p.print("[change_ledger] MARK ignored (recording is OFF)")
    end
    return
  end

  -- CHG window close/hide
  if el.name == M.GUI_CHG_CLOSE or el.name == M.GUI_CHG_BTN_HIDE then
    UI.close_chg_gui(p)
    return
  end

  -- Paging buttons (TX-like)
  if el.name == M.GUI_CHG_BTN_HOME  then Change.viewer_home(p.index);  UI.refresh_chg_box(p); return end
  if el.name == M.GUI_CHG_BTN_END   then Change.viewer_end(p.index);   UI.refresh_chg_box(p); return end
  if el.name == M.GUI_CHG_BTN_OLDER then Change.viewer_page_older(p.index, M.GUI_MAX_LINES); UI.refresh_chg_box(p); return end
  if el.name == M.GUI_CHG_BTN_NEWER then Change.viewer_page_newer(p.index, M.GUI_MAX_LINES); UI.refresh_chg_box(p); return end

  -- COPY: Select all text in the change viewer
  if el.name == M.GUI_CHG_BTN_COPY then
    local frame = p.gui.screen[M.GUI_CHG_FRAME]
    if frame and frame.valid then
      local box = frame[M.GUI_CHG_BOX]
      if box and box.valid then
        box.focus()
        box.select_all()
      end
    end
    return
  end

  -- EXPORT: Show export dialog
  if el.name == M.GUI_CHG_BTN_EXPORT then
    UI.show_export_dialog(p)
    return
  end

  -- RESET: Show reset confirmation dialog
  if el.name == M.GUI_CHG_BTN_RESET then
    UI.show_reset_dialog(p)
    return
  end

  -- Export Dialog buttons
  if el.name == M.GUI_CHG_EXPORT_CLOSE then
    UI.close_export_dialog(p)
    return
  end

  if el.name == M.GUI_CHG_BTN_EXPORT_CSV then
    local frame = p.gui.screen[M.GUI_CHG_EXPORT_FRAME]
    if frame and frame.valid then
      local filename_field = frame[M.GUI_CHG_EXPORT_FILENAME]
      local filename = (filename_field and filename_field.valid) and filename_field.text or "change_ledger_export"
      
      -- Generate CSV content
      local csv_lines = {}
      table.insert(csv_lines, "id,tick,session,action,actor_type,actor_name,actor_index,surface,force,entity_name,unit_number,pos_x,pos_y,dir_before,dir_after,extra")
      
      local size = Change.size()
      for i = 1, size do
        local ev = Change.peek_event(i)
        if ev then
          local pos_x = (ev.position and ev.position.x) or ""
          local pos_y = (ev.position and ev.position.y) or ""
          table.insert(csv_lines, string.format(
            "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
            tostring(ev.id or ""),
            tostring(ev.tick or ""),
            tostring(ev.session or ""),
            tostring(ev.action or ""),
            tostring(ev.actor_type or ""),
            tostring(ev.actor_name or ""),
            tostring(ev.actor_index or ""),
            tostring(ev.surface or ""),
            tostring(ev.force or ""),
            tostring(ev.entity_name or ""),
            tostring(ev.unit_number or ""),
            tostring(pos_x),
            tostring(pos_y),
            tostring(ev.dir_before or ""),
            tostring(ev.dir_after or ""),
            tostring(ev.extra or "")
          ))
        end
      end
      
      local csv_content = table.concat(csv_lines, "\n")
      game.write_file(filename .. ".csv", csv_content, false, p.index)
      p.print("[Change Ledger] CSV exported: " .. filename .. ".csv", {r=0.3, g=1, b=0.3})
      UI.close_export_dialog(p)
    end
    return
  end

  if el.name == M.GUI_CHG_BTN_EXPORT_JSON then
    local frame = p.gui.screen[M.GUI_CHG_EXPORT_FRAME]
    if frame and frame.valid then
      local filename_field = frame[M.GUI_CHG_EXPORT_FILENAME]
      local filename = (filename_field and filename_field.valid) and filename_field.text or "change_ledger_export"
      
      -- Generate JSON content
      local json_events = {}
      local size = Change.size()
      for i = 1, size do
        local ev = Change.peek_event(i)
        if ev then
          local ev_json = string.format(
            '{"id":%s,"tick":%s,"session":%s,"action":"%s","actor_type":"%s","actor_name":"%s","actor_index":%s,"surface":"%s","force":"%s","entity_name":"%s","unit_number":"%s","position":%s,"dir_before":%s,"dir_after":%s,"extra":"%s"}',
            tostring(ev.id or 0),
            tostring(ev.tick or 0),
            tostring(ev.session or 0),
            tostring(ev.action or ""):gsub('"', '\\"'),
            tostring(ev.actor_type or ""):gsub('"', '\\"'),
            tostring(ev.actor_name or ""):gsub('"', '\\"'),
            tostring(ev.actor_index or 0),
            tostring(ev.surface or ""):gsub('"', '\\"'),
            tostring(ev.force or ""):gsub('"', '\\"'),
            tostring(ev.entity_name or ""):gsub('"', '\\"'),
            tostring(ev.unit_number or ""):gsub('"', '\\"'),
            (ev.position and string.format('{"x":%s,"y":%s}', tostring(ev.position.x or 0), tostring(ev.position.y or 0))) or "null",
            (ev.dir_before and tostring(ev.dir_before)) or "null",
            (ev.dir_after and tostring(ev.dir_after)) or "null",
            tostring(ev.extra or ""):gsub('"', '\\"')
          )
          table.insert(json_events, ev_json)
        end
      end
      
      local json_content = "[\n  " .. table.concat(json_events, ",\n  ") .. "\n]"
      game.write_file(filename .. ".json", json_content, false, p.index)
      p.print("[Change Ledger] JSON exported: " .. filename .. ".json", {r=0.3, g=1, b=0.3})
      UI.close_export_dialog(p)
    end
    return
  end

  -- Reset Dialog buttons
  if el.name == M.GUI_CHG_RESET_CANCEL then
    UI.close_reset_dialog(p)
    return
  end

  if el.name == M.GUI_CHG_RESET_OK then
    -- Perform reset
    M.ensure_storage_defaults()
    local cl = storage.cl
    
    -- Clear all events
    cl.chg_events = {}
    cl.chg_seq = 0
    cl.chg_head = 1
    cl.chg_size = 0
    cl.chg_write = 1
    
    -- Increment session (new session starts)
    cl.chg_session_id = (tonumber(cl.chg_session_id) or 0) + 1
    
    -- Reset viewer state for all players
    cl.viewer = {}
    
    -- Close dialog and refresh viewer
    UI.close_reset_dialog(p)
    if p.gui.screen[M.GUI_CHG_FRAME] then
      UI.refresh_chg_box(p)
    end
    
    p.print("[Change Ledger] Log cleared. New session: " .. tostring(cl.chg_session_id), {r=1, g=0.8, b=0.3})
    
    -- If recording is on, log the reset event
    if cl.recording then
      Change.push_event(Change.make_rec_event(p, SA.REC_START))
    end
    
    return
  end

  -- No longer needed: COPY / EXPORT handled above
  -- Legacy fallback removed
end)

-- React to checkbox toggles in the Change Viewer.
-- This keeps the text box in sync without requiring paging/button clicks.
script.on_event(defines.events.on_gui_checked_state_changed, function(e)
  local p = game.get_player(e.player_index)
  if not p then return end
  local el = e.element
  if not (el and el.valid) then return end

  if el.name == "cl_chg_chk_player"
    or el.name == "cl_chg_chk_robot"
    or el.name == "cl_chg_chk_ghost"
    or el.name == "cl_chg_chk_other" then
    if p.gui.screen[M.GUI_CHG_FRAME] then
      UI.refresh_chg_box(p)
    end
  end
end)

-- Chat command to show integration info
commands.add_command("cl-info", "Zeigt alle aktiven Change Ledger Integrationen und erkannte Manipulationen", function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  
  IntegrationInfo.print_info(player)
end)

-- Chat command to show short summary
commands.add_command("cl-summary", "Zeigt eine kurze Zusammenfassung der Change Ledger Integrationen", function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  
  local summary = IntegrationInfo.get_summary()
  player.print("[Change Ledger] " .. summary, {r=0.5, g=0.8, b=1})
end)

