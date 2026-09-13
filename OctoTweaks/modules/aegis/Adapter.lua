--[[
Module: aegis.integration
Category: compatibility
Target: Aegis: Exchange
Source-audited against:
- Aegis: Exchange 1.53.16 (upstream main commit 3b69fac3bf141d8310996f5012406b5ea58f5971)
- Aegis: Exchange 1.20.2 (user-supplied installed addon ZIP, audited 2026-09-13)

Purpose:
Centralize all OctoTweaks access to AegisExchange internals behind capability
probes. Higher-level OctoTweaks modules should use OT.Aegis rather than reaching
into AegisExchange directly.

Aegis only documents its Courier integration block as a public contract. The
scan/buy/db/sell symbols below are therefore treated as version-sensitive
internals even when their shape is clean and well tested upstream.
]]

local OT = OctoTweaks

OT.Aegis = OT.Aegis or {}
local adapter = OT.Aegis

adapter.testedVersion = "1.53.16"
adapter.testedCommit = "3b69fac3bf141d8310996f5012406b5ea58f5971"
adapter.sourceAuditedVersions = {
  ["1.53.16"] = "upstream main 3b69fac3bf141d8310996f5012406b5ea58f5971",
  ["1.20.2"] = "user-supplied installed addon ZIP audited 2026-09-13",
}
adapter.capabilities = adapter.capabilities or {}
adapter.capabilityReasons = adapter.capabilityReasons or {}
adapter.activeOwner = nil

local function lower(value)
  if type(value) ~= "string" then
    return ""
  end
  return string.lower(value)
end

local function setCapability(name, available, reason)
  adapter.capabilities[name] = available and true or false
  adapter.capabilityReasons[name] = reason or (available and "available" or "unavailable")
end

function adapter:GetAegis()
  return OT:GetGlobal("AegisExchange")
end

function adapter:GetVersion()
  local A = self:GetAegis()
  if A and A.version then
    return tostring(A.version)
  end
  return OT:GetAddonVersion("Aegis_Exchange")
end

function adapter:IsLoaded()
  local A = self:GetAegis()
  return A and A.loaded == true
end

function adapter:IsSourceAuditedVersion(version)
  version = version or self:GetVersion()
  return version and self.sourceAuditedVersions[tostring(version)] ~= nil
end

function adapter:RefreshCapabilities()
  local A = self:GetAegis()

  setCapability("namespace", type(A) == "table", "global AegisExchange table")
  if type(A) ~= "table" then
    setCapability("loaded", false, "AegisExchange is not present")
    setCapability("scan_start", false, "AegisExchange.scan.Start is unavailable")
    setCapability("scan_control", false, "Aegis scan control is unavailable")
    setCapability("category_options", false, "Aegis buy category helpers are unavailable")
    setCapability("item_info", false, "Aegis util.ItemInfo normalizer is unavailable")
    setCapability("buy_search", false, "Aegis buy.Search is unavailable")
    setCapability("market_db", false, "Aegis market database accessors are unavailable")
    setCapability("sell_suggest", false, "Aegis sell.Suggest is unavailable")
    setCapability("sell_posting", false, "Aegis sell posting engine is unavailable")
    setCapability("tooltip_extend", false, "Aegis tooltip.Extend is unavailable")
    return self.capabilities
  end

  setCapability("loaded", A.loaded == true, A.loaded == true and "Aegis ADDON_LOADED completed" or "Aegis has not completed ADDON_LOADED")

  local scan = A.scan
  setCapability("scan_start", scan and type(scan.Start) == "function", "AegisExchange.scan.Start")
  setCapability("scan_control",
    scan and type(scan.IsRunning) == "function" and type(scan.IsPaused) == "function"
      and type(scan.Stop) == "function" and type(scan.GetProgress) == "function",
    "AegisExchange.scan IsRunning/IsPaused/Stop/GetProgress")

  local util = A.util
  setCapability("item_info", util and type(util.ItemInfo) == "function", "AegisExchange.util.ItemInfo")

  local buy = A.buy
  setCapability("category_options",
    buy and type(buy.ClassOptions) == "function" and type(buy.SubclassOptions) == "function"
      and type(buy.SlotOptions) == "function",
    "AegisExchange.buy ClassOptions/SubclassOptions/SlotOptions")
  setCapability("buy_search", buy and type(buy.Search) == "function", "AegisExchange.buy.Search")

  local db = A.db
  setCapability("market_db",
    db and type(db.MarketValue) == "function" and type(db.MinBuyout) == "function",
    "AegisExchange.db MarketValue/MinBuyout")

  local sell = A.sell
  setCapability("sell_suggest", sell and type(sell.Suggest) == "function", "AegisExchange.sell.Suggest")
  setCapability("sell_posting",
    sell and type(sell.StartPosting) == "function" and type(sell.PostingActive) == "function"
      and type(sell.CancelPosting) == "function" and type(sell.CountInBags) == "function"
      and type(sell.MaxStacks) == "function",
    "AegisExchange.sell StartPosting/PostingActive/CancelPosting/CountInBags/MaxStacks")

  local tooltip = A.tooltip
  setCapability("tooltip_extend", tooltip and type(tooltip.Extend) == "function", "AegisExchange.tooltip.Extend")

  return self.capabilities
