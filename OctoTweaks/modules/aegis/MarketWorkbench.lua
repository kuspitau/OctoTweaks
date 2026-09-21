--[[
Module: aegis.market_workbench
Category: feature
Target: Aegis: Exchange
Source-audited against Aegis: Exchange 1.20.2, 1.53.16, and 1.53.29
Runtime validation: PASS on the current Aegis 1.53.29 integration baseline; targeted Similar Search slot-fallback correction pending in-game regression

Core scope:
- keep a Target Item selected from the player's bags;
- build a simple Similar Search from class/subclass/equipment slot and
  required-level +/- N;
- collect results through the probed Aegis scan adapter;
- group results by item/name and expose individual listings;
- show normal/Aegis-enhanced GameTooltips on hover;
- choose a Reference Listing without replacing the Target Item;
- compute Match, Flat, or Percent undercut suggestions.

Direct posting is exposed through Aegis's own multi-stack posting engine.
Background scanning, inventory analytics, and guarded smart reference policies
remain outside this module. Aegis-window hosting is provided separately by
aegis.market_workbench_ui.
]]

local OT = OctoTweaks
local WB = {
  target = nil,
  reference = nil,
  rawRows = {},
  groups = {},
  displayRows = {},
  expanded = {},
  resultPage = 1,
  rowsPerPage = 11,
  scanActive = false,
  postingActive = false,
  postStackSize = 1,
  postNumStacks = 1,
  postDuration = 480,
  pendingTarget = nil,
  resolveDriver = nil,
  frame = nil,
  resultButtons = {},
}

OT.MarketWorkbench = WB

local function ensureSettings()
  OT:EnsureSavedVariables()
  if not OctoTweaksDB.marketWorkbench then
    OctoTweaksDB.marketWorkbench = {}
  end
  local db = OctoTweaksDB.marketWorkbench
  if db.levelRange == nil then db.levelRange = 2 end
  if db.buyoutOnly == nil then db.buyoutOnly = true end
  if db.exactQuality == nil then db.exactQuality = false end
  if db.undercutMode == nil then db.undercutMode = "flat" end
  if db.undercutAmount == nil then db.undercutAmount = 1 end
  if db.postDuration == nil then db.postDuration = 480 end
  return db
end

local function trim(value)
  if not value then return "" end
  local _, _, out = string.find(value, "^%s*(.-)%s*$")
  return out or value
end

local function money(copper)
  if type(copper) ~= "number" then return "--" end
  copper = math.floor(copper)
  if copper < 0 then copper = 0 end
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

local function qualityColor(quality)
  if ITEM_QUALITY_COLORS and quality ~= nil and ITEM_QUALITY_COLORS[quality] then
    local c = ITEM_QUALITY_COLORS[quality]
    return c.r or 1, c.g or 1, c.b or 1
  end
  return 1, 1, 1
end

function WB:SetStatus(text)
  if self.frame and self.frame.status then
    self.frame.status:SetText(tostring(text or ""))
  end
  OT:Debug("Market Workbench: " .. tostring(text or ""))
end

function WB:ItemIdFromLink(link)
  if OT.Aegis and OT.Aegis.ItemIdFromLink then
    return OT.Aegis:ItemIdFromLink(link)
  end
  if type(link) ~= "string" then return nil end
  local _, _, itemId = string.find(link, "item:(%d+)")
  return itemId and tonumber(itemId) or nil
end

function WB:FindBagItem(itemId)
  if not itemId then return nil end
  local bag = 0
  while bag <= 4 do
    local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
    local slot = 1
    while slot <= slots do
      local link = GetContainerItemLink and GetContainerItemLink(bag, slot) or nil
      if link and self:ItemIdFromLink(link) == itemId then
        return bag, slot
      end
      slot = slot + 1
    end
    bag = bag + 1
  end
  return nil
end

function WB:StopTargetResolver()
  if self.resolveDriver then self.resolveDriver:Hide() end
  self.pendingTarget = nil
end

function WB:ApplyResolvedTarget(payload)
  local info = payload and payload.info
  if not payload or not payload.ready or not info then
    return false, "target metadata is not ready"
  end
  if not payload.itemId then
    return false, "could not resolve item id from bag link"
  end

  self:StopTargetResolver()
  self.target = {
    bag = payload.bag,
    slot = payload.slot,
    itemId = payload.itemId,
    name = info.name or payload.name,
    link = info.link or payload.link,
    quality = info.quality,
    itemLevel = info.itemLevel,
    requiredLevel = info.minLevel or 0,
    itemType = info.type,
    itemSubType = info.subType,
    stackMax = info.stackCount,
    equipLoc = info.equipLoc,
    texture = info.texture or payload.texture,
    count = payload.count or 1,
  }
  self.reference = nil
  self.postStackSize = payload.count or 1
  self.postNumStacks = 1
  self.postDuration = ensureSettings().postDuration or 480
  self.rawRows = {}
  self.groups = {}
  self.displayRows = {}
  self.expanded = {}
  self.resultPage = 1

  self:RefreshTargetPanel()
  self:RefreshPricingPanel()
  self:RenderResults()
  self:SetStatus("Target Item set: " .. tostring(self.target.name))
  return true, self.target.name
end

