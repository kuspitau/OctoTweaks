-- Aegis UI extension adapter.
--
-- This file is part of aegis.integration. It intentionally owns every direct
-- dependency on Aegis presentation internals used by OctoTweaks. Higher-level
-- modules register a view through this adapter and never touch AegisExchange.ui.
--
-- Exact private-UI sources audited for this extension seam:
-- Aegis: Exchange 1.20.2, upstream commit
-- 70f648492607ca1aec6c3df2da42deed21d09c9d.
-- Aegis: Exchange 1.53.29, upstream main commit
-- 924ce71fee75a61bec08983243385a53ee71ddbc.

local OT = OctoTweaks
local adapter = OT.Aegis

if not adapter then
  return
end

adapter.uiExtension = adapter.uiExtension or {
  key = nil,
  spec = nil,
  installed = false,
  attached = false,
  disabled = false,
  reason = "not installed",
  lastError = nil,
  tab = nil,
  panel = nil,
  originalOpenWindow = nil,
  originalSelectSubTab = nil,
  hostOriginalHeight = nil,
  hostForcedHeight = nil,
  closeDriver = nil,
}

local state = adapter.uiExtension

local UI_TESTED_VERSION = "1.53.29"
local UI_AUDITS = {
  ["1.20.2"] = "70f648492607ca1aec6c3df2da42deed21d09c9d",
  ["1.53.29"] = "924ce71fee75a61bec08983243385a53ee71ddbc",
}

local function uiAuditCommit(version)
  if version == nil then return nil end
  return UI_AUDITS[tostring(version)]
end

local function auditedVersionsText()
  return "1.20.2 and 1.53.29"
end

local function uiFailure(reason)
  state.disabled = true
  state.reason = reason
  state.lastError = reason
  return false, reason
end

local function extensionUI()
  local A = adapter:GetAegis()
  if not A or type(A.ui) ~= "table" then return nil end
  return A.ui
end

function adapter:ProbeWorkbenchUIHost()
  local A = self:GetAegis()
  if type(A) ~= "table" then
    return false, "AegisExchange global not found"
  end

  local version = self:GetVersion()
  local auditCommit = uiAuditCommit(version)
  if not auditCommit then
    return false, "Aegis private UI extension is source-audited only for "
      .. auditedVersionsText() .. "; detected " .. tostring(version or "unknown")
  end

  local ui = A.ui
  if type(ui) ~= "table" then
    return false, "AegisExchange.ui not found"
  end
  if type(ui.BuildWindow) ~= "function" then
    return false, "Aegis ui.BuildWindow missing"
  end
  if type(ui.OpenWindow) ~= "function" then
    return false, "Aegis ui.OpenWindow missing"
  end
  if type(ui.SelectSubTab) ~= "function" then
    return false, "Aegis ui.SelectSubTab missing"
  end

  return true, "Aegis " .. tostring(version)
    .. " extensible sub-tab host detected (audit "
    .. string.sub(auditCommit, 1, 8) .. ")"
end

local function repaintUnselectedTab(tab)
  if not tab then return end
  local target = tab
  if tab.backdrop and tab.backdrop.SetBackdropColor then
    target = tab.backdrop
  end
  if target.SetBackdropColor then
    target:SetBackdropColor(0.21, 0.17, 0.12, 1)
  end
  if target.SetBackdropBorderColor then
    target:SetBackdropBorderColor(0.30, 0.26, 0.16)
  end
  if tab.label and tab.label.SetTextColor then
    tab.label:SetTextColor(0.72, 0.58, 0.32)
  end
end

local function createExtensionTab(ui, key, label)
  local anchor = ui.subtabs and ui.subtabs.Scan
  if not anchor then
    return nil, "Aegis Scan/Aegis sub-tab anchor missing"
  end

  local tab = CreateFrame("Button", "OctoTweaksAegisSubTab" .. key, ui.frame)
  tab.aegisNoSkin = true
  tab:SetHeight(24)
  tab:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  tab.aegisFont = "GameFontNormalSmall"

  local fs = tab:CreateFontString(nil, "OVERLAY", tab.aegisFont)
  fs:SetPoint("CENTER", tab, "CENTER", 0, 0)
  fs:SetText(label)
  tab.label = fs
  tab:SetWidth(fs:GetStringWidth() + 30)
  tab:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
  tab:SetScript("OnClick", function()
    ui.SelectSubTab(key)
  end)
  repaintUnselectedTab(tab)
  return tab
end

local function createExtensionPanel(ui, key)
  if not ui.content or not ui.panels or not ui.panels.Buy then
    return nil, "Aegis content/panel structure missing"
  end
  local panel = CreateFrame("Frame", "OctoTweaksAegisPanel" .. key, ui.content)
  panel:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 6, -6)
  panel:SetPoint("BOTTOMRIGHT", ui.content, "BOTTOMRIGHT", -6, 6)
  panel:Hide()
  return panel
