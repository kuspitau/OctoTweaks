--[[
Module: aegis.gear_search
Category: feature
Target: Aegis: Exchange
Default: enabled
Tested/source-audited UI seam: Aegis 1.53.29; historical UI seam 1.20.2.

Purpose:
Advanced Auction House gear search built on Aegis' paced scanner. Gear Search
scans selected gear categories, parses numeric item stats from tooltips, applies
configurable minimums and a configurable weighted score, and displays sortable
results in its own Aegis sub-tab.

No Aegis file is modified. Aegis owns AH pacing and page traversal; the only
private scanner/UI access is isolated in GearSearchAdapter.lua and the Aegis UI
adapter layer.
]]

local OT = OctoTweaks
local Aegis = OT.Aegis

if not Aegis then
  return
end

local GS = {
  key = "OctoGearSearch",
  label = "Gear Search",
  hostHeight = 640,
  rowsPerPage = 10,
  parsePerFrame = 3,
  maxStatColumns = 8,
  frame = nil,
  panel = nil,
  resultRows = {},
  headerButtons = {},
  activeStatColumns = {},
  page = 1,
  rawByKey = {},
  rawCount = 0,
  results = {},
  scanActive = false,
  parseActive = false,
  parseQueue = {},
  parseIndex = 1,
  parseFailures = 0,
  parseDriver = nil,
  tooltip = nil,
}
OT.GearSearch = GS

local DEFAULTS = {
  schema = 3,
  cloth = true,
  leather = true,
  mail = true,
  plate = false,
  shields = false,
  misc = false,
  weapons = false,
  slotFilter = "any",
  minLevel = 50,
  maxLevel = 60,
  minQuality = 2,
  maxPriceGold = 0,
  minScore = 0,
  sortKey = "score",
  sortAscending = false,
  activePreset = "Custom",
}

local STAT_DEFS = {
  { key = "heal", label = "Heal", defaultWeight = 1.00 },
  { key = "spellPower", label = "SP", defaultWeight = 0.00 },
  { key = "mp5", label = "MP5", defaultWeight = 8.00 },
  { key = "intellect", label = "Int", defaultWeight = 0.70 },
  { key = "spirit", label = "Spi", defaultWeight = 0.15 },
  { key = "stamina", label = "Sta", defaultWeight = 0.10 },
  { key = "spellCrit", label = "SCrit", defaultWeight = 12.00 },
  { key = "strength", label = "Str", defaultWeight = 0.00 },
  { key = "agility", label = "Agi", defaultWeight = 0.00 },
  { key = "attackPower", label = "AP", defaultWeight = 0.00 },
  { key = "rangedAttackPower", label = "RAP", defaultWeight = 0.00 },
  { key = "hit", label = "Hit", defaultWeight = 0.00 },
  { key = "meleeCrit", label = "Crit", defaultWeight = 0.00 },
  { key = "spellHit", label = "SHit", defaultWeight = 0.00 },
  { key = "defense", label = "Def", defaultWeight = 0.00 },
  { key = "dodge", label = "Dodge", defaultWeight = 0.00 },
  { key = "parry", label = "Parry", defaultWeight = 0.00 },
  { key = "block", label = "Block", defaultWeight = 0.00 },
  { key = "blockValue", label = "BlockV", defaultWeight = 0.00 },
  { key = "armor", label = "Armor", defaultWeight = 0.00 },
}

local STAT_BY_KEY = {}
local statIndex = 1
while statIndex <= table.getn(STAT_DEFS) do
  STAT_BY_KEY[STAT_DEFS[statIndex].key] = STAT_DEFS[statIndex]
  statIndex = statIndex + 1
end

local LEGACY_WEIGHT_FIELDS = {
  heal = "weightHeal",
  mp5 = "weightMp5",
  intellect = "weightInt",
  spirit = "weightSpirit",
  stamina = "weightStamina",
  spellCrit = "weightCrit",
}

local GEAR_KINDS = {
  { setting = "cloth", classGlobal = "ARMOR", classFallback = "Armor", subtypeGlobal = "CLOTH", subtypeFallback = "Cloth" },
  { setting = "leather", classGlobal = "ARMOR", classFallback = "Armor", subtypeGlobal = "LEATHER", subtypeFallback = "Leather" },
  { setting = "mail", classGlobal = "ARMOR", classFallback = "Armor", subtypeGlobal = "MAIL", subtypeFallback = "Mail" },
  { setting = "plate", classGlobal = "ARMOR", classFallback = "Armor", subtypeGlobal = "PLATE", subtypeFallback = "Plate" },
  { setting = "shields", classGlobal = "ARMOR", classFallback = "Armor", subtypeGlobal = nil, subtypeFallback = "Shields" },
  { setting = "misc", classGlobal = "ARMOR", classFallback = "Armor", subtypeGlobal = nil, subtypeFallback = "Miscellaneous" },
  { setting = "weapons", classGlobal = "WEAPON", classFallback = "Weapon", allSubclasses = true },
}