function WB:EnsureTargetResolver()
  if self.resolveDriver then return self.resolveDriver end
  local driver = CreateFrame("Frame", "OctoTweaksMarketWorkbenchItemResolver")
  driver:Hide()
  driver:SetScript("OnUpdate", function()
    WB:ResolvePendingTarget(arg1)
  end)
  self.resolveDriver = driver
  return driver
end

function WB:QueueTargetResolution(bag, slot, itemId, displayName)
  self.pendingTarget = {
    bag = bag,
    slot = slot,
    itemId = itemId,
    displayName = displayName,
    elapsed = 0,
    delay = 0,
    attempts = 0,
  }
  self:SetStatus("Resolving Target Item metadata from the 1.12 item cache...")
  self:EnsureTargetResolver():Show()
end

function WB:ResolvePendingTarget(elapsed)
  local pending = self.pendingTarget
  if not pending then
    if self.resolveDriver then self.resolveDriver:Hide() end
    return
  end

  pending.delay = (pending.delay or 0) + (elapsed or 0)
  pending.elapsed = (pending.elapsed or 0) + (elapsed or 0)
  if pending.delay < 0.15 then return end
  pending.delay = 0
  pending.attempts = (pending.attempts or 0) + 1

  if pending.itemId then
    local currentLink = pending.bag and GetContainerItemLink and GetContainerItemLink(pending.bag, pending.slot) or nil
    if not currentLink or self:ItemIdFromLink(currentLink) ~= pending.itemId then
      pending.bag, pending.slot = self:FindBagItem(pending.itemId)
    end
  end

  if pending.bag and pending.slot and OT.Aegis then
    local payload = OT.Aegis:GetBagItemInfo(pending.bag, pending.slot)
    if payload and payload.ready then
      self:ApplyResolvedTarget(payload)
      return
    end
  end

  if pending.attempts >= 30 then
    local bag = pending.bag
    local slot = pending.slot
    self:StopTargetResolver()
    if bag and slot then
      self:SetStatus("Target metadata is still unavailable. Run /otmarket itemprobe "
        .. tostring(bag) .. " " .. tostring(slot))
      OT:Print("Market Workbench: item cache did not resolve after retries; run /otmarket itemprobe "
        .. tostring(bag) .. " " .. tostring(slot))
    else
      self:SetStatus("Target item returned to the bags but could not be located after drop")
    end
  end
end

function WB:SetTargetFromBag(bag, slot)
  bag = tonumber(bag)
  slot = tonumber(slot)
  if not bag or not slot then
    return false, "bag and slot must be numeric"
  end
  if not OT.Aegis or not OT.Aegis.GetBagItemInfo then
    return false, "Aegis bag-item adapter is unavailable"
  end

  local payload, reason = OT.Aegis:GetBagItemInfo(bag, slot)
  if not payload then
    return false, reason
  end
  if payload.ready then
    return self:ApplyResolvedTarget(payload)
  end

  self:QueueTargetResolution(bag, slot, payload.itemId, payload.name)
  return true, "resolving item metadata"
end

function WB:CaptureCursorTarget()
  if not GetCursorInfo then
    return false, "GetCursorInfo unavailable; use /otmarket target <bag> <slot>"
  end

  local cursorType, cursorId, cursorInfo = GetCursorInfo()
  if cursorType ~= "item" then
    return false, "drag an item from your bags onto the Target Item box"
  end

  local itemId = tonumber(cursorId)
  if not itemId and type(cursorInfo) == "string" then
    itemId = self:ItemIdFromLink(cursorInfo)
  end

  if ClearCursor then ClearCursor() end
  if not itemId then
    return false, "cursor item id could not be resolved"
  end

  local bag, slot = self:FindBagItem(itemId)
  if not bag then
    self:QueueTargetResolution(nil, nil, itemId, nil)
    return true, "waiting for the dropped item to return to the bags"
  end
  return self:SetTargetFromBag(bag, slot)
end

function WB:ReferenceUnit()
  return self.reference and self.reference.unit or nil
end

function WB:SuggestedPrice()
  local ref = self:ReferenceUnit()
  if not ref or ref <= 0 then return nil end

  local db = ensureSettings()
  local mode = db.undercutMode
  local amount = tonumber(db.undercutAmount) or 0
  if amount < 0 then amount = 0 end

  if mode == "match" then
    return ref
  elseif mode == "percent" then
    local value = math.floor(ref * (100 - amount) / 100)
    if value < 1 then value = 1 end
    return value
  end

  local value = ref - math.floor(amount)
  if value < 1 then value = 1 end
  return value
end

function WB:SetReference(row)
  if not row or not row.unit or row.unit <= 0 then
    self:SetStatus("Reference Listing requires a buyout price")
    return false
  end
  self.reference = row
  self:RefreshPricingPanel()
  self:SetStatus("Reference Listing set: " .. tostring(row.name) .. " at " .. money(row.unit) .. " per unit")
  return true
end

function WB:CycleUndercutMode()
  local db = ensureSettings()
  if db.undercutMode == "flat" then
    db.undercutMode = "match"
  elseif db.undercutMode == "match" then
    db.undercutMode = "percent"
  else
    db.undercutMode = "flat"
  end
  self:RefreshPricingPanel()
end

