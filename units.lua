-- Identifying units by name. The addon API only describes yourself, your party/raid members
-- and your current target, so anyone else is unknown and isn't shown on the meter.
local api = require("api")
local units = {}

local MAX_TEAM_MEMBERS = 50

-- Skillsets whose icon is shown next to a class, in priority order:
-- Archery, Vitalism, Sorcery, Battlerage, Defense
local ICON_SKILLSET_PRIORITY = { 6, 10, 7, 1, 3 }

local Resolver = {}

function units.newResolver()
  -- setmetatable isn't available to addons, so copy the methods onto the instance
  local self = {}
  for name, method in pairs(Resolver) do self[name] = method end
  -- Type/faction of every unit we've identified, kept for the whole session
  self.known = {}
  -- Units visible through a token right now: name -> { info, isSelf, isGroupMember }
  self.live = {}
  self.playerName = nil
  return self
end

function Resolver:addLive(token, isSelf, isGroupMember)
  local unitId = api.Unit:GetUnitId(token)
  if unitId == nil then return end
  local unitName = api.Unit:GetUnitNameById(unitId)
  if unitName == nil or unitName == "" then return end
  local info = api.Unit:GetUnitInfoById(unitId)
  if info == nil then return end

  local live = self.live[unitName]
  if live == nil then
    live = { info = info }
    self.live[unitName] = live
  end
  live.isSelf = live.isSelf or isSelf
  live.isGroupMember = live.isGroupMember or isGroupMember
  if isSelf then self.playerName = unitName end

  -- Only overwrite with non-nil values, so partial info never wipes what we learned
  local known = self.known[unitName] or {}
  if info.type ~= nil then known.type = info.type end
  if info.faction ~= nil then known.faction = info.faction end
  self.known[unitName] = known
end

-- Re-read the tokens. Called once per meter refresh.
function Resolver:refresh()
  self.live = {}
  self:addLive("player", true, false)
  self:addLive("target", false, false)
  for i = 1, MAX_TEAM_MEMBERS do
    self:addLive("team" .. i, false, true)
  end
end

-- Everything we know about a unit, or nil if it has never been identified
function Resolver:get(unitName)
  local known = self.known[unitName]
  if known == nil or known.type == nil then return nil end
  local live = self.live[unitName]
  return {
    name = unitName,
    type = known.type,
    faction = known.faction,
    info = live and live.info,
    isSelf = live ~= nil and live.isSelf == true,
    isGroupMember = live ~= nil and live.isGroupMember == true
  }
end

-- Characters need the Players filter and everything else the NPCs filter.
-- Hostile units additionally need the Hostiles filter.
function units.passesFilters(unit, filters)
  if unit.type == "character" then
    if filters.Players ~= 1 then return false end
  elseif filters.NPCs ~= 1 then
    return false
  end
  if unit.faction == "hostile" and filters.Hostiles ~= 1 then return false end
  return true
end

-- Which colour scheme a unit's row uses (see CATEGORY_STYLES in ui.lua)
function units.category(unit)
  if unit.type == "character" then
    if unit.isSelf then return "self" end
    if unit.faction == "hostile" then return "hostile" end
    if unit.isGroupMember then return "party" end
    return "player"
  end
  if unit.faction == "hostile" then return "hostileNpc" end
  return "npc"
end

-- Skillset id whose icon represents the unit's class, or nil. Only yourself and group
-- members get detailed info (including class) from the addon API.
function units.iconSkillset(unit)
  if not (unit.isSelf or unit.isGroupMember) then return nil end
  local class = unit.info and unit.info.class
  if type(class) ~= "table" then return nil end
  for _, skillset in ipairs(ICON_SKILLSET_PRIORITY) do
    for _, classSkillset in pairs(class) do
      if classSkillset == skillset then return skillset end
    end
  end
  return nil
end

return units