end

function adapter:HasCapability(name)
  self:RefreshCapabilities()
  return self.capabilities[name] == true
end

function adapter:MinimumWorkbenchReady()
  self:RefreshCapabilities()
  if not self.capabilities.loaded then
    return false, self.capabilityReasons.loaded
  end
  if not self.capabilities.scan_start then
    return false, self.capabilityReasons.scan_start
  end
  if not self.capabilities.scan_control then
    return false, self.capabilityReasons.scan_control
  end
  if not self.capabilities.category_options then
    return false, self.capabilityReasons.category_options
  end
  if not self.capabilities.item_info then
    return false, self.capabilityReasons.item_info
  end
  return true, "Aegis scan/category/item-info capabilities detected"
end

local function findExactOption(options, wanted)
  if not options or not wanted or wanted == "" then
    return nil
  end

  local needle = lower(wanted)
  local i = 1
  while i <= table.getn(options) do
    local option = options[i]
    if option and lower(option.text) == needle then
      return option.value, option.text
    end
    i = i + 1
  end
  return nil
end

function adapter:ResolveAuctionFilters(target)
  local A = self:GetAegis()
  if not A or not A.buy then
    return nil, "Aegis buy helpers unavailable"
  end

  local ok, readyReason = self:MinimumWorkbenchReady()
  if not ok then
    return nil, readyReason
  end

  local classOk, classOptions = pcall(A.buy.ClassOptions)
  if not classOk then
    return nil, "Aegis ClassOptions error: " .. tostring(classOptions)
  end
  local classIndex, className = findExactOption(classOptions, target.itemType)
  if not classIndex then
    return nil, "AH class not resolved for item type: " .. tostring(target.itemType)
  end

  local subOk, subOptions = pcall(A.buy.SubclassOptions, classIndex)
  if not subOk then
    return nil, "Aegis SubclassOptions error: " .. tostring(subOptions)
  end
  local subclassIndex, subclassName = findExactOption(subOptions, target.itemSubType)
  if not subclassIndex then
    return nil, "AH subclass not resolved for item subtype: " .. tostring(target.itemSubType)
  end

  local slotIndex, slotName
  if target.equipLoc and target.equipLoc ~= "" then
    local localizedSlot = OT:GetGlobal(target.equipLoc)
    if localizedSlot then
      local slotOk, slotOptions = pcall(A.buy.SlotOptions, classIndex, subclassIndex)
      if not slotOk then
        return nil, "Aegis SlotOptions error: " .. tostring(slotOptions)
      end
      slotIndex, slotName = findExactOption(slotOptions, localizedSlot)
    end
    if not slotIndex then
      return nil, "AH equipment slot not resolved for: " .. tostring(target.equipLoc)
    end
  end

  return {
    class = classIndex,
    className = className or target.itemType,
    subclass = subclassIndex,
    subclassName = subclassName or target.itemSubType,
    invType = slotIndex,
    slotName = slotName,
  }
end