local SLOT_OPTIONS = {
  { key = "any", label = "Any slot" },
  { key = "head", label = "Head", equips = { "INVTYPE_HEAD" } },
  { key = "neck", label = "Neck", equips = { "INVTYPE_NECK" } },
  { key = "shoulder", label = "Shoulders", equips = { "INVTYPE_SHOULDER" } },
  { key = "back", label = "Back", equips = { "INVTYPE_CLOAK" } },
  { key = "chest", label = "Chest", equips = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
  { key = "wrist", label = "Wrist", equips = { "INVTYPE_WRIST" } },
  { key = "hands", label = "Hands", equips = { "INVTYPE_HAND" } },
  { key = "waist", label = "Waist", equips = { "INVTYPE_WAIST" } },
  { key = "legs", label = "Legs", equips = { "INVTYPE_LEGS" } },
  { key = "feet", label = "Feet", equips = { "INVTYPE_FEET" } },
  { key = "finger", label = "Finger", equips = { "INVTYPE_FINGER" } },
  { key = "trinket", label = "Trinket", equips = { "INVTYPE_TRINKET" } },
  { key = "onehand", label = "One-hand", equips = { "INVTYPE_WEAPON" } },
  { key = "twohand", label = "Two-hand", equips = { "INVTYPE_2HWEAPON" } },
  { key = "mainhand", label = "Main hand", equips = { "INVTYPE_WEAPONMAINHAND" } },
  { key = "offhand", label = "Off hand", equips = { "INVTYPE_WEAPONOFFHAND" } },
  { key = "shield", label = "Shield", equips = { "INVTYPE_SHIELD" } },
  { key = "held", label = "Held offhand", equips = { "INVTYPE_HOLDABLE" } },
  { key = "ranged", label = "Ranged", equips = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" } },
  { key = "relic", label = "Relic", equips = { "INVTYPE_RELIC" } },
}

local SLOT_BY_KEY = {}
local SLOT_NAME_BY_EQUIP = {}
local slotIndex = 1
while slotIndex <= table.getn(SLOT_OPTIONS) do
  local option = SLOT_OPTIONS[slotIndex]
  SLOT_BY_KEY[option.key] = option
  if option.equips then
    local j = 1
    while j <= table.getn(option.equips) do
      SLOT_NAME_BY_EQUIP[option.equips[j]] = option.label
      j = j + 1
    end
  end
  slotIndex = slotIndex + 1
end

local PRESET_FIELDS = {
  "cloth", "leather", "mail", "plate", "shields", "misc", "weapons",
  "slotFilter", "minLevel", "maxLevel", "minQuality", "maxPriceGold",
  "minScore",
}

local function defaultWeights()
  local weights = {}
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    local def = STAT_DEFS[i]
    weights[def.key] = def.defaultWeight
    i = i + 1
  end
  return weights
end

local function blankWeights()
  local weights = {}
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    weights[STAT_DEFS[i].key] = 0
    i = i + 1
  end
  return weights
end

local function blankMinimums()
  local minimums = {}
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    minimums[STAT_DEFS[i].key] = 0
    i = i + 1
  end
  return minimums
end

local function restoShownStats()
  local shown = {}
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    shown[STAT_DEFS[i].key] = false
    i = i + 1
  end
  shown.heal = true
  shown.mp5 = true
  shown.intellect = true
  shown.spirit = true
  shown.stamina = true
  shown.spellCrit = true
  return shown
end

local function blankShownStats()
  local shown = {}
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    shown[STAT_DEFS[i].key] = false
    i = i + 1
  end
  return shown
end

local BUILTIN_PRESETS = {
  ["Resto Shaman"] = {
    cloth = true, leather = true, mail = true, plate = false,
    shields = false, misc = false, weapons = false, slotFilter = "any",
    minLevel = 50, maxLevel = 60, minQuality = 2, maxPriceGold = 0,
    minScore = 0,
    weights = defaultWeights(),
    minimums = blankMinimums(),
    shownStats = restoShownStats(),
  },
  ["Blank"] = {
    cloth = false, leather = false, mail = false, plate = false,
    shields = false, misc = false, weapons = false, slotFilter = "any",
    minLevel = 50, maxLevel = 60, minQuality = 2, maxPriceGold = 0,
    minScore = 0,
    weights = blankWeights(),
    minimums = blankMinimums(),
    shownStats = blankShownStats(),
  },
}

local function trim(text)
  text = tostring(text or "")
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  return text
end

local function copyTable(source)
  local out = {}
  local key, value
  for key, value in pairs(source or {}) do out[key] = value end
  return out
end

local function clampNumber(value, minimum, maximum, fallback)
  local n = tonumber(value)
  if n == nil then n = fallback end
  if minimum ~= nil and n < minimum then n = minimum end
  if maximum ~= nil and n > maximum then n = maximum end
  return n
end

local function money(copper)
  copper = tonumber(copper)
  if not copper then return "--" end
  copper = math.floor(copper)
  local gold = math.floor(copper / 10000)
  local silver = math.floor(math.mod(copper, 10000) / 100)
  local coin = math.mod(copper, 100)
  if gold > 0 then return tostring(gold) .. "g" .. tostring(silver) .. "s" end
  if silver > 0 then return tostring(silver) .. "s" .. tostring(coin) .. "c" end
  return tostring(coin) .. "c"
end

local function itemPayload(link)
  if type(link) ~= "string" then return nil end
  local _, _, payload = string.find(link, "|H(item:[^|]+)|h")
  if payload then return payload end
  local _, _, bare = string.find(link, "(item:[^|]+)")
  return bare
end

local function variantKey(row)
  local payload = itemPayload(row and row.link)
  if payload then
    local _, _, itemId, enchantId, randomId = string.find(payload,
      "^item:([%-]?%d+):([%-]?%d*):([%-]?%d*)")
    if itemId then
      return tostring(itemId) .. ":" .. tostring(enchantId or "0")
        .. ":" .. tostring(randomId or "0")
    end
    return payload
  end
  return tostring(row and row.itemId or "?") .. ":" .. tostring(row and row.name or "?")
end

local function captureNumber(text, pattern)
  local _, _, value = string.find(text, pattern)
  if value then return tonumber(value) end
  return nil
end

local function firstNumber(text, patterns)
  local i = 1
  while i <= table.getn(patterns) do
    local value = captureNumber(text, patterns[i])
    if value then return value end
    i = i + 1
  end
  return nil
end

local function addStat(stats, key, value)
  if value and value > 0 then stats[key] = (stats[key] or 0) + value end
end

local function parseStatLine(stats, line)
  local text = string.lower(line or "")
  local value

  value = firstNumber(text, { "%+(%d+)%s+strength", "strength%s*%+(%d+)" })
  addStat(stats, "strength", value)
  value = firstNumber(text, { "%+(%d+)%s+agility", "agility%s*%+(%d+)" })
  addStat(stats, "agility", value)
  value = firstNumber(text, { "%+(%d+)%s+stamina", "stamina%s*%+(%d+)" })
  addStat(stats, "stamina", value)
  value = firstNumber(text, { "%+(%d+)%s+intellect", "intellect%s*%+(%d+)" })
  addStat(stats, "intellect", value)
  value = firstNumber(text, { "%+(%d+)%s+spirit", "spirit%s*%+(%d+)" })
  addStat(stats, "spirit", value)

  value = firstNumber(text, {
    "increases healing done by spells and effects by up to (%d+)",
    "increases healing done by magical spells and effects by up to (%d+)",
    "healing spells by up to (%d+)",
    "%+(%d+)%s+healing",
    "healing%s*%+(%d+)",
  })
  addStat(stats, "healingOnly", value)

  value = firstNumber(text, {
    "increases damage and healing done by magical spells and effects by up to (%d+)",
    "increases damage and healing done by spells and effects by up to (%d+)",
    "healing and damage spells by up to (%d+)",
    "%+(%d+)%s+spell damage and healing",
  })
  addStat(stats, "spellPower", value)

  value = firstNumber(text, {
    "restores (%d+) mana per 5 sec",
    "restores (%d+) mana every 5 sec",
    "(%d+)%s+mana%s+per%s+5%s+sec",
    "(%d+)%s+mana%s+every%s+5%s+sec",
  })
  addStat(stats, "mp5", value)

  value = firstNumber(text, {
    "increases ranged attack power by (%d+)",
    "%+(%d+)%s+ranged attack power",
  })
  addStat(stats, "rangedAttackPower", value)

  value = firstNumber(text, {
    "increases attack power by (%d+)",
    "%+(%d+)%s+attack power",
  })
  addStat(stats, "attackPower", value)

  value = firstNumber(text, {
    "chance to hit with spells by (%d+)%%",
    "spell hit chance by (%d+)%%",
  })
  addStat(stats, "spellHit", value)

  value = firstNumber(text, {
    "chance to hit by (%d+)%%",
  })
  if not string.find(text, "with spells") then addStat(stats, "hit", value) end

  value = firstNumber(text, {
    "critical strike with spells by (%d+)%%",
    "spell critical strike chance by (%d+)%%",
    "chance to critically hit with spells by (%d+)%%",
  })
  addStat(stats, "spellCrit", value)

  value = firstNumber(text, {
    "chance to get a critical strike by (%d+)%%",
    "critical strike chance by (%d+)%%",
  })
  if not string.find(text, "with spells") then addStat(stats, "meleeCrit", value) end

  value = firstNumber(text, {
    "increased defense%s*%+(%d+)",
    "defense%s*%+(%d+)",
    "increases defense by (%d+)",
  })
  addStat(stats, "defense", value)

  value = firstNumber(text, { "chance to dodge.-by (%d+)%%" })
  addStat(stats, "dodge", value)
  value = firstNumber(text, { "chance to parry.-by (%d+)%%" })
  addStat(stats, "parry", value)
  value = firstNumber(text, { "chance to block.-by (%d+)%%" })
  addStat(stats, "block", value)

  value = firstNumber(text, {
    "block value of your shield by (%d+)",
    "shield block value by (%d+)",
  })
  addStat(stats, "blockValue", value)

  value = firstNumber(text, {
    "^(%d+)%s+armor$",
    "%+(%d+)%s+armor$",
  })
  addStat(stats, "armor", value)
end

local function ensureSettings()
  if OT.EnsureSavedVariables then OT:EnsureSavedVariables() end
  if not OctoTweaksDB then OctoTweaksDB = {} end
  if not OctoTweaksDB.gearSearch then OctoTweaksDB.gearSearch = {} end
  local db = OctoTweaksDB.gearSearch

  local key, value
  for key, value in pairs(DEFAULTS) do
    if db[key] == nil then db[key] = value end
  end

  if type(db.weights) ~= "table" then
    db.weights = {}
    local i = 1
    while i <= table.getn(STAT_DEFS) do
      local def = STAT_DEFS[i]
      local legacy = LEGACY_WEIGHT_FIELDS[def.key]
      if legacy and db[legacy] ~= nil then
        db.weights[def.key] = tonumber(db[legacy]) or def.defaultWeight
      else
        db.weights[def.key] = def.defaultWeight
      end
      i = i + 1
    end
  else
    local i = 1
    while i <= table.getn(STAT_DEFS) do
      local def = STAT_DEFS[i]
      if db.weights[def.key] == nil then db.weights[def.key] = def.defaultWeight end
      i = i + 1
    end
  end

  -- Schema 3 generalizes the v1/v2 fixed Heal/Int/MP5 minimums into one
  -- numeric minimum per parsed stat. Preserve the old values on first load.
  if type(db.minimums) ~= "table" then
    db.minimums = blankMinimums()
    if db.minHeal ~= nil then db.minimums.heal = tonumber(db.minHeal) or 0 end
    if db.minInt ~= nil then db.minimums.intellect = tonumber(db.minInt) or 0 end
    if db.minMp5 ~= nil then db.minimums.mp5 = tonumber(db.minMp5) or 0 end
  else
    local i = 1
    while i <= table.getn(STAT_DEFS) do
      local key = STAT_DEFS[i].key
      if db.minimums[key] == nil then db.minimums[key] = 0 end
      i = i + 1
    end
  end

  -- v2 chose visible columns implicitly from non-zero weights/minimums. Freeze
  -- that view into explicit per-preset visibility flags so later weight edits
  -- do not unexpectedly rearrange the table.
  if type(db.shownStats) ~= "table" then
    db.shownStats = blankShownStats()
    local count = 0
    local i = 1
    while i <= table.getn(STAT_DEFS) and count < GS.maxStatColumns do
      local def = STAT_DEFS[i]
      local used = (tonumber(db.weights[def.key]) or 0) > 0
        or (tonumber(db.minimums[def.key]) or 0) > 0
      if used then
        db.shownStats[def.key] = true
        count = count + 1
      end
      i = i + 1
    end
    if count == 0 then db.shownStats = restoShownStats() end
  else
    local i = 1
    local count = 0
    while i <= table.getn(STAT_DEFS) do
      local key = STAT_DEFS[i].key
      db.shownStats[key] = db.shownStats[key] and true or false
      if db.shownStats[key] then
        count = count + 1
        if count > GS.maxStatColumns then db.shownStats[key] = false end
      end
      i = i + 1
    end
  end

  if type(db.presets) ~= "table" then db.presets = {} end
  if not SLOT_BY_KEY[db.slotFilter] then db.slotFilter = "any" end
  db.schema = 3
  return db
end

local function scoreStats(stats, db)
  local score = 0
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    local def = STAT_DEFS[i]
    score = score + (stats[def.key] or 0) * (tonumber(db.weights[def.key]) or 0)
    i = i + 1
  end
  return score
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

local serial = 0
local function createButton(parent, text, x, y, width, height, fn)
  serial = serial + 1
  local button = CreateFrame("Button", "OctoTweaksGearSearchButton" .. serial,
    parent, "UIPanelButtonTemplate")
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:SetWidth(width)
  button:SetHeight(height)
  button:SetText(text)
  button:SetScript("OnClick", fn)
  return button
end

local function createEdit(parent, name, x, y, width)
  local box = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
  box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  box:SetWidth(width)
  box:SetHeight(20)
  box:SetAutoFocus(false)
  box:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  return box
end

local function createCheck(parent, name, label, x, y, labelWidth)
  local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  check:SetWidth(24)
  check:SetHeight(24)
  createLabel(parent, label, x + 24, y - 7, labelWidth or 62)
  return check
end

local function createHeaderButton(parent, name, x, y, width, fn)
  local button = CreateFrame("Button", name, parent)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  button:SetWidth(width)
  button:SetHeight(18)
  button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button.label:SetPoint("LEFT", button, "LEFT", 1, 0)
  button.label:SetWidth(width - 2)
  button.label:SetJustifyH("LEFT")
  button.label:SetTextColor(0.85, 0.85, 0.85)
  button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  button:SetScript("OnClick", fn)
  return button
end

local function createMenu(parent, name, width)
  local menu = CreateFrame("Frame", name, parent)
  menu:SetWidth(width)
  menu:SetHeight(40)
  menu:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 30)
  menu:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  menu:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
  menu.buttons = {}
  menu:Hide()
  return menu
end

function GS:SetStatus(text)
  self.status = tostring(text or "")
  if self.frame and self.frame.status then self.frame.status:SetText(self.status) end
end

function GS:PresetSnapshot(db)
  local snapshot = {}
  local i = 1
  while i <= table.getn(PRESET_FIELDS) do
    local key = PRESET_FIELDS[i]
    snapshot[key] = db[key]
    i = i + 1
  end
  snapshot.weights = copyTable(db.weights)
  snapshot.minimums = copyTable(db.minimums)
  snapshot.shownStats = copyTable(db.shownStats)
  return snapshot
end

function GS:ApplyPresetData(data)
  if type(data) ~= "table" then return false end
  local db = ensureSettings()
  local i = 1
  while i <= table.getn(PRESET_FIELDS) do
    local key = PRESET_FIELDS[i]
    if data[key] ~= nil then db[key] = data[key] end
    i = i + 1
  end

  if type(data.weights) == "table" then
    local j = 1
    while j <= table.getn(STAT_DEFS) do
      local key = STAT_DEFS[j].key
      db.weights[key] = tonumber(data.weights[key]) or 0
      j = j + 1
    end
  end

  if type(data.minimums) == "table" then
    local j = 1
    while j <= table.getn(STAT_DEFS) do
      local key = STAT_DEFS[j].key
      db.minimums[key] = tonumber(data.minimums[key]) or 0
      j = j + 1
    end
  else
    -- Accept v2 saved presets without losing their fixed minimum fields.
    local j = 1
    while j <= table.getn(STAT_DEFS) do
      db.minimums[STAT_DEFS[j].key] = 0
      j = j + 1
    end
    if data.minHeal ~= nil then db.minimums.heal = tonumber(data.minHeal) or 0 end
    if data.minInt ~= nil then db.minimums.intellect = tonumber(data.minInt) or 0 end
    if data.minMp5 ~= nil then db.minimums.mp5 = tonumber(data.minMp5) or 0 end
  end

  if type(data.shownStats) == "table" then
    local count = 0
    local j = 1
    while j <= table.getn(STAT_DEFS) do
      local key = STAT_DEFS[j].key
      local shown = data.shownStats[key] and true or false
      if shown then
        count = count + 1
        if count > self.maxStatColumns then shown = false end
      end
      db.shownStats[key] = shown
      j = j + 1
    end
  else
    -- Recreate the v2 implicit display rule for legacy presets.
    local count = 0
    local j = 1
    while j <= table.getn(STAT_DEFS) do
      local key = STAT_DEFS[j].key
      local shown = ((tonumber(db.weights[key]) or 0) > 0
        or (tonumber(db.minimums[key]) or 0) > 0) and count < self.maxStatColumns
      db.shownStats[key] = shown
      if shown then count = count + 1 end
      j = j + 1
    end
    if count == 0 then db.shownStats = restoShownStats() end
  end
  return true
end

function GS:PresetNames()
  local db = ensureSettings()
  local seen = {}
  local names = {}
  local key
  for key in pairs(BUILTIN_PRESETS) do
    seen[key] = true
    table.insert(names, key)
  end
  for key in pairs(db.presets) do
    if not seen[key] then table.insert(names, key) end
  end
  table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
  return names
end

function GS:LoadPreset(name)
  name = trim(name)
  if name == "" then return false end
  local db = ensureSettings()
  local data = db.presets[name] or BUILTIN_PRESETS[name]
  if not data then
    self:SetStatus("Unknown preset: " .. name)
    return false
  end
  self:ApplyPresetData(data)
  db.activePreset = name
  self:ApplySettingsToUI()
  self:SetStatus("Loaded preset: " .. name .. " (press SEARCH to rescan)")
  return true
end

function GS:SavePreset(name)
  name = trim(name)
  if name == "" or name == "Custom" then
    self:SetStatus("Enter a preset name in the Save as field")
    return false
  end
  local db = self:ReadSettingsFromUI()
  db.presets[name] = self:PresetSnapshot(db)
  db.activePreset = name
  self:ApplySettingsToUI()
  self:SetStatus("Saved preset: " .. name)
  return true
end

function GS:DeletePreset(name)
  name = trim(name)
  local db = ensureSettings()
  if db.presets[name] then
    db.presets[name] = nil
    if db.activePreset == name then db.activePreset = "Custom" end
    self:ApplySettingsToUI()
    self:SetStatus("Deleted saved preset: " .. name)
    return true
  end
  if BUILTIN_PRESETS[name] then
    self:SetStatus("Built-in preset cannot be deleted; delete only removes saved overrides")
    return false
  end
  self:SetStatus("No saved preset named: " .. name)
  return false
end

function GS:PrintPresets()
  local names = self:PresetNames()
  OT:Print("Gear Search presets:")
  local i = 1
  while i <= table.getn(names) do
    local name = names[i]
    local saved = ensureSettings().presets[name] and "saved" or "built-in"
    OT:Print("  " .. name .. " (" .. saved .. ")")
    i = i + 1
  end
end

function GS:StatsSummary(db)
  local shown = 0
  local weighted = 0
  local minimums = 0
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    local key = STAT_DEFS[i].key
    if db.shownStats[key] then shown = shown + 1 end
    if (tonumber(db.weights[key]) or 0) > 0 then weighted = weighted + 1 end
    if (tonumber(db.minimums[key]) or 0) > 0 then minimums = minimums + 1 end
    i = i + 1
  end
  return tostring(shown) .. " shown / " .. tostring(weighted) .. " weighted / "
    .. tostring(minimums) .. " minimums"
end

function GS:ApplySettingsToUI()
  if not self.frame then return end
  local db = ensureSettings()
  local f = self.frame
  f.cloth:SetChecked(db.cloth and 1 or nil)
  f.leather:SetChecked(db.leather and 1 or nil)
  f.mail:SetChecked(db.mail and 1 or nil)
  f.plate:SetChecked(db.plate and 1 or nil)
  f.shields:SetChecked(db.shields and 1 or nil)
  f.misc:SetChecked(db.misc and 1 or nil)
  f.weapons:SetChecked(db.weapons and 1 or nil)
  f.minLevel:SetText(tostring(db.minLevel))
  f.maxLevel:SetText(tostring(db.maxLevel))
  f.minQuality:SetText(tostring(db.minQuality))
  f.maxPrice:SetText(tostring(db.maxPriceGold))
  f.minScore:SetText(tostring(db.minScore))
  if f.slotButton then
    local option = SLOT_BY_KEY[db.slotFilter] or SLOT_BY_KEY.any
    f.slotButton:SetText(option.label .. "  v")
  end
  if f.presetButton then f.presetButton:SetText(tostring(db.activePreset or "Custom") .. "  v") end
  if f.statsSummary then f.statsSummary:SetText(self:StatsSummary(db)) end

  if f.statConfigChecks then
    local i = 1
    while i <= table.getn(STAT_DEFS) do
      local def = STAT_DEFS[i]
      local key = def.key
      if f.statConfigChecks[key] then
        f.statConfigChecks[key]:SetChecked(db.shownStats[key] and 1 or nil)
      end
      if f.statMinBoxes[key] then f.statMinBoxes[key]:SetText(tostring(db.minimums[key] or 0)) end
      if f.statWeightBoxes[key] then f.statWeightBoxes[key]:SetText(tostring(db.weights[key] or 0)) end
      i = i + 1
    end
  end
  self:RefreshColumnLayout()
end

function GS:ReadStatConfigFromUI()
  local db = ensureSettings()
  local f = self.frame
  if not f or not f.statConfigChecks then return db end

  local shownCount = 0
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    local def = STAT_DEFS[i]
    local key = def.key
    local shown = f.statConfigChecks[key]:GetChecked() and true or false
    if shown then
      shownCount = shownCount + 1
      if shownCount > self.maxStatColumns then
        shown = false
        f.statConfigChecks[key]:SetChecked(nil)
      end
    end
    db.shownStats[key] = shown
    db.minimums[key] = clampNumber(f.statMinBoxes[key]:GetText(), 0, nil,
      db.minimums[key] or 0)
    db.weights[key] = clampNumber(f.statWeightBoxes[key]:GetText(), 0, nil,
      db.weights[key] or 0)
    i = i + 1
  end

  if STAT_BY_KEY[db.sortKey] and not db.shownStats[db.sortKey] then
    db.sortKey = "score"
    db.sortAscending = false
  end
  if f.statsSummary then f.statsSummary:SetText(self:StatsSummary(db)) end
  self:RefreshColumnLayout()
  return db
end

function GS:ReadSettingsFromUI()
  if not self.frame then return ensureSettings() end
  local db = ensureSettings()
  local f = self.frame
  db.cloth = f.cloth:GetChecked() and true or false
  db.leather = f.leather:GetChecked() and true or false
  db.mail = f.mail:GetChecked() and true or false
  db.plate = f.plate:GetChecked() and true or false
  db.shields = f.shields:GetChecked() and true or false
  db.misc = f.misc:GetChecked() and true or false
  db.weapons = f.weapons:GetChecked() and true or false
  db.minLevel = math.floor(clampNumber(f.minLevel:GetText(), 0, 99, db.minLevel))
  db.maxLevel = math.floor(clampNumber(f.maxLevel:GetText(), db.minLevel, 99, db.maxLevel))
  db.minQuality = math.floor(clampNumber(f.minQuality:GetText(), 0, 6, db.minQuality))
  db.maxPriceGold = clampNumber(f.maxPrice:GetText(), 0, nil, db.maxPriceGold)
  db.minScore = clampNumber(f.minScore:GetText(), 0, nil, db.minScore)
  self:ReadStatConfigFromUI()
  self:ApplySettingsToUI()
  return db
end

function GS:ResetSettings()
  local db = ensureSettings()
  local key, value
  for key, value in pairs(DEFAULTS) do
    if key ~= "activePreset" then db[key] = value end
  end
  db.weights = defaultWeights()
  db.minimums = blankMinimums()
  db.shownStats = restoShownStats()
  db.activePreset = "Resto Shaman"
  self:ApplySettingsToUI()
  self:SetStatus("Gear Search reset to the Resto Shaman heuristic")
end

function GS:SelectedGearKinds(db)
  local out = {}
  local i = 1
  while i <= table.getn(GEAR_KINDS) do
    local kind = GEAR_KINDS[i]
    if db[kind.setting] then table.insert(out, kind) end
    i = i + 1
  end
  return out
end

function GS:MatchesSlot(equipLoc, slotKey)
  if not slotKey or slotKey == "any" then return true end
  local option = SLOT_BY_KEY[slotKey]
  if not option or not option.equips or not equipLoc then return false end
  local i = 1
  while i <= table.getn(option.equips) do
    if option.equips[i] == equipLoc then return true end
    i = i + 1
  end
  return false
end

function GS:FriendlySlot(equipLoc)
  if not equipLoc or equipLoc == "" then return "--" end
  return SLOT_NAME_BY_EQUIP[equipLoc] or tostring(OT:GetGlobal(equipLoc) or equipLoc)
end

function GS:ResetSearchState()
  self.rawByKey = {}
  self.rawCount = 0
  self.results = {}
  self.page = 1
  self.parseQueue = {}
  self.parseIndex = 1
  self.parseFailures = 0
  self.scanActive = false
  self.parseActive = false
  if self.parseDriver then self.parseDriver:Hide() end
  self:RefreshResults()
end

function GS:OnRows(rows)
  local db = ensureSettings()
  local maxPrice = db.maxPriceGold > 0 and math.floor(db.maxPriceGold * 10000) or nil
  local i = 1
  while rows and i <= table.getn(rows) do
    local row = rows[i]
    local qualityOk = (tonumber(row.quality) or 0) >= db.minQuality
    local priceOk = row.unit and row.unit > 0 and (not maxPrice or row.unit <= maxPrice)
    if row.link and qualityOk and priceOk then
      local key = variantKey(row)
      local existing = self.rawByKey[key]
      if not existing then
        self.rawByKey[key] = row
        self.rawCount = self.rawCount + 1
      elseif row.unit < existing.unit then
        self.rawByKey[key] = row
      end
    end
    i = i + 1
  end
end

function GS:GetTooltip()
  if self.tooltip then return self.tooltip end
  if not CreateFrame or not UIParent then return nil end
  self.tooltip = CreateFrame("GameTooltip", "OctoTweaksGearSearchParseTooltip",
    UIParent, "GameTooltipTemplate")
  return self.tooltip
end

function GS:ReadTooltipLines(link)
  local tip = self:GetTooltip()
  if not tip or not link then return nil end
  local payload = itemPayload(link)
  local ok = false

  tip:SetOwner(UIParent, "ANCHOR_NONE")
  tip:ClearLines()
  if payload and tip.SetHyperlink then ok = pcall(tip.SetHyperlink, tip, payload) end
  if not ok and tip.SetHyperlink then
    tip:ClearLines()
    ok = pcall(tip.SetHyperlink, tip, link)
  end
  if not ok then tip:Hide(); return nil end

  local lines = {}
  local count = tip.NumLines and tip:NumLines() or 0
  local i = 1
  while i <= count do
    local left = OT:GetGlobal("OctoTweaksGearSearchParseTooltipTextLeft" .. tostring(i))
    local right = OT:GetGlobal("OctoTweaksGearSearchParseTooltipTextRight" .. tostring(i))
    if left and left.GetText then
      local text = left:GetText()
      if text and text ~= "" then table.insert(lines, text) end
    end
    if right and right.GetText then
      local text = right:GetText()
      if text and text ~= "" then table.insert(lines, text) end
    end
    i = i + 1
  end
  tip:Hide()
  return lines
end

local TOOLTIP_SLOT_ALIASES = {
  ["head"] = "INVTYPE_HEAD",
  ["neck"] = "INVTYPE_NECK",
  ["shoulder"] = "INVTYPE_SHOULDER",
  ["shoulders"] = "INVTYPE_SHOULDER",
  ["back"] = "INVTYPE_CLOAK",
  ["chest"] = "INVTYPE_CHEST",
  ["wrist"] = "INVTYPE_WRIST",
  ["hands"] = "INVTYPE_HAND",
  ["waist"] = "INVTYPE_WAIST",
  ["legs"] = "INVTYPE_LEGS",
  ["feet"] = "INVTYPE_FEET",
  ["finger"] = "INVTYPE_FINGER",
  ["trinket"] = "INVTYPE_TRINKET",
  ["one-hand"] = "INVTYPE_WEAPON",
  ["one hand"] = "INVTYPE_WEAPON",
  ["two-hand"] = "INVTYPE_2HWEAPON",
  ["two hand"] = "INVTYPE_2HWEAPON",
  ["main hand"] = "INVTYPE_WEAPONMAINHAND",
  ["off hand"] = "INVTYPE_WEAPONOFFHAND",
  ["held in off-hand"] = "INVTYPE_HOLDABLE",
  ["held in offhand"] = "INVTYPE_HOLDABLE",
  ["ranged"] = "INVTYPE_RANGED",
  ["thrown"] = "INVTYPE_THROWN",
  ["relic"] = "INVTYPE_RELIC",
}

local function normalizedTooltipText(value)
  local text = string.lower(trim(value or ""))
  text = string.gsub(text, "%s+", " ")
  return text
end

function GS:InferEquipLoc(lines, subtype)
  local subtypeText = normalizedTooltipText(subtype)
  if string.find(subtypeText, "shield", 1, true) then return "INVTYPE_SHIELD" end

  local i = 1
  while lines and i <= table.getn(lines) do
    local text = normalizedTooltipText(lines[i])
    local alias = TOOLTIP_SLOT_ALIASES[text]
    if alias then return alias end

    local j = 1
    while j <= table.getn(SLOT_OPTIONS) do
      local option = SLOT_OPTIONS[j]
      if option.equips then
        local k = 1
        while k <= table.getn(option.equips) do
          local equipLoc = option.equips[k]
          local localized = OT:GetGlobal(equipLoc)
          if localized and normalizedTooltipText(localized) == text then return equipLoc end
          k = k + 1
        end
      end
      j = j + 1
    end
    i = i + 1
  end
  return nil
end

function GS:ParseCandidate(row)
  local lines = self:ReadTooltipLines(row.link)
  if not lines or table.getn(lines) == 0 then return nil end

  local stats = { healingOnly = 0 }
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    stats[STAT_DEFS[i].key] = 0
    i = i + 1
  end
  i = 1
  while i <= table.getn(lines) do
    parseStatLine(stats, lines[i])
    i = i + 1
  end
  stats.heal = (stats.healingOnly or 0) + (stats.spellPower or 0)

  -- Auction links can have a warm tooltip while GetItemInfo is still cold on
  -- this client. Try both the exact variant link and the base item id, then use
  -- the category metadata captured by GearSearchAdapter plus the equipment line
  -- from the tooltip. This avoids blank Slot/Type columns without depending on
  -- Aegis UI rows or modifying Aegis itself.
  local info = Aegis:GetItemInfo(row.link)
  if (not info or not info.equipLoc or not info.subType) and row.itemId then
    local alternate = Aegis:GetItemInfo(row.itemId)
    if alternate then
      if not info then info = alternate else
        if not info.equipLoc then info.equipLoc = alternate.equipLoc end
        if not info.type then info.type = alternate.type end
        if not info.subType then info.subType = alternate.subType end
      end
    end
  end

  row.itemType = info and info.type or row.scanClassName
  row.itemSubType = info and info.subType or row.scanSubtypeName
  row.equipLoc = info and info.equipLoc or nil
  if not row.equipLoc then row.equipLoc = self:InferEquipLoc(lines, row.itemSubType) end
  row.slotName = self:FriendlySlot(row.equipLoc)
  row.typeName = row.itemSubType or row.itemType or "--"
  return stats
end

function GS:PassesMinimums(row, stats, score, db)
  if not self:MatchesSlot(row.equipLoc, db.slotFilter) then return false end
  local i = 1
  while i <= table.getn(STAT_DEFS) do
    local key = STAT_DEFS[i].key
    if (stats[key] or 0) < (tonumber(db.minimums[key]) or 0) then return false end
    i = i + 1
  end
  if score < db.minScore then return false end
  return true
end

function GS:RowSortValue(row, key)
  if key == "score" then return row.score or 0 end
  if key == "price" then return row.unit or 0 end
  if key == "slot" then return string.lower(tostring(row.slotName or "")) end
  if key == "type" then return string.lower(tostring(row.typeName or "")) end
  if key == "item" then return string.lower(tostring(row.name or "")) end
  if STAT_BY_KEY[key] then return row.stats and row.stats[key] or 0 end
  return 0
end

function GS:SortResults()
  local db = ensureSettings()
  local key = db.sortKey or "score"
  local ascending = db.sortAscending and true or false
  table.sort(self.results, function(a, b)
    local av = GS:RowSortValue(a, key)
    local bv = GS:RowSortValue(b, key)
    if av ~= bv then
      if ascending then return av < bv else return av > bv end
    end
    if (a.unit or 0) ~= (b.unit or 0) then return (a.unit or 0) < (b.unit or 0) end
    return string.lower(tostring(a.name or "")) < string.lower(tostring(b.name or ""))
  end)
  self:RefreshHeaderLabels()
end

function GS:SetSort(key)
  local db = ensureSettings()
  if db.sortKey == key then
    db.sortAscending = not db.sortAscending
  else
    db.sortKey = key
    if key == "price" or key == "slot" or key == "type" or key == "item" then
      db.sortAscending = true
    else
      db.sortAscending = false
    end
  end
  self:SortResults()
  self.page = 1
  self:RefreshResults()
end

function GS:ActiveStatsForDisplay()
  local db = ensureSettings()
  local active = {}
  local i = 1
  while i <= table.getn(STAT_DEFS) and table.getn(active) < self.maxStatColumns do
    local def = STAT_DEFS[i]
    if db.shownStats[def.key] then table.insert(active, def) end
    i = i + 1
  end
  return active
end

function GS:HeaderText(label, key)
  local db = ensureSettings()
  if db.sortKey == key then return label .. (db.sortAscending and " ^" or " v") end
  return label
end

function GS:RefreshHeaderLabels()
  if not self.frame or not self.frame.headers then return end
  local h = self.frame.headers
  h.score.label:SetText(self:HeaderText("Score", "score"))
  local i = 1
  while i <= self.maxStatColumns do
    local def = self.activeStatColumns[i]
    local button = h.stats[i]
    if def then
      button.sortKey = def.key
      button.label:SetText(self:HeaderText(def.label, def.key))
      button:Show()
    else
      button.sortKey = nil
      button.label:SetText("")
      button:Hide()
    end
    i = i + 1
  end
  h.price.label:SetText(self:HeaderText("Price", "price"))
  h.slot.label:SetText(self:HeaderText("Slot", "slot"))
  h.type.label:SetText(self:HeaderText("Type", "type"))
  h.item.label:SetText(self:HeaderText("Item", "item"))
end

function GS:LayoutResultColumns()
  if not self.frame or not self.frame.headers then return end
  local h = self.frame.headers
  local x = 16

  local function placeHeader(button, width)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -190)
    button:SetWidth(width)
    if button.label then button.label:SetWidth(width - 2) end
    x = x + width
  end

  placeHeader(h.score, 56)
  local i = 1
  while i <= self.maxStatColumns do
    local button = h.stats[i]
    if i <= table.getn(self.activeStatColumns) then
      placeHeader(button, 48)
    else
      button:Hide()
    end
    i = i + 1
  end
  placeHeader(h.price, 74)
  placeHeader(h.slot, 84)
  placeHeader(h.type, 84)
  local itemWidth = 900 - x
  if itemWidth < 170 then itemWidth = 170 end
  placeHeader(h.item, itemWidth)

  local rowIndex = 1
  while rowIndex <= table.getn(self.resultRows) do
    local row = self.resultRows[rowIndex]
    local rx = 0
    local function placeText(fs, width)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", row, "TOPLEFT", rx + 2, -4)
      fs:SetWidth(width - 4)
      rx = rx + width
    end
    placeText(row.score, 56)
    i = 1
    while i <= self.maxStatColumns do
      local fs = row.stats[i]
      if i <= table.getn(self.activeStatColumns) then
        placeText(fs, 48)
        fs:Show()
      else
        fs:SetText("")
        fs:Hide()
      end
      i = i + 1
    end
    placeText(row.price, 74)
    placeText(row.slot, 84)
    placeText(row.type, 84)
    placeText(row.item, itemWidth)
    rowIndex = rowIndex + 1
  end
