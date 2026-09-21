-- Market Workbench presentation inside source-audited Aegis windows.
--
-- All direct Aegis UI access stays in UIAdapter.lua. This module only talks to
-- OctoTweaks.Aegis and reuses the already runtime-validated Workbench frame.

local OT = OctoTweaks
local WB = OT.MarketWorkbench
local Aegis = OT.Aegis

if not WB or not Aegis then
  return
end

local View = {
  key = "OctoWorkbench",
  label = "Workbench",
  hostHeight = 620,
  embedded = false,
  routingInstalled = false,
  originalOpen = nil,
  originalToggle = nil,
  originalPrintDiagnostics = nil,
  originalSlash = nil,
  savedDragStart = nil,
  savedDragStop = nil,
  targetDropMouseUp = nil,
  targetDropMouseUpSaved = false,
  bagHookInstalled = false,
  originalContainerClick = nil,
  originalUseContainerItem = nil,
  quickWorkflowInstalled = false,
  originalApplyResolvedTarget = nil,
  originalBuildGroups = nil,
  originalRefreshPricingPanel = nil,
  originalCancelSearch = nil,
  quickTargetItemId = nil,
  quickTargetExpires = nil,
  autoReferencePending = false,
}

OT.MarketWorkbenchAegisUI = View

local function workbenchCloseButton()
  return getglobal and getglobal("OctoTweaksMarketWorkbenchCloseButton") or nil
end

local function modifierDown()
  if IsShiftKeyDown and IsShiftKeyDown() then return true end
  if IsControlKeyDown and IsControlKeyDown() then return true end
  if IsAltKeyDown and IsAltKeyDown() then return true end
  return false
end

local GAIN_DEFAULT_GREEN = 10 * 100
local GAIN_DEFAULT_YELLOW = 40 * 100
local GAIN_DEFAULT_ORANGE = 70 * 100
local GAIN_DEFAULT_RED = 100 * 100

local function marketSettings()
  if OT.EnsureSavedVariables then OT:EnsureSavedVariables() end
  if not OctoTweaksDB then OctoTweaksDB = {} end
  if not OctoTweaksDB.marketWorkbench then OctoTweaksDB.marketWorkbench = {} end
  local db = OctoTweaksDB.marketWorkbench
  if not db.gainThresholds then db.gainThresholds = {} end
  local t = db.gainThresholds
  if t.green == nil then t.green = GAIN_DEFAULT_GREEN end
  if t.yellow == nil then t.yellow = GAIN_DEFAULT_YELLOW end
  if t.orange == nil then t.orange = GAIN_DEFAULT_ORANGE end
  if t.red == nil then t.red = GAIN_DEFAULT_RED end
  return db, t
end

local function money(copper)
  copper = tonumber(copper)
  if not copper then return "--" end
  copper = math.floor(copper)
  if copper < 0 then copper = -copper end
  local gold = math.floor(copper / 10000)
  local silver = math.floor(math.mod(copper, 10000) / 100)
  local coin = math.mod(copper, 100)
  if gold > 0 then
    return tostring(gold) .. "g " .. tostring(silver) .. "s " .. tostring(coin) .. "c"
  end
  if silver > 0 then
    return tostring(silver) .. "s " .. tostring(coin) .. "c"
  end
  return tostring(coin) .. "c"
end

function View:GetGainThresholds()
  local _, t = marketSettings()
  return t
end

function View:SetGainThresholdsSilver(green, yellow, orange, red)
  green = tonumber(green)
  yellow = tonumber(yellow)
  orange = tonumber(orange)
  red = tonumber(red)
  if not green or not yellow or not orange or not red
      or green <= 0 or yellow <= green or orange <= yellow or red <= orange then
    OT:Print("Market Workbench: gain thresholds must be four increasing silver values; example /otmarket gains 10 40 70 100")
    return false
  end
  local t = self:GetGainThresholds()
  t.green = math.floor(green * 100)
  t.yellow = math.floor(yellow * 100)
  t.orange = math.floor(orange * 100)
  t.red = math.floor(red * 100)
  self:RefreshGainDisplay()
  self:PrintGainThresholds()
  return true
end

function View:ResetGainThresholds()
  local t = self:GetGainThresholds()
  t.green = GAIN_DEFAULT_GREEN
  t.yellow = GAIN_DEFAULT_YELLOW
  t.orange = GAIN_DEFAULT_ORANGE
  t.red = GAIN_DEFAULT_RED
  self:RefreshGainDisplay()
  self:PrintGainThresholds()