function adapter:IsAuctionHouseOpen()
  -- Aegis deliberately hides the stock AuctionFrame while keeping the server
  -- AH session alive. Treat either visible frontend as an open AH session.
  -- Do not use CanSendAuctionQuery here: throttling can make it false while
  -- the AH is perfectly open.
  local A = self:GetAegis()
  local aegisFrame = A and A.ui and A.ui.frame or OT:GetGlobal("AegisExchangeFrame")
  if aegisFrame and aegisFrame.IsVisible then
    local ok, visible = pcall(function() return aegisFrame:IsVisible() end)
    if ok and visible then return true end
  end

  local frame = OT:GetGlobal("AuctionFrame")
  if frame and frame.IsVisible then
    local ok, visible = pcall(function() return frame:IsVisible() end)
    if ok and visible then return true end
  end
  return false
end

function adapter:IsQueryBusy()
  local A = self:GetAegis()
  if not A then
    return true, "Aegis is unavailable"
  end

  if self.activeOwner then
    return true, "OctoTweaks owns an Aegis scan: " .. tostring(self.activeOwner)
  end

  if A.scan then
    if type(A.scan.IsRunning) == "function" then
      local okRunning, running = pcall(A.scan.IsRunning)
      if not okRunning then return true, "Aegis IsRunning error: " .. tostring(running) end
      if running then return true, "Aegis scan is running" end
    end
    if type(A.scan.IsPaused) == "function" then
      local okPaused, paused = pcall(A.scan.IsPaused)
      if not okPaused then return true, "Aegis IsPaused error: " .. tostring(paused) end
      if paused then return true, "Aegis scan is paused; resume or stop it before Market Workbench" end
    end
  end

  if A.buy and A.buy.state and A.buy.state.phase and A.buy.state.phase ~= "idle" then
    return true, "Aegis Buy search is active"
  end

  if A.sell and type(A.sell.PostingActive) == "function" then
    local okPosting, posting = pcall(A.sell.PostingActive)
    if not okPosting then return true, "Aegis PostingActive error: " .. tostring(posting) end
    if posting then return true, "Aegis posting is active" end
  end

  return false, "AH query channel is idle"
end


function adapter:ReadVisiblePage(options, target)
  options = options or {}
  local rows = {}
  if not GetNumAuctionItems or not GetAuctionItemInfo then
    return rows
  end

  local numOnPage = GetNumAuctionItems("list")
  local i = 1
  while i <= (numOnPage or 0) do
    local name, texture, count, quality, canUse, level, minBid, minInc,
      buyout, bidAmount, highBidder, owner = GetAuctionItemInfo("list", i)
    if name then
      count = count or 1
      local link = GetAuctionItemLink and GetAuctionItemLink("list", i) or nil
      local itemId = self:ItemIdFromLink(link)
      local accept = true
      if options.buyoutOnly and (not buyout or buyout <= 0) then
        accept = false
      end
      if options.exactQuality and target and target.quality ~= nil and quality ~= target.quality then
        accept = false
      end
      if accept then
        local timeLeft
        if GetAuctionItemTimeLeft then
          local okTime, value = pcall(GetAuctionItemTimeLeft, "list", i)
          if okTime then timeLeft = value end
        end
        table.insert(rows, {
          index = i,
          itemId = itemId,
          name = name,
          link = link,
          texture = texture,
          count = count,
          quality = quality,
          canUse = canUse,
          level = level,
          minBid = minBid or 0,
          minInc = minInc or 0,
          buyout = buyout or 0,
          unit = (buyout and buyout > 0) and math.floor(buyout / count) or nil,
          bidAmount = bidAmount or 0,
          highBidder = highBidder,
          owner = owner,
          timeLeft = timeLeft,
        })
      end
    end
    i = i + 1
  end
  return rows
end

