--[[
Aegis UI multi-extension registry.

This file augments aegis.integration after UIAdapter.lua has established and
version-probed the private Aegis presentation seam. It replaces the original
single-extension registration helpers with a small registry so independent
OctoTweaks features can each own one Aegis sub-tab without touching Aegis
source files or each other's presentation code.

Private UI seam source-audited through UIAdapter.lua for Aegis 1.20.2 and
1.53.29 only. Unknown versions still fail closed through ProbeWorkbenchUIHost.
]]

local OT = OctoTweaks
local adapter = OT.Aegis

if not adapter then
  return
end

adapter.uiExtensions = adapter.uiExtensions or {}
adapter.uiExtensionOrder = adapter.uiExtensionOrder or {}
adapter.uiExtensionsHooked = adapter.uiExtensionsHooked or false
adapter.uiExtensionsHost = adapter.uiExtensionsHost or {
  activeKey = nil,
  originalHeight = nil,
  forcedHeight = nil,
}
adapter.uiExtensionsLastError = adapter.uiExtensionsLastError or nil
adapter.uiExtensionsCloseDriver = adapter.uiExtensionsCloseDriver or nil
adapter.uiExtensionsOriginalSelectSubTab = adapter.uiExtensionsOriginalSelectSubTab or nil
adapter.uiExtensionsOriginalOpenWindow = adapter.uiExtensionsOriginalOpenWindow or nil

local registry = adapter.uiExtensions
local order = adapter.uiExtensionOrder
local hostState = adapter.uiExtensionsHost

local function ui()
  local A = adapter:GetAegis()
  if type(A) ~= "table" or type(A.ui) ~= "table" then return nil end
  return A.ui
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

local function previousExtensionTab(key, aui)
  local previous = nil
  local i = 1
  while i <= table.getn(order) do
    local candidateKey = order[i]
    if candidateKey == key then break end
    local state = registry[candidateKey]
    if state and state.attached and state.tab then
      previous = state.tab
    end
    i = i + 1
  end
  if previous then return previous end
  return aui and aui.subtabs and aui.subtabs.Scan or nil
end

local function createExtensionTab(aui, state)
  local anchor = previousExtensionTab(state.key, aui)
  if not anchor then
    return nil, "Aegis Scan/Aegis sub-tab anchor missing"
  end

  local tab = CreateFrame("Button", "OctoTweaksAegisSubTab" .. state.key, aui.frame)
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
  fs:SetText(state.spec.label or state.key)
  tab.label = fs
  tab:SetWidth(fs:GetStringWidth() + 30)
  tab:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
  tab:SetScript("OnClick", function()
    aui.SelectSubTab(state.key)
  end)
  repaintUnselectedTab(tab)
  return tab
end

local function createExtensionPanel(aui, state)
  if not aui.content or type(aui.panels) ~= "table" or not aui.panels.Buy then
    return nil, "Aegis content/panel structure missing"
  end
  local panel = CreateFrame("Frame", "OctoTweaksAegisPanel" .. state.key, aui.content)
  panel:SetPoint("TOPLEFT", aui.content, "TOPLEFT", 6, -6)
  panel:SetPoint("BOTTOMRIGHT", aui.content, "BOTTOMRIGHT", -6, 6)
  panel:Hide()
  return panel
end

local function markFailure(state, reason)
  state.disabled = true
  state.reason = reason
  state.lastError = reason
  adapter.uiExtensionsLastError = reason
  return false, reason
end

function adapter:EnsureUIExtensionAttached(key)
  local state = registry[key]
  if not state then
    return false, "unknown Aegis UI extension: " .. tostring(key)
  end
  if state.disabled then
    return false, state.reason or "Aegis UI extension disabled"
  end
  if state.attached then
    return true, "Aegis UI extension attached: " .. tostring(key)
  end

  local okHost, hostReason = self:ProbeWorkbenchUIHost()
  if not okHost then return markFailure(state, hostReason) end

  local aui = ui()
  if not aui or not aui.frame then
    return false, "Aegis window has not been built yet"
  end
  if type(aui.subtabs) ~= "table" or type(aui.panels) ~= "table" or not aui.content then
    return markFailure(state, "Aegis audited sub-tab/panel tables are not present after BuildWindow")
  end
  if aui.subtabs[key] or aui.panels[key] then
    return markFailure(state, "Aegis UI extension key collision: " .. tostring(key))
  end

  local tab, tabReason = createExtensionTab(aui, state)
  if not tab then return markFailure(state, tabReason) end
  local panel, panelReason = createExtensionPanel(aui, state)
  if not panel then
    tab:Hide()
    return markFailure(state, panelReason)
  end

  aui.subtabs[key] = tab
  aui.panels[key] = panel
  state.tab = tab
  state.panel = panel
  state.attached = true
  state.reason = "Aegis " .. tostring(self:GetVersion() or "unknown")
    .. " sub-tab attached: " .. tostring(key)

  if state.spec.onAttach then
    local ok, err = pcall(state.spec.onAttach, panel, tab)
    if not ok then
      aui.subtabs[key] = nil
      aui.panels[key] = nil
      panel:Hide()
      tab:Hide()
      state.attached = false
      return markFailure(state, "Aegis UI extension onAttach error (" .. tostring(key) .. "): " .. tostring(err))
    end
  end

  return true, state.reason