end

function View:PrintGainThresholds()
  local t = self:GetGainThresholds()
  OT:Print("Market Workbench gain colors (silver): green < " .. tostring(math.floor(t.green / 100))
    .. ", yellow < " .. tostring(math.floor(t.yellow / 100))
    .. ", orange < " .. tostring(math.floor(t.orange / 100))
    .. ", red < " .. tostring(math.floor(t.red / 100))
    .. ", purple >= " .. tostring(math.floor(t.red / 100)))
  OT:Print("  Set with /otmarket gains <green> <yellow> <orange> <red>; reset with /otmarket gains reset")
end

function View:GainColor(gain)
  if not gain or gain <= 0 then return 0.55, 0.55, 0.55 end
  local t = self:GetGainThresholds()
  if gain < t.green then return 0.25, 1, 0.25 end
  if gain < t.yellow then return 1, 0.82, 0 end
  if gain < t.orange then return 1, 0.5, 0 end
  if gain < t.red then return 1, 0.2, 0.2 end
  return 0.72, 0.35, 1
end

function View:EnsureGainDisplay(frame)
  if not frame then return end

  -- The original iteration placed the small gain line too close to the Stack
  -- controls. In the real 1.12 client that made it visually collide with the
  -- next row. Give Suggested Price and the gain line their own vertical slots
  -- in the embedded pricing column.
  if frame.suggestedPrice and not frame.workbenchGainLayoutAdjusted then
    frame.suggestedPrice:ClearAllPoints()
    frame.suggestedPrice:SetPoint("TOPLEFT", frame, "TOPLEFT", 604, -286)
    frame.workbenchGainLayoutAdjusted = true
  end

  if frame.gainVsVendor then return end
  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", 604, -307)
  label:SetWidth(238)
  label:SetJustifyH("LEFT")
  label:SetText("Gain vs vendor: --")
  label:SetTextColor(0.55, 0.55, 0.55)
  frame.gainVsVendor = label
end

function View:GetVendorValue(target)
  if not target or not target.itemId then return nil, nil end

  -- SellValue 1.12 exposes its initialized/learned per-item vendor database as
  -- the global SellValues table. Keys are strings such as "item:15611". Its
  -- merchant scan updates the same table, so prefer it when present: on this
  -- OctoWoW setup it is also the source that already renders the reliable
  -- vendor amount in bag tooltips. This is read-only and SellValue remains an
  -- optional dependency.
  if type(SellValues) == "table" then
    local key = "item:" .. tostring(target.itemId)
    local value = tonumber(SellValues[key])
    if value == nil then value = tonumber(SellValues[target.itemId]) end
    if value ~= nil and value >= 0 then
      return math.floor(value), "SellValue"
    end
  end

  -- Preserve the existing Aegis market-db path as fallback when SellValue is
  -- absent or has no row for this item.
  local market = Aegis:GetMarketData(target.itemId)
  local value = market and tonumber(market.vendor) or nil
  if value ~= nil and value >= 0 then
    return math.floor(value), "Aegis"
  end
  return nil, nil
end

function View:RefreshVendorMarketText()
  local frame = WB.frame
  if not frame or not frame.targetMarket or not WB.target then return end

  local market = Aegis:GetMarketData(WB.target.itemId)
  local vendor = self:GetVendorValue(WB.target)
  if market or vendor ~= nil then
    frame.targetMarket:SetText("Target market: " .. money(market and market.market)
      .. "  min: " .. money(market and market.minBuyout)
      .. "  vendor: " .. money(vendor))
  end
end

function View:RefreshGainDisplay()
  local frame = WB.frame
  if not frame then return end
  self:EnsureGainDisplay(frame)
  self:RefreshVendorMarketText()
  local label = frame.gainVsVendor
  if not WB.target or not WB.SuggestedPrice then
    label:SetText("Gain vs vendor: --")
    label:SetTextColor(0.55, 0.55, 0.55)
    return
  end

  local suggested = WB:SuggestedPrice()
  local vendor = self:GetVendorValue(WB.target)
  if not suggested or vendor == nil then
    label:SetText("Gain vs vendor: --")
    label:SetTextColor(0.55, 0.55, 0.55)
    return
  end

  local gain = math.floor(suggested - vendor)
  local sign = gain > 0 and "+" or (gain < 0 and "-" or "")
  label:SetText("Gain vs vendor: " .. sign .. money(gain) .. " / item")
  label:SetTextColor(self:GainColor(gain))
