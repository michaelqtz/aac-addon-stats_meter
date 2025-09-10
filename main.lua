-- Addon API and settings
local api = require("api")
local michaelClientLib = require("stats_meter/michael_client")

local stats_meter_addon = {
	name = "Stats Meter",
	author = "Michaelqt",
	version = "2.0.5",
	desc = "A stats meter covering damage, heals and more!"
}
local statsMeterWnd = nil
local minimizedWnd = nil
local resetPromptWnd = nil
local settingsWindow = nil
local detailsWindow = nil

local oldSettings = nil

local stats = nil
local statsDetails = nil

local lastUpdate = 0
local lastMeterUpdate = 0
local lastPauseUpdate = 0
local firstLoad = true

-- Changed by onclick on dropdown
local selectedPage = 1

-- Names, types and factions
local unitNames = {}
local unitTypes = {}
local unitFactions = {}

-- Last known channels
local lastKnownChannel = nil
local currentChannel = nil
-- Relative timer for DPS/HPS meters
local startingTimer = nil

-- Dungeon channel names 
local dungeonChannelNames = {
  -- Basic/Greater Dungeons
  "Burnt Castle Armory", "Greater Burnt Castle Armory",
  "Hadir Farm", "Greater Hadir Farm",
  "Palace Cellar", "Greater Palace Cellar",
  "Sharpwind Mines", "Greater Sharpwind Mines",
  "Howling Abyss", "Greater Howling Abyss",
  "Kroloal Cradle", "Greater Kroloal Cradle",
  -- "Hard" dungeons
  "Mistsong Summit",
  "Serpentis",
  -- Library Floors
  "Encyclopedia Room", --> Floor 1
  "Libris Garden", --> Floor 2
  "Screaming Archives", --> Floor 3
  -- Library Dungeons
  "Corner Reading Room", --> CRR, every floor
  "Screening Hall", --> Floor 1, Wynn
  "Frozen Study", --> Floor 2, Halnaak
  "Deranged Bookroom", --> Floor 3, Alexander
  "Heart of Ayanad" --> Ayanad Scroll Distribution Center
  -- Test value, which is mirage
  -- "Mirage Isle"
}

-- Filter Display Strings
local filtersDisplay = {
  "Total Damage",
  "Damage Per Second",
  "Total Healing",
  "Healing Per Second",
  "Damage Taken",
  "Damage Absorbed"
}
local unitFiltersDisplay = {
  "Players",
  "Hostiles",
  "NPCs"
}

-- Path for log files being stored
local logPath = "stats_meter/logs/stats_meter_log_template.txt"

-- TODO: Useful for debugging bullshit ---> dump fields on 
-- for key,value in pairs(api.Team) do
--   api.Log:Info("found member " .. key);
-- end

local pages = {
  {
    windowTitle = "Total Damage",
    tableName = "total_dmg"
  },
  {
    windowTitle = "Damage Per Second (DPS)",
    tableName = "dps"
  },
  {
    windowTitle = "Total Healing",
    tableName = "total_healing"
  },
  {
    windowTitle = "Healing Per Second (HPS)",
    tableName = "hps"
  },
  {
    windowTitle = "Damage Taken",
    tableName = "dmg_taken"
  },
  {
    windowTitle = "Damage Absorbed (%)",
    tableName = "dmg_absorbed_raw"
  }
}

local unitFilters = {
  Players = 0,
  Hostiles = 0,
  NPCs = 0
}

local unitFiltersToTypes = {
  character = "Players",
  hostile = "Hostiles", 
  npc = "NPCs"
}

-- Utility Functions
-- Sorting function for associative arrays
local function getKeysSortedByValue(tbl, sortFunction)
  local keys = {}
  for key in pairs(tbl) do
    table.insert(keys, key)
  end
  table.sort(keys, function(a, b)
    return sortFunction(tbl[a], tbl[b])
  end)
  return keys
end

-- Checking if a table contains a value
local function tableContains(tbl, checkFor)
  for i, value in ipairs(tbl) do
    if value == checkFor then 
      return true 
    end
  end
  return false
end

-- Checking if a table contains a value by pairs, not ipairs
local function tableContainsPairs(tbl, checkFor)
  for i, value in pairs(tbl) do
    if value == checkFor then 
      return true 
    end
  end
  return false
end

local function tableCopy(t)
  local t2 = {}
  for k,v in pairs(t) do
    t2[k] = v
  end
  return t2
end
-- Remove entries for "nil" and "0" from the table.
local function removeNilEntries(tbl)
  local keysToRemove = { "0", "nil" }
  for i, keyToRemove in ipairs(tbl) do
    if tbl[keyToRemove] ~= nil then
      tbl[keysToRemove] = nil
    end 
  end    
end

local function displayTimeString(timeInMs)
  local seconds = math.floor(timeInMs / 1000) % 60
  local minutes = math.floor(timeInMs / (1000*60)) % 60  
  local hours = math.floor(timeInMs / (1000*60*60)) % 24
  
  return string.format("%02d:%02d", minutes, seconds)
end

local function removeNilEntriesFromStats(stats)
  removeNilEntries(stats["total_dmg"])
  removeNilEntries(stats["dps"])
  removeNilEntries(stats["total_healing"])
  removeNilEntries(stats["hps"])
  removeNilEntries(stats["dmg_taken"])
  removeNilEntries(stats["dmg_absorbed_raw"])
  removeNilEntries(stats["dmg_absorbed"])
end

local function saveLogFile()
  -- Save current state of stats meter to a log file
  stats["_NAMES"] = unitNames --> save names to the file as well 
  local timedLogPath = string.gsub(logPath, "template", tostring(startingTimer).. "-" .. tostring(api.Time:GetUiMsec()))
  api.File:Write(timedLogPath, stats)
end

-- For reseting the meter
local function reinitializeMeter()
  -- Reset the meter and the timer
  stats["total_dmg"] = {}
  stats["dps"] = {}
  stats["total_healing"] = {}
  stats["hps"] = {}
  stats["dmg_taken"] = {}
  stats["dmg_absorbed_raw"] = {}
  stats["dmg_absorbed"] = {}
  -- reset details as well
  statsDetails["total_dmg"] = {}
  statsDetails["total_healing"] = {}
  statsDetails["dmg_taken"] = {}
  -- 
  if stats["_NAMES"] ~= nil then 
    stats["_NAMES"] = nil
    unitNames = {}
    unitFactions = {}
    unitTypes = {}
  end 
  startingTimer = api.Time:GetUiMsec()
end 

local function updateDpsHpsNumbers()
  local secondsSinceStarted = api.Time:GetUiMsec() - startingTimer
  for key, value in pairs(stats["total_dmg"]) do
    stats["dps"][key] = math.floor(value / secondsSinceStarted * 1000)
  end
  for key, value in pairs(stats["total_healing"]) do
    stats["hps"][key] = math.floor(value / secondsSinceStarted * 1000)
  end
end

