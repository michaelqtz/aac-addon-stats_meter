-- Recording and aggregating combat stats from COMBAT_MSG. Everything is keyed by unit name,
-- because the addon API can't resolve the unit ids of most units.
local stats = {}

-- Every stat the meter can show. `values` is where its numbers come from, `details` is the
-- per-skill breakdown shown when a row is clicked.
stats.PAGES = {
  { label = "Total Damage", values = "total_dmg", details = "total_dmg" },
  { label = "Damage Per Second", values = "dps", details = "total_dmg" },
  { label = "Total Healing", values = "total_healing", details = "total_healing" },
  { label = "Healing Per Second", values = "hps", details = "total_healing" },
  { label = "Damage Taken", values = "dmg_taken", details = "dmg_taken" },
  { label = "Damage Absorbed", values = "dmg_absorbed", details = "dmg_taken" },
}

local TOTALS = { "total_dmg", "total_healing", "dmg_taken", "dmg_absorbed" }
local DETAILS = { "total_dmg", "total_healing", "dmg_taken" }
-- Per-second stats and the totals they're calculated from
local RATES = { dps = "total_dmg", hps = "total_healing" }

local DAMAGE_EVENTS = { SPELL_DAMAGE = true, SPELL_DOT_DAMAGE = true, MELEE_DAMAGE = true }
-- Melee hits have no spell name, so they're listed under this in the breakdown
local MELEE_NAME = "Melee Attack"

-- Spells that shouldn't count towards any stat
local IGNORED_SPELL_NAMES = {
  ["Reset After Duel"] = true --> full heal when a duel ends
}

-- Whether a COMBAT_MSG type contributes to any stat (cheap check before parsing it)
function stats.isTrackedEvent(combatEvent)
  return DAMAGE_EVENTS[combatEvent] == true or combatEvent == "SPELL_HEALED"
end

-- 1234 -> "1234", 12345 -> "12.3k", 1234567 -> "1.2m"
function stats.formatAmount(number)
  if number > 1000000 then
    return tostring(math.floor(number / 1000000 * 10) / 10) .. "m"
  elseif number > 1000 then
    return tostring(math.floor(number / 1000 * 10) / 10) .. "k"
  end
  return tostring(math.floor(number))
end

-- Percentage of part in whole with one decimal, 0 when whole is 0
function stats.percent(part, whole)
  if whole == nil or whole == 0 then return 0 end
  return math.floor(part / whole * 1000) / 10
end

local Tracker = {}

function stats.newTracker()
  -- setmetatable isn't available to addons, so copy the methods onto the instance
  local self = {}
  for name, method in pairs(Tracker) do self[name] = method end
  self:reset()
  return self
end

function Tracker:reset()
  self.totals = {}
  for _, name in ipairs(TOTALS) do self.totals[name] = {} end
  self.details = {}
  for _, name in ipairs(DETAILS) do self.details[name] = {} end
  -- Set by the first recorded event, so idle time before a fight doesn't count
  self.startTime = nil
end

function Tracker:isEmpty()
  return self.startTime == nil
end

-- Milliseconds since the first recorded event (0 while empty)
function Tracker:elapsed(now)
  if self.startTime == nil then return 0 end
  return now - self.startTime
end

function Tracker:add(totalName, unitName, amount)
  local total = self.totals[totalName]
  total[unitName] = (total[unitName] or 0) + amount
end

function Tracker:addDetail(detailName, unitName, spellName, amount)
  local unitDetails = self.details[detailName][unitName]
  if unitDetails == nil then
    unitDetails = {}
    self.details[detailName][unitName] = unitDetails
  end
  unitDetails[spellName] = (unitDetails[spellName] or 0) + amount
end

-- Record one COMBAT_MSG. `result` is the table returned by ParseCombatMessage.
function Tracker:recordCombatMessage(combatEvent, source, target, result, now)
  if result == nil then return end
  if result.spellName ~= nil and IGNORED_SPELL_NAMES[result.spellName] then return end
  local hasSource = source ~= nil and source ~= ""
  local hasTarget = target ~= nil and target ~= ""
  local spellName = result.spellName
  if spellName == nil or spellName == "" then spellName = MELEE_NAME end

  if DAMAGE_EVENTS[combatEvent] then
    local damage = tonumber(result.damage)
    local reduced = tonumber(result.reduced)
    if damage == nil or reduced == nil then return end
    damage = -damage --> damage arrives as a negative number
    if hasSource then
      self:add("total_dmg", source, damage)
      self:addDetail("total_dmg", source, spellName, damage)
    end
    if hasTarget then
      self:add("dmg_taken", target, damage)
      self:add("dmg_absorbed", target, reduced)
      self:addDetail("dmg_taken", target, spellName, damage)
    end
  elseif combatEvent == "SPELL_HEALED" then
    local heal = tonumber(result.heal)
    if heal == nil or not hasSource then return end
    self:add("total_healing", source, heal)
    self:addDetail("total_healing", source, spellName, heal)
  else
    return
  end

  if self.startTime == nil then self.startTime = now end
end

-- Amount per second for a total
function Tracker:perSecond(totalName, unitName, now)
  -- At least 1 second, so the first hits don't show absurd rates
  local seconds = math.max(self:elapsed(now), 1000) / 1000
  return math.floor((self.totals[totalName][unitName] or 0) / seconds)
end

-- unitName -> amount for a page's stat
function Tracker:getValues(page, now)
  local rateOf = RATES[page.values]
  if rateOf == nil then
    return self.totals[page.values]
  end
  local values = {}
  for unitName in pairs(self.totals[rateOf]) do
    values[unitName] = self:perSecond(rateOf, unitName, now)
  end
  return values
end

-- Text for the details window when a unit's row is clicked
function Tracker:getDetailsText(page, unitName, now)
  local totals = self.totals
  local summary
  if page.details == "total_dmg" then
    summary = "Total Damage: " .. stats.formatAmount(totals.total_dmg[unitName] or 0)
      .. " | DPS: " .. stats.formatAmount(self:perSecond("total_dmg", unitName, now))
  elseif page.details == "total_healing" then
    summary = "Total Healing: " .. stats.formatAmount(totals.total_healing[unitName] or 0)
      .. " | HPS: " .. stats.formatAmount(self:perSecond("total_healing", unitName, now))
  else
    local taken = totals.dmg_taken[unitName] or 0
    local absorbed = totals.dmg_absorbed[unitName] or 0
    summary = "Total Damage Taken: " .. stats.formatAmount(taken)
      .. " | Damage Absorbed: " .. stats.formatAmount(absorbed)
      .. " (" .. tostring(stats.percent(absorbed, taken + absorbed)) .. "%)"
  end

  local lines = { summary }
  local unitDetails = self.details[page.details][unitName] or {}
  local unitTotal = totals[page.details][unitName] or 0
  local spellNames = {}
  for spellName in pairs(unitDetails) do table.insert(spellNames, spellName) end
  table.sort(spellNames, function(a, b) return unitDetails[a] > unitDetails[b] end)
  for i, spellName in ipairs(spellNames) do
    local amount = unitDetails[spellName]
    table.insert(lines, i .. ". " .. spellName .. ": " .. stats.formatAmount(amount)
      .. " (" .. tostring(stats.percent(amount, unitTotal)) .. "%)")
  end
  return table.concat(lines, "\n")
end

-- Data written to the log file when the meter is reset
function Tracker:snapshot(now)
  return {
    startTime = self.startTime,
    endTime = now,
    totals = self.totals,
    details = self.details
  }
end

return stats