function WB:ApplyUndercutAmount()
  if not self.frame or not self.frame.undercutBox then return end
  local value = tonumber(trim(self.frame.undercutBox:GetText()))
  if not value or value < 0 then
    self:SetStatus("Undercut amount must be zero or greater")
    self:RefreshPricingPanel()
    return
  end
  ensureSettings().undercutAmount = value
  self:RefreshPricingPanel()
end


local function durationLabel(minutes)
  if minutes == 120 then return "6h" end
  if minutes == 1440 then return "72h" end
  return "24h"
end

function WB:CyclePostDuration()
  if self.postDuration == 120 then
    self.postDuration = 480
  elseif self.postDuration == 480 then
    self.postDuration = 1440
  else
    self.postDuration = 120
  end
  ensureSettings().postDuration = self.postDuration
  self:RefreshPricingPanel()
end

function WB:ReadPostControls()
  local stackSize = self.postStackSize or 1
  local numStacks = self.postNumStacks or 1
  if self.frame and self.frame.stackBox then
    stackSize = tonumber(trim(self.frame.stackBox:GetText()))
  end
  if self.frame and self.frame.numStacksBox then
    numStacks = tonumber(trim(self.frame.numStacksBox:GetText()))
  end
  if not stackSize or stackSize < 1 then
    return nil, nil, "Stack size must be at least 1"
  end
  if not numStacks or numStacks < 1 then
    return nil, nil, "Auction count must be at least 1"
  end
  stackSize = math.floor(stackSize)
  numStacks = math.floor(numStacks)
  self.postStackSize = stackSize
  self.postNumStacks = numStacks
  return stackSize, numStacks
end

function WB:RefreshPostAvailability()
  if not self.frame or not self.frame.postAvailability then return end
  if not self.target or not OT.Aegis or not OT.Aegis.GetPostAvailability then
    self.frame.postAvailability:SetText("In bags: --  |  postable stacks: --")
    return
  end
  local stackSize = tonumber(self.frame.stackBox and self.frame.stackBox:GetText())
    or self.postStackSize or 1
  stackSize = math.floor(stackSize)
  if stackSize < 1 then stackSize = 1 end
  local availability = OT.Aegis:GetPostAvailability(self.target.itemId, stackSize)
  if not availability then
    self.frame.postAvailability:SetText("In bags: --  |  postable stacks: --")
    return
  end
  self.frame.postAvailability:SetText("In bags: " .. tostring(availability.total)
    .. "  |  postable stacks: " .. tostring(availability.stacks))
end

function WB:StartPosting()
  if self.postingActive then
    self:SetStatus("A Workbench posting job is already active")
    return false
  end
  if not self.target then
    self:SetStatus("Choose a Target Item first")
    return false
  end
  if not OT.Aegis or not OT.Aegis.StartPosting then
    self:SetStatus("Aegis posting adapter is unavailable")
    return false
  end

  local unitPrice = self:SuggestedPrice()
  if not unitPrice or unitPrice < 1 then
    self:SetStatus("Choose a Reference Listing with SET before posting")
    return false
  end

  local stackSize, numStacks, controlReason = self:ReadPostControls()
  if not stackSize then
    self:SetStatus(controlReason)
    return false
  end

  local availability, availabilityReason = OT.Aegis:GetPostAvailability(self.target.itemId, stackSize)
  if not availability then
    self:SetStatus("Posting unavailable: " .. tostring(availabilityReason))
    return false
  end
  if availability.stacks < 1 then
    self:SetStatus("No postable stack of size " .. tostring(stackSize) .. " is available")
    return false
  end

  local ok, reason = OT.Aegis:StartPosting(
    self.target.itemId,
    self.target.name,
    stackSize,
    numStacks,
    unitPrice,
    unitPrice,
    self.postDuration or 480,
    {
      onProgress = function(posted, requested)
        WB:SetStatus("Posting " .. tostring(WB.target and WB.target.name or "item")
          .. ": " .. tostring(posted) .. " / " .. tostring(requested) .. " auctions posted")
        WB:RefreshPostAvailability()
      end,
      onDone = function(posted, requested, doneReason)
        WB.postingActive = false
        WB:RefreshPostAvailability()
        WB:RefreshPricingPanel()
        if doneReason == "done" then
          WB:SetStatus("Posting complete: " .. tostring(posted) .. " / "
            .. tostring(requested) .. " auctions posted")
        else
          WB:SetStatus("Posting stopped: " .. tostring(posted) .. " / "
            .. tostring(requested) .. " posted (" .. tostring(doneReason) .. ")")
        end
      end,
    })

  if not ok then
    self.postingActive = false
    self:SetStatus("POST refused: " .. tostring(reason))
    return false
  end

  self.postingActive = true
  self:SetStatus("Posting started: " .. tostring(numStacks) .. " auction(s), stack "
    .. tostring(stackSize) .. ", " .. money(unitPrice) .. " / unit, "
    .. durationLabel(self.postDuration or 480))
  self:RefreshPricingPanel()
  return true
end