end

function View:FirstPricedReference()
  local i = 1
  while WB.groups and i <= table.getn(WB.groups) do
    local group = WB.groups[i]
    local row = group and group.cheapest or nil
    if row and row.unit and row.unit > 0 then return row end
    i = i + 1
  end
  return nil
end

function View:QuickTargetMatches(payload)
  if not payload or not payload.itemId or not self.quickTargetItemId then return false end
  if payload.itemId ~= self.quickTargetItemId then return false end
  if self.quickTargetExpires and GetTime and GetTime() > self.quickTargetExpires then return false end
  return true
end

function View:InstallQuickWorkflow()
  if self.quickWorkflowInstalled then return end
  self.quickWorkflowInstalled = true

  self.originalApplyResolvedTarget = WB.ApplyResolvedTarget
  WB.ApplyResolvedTarget = function(self, payload)
    local quick = View:QuickTargetMatches(payload)
    local ok, reason = View.originalApplyResolvedTarget(self, payload)
    if ok and quick then
      View.quickTargetItemId = nil
      View.quickTargetExpires = nil
      View.autoReferencePending = true
      local started = self:StartSimilarSearch()
      if not started then View.autoReferencePending = false end
    end
    View:RefreshGainDisplay()
    return ok, reason
  end

  self.originalBuildGroups = WB.BuildGroups
  WB.BuildGroups = function(self)
    View.originalBuildGroups(self)
    if View.autoReferencePending then
      View.autoReferencePending = false
      local row = View:FirstPricedReference()
      if row then self:SetReference(row) end
    end
  end

  self.originalRefreshPricingPanel = WB.RefreshPricingPanel
  WB.RefreshPricingPanel = function(self)
    View.originalRefreshPricingPanel(self)
    View:RefreshGainDisplay()
  end

  self.originalCancelSearch = WB.CancelSearch
  WB.CancelSearch = function(self)
    View.autoReferencePending = false
    return View.originalCancelSearch(self)
  end
end

function View:IsTargetRightClickActive()
  return Aegis:IsUIExtensionActive(self.key)
    and WB.frame and WB.frame.IsVisible and WB.frame:IsVisible() and true or false
end

function View:TryTargetFromBag(bag, slot)
  if not self:IsTargetRightClickActive() then return false end
  if modifierDown() then return false end
  if CursorHasItem and CursorHasItem() then return false end
  if not bag or not slot or not GetContainerItemLink then return false end

  local link = GetContainerItemLink(bag, slot)
  if not link then return false end

  if WB.scanActive then WB:CancelSearch() end
  View.autoReferencePending = false
  View.quickTargetItemId = WB:ItemIdFromLink(link)
  View.quickTargetExpires = GetTime and (GetTime() + 8) or nil

  local ok, reason = WB:SetTargetFromBag(bag, slot)
  if ok then
    WB:RefreshAll()
    return true
  end

  View.quickTargetItemId = nil
  View.quickTargetExpires = nil
  View.autoReferencePending = false
  WB:SetStatus("Target selection failed: " .. tostring(reason))
  -- A real bag item was right-clicked while Workbench was active. Swallow the
  -- normal use/equip action even if metadata resolution refused it; otherwise
  -- a failed pricing selection could unexpectedly consume or equip the item.
  return true
end

function View:InstallBagTargetHook()
  if self.bagHookInstalled then return end
  self.bagHookInstalled = true

  if ContainerFrameItemButton_OnClick then
    self.originalContainerClick = ContainerFrameItemButton_OnClick
    ContainerFrameItemButton_OnClick = function(button, ignoreModifiers)
      if button == "RightButton" then
        local btn = this
        local parent = btn and btn.GetParent and btn:GetParent() or nil
        local bag = parent and parent.GetID and parent:GetID() or nil
        local slot = btn and btn.GetID and btn:GetID() or nil
        if View:TryTargetFromBag(bag, slot) then return end
      end
      return View.originalContainerClick(button, ignoreModifiers)
    end
  end

  if UseContainerItem then
    self.originalUseContainerItem = UseContainerItem
    UseContainerItem = function(bag, slot, onSelf)
      if View:TryTargetFromBag(bag, slot) then return end
      return View.originalUseContainerItem(bag, slot, onSelf)
    end
  end
