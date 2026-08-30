-- Small compatibility helpers. Keep this file conservative for Lua 5.0 / WoW 1.12.

local OT = OctoTweaks

function OT:GetGlobal(name)
  if getglobal then
    return getglobal(name)
  end

  if _G then
    return _G[name]
  end

  return nil
end

function OT:GetAddonVersion(addonName)
  if not GetAddOnMetadata then
    return nil
  end

  return GetAddOnMetadata(addonName, "Version")
end

function OT:IsAddonLoaded(addonName)
  if IsAddOnLoaded then
    return IsAddOnLoaded(addonName)
  end

  return self:GetGlobal(addonName) ~= nil
end