function WB:CancelPosting()
  if not self.postingActive then
    self:SetStatus("No Workbench posting job is active")
    return false
  end
  if not OT.Aegis or not OT.Aegis.CancelPosting then
    self:SetStatus("Aegis CancelPosting is unavailable")
    return false
  end
  local ok, reason = OT.Aegis:CancelPosting()
  if ok then self.postingActive = false end
  self:SetStatus(tostring(reason))
  self:RefreshPricingPanel()
  return ok
end

local function groupSort(a, b)
  if a.lowestUnit and b.lowestUnit then
    if a.lowestUnit == b.lowestUnit then return string.lower(a.name or "") < string.lower(b.name or "") end
    return a.lowestUnit < b.lowestUnit
  end
  if a.lowestUnit then return true end
  if b.lowestUnit then return false end
  return string.lower(a.name or "") < string.lower(b.name or "")
end

local function listingSort(a, b)
  if a.unit and b.unit then
    if a.unit == b.unit then return (a.buyout or 0) < (b.buyout or 0) end
    return a.unit < b.unit
  end
  if a.unit then return true end
  if b.unit then return false end
  return (a.minBid or 0) < (b.minBid or 0)
end

function WB:BuildGroups()
  local byKey = {}
  local groups = {}
  local i = 1
  while i <= table.getn(self.rawRows) do
    local row = self.rawRows[i]
    local key = tostring(row.itemId or 0) .. "\001" .. tostring(row.name or "")
    local group = byKey[key]
    if not group then
      group = {
        key = key,
        itemId = row.itemId,
        name = row.name,
        quality = row.quality,
        link = row.link,
        listingCount = 0,
        totalQty = 0,
        lowestUnit = nil,
        lowestTransaction = nil,
        cheapest = nil,
        children = {},
      }
      byKey[key] = group
      table.insert(groups, group)
    end

    group.listingCount = group.listingCount + 1
    group.totalQty = group.totalQty + (row.count or 1)
    table.insert(group.children, row)
    if row.buyout and row.buyout > 0 then
      if not group.lowestTransaction or row.buyout < group.lowestTransaction then
        group.lowestTransaction = row.buyout
      end
      if row.unit and (not group.lowestUnit or row.unit < group.lowestUnit) then
        group.lowestUnit = row.unit
        group.cheapest = row
        group.link = row.link or group.link
      end
    end
    i = i + 1
  end

  i = 1
  while i <= table.getn(groups) do
    table.sort(groups[i].children, listingSort)
    if OT.Aegis and groups[i].itemId then
      groups[i].market = OT.Aegis:GetMarketData(groups[i].itemId)
    end
    i = i + 1
  end
  table.sort(groups, groupSort)
  self.groups = groups
  self:BuildDisplayRows()
end

function WB:BuildDisplayRows()
  local display = {}
  local i = 1
  while i <= table.getn(self.groups) do
    local group = self.groups[i]
    table.insert(display, { kind = "group", group = group })
    if self.expanded[group.key] then
      local j = 1
      while j <= table.getn(group.children) do
        table.insert(display, { kind = "listing", listing = group.children[j], group = group })
        j = j + 1
      end
    end
    i = i + 1
  end
  self.displayRows = display

  local pages = math.ceil(table.getn(display) / self.rowsPerPage)
  if pages < 1 then pages = 1 end
  if self.resultPage > pages then self.resultPage = pages end
  if self.resultPage < 1 then self.resultPage = 1 end
end

function WB:ToggleGroup(group)
  if not group then return end
  self.expanded[group.key] = not self.expanded[group.key]
  self:BuildDisplayRows()
  self:RenderResults()
end

function WB:ShowTooltip(data, owner)
  if not data or not GameTooltip then return end
  local row
  if data.kind == "group" then
    row = data.group and (data.group.cheapest or data.group.children[1])
  else
    row = data.listing
  end
  if not row then return end

  if OT.Aegis and OT.Aegis.ShowListingTooltip then
    OT.Aegis:ShowListingTooltip(owner, row)
    return
  end

  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(row.name or "")
  GameTooltip:Show()
end

function WB:HideTooltip()
  if GameTooltip then GameTooltip:Hide() end
end

function WB:RenderResults()
  if not self.frame then return end
  self:BuildDisplayRows()

  local total = table.getn(self.displayRows)
  local pages = math.ceil(total / self.rowsPerPage)
  if pages < 1 then pages = 1 end
  local startIndex = (self.resultPage - 1) * self.rowsPerPage + 1

  local i = 1
  while i <= self.rowsPerPage do
    local button = self.resultButtons[i]
    local data = self.displayRows[startIndex + i - 1]
    button.data = data
    button.setButton.refData = nil

    if not data then
      button:Hide()
    else
      button:Show()
      local text = ""
      local row
      if data.kind == "group" then
        local g = data.group
        local marker = self.expanded[g.key] and "[-] " or "[+] "
        text = marker .. tostring(g.name or "?")
          .. "  x" .. tostring(g.totalQty)
          .. "  " .. tostring(g.listingCount) .. " listings"
          .. "  unit " .. money(g.lowestUnit)
          .. "  tx " .. money(g.lowestTransaction)
        if g.market and g.market.market then
          text = text .. "  mkt " .. money(g.market.market)
        end
        row = g.cheapest
      else
        row = data.listing
        text = "      x" .. tostring(row.count or 1)
          .. "  " .. tostring(row.owner or "?")
          .. "  unit " .. money(row.unit)
          .. "  stack " .. money(row.buyout)
      end

      button.label:SetText(text)
      if row then
        local r, g, b = qualityColor(row.quality)
        button.label:SetTextColor(r, g, b)
      else
        button.label:SetTextColor(1, 1, 1)
      end

      if row and row.unit and row.unit > 0 then
        button.setButton.refData = row
        button.setButton:Enable()
        button.setButton:SetText("SET")
      else
        button.setButton:Disable()
        button.setButton:SetText("--")
      end
    end
    i = i + 1
  end

  self.frame.pageText:SetText("Page " .. tostring(self.resultPage) .. " / " .. tostring(pages)
    .. "  (" .. tostring(table.getn(self.groups)) .. " item groups)")
