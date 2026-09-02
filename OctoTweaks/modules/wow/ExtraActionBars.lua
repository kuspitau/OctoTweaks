--[[
Module: wow.extra_action_bars
Category: feature
Target: WoW 1.12 / OctoWoW client UI
Tested against: partial OctoWoW runtime observation; full runtime validation pending

Purpose:
Provide persistent virtual action slots that are independent of Blizzard's native
action-slot pool. Slots can execute spells, items, macros, and SuperMacros while
remaining bindable even when their visual bar is hidden.

Compatibility:
Uses only public WoW 1.12-era frame, cursor, spellbook, inventory, macro, and
binding APIs. SuperMacro support is optional and detected dynamically.
]]

local OT = OctoTweaks

local MAX_BARS = 8
local SLOTS_PER_BAR = 12
local MAX_SLOTS = MAX_BARS * SLOTS_PER_BAR
local DEFAULT_BAR_COUNT = 4
local DEFAULT_BUTTON_SIZE = 30
local DEFAULT_BUTTON_SPACING = 1
local DEFAULT_ICON_INSET = 2
local MIN_BUTTON_SIZE = 22
local MAX_BUTTON_SIZE = 48
local MAX_BUTTON_SPACING = 10
local MAX_ICON_INSET = 8
local HOVER_ALPHA = 0.08
local REFRESH_INTERVAL = 0.20
local BOOK_PLAYER = BOOKTYPE_SPELL or "spell"

local module = {
  id = "wow.extra_action_bars",
  category = "feature",
  target = "WoW 1.12 / OctoWoW",
  defaultEnabled = true,
  testedVersion = "WoW 1.12 / OctoWoW",
  enabled = false,
  bars = {},
  buttons = {},
  holdActive = false,
  qbindActive = false,
  refreshElapsed = 0,
  settingsBar = 1,
  settingsFrame = nil,
  pendingMoveSource = nil,
  pendingMacroAction = nil,
  pendingMacroCursorToken = nil,
  originalPickupMacro = nil,
  pickupMacroWrapper = nil,
  launcherDragging = false,
  suppressLauncherClick = false,
  launcherDragEndedAt = nil,
}

local function clamp(value, minimum, maximum)
  if value < minimum then
    return minimum
  end
  if value > maximum then
    return maximum
  end
  return value
end

local function trim(text)
  text = tostring(text or "")
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  return text
end

local function shiftIsDown()
  return IsShiftKeyDown and IsShiftKeyDown() and true or false
end

local function splitFirst(text)
  local _, _, first, rest = string.find(trim(text), "^(%S+)%s*(.-)$")
  return first, rest or ""
end

local function parseTwo(text)
  local _, _, first, second = string.find(trim(text), "^(%S+)%s+(.+)$")
  return first, second
end

local function setBindingName(name, value)
  if setglobal then
    setglobal(name, value)
  elseif _G then
    _G[name] = value
  end
end

BINDING_HEADER_OCTOTWEAKS_EXTRABARS = "OctoTweaks Extra Action Bars"
BINDING_NAME_OCTOTWEAKS_EXTRABARS_TOGGLE = "Toggle OctoTweaks extra bars"
BINDING_NAME_OCTOTWEAKS_EXTRABARS_HOLD = "Hold OctoTweaks hold-mode bars"

local bindingIndex
for bindingIndex = 1, MAX_SLOTS do
  setBindingName(
    "BINDING_NAME_OCTOTWEAKS_EXTRABAR_SLOT" .. bindingIndex,
    "OctoTweaks extra action slot " .. bindingIndex
  )
end

local function defaultMode(barIndex)
  if barIndex == 3 then
    return "hover"
  end
  if barIndex == 4 then
    return "toggle"
  end
  return "always"
end

local function defaultBarY(barIndex)
  return 220 + ((barIndex - 1) * 42)
end

local function ensureBarConfig(db, barIndex)
  if not db.bars[barIndex] then
    db.bars[barIndex] = {}
  end

  local cfg = db.bars[barIndex]
  if not cfg.point then
    cfg.point = "BOTTOM"
  end
  if not cfg.relativePoint then
    cfg.relativePoint = "BOTTOM"
  end
  if cfg.x == nil then
    cfg.x = 0
  end
  if cfg.y == nil then
    cfg.y = defaultBarY(barIndex)
  end
  if cfg.scale == nil then
    cfg.scale = 1
  end
  if cfg.columns == nil then
    cfg.columns = 12
  end
  if not cfg.mode then
    cfg.mode = defaultMode(barIndex)
  end
  if cfg.visible == nil then
    cfg.visible = false
  end

  return cfg
end

function module:EnsureData()
  OT:EnsureSavedVariables()

  if not OctoTweaksDB.extraActionBars then
    OctoTweaksDB.extraActionBars = {}
  end

  local db = OctoTweaksDB.extraActionBars
  local schemaVersion = tonumber(db.schemaVersion) or 1
  if schemaVersion < 2 then
    db.schemaVersion = 2
  else
    db.schemaVersion = schemaVersion
  end
  if db.barCount == nil then
    db.barCount = DEFAULT_BAR_COUNT
  end
  db.barCount = clamp(tonumber(db.barCount) or DEFAULT_BAR_COUNT, 1, MAX_BARS)

  if db.buttonSize == nil then
    db.buttonSize = DEFAULT_BUTTON_SIZE
  end
  db.buttonSize = clamp(math.floor(tonumber(db.buttonSize) or DEFAULT_BUTTON_SIZE), MIN_BUTTON_SIZE, MAX_BUTTON_SIZE)

  if db.buttonSpacing == nil then
    db.buttonSpacing = DEFAULT_BUTTON_SPACING
  end
  db.buttonSpacing = clamp(math.floor(tonumber(db.buttonSpacing) or DEFAULT_BUTTON_SPACING), 0, MAX_BUTTON_SPACING)

  if db.iconInset == nil then
    db.iconInset = DEFAULT_ICON_INSET
  end
  db.iconInset = clamp(math.floor(tonumber(db.iconInset) or DEFAULT_ICON_INSET), 1, MAX_ICON_INSET)

  if db.locked == nil then
    db.locked = false
  end
  if not db.bars then
    db.bars = {}
  end
  if not db.slots then
    db.slots = {}
  end
  if not db.launcher then
    db.launcher = {}
  end

  local launcher = db.launcher
  if launcher.shown == nil then
    launcher.shown = true
  end
  if not launcher.point then
    launcher.point = "TOPRIGHT"
  end
  if not launcher.relativePoint then
    launcher.relativePoint = "TOPRIGHT"
  end
  if launcher.x == nil then
    launcher.x = -220
  end
  if launcher.y == nil then
    launcher.y = -8
  end

  local i
  for i = 1, MAX_BARS do
    ensureBarConfig(db, i)
  end

  self.db = db
  return db
end

function module:GetSlot(slotIndex)
  local db = self:EnsureData()
  if slotIndex < 1 or slotIndex > MAX_SLOTS then
    return nil
  end
  return db.slots[slotIndex]
end

function module:SetSlot(slotIndex, action)
  local db = self:EnsureData()
  if slotIndex < 1 or slotIndex > MAX_SLOTS then
    return false
  end
  db.slots[slotIndex] = action
  self:RefreshButton(slotIndex)
  return true
end

function module:ClearSlot(slotIndex)
  local db = self:EnsureData()
  if slotIndex < 1 or slotIndex > MAX_SLOTS then
    return false
  end
  db.slots[slotIndex] = nil
  self:RefreshButton(slotIndex)
  return true
end

function module:SetMoveSelection(slotIndex)
  local previous = self.pendingMoveSource
  self.pendingMoveSource = slotIndex

  if previous and self.buttons[previous] then
    self:RefreshButton(previous)
  end
  if slotIndex and self.buttons[slotIndex] then
    self:RefreshButton(slotIndex)
  end
end

function module:CancelMoveSelection()
  if not self.pendingMoveSource then
    return false
  end
  self:SetMoveSelection(nil)
  return true
end

function module:HandleMoveClick(slotIndex)
  local source = self.pendingMoveSource

  if not source then
    if not self:GetSlot(slotIndex) then
      return false, "source slot is empty"
    end
    self:SetMoveSelection(slotIndex)
    OT:Print("move selected: extra slot " .. slotIndex .. "; Shift+Left Click destination")
    return true
  end

  if source == slotIndex then
    self:CancelMoveSelection()
    OT:Print("move cancelled")
    return true
  end

  local db = self:EnsureData()
  local sourceAction = db.slots[source]
  if not sourceAction then
    self:CancelMoveSelection()
    return false, "selected source slot is now empty"
  end

  local destinationAction = db.slots[slotIndex]
  db.slots[slotIndex] = sourceAction
  db.slots[source] = destinationAction
  self.pendingMoveSource = nil
  self:RefreshButton(source)
  self:RefreshButton(slotIndex)
  OT:Print("moved extra action slot " .. source .. " to " .. slotIndex)
  return true
end

function module:BindingCommand(slotIndex)
  return "OCTOTWEAKS_EXTRABAR_SLOT" .. slotIndex
end

function module:GetSlotBinding(slotIndex)
  if not GetBindingKey then
    return nil
  end
  return GetBindingKey(self:BindingCommand(slotIndex))
end

function module:ShortBinding(key)
  if not key or key == "" then
    return ""
  end

  local short = tostring(key)
  short = string.gsub(short, "SHIFT%-", "S-")
  short = string.gsub(short, "CTRL%-", "C-")
  short = string.gsub(short, "ALT%-", "A-")
  short = string.gsub(short, "BUTTON", "M")
  short = string.gsub(short, "MOUSEWHEELUP", "MWU")
  short = string.gsub(short, "MOUSEWHEELDOWN", "MWD")
  return short