end

function adapter:EnsureAllUIExtensionsAttached()
  local allOk = true
  local lastReason = "no UI extensions registered"
  local i = 1
  while i <= table.getn(order) do
    local key = order[i]
    local ok, reason = self:EnsureUIExtensionAttached(key)
    if not ok then
      allOk = false
      lastReason = reason
    else
      lastReason = reason
    end
    i = i + 1
  end
  return allOk, lastReason
end

local function acquireHost(state)
  if not state then return false, "UI extension state missing" end
  if hostState.activeKey == state.key then
    return true, "Aegis host already acquired"
  end

  local aui = ui()
  local frame = aui and aui.frame
  if not frame or not frame.GetHeight or not frame.SetHeight then
    return false, "Aegis host frame unavailable"
  end

  local wanted = tonumber(state.spec.hostHeight) or 0
  local current = tonumber(frame:GetHeight()) or 0
  hostState.activeKey = state.key
  hostState.originalHeight = nil
  hostState.forcedHeight = nil

  if wanted > 0 and current < wanted then
    hostState.originalHeight = current
    hostState.forcedHeight = wanted
    frame:SetHeight(wanted)
    return true, "Aegis host temporarily enlarged"
  end
  return true, "Aegis host already tall enough"
end

local function releaseHost(key)
  if not hostState.activeKey then
    return false, "no Aegis extension host height is active"
  end
  if key and hostState.activeKey ~= key then
    return false, "different Aegis extension owns host height"
  end

  local aui = ui()
  local frame = aui and aui.frame
  local original = hostState.originalHeight
  local forced = hostState.forcedHeight
  hostState.activeKey = nil
  hostState.originalHeight = nil
  hostState.forcedHeight = nil

  if not frame or not original or not forced or not frame.GetHeight or not frame.SetHeight then
    return true, "no temporary height to restore"
  end

  local current = tonumber(frame:GetHeight()) or 0
  if math.abs(current - forced) <= 1 then
    frame:SetHeight(original)
    return true, "Aegis host height restored"
  end
  return true, "Aegis host height kept because the user resized it"
end

-- Backward-compatible names retained for the existing Workbench integration.
function adapter:AcquireWorkbenchHostHeight(minHeight)
  local state = registry["OctoWorkbench"]
  if not state then
    state = { key = "OctoWorkbench", spec = { hostHeight = minHeight } }
  elseif minHeight then
    state.spec.hostHeight = minHeight
  end
  return acquireHost(state)
end

function adapter:ReleaseWorkbenchHostHeight()
  return releaseHost("OctoWorkbench")
end

local function callBeforeHide(state)
  if state and state.spec and state.spec.beforeHide then
    local ok, err = pcall(state.spec.beforeHide)
    if not ok then
      state.lastError = "beforeHide error: " .. tostring(err)
      adapter.uiExtensionsLastError = state.lastError
    end
  end
  if state then releaseHost(state.key) end
end

local function callBeforeShow(state)
  local okHeight, heightReason = acquireHost(state)
  if not okHeight then return false, heightReason end
  if state.spec and state.spec.beforeShow then
    local ok, err = pcall(state.spec.beforeShow, state.panel)
    if not ok then
      releaseHost(state.key)
      return false, "beforeShow error: " .. tostring(err)
    end
  end
  return true, "extension ready to show"
end

local function callAfterShow(state)
  if state.spec and state.spec.onShow then
    local ok, err = pcall(state.spec.onShow, state.panel, state.tab)
    if not ok then
      return false, "onShow error: " .. tostring(err)
    end
  end
  return true, "extension shown"
end

local function installCloseDriver()
  if adapter.uiExtensionsCloseDriver then return end
  local f = CreateFrame("Frame", "OctoTweaksAegisUIExtensionsCloseDriver")
  f:RegisterEvent("AUCTION_HOUSE_CLOSED")
  f:SetScript("OnEvent", function()
    local aui = ui()
    local key = aui and aui.selectedSubTab or hostState.activeKey
    local state = key and registry[key] or nil
    if state then callBeforeHide(state) else releaseHost(nil) end
  end)
  adapter.uiExtensionsCloseDriver = f
end