end

function WB:PrevResultsPage()
  if self.resultPage > 1 then
    self.resultPage = self.resultPage - 1
    self:RenderResults()
  end
end

function WB:NextResultsPage()
  local pages = math.ceil(table.getn(self.displayRows) / self.rowsPerPage)
  if pages < 1 then pages = 1 end
  if self.resultPage < pages then
    self.resultPage = self.resultPage + 1
    self:RenderResults()
  end
end

function WB:RefreshTargetPanel()
  if not self.frame then return end
  if not self.target then
    self.frame.targetName:SetText("Drop a bag item here")
    self.frame.targetInfo:SetText("Target Item remains independent from Reference Listing")
    return
  end

  local t = self.target
  self.frame.targetName:SetText(tostring(t.name))
  local info = tostring(t.itemType or "?") .. " / " .. tostring(t.itemSubType or "?")
  if t.equipLoc and t.equipLoc ~= "" then
    info = info .. " / " .. tostring(OT:GetGlobal(t.equipLoc) or t.equipLoc)
  end
  info = info .. " / required " .. tostring(t.requiredLevel or 0)
  self.frame.targetInfo:SetText(info)
end

function WB:RefreshPricingPanel()
  if not self.frame then return end
  local db = ensureSettings()
  self.frame.modeButton:SetText("Mode: " .. tostring(db.undercutMode))
  self.frame.undercutBox:SetText(tostring(db.undercutAmount or 0))

  if not self.reference then
    self.frame.referenceText:SetText("Reference: none")
    self.frame.referencePrice:SetText("Reference Price: --")
    self.frame.suggestedPrice:SetText("Suggested Price: --")
  else
    self.frame.referenceText:SetText("Reference: " .. tostring(self.reference.name)
      .. " x" .. tostring(self.reference.count or 1)
      .. " by " .. tostring(self.reference.owner or "?"))
    self.frame.referencePrice:SetText("Reference Price: " .. money(self.reference.unit) .. " / unit")
    local suggested = self:SuggestedPrice()
    self.frame.suggestedPrice:SetText("Suggested Price: " .. money(suggested) .. " / unit")
  end

  if self.target then
    self.frame.targetRightName:SetText("Target: " .. tostring(self.target.name)
      .. " x" .. tostring(self.target.count or 1))
  else
    self.frame.targetRightName:SetText("Target: none")
  end

  if self.target and OT.Aegis then
    local market = OT.Aegis:GetMarketData(self.target.itemId)
    if market then
      self.frame.targetMarket:SetText("Target market: " .. money(market.market)
        .. "  min: " .. money(market.minBuyout)
        .. "  vendor: " .. money(market.vendor))
    else
      self.frame.targetMarket:SetText("Target market: --")
    end
  else
    self.frame.targetMarket:SetText("Target market: --")
  end

  if self.frame.stackBox then
    self.frame.stackBox:SetText(tostring(self.postStackSize or 1))
  end
  if self.frame.numStacksBox then
    self.frame.numStacksBox:SetText(tostring(self.postNumStacks or 1))
  end
  if self.frame.durationButton then
    self.frame.durationButton:SetText("Duration: " .. durationLabel(self.postDuration or 480))
  end

  self:RefreshPostAvailability()

  if self.frame.postButton and self.frame.postButton.Enable then
    local canPost = self.target and self:SuggestedPrice() and not self.postingActive
      and OT.Aegis and OT.Aegis:HasCapability("sell_posting")
    if canPost then self.frame.postButton:Enable() else self.frame.postButton:Disable() end
  end
  if self.frame.cancelPostButton and self.frame.cancelPostButton.Enable then
    if self.postingActive then
      self.frame.cancelPostButton:Enable()
    else
      self.frame.cancelPostButton:Disable()
    end
  end
end

function WB:RefreshAll()
  self:RefreshTargetPanel()
  self:RefreshPricingPanel()
  self:RenderResults()
end