function adapter:StartSimilarScan(target, levelRange, options, callbacks)
  options = options or {}
  callbacks = callbacks or {}

  local ready, why = self:MinimumWorkbenchReady()
  if not ready then
    return false, why
  end
  if not self:IsAuctionHouseOpen() then
    return false, "open the Auction House before running a Similar Search"
  end

  local busy, busyReason = self:IsQueryBusy()
  if busy then
    return false, busyReason
  end

  local filters, filterReason = self:ResolveAuctionFilters(target)
  if not filters then
    return false, filterReason
  end

  local req = tonumber(target.requiredLevel) or 0
  local range = tonumber(levelRange) or 0
  if range < 0 then range = 0 end
  range = math.floor(range)
  local minLevel, maxLevel
  if req > 0 then
    minLevel = req - range
    if minLevel < 0 then minLevel = 0 end
    maxLevel = req + range
  end

  local query = {
    minLevel = minLevel and tostring(minLevel) or "",
    maxLevel = maxLevel and tostring(maxLevel) or "",
    class = filters.class,
    subclass = filters.subclass,
    invType = filters.invType,
  }
  if options.exactQuality then
    query.quality = target.quality
  end

  local A = self:GetAegis()
  self.activeOwner = "market_workbench"

  local wrapped = {
    onPage = function(page, totalPages)
      local readOk, pageRows = pcall(function()
        return adapter:ReadVisiblePage(options, target)
      end)
      if not readOk then
        adapter.lastError = "visible-page read error: " .. tostring(pageRows)
        OT:Print("aegis.integration: " .. adapter.lastError)
        return
      end
      if callbacks.onRows then
        local cbOk, cbErr = pcall(function() callbacks.onRows(pageRows, page, totalPages) end)
        if not cbOk then
          adapter.lastError = "Workbench onRows error: " .. tostring(cbErr)
          OT:Print("aegis.integration: " .. adapter.lastError)
        end
      end
      if callbacks.onPage then
        local cbOk, cbErr = pcall(function() callbacks.onPage(page, totalPages) end)
        if not cbOk then
          adapter.lastError = "Workbench onPage error: " .. tostring(cbErr)
          OT:Print("aegis.integration: " .. adapter.lastError)
        end
      end
    end,
    onComplete = function(stats)
      adapter.activeOwner = nil
      if callbacks.onComplete then
        local cbOk, cbErr = pcall(function() callbacks.onComplete(stats) end)
        if not cbOk then
          adapter.lastError = "Workbench onComplete error: " .. tostring(cbErr)
          OT:Print("aegis.integration: " .. adapter.lastError)
        end
      end
    end,
  }

  local callOk, err = pcall(A.scan.Start, query, wrapped)
  if not callOk then
    self.activeOwner = nil
    return false, "Aegis scan.Start error: " .. tostring(err)
  end

  local summary = tostring(filters.className) .. " / " .. tostring(filters.subclassName)
  if filters.slotName then
    summary = summary .. " / " .. tostring(filters.slotName)
  end
  if minLevel and maxLevel then
    summary = summary .. " / level " .. tostring(minLevel) .. "-" .. tostring(maxLevel)
  else
    summary = summary .. " / level any"
  end
  if options.exactQuality then summary = summary .. " / exact quality" end
  if options.buyoutOnly then summary = summary .. " / buyout only" end

  return true, summary
end

function adapter:CancelOwnedScan()
  if self.activeOwner ~= "market_workbench" then
    return false, "no Market Workbench scan is active"
  end

  local A = self:GetAegis()
  if not A or not A.scan or type(A.scan.Stop) ~= "function" then
    return false, "Aegis scan.Stop unavailable"
  end

  local stopOk, stopErr = pcall(A.scan.Stop)
  if not stopOk then
    return false, "Aegis scan.Stop error: " .. tostring(stopErr)
  end
  self.activeOwner = nil
  return true, "Market Workbench scan stopped"
end

function adapter:GetScanProgress()
  local A = self:GetAegis()
  if A and A.scan and type(A.scan.GetProgress) == "function" then
    local ok, progress = pcall(A.scan.GetProgress)
    if ok then return progress end
  end
  return nil
end

local function looksLikeTexturePath(value)
  if type(value) ~= "string" then return false end
  local text = lower(value)
  return string.sub(text, 1, 10) == "interface\\"
    or string.sub(text, 1, 10) == "interface/"
end

local function looksLikeEquipLoc(value)
  return type(value) == "string" and string.sub(value, 1, 8) == "INVTYPE_"
end

local function itemInfoLooksSane(info)
  if type(info) ~= "table" or not info.name then return false end
  if type(info.type) ~= "string" or type(info.subType) ~= "string" then return false end
  -- Runtime on Octo/Aegis 1.20.2 exposed a shifted tuple where the Aegis
  -- normalizer returned INVTYPE_FEET as `type` and the icon path as `subType`.
  if looksLikeEquipLoc(info.type) then return false end
  if looksLikeTexturePath(info.type) or looksLikeTexturePath(info.subType) then return false end
  if info.equipLoc and info.equipLoc ~= "" and not looksLikeEquipLoc(info.equipLoc) then
    return false
  end
  return true