end

function adapter:EnsureUIExtensionAttached()
  if not state.installed then
    return false, "Aegis UI extension is not installed"
  end
  if state.disabled then
    return false, state.reason or "Aegis UI extension disabled"
  end
  if state.attached then
    return true, "Aegis Workbench sub-tab attached"
  end

  local okHost, hostReason = self:ProbeWorkbenchUIHost()
  if not okHost then return uiFailure(hostReason) end

  local ui = extensionUI()
  if not ui or not ui.frame then
    return false, "Aegis window has not been built yet"
  end
  if type(ui.subtabs) ~= "table" or type(ui.panels) ~= "table" or not ui.content then
    return uiFailure("Aegis audited sub-tab/panel tables are not present after BuildWindow")
  end

  local key = state.key
  if ui.subtabs[key] or ui.panels[key] then
    return uiFailure("Aegis UI extension key collision: " .. tostring(key))
  end

  local tab, tabReason = createExtensionTab(ui, key, state.spec.label or "Workbench")
  if not tab then return uiFailure(tabReason) end
  local panel, panelReason = createExtensionPanel(ui, key)
  if not panel then
    tab:Hide()
    return uiFailure(panelReason)
  end

  ui.subtabs[key] = tab
  ui.panels[key] = panel
  state.tab = tab
  state.panel = panel
  state.attached = true
  state.reason = "Aegis " .. tostring(self:GetVersion() or "unknown") .. " Workbench sub-tab attached"

  if state.spec.onAttach then
    local ok, err = pcall(state.spec.onAttach, panel, tab)
    if not ok then
      ui.subtabs[key] = nil
      ui.panels[key] = nil
      panel:Hide()
      tab:Hide()
      state.attached = false
      return uiFailure("Workbench onAttach error: " .. tostring(err))
    end
  end

  return true, state.reason
end

function adapter:AcquireWorkbenchHostHeight(minHeight)
  local ui = extensionUI()
  local frame = ui and ui.frame
  if not frame or not frame.GetHeight or not frame.SetHeight then
    return false, "Aegis host frame unavailable"
  end

  local wanted = tonumber(minHeight) or 0
  local current = tonumber(frame:GetHeight()) or 0
  if wanted <= 0 or current >= wanted then
    state.hostOriginalHeight = nil
    state.hostForcedHeight = nil
    return true, "Aegis host already tall enough"
  end

  state.hostOriginalHeight = current
  state.hostForcedHeight = wanted
  frame:SetHeight(wanted)
  return true, "Aegis host temporarily enlarged"
end

function adapter:ReleaseWorkbenchHostHeight()
  local ui = extensionUI()
  local frame = ui and ui.frame
  local original = state.hostOriginalHeight
  local forced = state.hostForcedHeight
  state.hostOriginalHeight = nil
  state.hostForcedHeight = nil

  if not frame or not original or not forced or not frame.GetHeight or not frame.SetHeight then
    return false, "no temporary Aegis host height to restore"
  end

  local current = tonumber(frame:GetHeight()) or 0
  -- Do not undo a resize the user performed while the Workbench was open.
  if math.abs(current - forced) <= 1 then
    frame:SetHeight(original)
    return true, "Aegis host height restored"
  end
  return true, "Aegis host height kept because it was resized while Workbench was open"
end

local function callBeforeHide()
  if state.spec and state.spec.beforeHide then
    local ok, err = pcall(state.spec.beforeHide)
    if not ok then
      state.lastError = "Workbench beforeHide error: " .. tostring(err)
    end
  end
  adapter:ReleaseWorkbenchHostHeight()
end

local function callBeforeShow()
  local minHeight = state.spec and state.spec.hostHeight or nil
  if minHeight then
    local ok, reason = adapter:AcquireWorkbenchHostHeight(minHeight)
    if not ok then return false, reason end
  end
  if state.spec and state.spec.beforeShow then
    local ok, err = pcall(state.spec.beforeShow, state.panel)
    if not ok then
      adapter:ReleaseWorkbenchHostHeight()
      return false, "Workbench beforeShow error: " .. tostring(err)
    end
  end
  return true
end

local function callAfterShow()
  if state.spec and state.spec.onShow then
    local ok, err = pcall(state.spec.onShow, state.panel, state.tab)
    if not ok then
      return false, "Workbench onShow error: " .. tostring(err)
    end
  end
  return true
end

