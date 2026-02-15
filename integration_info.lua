-- =========================================
-- Change Ledger (Factorio 2.0) 
-- Integration Info Module
-- Provides information about all available integrations and tracked actions
--
-- version 0.1.0 first try
-- version 0.2.0 first opertional Version
--
-- =========================================

local IntegrationInfo = {}
IntegrationInfo.version = "0.2.0"

-- Get information about all loaded integrations
function IntegrationInfo.get_all_integrations()
  local integrations = {}
  
  -- Try to load each integration
  local integration_modules = {
    {name = "vanilla", module = "integrations.vanilla"},
    {name = "pickier_dollies", module = "integrations.pickier_dollies"},
    {name = "circuit_tracking", module = "integrations.circuit_tracking"}
  }
  
  for _, def in ipairs(integration_modules) do
    local success, mod = pcall(require, def.module)
    
    if success and mod then
      local info = {
        name = def.name,
        available = mod.is_available and mod.is_available() or false,
        enabled = true,
        actions = {}
      }
      
      -- Check if it's enabled (for optional modules)
      if mod.is_enabled then
        info.enabled = mod.is_enabled()
      end
      
      -- Get tracked actions
      if mod.get_tracked_actions then
        info.actions = mod.get_tracked_actions()
      end
      
      table.insert(integrations, info)
    end
  end
  
  return integrations
end

-- Print integration info to console/log
function IntegrationInfo.print_info(player)
  local integrations = IntegrationInfo.get_all_integrations()
  
  local output = {"[Change Ledger] Aktive Integrationen und erkannte Manipulationen:"}
  table.insert(output, "")
  
  for _, int in ipairs(integrations) do
    local status = "❌"
    if int.available and int.enabled then
      status = "✅"
    elseif int.available and not int.enabled then
      status = "⚠️"
    end
    
    local name_display = int.name:gsub("_", " "):upper()
    table.insert(output, status .. " " .. name_display)
    
    if int.available and int.enabled and #int.actions > 0 then
      for _, action in ipairs(int.actions) do
        table.insert(output, "   • " .. action)
      end
    elseif int.available and not int.enabled then
      table.insert(output, "   (Verfügbar aber deaktiviert)")
      for _, action in ipairs(int.actions) do
        table.insert(output, "   • " .. action)
      end
    elseif not int.available then
      table.insert(output, "   (Nicht verfügbar)")
    end
    
    table.insert(output, "")
  end
  
  -- Print to player if available
  if player then
    for _, line in ipairs(output) do
      player.print(line)
    end
  end
  
  -- Always log
  for _, line in ipairs(output) do
    log(line)
  end
end

-- Get formatted string for all tracked actions
function IntegrationInfo.get_summary()
  local integrations = IntegrationInfo.get_all_integrations()
  local total_actions = 0
  local active_integrations = 0
  
  for _, int in ipairs(integrations) do
    if int.available and int.enabled then
      active_integrations = active_integrations + 1
      total_actions = total_actions + #int.actions
    end
  end
  
  return string.format("%d Integrationen aktiv, %d Manipulations-Typen erkannt", 
    active_integrations, total_actions)
end

return IntegrationInfo
