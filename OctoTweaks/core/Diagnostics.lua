-- Slash commands and compact runtime diagnostics.

local OT = OctoTweaks

local function printHelp()
  OT:Print("Commands: /ot status, /ot modules, /ot debug on, /ot debug off")
end

local function printModules()
  local count = table.getn(OT.moduleOrder)
  local i

  if count == 0 then
    OT:Print("No modules registered.")
    return
  end

  for i = 1, count do
    local id = OT.moduleOrder[i]
    local state = OT:GetModuleState(id) or {}
    OT:Print(id .. " = " .. tostring(state.status or "UNKNOWN") .. " (" .. tostring(state.reason or "no reason") .. ")")
  end
end

local function printStatus()
  OT:Print("version " .. OT.version)
  printModules()
end

SLASH_OCTOTWEAKS1 = "/ot"
SLASH_OCTOTWEAKS2 = "/octotweaks"
SlashCmdList["OCTOTWEAKS"] = function(msg)
  msg = string.lower(msg or "")

  if msg == "" or msg == "help" then
    printHelp()
    return
  end

  if msg == "status" or msg == "modules" then
    printStatus()
    return
  end

  if msg == "debug on" then
    OT:EnsureSavedVariables()
    OctoTweaksDB.debug = true
    OT:Print("debug enabled")
    return
  end

  if msg == "debug off" then
    OT:EnsureSavedVariables()
    OctoTweaksDB.debug = false
    OT:Print("debug disabled")
    return
  end

  printHelp()
end