end

function adapter:NormalizeClientItemInfo(link)
  if not GetItemInfo or not link then return nil end

  local r = { GetItemInfo(link) }
  local n = table.getn(r)
  if n < 1 or not r[1] then return nil end

  -- Anchor on texture/equipLoc instead of "last numeric return". Octo's
  -- runtime tuple can contain an additional numeric value after the texture,
  -- which makes Aegis 1.20.2's last-number heuristic shift every field.
  local textureIndex
  local equipIndex
  local i = 4
  while i <= n do
    if looksLikeTexturePath(r[i]) then
      textureIndex = i
      equipIndex = i - 1
      break
    end
    i = i + 1
  end

  if not equipIndex then
    i = 4
    while i <= n do
      if looksLikeEquipLoc(r[i]) then
        equipIndex = i
        textureIndex = i + 1
        break
      end
      i = i + 1
    end
  end

  if not equipIndex or equipIndex < 7 then
    return { name = r[1], link = r[2], quality = r[3] }
  end

  local stackIndex = equipIndex - 1
  local subTypeIndex = stackIndex - 1
  local typeIndex = stackIndex - 2
  local minLevelIndex = stackIndex - 3
  if minLevelIndex < 4 then
    return { name = r[1], link = r[2], quality = r[3] }
  end

  local out = {
    name = r[1],
    link = r[2],
    quality = r[3],
    minLevel = r[minLevelIndex],
    type = r[typeIndex],
    subType = r[subTypeIndex],
    stackCount = r[stackIndex],
    equipLoc = r[equipIndex],
    texture = textureIndex and r[textureIndex] or nil,
  }

  -- Later-client layouts insert itemLevel immediately before minLevel. Keep it
  -- when present, but never depend on it for Similar Search.
  if minLevelIndex > 4 and type(r[minLevelIndex - 1]) == "number" then
    out.itemLevel = r[minLevelIndex - 1]
  end
  return out
end

function adapter:GetItemInfo(link)
  local A = self:GetAegis()
  local aegisInfo
  if A and A.util and type(A.util.ItemInfo) == "function" then
    local ok, info = pcall(A.util.ItemInfo, link)
    if ok then
      aegisInfo = info
      if itemInfoLooksSane(info) then return info end
    else
      self.lastError = "Aegis util.ItemInfo error: " .. tostring(info)
    end
  end

  local rawInfo = self:NormalizeClientItemInfo(link)
  if itemInfoLooksSane(rawInfo) then
    if aegisInfo then
      self.lastItemInfoFallback = "Aegis item-info tuple was shifted; used client texture/equipLoc anchor"
    end
    return rawInfo
  end
  return rawInfo or aegisInfo
end

local function linkName(link)
  if type(link) ~= "string" then return nil end
  local _, _, name = string.find(link, "%[([^%]]+)%]")
  return name
end

function adapter:WarmBagItem(bag, slot)
  if not CreateFrame or not UIParent then
    return false, "tooltip warming unavailable"
  end

  if not self.itemWarmTooltip then
    local okCreate, tooltip = pcall(CreateFrame, "GameTooltip",
      "OctoTweaksAegisItemWarmTooltip", UIParent, "GameTooltipTemplate")
    if okCreate then
      self.itemWarmTooltip = tooltip
    else
      return false, "could not create item warming tooltip: " .. tostring(tooltip)
    end
  end

  local tooltip = self.itemWarmTooltip
  if not tooltip or type(tooltip.SetBagItem) ~= "function" then
    return false, "tooltip SetBagItem unavailable"
  end

  local okWarm, warmErr = pcall(function()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:ClearLines()
    tooltip:SetBagItem(bag, slot)
    tooltip:Hide()
  end)
  if not okWarm then
    return false, "bag tooltip warm error: " .. tostring(warmErr)
  end
  return true, "bag tooltip requested"
end