local function installDispatcherHooks()
  if adapter.uiExtensionsHooked then return true end

  local okHost, hostReason = adapter:ProbeWorkbenchUIHost()
  if not okHost then return false, hostReason end
  local aui = ui()
  if not aui then return false, "Aegis UI table unavailable" end

  adapter.uiExtensionsOriginalSelectSubTab = aui.SelectSubTab
  adapter.uiExtensionsOriginalOpenWindow = aui.OpenWindow

  aui.SelectSubTab = function(name)
    local previous = aui.selectedSubTab
    local previousState = previous and registry[previous] or nil
    local nextState = registry[name]

    if previousState and previous ~= name then
      callBeforeHide(previousState)
    end

    if nextState then
      local attached, attachReason = adapter:EnsureUIExtensionAttached(name)
      if not attached then
        nextState.lastError = attachReason
        adapter.uiExtensionsLastError = attachReason
        return adapter.uiExtensionsOriginalSelectSubTab("Buy")
      end
      local ready, readyReason = callBeforeShow(nextState)
      if not ready then
        nextState.lastError = readyReason
        adapter.uiExtensionsLastError = readyReason
        return adapter.uiExtensionsOriginalSelectSubTab("Buy")
      end
    end

    local result = adapter.uiExtensionsOriginalSelectSubTab(name)

    if nextState then
      if aui.selectedSubTab ~= name then
        callBeforeHide(nextState)
        nextState.lastError = "Aegis did not select extension tab: " .. tostring(name)
        adapter.uiExtensionsLastError = nextState.lastError
        return result
      end
      local shown, showReason = callAfterShow(nextState)
      if not shown then
        nextState.lastError = showReason
        adapter.uiExtensionsLastError = showReason
        callBeforeHide(nextState)
        adapter.uiExtensionsOriginalSelectSubTab("Buy")
      end
    end
    return result
  end

  aui.OpenWindow = function()
    local result = adapter.uiExtensionsOriginalOpenWindow()
    local ok, reason = adapter:EnsureAllUIExtensionsAttached()
    if not ok then adapter.uiExtensionsLastError = reason end
    return result
  end

  adapter.uiExtensionsHooked = true
  installCloseDriver()
  return true, "Aegis multi-extension dispatcher installed"
end

function adapter:InstallUIExtension(spec)
  if not spec or not spec.key then
    return false, "UI extension key missing"
  end
  local key = tostring(spec.key)
  if registry[key] then
    return false, "Aegis UI extension already registered: " .. key
  end

  local okHost, hostReason = self:ProbeWorkbenchUIHost()
  if not okHost then return false, hostReason end

  local state = {
    key = key,
    spec = spec,
    installed = true,
    attached = false,
    disabled = false,
    reason = "registered; waiting for Aegis window",
    lastError = nil,
    tab = nil,
    panel = nil,
  }
  registry[key] = state
  table.insert(order, key)

  local hooked, hookReason = installDispatcherHooks()
  if not hooked then
    registry[key] = nil
    table.remove(order, table.getn(order))
    return false, hookReason
  end

  local aui = ui()
  if aui and aui.frame then
    local attached, attachReason = self:EnsureUIExtensionAttached(key)
    if not attached then return false, attachReason end
  end

  return true, state.reason
end

function adapter:SelectUIExtension(key)
  local state = registry[key]
  if not state or state.disabled then
    return false, state and state.reason or "Aegis UI extension unavailable"
  end
  local aui = ui()
  if not aui or not aui.frame or not aui.frame.IsVisible or not aui.frame:IsVisible() then
    return false, "Aegis window is not visible"
  end
  local attached, reason = self:EnsureUIExtensionAttached(key)
  if not attached then return false, reason end
  aui.SelectSubTab(key)
  if aui.selectedSubTab ~= key then
    return false, state.lastError or "Aegis refused UI extension selection"
  end
  return true, "Aegis UI extension selected: " .. tostring(key)
end

function adapter:OpenUIExtension(key)
  local state = registry[key]
  if not state or state.disabled then
    return false, state and state.reason or "Aegis UI extension unavailable"
  end
  local aui = ui()
  if not aui or type(aui.OpenWindow) ~= "function" then
    return false, "Aegis ui.OpenWindow unavailable"
  end
  local ok, err = pcall(aui.OpenWindow)
  if not ok then return false, "Aegis OpenWindow error: " .. tostring(err) end
  return self:SelectUIExtension(key)
end

function adapter:IsUIExtensionActive(key)
  local state = registry[key]
  local aui = ui()
  return state and state.installed and state.attached and not state.disabled
    and aui and aui.selectedSubTab == key
    and aui.frame and aui.frame.IsVisible and aui.frame:IsVisible() and true or false
end

function adapter:GetUIExtensionDiagnostics(key)
  local version = self:GetVersion()
  local audits = {
    ["1.20.2"] = "70f648492607ca1aec6c3df2da42deed21d09c9d",
    ["1.53.29"] = "924ce71fee75a61bec08983243385a53ee71ddbc",
  }
  if not key then
    if registry["OctoWorkbench"] then
      key = "OctoWorkbench"
    elseif table.getn(order) > 0 then
      key = order[1]
    end
  end
  local state = key and registry[key] or nil
  return {
    key = key,
    version = version,
    auditedVersion = "1.53.29",
    auditCommit = audits["1.53.29"],
    detectedAuditCommit = version and audits[tostring(version)] or nil,
    installed = state and state.installed or false,
    attached = state and state.attached or false,
    active = key and self:IsUIExtensionActive(key) or false,
    disabled = state and state.disabled or false,
    reason = state and state.reason or "extension not registered",
    lastError = state and state.lastError or self.uiExtensionsLastError,
    registeredCount = table.getn(order),
  }
end
