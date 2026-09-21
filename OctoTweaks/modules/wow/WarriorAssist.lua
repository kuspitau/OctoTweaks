--[[
Module: wow.warrior_assist
Category: feature
Target: WoW 1.12 / OctoWoW warrior client
Runtime validation: PASS by user acceptance on OctoWoW (2026-09-21)

Purpose:
Provide one manually-triggered "smart action" for a Warrior. Each key press reads
local client state, chooses at most one configured combat action, and executes
that action through the native action slot that already contains the spell.
There is no timer/OnUpdate-driven action execution.

Required client extension APIs:
- ClassicAPI GetActionInfo(slot)
- ClassicAPI GetSpellInfo(spellID)
- ClassicAPI C_UnitAuras.GetAuraDataBySpellName(...)

Swing timing:
- primary: internal main-hand tracker driven by WoW 1.12 self-combat messages;
- fallback: SuperCleveRoidMacros swing-percent helper;
- fallback: SP_SwingTimer globals when present;
- fallback: pfUI swing timer (pfUI.swingtimer.mainhand).

The internal tracker is intentionally independent of AttackBar, but its event
strategy was cross-checked against the user-supplied AttackBar 5.0.7 source.

Compatibility notes:
The managed spells must exist on Blizzard's 1..120 native action-slot table so
IsUsableAction/IsActionInRange/GetActionCooldown and UseAction all describe and
execute the same action. The user's actual key bindings may change freely.
]]

local OT = OctoTweaks

local MAX_ACTION_SLOTS = 120
local RAGE_POWER_TYPE = 1
local DEFAULT_RESERVE_RAGE = 15
local DEFAULT_MS_OVERFLOW_RAGE = 55
local LEGACY_DEFAULT_SLAM_CAST_TIME = 0.50
local DEFAULT_SLAM_CAST_TIME_FALLBACK = 2.00
local DEFAULT_SLAM_SAFETY_MARGIN = 0.05
local DEFAULT_SLAM_LATE_TOLERANCE = 0.30
local READY_EPSILON = 0.05

local ACTION_ORDER = {
  "execute",
  "overpower",
  "sunder",
  "battleShout",
  "mortalStrike",
  "slam",
}

local ACTIONS = {
  execute = {
    name = "Execute",
    label = "Execute",
    defaultEnabled = true,
  },
  overpower = {
    name = "Overpower",
    label = "Overpower",
    defaultEnabled = true,
  },
  sunder = {
    name = "Sunder Armor",
    label = "Sunder Armor",
    defaultEnabled = true,
  },
  battleShout = {
    name = "Battle Shout",
    label = "Battle Shout",
    defaultEnabled = true,
  },
  mortalStrike = {
    name = "Mortal Strike",
    label = "Mortal Strike",
    defaultEnabled = true,
  },
  slam = {
    name = "Slam",
    label = "Slam",
    defaultEnabled = true,
  },
}

local FALLBACK_COSTS = {
  execute = 15,
  overpower = 5,
  sunder = 10,
  battleShout = 10,
  mortalStrike = 30,
  slam = 15,
}

local module = {
  id = "wow.warrior_assist",
  category = "feature",
  target = "WoW 1.12 / OctoWoW Warrior",
  defaultEnabled = true,
  testedVersion = "OctoWoW runtime PASS 2026-09-21; ClassicAPI contract source-audited",
  enabled = false,
  actions = {},
  eventFrame = nil,
  lastDecision = "not evaluated",
  lastDecisionDetail = "",
  swingStart = nil,
  swingDuration = nil,
  swingReason = nil,
  swingMessage = nil,
}

local function trim(text)
  text = tostring(text or "")
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  return text
end

local function splitFirst(text)
  local _, _, first, rest = string.find(trim(text), "^(%S+)%s*(.-)$")
  return first, rest or ""
end

local function parseTwo(text)
  local _, _, first, second = string.find(trim(text), "^(%S+)%s+(.+)$")
  return first, second
end

local function boolText(value)
  if value then
    return "ON"
  end
  return "OFF"
end

local function normalizeActionKey(key)
  local value = string.lower(trim(key))
  value = string.gsub(value, "[%s_%-]", "")

  if value == "execute" then
    return "execute"
  end
  if value == "overpower" then
    return "overpower"
  end
  if value == "sunder" or value == "sunderarmor" then
    return "sunder"
  end
  if value == "battleshout" or value == "shout" then
    return "battleShout"
  end
  if value == "mortalstrike" or value == "ms" then
    return "mortalStrike"
  end
  if value == "slam" then
    return "slam"
  end

  return nil