function adapter:GetBagItemInfo(bag, slot)
  if not GetContainerItemLink or not GetContainerItemInfo then
    return nil, "required bag APIs unavailable"
  end

  local link = GetContainerItemLink(bag, slot)
  if not link then
    return nil, "no item found in bag " .. tostring(bag) .. " slot " .. tostring(slot)
  end

  local texture, count = GetContainerItemInfo(bag, slot)
  local itemId = self:ItemIdFromLink(link)
  local info = self:GetItemInfo(link)
  if (not info or not info.name or not info.type or not info.subType) and itemId then
    local alternate = self:GetItemInfo(itemId)
    if alternate then info = alternate end
  end

  if not info or not info.name or not info.type or not info.subType then
    self:WarmBagItem(bag, slot)
    info = self:GetItemInfo(link)
    if (not info or not info.name or not info.type or not info.subType) and itemId then
      local alternate = self:GetItemInfo(itemId)
      if alternate then info = alternate end
    end
  end

  local name = info and info.name or linkName(link)
  local ready = info and info.name and info.type and info.subType and true or false
  return {
    bag = bag,
    slot = slot,
    itemId = itemId,
    link = (info and info.link) or link,
    name = name,
    texture = (info and info.texture) or texture,
    count = count or 1,
    info = info,
    ready = ready,
  }, ready and "item metadata ready" or "item metadata pending client cache"
end

local function probeValue(value)
  if value == nil then return "nil" end
  local text = tostring(value)
  if string.len(text) > 80 then
    text = string.sub(text, 1, 77) .. "..."
  end
  return type(value) .. ":" .. text
end

function adapter:PrintBagItemProbe(bag, slot)
  bag = tonumber(bag)
  slot = tonumber(slot)
  if not bag or not slot then
    OT:Print("Aegis item probe: bag and slot must be numeric")
    return
  end

  local link = GetContainerItemLink and GetContainerItemLink(bag, slot) or nil
  local itemId = self:ItemIdFromLink(link)
  OT:Print("Aegis item probe: bag=" .. tostring(bag) .. " slot=" .. tostring(slot)
    .. " itemId=" .. tostring(itemId) .. " link=" .. tostring(link))

  local before = self:GetItemInfo(link)
  OT:Print("  normalized before warm: " .. tostring(before and before.name or "nil")
    .. " type=" .. tostring(before and before.type or "nil")
    .. " subtype=" .. tostring(before and before.subType or "nil")
    .. " equip=" .. tostring(before and before.equipLoc or "nil"))

  if GetItemInfo and link then
    local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 = GetItemInfo(link)
    OT:Print("  raw 1-5: " .. probeValue(r1) .. " | " .. probeValue(r2) .. " | "
      .. probeValue(r3) .. " | " .. probeValue(r4) .. " | " .. probeValue(r5))
    OT:Print("  raw 6-10: " .. probeValue(r6) .. " | " .. probeValue(r7) .. " | "
      .. probeValue(r8) .. " | " .. probeValue(r9) .. " | " .. probeValue(r10))
    OT:Print("  raw 11-12: " .. probeValue(r11) .. " | " .. probeValue(r12))
  end

  local warmed, warmReason = self:WarmBagItem(bag, slot)
  local after = self:GetItemInfo(link)
  OT:Print("  warm: " .. tostring(warmed) .. " (" .. tostring(warmReason) .. ")")
  OT:Print("  normalized after warm: " .. tostring(after and after.name or "nil")
    .. " type=" .. tostring(after and after.type or "nil")
    .. " subtype=" .. tostring(after and after.subType or "nil")
    .. " equip=" .. tostring(after and after.equipLoc or "nil"))
end

local function bareItemHyperlink(link, itemId)
  if type(link) == "string" then
    if string.sub(link, 1, 5) == "item:" then
      return link
    end
    local _, _, payload = string.find(link, "|H(item:[^|]+)|h")
    if payload then return payload end
    local _, _, loose = string.find(link, "(item:[^|]+)")
    if loose then return loose end
  end
  if itemId then
    return "item:" .. tostring(itemId) .. ":0:0:0"
  end
  return nil
end

