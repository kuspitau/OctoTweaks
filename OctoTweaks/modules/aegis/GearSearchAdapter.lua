--[[
Aegis Gear Search adapter helpers.

Part of aegis.integration. This file owns the Gear Search access to Aegis'
version-sensitive Buy category helpers and paced scanner. The feature module
itself consumes these OctoTweaks.Aegis methods and never reaches into
AegisExchange directly.
]]

local OT = OctoTweaks
local adapter = OT.Aegis

if not adapter then
  return
end

local function localized(name, fallback)
  if name then
    local value = OT:GetGlobal(name)
    if type(value) == "string" and value ~= "" then return value end
  end
  return fallback
end

local function lower(value)
  if type(value) ~= "string" then return "" end
  return string.lower(value)
end

local function findExactOption(options, wanted)
  if not options or not wanted then return nil end
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

local function queryKey(classIndex, subclassIndex)
  return tostring(classIndex or "") .. ":" .. tostring(subclassIndex or "")
end

function adapter:BuildGearSearchQueries(gearKinds, minLevel, maxLevel)
  local A = self:GetAegis()
  if not A or not A.buy or type(A.buy.ClassOptions) ~= "function"
      or type(A.buy.SubclassOptions) ~= "function" then
    return nil, "Aegis Buy category helpers unavailable"
  end

  local okClasses, classOptions = pcall(A.buy.ClassOptions)
  if not okClasses then
    return nil, "Aegis ClassOptions error: " .. tostring(classOptions)
  end

  local queries = {}
  local seen = {}
  local i = 1
  while gearKinds and i <= table.getn(gearKinds) do
    local kind = gearKinds[i]
    local className = localized(kind.classGlobal, kind.classFallback)
    local classIndex, resolvedClass = findExactOption(classOptions, className)
    if not classIndex then
      return nil, "AH class not resolved for Gear Search: " .. tostring(className)
    end

    local okSubs, subOptions = pcall(A.buy.SubclassOptions, classIndex)
    if not okSubs then
      return nil, "Aegis SubclassOptions error for " .. tostring(resolvedClass or className)
        .. ": " .. tostring(subOptions)
    end

    if kind.allSubclasses then
      local j = 1
      while subOptions and j <= table.getn(subOptions) do
        local option = subOptions[j]
        if option and option.value ~= nil then
          local key = queryKey(classIndex, option.value)
          if not seen[key] then
            seen[key] = true
            table.insert(queries, {
              minLevel = minLevel and tostring(minLevel) or "",
              maxLevel = maxLevel and tostring(maxLevel) or "",
              class = classIndex,
              subclass = option.value,
              invType = nil,
              _otClassName = resolvedClass or className,
              _otSubclassName = option.text,
            })
          end
        end
        j = j + 1
      end
    else
      local subtype = localized(kind.subtypeGlobal, kind.subtypeFallback)
      local subclassIndex = findExactOption(subOptions, subtype)
      if not subclassIndex then
        return nil, "AH subclass not resolved for Gear Search: " .. tostring(subtype)
      end
      local key = queryKey(classIndex, subclassIndex)
      if not seen[key] then
        seen[key] = true
        table.insert(queries, {
          minLevel = minLevel and tostring(minLevel) or "",
          maxLevel = maxLevel and tostring(maxLevel) or "",
          class = classIndex,
          subclass = subclassIndex,
          invType = nil,
          _otClassName = resolvedClass or className,
          _otSubclassName = subtype,
        })
      end
    end
    i = i + 1
  end

  if table.getn(queries) == 0 then
    return nil, "select at least one gear category"
  end
  return queries, tostring(table.getn(queries)) .. " Aegis gear categor"
    .. (table.getn(queries) == 1 and "y" or "ies") .. " resolved"
end

