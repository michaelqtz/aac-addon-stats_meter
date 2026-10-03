-- Stats Meter: wires combat events, settings and the meter window together.
--   stats.lua  recording and totals
--   units.lua  identifying units, filters and colour categories
--   ui.lua     the windows
local api = require("api")
local stats = require("stats_meter/stats")
local units = require("stats_meter/units")
local ui = require("stats_meter/ui")

local stats_meter_addon = {
  name = "Stats Meter",
  author = "Michaelqt",
  version = "2.2.0",
  desc = "A stats meter covering damage, heals and more!"
}

local SETTINGS_ID = "stats_meter"
local DEFAULT_SETTINGS = {
  posX = 0,
  posY = 0,
  playerFilter = 1,
  hostileFilter = 1,
  npcFilter = 0,
  mainFilter = 1,
  isMinimized = 0
}
local REFRESH_INTERVAL_MS = 1000
local LOG_PATH = "stats_meter/logs/stats_meter_log_%.0f-%.0f.txt"

-- Joining one of these shout channels means we've entered a dungeon, so offer a reset
local SHOUT_CHANNEL_ID = 1
local DUNGEON_CHANNEL_NAMES = {
  -- Basic/Greater Dungeons
  ["Burnt Castle Armory"] = true, ["Greater Burnt Castle Armory"] = true,
  ["Hadir Farm"] = true, ["Greater Hadir Farm"] = true,
  ["Palace Cellar"] = true, ["Greater Palace Cellar"] = true,
  ["Sharpwind Mines"] = true, ["Greater Sharpwind Mines"] = true,
  ["Howling Abyss"] = true, ["Greater Howling Abyss"] = true,
  ["Kroloal Cradle"] = true, ["Greater Kroloal Cradle"] = true,
  -- "Hard" dungeons
  ["Mistsong Summit"] = true,
  ["Serpentis"] = true,
  -- Library Floors
  ["Encyclopedia Room"] = true, --> Floor 1
  ["Libris Garden"] = true, --> Floor 2
  ["Screaming Archives"] = true, --> Floor 3
  -- Library Dungeons
  ["Corner Reading Room"] = true, --> CRR, every floor
  ["Screening Hall"] = true, --> Floor 1, Wynn
  ["Frozen Study"] = true, --> Floor 2, Halnaak
  ["Deranged Bookroom"] = true, --> Floor 3, Alexander
  ["Heart of Ayanad"] = true --> Ayanad Scroll Distribution Center
}

-- Set to true to print handler errors to chat (each distinct error once) when debugging
local DEBUG = false

local meter = nil
local tracker = nil
local resolver = nil
local settings = nil
local filters = { Players = 1, Hostiles = 1, NPCs = 0 }
local selectedPage = 1
-- How many rows the meter is scrolled down, and the furthest it can scroll
local scrollOffset = 0
local maxScrollOffset = 0
local currentChannel = nil
local timeSinceRefresh = 0
-- Saved position etc. are applied on the first frame; nothing is saved before that
local settingsApplied = false

