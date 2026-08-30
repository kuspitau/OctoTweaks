--[[
Module: pfui.libpredict_fix
Category: compatibility
Target: pfUI
Tested against: pfUI 5.5.4 on OctoWoW/SuperWoW

Purpose:
Guard pfUI's pfPredictionSender UNIT_SPELLCAST_START handler when
UnitCastingInfo("player") exposes incomplete cast timestamps.

The patch is external: pfUI source files are not modified.
]]

local OT = OctoTweaks

local module = {
  id = "pfui.libpredict_fix",
  category = "compatibility",
  target = "pfUI",
  defaultEnabled = true,
  testedVersion = "5.5.4",
  sender = nil,
  originalOnEvent = nil,
  wrapperOnEvent = nil,
}

function module:probe()
  if not UnitCastingInfo then
    return false, "UnitCastingInfo is unavailable"
  end

  local sender = OT:GetGlobal("pfPredictionSender")
  if not sender then
    return false, "pfPredictionSender not found; pfUI/libpredict may not be loaded"
  end

  if not sender.GetScript or not sender.SetScript then
    return false, "pfPredictionSender does not expose script accessors"
  end

  local original = sender:GetScript("OnEvent")
  if not original then
    return false, "pfPredictionSender has no OnEvent handler"
  end

  return true, "pfUI libpredict structure detected"
end

function module:enable()
  local sender = OT:GetGlobal("pfPredictionSender")
  if not sender then
    return false, "pfPredictionSender disappeared before activation"
  end

  if sender.OctoTweaksLibPredictFixInstalled then
    self.sender = sender
    return true, "already installed"
  end

  local original = sender:GetScript("OnEvent")
  if not original then
    return false, "original OnEvent handler unavailable"
  end

  self.sender = sender
  self.originalOnEvent = original

  self.wrapperOnEvent = function()
    if event == "UNIT_SPELLCAST_START" and arg1 == "player" then
      local spellname, rank, displayName, icon, starttime, endtime = UnitCastingInfo("player")

      if type(starttime) ~= "number" or type(endtime) ~= "number" then
        OT:Debug("ignored incomplete UNIT_SPELLCAST_START from pfPredictionSender: " .. tostring(spellname))
        return
      end
    end

    return original()
  end

  sender:SetScript("OnEvent", self.wrapperOnEvent)
  sender.OctoTweaksLibPredictFixInstalled = true

  local version = OT:GetAddonVersion("pfUI")
  if version and version ~= self.testedVersion then
    OT:Print("pfui.libpredict_fix enabled on unvalidated pfUI version " .. tostring(version) .. " (tested: " .. self.testedVersion .. ")")
  end

  return true, "external guard installed"
end

OT:RegisterModule(module)