end

function View:RaiseEmbeddedControls(frame)
  if not frame or not frame.GetFrameLevel then return end

  local function raiseChildren(parent, level)
    if not parent or not parent.GetChildren then return end
    local children = { parent:GetChildren() }
    local i = 1
    while i <= table.getn(children) do
      local child = children[i]
      if child and child.SetFrameLevel then
        child:SetFrameLevel(level)
        raiseChildren(child, level + 1)
      end
      i = i + 1
    end
  end

  -- The Workbench controls are created while the frame is standalone. On the
  -- tested 1.12 client, reparenting the already-built frame into Aegis and
  -- raising only the parent leaves existing Button/EditBox/CheckButton child
  -- frames at their old absolute frame levels. Aegis' content layer then sits
  -- above those controls: parent FontStrings stay visible, but buttons, input
  -- boxes, checkboxes and result rows disappear and cannot receive clicks.
  -- Rebase the complete Workbench child-frame tree after embedding.
  raiseChildren(frame, frame:GetFrameLevel() + 2)
end

function View:HardenEmbeddedTargetDrop(frame)
  local drop = frame and frame.targetDrop
  if not drop then return end

  drop:EnableMouse(true)
  if drop.RegisterForDrag then drop:RegisterForDrag("LeftButton") end
  if drop.SetFrameLevel and frame.GetFrameLevel then
    drop:SetFrameLevel(frame:GetFrameLevel() + 8)
  end
  drop:Show()

  -- OnReceiveDrag is the validated standalone path. The embedded Aegis host
  -- can fail to deliver that release on the tested 1.12 client, so add a
  -- mouse-up fallback which only acts while an item is still on the cursor.
  -- If OnReceiveDrag already handled the item it clears the cursor and this is
  -- a no-op, avoiding duplicate Target selection.
  if not self.targetDropMouseUpSaved then
    self.targetDropMouseUp = drop:GetScript("OnMouseUp")
    self.targetDropMouseUpSaved = true
  end
  drop:SetScript("OnMouseUp", function()
    if View.targetDropMouseUp then View.targetDropMouseUp() end
    if GetCursorInfo then
      local kind = GetCursorInfo()
      if kind == "item" then
        local ok, reason = WB:CaptureCursorTarget()
        if not ok then WB:SetStatus(reason) end
      end
    end
  end)
end

function View:Embed(panel)
  if not panel then return false, "Aegis Workbench panel missing" end
  local frame = WB:CreateUI()
  if not frame then return false, "Workbench frame creation failed" end

  if not self.savedDragStart then self.savedDragStart = frame:GetScript("OnDragStart") end
  if not self.savedDragStop then self.savedDragStop = frame:GetScript("OnDragStop") end

  if frame:IsVisible() then frame:Hide() end
  frame:SetParent(panel)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", panel, "CENTER", 0, 0)
  frame:SetMovable(false)
  frame:SetScript("OnDragStart", nil)
  frame:SetScript("OnDragStop", nil)
  if frame.SetFrameStrata then frame:SetFrameStrata("HIGH") end
  if frame.SetFrameLevel and panel.GetFrameLevel then
    frame:SetFrameLevel(panel:GetFrameLevel() + 2)
  end
  self:RaiseEmbeddedControls(frame)

  local close = workbenchCloseButton()
  if close then close:Hide() end
  if frame.title then frame.title:SetText("Market Workbench") end
  if frame.targetInfo then
    frame.targetInfo:SetText("Right-click a bag item or drop it here — Target stays independent from Reference")
  end
  self:HardenEmbeddedTargetDrop(frame)

  self.embedded = true
  WB:RefreshAll()
  frame:Show()
  return true, "Workbench embedded in Aegis"
end

function View:MakeStandalone()
  local frame = WB.frame
  if not frame or not self.embedded then return end

  if frame:IsVisible() then frame:Hide() end
  frame:SetParent(UIParent)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetMovable(true)
  frame:SetScript("OnDragStart", self.savedDragStart)
  frame:SetScript("OnDragStop", self.savedDragStop)
  if frame.SetFrameStrata then frame:SetFrameStrata("DIALOG") end

  local close = workbenchCloseButton()
  if close then close:Show() end
  if frame.title then frame.title:SetText("OctoTweaks Market Workbench") end
  if frame.targetInfo then
    frame.targetInfo:SetText("Target Item remains independent from Reference Listing")
  end
  self.embedded = false