local reportedErrors = {}
local function reportError(where, err, ...)
  if not DEBUG then return end
  local msg = "[Stats Meter] Error in " .. where .. ": " .. tostring(err)
  if reportedErrors[msg] then return end
  reportedErrors[msg] = true
  -- select isn't available to addons; event args are rarely nil, so this is close enough
  local args = {}
  for _, value in ipairs({ ... }) do
    args[#args + 1] = tostring(value)
  end
  if #args > 0 then
    msg = msg .. " | args: " .. table.concat(args, ", ")
  end
  api.Log:Err(msg)
end

local function formatTime(ms)
  local seconds = math.floor(ms / 1000) % 60
  local minutes = math.floor(ms / 60000) % 60
  return string.format("%02d:%02d", minutes, seconds)
end

local function saveSettings()
  if not settingsApplied then return end
  local x, y = meter:getPosition()
  settings.posX = x
  settings.posY = y
  settings.mainFilter = selectedPage
  settings.playerFilter = filters.Players
  settings.hostileFilter = filters.Hostiles
  settings.npcFilter = filters.NPCs
  settings.isMinimized = meter:isMinimized() and 1 or 0
  api.SaveSettings()
end

-- Redraw the rows for the selected stat
local function refreshMeter()
  local now = api.Time:GetUiMsec()
  resolver:refresh()
  local page = stats.PAGES[selectedPage]

  -- Units that can be identified and pass the filters, highest first
  local visible = {}
  local visibleTotal = 0
  for unitName, amount in pairs(tracker:getValues(page, now)) do
    local unit = resolver:get(unitName)
    if unit ~= nil and units.passesFilters(unit, filters) then
      table.insert(visible, { unit = unit, amount = amount })
      visibleTotal = visibleTotal + amount
    end
  end
  table.sort(visible, function(a, b)
    if a.amount ~= b.amount then return a.amount > b.amount end
    return a.unit.name < b.unit.name
  end)

  local rowCount = meter:rowCount()
  maxScrollOffset = math.max(0, #visible - rowCount)
  scrollOffset = math.max(0, math.min(scrollOffset, maxScrollOffset))

  local playerRank = nil
  for rank, entry in ipairs(visible) do
    if entry.unit.isSelf then
      playerRank = rank
      break
    end
  end

  local highestAmount = visible[1] and visible[1].amount or 0
  local rows = {}
  for i = 1, rowCount do
    local rank = scrollOffset + i
    -- Pin yourself to the last row whenever you'd otherwise be scrolled out of view
    if i == rowCount and playerRank ~= nil and (playerRank <= scrollOffset or playerRank > scrollOffset + rowCount) then
      rank = playerRank
    end
    local entry = visible[rank]
    if entry ~= nil then
      local barPercent = 0
      if highestAmount > 0 then
        barPercent = math.floor(math.max(0, math.min(100, entry.amount / highestAmount * 100)))
      end
      rows[i] = {
        rank = rank,
        name = entry.unit.name,
        amountText = stats.formatAmount(entry.amount) .. " (" .. tostring(stats.percent(entry.amount, visibleTotal)) .. "%)",
        barPercent = barPercent,
        category = units.category(entry.unit),
        skillset = units.iconSkillset(entry.unit)
      }
    end
  end
  meter:drawRows(rows, scrollOffset + 1)
end

-- Save the current fight to a log file (if anything was recorded) and start over
local function resetMeter()
  local now = api.Time:GetUiMsec()
  if not tracker:isEmpty() then
    api.File:Write(string.format(LOG_PATH, tracker.startTime, now), tracker:snapshot(now))
  end
  tracker:reset()
  scrollOffset = 0
  refreshMeter()
end

local function onCombatMessage(targetUnitId, combatEvent, source, target, ...)
  if not stats.isTrackedEvent(combatEvent) then return end
  local result = ParseCombatMessage(combatEvent, ...)
  tracker:recordCombatMessage(combatEvent, source, target, result, api.Time:GetUiMsec())
end

local function onJoinedChannel(channelId, channelName)
  if channelId ~= SHOUT_CHANNEL_ID then return end
  local previousChannel = currentChannel
  currentChannel = channelName
  if channelName ~= previousChannel and DUNGEON_CHANNEL_NAMES[channelName] then
    meter:showResetPrompt()
  end
end

local eventHandlers = {
  COMBAT_MSG = onCombatMessage,
  CHAT_JOINED_CHANNEL = onJoinedChannel
}

local function OnUpdate(dt)
  if not settingsApplied then
    meter:applySettings(settings)
    settingsApplied = true
  end
  meter:setTimerText(formatTime(tracker:elapsed(api.Time:GetUiMsec())))
  timeSinceRefresh = timeSinceRefresh + dt
  if timeSinceRefresh >= REFRESH_INTERVAL_MS then
    timeSinceRefresh = 0
    if not meter:isMinimized() then
      refreshMeter()
    end
  end
end

-- Called by ui.lua when the user does something
local uiHandlers = {
  onRowClicked = function(unitName)
    local text = tracker:getDetailsText(stats.PAGES[selectedPage], unitName, api.Time:GetUiMsec())
    meter:showDetails(unitName, text)
  end,
  onScroll = function(rows)
    scrollOffset = math.max(0, math.min(scrollOffset + rows, maxScrollOffset))
    refreshMeter()
  end,
  onReset = function()
    resetMeter()
  end,
  onPageSelected = function(index)
    if stats.PAGES[index] == nil then return end
    selectedPage = index
    scrollOffset = 0 --> start each stat at the top
    if settingsApplied then
      saveSettings()
      refreshMeter()
    end
  end,
  onFilterToggled = function(filterName)
    filters[filterName] = filters[filterName] == 1 and 0 or 1
    meter:setFilterColors(filters)
    scrollOffset = 0 --> the visible list changed, start back at the top
    saveSettings()
    refreshMeter()
  end,
  onMinimizedChanged = function(minimized)
    saveSettings()
    if not minimized then refreshMeter() end
  end,
  onMoved = function()
    saveSettings()
  end
}

local function OnLoad()
  settings = api.GetSettings(SETTINGS_ID)
  for key, value in pairs(DEFAULT_SETTINGS) do
    if settings[key] == nil then settings[key] = value end
  end
  if stats.PAGES[settings.mainFilter] == nil then settings.mainFilter = 1 end
  filters.Players = settings.playerFilter
  filters.Hostiles = settings.hostileFilter
  filters.NPCs = settings.npcFilter
  selectedPage = settings.mainFilter

  tracker = stats.newTracker()
  resolver = units.newResolver()
  scrollOffset = 0
  currentChannel = nil
  timeSinceRefresh = 0
  settingsApplied = false

  meter = ui.create(stats.PAGES, uiHandlers)
  meter:setFilterColors(filters)

  local meterWnd = meter.meterWnd
  meterWnd:SetHandler("OnEvent", function(_, event, ...)
    local handler = eventHandlers[event]
    if handler == nil then return end
    local ok, err = pcall(handler, ...)
    if not ok then reportError(tostring(event), err, ...) end
  end)
  for event in pairs(eventHandlers) do
    meterWnd:RegisterEvent(event)
  end
  meterWnd:SetHandler("OnUpdate", function(_, dt)
    local ok, err = pcall(OnUpdate, dt)
    if not ok then reportError("OnUpdate", err) end
  end)

  api.Log:Info("[Stats Meter] Successfully loaded, Please find settings by pressing ESC and clicking 'Stats Meter' in the Addon Menu.")
end

local function OnUnload()
  if meter == nil then return end
  saveSettings()
  meter:free()
  meter = nil
end

stats_meter_addon.OnLoad = OnLoad
stats_meter_addon.OnUnload = OnUnload

return stats_meter_addon