end

function module:ClearSlotBindings(slotIndex, save)
  slotIndex = tonumber(slotIndex)
  if not slotIndex or slotIndex < 1 or slotIndex > MAX_SLOTS then
    return false, "slot must be between 1 and " .. MAX_SLOTS
  end
  if not GetBindingKey or not SetBinding then
    return false, "binding API unavailable"
  end

  local command = self:BindingCommand(slotIndex)
  local key1, key2 = GetBindingKey(command)
  if key1 then
    SetBinding(key1)
  end
  if key2 then
    SetBinding(key2)
  end

  if save and SaveBindings and GetCurrentBindingSet then
    SaveBindings(GetCurrentBindingSet())
  end

  self:RefreshButton(slotIndex)
  return true
end

function module:BindSlot(slotIndex, key)
  slotIndex = tonumber(slotIndex)
  if not slotIndex or slotIndex < 1 or slotIndex > MAX_SLOTS then
    return false, "slot must be between 1 and " .. MAX_SLOTS
  end
  if not key or key == "" then
    return false, "key is empty"
  end
  if not SetBinding or not SaveBindings or not GetCurrentBindingSet then
    return false, "binding API unavailable"
  end

  self:ClearSlotBindings(slotIndex, false)

  local command = self:BindingCommand(slotIndex)
  local changed = SetBinding(string.upper(key), command)
  if not changed then
    return false, "SetBinding refused " .. tostring(key)
  end

  SaveBindings(GetCurrentBindingSet())
  self:RefreshAllButtons()
  return true
end

function module:BindUtility(command, key)
  key = trim(key)
  if key == "" then
    return false, "key is empty"
  end
  if not SetBinding or not SaveBindings or not GetCurrentBindingSet then
    return false, "binding API unavailable"
  end

  local old1, old2
  if GetBindingKey then
    old1, old2 = GetBindingKey(command)
  end
  if old1 then
    SetBinding(old1)
  end
  if old2 then
    SetBinding(old2)
  end

  local changed = SetBinding(string.upper(key), command)
  if not changed then
    return false, "SetBinding refused " .. tostring(key)
  end
  SaveBindings(GetCurrentBindingSet())
  return true
end

function module:BuildBindingKey(key)
  if not key or key == "" then
    return nil
  end

  key = string.upper(key)
  if key == "SHIFT" or key == "LSHIFT" or key == "RSHIFT" or
     key == "CTRL" or key == "LCTRL" or key == "RCTRL" or
     key == "ALT" or key == "LALT" or key == "RALT" then
    return nil
  end

  local prefix = ""
  if IsAltKeyDown and IsAltKeyDown() then
    prefix = prefix .. "ALT-"
  end
  if IsControlKeyDown and IsControlKeyDown() then
    prefix = prefix .. "CTRL-"
  end
  if IsShiftKeyDown and IsShiftKeyDown() then
    prefix = prefix .. "SHIFT-"
  end
  return prefix .. key
end

function module:GetHoveredSlot()
  if not GetMouseFocus then
    return nil
  end

  local focus = GetMouseFocus()
  local depth = 0
  while focus and depth < 8 do
    if focus.OctoTweaksExtraActionSlot then
      return focus.OctoTweaksExtraActionSlot
    end
    if not focus.GetParent then
      break
    end
    focus = focus:GetParent()
    depth = depth + 1
  end
  return nil
end

function module:SetQBindMode(enabled)
  enabled = enabled and true or false
  if enabled == self.qbindActive then
    return
  end

  self.qbindActive = enabled

  local buttonIndex
  for buttonIndex = 1, MAX_SLOTS do
    local button = self.buttons[buttonIndex]
    if button and button.EnableMouseWheel then
      button:EnableMouseWheel(enabled)
    end
  end

  if self.qbindFrame then
    if enabled then
      self.qbindFrame:Show()
      self.qbindFrame:EnableKeyboard(true)
    else
      self.qbindFrame:EnableKeyboard(false)
      self.qbindFrame:Hide()
    end
  end

  if self.launcher and self.launcher.text then
    if enabled then
      self.launcher.text:SetText("QB")
    else
      self.launcher.text:SetText("OTB")
    end
  end

  if enabled then
    OT:Print("Extra Bars qbind ON: hover a slot and press a key. ESC clears the hovered slot binding; move off the bars and press ESC to exit.")
  else
    OT:Print("Extra Bars qbind OFF")
  end

  self:RefreshSettingsPanel()
end

function module:HandleQBindKey(key)
  if not self.qbindActive then
    return
  end

  local slotIndex = self:GetHoveredSlot()
  if key == "ESCAPE" then
    if slotIndex then
      self:ClearSlotBindings(slotIndex, true)
      OT:Print("cleared binding for extra slot " .. slotIndex)
    else
      self:SetQBindMode(false)
    end
    return
  end

  if not slotIndex then
    return
  end

  local bindingKey = self:BuildBindingKey(key)
  if not bindingKey then
    return
  end

  local ok, reason = self:BindSlot(slotIndex, bindingKey)
  if ok then
    OT:Print("extra slot " .. slotIndex .. " bound to " .. bindingKey)
  else
    OT:Print("could not bind extra slot " .. slotIndex .. ": " .. tostring(reason))
  end
end

local function itemIdFromLink(link)
  if not link then
    return nil
  end
  local _, _, itemId = string.find(link, "item:(%d+)")
  return tonumber(itemId)
end

local function validTexturePath(texture)
  return type(texture) == "string" and texture ~= ""
end

function module:FindSpell(action)
  if not action or not action.name then
    return nil
  end

  local bookTypes = { BOOK_PLAYER, "pet" }
  local bookIndex
  for bookIndex = 1, table.getn(bookTypes) do
    local bookType = bookTypes[bookIndex]
    local i = 1
    while i <= 500 do
      local name, rank = GetSpellName(i, bookType)
      if not name then
        break
      end
      if name == action.name and (not action.rank or action.rank == "" or rank == action.rank) then
        return i, bookType
      end
      i = i + 1
    end
  end

  return nil
end

function module:SpellLabel(action)
  if action.rank and action.rank ~= "" then
    return action.name .. "(" .. action.rank .. ")"
  end
  return action.name
end

function module:FindMacroIndex(name, preferredIndex)
  if preferredIndex and GetMacroInfo then
    local preferredName = GetMacroInfo(preferredIndex)
    if preferredName and (not name or preferredName == name) then
      return preferredIndex
    end
  end

  if not name then
    return nil
  end

  if GetMacroIndexByName then
    local index = GetMacroIndexByName(name)
    if index and index > 0 then
      return index
    end
  end

  if not GetMacroInfo then
    return nil
  end

  -- Vanilla uses a small fixed macro pool. Scan beyond the stock 54 slots so
  -- OctoWoW/SuperWoW variants with expanded regular-macro pools still work.
  local i
  for i = 1, 72 do
    local macroName = GetMacroInfo(i)
    if macroName == name then
      return i
    end
  end
  return nil
end

function module:ResolveMacroTexture(texture)
  if validTexturePath(texture) then
    return texture
  end

  -- Some 1.12-derived clients expose the selected macro-icon index rather
  -- than the final texture path. Resolve it before feeding SetTexture().
  local iconIndex = tonumber(texture)
  if iconIndex and GetMacroIconInfo then
    local resolved = GetMacroIconInfo(iconIndex)
    if validTexturePath(resolved) then
      return resolved
    end
  end

  return nil
end

function module:MacroActionFromToken(macroToken)
  if not GetMacroInfo then
    return nil, "GetMacroInfo unavailable"
  end
  if macroToken == nil then
    return nil, "macro cursor data unavailable"
  end

  local macroIndex = tonumber(macroToken)
  if not macroIndex and type(macroToken) == "string" then
    macroIndex = self:FindMacroIndex(macroToken)
  end

  local lookup = macroIndex or macroToken
  local name, texture, body = GetMacroInfo(lookup)
  if not name and macroIndex then
    -- A few clients expose an unstable numeric cursor token. If the direct
    -- lookup misses, there is no safe name to infer, so fail rather than
    -- binding a different macro accidentally.
    return nil, "macro index " .. tostring(macroIndex) .. " is unavailable"
  end
  if not name then
    return nil, "macro name unavailable"
  end

  if not macroIndex then
    macroIndex = self:FindMacroIndex(name)
  end
  if (not body or body == "") and GetMacroBody then
    body = GetMacroBody(macroIndex or name)
  end

  return {
    type = "macro",
    name = name,
    macroIndex = macroIndex,
    texture = self:ResolveMacroTexture(texture),
    body = body,
  }
end

function module:ClearPendingMacroPickup()
  self.pendingMacroAction = nil
  self.pendingMacroCursorToken = nil
end

function module:InstallMacroPickupCapture()
  if self.pickupMacroWrapper then
    return true
  end
  if not PickupMacro then
    return false
  end

  local original = PickupMacro
  self.originalPickupMacro = original
  self.pickupMacroWrapper = function(macroToken)
    -- Capture the macro from the public PickupMacro() call itself. On the
    -- observed OctoWoW runtime, GetCursorInfo() can expose a numeric macro
    -- token that does not consistently map back to the macro slot that was
    -- picked up. The source call is authoritative and avoids offset/icon-id
    -- heuristics.
    local action = module:MacroActionFromToken(macroToken)
    module.pendingMacroAction = action
    module.pendingMacroCursorToken = nil

    original(macroToken)

    if GetCursorInfo then
      local kind, cursorToken = GetCursorInfo()
      if kind == "macro" then
        module.pendingMacroCursorToken = cursorToken
      else
        module:ClearPendingMacroPickup()
      end
    end
  end

  PickupMacro = self.pickupMacroWrapper
  return true