function WB:StartSimilarSearch()
  if not self.target then
    self:SetStatus("Choose a Target Item first")
    return false
  end
  if not OT.Aegis then
    self:SetStatus("Aegis adapter is unavailable")
    return false
  end

  local db = ensureSettings()
  local range = tonumber(self.frame and self.frame.rangeBox:GetText() or db.levelRange)
  if not range or range < 0 then
    self:SetStatus("Level range must be zero or greater")
    return false
  end
  range = math.floor(range)
  db.levelRange = range

  if self.frame then
    db.buyoutOnly = self.frame.buyoutCheck:GetChecked() and true or false
    db.exactQuality = self.frame.qualityCheck:GetChecked() and true or false
  end

  self.rawRows = {}
  self.groups = {}
  self.displayRows = {}
  self.expanded = {}
  self.reference = nil
  self.resultPage = 1
  self:RefreshPricingPanel()
  self:RenderResults()
  self:SetStatus("Preparing Similar Search...")

  local ok, reason = OT.Aegis:StartSimilarScan(self.target, range, {
    buyoutOnly = db.buyoutOnly,
    exactQuality = db.exactQuality,
  }, {
    onRows = function(rows, page, totalPages)
      local i = 1
      while rows and i <= table.getn(rows) do
        table.insert(WB.rawRows, rows[i])
        i = i + 1
      end
      WB:SetStatus("Scanning similar items: page " .. tostring(page) .. " / " .. tostring(totalPages)
        .. ", " .. tostring(table.getn(WB.rawRows)) .. " listings collected")
    end,
    onComplete = function(stats)
      WB.scanActive = false
      WB:BuildGroups()
      WB:RenderResults()
      WB:SetStatus("Similar Search complete: " .. tostring(table.getn(WB.rawRows))
        .. " listings, " .. tostring(table.getn(WB.groups)) .. " item groups")
    end,
  })

  if not ok then
    self.scanActive = false
    self:SetStatus("Similar Search refused: " .. tostring(reason))
    return false
  end

  self.scanActive = true
  self:SetStatus("Similar Search: " .. tostring(reason))
  return true
end

function WB:CancelSearch()
  if not OT.Aegis then return false end
  local ok, reason = OT.Aegis:CancelOwnedScan()
  self.scanActive = false
  self:SetStatus(reason)
  return ok
end

