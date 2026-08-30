-- OctoTweaks
-- Core bootstrap for WoW 1.12 / OctoWoW.

OctoTweaks = OctoTweaks or {}
local OT = OctoTweaks

OT.name = "OctoTweaks"
OT.version = "0.1.0-dev"
OT.modules = OT.modules or {}
OT.moduleOrder = OT.moduleOrder or {}
OT.runtime = OT.runtime or {}
OT.initialized = false

function OT:Print(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffOctoTweaks|r: " .. tostring(message))
  end
end

function OT:Debug(message)
  if OctoTweaksDB and OctoTweaksDB.debug then
    self:Print("|cffaaaaaa[debug]|r " .. tostring(message))
  end
end

function OT:EnsureSavedVariables()
  if not OctoTweaksDB then
    OctoTweaksDB = {}
  end

  if not OctoTweaksDB.modules then
    OctoTweaksDB.modules = {}
  end

  if OctoTweaksDB.debug == nil then
    OctoTweaksDB.debug = false
  end
end

function OT:Initialize()
  if self.initialized then
    return
  end

  self:EnsureSavedVariables()
  self.initialized = true

  if self.TryEnableAllModules then
    self:TryEnableAllModules("initialize")
  end
end

OT.eventFrame = OT.eventFrame or CreateFrame("Frame", "OctoTweaksEventFrame")
OT.eventFrame:RegisterEvent("VARIABLES_LOADED")
OT.eventFrame:RegisterEvent("ADDON_LOADED")
OT.eventFrame:RegisterEvent("PLAYER_LOGIN")

OT.eventFrame:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    OT:Initialize()
    return
  end

  if event == "ADDON_LOADED" then
    if OT.initialized and OT.TryEnableAllModules then
      OT:TryEnableAllModules("addon_loaded:" .. tostring(arg1))
    end
    return
  end

  if event == "PLAYER_LOGIN" then
    OT:Initialize()
    if OT.TryEnableAllModules then
      OT:TryEnableAllModules("player_login")
    end
  end
end)