end

function GS:RefreshColumnLayout()
  self.activeStatColumns = self:ActiveStatsForDisplay()
  self:LayoutResultColumns()
  self:RefreshHeaderLabels()
  self:RefreshResults()
end

function GS:FinishParsing()
  self.parseActive = false
  if self.parseDriver then self.parseDriver:Hide() end
  self:SortResults()
  self.page = 1
  self:RefreshResults()
  self:SetStatus("Gear Search complete: " .. tostring(table.getn(self.results))
    .. " matches from " .. tostring(self.rawCount) .. " item variants"
    .. (self.parseFailures > 0 and ("; tooltip failures=" .. tostring(self.parseFailures)) or ""))
end

function GS:ProcessParseQueue()
  if not self.parseActive then
    if self.parseDriver then self.parseDriver:Hide() end
    return
  end

  local db = ensureSettings()
  local processed = 0
  while processed < self.parsePerFrame and self.parseIndex <= table.getn(self.parseQueue) do
    local row = self.parseQueue[self.parseIndex]
    self.parseIndex = self.parseIndex + 1
    processed = processed + 1

    local stats = self:ParseCandidate(row)
    if stats then
      local score = scoreStats(stats, db)
      if self:PassesMinimums(row, stats, score, db) then
        row.stats = stats
        row.score = score
        table.insert(self.results, row)
      end
    else
      self.parseFailures = self.parseFailures + 1
    end
  end

  local total = table.getn(self.parseQueue)
  if self.parseIndex > total then
    self:FinishParsing()
  else
    self:SetStatus("Parsing item tooltips: " .. tostring(self.parseIndex - 1)
      .. "/" .. tostring(total) .. "  matches=" .. tostring(table.getn(self.results)))
  end