end


local function extractSelfSpell(message)
  message = tostring(message or "")
  local _, _, spell = string.find(message, "Your (.+) hits")
  if not spell then
    _, _, spell = string.find(message, "Your (.+) crits")
  end
  if not spell then
    _, _, spell = string.find(message, "Your (.+) is")
  end
  if not spell then
    _, _, spell = string.find(message, "Your (.+) misses")
  end
  return spell
end

local function isOnNextSwingWarriorSpell(spell)
  return spell == "Heroic Strike" or spell == "Cleave"
end

local function setBindingName(name, value)
  if setglobal then
    setglobal(name, value)
  elseif _G then
    _G[name] = value
  end
end

BINDING_HEADER_OCTOTWEAKS_WARRIORASSIST = "OctoTweaks Warrior Assist"
BINDING_NAME_OCTOTWEAKS_WARRIORASSIST_ACT = "Smart combat action"

setBindingName("BINDING_HEADER_OCTOTWEAKS_WARRIORASSIST", "OctoTweaks Warrior Assist")
setBindingName("BINDING_NAME_OCTOTWEAKS_WARRIORASSIST_ACT", "Smart combat action")

function module:EnsureData()
  OT:EnsureSavedVariables()

  if not OctoTweaksDB.warriorAssist then
    OctoTweaksDB.warriorAssist = {}
  end

  local db = OctoTweaksDB.warriorAssist

  if db.reserveRage == nil then
    db.reserveRage = DEFAULT_RESERVE_RAGE
  end
  if db.msOverflowRage == nil then
    db.msOverflowRage = DEFAULT_MS_OVERFLOW_RAGE
  end
  if db.requireSafeSlam == nil then
    db.requireSafeSlam = true
  end

  local schemaVersion = tonumber(db.schemaVersion) or 1
  if schemaVersion < 2 then
    local legacyCast = tonumber(db.slamCastTime)
    if legacyCast and legacyCast ~= LEGACY_DEFAULT_SLAM_CAST_TIME then
      db.slamCastOverride = legacyCast
    end
    db.slamCastTime = nil
  end
  if schemaVersion < 3 then
    db.slamLateTolerance = DEFAULT_SLAM_LATE_TOLERANCE
    schemaVersion = 3
  end
  db.schemaVersion = schemaVersion
  if db.slamSafetyMargin == nil then
    db.slamSafetyMargin = DEFAULT_SLAM_SAFETY_MARGIN
  end
  if db.slamLateTolerance == nil then
    db.slamLateTolerance = DEFAULT_SLAM_LATE_TOLERANCE
  end
  if db.debug == nil then
    db.debug = false
  end
  if not db.actions then
    db.actions = {}
  end
  if not db.costOverrides then
    db.costOverrides = {}
  end

  local i
  for i = 1, table.getn(ACTION_ORDER) do
    local key = ACTION_ORDER[i]
    if db.actions[key] == nil then
      db.actions[key] = ACTIONS[key].defaultEnabled
    end
  end

  return db
end

function module:IsActionEnabled(key)
  local db = self:EnsureData()
  return db.actions[key] and true or false
end

function module:Debug(message)
  local db = self:EnsureData()
  if db.debug then
    OT:Print("Warrior Assist: " .. tostring(message))
  end
end

function module:SetDecision(action, detail)
  self.lastDecision = action or "WAIT"
  self.lastDecisionDetail = detail or ""
  if self:EnsureData().debug then
    local message = self.lastDecision
    if self.lastDecisionDetail ~= "" then
      message = message .. " - " .. self.lastDecisionDetail
    end
    self:Debug(message)
  end
end

function module:GetRage()
  if UnitPower then
    return tonumber(UnitPower("player", RAGE_POWER_TYPE)) or 0
  end
  if UnitMana then
    return tonumber(UnitMana("player")) or 0
  end
  return 0
end

function module:GetSpellPowerCost(entry, key)
  local db = self:EnsureData()
  local override = tonumber(db.costOverrides[key])
  if override then
    return override, "override"
  end

  if entry and entry.spellId and C_Spell and C_Spell.GetSpellPowerCost then
    local costs = C_Spell.GetSpellPowerCost(entry.spellId)
    if costs and costs[1] and tonumber(costs[1].cost) then
      local cost = tonumber(costs[1].cost)
      local rawPowerType = costs[1].type
      local powerType = tonumber(rawPowerType)
      local powerName = string.upper(tostring(rawPowerType or ""))
      if powerType == RAGE_POWER_TYPE or powerName == "RAGE" then
        -- The source-audited ClassicAPI path exposes engine-style rage cost
        -- units on the current contract. Normalize them to display rage; this
        -- exact unit behavior remains part of the first runtime calibration.
        cost = cost / 10
      end
      return cost, "ClassicAPI"
    end
  end

  return FALLBACK_COSTS[key] or 0, "fallback"