end

function module:FindItemLocation(action)
  if not action then
    return nil
  end

  if GetContainerNumSlots and GetContainerItemLink then
    local bag
    for bag = 0, 4 do
      local slots = GetContainerNumSlots(bag) or 0
      local slot
      for slot = 1, slots do
        local link = GetContainerItemLink(bag, slot)
        if link then
          local same = false
          if action.itemId and itemIdFromLink(link) == action.itemId then
            same = true
          elseif action.name and string.find(string.lower(link), string.lower(action.name), 1, true) then
            same = true
          end
          if same then
            return "bag", bag, slot, link
          end
        end
      end
    end
  end

  if GetInventoryItemLink then
    local inv
    for inv = 0, 19 do
      local link = GetInventoryItemLink("player", inv)
      if link then
        local same = false
        if action.itemId and itemIdFromLink(link) == action.itemId then
          same = true
        elseif action.name and string.find(string.lower(link), string.lower(action.name), 1, true) then
          same = true
        end
        if same then
          return "inventory", inv, nil, link
        end
      end
    end
  end

  return nil
end

function module:GetItemCount(action)
  if not action or not GetContainerNumSlots or not GetContainerItemLink then
    return nil
  end

  local total = 0
  local bag
  for bag = 0, 4 do
    local slots = GetContainerNumSlots(bag) or 0
    local slot
    for slot = 1, slots do
      local link = GetContainerItemLink(bag, slot)
      if link and action.itemId and itemIdFromLink(link) == action.itemId then
        local _, count = GetContainerItemInfo(bag, slot)
        total = total + (count or 1)
      end
    end
  end
  return total
end

function module:UseItem(action)
  -- Prefer the concrete bag/equipment location. This is more reliable for
  -- equippable items (for example a fishing pole) than relying on
  -- UseItemByName alone on 1.12-era clients.
  local location, first, second = self:FindItemLocation(action)
  if location == "bag" and UseContainerItem and first and second then
    UseContainerItem(first, second)
    return true
  end
  if location == "inventory" and UseInventoryItem and first then
    UseInventoryItem(first)
    return true
  end

  if UseItemByName and (action.link or action.name) then
    UseItemByName(action.link or action.name)
    return true
  end

  return false
end

function module:UseSlot(slotIndex)
  slotIndex = tonumber(slotIndex)
  if not slotIndex or slotIndex < 1 or slotIndex > MAX_SLOTS then
    return false
  end

  local action = self:GetSlot(slotIndex)
  if not action then
    return false
  end

  if action.type == "spell" then
    local spellSlot, bookType = self:FindSpell(action)
    if spellSlot and CastSpell then
      CastSpell(spellSlot, bookType)
      return true
    end
    if CastSpellByName then
      CastSpellByName(self:SpellLabel(action))
      return true
    end
    return false
  end

  if action.type == "item" then
    return self:UseItem(action)
  end

  if action.type == "macro" then
    if not RunMacro then
      return false
    end
    local macroIndex = self:FindMacroIndex(action.name, action.macroIndex)
    if macroIndex then
      action.macroIndex = macroIndex
      RunMacro(macroIndex)
      return true
    end
    if action.name then
      RunMacro(action.name)
      return true
    end
    return false
  end

  if action.type == "supermacro" then
    if RunSuperMacro then
      RunSuperMacro(action.name)
      return true
    end
    OT:Print("extra slot " .. slotIndex .. " requires SuperMacro: " .. tostring(action.name))
    return false
  end

  return false
end

function module:ActionFromCursor()
  if not GetCursorInfo then
    return nil, "GetCursorInfo unavailable"
  end

  local kind, a, b, c = GetCursorInfo()
  if not kind then
    return nil, "cursor is empty"
  end

  if kind == "spell" then
    local spellSlot = tonumber(a)
    local bookType = b or BOOK_PLAYER
    if not spellSlot or not GetSpellName then
      return nil, "spell cursor data unavailable"
    end
    local name, rank = GetSpellName(spellSlot, bookType)
    if not name then
      return nil, "spell name unavailable"
    end
    local texture
    if GetSpellTexture then
      texture = GetSpellTexture(spellSlot, bookType)
    end
    return {
      type = "spell",
      name = name,
      rank = rank or "",
      texture = texture,
      spellId = tonumber(c),
    }
  end

  if kind == "item" then
    local itemId = tonumber(a)
    local link = b
    local name, canonicalLink, texture

    if GetItemInfo then
      local lookup = link or itemId
      local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = GetItemInfo(lookup)
      name = itemName
      canonicalLink = itemLink
      if validTexturePath(itemTexture) then
        texture = itemTexture
      end

      -- Some 1.12-derived clients are happier when queried by id than by the
      -- full colored hyperlink. Retry that form before giving up.
      if not name and itemId then
        itemName, itemLink, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemId)
        name = itemName
        canonicalLink = itemLink or canonicalLink
        if validTexturePath(itemTexture) then
          texture = itemTexture
        end
      end
    end

    local resolvedLink = canonicalLink or link
    if not itemId then
      itemId = itemIdFromLink(resolvedLink)
    end
    if not name and resolvedLink then
      local _, _, linkName = string.find(resolvedLink, "%[(.-)%]")
      name = linkName
    end

    if not itemId and not resolvedLink and not name then
      return nil, "item cursor data unavailable"
    end

    return {
      type = "item",
      itemId = itemId,
      name = name,
      link = resolvedLink,
      texture = texture,
    }
  end

  if kind == "macro" then
    -- Prefer the action captured from PickupMacro(). The observed OctoWoW
    -- cursor token is not a reliable macro index for every macro. Match the
    -- cursor token when available so a stale capture is never reused for an
    -- unrelated macro cursor.
    if self.pendingMacroAction then
      if self.pendingMacroCursorToken == nil or tostring(self.pendingMacroCursorToken) == tostring(a) then
        return self.pendingMacroAction
      end
    end

    -- Fallback for macro cursors created by code paths that do not call the
    -- public PickupMacro() function. Stock Vanilla reports the macro index
    -- here, and some clients/addons may expose a string token.
    local action, reason = self:MacroActionFromToken(a)
    if action then
      return action
    end
    if b ~= nil then
      action, reason = self:MacroActionFromToken(b)
      if action then
        return action
      end
    end
    return nil, reason or "macro cursor data unavailable"
  end

  self:ClearPendingMacroPickup()

  return nil, "unsupported cursor type: " .. tostring(kind)
end

function module:ReceiveCursor(slotIndex)
  local action, reason = self:ActionFromCursor()
  if not action then
    return false, reason
  end

  if self.pendingMoveSource then
    self:CancelMoveSelection()
  end
  self:SetSlot(slotIndex, action)
  if ClearCursor then
    ClearCursor()
  end
  self:ClearPendingMacroPickup()
  return true
end

function module:SetMacroSlot(slotIndex, macroToken)
  slotIndex = tonumber(slotIndex)
  macroToken = trim(macroToken)
  if not slotIndex or slotIndex < 1 or slotIndex > MAX_SLOTS then
    return false, "slot must be between 1 and " .. MAX_SLOTS
  end
  if macroToken == "" then
    return false, "macro name/index is empty"
  end

  local action, reason = self:MacroActionFromToken(macroToken)
  if not action then
    return false, reason
  end
  self:SetSlot(slotIndex, action)
  return true
end

function module:SetItemSlot(slotIndex, itemToken)
  slotIndex = tonumber(slotIndex)
  itemToken = trim(itemToken)
  if not slotIndex or slotIndex < 1 or slotIndex > MAX_SLOTS then
    return false, "slot must be between 1 and " .. MAX_SLOTS
  end
  if itemToken == "" then
    return false, "item name/link/id is empty"
  end

  local lookup = tonumber(itemToken) or itemToken
  local itemId = tonumber(itemToken) or itemIdFromLink(itemToken)
  local name, link, texture
  if GetItemInfo then
    local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = GetItemInfo(lookup)
    name = itemName
    link = itemLink
    if validTexturePath(itemTexture) then
      texture = itemTexture
    end
  end

  link = link or (string.find(itemToken, "item:", 1, true) and itemToken or nil)
  if not itemId then
    itemId = itemIdFromLink(link)
  end
  if not name and link then
    local _, _, linkName = string.find(link, "%[(.-)%]")
    name = linkName
  end
  name = name or (not tonumber(itemToken) and itemToken or nil)

  self:SetSlot(slotIndex, {
    type = "item",
    itemId = itemId,
    name = name,
    link = link,
    texture = texture,
  })
  return true
end

function module:SetSuperMacro(slotIndex, name)
  slotIndex = tonumber(slotIndex)
  name = trim(name)
  if not slotIndex or slotIndex < 1 or slotIndex > MAX_SLOTS then
    return false, "slot must be between 1 and " .. MAX_SLOTS
  end
  if name == "" then
    return false, "SuperMacro name is empty"
  end
  if not RunSuperMacro or not GetSuperMacroInfo then
    return false, "SuperMacro API is unavailable"
  end

  local body = GetSuperMacroInfo(name, "body")
  if not body then
    return false, "SuperMacro not found: " .. name
  end
  local texture = GetSuperMacroInfo(name, "texture")

  self:SetSlot(slotIndex, {
    type = "supermacro",
    name = name,
    texture = texture,
    body = body,
  })
  return true
end