end

function GS:StartParsing()
  self.parseQueue = {}
  local key, row
  for key, row in pairs(self.rawByKey) do table.insert(self.parseQueue, row) end
  self.parseIndex = 1
  self.parseFailures = 0
  self.results = {}
  self.page = 1

  if table.getn(self.parseQueue) == 0 then
    self:SetStatus("Scan complete: no buyout listings matched the coarse filters")
    self:RefreshResults()
    return
  end

  if not self.parseDriver then
    self.parseDriver = CreateFrame("Frame", "OctoTweaksGearSearchParseDriver")
    self.parseDriver:SetScript("OnUpdate", function() GS:ProcessParseQueue() end)
  end
  self.parseActive = true
  self.parseDriver:Show()
  self:SetStatus("Parsing item tooltips: 0/" .. tostring(table.getn(self.parseQueue)))
end

function GS:StartSearch()
  if self.scanActive or self.parseActive then
    self:SetStatus("Gear Search is already running; stop it first")
    return false
  end

  local db = self:ReadSettingsFromUI()
  local kinds = self:SelectedGearKinds(db)
  local queries, queryReason = Aegis:BuildGearSearchQueries(kinds, db.minLevel, db.maxLevel)
  if not queries then
    self:SetStatus(queryReason)
    return false
  end

  self:ResetSearchState()
  local ok, reason = Aegis:StartGearSearchScan(queries, {
    onRows = function(rows) GS:OnRows(rows) end,
    onPage = function(page, totalPages)
      GS:SetStatus("Scanning Aegis AH: page " .. tostring(page) .. "/" .. tostring(totalPages)
        .. "  unique variants=" .. tostring(GS.rawCount))
    end,
    onComplete = function()
      GS.scanActive = false
      GS:StartParsing()
    end,
  })
  if not ok then
    self:SetStatus("Gear Search refused: " .. tostring(reason))
    return false
  end

  self.scanActive = true
  self:SetStatus(reason .. "; slot filter=" .. tostring((SLOT_BY_KEY[db.slotFilter] or SLOT_BY_KEY.any).label))
  return true