end

function module:CanSpend(key, rage, preserveReserve)
  local entry = self.actions[key]
  local cost = self:GetSpellPowerCost(entry, key)
  if rage < cost then
    return false, cost
  end

  if preserveReserve then
    local reserve = tonumber(self:EnsureData().reserveRage) or DEFAULT_RESERVE_RAGE
    if (rage - cost) < reserve then
      return false, cost
    end
  end

  return true, cost
end

function module:IsActionReady(key)
  local entry = self.actions[key]
  if not entry or not entry.slot then
    return false, "missing action slot"
  end

  if HasAction and not HasAction(entry.slot) then
    return false, "slot empty"
  end

  if IsUsableAction then
    local usable = IsUsableAction(entry.slot)
    if not usable then
      return false, "not usable"
    end
  end

  if IsActionInRange then
    local inRange = IsActionInRange(entry.slot)
    if inRange == 0 then
      return false, "out of range"
    end
  end

  if GetActionCooldown and GetTime then
    local start, duration, enabled = GetActionCooldown(entry.slot)
    if enabled == 0 then
      return false, "disabled cooldown"
    end
    if start and duration and start > 0 and duration > 0 then
      local remaining = start + duration - GetTime()
      if remaining > READY_EPSILON then
        return false, "cooldown " .. string.format("%.2f", remaining)
      end
    end
  end

  return true, "ready"
end

function module:HasAuraByName(unit, spellName, filter)
  if not spellName or spellName == "" then
    return false
  end

  if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spellName, filter)
    if ok and aura then
      return true
    end
  end

  return false
end

function module:HasBattleShout()
  local entry = self.actions.battleShout
  local name = entry and entry.name or ACTIONS.battleShout.name
  return self:HasAuraByName("player", name, "HELPFUL")
end

function module:TargetHasOwnSunder()
  local entry = self.actions.sunder
  local name = entry and entry.name or ACTIONS.sunder.name

  if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", name, "HARMFUL|PLAYER")
    if ok and aura then
      return true
    end

    -- Some ClassicAPI versions may accept HARMFUL but not combine PLAYER in
    -- the filter parser. Falling back to any visible Sunder is preferable to
    -- repeatedly spending rage when the target is already sundered.
    ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", name, "HARMFUL")
    if ok and aura then
      return true
    end
  end

  return false
end

function module:GetSlamCastTime()
  local db = self:EnsureData()
  local override = tonumber(db.slamCastOverride)
  if override and override >= 0 then
    return override, "override"
  end

  if CleveRoids and CleveRoids.GetSpellCastTime then
    local ok, value = pcall(CleveRoids.GetSpellCastTime, ACTIONS.slam.name)
    value = tonumber(value)
    if ok and value and value > 0 and value <= 10 then
      return value, "SuperCleveRoidMacros tooltip"
    end
  end

  local entry = self.actions.slam
  if entry and entry.spellId and C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, entry.spellId)
    if ok and type(info) == "table" then
      local castTime = tonumber(info.castTime)
      if castTime and castTime > 0 then
        if castTime > 10 then
          castTime = castTime / 1000
        end
        if castTime > 0 and castTime <= 10 then
          return castTime, "ClassicAPI spell info"
        end
      end
    end
  end

  return DEFAULT_SLAM_CAST_TIME_FALLBACK, "fallback"
end

function module:ResetSwingTracker(reason)
  self.swingStart = nil
  self.swingDuration = nil
  self.swingReason = reason
  self.swingMessage = nil
end

function module:StartMainHandSwing(reason, message)
  if not GetTime or not UnitAttackSpeed then
    return false
  end

  local speed = tonumber(UnitAttackSpeed("player"))
  if not speed or speed <= 0 then
    return false
  end

  self.swingStart = GetTime()
  self.swingDuration = speed
  self.swingReason = reason or "self combat message"
  self.swingMessage = tostring(message or "")
  return true
end

function module:HandleSelfMeleeMessage(message)
  local spell = extractSelfSpell(message)
  if spell then
    if isOnNextSwingWarriorSpell(spell) then
      self:StartMainHandSwing(spell, message)
    end
    return
  end

  -- In the 1.12 combat text used by AttackBar, ordinary white main-hand
  -- hits/misses are the SELF_HITS/SELF_MISSES messages that do not start
  -- with a named "Your <spell> ..." payload. With a two-hander or a
  -- one-hand + shield this gives an unambiguous main-hand reset.
  self:StartMainHandSwing("white swing", message)