local function installCloseDriver()
  if state.closeDriver then return end
  local f = CreateFrame("Frame", "OctoTweaksAegisWorkbenchUICloseDriver")
  f:RegisterEvent("AUCTION_HOUSE_CLOSED")
  f:SetScript("OnEvent", function()
    if state.spec and state.spec.beforeHide then
      local ok, err = pcall(state.spec.beforeHide)
      if not ok then state.lastError = "Workbench close cleanup error: " .. tostring(err) end
    end
    adapter:ReleaseWorkbenchHostHeight()
  end)
  state.closeDriver = f
end

function adapter:InstallUIExtension(spec)
  if state.installed then
    if state.key == spec.key then return true, state.reason end
    return false, "another Aegis UI extension is already installed"
  end
  if not spec or not spec.key then
    return false, "UI extension key missing"
  end

  local okHost, hostReason = self:ProbeWorkbenchUIHost()
  if not okHost then return false, hostReason end

  local ui = extensionUI()
  state.key = spec.key
  state.spec = spec
  state.installed = true
  state.disabled = false
  state.reason = "Aegis UI hook installed; waiting for window build"

  -- If Aegis already built its window, prove the exact structures now before
  -- altering its dispatcher. Otherwise attachment is deferred until OpenWindow
  -- has built them.
  if ui.frame then
    local attached, attachReason = self:EnsureUIExtensionAttached()
    if not attached then
      state.installed = false
      return false, attachReason
    end
  end

  state.originalSelectSubTab = ui.SelectSubTab
  ui.SelectSubTab = function(name)
    local previous = ui.selectedSubTab

    if previous == state.key and name ~= state.key then
      callBeforeHide()
    end

    if name == state.key then
      local attached, attachReason = adapter:EnsureUIExtensionAttached()
      if not attached then
        state.lastError = attachReason
        return state.originalSelectSubTab("Buy")
      end
      local ready, readyReason = callBeforeShow()
      if not ready then
        state.lastError = readyReason
        return state.originalSelectSubTab("Buy")
      end
    end

    local result = state.originalSelectSubTab(name)

    if name == state.key then
      local shown, showReason = callAfterShow()
      if not shown then
        state.lastError = showReason
        callBeforeHide()
        state.originalSelectSubTab("Buy")
      end
    end
    return result
  end

  state.originalOpenWindow = ui.OpenWindow
  ui.OpenWindow = function()
    local result = state.originalOpenWindow()
    if not state.disabled then
      local attached, attachReason = adapter:EnsureUIExtensionAttached()
      if not attached and ui.frame then
        state.lastError = attachReason
      end
    end
    return result
  end

  installCloseDriver()
  state.reason = state.attached
    and ("Aegis " .. tostring(self:GetVersion() or "unknown") .. " Workbench sub-tab attached")
    or "Aegis UI hook installed; attachment deferred until first Aegis window build"
  return true, state.reason
end

function adapter:SelectUIExtension(key)
  if not state.installed or state.disabled or state.key ~= key then
    return false, state.reason or "Aegis UI extension unavailable"
  end
  local ui = extensionUI()
  if not ui or not ui.frame or not ui.frame.IsVisible or not ui.frame:IsVisible() then
    return false, "Aegis window is not visible"
  end
  local attached, reason = self:EnsureUIExtensionAttached()
  if not attached then return false, reason end
  ui.SelectSubTab(key)
  if ui.selectedSubTab ~= key then
    return false, state.lastError or "Aegis refused Workbench sub-tab selection"
  end
  return true, "Workbench sub-tab selected"
end

function adapter:SelectAegisSubTab(name)
  local ui = extensionUI()
  if not ui or not ui.frame or not ui.frame.IsVisible or not ui.frame:IsVisible() then
    return false, "Aegis window is not visible"
  end
  if type(ui.SelectSubTab) ~= "function" then
    return false, "Aegis ui.SelectSubTab unavailable"
  end
  if type(ui.panels) ~= "table" or not ui.panels[name] then
    return false, "Aegis sub-tab unavailable: " .. tostring(name)
  end
  ui.SelectSubTab(name)
  return ui.selectedSubTab == name, "Aegis sub-tab selected: " .. tostring(name)
end

function adapter:IsUIExtensionActive(key)
  local ui = extensionUI()
  return state.installed and state.attached and not state.disabled
    and state.key == key and ui and ui.selectedSubTab == key
    and ui.frame and ui.frame.IsVisible and ui.frame:IsVisible() and true or false
end

function adapter:GetUIExtensionDiagnostics()
  local version = self:GetVersion()
  return {
    version = version,
    auditedVersion = UI_TESTED_VERSION,
    auditCommit = UI_AUDITS[UI_TESTED_VERSION],
    detectedAuditCommit = uiAuditCommit(version),
    installed = state.installed,
    attached = state.attached,
    active = self:IsUIExtensionActive(state.key),
    disabled = state.disabled,
    reason = state.reason,
    lastError = state.lastError,
  }
end