end

function GS:StopSearch()
  local stopped = false
  if self.scanActive then
    local ok, reason = Aegis:CancelGearSearchScan()
    self.scanActive = false
    self:SetStatus(reason)
    stopped = ok or stopped
  end
  if self.parseActive then
    self.parseActive = false
    if self.parseDriver then self.parseDriver:Hide() end
    self:SetStatus("Gear Search tooltip parsing stopped")
    stopped = true
  end
  if not stopped then self:SetStatus("Gear Search is idle") end
  return stopped
end

function GS:SetRowText(rowFrame, row)
  rowFrame.score:SetText(string.format("%.1f", row.score or 0))
  local i = 1
  while i <= self.maxStatColumns do
    local def = self.activeStatColumns[i]
    local fs = rowFrame.stats[i]
    if def then fs:SetText(tostring(row.stats and row.stats[def.key] or 0)) else fs:SetText("") end
    i = i + 1
  end
  rowFrame.price:SetText(money(row.unit))
  rowFrame.slot:SetText(tostring(row.slotName or "--"))
  rowFrame.type:SetText(tostring(row.typeName or "--"))
  rowFrame.item:SetText(tostring(row.name or "?"))
  if GetItemQualityColor and row.quality ~= nil then
    local r, g, b = GetItemQualityColor(row.quality)
    if r then rowFrame.item:SetTextColor(r, g, b) end
  else
    rowFrame.item:SetTextColor(1, 0.82, 0)
  end