end

function module:HandleSelfSpellDamage(message)
  local spell = extractSelfSpell(message)
  if spell and isOnNextSwingWarriorSpell(spell) then
    self:StartMainHandSwing(spell, message)
  end
end

function module:GetInternalSwingProgress()
  if not self.swingStart or not self.swingDuration or not GetTime then
    return nil, "internal tracker idle"
  end

  local duration = tonumber(self.swingDuration)
  if not duration or duration <= 0 then
    self:ResetSwingTracker("invalid duration")
    return nil, "internal tracker invalid duration"
  end

  local age = GetTime() - self.swingStart
  if age < 0 then
    self:ResetSwingTracker("negative age")
    return nil, "internal tracker invalid age"
  end

  if age > duration then
    -- Do not invent a new cycle when the expected white swing has not yet
    -- produced its combat message. An expired timer is unsafe for Slam and
    -- the next real hit/miss will start the next cycle.
    return nil, "internal tracker expired"
  end

  local progress = age / duration
  if progress < 0 then
    progress = 0
  elseif progress > 1 then
    progress = 1
  end

  return progress, "internal combat-log tracker"
end

function module:GetSwingProgress()
  local internalProgress, internalSource = self:GetInternalSwingProgress()
  if internalProgress ~= nil then
    return internalProgress, internalSource
  end

  if CleveRoids and CleveRoids.GetSwingPercentElapsed then
    local ok, percent = pcall(CleveRoids.GetSwingPercentElapsed)
    percent = tonumber(percent)
    if ok and percent and percent >= 0 and percent <= 100 then
      return percent / 100, "SuperCleveRoidMacros timer"
    end
  end

  if tonumber(st_timer) and tonumber(st_timerMax) and tonumber(st_timerMax) > 0 then
    local remaining = tonumber(st_timer)
    local maximum = tonumber(st_timerMax)
    local progress = (maximum - remaining) / maximum
    if progress < 0 then
      progress = 0
    elseif progress > 1 then
      progress = 1
    end
    return progress, "SP_SwingTimer"
  end

  if pfUI and pfUI.swingtimer and pfUI.swingtimer.mainhand and pfUI.swingtimer.mainhand.GetValue then
    local bar = pfUI.swingtimer.mainhand
    local shown = true
    if bar.IsShown then
      shown = bar:IsShown() and true or false
    end
    if shown then
      local value = tonumber(bar:GetValue())
      if value and value >= 0 and value <= 1 then
        return value, "pfUI"
      end
    end
  end

  return nil, "no active swing timer"
end

function module:IsSafeSlamWindow()
  local db = self:EnsureData()
  if not db.requireSafeSlam then
    return true, "safe-slam check disabled"
  end

  local elapsed, source = self:GetSwingProgress()
  if elapsed == nil then
    return false, source
  end

  if not UnitAttackSpeed then
    return false, "UnitAttackSpeed unavailable"
  end

  local mainSpeed = tonumber(UnitAttackSpeed("player"))
  if not mainSpeed or mainSpeed <= 0 then
    return false, "invalid main-hand speed"
  end

  local castTime, castSource = self:GetSlamCastTime()
  local margin = tonumber(db.slamSafetyMargin) or DEFAULT_SLAM_SAFETY_MARGIN
  local lateTolerance = tonumber(db.slamLateTolerance) or DEFAULT_SLAM_LATE_TOLERANCE
  local safeUntil = (mainSpeed - castTime - margin + lateTolerance) / mainSpeed
  if safeUntil < 0 then
    return false, "Slam cast longer than swing window"
  end
  if safeUntil > 1 then
    safeUntil = 1
  end

  if elapsed <= safeUntil then
    return true, source .. " progress=" .. string.format("%.2f", elapsed) .. " safe<=" .. string.format("%.2f", safeUntil) .. "; cast=" .. string.format("%.2f", castTime) .. "s (" .. tostring(castSource) .. "), late tolerance=" .. string.format("%.2f", lateTolerance) .. "s"
  end

  return false, source .. " progress=" .. string.format("%.2f", elapsed) .. " safe<=" .. string.format("%.2f", safeUntil) .. "; cast=" .. string.format("%.2f", castTime) .. "s (" .. tostring(castSource) .. "), late tolerance=" .. string.format("%.2f", lateTolerance) .. "s"
end