function module:GetActionTexture(action)
  if not action then
    return nil
  end

  if action.type == "spell" then
    local spellSlot, bookType = self:FindSpell(action)
    if spellSlot and GetSpellTexture then
      return GetSpellTexture(spellSlot, bookType) or action.texture
    end
  elseif action.type == "item" then
    -- On some 1.12-derived clients GetItemInfo() can expose a non-path value
    -- in the icon return position. Passing that number to Texture:SetTexture
    -- produces a solid colored square. Prefer the concrete bag/equipment
    -- location, whose texture APIs return the actual icon path.
    local location, first, second = self:FindItemLocation(action)
    if location == "bag" and GetContainerItemInfo then
      local texture = GetContainerItemInfo(first, second)
      if validTexturePath(texture) then
        action.texture = texture
        return texture
      end
    elseif location == "inventory" and GetInventoryItemTexture then
      local texture = GetInventoryItemTexture("player", first)
      if validTexturePath(texture) then
        action.texture = texture
        return texture
      end
    end

    if GetItemInfo then
      local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(action.link or action.itemId or action.name)
      if validTexturePath(texture) then
        action.texture = texture
        return texture
      end
    end
  elseif action.type == "macro" then
    local index = self:FindMacroIndex(action.name, action.macroIndex)
    if index and GetMacroInfo then
      local name, texture, body = GetMacroInfo(index)
      local resolved = self:ResolveMacroTexture(texture)
      action.macroIndex = index
      if name then
        action.name = name
      end
      if body then
        action.body = body
      end
      if resolved then
        action.texture = resolved
        return resolved
      end
    end
  elseif action.type == "supermacro" and GetSuperMacroInfo then
    local texture = GetSuperMacroInfo(action.name, "texture")
    if texture then
      return texture
    end
  end

  if validTexturePath(action.texture) then
    return action.texture
  end
  return nil
end

function module:GetActionCooldown(action)
  if not action then
    return 0, 0, 0
  end

  if action.type == "spell" and GetSpellCooldown then
    local spellSlot, bookType = self:FindSpell(action)
    if spellSlot then
      return GetSpellCooldown(spellSlot, bookType)
    end
  elseif action.type == "item" then
    local location, a, b = self:FindItemLocation(action)
    if location == "bag" and GetContainerItemCooldown then
      return GetContainerItemCooldown(a, b)
    end
    if location == "inventory" and GetInventoryItemCooldown then
      return GetInventoryItemCooldown("player", a)
    end
  end

  return 0, 0, 0
end

function module:ShowSlotTooltip(slotIndex, button)
  if not GameTooltip then
    return
  end

  local action = self:GetSlot(slotIndex)
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

  if not action then
    GameTooltip:SetText("Extra Action Slot " .. slotIndex)
    GameTooltip:AddLine("Drag a spell, item, or regular macro here.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("/otb super " .. slotIndex .. " <name> for a SuperMacro.", 0.8, 0.8, 0.8, true)
  elseif action.type == "spell" then
    local spellSlot, bookType = self:FindSpell(action)
    if spellSlot and GameTooltip.SetSpell then
      GameTooltip:SetSpell(spellSlot, bookType)
    else
      GameTooltip:SetText(action.name or "Spell")
      if action.rank and action.rank ~= "" then
        GameTooltip:AddLine(action.rank, 0.8, 0.8, 0.8)
      end
    end
  elseif action.type == "item" then
    if action.link and GameTooltip.SetHyperlink then
      GameTooltip:SetHyperlink(action.link)
    else
      GameTooltip:SetText(action.name or (action.itemId and ("Item " .. action.itemId)) or "Item")
    end
  elseif action.type == "macro" then
    local body = action.body
    local index = self:FindMacroIndex(action.name, action.macroIndex)
    if index and GetMacroInfo then
      local liveName, _, liveBody = GetMacroInfo(index)
      action.macroIndex = index
      if liveName then
        action.name = liveName
      end
      if liveBody then
        body = liveBody
        action.body = liveBody
      end
    elseif GetMacroBody and action.name then
      body = GetMacroBody(action.name) or body
    end
    GameTooltip:SetText(action.name or "Macro")
    GameTooltip:AddLine("Macro", 0.65, 0.8, 1.0)
    if body and body ~= "" then
      body = string.gsub(body, "[\r\n]+", " / ")
      GameTooltip:AddLine(string.sub(body, 1, 180), 0.8, 0.8, 0.8, true)
    end
  elseif action.type == "supermacro" then
    GameTooltip:SetText(action.name or "SuperMacro")
    GameTooltip:AddLine("SuperMacro", 0.65, 0.8, 1.0)
    local body = action.body
    if GetSuperMacroInfo then
      body = GetSuperMacroInfo(action.name, "body") or body
    end
    if body and body ~= "" then
      body = string.gsub(body, "[\r\n]+", " / ")
      GameTooltip:AddLine(string.sub(body, 1, 180), 0.8, 0.8, 0.8, true)
    end
  end

  local key = self:GetSlotBinding(slotIndex)
  if key then
    GameTooltip:AddLine("Binding: " .. key, 1.0, 0.82, 0.0)
  else
    GameTooltip:AddLine("Binding: none", 0.55, 0.55, 0.55)
  end
  if action then
    if self.pendingMoveSource == slotIndex then
      GameTooltip:AddLine("Move selected - Shift + Left Click another slot", 1.0, 0.82, 0.0, true)
    else
      GameTooltip:AddLine("Shift + Left Click: move/swap action", 0.55, 0.55, 0.55, true)
    end
  elseif self.pendingMoveSource then
    GameTooltip:AddLine("Shift + Left Click: move selected action here", 1.0, 0.82, 0.0, true)
  end
  GameTooltip:AddLine("Shift + Right Click: clear action", 0.55, 0.55, 0.55)
  GameTooltip:Show()
end

function module:RefreshButton(slotIndex)
  local button = self.buttons[slotIndex]
  if not button then
    return
  end

  local action = self:GetSlot(slotIndex)
  local texture = self:GetActionTexture(action)
  if texture then
    button.icon:SetTexture(texture)
    button.icon:Show()
  else
    button.icon:SetTexture(nil)
    button.icon:Hide()
  end

  local key = self:GetSlotBinding(slotIndex)
  button.hotkey:SetText(self:ShortBinding(key))

  if action and action.type == "item" then
    local count = self:GetItemCount(action)
    if count and count > 1 then
      button.count:SetText(count)
      button.count:Show()
    else
      button.count:SetText("")
      button.count:Hide()
    end
  else
    button.count:SetText("")
    button.count:Hide()
  end

  if button.cooldown and CooldownFrame_SetTimer then
    local start, duration, enable = self:GetActionCooldown(action)
    CooldownFrame_SetTimer(button.cooldown, start or 0, duration or 0, enable or 0)
  end

  if button.moveMark then
    if self.pendingMoveSource == slotIndex then
      button.moveMark:Show()
    else
      button.moveMark:Hide()
    end
  end
end

function module:RefreshAllButtons()
  local i
  for i = 1, MAX_SLOTS do
    if self.buttons[i] then
      self:RefreshButton(i)
    end
  end
end

function module:IsFocusInside(frame)
  if not GetMouseFocus then
    return false
  end
  local focus = GetMouseFocus()
  local depth = 0
  while focus and depth < 10 do
    if focus == frame then
      return true
    end
    if not focus.GetParent then
      break
    end
    focus = focus:GetParent()
    depth = depth + 1
  end
  return false
end

function module:ApplyBarVisibility(barIndex)
  local db = self:EnsureData()
  local bar = self.bars[barIndex]
  if not bar then
    return
  end

  if barIndex > db.barCount then
    bar:Hide()
    return
  end

  local cfg = db.bars[barIndex]
  if not db.locked then
    bar:Show()
    bar:SetAlpha(1)
    return
  end

  if cfg.mode == "toggle" then
    if cfg.visible then
      bar:Show()
      bar:SetAlpha(1)
    else
      bar:Hide()
    end
  elseif cfg.mode == "hold" then
    if self.holdActive then
      bar:Show()
      bar:SetAlpha(1)
    else
      bar:Hide()
    end
  elseif cfg.mode == "hover" then
    bar:Show()
    if self:IsFocusInside(bar) then
      bar:SetAlpha(1)
    else
      bar:SetAlpha(HOVER_ALPHA)
    end
  else
    bar:Show()
    bar:SetAlpha(1)
  end
end

function module:ApplyAllVisibility()
  local i
  for i = 1, MAX_BARS do
    self:ApplyBarVisibility(i)
  end
  self:UpdateHandles()
end

function module:SetHold(active)
  self.holdActive = active and true or false
  local i
  for i = 1, MAX_BARS do
    local cfg = self:EnsureData().bars[i]
    if cfg.mode == "hold" then
      self:ApplyBarVisibility(i)
    end
  end
end

function module:ToggleToggleBars()
  local db = self:EnsureData()
  local any = false
  local makeVisible = false
  local i

  for i = 1, db.barCount do
    local cfg = db.bars[i]
    if cfg.mode == "toggle" then
      any = true
      if not cfg.visible then
        makeVisible = true
      end
    end
  end

  if not any then
    OT:Print("no Extra Bar is currently in toggle mode")
    return
  end

  for i = 1, db.barCount do
    local cfg = db.bars[i]
    if cfg.mode == "toggle" then
      cfg.visible = makeVisible
      self:ApplyBarVisibility(i)
    end
  end
end

function module:ToggleBar(barIndex)
  local db = self:EnsureData()
  barIndex = tonumber(barIndex)
  if not barIndex or barIndex < 1 or barIndex > db.barCount then
    return false, "bar must be between 1 and " .. db.barCount
  end
  local cfg = db.bars[barIndex]
  if cfg.mode ~= "toggle" then
    return false, "bar " .. barIndex .. " is in " .. cfg.mode .. " mode"
  end
  cfg.visible = not cfg.visible
  self:ApplyBarVisibility(barIndex)
  return true
end

function module:SetBarMode(barIndex, mode)
  local db = self:EnsureData()
  barIndex = tonumber(barIndex)
  mode = string.lower(trim(mode))
  if not barIndex or barIndex < 1 or barIndex > MAX_BARS then
    return false, "bar must be between 1 and " .. MAX_BARS
  end
  if mode ~= "always" and mode ~= "hover" and mode ~= "toggle" and mode ~= "hold" then
    return false, "mode must be always, hover, toggle, or hold"
  end
  db.bars[barIndex].mode = mode
  self:UpdateBarLabel(barIndex)
  self:ApplyBarVisibility(barIndex)
  self:RefreshSettingsPanel()
  return true
end

function module:SetBarColumns(barIndex, columns)
  local db = self:EnsureData()
  barIndex = tonumber(barIndex)
  columns = tonumber(columns)
  if not barIndex or barIndex < 1 or barIndex > MAX_BARS then
    return false, "bar must be between 1 and " .. MAX_BARS
  end
  if not columns then
    return false, "columns must be a number"
  end
  columns = clamp(math.floor(columns), 1, SLOTS_PER_BAR)
  db.bars[barIndex].columns = columns
  self:LayoutBar(barIndex)
  self:RefreshSettingsPanel()
  return true
end

function module:SetBarScale(barIndex, scale)
  local db = self:EnsureData()
  barIndex = tonumber(barIndex)
  scale = tonumber(scale)
  if not barIndex or barIndex < 1 or barIndex > MAX_BARS then
    return false, "bar must be between 1 and " .. MAX_BARS
  end
  if not scale then
    return false, "scale must be a number"
  end
  scale = clamp(scale, 0.5, 2.0)
  db.bars[barIndex].scale = scale
  if self.bars[barIndex] then
    self.bars[barIndex]:SetScale(scale)
  end
  self:RefreshSettingsPanel()
  return true
end

function module:SetBarCount(count)
  local db = self:EnsureData()
  count = tonumber(count)
  if not count then
    return false, "bar count must be a number"
  end
  db.barCount = clamp(math.floor(count), 1, MAX_BARS)
  if self.settingsBar > db.barCount then
    self.settingsBar = db.barCount
  end
  self:ApplyAllVisibility()
  self:RefreshSettingsPanel()
  return true
end

function module:SetLocked(locked)
  local db = self:EnsureData()
  db.locked = locked and true or false
  self:ApplyAllVisibility()
  self:RefreshSettingsPanel()
  OT:Print("Extra Bars " .. (db.locked and "locked" or "unlocked"))
end

function module:ApplyButtonGeometry(button)
  if not button then
    return
  end

  local db = self:EnsureData()
  local size = db.buttonSize
  local inset = clamp(db.iconInset, 1, math.floor((size - 4) / 2))

  button:SetWidth(size)
  button:SetHeight(size)

  if button.icon then
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
  end
end

function module:RelayoutAllBars()
  local i
  for i = 1, MAX_BARS do
    self:LayoutBar(i)
  end
end

function module:SetButtonSize(size)
  local db = self:EnsureData()
  size = tonumber(size)
  if not size then
    return false, "button size must be a number"
  end
  db.buttonSize = clamp(math.floor(size), MIN_BUTTON_SIZE, MAX_BUTTON_SIZE)
  self:RelayoutAllBars()
  self:RefreshSettingsPanel()
  return true
end

function module:SetButtonSpacing(spacing)
  local db = self:EnsureData()
  spacing = tonumber(spacing)
  if not spacing then
    return false, "button spacing must be a number"
  end
  db.buttonSpacing = clamp(math.floor(spacing), 0, MAX_BUTTON_SPACING)
  self:RelayoutAllBars()
  self:RefreshSettingsPanel()
  return true
end

function module:SetIconInset(inset)
  local db = self:EnsureData()
  inset = tonumber(inset)
  if not inset then
    return false, "icon inset must be a number"
  end
  db.iconInset = clamp(math.floor(inset), 1, MAX_ICON_INSET)
  self:RelayoutAllBars()
  self:RefreshSettingsPanel()
  return true
end

function module:UpdateBarLabel(barIndex)
  local bar = self.bars[barIndex]
  local db = self:EnsureData()
  if bar and bar.handle and bar.handle.text then
    bar.handle.text:SetText("OT" .. barIndex .. "  " .. db.bars[barIndex].mode)
  end
end

function module:UpdateHandles()
  local db = self:EnsureData()
  local i
  for i = 1, MAX_BARS do
    local bar = self.bars[i]
    if bar and bar.handle then
      if not db.locked and i <= db.barCount then
        bar.handle:Show()
      else
        bar.handle:Hide()
      end
    end
  end
end

function module:SaveFramePosition(frame, cfg)
  if not frame or not cfg then
    return
  end
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  cfg.point = point or cfg.point
  cfg.relativePoint = relativePoint or cfg.relativePoint
  cfg.x = x or 0
  cfg.y = y or 0
end

function module:ResetLayout()
  local db = self:EnsureData()
  db.buttonSize = DEFAULT_BUTTON_SIZE
  db.buttonSpacing = DEFAULT_BUTTON_SPACING
  db.iconInset = DEFAULT_ICON_INSET
  local i
  for i = 1, MAX_BARS do
    local cfg = db.bars[i]
    cfg.point = "BOTTOM"
    cfg.relativePoint = "BOTTOM"
    cfg.x = 0
    cfg.y = defaultBarY(i)
    cfg.scale = 1
    cfg.columns = 12
    local bar = self.bars[i]
    if bar then
      bar:ClearAllPoints()
      bar:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)
      bar:SetScale(cfg.scale)
      self:LayoutBar(i)
    end
  end

  local launcher = db.launcher
  launcher.point = "TOPRIGHT"
  launcher.relativePoint = "TOPRIGHT"
  launcher.x = -220
  launcher.y = -8
  if self.launcher then
    self.launcher:ClearAllPoints()
    self.launcher:SetPoint(launcher.point, UIParent, launcher.relativePoint, launcher.x, launcher.y)
  end

  self:RelayoutAllBars()
  self:RefreshSettingsPanel()
