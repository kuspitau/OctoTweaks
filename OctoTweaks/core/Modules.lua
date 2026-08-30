-- Module registry and lifecycle.

local OT = OctoTweaks

local function setState(id, status, reason)
  OT.runtime[id] = OT.runtime[id] or {}
  OT.runtime[id].status = status
  OT.runtime[id].reason = reason
end

function OT:RegisterModule(module)
  if not module or not module.id then
    self:Print("Refused module registration without an id.")
    return false
  end

  if self.modules[module.id] then
    self:Print("Duplicate module id refused: " .. module.id)
    return false
  end

  self.modules[module.id] = module
  table.insert(self.moduleOrder, module.id)
  setState(module.id, "REGISTERED", "not evaluated yet")
  return true
end

function OT:IsModuleEnabledByConfig(module)
  self:EnsureSavedVariables()

  local explicit = OctoTweaksDB.modules[module.id]
  if explicit ~= nil then
    return explicit
  end

  if module.defaultEnabled == nil then
    return true
  end

  return module.defaultEnabled
end

function OT:TryEnableModule(id, trigger)
  local module = self.modules[id]
  if not module then
    return false
  end

  local runtime = self.runtime[id] or {}
  self.runtime[id] = runtime

  if runtime.status == "ENABLED" then
    return true
  end

  if not self:IsModuleEnabledByConfig(module) then
    setState(id, "DISABLED", "disabled by configuration")
    return false
  end

  if module.probe then
    local ok, compatible, reason = pcall(module.probe, module)
    if not ok then
      setState(id, "ERROR", "probe error: " .. tostring(compatible))
      return false
    end

    if not compatible then
      setState(id, "WAITING", reason or "compatibility probe not satisfied")
      return false
    end
  end

  if not module.enable then
    setState(id, "ERROR", "module has no enable function")
    return false
  end

  local ok, enabled, reason = pcall(module.enable, module)
  if not ok then
    setState(id, "ERROR", "enable error: " .. tostring(enabled))
    return false
  end

  if enabled == false then
    setState(id, "ERROR", reason or "module refused activation")
    return false
  end

  setState(id, "ENABLED", reason or ("enabled by " .. tostring(trigger)))
  self:Debug("enabled " .. id)
  return true
end

function OT:TryEnableAllModules(trigger)
  local count = table.getn(self.moduleOrder)
  local i

  for i = 1, count do
    self:TryEnableModule(self.moduleOrder[i], trigger)
  end
end

function OT:GetModuleState(id)
  return self.runtime[id]
end