function module:TargetIsValidCombatTarget()
  if not UnitExists or not UnitExists("target") then
    return false, "no target"
  end

  if UnitIsDead and UnitIsDead("target") then
    return false, "target dead"
  end

  if UnitCanAttack and not UnitCanAttack("player", "target") then
    return false, "target not hostile"
  end

  if UnitAffectingCombat and not UnitAffectingCombat("player") then
    return false, "player not in combat"
  end

  return true, "combat target"
end

function module:ChooseAction()
  local valid, reason = self:TargetIsValidCombatTarget()
  if not valid then
    return nil, reason
  end

  local db = self:EnsureData()
  local rage = self:GetRage()
  local ready
  local canSpend
  local cost
  local detail
  local slamBlockedDetail

  if db.actions.execute then
    ready = self:IsActionReady("execute")
    if ready then
      return "execute", "execute usable; rage=" .. tostring(rage)
    end
  end

  if db.actions.overpower then
    ready = self:IsActionReady("overpower")
    if ready then
      canSpend, cost = self:CanSpend("overpower", rage, true)
      if canSpend then
        return "overpower", "reactive proc; rage=" .. tostring(rage) .. " cost=" .. tostring(cost)
      end
    end
  end

  if db.actions.sunder and not self:TargetHasOwnSunder() then
    ready = self:IsActionReady("sunder")
    if ready then
      canSpend, cost = self:CanSpend("sunder", rage, false)
      if canSpend then
        return "sunder", "initial Sunder; rage=" .. tostring(rage) .. " cost=" .. tostring(cost)
      end
    end
  end

  if db.actions.battleShout and not self:HasBattleShout() then
    ready = self:IsActionReady("battleShout")
    if ready then
      canSpend, cost = self:CanSpend("battleShout", rage, true)
      if canSpend then
        return "battleShout", "Battle Shout missing; rage=" .. tostring(rage) .. " cost=" .. tostring(cost)
      end
    end
  end

  if db.actions.mortalStrike and rage >= (tonumber(db.msOverflowRage) or DEFAULT_MS_OVERFLOW_RAGE) then
    ready = self:IsActionReady("mortalStrike")
    if ready then
      canSpend, cost = self:CanSpend("mortalStrike", rage, true)
      if canSpend then
        return "mortalStrike", "overflow rage=" .. tostring(rage) .. " threshold=" .. tostring(db.msOverflowRage)
      end
    end
  end

  if db.actions.slam then
    ready = self:IsActionReady("slam")
    if ready then
      canSpend, cost = self:CanSpend("slam", rage, true)
      if canSpend then
        local safe
        safe, detail = self:IsSafeSlamWindow()
        if safe then
          return "slam", "rage=" .. tostring(rage) .. " cost=" .. tostring(cost) .. "; " .. tostring(detail)
        end
        slamBlockedDetail = tostring(detail)
      end
    end
  end

  if slamBlockedDetail then
    return nil, "Slam blocked: " .. slamBlockedDetail .. "; rage=" .. tostring(rage)
  end
  return nil, "no eligible action; rage=" .. tostring(rage)
end

function module:UseManagedAction(key)
  local entry = self.actions[key]
  if not entry or not entry.slot then
    return false, "missing action slot for " .. tostring(key)
  end

  if not UseAction then
    return false, "UseAction unavailable"
  end

  UseAction(entry.slot)
  return true, "slot " .. tostring(entry.slot)
end

function module:Act()
  if not self.enabled then
    return false, "module not enabled"
  end

  local key, detail = self:ChooseAction()
  if not key then
    self:SetDecision("WAIT", detail)
    return false, detail
  end

  local ok, result = self:UseManagedAction(key)
  if ok then
    self:SetDecision(string.upper(key), detail)
    return true, key
  end

  self:SetDecision("WAIT", result)
  return false, result
end

local function rankNumber(rank)
  if not rank then
    return 0
  end
  local _, _, value = string.find(tostring(rank), "(%d+)")
  return tonumber(value) or 0
end

function module:RebuildActionMap()
  local discovered = {}
  local slot

  for slot = 1, MAX_ACTION_SLOTS do
    local actionType, spellId = GetActionInfo(slot)
    if actionType == "spell" and spellId then
      local name, rank = GetSpellInfo(spellId)
      if name then
        local i
        for i = 1, table.getn(ACTION_ORDER) do
          local key = ACTION_ORDER[i]
          local wanted = ACTIONS[key]
          if name == wanted.name then
            local candidateRank = rankNumber(rank)
            local current = discovered[key]
            if not current or candidateRank > current.rankNumber then
              discovered[key] = {
                key = key,
                name = name,
                rank = rank or "",
                rankNumber = candidateRank,
                spellId = spellId,
                slot = slot,
              }
            end
          end
        end
      end
    end
  end

  self.actions = discovered

  if self:EnsureData().debug then
    self:Debug("action slots rebuilt")
  end