end

function GS:ClearRowText(rowFrame)
  rowFrame.score:SetText("")
  local i = 1
  while i <= self.maxStatColumns do rowFrame.stats[i]:SetText(""); i = i + 1 end
  rowFrame.price:SetText("")
  rowFrame.slot:SetText("")
  rowFrame.type:SetText("")
  rowFrame.item:SetText("")
end

function GS:RefreshResults()
  if not self.frame then return end
  local total = table.getn(self.results)
  local pages = math.floor((total + self.rowsPerPage - 1) / self.rowsPerPage)
  if pages < 1 then pages = 1 end
  if self.page > pages then self.page = pages end
  if self.page < 1 then self.page = 1 end

  local i = 1
  while i <= self.rowsPerPage do
    local button = self.resultRows[i]
    local index = (self.page - 1) * self.rowsPerPage + i
    local row = self.results[index]
    if row then
      button.data = row
      self:SetRowText(button, row)
      button:Show()
    else
      button.data = nil
      self:ClearRowText(button)
      button:Hide()
    end
    i = i + 1
  end

  if self.frame.pageText then
    self.frame.pageText:SetText("Page " .. tostring(self.page) .. "/" .. tostring(pages)
      .. "   results=" .. tostring(total))
  end
end

function GS:PrevPage()
  if self.page > 1 then self.page = self.page - 1 end
  self:RefreshResults()
end

function GS:NextPage()
  local pages = math.floor((table.getn(self.results) + self.rowsPerPage - 1) / self.rowsPerPage)
  if pages < 1 then pages = 1 end
  if self.page < pages then self.page = self.page + 1 end
  self:RefreshResults()
end

function GS:ShowTooltip(button)
  if button and button.data then Aegis:ShowListingTooltip(button, button.data) end
end

function GS:HideTooltip()
  if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

function GS:BuildSlotMenu()
  if not self.frame or not self.frame.slotMenu then return end
  local menu = self.frame.slotMenu
  local i = 1
  while i <= table.getn(SLOT_OPTIONS) do
    local option = SLOT_OPTIONS[i]
    local button = menu.buttons[i]
    if not button then
      button = CreateFrame("Button", nil, menu)
      button:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, -5 - ((i - 1) * 18))
      button:SetWidth(132)
      button:SetHeight(18)
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      button.text:SetPoint("LEFT", button, "LEFT", 3, 0)
      button.text:SetWidth(126)
      button.text:SetJustifyH("LEFT")
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      button:SetScript("OnClick", function()
        local db = ensureSettings()
        db.slotFilter = this.slotKey
        GS:ApplySettingsToUI()
        menu:Hide()
        GS:SetStatus("Slot filter set to " .. tostring((SLOT_BY_KEY[this.slotKey] or SLOT_BY_KEY.any).label)
          .. "; press SEARCH to apply")
      end)
      menu.buttons[i] = button
    end
    button.slotKey = option.key
    button.text:SetText(option.label)
    button:Show()
    i = i + 1
  end
  menu:SetHeight(10 + (table.getn(SLOT_OPTIONS) * 18))
end