end

function View:BeforeHide()
  if WB.frame then
    -- Reuse the Workbench's existing OnHide ownership rule: a scan/post job
    -- started by the Workbench is cancelled when its view is left. Calling
    -- Hide explicitly also covers AUCTION_HOUSE_CLOSED after the parent Aegis
    -- frame has already become effectively hidden.
    WB.frame:Hide()
  end
end

function View:OnShow(panel)
  local ok, reason = self:Embed(panel)
  if not ok then error(reason) end
end

function View:InstallRouting()
  if self.routingInstalled then return end
  self.routingInstalled = true

  self.originalOpen = WB.Open
  WB.Open = function(self)
    if Aegis:IsAuctionHouseOpen() then
      local ok = Aegis:SelectUIExtension(View.key)
      if ok then return end
    end
    View:MakeStandalone()
    return View.originalOpen(self)
  end

  self.originalToggle = WB.Toggle
  WB.Toggle = function(self)
    if Aegis:IsUIExtensionActive(View.key) then
      Aegis:SelectAegisSubTab("Buy")
      return
    end
    return View.originalToggle(self)
  end

  self.originalPrintDiagnostics = WB.PrintDiagnostics
  WB.PrintDiagnostics = function(self)
    View.originalPrintDiagnostics(self)
    local d = Aegis:GetUIExtensionDiagnostics()
    OT:Print("Market Workbench Aegis UI: installed=" .. tostring(d.installed)
      .. ", attached=" .. tostring(d.attached)
      .. ", active=" .. tostring(d.active)
      .. ", disabled=" .. tostring(d.disabled))
    OT:Print("  UI audit: detected Aegis " .. tostring(d.version)
      .. " @ " .. tostring(d.detectedAuditCommit))
    OT:Print("  latest audited UI baseline: Aegis " .. tostring(d.auditedVersion)
      .. " @ " .. tostring(d.auditCommit))
    OT:Print("  UI reason: " .. tostring(d.reason))
    if d.lastError then OT:Print("  UI last error: " .. tostring(d.lastError)) end
  end

  self.originalSlash = SlashCmdList["OCTOTWEAKSMARKET"]
  if self.originalSlash then
    SlashCmdList["OCTOTWEAKSMARKET"] = function(msg)
      local low = string.lower(msg or "")
      low = string.gsub(low, "^%s+", "")
      low = string.gsub(low, "%s+$", "")
      if low == "gains" or low == "gain" then
        View:PrintGainThresholds()
        return
      end
      if low == "gains reset" or low == "gain reset" then
        View:ResetGainThresholds()
        return
      end
      local _, _, green, yellow, orange, red = string.find(low,
        "^gains?%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      if green then
        View:SetGainThresholdsSilver(green, yellow, orange, red)
        return
      end
      if low == "close" and Aegis:IsUIExtensionActive(View.key) then
        Aegis:SelectAegisSubTab("Buy")
        return
      end
      return View.originalSlash(msg)
    end
  end
end

local module = {
  id = "aegis.market_workbench_ui",
  category = "feature",
  target = "Aegis_Exchange",
  defaultEnabled = true,
  testedVersion = "1.53.29",
  sourceAuditedVersions = "1.20.2 UI seam (commit 70f64849), 1.53.29 UI seam (commit 924ce71f)",
}

function module:probe()
  local integration = OT:GetModuleState("aegis.integration")
  if not integration or integration.status ~= "ENABLED" then
    return false, "waiting for aegis.integration"
  end
  local workbench = OT:GetModuleState("aegis.market_workbench")
  if not workbench or workbench.status ~= "ENABLED" then
    return false, "waiting for aegis.market_workbench"
  end
  return Aegis:ProbeWorkbenchUIHost()
end

function module:enable()
  local ok, reason = Aegis:InstallUIExtension({
    key = View.key,
    label = View.label,
    hostHeight = View.hostHeight,
    beforeHide = function() View:BeforeHide() end,
    onShow = function(panel) View:OnShow(panel) end,
  })
  if not ok then return false, reason end
  View:InstallQuickWorkflow()
  View:InstallBagTargetHook()
  View:InstallRouting()
  return true, "Market Workbench Aegis sub-tab integration ready"
end

OT:RegisterModule(module)