local function updateAbsorbedDmgNumbers()
  for key, value in pairs(stats["dmg_absorbed_raw"]) do
    local totalDmgTaken = stats["dmg_taken"][key] + stats["dmg_absorbed_raw"][key]
    stats["dmg_absorbed"][key] = tostring(math.floor((stats["dmg_absorbed_raw"][key] / totalDmgTaken) * 1000) / #statsMeterWnd.child)
  end
end 

local function getMainSkillsetName(unitClassTable)
  local classMappings = {
    "Battlerage",
    "Witchcraft",
    "Defense",
    "Auramancy",
    "Occultism",
    "Archery",
    "Sorcery",
    "Shadowplay",
    "Songcraft",
    "Vitalism"
  }
  -- Prioritizing different skill icons
  if tableContainsPairs(unitClassTable, 6) then 
    return 6
  elseif tableContainsPairs(unitClassTable, 10) then
    return 10
  elseif tableContainsPairs(unitClassTable, 7) then
    return 7
  elseif tableContainsPairs(unitClassTable, 1) then
    return 1
  elseif tableContainsPairs(unitClassTable, 3) then
    return 3  
  end 
  return 0
end

local function getSkillsetIcon(skillsetId, widget)
  local size = 12
  if skillsetId < 1 or skillsetId > 10 then 
    return nil
  end 
  local texturePath = TEXTURE_PATH.HUD
  local coords = {
    -- Battlerage Icon
    { 480, 498, size, size },
    -- Witchcraft Icon
    { 534, 483, size, size },
    -- Defense Icon
    { 492, 498, size, size },
    -- Auramancy Icon
    { 510, 483, size, size },
    -- Occultism Icon
    { 522, 471, size, size },
    -- Archery Icon
    { 528, 454, size, size },
    -- Sorcery Icon
    { 504, 498, size, size },
    -- Shadowplay Icon
    { 522, 483, size, size },
    -- Songcraft Icon
    { 534, 471, size, size },
    -- Vitalism Icon
    { 510, 471, size, size }
  }
  local iconCoords = coords[skillsetId]
  local icon = widget:CreateImageDrawable(TEXTURE_PATH.HUD, "overlay")
  icon:SetCoords(iconCoords[1], iconCoords[2], iconCoords[3], iconCoords[4])
  icon:SetExtent(iconCoords[3], iconCoords[4])
  icon:SetVisible(true)
  icon:AddAnchor("LEFT", widget, size + 1, 0)
  widget.skillsetIcon = icon

  return icon
end

local function getPrettyAmountNumber(number)
  local prettyNumber
  if number > 1000000 then -- Printing 1m -> infinity
    prettyNumber = tostring(math.floor(number / 1000000 * 10) / 10) .. "m"
  elseif number > 1000 then -- Printing 1k -> 999.9k
    prettyNumber = tostring(math.floor(number / 1000 * 10) / 10) .. "k"
  else
    prettyNumber = tostring(number)
  end
  return prettyNumber
end

local function getUnitIdFromNames(unitName)
  for unitId, name in pairs(unitNames) do
    if name == unitName then
      return unitId
    end
  end
  return nil
end 

local function loadDamageBreakdown(unitName)
  -- detailsWindow.title:SetText("Damage Breakdown for " .. tostring(unitName))
  -- api.Log:Info("[Stats Meter] Loading damage breakdown for " .. tostring(unitName))
  if unitName == nil or unitName == "" then return end
  detailsWindow.playerLabel:SetText("Player: " .. tostring(unitName))

  local currentStat = ""
  local currentTable = pages[selectedPage].tableName
  local detailsTable = ""
  if currentTable == "total_dmg" or currentTable == "dps" then 
    currentStat = "Damage"
    detailsTable = "total_dmg"
  elseif currentTable == "total_healing" or currentTable == "hps" then
    currentStat = "Healing"
    detailsTable = "total_healing"
  elseif currentTable == "dmg_taken" or currentTable == "dmg_absorbed_raw" then
    currentStat = "Damage Taken"
    detailsTable = "dmg_taken"
  end

  local unitId = getUnitIdFromNames(unitName)
  local totalDmg = stats["total_dmg"][unitId] or 0
  local totalHealing = stats["total_healing"][unitId] or 0
  local totalDmgTaken = stats["dmg_taken"][unitId] or 0
  local totalDmgAbsorbed = stats["dmg_absorbed_raw"][unitId] or 0
  local totalStat = stats[detailsTable][unitId] or 0
  local dps = stats["dps"][unitId] or 0
  local hps = stats["hps"][unitId] or 0
  local dmgAbsorbedPercent = stats["dmg_absorbed"][unitId] or 0

  local totalString = ""
  if detailsTable == "total_dmg" then 
    totalString = "Total Damage: " .. tostring(getPrettyAmountNumber(totalDmg)) .. " | DPS: " .. tostring(getPrettyAmountNumber(dps))
  elseif detailsTable == "total_healing" then
    totalString = "Total Healing: " .. tostring(getPrettyAmountNumber(totalHealing)) .. " | HPS: " .. tostring(getPrettyAmountNumber(hps))
  elseif detailsTable == "dmg_taken" then
    totalString = "Total Damage Taken: " .. tostring(getPrettyAmountNumber(totalDmgTaken)) .. " | Damage Absorbed: " .. tostring(getPrettyAmountNumber(totalDmgAbsorbed)) .. " (" .. tostring(dmgAbsorbedPercent) .. "%)"
  end

  local detailsString = ""
  detailsString = detailsString .. totalString .. "\n"
  local sortedSkills = getKeysSortedByValue(statsDetails[detailsTable][unitName] or {}, function(a, b) return a > b end)
  -- api.Log:Info(sortedSkills)
  for i, skillName in pairs(sortedSkills) do
    local skillAmount = statsDetails[detailsTable][unitName][skillName]
    local skillPercent = math.floor((skillAmount / totalStat) * 1000) / 10
    local skillAmountText = getPrettyAmountNumber(skillAmount)
    detailsString = detailsString .. tostring(i) .. ". " .. tostring(skillName) .. ": " .. tostring(skillAmountText) .. " (" .. tostring(skillPercent) .. "%)\n"
  end

  detailsWindow.detailsTextEdit:SetText(detailsString)
  detailsWindow:Show(true)
end 

-- Main Drawing Update Function
local function Update()
  local cur = pages[selectedPage]
  -- Random shit
  local statNumbers = stats[cur.tableName]
  local sortedUnitIds = getKeysSortedByValue(statNumbers, function(a, b) return a > b end)

  statsMeterWnd.moveWnd:SetText("")
  local labelIndex = 1
  for _, unitId in ipairs(sortedUnitIds) do
    -- Do not write the overall number down
    if unitId ~= "_OVERALL" then
      -- Relevant information for the current unit
      local unitName = api.Unit:GetUnitNameById(unitId)
      local unitInfo = api.Unit:GetUnitInfoById(unitId)
      local unitFaction = "hostile"
      local unitType = "npc"

      ---- Loading information can only be done while a unit is rendered in, so we have to cache unit information.
      -- If the unit is rendered locally, we can get it's info.
      if unitInfo ~= nil then
        unitFaction = unitInfo.faction
        unitType = unitInfo.type
        unitNames[unitId] = unitName
        unitTypes[unitId] = unitType
        unitFactions[unitId] = unitFaction
      end
      
      -- If it's not rendered locally, let's load it from our local caches.
      if unitNames[unitId] ~= nil or unitInfo ~= nil then 
        unitName = tostring(unitNames[unitId])
        unitFaction = tostring(unitFactions[unitId])
        unitType = unitTypes[unitId]
      end
      ---- FILTERING DISPLAYED UNITS
      -- Firstly, do not show any "nils"
      if unitName ~= nil then
        -- Time to filter our based on user selection, skip and dont increment
        local playerFilter = unitFilters['character']

        local npcFilter = unitFilters[unitFiltersToTypes[unitType]]
        local hostileFilter = unitFilters[unitFiltersToTypes[unitFaction]]
        local playerFilter = unitFilters[unitFiltersToTypes[unitType]]
        
        -- TODO: Fix "playerFilter" not filtering out hostiles
        local allowThrough = true
        if unitType == 'character' and unitFaction == 'hostile' then 
          if unitFilters["Players"] == 1 and unitFilters["Hostiles"] ~= 1 then 
            allowThrough = false
          end 
        end 

        if ((npcFilter == 1 and hostileFilter ~= 1) or 
          (npcFilter == 1 and hostileFilter ~= 1 and playerFilter ~= 1) or
          (playerFilter == 1 and hostileFilter ~= 1 and unitFaction ~= "hostile") or 
          (playerFilter == 1 and hostileFilter == 1)) and allowThrough then
          local statAmount = statNumbers[unitId]
          local isInPlayerGroup = false
          -- Flag the member as in party if they are
          if unitType == "character" then
            isInPlayerGroup = (api.Team:IsPartyTeam() or api.Team:GetMemberIndexByName(unitName) ~= nil) and api.Team:GetMemberIndexByName(unitName) > 0
          end

          -- Stop drawing DPS numbers if none are left.
          if labelIndex > #statsMeterWnd.child then
            break
          end

          -- Delete skillsetIcon if it exists
          if statsMeterWnd.child[labelIndex].skillsetIcon ~= nil then
            statsMeterWnd.child[labelIndex].skillsetIcon:Show(false)
            statsMeterWnd.child[labelIndex].skillsetIcon = nil
          end      
          

          -- Contrstructing display strings
          local text = ""
          local nameText = ""
          local amountText = ""
          -- Prettying up the % text in the label
          local statAmountPercent = statAmount / statNumbers["_OVERALL"]
          statAmountPercent = math.floor(statAmountPercent * 100 * 10) / 10
          -- Now, let's pretty up the statAmount
          if statAmount > 1000000 then -- Printing 1m -> infinity
            amountText = tostring(math.floor(statAmount / 1000000 * 10) / 10) .. "m"
          elseif statAmount > 1000 then -- Printing 1k -> 999.9k
            amountText = tostring(math.floor(statAmount / 1000 * 10) / 10) .. "k"
          else
            amountText = statAmount
          end

          if statAmount then
            text = tostring(unitName) .. ": " .. tostring(amountText) .. " (" .. tostring(statAmountPercent) .. "%)"
            nameText = tostring(unitId)
            amountText = tostring(amountText)
          end    
          statsMeterWnd.child[labelIndex].bgStatusBar.statLabel:SetText(tostring(unitName))
          statsMeterWnd.child[labelIndex].bgStatusBar.statAmtLabel:SetText(tostring(amountText) .. " (" .. tostring(statAmountPercent) .. "%)")
          -- Setting status bar's value relative to the highest amount
          local relativePercent = statAmount / statNumbers[sortedUnitIds[2]] * 100
          statsMeterWnd.child[labelIndex].bgStatusBar:SetValue(math.floor(relativePercent))
      
          -- Stylize status bar and label based on unit type (character or monster) and faction
          -- Player Characters
          if unitType == "character" then
            if unitName == (api.Unit:GetUnitNameById(api.Unit:GetUnitId("player"))) then
              -- Draw class icon for yourself!
              if unitInfo ~= nil then
                if unitInfo["class"] ~= nil then 
                  local unitClass = unitInfo.class
                  local mainClass = getMainSkillsetName(unitClass)
                  local skillsetIcon = getSkillsetIcon(mainClass, statsMeterWnd.child[labelIndex])
                end 
              end 
              
              -- thats you! colour bar turquoise, player text white (default text colour)
              statsMeterWnd.child[labelIndex].bgStatusBar.statLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar.statAmtLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar:SetBarColor({
                ConvertColor(0),
                ConvertColor(204),
                ConvertColor(153),
                1
              })
            elseif unitFaction == "hostile" then
              -- colour bar red, player text white (default text colour)
              statsMeterWnd.child[labelIndex].bgStatusBar.statLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar.statAmtLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar:SetBarColor({
                ConvertColor(223),
                ConvertColor(69),
                ConvertColor(69),
                1
              })
            elseif unitFaction ~= "hostile" and isInPlayerGroup then
              -- Draw class icon for party/raid members!
              if unitInfo ~= nil then
                if unitInfo["class"] ~= nil then 
                  local unitClass = unitInfo.class
                  local mainClass = getMainSkillsetName(unitClass)
                  local skillsetIcon = getSkillsetIcon(mainClass, statsMeterWnd.child[labelIndex])
                end 
              end 
              -- colour bar blue, player text white (default text colour)
              statsMeterWnd.child[labelIndex].bgStatusBar.statLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar.statAmtLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar:SetBarColor({
                ConvertColor(86),
                ConvertColor(198),
                ConvertColor(239),
                1
              })
            else 
              -- colour bar green, player text white (default text colour)
              statsMeterWnd.child[labelIndex].bgStatusBar.statLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar.statAmtLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar:SetBarColor({
                ConvertColor(134),
                ConvertColor(207),
                ConvertColor(82),
                1
              })
            end 
          end
          -- Non-Player Characters
          if unitType ~= "character" then
            if unitFaction == "hostile" then
              -- colour bar red, NPC text red
              statsMeterWnd.child[labelIndex].bgStatusBar.statLabel.style:SetColor(1, 0, 0, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar.statAmtLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar:SetBarColor({
                ConvertColor(223),
                ConvertColor(69),
                ConvertColor(69),
                1
              })
            else
              -- Any non-hostile NPC is drawn as default.
              statsMeterWnd.child[labelIndex].bgStatusBar.statLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar.statAmtLabel.style:SetColor(1, 1, 1, 1)
              statsMeterWnd.child[labelIndex].bgStatusBar:SetBarColor({
                ConvertColor(230),
                ConvertColor(141),
                ConvertColor(36),
                1
              })
            end
          end
          labelIndex = labelIndex + 1
        end
        -- Do not increment if unit was filtered out
      end
      -- For the _OVERALL stat, skip to the end.
    end 
  end
  if labelIndex < #statsMeterWnd.child then
    for i = labelIndex, #statsMeterWnd.child do
      -- Reset every child that doesn't have unit information written into it
      -- Delete skillsetIcon if it exists
      if statsMeterWnd.child[i]["skillsetIcon"] ~= nil then
        statsMeterWnd.child[i].skillsetIcon:Show(false)
        statsMeterWnd.child[i].skillsetIcon = nil
      end 
      statsMeterWnd.child[i].bgStatusBar.statLabel.style:SetColor(1, 1, 1, 1)
      statsMeterWnd.child[i].bgStatusBar.statLabel:SetText("")
      statsMeterWnd.child[i].bgStatusBar.statAmtLabel.style:SetColor(1, 1, 1, 1)
      statsMeterWnd.child[i].bgStatusBar.statAmtLabel:SetText("")
      statsMeterWnd.child[i].bgStatusBar:SetValue(0)
    end
  end
  statsMeterWnd:Show(true)
end

local function promptForReset()
  resetPromptWnd:Show(true)
end

local function updateLastKnownChannels(channelId, channelName)
  -- Skip anything that isn't shout chat
  local targetChannelId = 1 --> we'll use shout chat channels for zone name
  if channelId ~= 1 then 
    return 
  end 
  -- Move the currently stored channel name to last known channel
  if currentChannel ~= nil then 
    lastKnownChannel = currentChannel
  end 
  
  -- now we replace current
  currentChannel = channelName

  if lastKnownChannel ~= currentChannel then 
    -- If the channel name is a dungeon and we weren't in that dungeon as the last channel, we reset 
    if tableContains(dungeonChannelNames, currentChannel) == true then
      promptForReset()
    end
  end 
end

-- Main Event Handlers
local function OnUpdate(dt)
  
  -- Update timer label
  statsMeterWnd.timerLabel:SetText(displayTimeString(api.Time:GetUiMsec() - startingTimer))
  -- Hack to color dropdowns as white
  ApplyTextColor(statsMeterWnd.moveWnd.filterButton, FONT_COLOR.WHITE)
  ApplyTextColor(statsMeterWnd.moveWnd.unitFiltersButton, FONT_COLOR.DEFAULT)

  -- If this is the first frame drawn, move the meter to where the settings point.
  if firstLoad then 
    local settings = api.GetSettings("stats_meter")
    statsMeterWnd:RemoveAllAnchors()
    if settings.posX == 0 and settings.posY == 0 then
      statsMeterWnd:AddAnchor("RIGHT", "UIParent", 0, 0)
    else 
      statsMeterWnd:AddAnchor("TOPLEFT", "UIParent", settings.posX, settings.posY)
    end 
  
    if settings.playerFilter ~= nil then
      unitFilters["Players"] = settings.playerFilter
      if unitFilters["Players"] == 1 then
        statsMeterWnd.moveWnd.unitFiltersButton.dropdownItemColor[1] = FONT_COLOR.GREEN
      end 
    end 
    if settings.hostileFilter ~= nil then
      unitFilters["Hostiles"] = settings.hostileFilter
      if unitFilters["Hostiles"] == 1 then
        statsMeterWnd.moveWnd.unitFiltersButton.dropdownItemColor[2] = FONT_COLOR.GREEN
      end 
    end 
    if settings.npcFilter ~= nil then
      unitFilters["NPCs"] = settings.npcFilter
      if unitFilters["NPCs"] == 1 then
        statsMeterWnd.moveWnd.unitFiltersButton.dropdownItemColor[3] = FONT_COLOR.GREEN
      end 
    end 
    if settings.mainFilter ~= nil then 
      selectedPage = settings.mainFilter
      statsMeterWnd.moveWnd.filterButton:Select(selectedPage)
    end 
    firstLoad = false
  end 

  -- TODO: Pause Timer Hack
  lastPauseUpdate = lastPauseUpdate + dt
  if lastPauseUpdate > 900 then 
    if (stats["total_dmg"]["_OVERALL"] == nil) and
      (stats["total_healing"]["_OVERALL"] == nil) and
      (stats["dmg_taken"]["_OVERALL"] == nil and stats["dmg_absorbed_raw"]["_OVERALL"] == nil) then 
      reinitializeMeter()
    end 
    lastPauseUpdate = dt
  end 
  -- Every 60 seconds, save settings.
  lastUpdate = lastUpdate + dt
  if oldSettings ~= settings and lastUpdate > 60000 then
    local settings = api.GetSettings("stats_meter")
    local x, y = statsMeterWnd:GetOffset()
    settings.posX = x
    settings.posY = y
    settings.mainFilter = selectedPage
    settings.playerFilter = unitFilters["Players"]
    settings.hostileFilter = unitFilters["Hostiles"]
    settings.npcFilter = unitFilters["NPCs"]
    api.SaveSettings()
    lastUpdate = dt
  end 
  -- Every 1 second, update meter
  lastMeterUpdate = lastMeterUpdate + dt
  if lastMeterUpdate > 1000 then

    -- -- TODO: CURRENT HACK TO MAKE TRACKING PAUSE UNTIL A NUMBER SHOWS UP
    -- if (stats["total_dmg"]["_OVERALL"] == nil and stats["dps"]["_OVERALL"] == nil) and
    --   (stats["total_healing"]["_OVERALL"] == nil and stats["hps"]["_OVERALL"] == nil) and
    --   (stats["dmg_taken"]["_OVERALL"] == nil and stats["dmg_absorbed_raw"]["_OVERALL"] == nil) then 
    --   reinitializeMeter()
    -- end 
    lastMeterUpdate = dt
    removeNilEntriesFromStats(stats)
    updateDpsHpsNumbers()
    updateAbsorbedDmgNumbers()
    Update()
  end
end


local function OnLoad()
  local settings = api.GetSettings("stats_meter")
  oldSettings = tableCopy(settings)
  -- Initialize settings if not filled out yet
  if settings["posX"] == nil then
    settings["posX"] = 0
  end
  if settings["posY"] == nil then
    settings["posY"] = 0
  end
  if settings["playerFilter"] == nil then
    settings["playerFilter"] = 1
  end
  if settings["hostileFilter"] == nil then
    settings["hostileFilter"] = 1
  end
  if settings["npcFilter"] == nil then
    settings["npcFilter"] = 0
  end
  if settings["mainFilter"] == nil then
    settings["mainFilter"] = 1
  end

  --- Meter Settings window
  -- Settings
	settingsWindow = api.Interface:CreateWindow("settingsWindow", "Stats Meter Settings", 0, 0)
	settingsWindow:AddAnchor("CENTER", "UIParent", 0, 0)
	settingsWindow:SetExtent(300, 100)
	settingsWindow:Show(false)
	-- Add it to the michael client addon menu bara
	michaelClientLib:initializeMichaelClient()
	local configMenu = ADDON:GetContent(UIC.SYSTEM_CONFIG_FRAME)
	configMenu.michaelClient:AddAddon("Stats Meter", function()
		settingsWindow:Show(true)
	end)

  --- Meter Details Window
  detailsWindow = api.Interface:CreateWindow("detailsWindow", "Stats Meter Details", 0, 0)
  detailsWindow:AddAnchor("CENTER", "UIParent", 0, 0)
  detailsWindow:SetExtent(430, 530)
  detailsWindow:Show(false)
  -- Player label
  local playerLabel = detailsWindow:CreateChildWidget("label", "playerNameLabel", 0, true)
  playerLabel:AddAnchor("TOPLEFT", detailsWindow, 12, 46)
  playerLabel.style:SetFontSize(FONT_SIZE.LARGE)
  playerLabel.style:SetAlign(ALIGN.LEFT)
  playerLabel:SetText("Unit: ")
  -- playerLabel:SetExtent(100, 20)
  ApplyTextColor(playerLabel, FONT_COLOR.DEFAULT)
  detailsWindow.playerLabel = playerLabel
  -- Text area for details
  local detailsTextEdit = W_CTRL.CreateMultiLineEdit("detailsTextEdit", detailsWindow)
  detailsTextEdit:AddAnchor("TOPLEFT", detailsWindow, 12, 62)
  detailsTextEdit:AddAnchor("BOTTOMRIGHT", detailsWindow, -12, -12)
  detailsTextEdit:SetMaxTextLength(5000)
  detailsWindow.detailsTextEdit = detailsTextEdit


  -- TODO: This is the section where we put everything else
  statsMeterWnd = api.Interface:CreateEmptyWindow("statsMeterWnd", "UIParent")
  statsMeterWnd:SetExtent(280, 280)
  --statsMeterWnd:SetTitle("dps meter")
  --statsMeterWnd:SetCloseOnEscape(false)
  --statsMeterWnd.titleBar.closeButton:Show(false)
  statsMeterWnd.child = {}
  local offsetX = 30
  local offsetY = 32
  local labelHeight = 20
  for k = 1, 12 do
    -- Overall child widget and ranking # text
    local id = tostring(k) .. ""
    statsMeterWnd.child[k] = api.Interface:CreateWidget("label", id, statsMeterWnd)
    local child = statsMeterWnd.child[k]
    child:AddAnchor("TOPLEFT", 12, offsetY)
    child:SetExtent(255, labelHeight)
    child:SetText(id)
    child.style:SetColor(1, 1, 1, 1)
    child.style:SetAlign(ALIGN.LEFT)
    function child:OnClick()
      loadDamageBreakdown(child.bgStatusBar.statLabel:GetText())
    end 
    child:SetHandler("OnClick", child.OnClick)

    -- Status bar and background
    local statusBar = api.Interface:CreateStatusBar("bgStatusBar", child, "item_evolving_material")
    child.bgStatusBar = statusBar

    -- Correcting the coords to show only top layer (texture width divided by 2)  
    local coords = {
      GetTextureInfo(TEXTURE_PATH.COSPLAY_ENCHANT, "grade_01"):GetCoords()
    }
    child.bgStatusBar.statusBar:SetBarTextureCoords(coords[1], coords[2], coords[3] / 2, coords[4])  
    
    child.bgStatusBar:AddAnchor("TOPLEFT", child, 25, 1)
    child.bgStatusBar:AddAnchor("BOTTOMRIGHT", child, -1, -1)
    child.bgStatusBar:SetMinMaxValues(0, 100)
    child.bgStatusBar:SetBarColor({
      ConvertColor(222),
      ConvertColor(177),
      ConvertColor(102),
      1
    })
    child.bgStatusBar.bg:SetColor(ConvertColor(76), ConvertColor(45), ConvertColor(8), 0.4)
    
    -- Display text for name and # + % of selected stat 
    local statLabel = child.bgStatusBar:CreateChildWidget("label", "statLabel", 0, true)
    statLabel.style:SetShadow(true)
    statLabel.style:SetAlign(ALIGN.LEFT)
    ApplyTextColor(statLabel, FONT_COLOR.WHITE)
    statLabel:AddAnchor("LEFT", 5, 0)
    local statAmtLabel = child.bgStatusBar:CreateChildWidget("label", "statAmtLabel", 0, true)
    statAmtLabel.style:SetShadow(true)
    statAmtLabel.style:SetAlign(ALIGN.RIGHT)
    ApplyTextColor(statAmtLabel, FONT_COLOR.WHITE)
    statAmtLabel:AddAnchor("RIGHT", -5, 0)
    
    offsetY = offsetY + labelHeight
  end



  --- Add dragable bar across top
  local moveWnd = statsMeterWnd:CreateChildWidget("label", "moveWnd", 0, true)
  moveWnd:AddAnchor("TOPLEFT", statsMeterWnd, 12, 0)
  moveWnd:AddAnchor("TOPRIGHT", statsMeterWnd, 0, 0)
  moveWnd:SetHeight(35)
  moveWnd.style:SetFontSize(FONT_SIZE.XLARGE)
  moveWnd.style:SetAlign(ALIGN.LEFT)
  moveWnd:SetText("")
  ApplyTextColor(moveWnd, FONT_COLOR.WHITE)
  -- Drag handlers for dragable bar
  function moveWnd:OnDragStart()
    if api.Input:IsShiftKeyDown() then
      statsMeterWnd:StartMoving()
      api.Cursor:ClearCursor()
      api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end
  end
  moveWnd:SetHandler("OnDragStart", moveWnd.OnDragStart)
  function moveWnd:OnDragStop()
    statsMeterWnd:StopMovingOrSizing()
    api.Cursor:ClearCursor()
  end
  moveWnd:SetHandler("OnDragStop", moveWnd.OnDragStop)
  moveWnd:EnableDrag(true)
  -- Background for Title Bar
  moveWnd.bg = moveWnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
  moveWnd.bg:SetTextureInfo("bg_quest")
  moveWnd.bg:SetColor(0, 0, 0, 0.7)
  moveWnd.bg:AddAnchor("TOPLEFT", moveWnd, -12, 0)
  moveWnd.bg:AddAnchor("BOTTOMRIGHT", moveWnd, 0, 0)

  
  -- Timer clock icon and label
  local timerLabel = statsMeterWnd:CreateChildWidget("label", "timerLabel", 0, true)
  timerLabel.style:SetShadow(true)
  timerLabel.style:SetAlign(ALIGN.RIGHT)
  timerLabel:AddAnchor("TOPRIGHT", statsMeterWnd, "TOPRIGHT", -60, 15)
  timerLabel.style:SetFontSize(FONT_SIZE.SMALL)
  local clockIcon = timerLabel:CreateChildWidget("label", "clockIcon", 0, true)  
  clockIcon:AddAnchor("TOPRIGHT", timerLabel, "TOPLEFT", -32, -10)
  clockIcon:SetExtent(FONT_SIZE.SMALL *2, FONT_SIZE.SMALL *2)
  local clockIconTexture = clockIcon:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
  clockIconTexture:SetTextureInfo("clock")
  clockIconTexture:AddAnchor("TOPLEFT", clockIcon, 0, 0)
  clockIconTexture:AddAnchor("BOTTOMRIGHT", clockIcon, 0, 0)

  -- Refresh button for timer
  local refreshButton = statsMeterWnd:CreateChildWidget("button", "refreshButton", 0, true)
  refreshButton:AddAnchor("TOPRIGHT", moveWnd, -35, 6)
  refreshButton:Show(true)
  api.Interface:ApplyButtonSkin(refreshButton, BUTTON_BASIC.RESET)
  refreshButton:SetExtent(20, 20)

  local unitFiltersDisplayColors = {
    FONT_COLOR.RED,
    FONT_COLOR.RED,
    FONT_COLOR.RED
  }

  -- Main Filter Dropdown Menu (Also used as title)
  local filterButton = api.Interface:CreateComboBox(moveWnd)
  filterButton:AddAnchor("TOPLEFT", moveWnd, -4, 0)
  filterButton:SetExtent(150, 30)
  filterButton.dropdownItem = filtersDisplay
  filterButton:Select(1)
  filterButton.style:SetFontSize(FONT_SIZE.LARGE)
  ApplyTextColor(filterButton, FONT_COLOR.WHITE)
  filterButton.bg:SetColor(0,0,0,0)
  filterButton:SetHighlightTextColor(1, 1, 1, 1)
  filterButton:SetPushedTextColor(1, 1, 1, 1)
  filterButton:SetDisabledTextColor(1, 1, 1, 1)
  filterButton:SetTextColor(1, 1, 1, 1)
  filterButton.button:Show(false) -- Hide dropdown arrow
  moveWnd.filterButton = filterButton

  -- Unit Filters Dropdown Menu
  local unitFiltersButton = api.Interface:CreateComboBox(settingsWindow)
  unitFiltersButton:AddAnchor("TOPLEFT", settingsWindow, 10, 50)
  unitFiltersButton:SetExtent(100, 30)
  unitFiltersButton.dropdownItem = unitFiltersDisplay
  unitFiltersButton.dropdownItemColor = unitFiltersDisplayColors
  unitFiltersButton:SetText("Filters")
  unitFiltersButton:Select(0)
  unitFiltersButton.style:SetFontSize(FONT_SIZE.LARGE)
  ApplyTextColor(unitFiltersButton, FONT_COLOR.DEFAULT)
  -- unitFiltersButton.bg:SetColor(0,0,0,0)
  unitFiltersButton:SetHighlightTextColor(1, 1, 1, 1)
  unitFiltersButton:SetPushedTextColor(1, 1, 1, 1)
  unitFiltersButton:SetDisabledTextColor(1, 1, 1, 1)
  unitFiltersButton:SetTextColor(1, 1, 1, 1)
  -- unitFiltersButton.button:Show(false) -- Hide dropdown arrow
  moveWnd.unitFiltersButton = unitFiltersButton

  -- Minimize button
  local minimizeButton = statsMeterWnd:CreateChildWidget("button", "minimizeButton", 0, true)
  minimizeButton:SetExtent(26, 28)
  minimizeButton:AddAnchor("TOPRIGHT", statsMeterWnd, -9, 3)
  local minimizeButtonTexture = minimizeButton:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
  minimizeButtonTexture:SetTexture(TEXTURE_PATH.HUD)
  minimizeButtonTexture:SetCoords(754, 121, 26, 28)
  minimizeButtonTexture:AddAnchor("TOPLEFT", minimizeButton, 0, 0)
  minimizeButtonTexture:SetExtent(26, 28)

  --- Minimized view & maximize button
  minimizedWnd = api.Interface:CreateEmptyWindow("minimizedWnd", "UIParent")
  minimizedWnd:SetExtent(130, 30)
  minimizedWnd:AddAnchor("TOPRIGHT", statsMeterWnd, 0, 0)
  local minimizedLabel = minimizedWnd:CreateChildWidget("label", "minimizedLabel", 0, true)
  minimizedLabel:SetText("Stats Meter")
  minimizedLabel.style:SetFontSize(FONT_SIZE.LARGE)
  minimizedLabel.style:SetAlign(ALIGN.RIGHT)
  minimizedLabel:AddAnchor("TOPRIGHT", minimizedWnd, -40, FONT_SIZE.LARGE - 2)
  -- Dragable bar for minimized window too
  local minimizedMoveWnd = minimizedWnd:CreateChildWidget("label", "minimizedMoveWnd", 0, true)
  minimizedMoveWnd:AddAnchor("TOPLEFT", minimizedWnd, 12, 0)
  minimizedMoveWnd:AddAnchor("TOPRIGHT", minimizedWnd, 0, 0)
  minimizedMoveWnd:SetHeight(30)
  -- Drag handlers for dragable bar
  function minimizedMoveWnd:OnDragStart(arg)
    if arg == "LeftButton" and api.Input:IsShiftKeyDown() then
      minimizedWnd:StartMoving()
      api.Cursor:ClearCursor()
      api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end
  end
  minimizedMoveWnd:SetHandler("OnDragStart", minimizedMoveWnd.OnDragStart)
  function minimizedMoveWnd:OnDragStop()
    minimizedWnd:StopMovingOrSizing()
    api.Cursor:ClearCursor()
  end
  minimizedMoveWnd:SetHandler("OnDragStop", minimizedMoveWnd.OnDragStop)
  minimizedMoveWnd:EnableDrag(true)
  -- Toggle back to maximized view with this button
  local maximizeButton = minimizedWnd:CreateChildWidget("button", "maximizeButton", 0, true)
  maximizeButton:SetExtent(26, 28)
  maximizeButton:AddAnchor("TOPRIGHT", minimizedWnd, -12, 0)
  local maximizeButtonTexture = maximizeButton:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
  maximizeButtonTexture:SetTexture(TEXTURE_PATH.HUD)
  maximizeButtonTexture:SetCoords(754, 94, 26, 28)
  maximizeButtonTexture:AddAnchor("TOPLEFT", maximizeButton, 0, 0)
  maximizeButtonTexture:SetExtent(26, 28)
  -- Minimized Window Background Styling
  minimizedWnd.bg = minimizedWnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
  minimizedWnd.bg:SetTextureInfo("bg_quest")
  minimizedWnd.bg:SetColor(0, 0, 0, 0.5)
  minimizedWnd.bg:AddAnchor("TOPLEFT", minimizedWnd, 0, 0)
  minimizedWnd.bg:AddAnchor("BOTTOMRIGHT", minimizedWnd, 0, 0)

  minimizedWnd:Show(false) --> default to being hidden

  -- Main Window Background Styling
  statsMeterWnd.bg = statsMeterWnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
  statsMeterWnd.bg:SetTextureInfo("bg_quest")
  statsMeterWnd.bg:SetColor(0, 0, 0, 0.5)
  statsMeterWnd.bg:AddAnchor("TOPLEFT", statsMeterWnd, 0, 0)
  statsMeterWnd.bg:AddAnchor("BOTTOMRIGHT", statsMeterWnd, 0, 0)



  -- Show the damn thing.
  statsMeterWnd:Show(true)

  --- Meter Reset Prompt window
  -- Actual window
  resetPromptWnd = api.Interface:CreateWindow("resetPromptWnd", "Dungeon Entry Detected", 0, 0)
  resetPromptWnd:AddAnchor("CENTER", "UIParent", 0, 0)
  resetPromptWnd:SetExtent(300, 150)
  -- Prompt label and buttons
  resetPromptText = "You are entering a new dungeon. \n \n  Would you like to reset your meter?"
  resetPromptLabel = resetPromptWnd:CreateChildWidget("textbox", "resetPromptLabel", 0, true)
  resetPromptLabel:SetText(resetPromptText)
  resetPromptLabel:SetExtent(240, FONT_SIZE.LARGE * 2.5)
  resetPromptLabel.style:SetAlign(ALIGN.CENTER)
  ApplyTextColor(resetPromptLabel, FONT_COLOR.DEFAULT)
  resetPromptLabel:AddAnchor("CENTER", resetPromptWnd, 0, 0)
  resetPromptYesBtn = resetPromptWnd:CreateChildWidget("button", "resetPromptYesBtn", 0, true)
  api.Interface:ApplyButtonSkin(resetPromptYesBtn, BUTTON_BASIC.DEFAULT)
  resetPromptYesBtn:AddAnchor("BOTTOMLEFT", resetPromptWnd, 10, -10)
  resetPromptYesBtn:SetText("Yes")
  resetPromptNoBtn = resetPromptWnd:CreateChildWidget("button", "resetPromptNoBtn", 0, true)
  api.Interface:ApplyButtonSkin(resetPromptNoBtn, BUTTON_BASIC.DEFAULT)
  resetPromptNoBtn:AddAnchor("BOTTOMRIGHT", resetPromptWnd, -10, -10)
  resetPromptNoBtn:SetText("No")
  -- Starts off hidden (Hide the damn thing)
  resetPromptWnd:Show(false)

  


  

  -- Where statistics are set
  stats = {}
  stats["total_dmg"] = {}
  stats["dps"] = {}
  stats["total_healing"] = {}
  stats["hps"] = {}
  stats['dmg_taken'] = {}
  stats['dmg_absorbed_raw'] = {}
  stats['dmg_absorbed'] = {}

  statsDetails = {}
  statsDetails["total_dmg"] = {}
  statsDetails["total_healing"] = {}
  statsDetails['dmg_taken'] = {}

  -- Changed by onclick on dropdown
  selectedPage = 1

  unitNames = {}
  unitTypes = {}
  unitFactions = {}

  -- Last known channels
  lastKnownChannel = nil
  currentChannel = nil

  -- Relative timer for DPS/HPS meters
  startingTimer = api.Time:GetUiMsec()

  -- Crude total dmg calc
  local function addDmgNumber(sourceUnitId, targetUnitId, amount, skillType, hitOrMissType, weaponDamage, isSynergy, distance)
    local sourceUnitIdStr = tostring(sourceUnitId)
    
    local unitName = api.Unit:GetUnitNameById(sourceUnitId)
    local unitInfo = nil 
    local unitType = nil
    if unitTypes[sourceUnitIdStr] == nil then 
      unitInfo = api.Unit:GetUnitInfoById(sourceUnitId)
      if unitInfo ~= nil and unitInfo.type ~= nil then 
        unitType = unitInfo.type
        unitTypes[sourceUnitIdStr] = unitType
      end 
    else
      unitType = unitTypes[sourceUnitIdStr]
    end 

    
    local targetName = api.Unit:GetUnitNameById(targetUnitId)

    if unitType ~= "npc" or (unitType == "npc" and unitFilters["NPCs"] == 1) then 
      -- Add to individual player totals
      if skillType == "SKILL" or skillType == "SWING" or skillType == "DOT" then 
        if stats["total_dmg"][sourceUnitIdStr] == nil then
          stats["total_dmg"][sourceUnitIdStr] = tonumber(amount) * -1
        else  
          stats["total_dmg"][sourceUnitIdStr] = stats["total_dmg"][sourceUnitIdStr] + (tonumber(amount) * -1)
        end
        -- Add to overall (all player) totals
        if stats["total_dmg"]["_OVERALL"] == nil then
          stats["total_dmg"]["_OVERALL"] = tonumber(amount) * -1
        else
          stats["total_dmg"]["_OVERALL"] = stats["total_dmg"]["_OVERALL"] + (tonumber(amount) * -1)
        end
      end
      if skillType == "HEAL" then
        if stats["total_healing"][sourceUnitIdStr] == nil then
          stats["total_healing"][sourceUnitIdStr] = tonumber(amount)
        else  
          stats["total_healing"][sourceUnitIdStr] = stats["total_healing"][sourceUnitIdStr] + (tonumber(amount))
        end
        -- Add to overall (all player) totals
        if stats["total_healing"]["_OVERALL"] == nil then
          stats["total_healing"]["_OVERALL"] = tonumber(amount)
        else
          stats["total_healing"]["_OVERALL"] = stats["total_healing"]["_OVERALL"] + (tonumber(amount))
        end
      end
    end
  end

  -- TODO: Crude Logging of combat messages. switch all non-personal logic over to this.
  local function processCombatMessage(targetUnitId, combatEvent, source, target, ...)
    local targetUnitIdStr = tostring(targetUnitId)
    local unitInfo = nil 
    local unitType = nil
    if unitTypes[targetUnitIdStr] == nil then 
      unitInfo = api.Unit:GetUnitInfoById(targetUnitId)
      if unitInfo ~= nil and unitInfo.type ~= nil then 
        if unitInfo.type ~= nil then 
          unitType = unitInfo.type
          unitTypes[targetUnitIdStr] = unitType
        end
      end 
    else
      unitType = unitTypes[targetUnitIdStr]
    end 
    local result = ParseCombatMessage(combatEvent, unpack(arg))
    if unitType ~= "npc" or (unitType == "npc" and unitFilters["NPCs"] == 1) then 
      if combatEvent == "SPELL_DAMAGE" or combatEvent == "SPELL_DOT_DAMAGE" or combatEvent == "MELEE_DAMAGE" then --> also needs "MELEE_DAMAGE"
        -- Record damage taken
        if stats["dmg_taken"][targetUnitIdStr] == nil then 
          stats["dmg_taken"][targetUnitIdStr] = tonumber(result.damage) * -1
        else
          stats["dmg_taken"][targetUnitIdStr] = stats["dmg_taken"][targetUnitIdStr] + (tonumber(result.damage) * -1)
        end 
        -- Add to overall damage taken totals
        if stats["dmg_taken"]["_OVERALL"] == nil then 
          stats["dmg_taken"]["_OVERALL"] = tonumber(result.damage) * -1
        else
          stats["dmg_taken"]["_OVERALL"] = stats["dmg_taken"]["_OVERALL"] + (tonumber(result.damage) * -1)
        end 
        -- Record damage abosrbed
        if stats["dmg_absorbed_raw"][targetUnitIdStr] == nil then 
          stats["dmg_absorbed_raw"][targetUnitIdStr] = tonumber(result.reduced) * 1
        else
          stats["dmg_absorbed_raw"][targetUnitIdStr] = stats["dmg_absorbed_raw"][targetUnitIdStr] + (tonumber(result.reduced) * 1)
        end 
        -- Add to overall damage absorbed totals
        if stats["dmg_absorbed_raw"]["_OVERALL"] == nil then 
          stats["dmg_absorbed_raw"]["_OVERALL"] = tonumber(result.reduced) * 1
        else
          stats["dmg_absorbed_raw"]["_OVERALL"] = stats["dmg_absorbed_raw"]["_OVERALL"] + (tonumber(result.reduced) * 1)
        end 
      end 
    end
    -- Filling details
    if combatEvent == "SPELL_DAMAGE" or combatEvent == "SPELL_DOT_DAMAGE" or combatEvent == "MELEE_DAMAGE" then 
      if source == nil or source == "" or result.spellName == nil or result.spellName == "" then 
        return
      end
      if statsDetails["total_dmg"][source] == nil then 
        statsDetails["total_dmg"][source] = {}
      end
      if statsDetails["total_dmg"][source][result.spellName] == nil then 
        statsDetails["total_dmg"][source][result.spellName] = tonumber(result.damage) * -1
      else
        statsDetails["total_dmg"][source][result.spellName] = statsDetails["total_dmg"][source][result.spellName] + (tonumber(result.damage) * -1)
      end

      if statsDetails["dmg_taken"][target] == nil then 
        statsDetails["dmg_taken"][target] = {}
      end
      if statsDetails["dmg_taken"][target][result.spellName] == nil then 
        statsDetails["dmg_taken"][target][result.spellName] = tonumber(result.damage) * -1
      else
        statsDetails["dmg_taken"][target][result.spellName] = statsDetails["dmg_taken"][target][result.spellName] + (tonumber(result.damage) * -1)
      end
    end 
    if combatEvent == "SPELL_HEALED" then 
      -- api.Log:Info(result)
      if statsDetails["total_healing"][source] == nil then 
        statsDetails["total_healing"][source] = {}
      end
      if statsDetails["total_healing"][source][result.spellName] == nil then 
        statsDetails["total_healing"][source][result.spellName] = tonumber(result.heal)
      else
        statsDetails["total_healing"][source][result.spellName] = statsDetails["total_healing"][source][result.spellName] + (tonumber(result.heal))
      end
    end 
  end 


  function statsMeterWnd:OnEvent(event, ...)
    if event == "COMBAT_TEXT" then
      addDmgNumber(unpack(arg))
      -- updateDpsHpsNumbers()
    end
    if event == "COMBAT_MSG" then
      processCombatMessage(unpack(arg))
      -- updateAbsorbedDmgNumbers()
    end
    if event == "CHAT_JOINED_CHANNEL" then 
      updateLastKnownChannels(unpack(arg))
    end 
    if event == "CHAT_LEAVED_CHANNEL" then
      return nil --> pass
    end
  end
  statsMeterWnd:SetHandler("OnEvent", statsMeterWnd.OnEvent)
  statsMeterWnd:RegisterEvent("COMBAT_TEXT")
  statsMeterWnd:RegisterEvent("COMBAT_MSG")
  statsMeterWnd:RegisterEvent("CHAT_JOINED_CHANNEL")
  statsMeterWnd:RegisterEvent("CHAT_LEAVED_CHANNEL")

  function statsMeterWnd:OnUpdate(dt)
    OnUpdate(dt)
  end 
  statsMeterWnd:SetHandler("OnUpdate", statsMeterWnd.OnUpdate)

  -- Button Handlers
  statsMeterWnd.refreshButton:SetHandler("OnClick", function()
    saveLogFile()
    reinitializeMeter()
    Update()
  end)

  resetPromptWnd.resetPromptYesBtn:SetHandler("OnClick", function()
    saveLogFile()
    reinitializeMeter()
    resetPromptWnd:Show(false)
  end)

  resetPromptWnd.resetPromptNoBtn:SetHandler("OnClick", function()
    resetPromptWnd:Show(false)
  end)

  statsMeterWnd.minimizeButton:SetHandler("OnClick", function()
    local statsMeterX, statsMeterY = statsMeterWnd:GetOffset()
    minimizedWnd:RemoveAllAnchors()
    minimizedWnd:AddAnchor("TOPRIGHT", statsMeterWnd, 0, 0)
    statsMeterWnd:Show(false)
    minimizedWnd:Show(true)
  end)

  minimizedWnd.maximizeButton:SetHandler("OnClick", function()
    statsMeterWnd:RemoveAllAnchors()
    statsMeterWnd:AddAnchor("TOPLEFT", minimizedWnd, 0, 0)
    minimizedWnd:Show(false)
    statsMeterWnd:Show(true)
  end)

  --- Dropdown Handlers
  -- Main Filter Dropdown
  function statsMeterWnd.moveWnd.filterButton:SelectedProc()
    selectedPage = statsMeterWnd.moveWnd.filterButton:GetSelectedIndex()

    -- for i = 1, 50 do
    --   indexStr = tostring(i)
    --   randomNum = math.random(5000000, 100000000)
    --   name = "PogMan" .. indexStr

    --   unitNames[indexStr] = name
    --   unitFactions[indexStr] = "friendly"
    --   unitTypes[indexStr] = "character"
    --   stats['total_dmg'][indexStr] = randomNum
    --   if stats['total_dmg']['_OVERALL'] ~= nil then 
    --     stats['total_dmg']['_OVERALL'] = stats['total_dmg']['_OVERALL'] + randomNum
    --   else
    --     stats['total_dmg']['_OVERALL'] = randomNum
    --   end 
    --   stats['total_healing'][indexStr] = randomNum
    --   if stats['total_healing']['_OVERALL'] ~= nil then 
    --     stats['total_healing']['_OVERALL'] = stats['total_healing']['_OVERALL'] + randomNum
    --   else
    --     stats['total_healing']['_OVERALL'] = randomNum
    --   end 
    --   stats['dmg_taken'][indexStr] = randomNum
    --   if stats['dmg_taken']['_OVERALL'] ~= nil then 
    --     stats['dmg_taken']['_OVERALL'] = stats['dmg_taken']['_OVERALL'] + randomNum
    --   else
    --     stats['dmg_taken']['_OVERALL'] = randomNum
    --   end
    --   stats['dmg_absorbed_raw'][indexStr] = randomNum
    --   if stats['dmg_absorbed_raw']['_OVERALL'] ~= nil then 
    --     stats['dmg_absorbed_raw']['_OVERALL'] = stats['dmg_absorbed_raw']['_OVERALL'] + randomNum
    --   else
    --     stats['dmg_absorbed_raw']['_OVERALL'] = randomNum
    --   end 
      
    --   api.Log:Info(tostring(randomNum))
    -- end 

    -- clear the meter to start fresh, and then update it
    -- for i = 1, #statsMeterWnd.child do
    --   -- Reset every child that doesn't have unit information written into it
    --   -- Delete skillsetIcon if it exists
    --   if statsMeterWnd.child[i].skillsetIcon ~= nil then
    --     statsMeterWnd.child[i].skillsetIcon:Show(false)
    --     statsMeterWnd.child[i].skillsetIcon = nil
    --   end 
    --   statsMeterWnd.child[i].bgStatusBar.statLabel.style:SetColor(1, 1, 1, 1)
    --   statsMeterWnd.child[i].bgStatusBar.statLabel:SetText("")
    --   statsMeterWnd.child[i].bgStatusBar.statAmtLabel.style:SetColor(1, 1, 1, 1)
    --   statsMeterWnd.child[i].bgStatusBar.statAmtLabel:SetText("")
    --   statsMeterWnd.child[i].bgStatusBar:SetValue(0)
    -- end
    Update()
  end
  -- Unit Type Filter Dropdown
  function statsMeterWnd.moveWnd.unitFiltersButton:SelectedProc()
    local clickedFilter = self:GetSelectedIndex()
    local text = self.dropdownItem[clickedFilter]
    if unitFilters[text] ~= nil and unitFilters[text] == 0 then
      unitFilters[text] = 1
      self.dropdownItemColor[clickedFilter] = FONT_COLOR.GREEN
      
    elseif unitFilters[text] ~= nil and unitFilters[text] == 1 then
      unitFilters[text] = 0
      self.dropdownItemColor[clickedFilter] = FONT_COLOR.RED
    end 

    -- clear the meter to start fresh, and then update it
    for i = 1, #statsMeterWnd.child do
      -- Reset every child that doesn't have unit information written into it
      -- Delete skillsetIcon if it exists
      if statsMeterWnd.child[i].skillsetIcon ~= nil then
        statsMeterWnd.child[i].skillsetIcon:Show(false)
        -- statsMeterWnd.child[i].skillsetIcon = nil
      end 
      statsMeterWnd.child[i].bgStatusBar.statLabel.style:SetColor(1, 1, 1, 1)
      statsMeterWnd.child[i].bgStatusBar.statLabel:SetText("")
      statsMeterWnd.child[i].bgStatusBar.statAmtLabel.style:SetColor(1, 1, 1, 1)
      statsMeterWnd.child[i].bgStatusBar.statAmtLabel:SetText("")
      statsMeterWnd.child[i].bgStatusBar:SetValue(0)
    end
    statsMeterWnd.moveWnd.unitFiltersButton:Select(0)
    self:SetText("Filters")
    Update()
  end
  --  
  api.Log:Info("[Stats Meter] Successfully loaded, Please find settings by pressing ESC and clicking 'Stats Meter' in the Addon Menu.")
end

local function OnUnload()
  local settings = api.GetSettings("stats_meter")
  local x, y = statsMeterWnd:GetOffset()
  settings.posX = x
  settings.posY = y
  settings.mainFilter = selectedPage
  settings.playerFilter = unitFilters["Players"]
  settings.hostileFilter = unitFilters["Hostiles"]
  settings.npcFilter = unitFilters["NPCs"]
  api.SaveSettings()
  statsMeterWnd:ReleaseHandler("OnEvent")
  statsMeterWnd:ReleaseHandler("OnUpdate")
  statsMeterWnd:Show(false)
  statsMeterWnd = nil
  minimizedWnd:Show(false)
  minimizedWnd = nil
end
stats_meter_addon.OnLoad = OnLoad
stats_meter_addon.OnUnload = OnUnload

return stats_meter_addon