-- Display a Workbench listing tooltip without trusting a full coloured chat
-- hyperlink. Some vanilla 1.12 clients throw "Unknown link type" when their
-- native GameTooltip:SetHyperlink receives |c...|Hitem:...|h...|h|r rather
-- than the bare item: payload. Prefer the live AH row when it is still valid,
-- then fall back to a bare item hyperlink, and finally to the row name.
function adapter:ShowListingTooltip(owner, row)
  if not owner or not row or not GameTooltip then return false end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")

  local A = self:GetAegis()
  local shown = false
  if row.index and GameTooltip.SetAuctionItem and A and A.buy
      and type(A.buy.Verify) == "function" then
    local okVerify, valid = pcall(A.buy.Verify, row)
    if okVerify and valid then
      local okAuction = pcall(function()
        GameTooltip:SetAuctionItem("list", row.index)
      end)
      if okAuction then shown = true end
    end
  end

  if not shown and GameTooltip.SetHyperlink then
    local payload = bareItemHyperlink(row.link, row.itemId)
    if payload then
      local okLink = pcall(function()
        GameTooltip:SetHyperlink(payload)
      end)
      if okLink then shown = true end
    end
  end

  if not shown and GameTooltip.SetText then
    GameTooltip:SetText(row.name or "")
    shown = true
  end
  if shown and GameTooltip.Show then GameTooltip:Show() end
  return shown
end

function adapter:IsPostingActive()
  local A = self:GetAegis()
  if not A or not A.sell or type(A.sell.PostingActive) ~= "function" then
    return false
  end
  local ok, active = pcall(A.sell.PostingActive)
  return ok and active and true or false
end

function adapter:GetPostAvailability(itemId, stackSize)
  local A = self:GetAegis()
  if not A or not A.sell then return nil, "Aegis Sell is unavailable" end
  if not self:HasCapability("sell_posting") then
    return nil, self.capabilityReasons.sell_posting
  end
  stackSize = math.floor(tonumber(stackSize) or 0)
  if stackSize < 1 then return nil, "stack size must be at least 1" end

  local okCount, total = pcall(A.sell.CountInBags, itemId)
  if not okCount then return nil, "Aegis CountInBags error: " .. tostring(total) end
  local okStacks, stacks = pcall(A.sell.MaxStacks, itemId, stackSize)
  if not okStacks then return nil, "Aegis MaxStacks error: " .. tostring(stacks) end
  return {
    total = tonumber(total) or 0,
    stacks = tonumber(stacks) or 0,
  }
end

function adapter:StartPosting(itemId, itemName, stackSize, numStacks,
                              unitBuyout, unitStart, minutes, callbacks)
  local A = self:GetAegis()
  if not A or not A.sell then return false, "Aegis Sell is unavailable" end
  if not self:IsAuctionHouseOpen() then
    return false, "open the Auction House before posting"
  end
  if not self:HasCapability("sell_posting") then
    return false, self.capabilityReasons.sell_posting
  end

  local busy, busyReason = self:IsQueryBusy()
  if busy then return false, busyReason end

  local safeCallbacks = nil
  if callbacks then
    safeCallbacks = {
      onProgress = function(posted, requested)
        if callbacks.onProgress then
          local ok, err = pcall(callbacks.onProgress, posted, requested)
          if not ok then adapter.lastError = "Workbench post progress callback: " .. tostring(err) end
        end
      end,
      onDone = function(posted, requested, reason)
        if callbacks.onDone then
          local ok, err = pcall(callbacks.onDone, posted, requested, reason)
          if not ok then adapter.lastError = "Workbench post done callback: " .. tostring(err) end
        end
      end,
    }
  end

  local okCall, started, reason = pcall(A.sell.StartPosting,
    itemId, itemName, stackSize, numStacks, unitBuyout, unitStart, minutes, safeCallbacks)
  if not okCall then
    return false, "Aegis StartPosting error: " .. tostring(started)
  end
  if not started then
    return false, tostring(reason or "Aegis refused posting")
  end
  return true, "posting started"
end

function adapter:CancelPosting()
  local A = self:GetAegis()
  if not A or not A.sell or type(A.sell.CancelPosting) ~= "function" then
    return false, "Aegis CancelPosting is unavailable"
  end
  if not self:IsPostingActive() then
    return false, "no Aegis posting job is active"
  end
  local ok, err = pcall(A.sell.CancelPosting)
  if not ok then return false, "Aegis CancelPosting error: " .. tostring(err) end
  return true, "posting cancelled"
end