end

function module:LayoutBar(barIndex)
  local bar = self.bars[barIndex]
  if not bar then
    return
  end
  local db = self:EnsureData()
  local cfg = db.bars[barIndex]
  local columns = clamp(tonumber(cfg.columns) or 12, 1, SLOTS_PER_BAR)
  local rows = math.ceil(SLOTS_PER_BAR / columns)
  local buttonSize = db.buttonSize
  local spacing = db.buttonSpacing
  local width = (columns * buttonSize) + ((columns - 1) * spacing)
  local height = (rows * buttonSize) + ((rows - 1) * spacing)
  bar:SetWidth(width)
  bar:SetHeight(height)

  if bar.handle then
    bar.handle:SetWidth(math.min(width, 130))
  end

  local localIndex
  for localIndex = 1, SLOTS_PER_BAR do
    local slotIndex = ((barIndex - 1) * SLOTS_PER_BAR) + localIndex
    local button = self.buttons[slotIndex]
    if button then
      local zero = localIndex - 1
      local row = math.floor(zero / columns)
      local col = math.mod(zero, columns)
      self:ApplyButtonGeometry(button)
      button:ClearAllPoints()
      button:SetPoint(
        "TOPLEFT",
        bar,
        "TOPLEFT",
        col * (buttonSize + spacing),
        -(row * (buttonSize + spacing))
      )
    end
  end
end