local function createLabel(parent, text, x, y, width, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if width then
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
  end
  fs:SetText(text or "")
  return fs
end

local buttonSerial = 0
local function createButton(parent, text, x, y, width, height, fn)
  buttonSerial = buttonSerial + 1
  local button = CreateFrame("Button", "OctoTweaksMarketWorkbenchButton" .. buttonSerial, parent, "UIPanelButtonTemplate")
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:SetWidth(width)
  button:SetHeight(height)
  button:SetText(text)
  button:SetScript("OnClick", fn)
  return button
end

function WB:CreateUI()
  if self.frame then return self.frame end

  local frame = CreateFrame("Frame", "OctoTweaksMarketWorkbenchFrame", UIParent)
  frame:SetWidth(870)
  frame:SetHeight(500)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })

  frame.title = createLabel(frame, "OctoTweaks Market Workbench — prototype", 22, -18, 600, "GameFontNormal")
  frame.title:SetTextColor(1, 0.82, 0)

  local close = CreateFrame("Button", "OctoTweaksMarketWorkbenchCloseButton", frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

  -- Left: market/search.
  createLabel(frame, "MARKET / SIMILAR SEARCH", 24, -48, 540, "GameFontNormal")
  frame.targetDrop = CreateFrame("Button", nil, frame)
  frame.targetDrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -72)
  frame.targetDrop:SetWidth(540)
  frame.targetDrop:SetHeight(48)
  frame.targetDrop:EnableMouse(true)
  frame.targetDrop:RegisterForDrag("LeftButton")
  frame.targetDrop:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame.targetDrop:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
  frame.targetDrop:SetScript("OnReceiveDrag", function()
    local ok, why = WB:CaptureCursorTarget()
    if not ok then WB:SetStatus(why) end
  end)
  frame.targetDrop:SetScript("OnClick", function()
    if GetCursorInfo then
      local kind = GetCursorInfo()
      if kind == "item" then
        local ok, why = WB:CaptureCursorTarget()
        if not ok then WB:SetStatus(why) end
      end
    end
  end)
  frame.targetName = createLabel(frame.targetDrop, "Drop a bag item here", 8, -7, 510, "GameFontNormal")
  frame.targetInfo = createLabel(frame.targetDrop, "Target Item remains independent from Reference Listing", 8, -26, 510, "GameFontNormalSmall")
  frame.targetInfo:SetTextColor(0.7, 0.7, 0.7)

  createLabel(frame, "Required level +/-", 24, -130, 100)
  frame.rangeBox = CreateFrame("EditBox", "OctoTweaksMarketWorkbenchRangeBox", frame, "InputBoxTemplate")
  frame.rangeBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 128, -125)
  frame.rangeBox:SetWidth(36)
  frame.rangeBox:SetHeight(20)
  frame.rangeBox:SetAutoFocus(false)
  frame.rangeBox:SetText(tostring(ensureSettings().levelRange))

  frame.buyoutCheck = CreateFrame("CheckButton", "OctoTweaksMarketWorkbenchBuyoutCheck", frame, "UICheckButtonTemplate")
  frame.buyoutCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 180, -122)
  frame.buyoutCheck:SetWidth(24)
  frame.buyoutCheck:SetHeight(24)
  frame.buyoutCheck:SetChecked(ensureSettings().buyoutOnly and 1 or nil)
  createLabel(frame, "Buyout only", 204, -130, 76)

  frame.qualityCheck = CreateFrame("CheckButton", "OctoTweaksMarketWorkbenchQualityCheck", frame, "UICheckButtonTemplate")
  frame.qualityCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 284, -122)
  frame.qualityCheck:SetWidth(24)
  frame.qualityCheck:SetHeight(24)
  frame.qualityCheck:SetChecked(ensureSettings().exactQuality and 1 or nil)
  createLabel(frame, "Exact quality", 308, -130, 86)

  frame.searchButton = createButton(frame, "SIMILAR SEARCH", 410, -124, 112, 24, function()
    WB:StartSimilarSearch()
  end)
  frame.cancelButton = createButton(frame, "Stop", 526, -124, 42, 24, function()
    WB:CancelSearch()
  end)

  createLabel(frame, "Item / quantity / listings / unit / market", 24, -160, 530)

  local rowY = -180
  local i = 1
  while i <= self.rowsPerPage do
    local row = CreateFrame("Button", nil, frame)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, rowY - ((i - 1) * 24))
    row:SetWidth(540)
    row:SetHeight(22)
    row:EnableMouse(true)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.label:SetWidth(474)
    row.label:SetJustifyH("LEFT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnClick", function()
      local data = this.data
      if data and data.kind == "group" then WB:ToggleGroup(data.group) end
    end)
    row:SetScript("OnEnter", function() WB:ShowTooltip(this.data, this) end)
    row:SetScript("OnLeave", function() WB:HideTooltip() end)

    row.setButton = CreateFrame("Button", "OctoTweaksMarketWorkbenchSetButton" .. i, row, "UIPanelButtonTemplate")
    row.setButton:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.setButton:SetWidth(52)
    row.setButton:SetHeight(19)
    row.setButton:SetText("SET")
    row.setButton:SetScript("OnClick", function()
      if this.refData then WB:SetReference(this.refData) end
    end)

    self.resultButtons[i] = row
    i = i + 1
  end

  frame.prevButton = createButton(frame, "<", 24, -452, 28, 22, function() WB:PrevResultsPage() end)
  frame.pageText = createLabel(frame, "Page 1 / 1", 60, -456, 280)
  frame.nextButton = createButton(frame, ">", 340, -452, 28, 22, function() WB:NextResultsPage() end)

  -- Divider and right pricing panel.
  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetTexture(0.35, 0.35, 0.35, 0.8)
  divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 584, -48)
  divider:SetWidth(1)
  divider:SetHeight(410)

  createLabel(frame, "SELL / PRICING", 604, -48, 235, "GameFontNormal")
  createLabel(frame, "Target Item", 604, -76, 230)
  frame.targetRightName = createLabel(frame, "Target: none", 604, -96, 238, "GameFontNormal")
  frame.targetMarket = createLabel(frame, "Target market: --", 604, -116, 238)
  frame.targetMarket:SetTextColor(0.7, 0.7, 0.7)

  frame.referenceText = createLabel(frame, "Reference: none", 604, -155, 238)
  frame.referencePrice = createLabel(frame, "Reference Price: --", 604, -178, 238, "GameFontNormal")

  createLabel(frame, "Undercut", 604, -225, 80)
  frame.modeButton = createButton(frame, "Mode: flat", 604, -242, 110, 24, function() WB:CycleUndercutMode() end)
  frame.undercutBox = CreateFrame("EditBox", "OctoTweaksMarketWorkbenchUndercutBox", frame, "InputBoxTemplate")
  frame.undercutBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 724, -238)
  frame.undercutBox:SetWidth(64)
  frame.undercutBox:SetHeight(20)
  frame.undercutBox:SetAutoFocus(false)
  frame.undercutBox:SetScript("OnEnterPressed", function()
    WB:ApplyUndercutAmount()
    this:ClearFocus()
  end)
  createLabel(frame, "copper / %", 794, -246, 60)

  frame.suggestedPrice = createLabel(frame, "Suggested Price: --", 604, -294, 238, "GameFontNormal")
  frame.suggestedPrice:SetTextColor(0.35, 1, 0.35)

  createLabel(frame, "Stack", 604, -326, 42)
  frame.stackBox = CreateFrame("EditBox", "OctoTweaksMarketWorkbenchStackBox", frame, "InputBoxTemplate")
  frame.stackBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 642, -320)
  frame.stackBox:SetWidth(42)
  frame.stackBox:SetHeight(20)
  frame.stackBox:SetAutoFocus(false)
  frame.stackBox:SetScript("OnEnterPressed", function()
    local stackSize, numStacks, reason = WB:ReadPostControls()
    if not stackSize then WB:SetStatus(reason) end
    WB:RefreshPostAvailability()
    this:ClearFocus()
  end)

  createLabel(frame, "Auctions", 696, -326, 52)
  frame.numStacksBox = CreateFrame("EditBox", "OctoTweaksMarketWorkbenchNumStacksBox", frame, "InputBoxTemplate")
  frame.numStacksBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 752, -320)
  frame.numStacksBox:SetWidth(36)
  frame.numStacksBox:SetHeight(20)
  frame.numStacksBox:SetAutoFocus(false)
  frame.numStacksBox:SetScript("OnEnterPressed", function()
    local stackSize, numStacks, reason = WB:ReadPostControls()
    if not stackSize then WB:SetStatus(reason) end
    this:ClearFocus()
  end)

  frame.durationButton = createButton(frame, "Duration: 24h", 604, -351, 105, 24, function()
    WB:CyclePostDuration()
  end)
  frame.postButton = createButton(frame, "POST", 716, -351, 72, 24, function()
    WB:StartPosting()
  end)
  frame.cancelPostButton = createButton(frame, "Cancel", 794, -351, 54, 24, function()
    WB:CancelPosting()
  end)

  frame.postAvailability = createLabel(frame, "In bags: --  |  postable stacks: --", 604, -383, 238)
  createLabel(frame, "POST uses Suggested Price as both start bid and buyout.", 604, -405, 238)
  frame.postNote = createLabel(frame, "Aegis handles stack assembly and auction submission.", 604, -424, 238)
  frame.postNote:SetTextColor(0.7, 0.7, 0.7)

  frame.status = createLabel(frame, "Ready", 24, -478, 820)
  frame.status:SetTextColor(0.8, 0.8, 0.8)

  frame:SetScript("OnHide", function()
    if WB.scanActive then WB:CancelSearch() end
    if WB.postingActive then WB:CancelPosting() end
  end)

  self.frame = frame
  self:RefreshAll()
  frame:Hide()
  return frame