end

function module:PrintSlamProbe()
  local entry = self.actions.slam
  local rage = self:GetRage()
  local ready, readyReason = self:IsActionReady("slam")
  local canSpend, cost = self:CanSpend("slam", rage, true)
  local castTime, castSource = self:GetSlamCastTime()
  local progress, swingSource = self:GetSwingProgress()
  local speed = UnitAttackSpeed and tonumber(UnitAttackSpeed("player")) or nil
  local safe, safeDetail = self:IsSafeSlamWindow()

  OT:Print("Slam probe: slot=" .. tostring(entry and entry.slot or "MISSING") .. ", ready=" .. tostring(ready) .. " (" .. tostring(readyReason) .. ")")
  OT:Print("Slam probe: rage=" .. tostring(rage) .. ", cost=" .. tostring(cost) .. ", reserveOK=" .. tostring(canSpend))
  OT:Print("Slam probe: cast=" .. string.format("%.2f", castTime) .. "s (" .. tostring(castSource) .. "), speed=" .. tostring(speed or "unknown"))
  OT:Print("Slam probe: swing=" .. tostring(progress and string.format("%.2f", progress) or "unknown") .. " (" .. tostring(swingSource) .. "), safe=" .. tostring(safe))
  if self.swingStart and GetTime then
    OT:Print("Slam probe tracker: age=" .. string.format("%.2f", GetTime() - self.swingStart) .. "s / " .. tostring(self.swingDuration or "?") .. "s, reset=" .. tostring(self.swingReason or "?"))
  else
    OT:Print("Slam probe tracker: idle; last=" .. tostring(self.swingReason or "none"))
  end
  OT:Print("Slam probe detail: " .. tostring(safeDetail))
end

function module:PrintStatus()
  local db = self:EnsureData()
  local key1, key2
  if GetBindingKey then
    key1, key2 = GetBindingKey("OCTOTWEAKS_WARRIORASSIST_ACT")
  end

  local slamCast, slamCastSource = self:GetSlamCastTime()
  OT:Print("Warrior Assist: reserve=" .. tostring(db.reserveRage) .. ", MS overflow=" .. tostring(db.msOverflowRage) .. ", safe Slam=" .. boolText(db.requireSafeSlam))
  OT:Print("Slam timing: cast=" .. string.format("%.2f", slamCast) .. "s (" .. tostring(slamCastSource) .. "), margin=" .. tostring(db.slamSafetyMargin) .. "s, late tolerance=" .. tostring(db.slamLateTolerance) .. "s")
  OT:Print("Smart Action binding: " .. tostring(key1 or "unbound") .. (key2 and (", " .. tostring(key2)) or ""))
  OT:Print("Last decision: " .. tostring(self.lastDecision) .. (self.lastDecisionDetail ~= "" and (" (" .. self.lastDecisionDetail .. ")") or ""))

  local i
  for i = 1, table.getn(ACTION_ORDER) do
    local key = ACTION_ORDER[i]
    local entry = self.actions[key]
    local enabled = db.actions[key] and "ON" or "OFF"
    if entry then
      local cost, source = self:GetSpellPowerCost(entry, key)
      OT:Print(key .. "=" .. enabled .. " slot=" .. tostring(entry.slot) .. " id=" .. tostring(entry.spellId) .. " " .. tostring(entry.rank) .. " cost=" .. tostring(cost) .. " (" .. source .. ")")
    else
      OT:Print(key .. "=" .. enabled .. " slot=MISSING")
    end
  end
end

function module:PrintHelp()
  OT:Print("Warrior Assist commands:")
  OT:Print("/otwa act | status | scan | slamprobe | debug <on|off>")
  OT:Print("/otwa reserve <rage> | ms <overflow rage>")
  OT:Print("/otwa toggle <execute|overpower|sunder|battleShout|mortalStrike|slam> <on|off>")
  OT:Print("/otwa cost <action> <rage|auto>")
  OT:Print("/otwa slamsafe <on|off> | slamcast <seconds|auto> | slammargin <seconds>")
  OT:Print("/otwa slamtolerance <seconds>  (alias: slamlate; default 0.30)")
  OT:Print("/otwa bind <KEY> | unbind | reset")
end