function adapter:GetMarketData(itemId)
  local A = self:GetAegis()
  if not A or not A.db then
    return nil
  end

  local out = {}
  if type(A.db.MarketValue) == "function" then
    local ok, value = pcall(A.db.MarketValue, itemId)
    if ok then out.market = value end
  end
  if type(A.db.MinBuyout) == "function" then
    local ok, value = pcall(A.db.MinBuyout, itemId)
    if ok then out.minBuyout = value end
  end
  if type(A.db.GetVendor) == "function" then
    local ok, value = pcall(A.db.GetVendor, itemId)
    if ok then out.vendor = value end
  end
  if type(A.db.SeenCount) == "function" then
    local ok, value = pcall(A.db.SeenCount, itemId)
    if ok then out.seen = value end
  end
  return out
end

function adapter:GetSellSuggestion(itemId)
  local A = self:GetAegis()
  if A and A.sell and type(A.sell.Suggest) == "function" then
    local ok, suggestion = pcall(A.sell.Suggest, itemId)
    if ok then return suggestion end
  end
  return nil
end

function adapter:ItemIdFromLink(link)
  local A = self:GetAegis()
  if A and A.util and type(A.util.ItemIdFromLink) == "function" then
    local ok, itemId = pcall(A.util.ItemIdFromLink, link)
    if ok then return itemId end
  end

  if type(link) ~= "string" then return nil end
  local _, _, itemId = string.find(link, "item:(%d+)")
  return itemId and tonumber(itemId) or nil
end

function adapter:PrintDiagnostics()
  self:RefreshCapabilities()
  OT:Print("Aegis adapter: version=" .. tostring(self:GetVersion() or "unknown")
    .. ", loaded=" .. tostring(self.capabilities.loaded))

  local order = {
    "namespace", "loaded", "scan_start", "scan_control", "category_options",
    "item_info", "buy_search", "market_db", "sell_suggest", "sell_posting", "tooltip_extend",
  }
  local i = 1
  while i <= table.getn(order) do
    local name = order[i]
    OT:Print("  " .. name .. " = " .. tostring(self.capabilities[name])
      .. " (" .. tostring(self.capabilityReasons[name]) .. ")")
    i = i + 1
  end

  local version = self:GetVersion()
  if version and self:IsSourceAuditedVersion(version) then
    if version ~= self.testedVersion then
      OT:Print("  NOTE: Aegis " .. tostring(version)
        .. " source was audited from the supplied installed addon; runtime validation is still pending")
    end
  elseif version then
    OT:Print("  WARNING: structurally probed on unaudited Aegis " .. tostring(version)
      .. "; source-audited versions are 1.20.2 and " .. self.testedVersion)
  end
end

local module = {
  id = "aegis.integration",
  category = "compatibility",
  target = "Aegis_Exchange",
  defaultEnabled = true,
  testedVersion = "1.53.16",
  sourceAuditedVersions = "1.20.2, 1.53.16",
}

function module:probe()
  local A = adapter:GetAegis()
  if type(A) ~= "table" then
    return false, "AegisExchange global not found"
  end
  if A.loaded ~= true then
    return false, "AegisExchange has not completed ADDON_LOADED"
  end

  local ok, reason = adapter:MinimumWorkbenchReady()
  if not ok then
    return false, reason
  end
  return true, reason
end

function module:enable()
  adapter:RefreshCapabilities()
  local version = adapter:GetVersion()
  if version and adapter:IsSourceAuditedVersion(version) and version ~= self.testedVersion then
    OT:Print("aegis.integration enabled on source-audited Aegis " .. tostring(version)
      .. "; OctoWoW runtime validation is pending")
  elseif version and not adapter:IsSourceAuditedVersion(version) then
    OT:Print("aegis.integration enabled on structurally compatible but unaudited Aegis "
      .. tostring(version))
  end
  return true, "Aegis capability adapter ready"
end

OT:RegisterModule(module)

SLASH_OCTOTWEAKSAEGIS1 = "/otaegis"
SlashCmdList["OCTOTWEAKSAEGIS"] = function(msg)
  msg = string.lower(msg or "")
  if msg == "" or msg == "status" or msg == "probe" or msg == "caps" then
    adapter:PrintDiagnostics()
    return
  end
  OT:Print("Usage: /otaegis [status|probe|caps]")
end