function adapter:ReadGearSearchPage()
  local rows = {}
  if not GetNumAuctionItems or not GetAuctionItemInfo then return rows end

  -- Queries built by OctoTweaks carry display-only class/subclass names. Aegis
  -- keeps the current query table in scanner state, so preserving those names
  -- here gives Gear Search a reliable type fallback even when GetItemInfo is
  -- still cold for an auction result. Extra query fields are ignored by the
  -- native QueryAuctionItems call.
  local A = self:GetAegis()
  local activeQuery = A and A.scan and A.scan.state and A.scan.state.query or nil
  local scanClassName = activeQuery and activeQuery._otClassName or nil
  local scanSubtypeName = activeQuery and activeQuery._otSubclassName or nil

  local count = GetNumAuctionItems("list") or 0
  local i = 1
  while i <= count do
    local name, texture, stackCount, quality, canUse, level, minBid, minInc,
      buyout, bidAmount, highBidder, owner = GetAuctionItemInfo("list", i)
    if name and buyout and buyout > 0 then
      stackCount = stackCount or 1
      local link = GetAuctionItemLink and GetAuctionItemLink("list", i) or nil
      table.insert(rows, {
        index = i,
        itemId = self:ItemIdFromLink(link),
        name = name,
        link = link,
        texture = texture,
        count = stackCount,
        quality = quality,
        canUse = canUse,
        level = level,
        minBid = minBid or 0,
        minInc = minInc or 0,
        buyout = buyout,
        unit = math.floor(buyout / stackCount),
        bidAmount = bidAmount or 0,
        highBidder = highBidder,
        owner = owner,
        scanClassName = scanClassName,
        scanSubtypeName = scanSubtypeName,
      })
    end
    i = i + 1
  end
  return rows
end

function adapter:StartGearSearchScan(queries, callbacks)
  callbacks = callbacks or {}

  local ready, readyReason = self:MinimumWorkbenchReady()
  if not ready then return false, readyReason end
  if not self:IsAuctionHouseOpen() then
    return false, "open the Auction House before Gear Search"
  end

  local busy, busyReason = self:IsQueryBusy()
  if busy then return false, busyReason end

  local A = self:GetAegis()
  if not A or not A.scan or type(A.scan.Start) ~= "function" then
    return false, "Aegis scan.Start unavailable"
  end

  self.activeOwner = "gear_search"
  local wrapped = {
    onPage = function(page, totalPages)
      local okRows, rows = pcall(function() return adapter:ReadGearSearchPage() end)
      if not okRows then
        adapter.lastError = "Gear Search page read error: " .. tostring(rows)
        OT:Print("aegis.integration: " .. adapter.lastError)
        return
      end
      if callbacks.onRows then
        local ok, err = pcall(function() callbacks.onRows(rows, page, totalPages) end)
        if not ok then
          adapter.lastError = "Gear Search onRows error: " .. tostring(err)
          OT:Print("aegis.integration: " .. adapter.lastError)
        end
      end
      if callbacks.onPage then
        local ok, err = pcall(function() callbacks.onPage(page, totalPages) end)
        if not ok then
          adapter.lastError = "Gear Search onPage error: " .. tostring(err)
          OT:Print("aegis.integration: " .. adapter.lastError)
        end
      end
    end,
    onComplete = function(stats)
      adapter.activeOwner = nil
      if callbacks.onComplete then
        local ok, err = pcall(function() callbacks.onComplete(stats) end)
        if not ok then
          adapter.lastError = "Gear Search onComplete error: " .. tostring(err)
          OT:Print("aegis.integration: " .. adapter.lastError)
        end
      end
    end,
  }

  local ok, err = pcall(A.scan.Start, queries, wrapped)
  if not ok then
    self.activeOwner = nil
    return false, "Aegis scan.Start error: " .. tostring(err)
  end
  return true, "Aegis Gear Search scan started (" .. tostring(table.getn(queries))
    .. " categor" .. (table.getn(queries) == 1 and "y" or "ies") .. ")"
end

function adapter:CancelGearSearchScan()
  if self.activeOwner ~= "gear_search" then
    return false, "no Gear Search scan is active"
  end
  local A = self:GetAegis()
  if not A or not A.scan or type(A.scan.Stop) ~= "function" then
    return false, "Aegis scan.Stop unavailable"
  end
  local ok, err = pcall(A.scan.Stop)
  if not ok then return false, "Aegis scan.Stop error: " .. tostring(err) end
  self.activeOwner = nil
  return true, "Gear Search scan stopped"
end