function module:SetToggle(key, value)
  local normalized = normalizeActionKey(key)
  if not normalized then
    return false, "unknown action " .. tostring(key)
  end
  key = normalized

  value = string.lower(trim(value))
  if value == "on" or value == "1" or value == "true" then
    self:EnsureData().actions[key] = true
    return true, key .. " ON"
  end
  if value == "off" or value == "0" or value == "false" then
    self:EnsureData().actions[key] = false
    return true, key .. " OFF"
  end

  return false, "toggle expects on/off"
end

function module:BindSmartAction(key)
  key = string.upper(trim(key))
  if key == "" then
    return false, "bind expects a key, for example F6 or SHIFT-F"
  end
  if not SetBinding or not SaveBindings or not GetCurrentBindingSet then
    return false, "binding API unavailable"
  end

  SetBinding(key, "OCTOTWEAKS_WARRIORASSIST_ACT")
  SaveBindings(GetCurrentBindingSet())
  return true, "Smart Action bound to " .. key
end

function module:UnbindSmartAction()
  if not GetBindingKey or not SetBinding or not SaveBindings or not GetCurrentBindingSet then
    return false, "binding API unavailable"
  end

  local key1, key2 = GetBindingKey("OCTOTWEAKS_WARRIORASSIST_ACT")
  if key1 then
    SetBinding(key1)
  end
  if key2 then
    SetBinding(key2)
  end
  SaveBindings(GetCurrentBindingSet())
  return true, "Smart Action binding cleared"
end

function module:ResetConfig()
  local db = self:EnsureData()
  db.reserveRage = DEFAULT_RESERVE_RAGE
  db.msOverflowRage = DEFAULT_MS_OVERFLOW_RAGE
  db.requireSafeSlam = true
  db.slamCastOverride = nil
  db.slamCastTime = nil
  db.schemaVersion = 3
  db.slamSafetyMargin = DEFAULT_SLAM_SAFETY_MARGIN
  db.slamLateTolerance = DEFAULT_SLAM_LATE_TOLERANCE
  db.costOverrides = {}

  local i
  for i = 1, table.getn(ACTION_ORDER) do
    local key = ACTION_ORDER[i]
    db.actions[key] = ACTIONS[key].defaultEnabled
  end
end

function module:HandleSlash(msg)
  local command, rest = splitFirst(msg)
  command = string.lower(command or "")

  if command == "" or command == "help" then
    self:PrintHelp()
    return
  end

  if command == "act" then
    self:Act()
    return
  end

  if command == "status" then
    self:PrintStatus()
    return
  end

  if command == "scan" then
    self:RebuildActionMap()
    self:PrintStatus()
    return
  end

  if command == "slamprobe" then
    self:PrintSlamProbe()
    return
  end

  if command == "debug" then
    local value = string.lower(trim(rest))
    if value == "on" then
      self:EnsureData().debug = true
      OT:Print("Warrior Assist debug ON")
    elseif value == "off" then
      self:EnsureData().debug = false
      OT:Print("Warrior Assist debug OFF")
    else
      OT:Print("debug expects on/off")
    end
    return
  end

  if command == "reserve" then
    local value = tonumber(trim(rest))
    if not value or value < 0 or value > 100 then
      OT:Print("reserve expects rage between 0 and 100")
      return
    end
    self:EnsureData().reserveRage = value
    OT:Print("Warrior Assist reserve rage = " .. tostring(value))
    return
  end

  if command == "ms" or command == "msoverflow" then
    local value = tonumber(trim(rest))
    if not value or value < 0 or value > 100 then
      OT:Print("ms expects rage threshold between 0 and 100")
      return
    end
    self:EnsureData().msOverflowRage = value
    OT:Print("Warrior Assist MS overflow threshold = " .. tostring(value))
    return
  end

  if command == "toggle" then
    local key, value = parseTwo(rest)
    local ok, result = self:SetToggle(key, value or "")
    OT:Print(result)
    return
  end

  if command == "cost" then
    local key, value = parseTwo(rest)
    local normalized = normalizeActionKey(key)
    value = string.lower(trim(value))
    if not normalized then
      OT:Print("unknown action " .. tostring(key))
      return
    end
    key = normalized
    if value == "auto" or value == "" then
      self:EnsureData().costOverrides[key] = nil
      OT:Print(key .. " rage cost = auto")
      return
    end
    local number = tonumber(value)
    if not number or number < 0 or number > 100 then
      OT:Print("cost expects 0..100 or auto")
      return
    end
    self:EnsureData().costOverrides[key] = number
    OT:Print(key .. " rage cost override = " .. tostring(number))
    return
  end

  if command == "slamsafe" then
    local value = string.lower(trim(rest))
    if value == "on" then
      self:EnsureData().requireSafeSlam = true
      OT:Print("Warrior Assist safe Slam check ON")
    elseif value == "off" then
      self:EnsureData().requireSafeSlam = false
      OT:Print("Warrior Assist safe Slam check OFF")
    else
      OT:Print("slamsafe expects on/off")
    end
    return
  end

  if command == "slamcast" then
    local text = string.lower(trim(rest))
    if text == "auto" or text == "" then
      self:EnsureData().slamCastOverride = nil
      OT:Print("Warrior Assist Slam cast time = auto")
      return
    end
    local value = tonumber(text)
    if not value or value < 0 or value > 3 then
      OT:Print("slamcast expects seconds between 0 and 3, or auto")
      return
    end
    self:EnsureData().slamCastOverride = value
    OT:Print("Warrior Assist Slam cast time override = " .. tostring(value) .. "s")
    return
  end

  if command == "slammargin" then
    local value = tonumber(trim(rest))
    if not value or value < 0 or value > 1 then
      OT:Print("slammargin expects seconds between 0 and 1")
      return
    end
    self:EnsureData().slamSafetyMargin = value
    OT:Print("Warrior Assist Slam safety margin = " .. tostring(value) .. "s")
    return
  end

  if command == "slamtolerance" or command == "slamlate" then
    local value = tonumber(trim(rest))
    if not value or value < 0 or value > 2 then
      OT:Print("slamtolerance expects seconds between 0 and 2")
      return
    end
    self:EnsureData().slamLateTolerance = value
    OT:Print("Warrior Assist Slam late-window tolerance = " .. tostring(value) .. "s")
    return
  end

  if command == "bind" then
    local ok, result = self:BindSmartAction(rest)
    OT:Print(result)
    return
  end

  if command == "unbind" then
    local ok, result = self:UnbindSmartAction()
    OT:Print(result)
    return
  end

  if command == "reset" then
    self:ResetConfig()
    OT:Print("Warrior Assist configuration reset; key binding preserved")
    return
  end

  self:PrintHelp()