function GS:BuildPresetMenu()
  if not self.frame or not self.frame.presetMenu then return end
  local menu = self.frame.presetMenu
  local names = self:PresetNames()
  local count = table.getn(names)
  local visible = count
  if visible > 12 then visible = 12 end
  local i = 1
  while i <= visible do
    local name = names[i]
    local button = menu.buttons[i]
    if not button then
      button = CreateFrame("Button", nil, menu)
      button:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, -5 - ((i - 1) * 18))
      button:SetWidth(158)
      button:SetHeight(18)
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      button.text:SetPoint("LEFT", button, "LEFT", 3, 0)
      button.text:SetWidth(152)
      button.text:SetJustifyH("LEFT")
      button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      button:SetScript("OnClick", function()
        GS:LoadPreset(this.presetName)
        menu:Hide()
      end)
      menu.buttons[i] = button
    end
    button.presetName = name
    button.text:SetText(name)
    button:Show()
    i = i + 1
  end
  while i <= table.getn(menu.buttons) do menu.buttons[i]:Hide(); i = i + 1 end
  menu:SetHeight(10 + (visible * 18))
end

function GS:ToggleSlotMenu()
  local menu = self.frame and self.frame.slotMenu
  if not menu then return end
  if menu:IsVisible() then menu:Hide() else self:BuildSlotMenu(); menu:Show() end
end

function GS:TogglePresetMenu()
  local menu = self.frame and self.frame.presetMenu
  if not menu then return end
  if menu:IsVisible() then menu:Hide() else self:BuildPresetMenu(); menu:Show() end
end

function GS:LimitStatSelection(clicked)
  if not clicked or not clicked:GetChecked() or not self.frame or not self.frame.statConfigChecks then return end
  local count = 0
  local key, check
  for key, check in pairs(self.frame.statConfigChecks) do
    if check:GetChecked() then count = count + 1 end
  end
  if count > self.maxStatColumns then
    clicked:SetChecked(nil)
    self:SetStatus("At most " .. tostring(self.maxStatColumns) .. " stat columns can be displayed at once")
  end
end

function GS:CreateStatConfig(frame)
  local panel = CreateFrame("Frame", "OctoTweaksGearSearchStatConfig", frame)
  panel:SetWidth(650)
  panel:SetHeight(286)
  panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -164)
  panel:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 1) + 50)
  panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  panel:SetBackdropColor(0.03, 0.03, 0.03, 0.98)
  panel:EnableMouse(true)
  panel:Hide()
  frame.statConfig = panel
  frame.statConfigChecks = {}
  frame.statMinBoxes = {}
  frame.statWeightBoxes = {}

  createLabel(panel, "STAT CONFIG — choose visible columns, minimum filters and score weights",
    12, -12, 610, "GameFontNormal"):SetTextColor(1, 0.82, 0)
  createLabel(panel, "Show (max " .. tostring(self.maxStatColumns) .. ")", 12, -32, 82)
  createLabel(panel, "Stat", 86, -32, 52)
  createLabel(panel, "Min", 143, -32, 34)
  createLabel(panel, "Weight", 190, -32, 48)
  createLabel(panel, "Show", 326, -32, 44)
  createLabel(panel, "Stat", 382, -32, 52)
  createLabel(panel, "Min", 439, -32, 34)
  createLabel(panel, "Weight", 486, -32, 48)

  local i = 1
  while i <= table.getn(STAT_DEFS) do
    local def = STAT_DEFS[i]
    local column = i <= 10 and 0 or 1
    local row = column == 0 and i or (i - 10)
    local baseX = column == 0 and 12 or 326
    local y = -42 - ((row - 1) * 21)

    local check = CreateFrame("CheckButton", "OctoTweaksGearSearchShowStat" .. tostring(i),
      panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", panel, "TOPLEFT", baseX, y)
    check:SetWidth(22)
    check:SetHeight(22)
    check.statKey = def.key
    check:SetScript("OnClick", function() GS:LimitStatSelection(this) end)
    frame.statConfigChecks[def.key] = check

    createLabel(panel, def.label, baseX + 26, y - 5, 52)
    frame.statMinBoxes[def.key] = createEdit(panel,
      "OctoTweaksGearSearchMinStat" .. tostring(i), baseX + 80, y - 1, 42)
    frame.statWeightBoxes[def.key] = createEdit(panel,
      "OctoTweaksGearSearchStatWeight" .. tostring(i), baseX + 127, y - 1, 48)
    i = i + 1
  end

  createLabel(panel, "A minimum of 0 disables that filter. Weight 0 removes the stat from Score.",
    12, -258, 420, "GameFontNormalSmall"):SetTextColor(0.65, 0.65, 0.65)
  createButton(panel, "APPLY", 500, -251, 62, 22, function()
    GS:ReadStatConfigFromUI()
    panel:Hide()
    GS:SetStatus("Stat configuration applied; press SEARCH to re-evaluate minimum filters")
  end)
  createButton(panel, "CANCEL", 568, -251, 68, 22, function()
    GS:ApplySettingsToUI()
    panel:Hide()
  end)
end

function GS:ToggleStatConfig()
  local panel = self.frame and self.frame.statConfig
  if not panel then return end
  if panel:IsVisible() then
    panel:Hide()
  else
    self:ApplySettingsToUI()
    panel:Show()
  end
end

function GS:CreateResultColumns(frame)
  frame.headers = { stats = {} }
  local headerY = -190
  frame.headers.score = createHeaderButton(frame, "OctoTweaksGearHeaderScore", 16, headerY, 56,
    function() GS:SetSort("score") end)

  local i = 1
  while i <= self.maxStatColumns do
    local button = createHeaderButton(frame, "OctoTweaksGearHeaderStat" .. tostring(i),
      72 + ((i - 1) * 48), headerY, 48,
      function() if this.sortKey then GS:SetSort(this.sortKey) end end)
    frame.headers.stats[i] = button
    i = i + 1
  end

  frame.headers.price = createHeaderButton(frame, "OctoTweaksGearHeaderPrice", 456, headerY, 74,
    function() GS:SetSort("price") end)
  frame.headers.slot = createHeaderButton(frame, "OctoTweaksGearHeaderSlot", 530, headerY, 84,
    function() GS:SetSort("slot") end)
  frame.headers.type = createHeaderButton(frame, "OctoTweaksGearHeaderType", 614, headerY, 84,
    function() GS:SetSort("type") end)
  frame.headers.item = createHeaderButton(frame, "OctoTweaksGearHeaderItem", 698, headerY, 202,
    function() GS:SetSort("item") end)

  local rowY = -210
  i = 1
  while i <= self.rowsPerPage do
    local row = CreateFrame("Button", nil, frame)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, rowY - ((i - 1) * 24))
    row:SetWidth(884)
    row:SetHeight(22)
    row:EnableMouse(true)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.score = createLabel(row, "", 2, -4, 52)
    row.stats = {}
    local j = 1
    while j <= self.maxStatColumns do
      row.stats[j] = createLabel(row, "", 58 + ((j - 1) * 48), -4, 44)
      j = j + 1
    end
    row.price = createLabel(row, "", 442, -4, 70)
    row.slot = createLabel(row, "", 516, -4, 80)
    row.type = createLabel(row, "", 600, -4, 80)
    row.item = createLabel(row, "", 684, -4, 198)
    row:SetScript("OnEnter", function() GS:ShowTooltip(this) end)
    row:SetScript("OnLeave", function() GS:HideTooltip() end)
    self.resultRows[i] = row
    i = i + 1
  end
end