function module:CreateButton(bar, slotIndex)
  local name = "OctoTweaksExtraActionButton" .. slotIndex
  local button = CreateFrame("Button", name, bar)
  button:SetWidth(DEFAULT_BUTTON_SIZE)
  button:SetHeight(DEFAULT_BUTTON_SIZE)
  button:EnableMouse(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button.OctoTweaksExtraActionSlot = slotIndex

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints(button)
  background:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  background:SetVertexColor(0, 0, 0)
  background:SetAlpha(0.42)
  button.background = background

  local icon = button:CreateTexture(name .. "Icon", "ARTWORK")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  button.icon = icon

  local function makeBorderEdge(point1, relativePoint1, x1, y1, point2, relativePoint2, x2, y2)
    local edge = button:CreateTexture(nil, "OVERLAY")
    edge:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    edge:SetVertexColor(0.38, 0.38, 0.38)
    edge:SetAlpha(0.92)
    edge:SetPoint(point1, button, relativePoint1, x1, y1)
    edge:SetPoint(point2, button, relativePoint2, x2, y2)
    return edge
  end

  local topEdge = makeBorderEdge("TOPLEFT", "TOPLEFT", 0, 0, "TOPRIGHT", "TOPRIGHT", 0, 0)
  topEdge:SetHeight(1)
  local bottomEdge = makeBorderEdge("BOTTOMLEFT", "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0)
  bottomEdge:SetHeight(1)
  local leftEdge = makeBorderEdge("TOPLEFT", "TOPLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0)
  leftEdge:SetWidth(1)
  local rightEdge = makeBorderEdge("TOPRIGHT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0)
  rightEdge:SetWidth(1)
  button.border = { topEdge, bottomEdge, leftEdge, rightEdge }

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
  highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  highlight:SetBlendMode("ADD")

  local hotkey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  hotkey:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
  hotkey:SetJustifyH("RIGHT")
  button.hotkey = hotkey

  local moveMark = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  moveMark:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
  moveMark:SetText("M")
  moveMark:SetTextColor(1.0, 0.82, 0.0)
  moveMark:Hide()
  button.moveMark = moveMark

  local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
  count:SetJustifyH("RIGHT")
  button.count = count

  local cooldown = CreateFrame("Model", name .. "Cooldown", button, "CooldownFrameTemplate")
  cooldown:SetAllPoints(button)
  button.cooldown = cooldown

  self:ApplyButtonGeometry(button)

  button:SetScript("OnEnter", function()
    module:ShowSlotTooltip(slotIndex, button)
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  button:SetScript("OnReceiveDrag", function()
    if module.qbindActive then
      return
    end
    local ok, reason = module:ReceiveCursor(slotIndex)
    if ok then
      -- On this client a drop can be followed by OnClick on the destination.
      -- Without this guard, dropping an item may immediately use/equip it and
      -- dropping a spell may immediately cast it.
      button.OctoTweaksSuppressNextClick = true
    elseif reason ~= "cursor is empty" then
      OT:Print("extra slot " .. slotIndex .. ": " .. tostring(reason))
    end
  end)
  button:SetScript("OnMouseDown", function()
    local mouseButton = arg1

    if not module.qbindActive then
      -- A stale drop-suppression flag must never eat the next genuine click.
      -- OnMouseDown on this button cannot be part of the external drag that
      -- produced OnReceiveDrag, so it is safe to clear here.
      button.OctoTweaksSuppressNextClick = false
      if mouseButton == "LeftButton" then
        -- Remember the modifier at press time. OctoWoW can report the Shift
        -- state differently by the later OnClick/LeftButtonUp callback.
        button.OctoTweaksShiftLeftDown = shiftIsDown()
      end
      return
    end

    if mouseButton == "LeftButton" or mouseButton == "RightButton" then
      return
    end
    local key = module:BuildBindingKey(mouseButton)
    if key then
      local ok, reason = module:BindSlot(slotIndex, key)
      if ok then
        OT:Print("extra slot " .. slotIndex .. " bound to " .. key)
      else
        OT:Print("could not bind extra slot " .. slotIndex .. ": " .. tostring(reason))
      end
    end
  end)
  if button.EnableMouseWheel then
    button:EnableMouseWheel(false)
    button:SetScript("OnMouseWheel", function()
      if not module.qbindActive then
        return
      end
      local keyName
      if arg1 and arg1 > 0 then
        keyName = "MOUSEWHEELUP"
      else
        keyName = "MOUSEWHEELDOWN"
      end
      local key = module:BuildBindingKey(keyName)
      if key then
        local ok, reason = module:BindSlot(slotIndex, key)
        if ok then
          OT:Print("extra slot " .. slotIndex .. " bound to " .. key)
        else
          OT:Print("could not bind extra slot " .. slotIndex .. ": " .. tostring(reason))
        end
      end
    end)
  end
  button:SetScript("OnClick", function()
    if module.qbindActive then
      return
    end

    if button.OctoTweaksSuppressNextClick then
      button.OctoTweaksSuppressNextClick = false
      button.OctoTweaksShiftLeftDown = false
      return
    end

    local kind
    if GetCursorInfo then
      kind = GetCursorInfo()
    end

    local shiftLeftClick = false
    if arg1 == "LeftButton" then
      shiftLeftClick = button.OctoTweaksShiftLeftDown or shiftIsDown()
    end
    button.OctoTweaksShiftLeftDown = false

    if shiftLeftClick and not kind then
      local ok, reason = module:HandleMoveClick(slotIndex)
      if not ok and reason ~= "source slot is empty" then
        OT:Print("extra slot " .. slotIndex .. ": " .. tostring(reason))
      end
      return
    end

    if arg1 == "RightButton" then
      if IsShiftKeyDown and IsShiftKeyDown() then
        if module.pendingMoveSource == slotIndex then
          module:CancelMoveSelection()
        end
        module:ClearSlot(slotIndex)
        OT:Print("cleared extra action slot " .. slotIndex)
      end
      return
    end

    if kind then
      local ok, reason = module:ReceiveCursor(slotIndex)
      if not ok then
        OT:Print("extra slot " .. slotIndex .. ": " .. tostring(reason))
      end
      return
    end

    module:UseSlot(slotIndex)
  end)

  self.buttons[slotIndex] = button
  return button
end

function module:CreateBar(barIndex)
  local name = "OctoTweaksExtraActionBar" .. barIndex
  local cfg = self:EnsureData().bars[barIndex]
  local bar = CreateFrame("Frame", name, UIParent)
  bar:SetFrameStrata("MEDIUM")
  bar:EnableMouse(true)
  bar:SetMovable(true)
  if bar.SetClampedToScreen then
    bar:SetClampedToScreen(true)
  end
  bar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  bar:SetBackdropColor(0, 0, 0, 0.28)
  bar:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)
  bar:SetScale(cfg.scale)
  bar:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)

  local handle = CreateFrame("Button", name .. "Handle", bar)
  handle:SetHeight(13)
  handle:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
  handle:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  handle:SetBackdropColor(0, 0, 0, 0.85)
  handle:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
  handle:RegisterForDrag("LeftButton")
  handle:EnableMouse(true)
  if handle.SetFrameLevel and bar.GetFrameLevel then
    handle:SetFrameLevel(bar:GetFrameLevel() + 5)
  end
  bar.handle = handle

  local text = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("CENTER", handle, "CENTER", 0, 0)
  handle.text = text

  handle:SetScript("OnDragStart", function()
    if not module:EnsureData().locked then
      bar:StartMoving()
    end
  end)
  handle:SetScript("OnDragStop", function()
    bar:StopMovingOrSizing()
    module:SaveFramePosition(bar, module:EnsureData().bars[barIndex])
  end)
  handle:SetScript("OnEnter", function()
    if GameTooltip then
      GameTooltip:SetOwner(handle, "ANCHOR_TOP")
      GameTooltip:SetText("OctoTweaks Extra Bar " .. barIndex)
      GameTooltip:AddLine("Drag this handle to move the bar.", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Mode: " .. module:EnsureData().bars[barIndex].mode, 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end
  end)
  handle:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  local localIndex
  for localIndex = 1, SLOTS_PER_BAR do
    local slotIndex = ((barIndex - 1) * SLOTS_PER_BAR) + localIndex
    self:CreateButton(bar, slotIndex)
  end

  bar:SetScript("OnUpdate", function()
    local db = module:EnsureData()
    if db.locked and db.bars[barIndex].mode == "hover" and bar:IsShown() then
      if module:IsFocusInside(bar) then
        if bar:GetAlpha() ~= 1 then
          bar:SetAlpha(1)
        end
      elseif bar:GetAlpha() ~= HOVER_ALPHA then
        bar:SetAlpha(HOVER_ALPHA)
      end
    end
  end)

  self.bars[barIndex] = bar
  self:LayoutBar(barIndex)
  self:UpdateBarLabel(barIndex)
  return bar
end

local function createSettingsButton(parent, width, height, label)
  local button = CreateFrame("Button", nil, parent)
  button:SetWidth(width)
  button:SetHeight(height)
  button:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  button:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
  button:SetBackdropBorderColor(0.42, 0.42, 0.42, 1)

  local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("CENTER", button, "CENTER", 0, 0)
  text:SetText(label or "")
  button.text = text

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
  highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
  highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  highlight:SetBlendMode("ADD")
  return button
end

local function createSettingsLabel(parent, text, x, y)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  label:SetText(text)
  label:SetJustifyH("LEFT")
  return label
end

function module:RefreshSettingsPanel()
  local frame = self.settingsFrame
  if not frame or not frame:IsShown() then
    return
  end

  local db = self:EnsureData()
  local barIndex = clamp(self.settingsBar or 1, 1, db.barCount)
  self.settingsBar = barIndex
  local cfg = db.bars[barIndex]

  frame.lockButton.text:SetText(db.locked and "Unlock bars" or "Lock bars")
  frame.qbindButton.text:SetText(self.qbindActive and "Quick Bind: ON" or "Quick Bind: OFF")
  frame.barCountValue:SetText(tostring(db.barCount))
  frame.buttonSizeValue:SetText(tostring(db.buttonSize))
  frame.spacingValue:SetText(tostring(db.buttonSpacing))
  frame.iconInsetValue:SetText(tostring(db.iconInset))
  frame.selectedBarValue:SetText("Bar " .. barIndex)
  frame.modeButton.text:SetText("Mode: " .. cfg.mode)
  frame.columnsValue:SetText(tostring(cfg.columns))
  frame.scaleValue:SetText(string.format("%.2f", cfg.scale))

  if db.locked then
    frame.moveHint:SetText("Bars locked. Click Unlock bars to move them.")
  else
    frame.moveHint:SetText("Move: drag the OT1 / OT2 / ... handle above each bar.")
  end
end

function module:ToggleSettings(forceShown)
  if not self.settingsFrame then
    return
  end

  local show
  if forceShown == nil then
    show = not self.settingsFrame:IsShown()
  else
    show = forceShown and true or false
  end

  if show then
    self.settingsFrame:Show()
    self:RefreshSettingsPanel()
  else
    self.settingsFrame:Hide()
  end
end

function module:CycleBarMode(barIndex)
  local cfg = self:EnsureData().bars[barIndex]
  local nextMode = "always"
  if cfg.mode == "always" then
    nextMode = "hover"
  elseif cfg.mode == "hover" then
    nextMode = "toggle"
  elseif cfg.mode == "toggle" then
    nextMode = "hold"
  end
  self:SetBarMode(barIndex, nextMode)
end

function module:CreateSettingsFrame()
  local frame = CreateFrame("Frame", "OctoTweaksExtraBarsSettings", UIParent)
  frame:SetWidth(390)
  frame:SetHeight(350)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  if frame.SetClampedToScreen then
    frame:SetClampedToScreen(true)
  end
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.03, 0.03, 0.03, 0.96)
  frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)

  local titleBar = CreateFrame("Button", nil, frame)
  titleBar:SetHeight(24)
  titleBar:EnableMouse(true)
  titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7)
  titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -7)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)

  local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", titleBar, "LEFT", 4, 0)
  title:SetText("OctoTweaks Action Bars")

  local close = createSettingsButton(frame, 22, 20, "X")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  frame.moveHint = createSettingsLabel(frame, "", 16, -42)

  createSettingsLabel(frame, "General", 16, -69)
  createSettingsLabel(frame, "Active bars", 24, -96)
  createSettingsLabel(frame, "Button size", 24, -123)
  createSettingsLabel(frame, "Icon margin", 24, -150)
  createSettingsLabel(frame, "Slot spacing", 24, -177)

  local function addMinusPlusRow(y, valueName, minusCallback, plusCallback)
    local minus = createSettingsButton(frame, 24, 20, "-")
    minus:SetPoint("TOPLEFT", frame, "TOPLEFT", 190, y)
    minus:SetScript("OnClick", minusCallback)

    local value = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("CENTER", minus, "CENTER", 54, 0)
    value:SetText("0")
    frame[valueName] = value

    local plus = createSettingsButton(frame, 24, 20, "+")
    plus:SetPoint("TOPLEFT", frame, "TOPLEFT", 280, y)
    plus:SetScript("OnClick", plusCallback)
  end

  addMinusPlusRow(-87, "barCountValue", function()
    module:SetBarCount(module:EnsureData().barCount - 1)
  end, function()
    module:SetBarCount(module:EnsureData().barCount + 1)
  end)

  addMinusPlusRow(-114, "buttonSizeValue", function()
    module:SetButtonSize(module:EnsureData().buttonSize - 1)
  end, function()
    module:SetButtonSize(module:EnsureData().buttonSize + 1)
  end)

  addMinusPlusRow(-141, "iconInsetValue", function()
    module:SetIconInset(module:EnsureData().iconInset - 1)
  end, function()
    module:SetIconInset(module:EnsureData().iconInset + 1)
  end)

  addMinusPlusRow(-168, "spacingValue", function()
    module:SetButtonSpacing(module:EnsureData().buttonSpacing - 1)
  end, function()
    module:SetButtonSpacing(module:EnsureData().buttonSpacing + 1)
  end)

  frame.lockButton = createSettingsButton(frame, 112, 22, "Unlock bars")
  frame.lockButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -204)
  frame.lockButton:SetScript("OnClick", function()
    module:SetLocked(not module:EnsureData().locked)
  end)

  frame.qbindButton = createSettingsButton(frame, 112, 22, "Quick Bind: OFF")
  frame.qbindButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 146, -204)
  frame.qbindButton:SetScript("OnClick", function()
    module:SetQBindMode(not module.qbindActive)
  end)

  local reset = createSettingsButton(frame, 98, 22, "Reset layout")
  reset:SetPoint("TOPLEFT", frame, "TOPLEFT", 268, -204)
  reset:SetScript("OnClick", function()
    module:ResetLayout()
    OT:Print("Extra Bars layout and visual sizing reset; slot contents and bindings were preserved")
  end)

  createSettingsLabel(frame, "Selected bar", 16, -244)
  local prev = createSettingsButton(frame, 24, 20, "<")
  prev:SetPoint("TOPLEFT", frame, "TOPLEFT", 112, -236)
  prev:SetScript("OnClick", function()
    module.settingsBar = clamp((module.settingsBar or 1) - 1, 1, module:EnsureData().barCount)
    module:RefreshSettingsPanel()
  end)
  frame.selectedBarValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.selectedBarValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 151, -239)
  frame.selectedBarValue:SetWidth(62)
  frame.selectedBarValue:SetJustifyH("CENTER")
  local nextButton = createSettingsButton(frame, 24, 20, ">")
  nextButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 220, -236)
  nextButton:SetScript("OnClick", function()
    module.settingsBar = clamp((module.settingsBar or 1) + 1, 1, module:EnsureData().barCount)
    module:RefreshSettingsPanel()
  end)

  frame.modeButton = createSettingsButton(frame, 116, 22, "Mode: always")
  frame.modeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 250, -236)
  frame.modeButton:SetScript("OnClick", function()
    module:CycleBarMode(module.settingsBar or 1)
  end)

  createSettingsLabel(frame, "Columns", 24, -278)
  local colsMinus = createSettingsButton(frame, 24, 20, "-")
  colsMinus:SetPoint("TOPLEFT", frame, "TOPLEFT", 96, -269)
  colsMinus:SetScript("OnClick", function()
    local cfg = module:EnsureData().bars[module.settingsBar or 1]
    module:SetBarColumns(module.settingsBar or 1, cfg.columns - 1)
  end)
  frame.columnsValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.columnsValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 135, -274)
  frame.columnsValue:SetWidth(34)
  frame.columnsValue:SetJustifyH("CENTER")
  local colsPlus = createSettingsButton(frame, 24, 20, "+")
  colsPlus:SetPoint("TOPLEFT", frame, "TOPLEFT", 176, -269)
  colsPlus:SetScript("OnClick", function()
    local cfg = module:EnsureData().bars[module.settingsBar or 1]
    module:SetBarColumns(module.settingsBar or 1, cfg.columns + 1)
  end)

  createSettingsLabel(frame, "Scale", 218, -278)
  local scaleMinus = createSettingsButton(frame, 24, 20, "-")
  scaleMinus:SetPoint("TOPLEFT", frame, "TOPLEFT", 270, -269)
  scaleMinus:SetScript("OnClick", function()
    local cfg = module:EnsureData().bars[module.settingsBar or 1]
    module:SetBarScale(module.settingsBar or 1, cfg.scale - 0.05)
  end)
  frame.scaleValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.scaleValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 306, -274)
  frame.scaleValue:SetWidth(34)
  frame.scaleValue:SetJustifyH("CENTER")
  local scalePlus = createSettingsButton(frame, 24, 20, "+")
  scalePlus:SetPoint("TOPLEFT", frame, "TOPLEFT", 344, -269)
  scalePlus:SetScript("OnClick", function()
    local cfg = module:EnsureData().bars[module.settingsBar or 1]
    module:SetBarScale(module.settingsBar or 1, cfg.scale + 0.05)
  end)

  local toggleSelected = createSettingsButton(frame, 158, 22, "Toggle selected bar")
  toggleSelected:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 16)
  toggleSelected:SetScript("OnClick", function()
    local cfg = module:EnsureData().bars[module.settingsBar or 1]
    if cfg.mode == "toggle" then
      module:ToggleBar(module.settingsBar or 1)
    else
      OT:Print("selected bar is in " .. cfg.mode .. " mode; toggle visibility applies only to toggle mode")
    end
  end)

  local done = createSettingsButton(frame, 92, 22, "Close")
  done:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 16)
  done:SetScript("OnClick", function()
    frame:Hide()
  end)

  frame:Hide()
  self.settingsFrame = frame