end

function module:RegisterSlashCommand()
  SLASH_OCTOTWEAKSWARRIORASSIST1 = "/otwa"
  SlashCmdList["OCTOTWEAKSWARRIORASSIST"] = function(msg)
    module:HandleSlash(msg or "")
  end
end

function module:CreateEventFrame()
  local frame = CreateFrame("Frame", "OctoTweaksWarriorAssistEvents")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
  frame:RegisterEvent("SPELLS_CHANGED")
  frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
  frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
  frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
  frame:RegisterEvent("PLAYER_LEAVE_COMBAT")
  frame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
      module:HandleSelfMeleeMessage(arg1)
      return
    end

    if event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
      module:HandleSelfSpellDamage(arg1)
      return
    end

    if event == "PLAYER_LEAVE_COMBAT" then
      module:ResetSwingTracker("left combat")
      return
    end

    if event == "PLAYER_ENTERING_WORLD" then
      module:ResetSwingTracker("entering world")
    end

    module:RebuildActionMap()
  end)
  self.eventFrame = frame
end

function module:probe()
  if not UnitClass then
    return false, "UnitClass unavailable"
  end

  local localizedClass, classToken = UnitClass("player")
  local normalizedClass = string.upper(tostring(classToken or localizedClass or ""))
  if normalizedClass ~= "WARRIOR" then
    return false, "player is not a Warrior"
  end

  if not GetActionInfo or not GetSpellInfo then
    return false, "ClassicAPI GetActionInfo/GetSpellInfo unavailable"
  end
  if not C_UnitAuras or not C_UnitAuras.GetAuraDataBySpellName then
    return false, "ClassicAPI C_UnitAuras.GetAuraDataBySpellName unavailable"
  end
  if not IsUsableAction or not GetActionCooldown or not UseAction then
    return false, "native action APIs unavailable"
  end
  if not UnitAffectingCombat or not UnitExists or not UnitCanAttack then
    return false, "combat unit APIs unavailable"
  end

  return true, "Warrior + ClassicAPI smart-action prerequisites detected"
end

function module:enable()
  if self.enabled then
    return true, "already installed"
  end

  self:EnsureData()
  self:RebuildActionMap()
  self:RegisterSlashCommand()
  self:CreateEventFrame()
  self.enabled = true

  return true, "manual Smart Action available; /otwa status for slot/cost diagnostics"
end

function OctoTweaks_WarriorAssist_Act()
  return module:Act()
end

OT.WarriorAssist = module
OT:RegisterModule(module)