function GS:CreateUI(panel)
  if self.frame then return self.frame end
  self.panel = panel

  local frame = CreateFrame("Frame", "OctoTweaksGearSearchFrame", panel)
  frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  frame:SetFrameLevel((panel.GetFrameLevel and panel:GetFrameLevel() or 1) + 1)
  self.frame = frame

  local title = createLabel(frame, "GEAR SEARCH — advanced stat filters, presets and sortable score",
    16, -10, 850, "GameFontNormal")
  title:SetTextColor(1, 0.82, 0)
  createLabel(frame, "Aegis owns AH pacing. Weights are editable heuristics; click result headers to sort.",
    16, -29, 850, "GameFontNormalSmall"):SetTextColor(0.7, 0.7, 0.7)

  createLabel(frame, "Preset", 16, -57, 42)
  frame.presetButton = createButton(frame, "Custom  v", 58, -50, 150, 22,
    function() GS:TogglePresetMenu() end)
  frame.presetMenu = createMenu(frame, "OctoTweaksGearSearchPresetMenu", 168)
  frame.presetMenu:SetPoint("TOPLEFT", frame.presetButton, "BOTTOMLEFT", 0, -2)
  frame.savePreset = createButton(frame, "SAVE", 213, -50, 54, 22, function()
    local name = ensureSettings().activePreset
    if name == "Custom" then name = frame.presetName:GetText() end
    GS:SavePreset(name)
  end)
  createLabel(frame, "Save as", 278, -57, 46)
  frame.presetName = createEdit(frame, "OctoTweaksGearSearchPresetName", 326, -52, 108)
  frame.saveAsPreset = createButton(frame, "SAVE AS", 439, -50, 66, 22,
    function() GS:SavePreset(frame.presetName:GetText()) end)
  frame.deletePreset = createButton(frame, "DEL", 510, -50, 42, 22,
    function() GS:DeletePreset(ensureSettings().activePreset) end)
  frame.resetButton = createButton(frame, "RESET", 557, -50, 58, 22,
    function() GS:ResetSettings() end)

  frame.cloth = createCheck(frame, "OctoTweaksGearSearchCloth", "Cloth", 16, -79, 56)
  frame.leather = createCheck(frame, "OctoTweaksGearSearchLeather", "Leather", 96, -79, 62)
  frame.mail = createCheck(frame, "OctoTweaksGearSearchMail", "Mail", 190, -79, 46)
  frame.plate = createCheck(frame, "OctoTweaksGearSearchPlate", "Plate", 260, -79, 50)
  frame.shields = createCheck(frame, "OctoTweaksGearSearchShields", "Shields", 337, -79, 60)
  frame.misc = createCheck(frame, "OctoTweaksGearSearchMisc", "Misc", 430, -79, 50)
  frame.weapons = createCheck(frame, "OctoTweaksGearSearchWeapons", "Weapons", 507, -79, 70)

  createLabel(frame, "Slot", 16, -113, 30)
  frame.slotButton = createButton(frame, "Any slot  v", 47, -106, 120, 22,
    function() GS:ToggleSlotMenu() end)
  frame.slotMenu = createMenu(frame, "OctoTweaksGearSearchSlotMenu", 142)
  frame.slotMenu:SetPoint("TOPLEFT", frame.slotButton, "BOTTOMLEFT", 0, -2)

  createLabel(frame, "Level", 184, -113, 34)
  frame.minLevel = createEdit(frame, "OctoTweaksGearSearchMinLevel", 222, -108, 34)
  createLabel(frame, "-", 260, -113, 10)
  frame.maxLevel = createEdit(frame, "OctoTweaksGearSearchMaxLevel", 273, -108, 34)
  createLabel(frame, "Quality >=", 326, -113, 62)
  frame.minQuality = createEdit(frame, "OctoTweaksGearSearchMinQuality", 390, -108, 30)
  createLabel(frame, "Max price g", 442, -113, 70)
  frame.maxPrice = createEdit(frame, "OctoTweaksGearSearchMaxPrice", 515, -108, 52)
  frame.searchButton = createButton(frame, "SEARCH", 718, -104, 78, 24, function() GS:StartSearch() end)
  frame.stopButton = createButton(frame, "STOP", 801, -104, 58, 24, function() GS:StopSearch() end)

  createLabel(frame, "Stats", 16, -143, 34, "GameFontNormal")
  frame.statsButton = createButton(frame, "STATS...", 54, -136, 76, 22,
    function() GS:ToggleStatConfig() end)
  frame.statsSummary = createLabel(frame, "", 140, -143, 310, "GameFontNormalSmall")
  frame.statsSummary:SetTextColor(0.75, 0.75, 0.75)
  createLabel(frame, "Min score", 470, -143, 58)
  frame.minScore = createEdit(frame, "OctoTweaksGearSearchMinScore", 531, -138, 48)

  self:CreateStatConfig(frame)
  self:CreateResultColumns(frame)

  frame.prev = createButton(frame, "<", 16, -458, 30, 22, function() GS:PrevPage() end)
  frame.next = createButton(frame, ">", 50, -458, 30, 22, function() GS:NextPage() end)
  frame.pageText = createLabel(frame, "Page 1/1", 90, -464, 230)
  frame.status = createLabel(frame, "Idle", 16, -488, 875, "GameFontNormalSmall")
  frame.status:SetTextColor(0.75, 0.85, 1)
  createLabel(frame,
    "STATS config controls visible columns, per-stat minimums and score weights; presets save all three.",
    16, -510, 875, "GameFontNormalSmall"):SetTextColor(0.6, 0.6, 0.6)

  self:BuildSlotMenu()
  self:BuildPresetMenu()
  self:ApplySettingsToUI()
  self:RefreshResults()
  self:SetStatus(self.status or "Idle")
  return frame
end

function GS:BeforeHide()
  if self.scanActive or self.parseActive then self:StopSearch() end
  if self.frame then
    if self.frame.slotMenu then self.frame.slotMenu:Hide() end
    if self.frame.presetMenu then self.frame.presetMenu:Hide() end
    if self.frame.statConfig then self.frame.statConfig:Hide() end
  end
  self:HideTooltip()
end

function GS:OnShow(panel)
  if not self.frame then self:CreateUI(panel) end
  self:ApplySettingsToUI()
  self:RefreshResults()
end

function GS:Open()
  if not Aegis:IsAuctionHouseOpen() then
    OT:Print("Gear Search: open the Auction House first")
    return false
  end
  local ok, reason = Aegis:OpenUIExtension(self.key)
  if not ok then OT:Print("Gear Search: " .. tostring(reason)) end
  return ok
end

function GS:PrintStatus()
  local db = ensureSettings()
  OT:Print("Gear Search: scan=" .. tostring(self.scanActive)
    .. ", parsing=" .. tostring(self.parseActive)
    .. ", raw=" .. tostring(self.rawCount)
    .. ", results=" .. tostring(table.getn(self.results)))
  OT:Print("  preset=" .. tostring(db.activePreset) .. ", slot=" .. tostring(db.slotFilter)
    .. ", level=" .. tostring(db.minLevel) .. "-" .. tostring(db.maxLevel)
    .. ", minQuality=" .. tostring(db.minQuality) .. ", maxPriceGold=" .. tostring(db.maxPriceGold))
  OT:Print("  sort=" .. tostring(db.sortKey) .. " " .. (db.sortAscending and "ascending" or "descending"))
  local d = Aegis:GetUIExtensionDiagnostics(self.key)
  OT:Print("  UI registered=" .. tostring(d.installed) .. ", attached=" .. tostring(d.attached)
    .. ", active=" .. tostring(d.active) .. ", reason=" .. tostring(d.reason))
  if d.lastError then OT:Print("  UI error=" .. tostring(d.lastError)) end
end

local module = {
  id = "aegis.gear_search",
  category = "feature",
  target = "Aegis_Exchange",
  defaultEnabled = true,
  testedVersion = "1.53.29",
  sourceAuditedVersions = "1.20.2 and 1.53.29 private UI seam",
}

function module:probe()
  local integration = OT:GetModuleState("aegis.integration")
  if not integration or integration.status ~= "ENABLED" then
    return false, "waiting for aegis.integration"
  end
  if type(Aegis.BuildGearSearchQueries) ~= "function"
      or type(Aegis.StartGearSearchScan) ~= "function"
      or type(Aegis.CancelGearSearchScan) ~= "function" then
    return false, "Gear Search adapter helpers unavailable"
  end
  return Aegis:ProbeWorkbenchUIHost()
end

function module:enable()
  local ok, reason = Aegis:InstallUIExtension({
    key = GS.key,
    label = GS.label,
    hostHeight = GS.hostHeight,
    onAttach = function(panel) GS:CreateUI(panel) end,
    beforeHide = function() GS:BeforeHide() end,
    onShow = function(panel) GS:OnShow(panel) end,
  })
  if not ok then return false, reason end

  SLASH_OCTOTWEAKSGEARSEARCH1 = "/otgear"
  SLASH_OCTOTWEAKSGEARSEARCH2 = "/otgears"
  SlashCmdList["OCTOTWEAKSGEARSEARCH"] = function(msg)
    local text = trim(msg)
    local low = string.lower(text)
    if low == "status" then GS:PrintStatus(); return end
    if low == "reset" then GS:ResetSettings(); return end
    if low == "stop" then GS:StopSearch(); return end
    if low == "search" then if GS:Open() then GS:StartSearch() end; return end
    if low == "presets" then GS:PrintPresets(); return end

    local _, _, saveName = string.find(text, "^[sS][aA][vV][eE]%s+(.+)$")
    if saveName then GS:SavePreset(saveName); return end
    local _, _, loadName = string.find(text, "^[lL][oO][aA][dD]%s+(.+)$")
    if loadName then GS:LoadPreset(loadName); return end
    local _, _, deleteName = string.find(text, "^[dD][eE][lL][eE][tT][eE]%s+(.+)$")
    if deleteName then GS:DeletePreset(deleteName); return end

    GS:Open()
  end

  return true, "Aegis Gear Search v2 ready; changed runtime behavior pending validation"
end

OT:RegisterModule(module)
