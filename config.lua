-- =========================================
-- Change Ledger (Factorio 2.0) 
-- Central configuration and storage initialization for LogSim (constants, GUI IDs, defaults).
--
-- version 0.1.0 first try
-- version 0.2.0 first opertional Version
--
-- =========================================

local M = {}
M.version = "0.2.0"

-- GUI sizing: match the TX window sizing style
M.GUI_BUFFER_WIDTH  = 900
M.GUI_BUFFER_HEIGHT = 500
M.GUI_REFRESH_TICKS = 10
M.GUI_MAX_LINES = 22

-- Topbar
M.GUI_TOP_ROOT = "cl_top_root"
M.GUI_BTN_REC  = "cl_btn_rec"
M.GUI_BTN_LOG  = "cl_btn_log"
M.GUI_BTN_MORE = "cl_btn_more"

-- Change Viewer Window (TX-look clone)
M.GUI_CHG_FRAME     = "cl_chg_frame"
M.GUI_CHG_CLOSE     = "cl_chg_close"
M.GUI_CHG_BTN_HOME  = "cl_chg_home"
M.GUI_CHG_BTN_OLDER = "cl_chg_older"
M.GUI_CHG_BTN_NEWER = "cl_chg_newer"
M.GUI_CHG_BTN_END   = "cl_chg_end"
M.GUI_CHG_BTN_COPY  = "cl_chg_copy"
M.GUI_CHG_BTN_EXPORT= "cl_chg_export"
M.GUI_CHG_BTN_HIDE  = "cl_chg_hide"
M.GUI_CHG_BTN_RESET = "cl_chg_reset"
M.GUI_CHG_BOX       = "cl_chg_box"

-- Export Dialog
M.GUI_CHG_EXPORT_FRAME    = "cl_chg_export_frame"
M.GUI_CHG_EXPORT_FILENAME = "cl_chg_export_filename"
M.GUI_CHG_BTN_EXPORT_CSV  = "cl_chg_export_csv"
M.GUI_CHG_BTN_EXPORT_JSON = "cl_chg_export_json"
M.GUI_CHG_EXPORT_CLOSE    = "cl_chg_export_close"

-- Reset Dialog
M.GUI_CHG_RESET_FRAME  = "cl_chg_reset_frame"
M.GUI_CHG_RESET_OK     = "cl_chg_reset_ok"
M.GUI_CHG_RESET_CANCEL = "cl_chg_reset_cancel"

-- Simple defaults for Change ringbuffer
M.CHG_MAX_EVENTS = 50000

-- Locale keys (DE/EN)
M.L = {
  top = {
    rec_tooltip  = {"change_ledger.rec_tooltip"},
    log_tooltip  = {"change_ledger.log_tooltip"},
    more_tooltip = {"change_ledger.more_tooltip"},
  },
  chg = {
    title = {"change_ledger.chg_title"},
    home_tt  = {"change_ledger.chg_home_tooltip"},
    older_tt = {"change_ledger.chg_page_older_tooltip"},
    newer_tt = {"change_ledger.chg_page_newer_tooltip"},
    end_tt   = {"change_ledger.chg_end_tooltip"},
    copy     = {"change_ledger.chg_copy"},
    export   = {"change_ledger.export"},
    export_tt= {"change_ledger.export_tt"},
    reset    = {"change_ledger.reset"},
    reset_tt = {"change_ledger.reset_tt"},
    hide     = {"change_ledger.chg_hide"},

    filter_player = {"change_ledger.filter_player"},
    filter_robot = {"change_ledger.filter_robot"},
    filter_ghost = {"change_ledger.filter_ghost"},
    filter_other = {"change_ledger.filter_other"},
  },
  export = {
    title = {"change_ledger.export_title"},
    info = {"change_ledger.export_info"},
    filename_label = {"change_ledger.export_filename"},
    format_label = {"change_ledger.export_format"},
    csv = {"change_ledger.export_csv"},
    csv_tooltip = {"change_ledger.export_csv_tooltip"},
    csv_desc = {"change_ledger.export_csv_desc"},
    json = {"change_ledger.export_json"},
    json_tooltip = {"change_ledger.export_json_tooltip"},
    json_desc = {"change_ledger.export_json_desc"},
    cancel = {"change_ledger.export_cancel"},
  },
  reset = {
    title = {"change_ledger.reset_title"},
    question = {"change_ledger.reset_question"},
    warning = {"change_ledger.reset_warning"},
    cancel = {"change_ledger.reset_cancel"},
    confirm = {"change_ledger.reset_confirm"},
  }
}

-- Script-generierte Aktionen
-- NUR HIER erweitern
M.SCRIPT_ACTION_LIST = {
  "REC_START",
  "REC_STOP",
  "MARK",
}

-- Abgeleitete Lookup-Tabellen
M.SCRIPT_ACTIONS = {}
M.SCRIPT_ACTION_SET = {}

for _, act in ipairs(M.SCRIPT_ACTION_LIST) do
  M.SCRIPT_ACTIONS[act] = act
  M.SCRIPT_ACTION_SET[act] = true
end


function M.ensure_storage_defaults()
  -- Factorio 2.x persistent state
  storage.cl = storage.cl or {}
  local cl = storage.cl

  if cl.recording == nil then cl.recording = false end

  -- Recording session id (increments on REC_START)
  cl.chg_session_id = tonumber(cl.chg_session_id) or 0

  cl.chg_events = cl.chg_events or {}
  cl.chg_max_events = tonumber(cl.chg_max_events) or M.CHG_MAX_EVENTS
  cl.chg_seq   = tonumber(cl.chg_seq)   or 0
  cl.chg_head  = tonumber(cl.chg_head)  or 1
  cl.chg_size  = tonumber(cl.chg_size)  or 0
  cl.chg_write = tonumber(cl.chg_write) or 1

  cl.viewer = cl.viewer or {}
end

return M