end

function module:CreateLauncher()
  local db = self:EnsureData()
  local cfg = db.launcher
  local button = CreateFrame("Button", "OctoTweaksExtraBarsLauncher", UIParent)
  button:SetWidth(30)
  button:SetHeight(18)
  button:SetFrameStrata("HIGH")
  button:SetMovable(true)
  button:EnableMouse(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetPoint(cfg.point, UIParent, cfg.relativePoint, cfg.x, cfg.y)
  button:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  button:SetBackdropColor(0, 0, 0, 0.8)
  button:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)

  local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("CENTER", button, "CENTER", 0, 0)
  text:SetText("OTB")
  button.text = text

  button:SetScript("OnClick", function()
    if module.suppressLauncherClick then
      local suppress = true
      if GetTime and module.launcherDragEndedAt then
        suppress = (GetTime() - module.launcherDragEndedAt) < 0.35
      end
      module.suppressLauncherClick = false
      module.launcherDragEndedAt = nil
      if suppress then
        return
      end
    end

    if arg1 == "RightButton" then
      if IsShiftKeyDown and IsShiftKeyDown() then
        module:SetLocked(not module:EnsureData().locked)
      else
        module:ToggleSettings()
      end
    elseif arg1 == "MiddleButton" then
      module:SetQBindMode(not module.qbindActive)
    else
      module:ToggleToggleBars()
    end
  end)
  button:SetScript("OnDragStart", function()
    if IsControlKeyDown and IsControlKeyDown() then
      module.launcherDragging = true
      module.suppressLauncherClick = true
      button:StartMoving()
    end
  end)
  button:SetScript("OnDragStop", function()
    if module.launcherDragging then
      button:StopMovingOrSizing()
      module:SaveFramePosition(button, module:EnsureData().launcher)
      module.launcherDragging = false
      if GetTime then
        module.launcherDragEndedAt = GetTime()
      end
    end
  end)
  button:SetScript("OnEnter", function()
    if GameTooltip then
      GameTooltip:SetOwner(button, "ANCHOR_LEFT")
      GameTooltip:SetText("OctoTweaks Extra Bars")
      GameTooltip:AddLine("Left click: toggle toggle-mode bars", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Middle click: quick-bind mode", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Right click: settings", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Shift + Right click: lock/unlock", 0.8, 0.8, 0.8)
      GameTooltip:AddLine("Ctrl + drag: move launcher", 0.55, 0.55, 0.55)
      GameTooltip:Show()
    end
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  if cfg.shown then
    button:Show()
  else
    button:Hide()
  end

  self.launcher = button
end

function module:CreateQBindFrame()
  local frame = CreateFrame("Frame", "OctoTweaksExtraBarsQBindCapture", UIParent)
  frame:SetWidth(1)
  frame:SetHeight(1)
  frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  frame:SetFrameStrata("TOOLTIP")
  frame:EnableKeyboard(false)
  frame:SetScript("OnKeyDown", function()
    module:HandleQBindKey(arg1)
  end)
  frame:Hide()
  self.qbindFrame = frame
end

function module:CreateRefreshFrame()
  local frame = CreateFrame("Frame", "OctoTweaksExtraBarsRefreshFrame", UIParent)
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("BAG_UPDATE")
  frame:RegisterEvent("SPELLS_CHANGED")
  frame:RegisterEvent("UPDATE_BINDINGS")
  frame:RegisterEvent("UPDATE_MACROS")
  frame:SetScript("OnEvent", function()
    module:RefreshAllButtons()
  end)
  frame:SetScript("OnUpdate", function()
    module.refreshElapsed = module.refreshElapsed + (arg1 or 0)
    if module.refreshElapsed >= REFRESH_INTERVAL then
      module.refreshElapsed = 0
      module:RefreshAllButtons()
    end
  end)
  self.refreshFrame = frame
end

function module:PrintHelp()
  OT:Print("Extra Bars commands:")
  OT:Print("/otb status | config | lock | unlock | qbind [on|off]")
  OT:Print("/otb bars <1-8> | mode <bar> <always|hover|toggle|hold>")
  OT:Print("/otb cols <bar> <1-12> | scale <bar> <0.5-2.0>")
  OT:Print("/otb size <22-48> | spacing <0-10> | inset <1-8>")
  OT:Print("/otb toggle [bar] | ui [on|off] | resetlayout")
  OT:Print("/otb bind <slot> <KEY> | unbind <slot>")
  OT:Print("/otb bindtoggle <KEY> | bindhold <KEY>")
  OT:Print("/otb clear <slot> | item <slot> <name/link/id>")
  OT:Print("/otb macro <slot> <regular macro name/index> | super <slot> <SuperMacro name>")
end

function module:PrintStatus()
  local db = self:EnsureData()
  OT:Print("Extra Bars: " .. db.barCount .. " bar(s), " .. (db.locked and "locked" or "unlocked") .. ", qbind " .. (self.qbindActive and "ON" or "OFF"))
  OT:Print("visuals: size=" .. db.buttonSize .. ", icon inset=" .. db.iconInset .. ", spacing=" .. db.buttonSpacing)
  local i
  for i = 1, db.barCount do
    local cfg = db.bars[i]
    OT:Print("bar " .. i .. ": mode=" .. cfg.mode .. ", columns=" .. cfg.columns .. ", scale=" .. cfg.scale .. (cfg.mode == "toggle" and (", visible=" .. tostring(cfg.visible)) or ""))
  end
end

function module:HandleSlash(msg)
  local command, rest = splitFirst(msg)
  command = string.lower(command or "")

  if command == "" or command == "help" then
    self:PrintHelp()
    return
  end
  if command == "status" then
    self:PrintStatus()
    return
  end
  if command == "config" or command == "settings" then
    self:ToggleSettings()
    return
  end
  if command == "lock" then
    self:SetLocked(true)
    return
  end
  if command == "unlock" then
    self:SetLocked(false)
    return
  end
  if command == "qbind" then
    local value = string.lower(trim(rest))
    if value == "on" then
      self:SetQBindMode(true)
    elseif value == "off" then
      self:SetQBindMode(false)
    else
      self:SetQBindMode(not self.qbindActive)
    end
    return
  end
  if command == "bars" then
    local ok, reason = self:SetBarCount(rest)
    if not ok then
      OT:Print(reason)
    end
    return
  end
  if command == "mode" then
    local bar, mode = parseTwo(rest)
    local ok, reason = self:SetBarMode(bar, mode or "")
    if not ok then
      OT:Print(reason)
    end
    return
  end
  if command == "cols" or command == "columns" then
    local bar, columns = parseTwo(rest)
    local ok, reason = self:SetBarColumns(bar, columns)
    if not ok then
      OT:Print(reason)
    end
    return
  end
  if command == "scale" then
    local bar, scale = parseTwo(rest)
    local ok, reason = self:SetBarScale(bar, scale)
    if not ok then
      OT:Print(reason)
    end
    return
  end
  if command == "size" then
    local ok, reason = self:SetButtonSize(rest)
    if not ok then
      OT:Print(reason)
    end
    return
  end
  if command == "spacing" then
    local ok, reason = self:SetButtonSpacing(rest)
    if not ok then
      OT:Print(reason)
    end
    return
  end
  if command == "inset" or command == "iconinset" then
    local ok, reason = self:SetIconInset(rest)
    if not ok then
      OT:Print(reason)
    end
    return
  end
  if command == "toggle" then
    if trim(rest) == "" or string.lower(trim(rest)) == "all" then
      self:ToggleToggleBars()
    else
      local ok, reason = self:ToggleBar(rest)
      if not ok then
        OT:Print(reason)
      end
    end
    return
  end
  if command == "ui" or command == "launcher" then
    local value = string.lower(trim(rest))
    local launcher = self:EnsureData().launcher
    local shown

    if value == "" then
      shown = not launcher.shown
    elseif value == "on" or value == "show" then
      shown = true
    elseif value == "off" or value == "hide" then
      shown = false
    else
      OT:Print("ui expects on/off, or no argument to toggle")
      return
    end

    launcher.shown = shown
    if self.launcher then
      if shown then
        self.launcher:Show()
      else
        self.launcher:Hide()
      end
    end
    OT:Print("OTB launcher " .. (shown and "shown" or "hidden"))
    return
  end
  if command == "resetlayout" then
    self:ResetLayout()
    OT:Print("Extra Bars layout and visual sizing reset; slot contents and bindings were preserved")
    return
  end
  if command == "bind" then
    local slot, key = parseTwo(rest)
    local ok, reason = self:BindSlot(slot, trim(key))
    if ok then
      OT:Print("extra slot " .. tostring(slot) .. " bound to " .. string.upper(trim(key)))
    else
      OT:Print(reason)
    end
    return
  end
  if command == "unbind" then
    local slot = tonumber(trim(rest))
    if not slot then
      OT:Print("unbind expects a slot number")
      return
    end
    local ok, reason = self:ClearSlotBindings(slot, true)
    if ok then
      OT:Print("cleared binding for extra slot " .. slot)
    else
      OT:Print(reason)
    end
    return
  end
  if command == "bindtoggle" then
    local key = trim(rest)
    local ok, reason = self:BindUtility("OCTOTWEAKS_EXTRABARS_TOGGLE", key)
    if ok then
      OT:Print("Extra Bars toggle bound to " .. string.upper(key))
    else
      OT:Print(reason)
    end
    return
  end
  if command == "bindhold" then
    local key = trim(rest)
    local ok, reason = self:BindUtility("OCTOTWEAKS_EXTRABARS_HOLD", key)
    if ok then
      OT:Print("Extra Bars hold bound to " .. string.upper(key))
    else
      OT:Print(reason)
    end
    return
  end
  if command == "clear" then
    local slot = tonumber(trim(rest))
    if not slot or slot < 1 or slot > MAX_SLOTS then
      OT:Print("clear expects a slot between 1 and " .. MAX_SLOTS)
      return
    end
    self:ClearSlot(slot)
    OT:Print("cleared extra action slot " .. slot)
    return
  end
  if command == "macro" then
    local slot, macroToken = parseTwo(rest)
    local ok, reason = self:SetMacroSlot(slot, macroToken or "")
    if ok then
      OT:Print("extra slot " .. tostring(slot) .. " = macro " .. tostring(macroToken))
    else
      OT:Print(reason)
    end
    return
  end
  if command == "item" then
    local slot, itemToken = parseTwo(rest)
    local ok, reason = self:SetItemSlot(slot, itemToken or "")
    if ok then
      OT:Print("extra slot " .. tostring(slot) .. " = item " .. tostring(itemToken))
    else
      OT:Print(reason)
    end
    return
  end
  if command == "super" then
    local slot, name = parseTwo(rest)
    local ok, reason = self:SetSuperMacro(slot, name or "")
    if ok then
      OT:Print("extra slot " .. tostring(slot) .. " = SuperMacro " .. tostring(name))
    else
      OT:Print(reason)
    end
    return
  end

  self:PrintHelp()
end

function module:RegisterSlashCommand()
  SLASH_OCTOTWEAKSEXTRABARS1 = "/otb"
  SlashCmdList["OCTOTWEAKSEXTRABARS"] = function(msg)
    module:HandleSlash(msg or "")
  end
end

function module:probe()
  if not CreateFrame or not UIParent then
    return false, "WoW frame API unavailable"
  end
  if not GetCursorInfo then
    return false, "GetCursorInfo unavailable"
  end
  if not SetBinding or not SaveBindings or not GetCurrentBindingSet then
    return false, "WoW binding API unavailable"
  end
  if not GetSpellName or not CastSpell then
    return false, "WoW spellbook API unavailable"
  end
  return true, "WoW 1.12 action-bar prerequisites detected"
end

function module:enable()
  if self.enabled then
    return true, "already installed"
  end

  self:EnsureData()
  self:InstallMacroPickupCapture()

  local i
  for i = 1, MAX_BARS do
    self:CreateBar(i)
  end
  self:CreateSettingsFrame()
  self:CreateLauncher()
  self:CreateQBindFrame()
  self:CreateRefreshFrame()
  self:RegisterSlashCommand()
  self:ApplyAllVisibility()
  self:RefreshAllButtons()
  self.enabled = true

  return true, "96 virtual slots available; 4 bars active by default"
end

function OctoTweaks_ExtraBars_UseSlot(slotIndex)
  return module:UseSlot(slotIndex)
end

function OctoTweaks_ExtraBars_Toggle()
  return module:ToggleToggleBars()
end

function OctoTweaks_ExtraBars_SetHold(active)
  return module:SetHold(active)
end

OT:RegisterModule(module)