end

function WB:Open()
  local state = OT:GetModuleState("aegis.market_workbench")
  if not state or state.status ~= "ENABLED" then
    OT:Print("aegis.market_workbench is not enabled: " .. tostring(state and state.reason or "unknown"))
    return
  end
  local frame = self:CreateUI()
  frame:Show()
  self:RefreshAll()
end

function WB:Toggle()
  if self.frame and self.frame:IsVisible() then
    self.frame:Hide()
  else
    self:Open()
  end
end

function WB:PrintDiagnostics()
  OT:Print("Market Workbench: target=" .. tostring(self.target and self.target.name or "none")
    .. ", pendingTarget=" .. tostring(self.pendingTarget and self.pendingTarget.itemId or "none")
    .. ", reference=" .. tostring(self.reference and self.reference.name or "none")
    .. ", scanActive=" .. tostring(self.scanActive)
    .. ", postingActive=" .. tostring(self.postingActive)
    .. ", listings=" .. tostring(table.getn(self.rawRows))
    .. ", groups=" .. tostring(table.getn(self.groups)))
  if OT.Aegis then OT.Aegis:PrintDiagnostics() end
end

local module = {
  id = "aegis.market_workbench",
  category = "feature",
  target = "Aegis_Exchange",
  defaultEnabled = true,
  testedVersion = "1.53.29",
  sourceAuditedVersions = "1.20.2, 1.53.16, 1.53.29",
}

function module:probe()
  local integration = OT:GetModuleState("aegis.integration")
  if not integration or integration.status ~= "ENABLED" then
    return false, "waiting for aegis.integration"
  end
  if not OT.Aegis then
    return false, "Aegis adapter unavailable"
  end
  local ok, reason = OT.Aegis:MinimumWorkbenchReady()
  if not ok then return false, reason end
  if not GetContainerItemLink or not GetContainerItemInfo then
    return false, "required bag APIs unavailable"
  end
  return true, "Aegis Market Workbench prerequisites detected"
end

function module:enable()
  ensureSettings()
  return true, "Market Workbench prototype ready; /otmarket"
end

OT:RegisterModule(module)

SLASH_OCTOTWEAKSMARKET1 = "/otmarket"
SlashCmdList["OCTOTWEAKSMARKET"] = function(msg)
  msg = trim(msg or "")
  local low = string.lower(msg)

  if low == "" or low == "toggle" then
    WB:Toggle()
    return
  end
  if low == "open" then
    WB:Open()
    return
  end
  if low == "close" then
    if WB.frame then WB.frame:Hide() end
    return
  end
  if low == "probe" or low == "status" then
    WB:PrintDiagnostics()
    return
  end
  if low == "search" then
    WB:Open()
    WB:StartSimilarSearch()
    return
  end
  if low == "cancel" or low == "stop" then
    WB:CancelSearch()
    return
  end
  if low == "post" then
    WB:Open()
    WB:StartPosting()
    return
  end
  if low == "cancelpost" or low == "stoppost" then
    WB:CancelPosting()
    return
  end

  local _, _, probeBag, probeSlot = string.find(low, "^itemprobe%s+(%d+)%s+(%d+)$")
  if probeBag and probeSlot then
    if OT.Aegis and OT.Aegis.PrintBagItemProbe then
      OT.Aegis:PrintBagItemProbe(tonumber(probeBag), tonumber(probeSlot))
    else
      OT:Print("Market Workbench: Aegis item probe unavailable")
    end
    return
  end

  local _, _, bag, slot = string.find(low, "^target%s+(%d+)%s+(%d+)$")
  if bag and slot then
    local ok, why = WB:SetTargetFromBag(tonumber(bag), tonumber(slot))
    if ok then WB:Open() else OT:Print("Market Workbench: " .. tostring(why)) end
    return
  end

  OT:Print("Usage: /otmarket [open|close|toggle|status|probe|search|cancel|post|cancelpost]")
  OT:Print("       /otmarket target <bag> <slot>")
  OT:Print("       /otmarket itemprobe <bag> <slot>")
end
