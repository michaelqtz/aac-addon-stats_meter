-- Building and drawing the meter's windows. Holds no stats state: main.lua passes in what to
-- draw and receives user actions through the `handlers` given to ui.create.
local api = require("api")
local michaelClientLib = require("stats_meter/michael_client")
local ui = {}

local ADDON_MENU_TITLE = "Stats Meter"
local ROW_COUNT = 12
local ROW_HEIGHT = 20
local ICON_SIZE = 12
local FILTER_NAMES = { "Players", "Hostiles", "NPCs" }

-- Bar colour (0-255 RGB) and name text colour for each units.category()
local CATEGORY_STYLES = {
  self = { bar = { 0, 204, 153 } },                      --> turquoise
  party = { bar = { 86, 198, 239 } },                    --> blue
  player = { bar = { 134, 207, 82 } },                   --> green
  hostile = { bar = { 223, 69, 69 } },                   --> red
  hostileNpc = { bar = { 223, 69, 69 }, name = { 1, 0, 0, 1 } }, --> red, red name
  npc = { bar = { 230, 141, 36 } }                       --> orange
}
local DEFAULT_NAME_COLOR = { 1, 1, 1, 1 }

-- Position of each skillset's icon in TEXTURE_PATH.HUD, by skillset id
local SKILLSET_ICON_COORDS = {
  { 480, 498 }, -- Battlerage
  { 534, 483 }, -- Witchcraft
  { 492, 498 }, -- Defense
  { 510, 483 }, -- Auramancy
  { 522, 471 }, -- Occultism
  { 528, 454 }, -- Archery
  { 504, 498 }, -- Sorcery
  { 522, 483 }, -- Shadowplay
  { 534, 471 }, -- Songcraft
  { 510, 471 }  -- Vitalism
}

local function rgb(color)
  return { ConvertColor(color[1]), ConvertColor(color[2]), ConvertColor(color[3]), 1 }
end

-- Keep the dropdown texts white/default; the combo boxes reset their colour when used
local function applyDropdownColors(self)
  ApplyTextColor(self.filterButton, FONT_COLOR.WHITE)
  ApplyTextColor(self.unitFiltersButton, FONT_COLOR.DEFAULT)
end

local function createSettingsWindow(self)
  local window = api.Interface:CreateWindow("settingsWindow", "Stats Meter Settings", 0, 0)
  window:AddAnchor("CENTER", "UIParent", 0, 0)
  window:SetExtent(300, 100)
  window:Show(false)
  self.settingsWindow = window

  -- Add it to the Addon Options menu (shared with other addons using michael_client)
  local configMenu = michaelClientLib.initializeMichaelClient()
  configMenu.michaelClient:AddAddon(ADDON_MENU_TITLE, function()
    window:Show(true)
  end)

  -- Unit filters dropdown: each click toggles a filter on (green) or off (red)
  local unitFiltersButton = api.Interface:CreateComboBox(window)
  unitFiltersButton:AddAnchor("TOPLEFT", window, 10, 50)
  unitFiltersButton:SetExtent(100, 30)
  unitFiltersButton.dropdownItem = FILTER_NAMES
  unitFiltersButton.dropdownItemColor = { FONT_COLOR.RED, FONT_COLOR.RED, FONT_COLOR.RED }
  unitFiltersButton:SetText("Filters")
  unitFiltersButton:Select(0)
  unitFiltersButton.style:SetFontSize(FONT_SIZE.LARGE)
  unitFiltersButton:SetHighlightTextColor(1, 1, 1, 1)
  unitFiltersButton:SetPushedTextColor(1, 1, 1, 1)
  unitFiltersButton:SetDisabledTextColor(1, 1, 1, 1)
  unitFiltersButton:SetTextColor(1, 1, 1, 1)
  local owner = self
  function unitFiltersButton:SelectedProc()
    local filterName = FILTER_NAMES[self:GetSelectedIndex()]
    self:Select(0)
    self:SetText("Filters")
    applyDropdownColors(owner)
    if filterName ~= nil then
      owner.handlers.onFilterToggled(filterName)
    end
  end
  self.unitFiltersButton = unitFiltersButton
end

local function createDetailsWindow(self)
  local window = api.Interface:CreateWindow("detailsWindow", "Stats Meter Details", 0, 0)
  window:AddAnchor("CENTER", "UIParent", 0, 0)
  window:SetExtent(430, 530)
  window:Show(false)

  local playerLabel = window:CreateChildWidget("label", "playerNameLabel", 0, true)
  playerLabel:AddAnchor("TOPLEFT", window, 12, 46)
  playerLabel.style:SetFontSize(FONT_SIZE.LARGE)
  playerLabel.style:SetAlign(ALIGN.LEFT)
  playerLabel:SetText("Unit: ")
  ApplyTextColor(playerLabel, FONT_COLOR.DEFAULT)
  window.playerLabel = playerLabel

  local detailsTextEdit = W_CTRL.CreateMultiLineEdit("detailsTextEdit", window)
  detailsTextEdit:AddAnchor("TOPLEFT", window, 12, 62)
  detailsTextEdit:AddAnchor("BOTTOMRIGHT", window, -12, -12)
  detailsTextEdit:SetMaxTextLength(5000)
  window.detailsTextEdit = detailsTextEdit
  self.detailsWindow = window
end

local function createRow(self, index, offsetY)
  local row = api.Interface:CreateWidget("label", tostring(index), self.meterWnd)
  row:AddAnchor("TOPLEFT", 12, offsetY)
  row:SetExtent(255, ROW_HEIGHT)
  row:SetText(tostring(index)) --> rank number
  row.style:SetColor(1, 1, 1, 1)
  row.style:SetAlign(ALIGN.LEFT)
  row:SetHandler("OnClick", function()
    if row.unitName ~= nil then
      self.handlers.onRowClicked(row.unitName)
    end
  end)

  -- Status bar and background
  local statusBar = api.Interface:CreateStatusBar("bgStatusBar", row, "item_evolving_material")
  row.bgStatusBar = statusBar
  -- Correcting the coords to show only top layer (texture width divided by 2)
  local coords = { GetTextureInfo(TEXTURE_PATH.COSPLAY_ENCHANT, "grade_01"):GetCoords() }
  statusBar.statusBar:SetBarTextureCoords(coords[1], coords[2], coords[3] / 2, coords[4])
  statusBar:AddAnchor("TOPLEFT", row, 25, 1)
  statusBar:AddAnchor("BOTTOMRIGHT", row, -1, -1)
  statusBar:SetMinMaxValues(0, 100)
  statusBar:SetBarColor(rgb({ 222, 177, 102 }))
  statusBar.bg:SetColor(ConvertColor(76), ConvertColor(45), ConvertColor(8), 0.4)

  -- Name on the left, amount and percentage on the right
  local statLabel = statusBar:CreateChildWidget("label", "statLabel", 0, true)
  statLabel.style:SetShadow(true)
  statLabel.style:SetAlign(ALIGN.LEFT)
  ApplyTextColor(statLabel, FONT_COLOR.WHITE)
  statLabel:AddAnchor("LEFT", 5, 0)
  local statAmtLabel = statusBar:CreateChildWidget("label", "statAmtLabel", 0, true)
  statAmtLabel.style:SetShadow(true)
  statAmtLabel.style:SetAlign(ALIGN.RIGHT)
  ApplyTextColor(statAmtLabel, FONT_COLOR.WHITE)
  statAmtLabel:AddAnchor("RIGHT", -5, 0)

  -- Class icon, created once and reused (shown for yourself and group members)
  local icon = row:CreateImageDrawable(TEXTURE_PATH.HUD, "overlay")
  icon:SetExtent(ICON_SIZE, ICON_SIZE)
  icon:AddAnchor("LEFT", row, ICON_SIZE + 1, 0)
  icon:SetVisible(false)
  row.skillsetIcon = icon

  return row
end

local function createMeterWindow(self)
  local meterWnd = api.Interface:CreateEmptyWindow("statsMeterWnd")
  meterWnd:SetExtent(280, 280)
  self.meterWnd = meterWnd

  self.rows = {}
  local offsetY = 32
  for i = 1, ROW_COUNT do
    self.rows[i] = createRow(self, i, offsetY)
    offsetY = offsetY + ROW_HEIGHT
  end

  -- Draggable title bar (Shift + drag)
  local moveWnd = meterWnd:CreateChildWidget("label", "moveWnd", 0, true)
  moveWnd:AddAnchor("TOPLEFT", meterWnd, 12, 0)
  moveWnd:AddAnchor("TOPRIGHT", meterWnd, 0, 0)
  moveWnd:SetHeight(35)
  moveWnd.style:SetFontSize(FONT_SIZE.XLARGE)
  moveWnd.style:SetAlign(ALIGN.LEFT)
  moveWnd:SetText("")
  ApplyTextColor(moveWnd, FONT_COLOR.WHITE)
  moveWnd:SetHandler("OnDragStart", function()
    if api.Input:IsShiftKeyDown() then
      meterWnd:StartMoving()
      api.Cursor:ClearCursor()
      api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end
  end)
  moveWnd:SetHandler("OnDragStop", function()
    meterWnd:StopMovingOrSizing()
    api.Cursor:ClearCursor()
    self.handlers.onMoved()
  end)
  moveWnd:EnableDrag(true)
  moveWnd.bg = moveWnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
  moveWnd.bg:SetTextureInfo("bg_quest")
  moveWnd.bg:SetColor(0, 0, 0, 0.7)
  moveWnd.bg:AddAnchor("TOPLEFT", moveWnd, -12, 0)
  moveWnd.bg:AddAnchor("BOTTOMRIGHT", moveWnd, 0, 0)

  -- Timer clock icon and label
  local timerLabel = meterWnd:CreateChildWidget("label", "timerLabel", 0, true)
  timerLabel.style:SetShadow(true)
  timerLabel.style:SetAlign(ALIGN.RIGHT)
  timerLabel:AddAnchor("TOPRIGHT", meterWnd, "TOPRIGHT", -60, 15)
  timerLabel.style:SetFontSize(FONT_SIZE.SMALL)
  local clockIcon = timerLabel:CreateChildWidget("label", "clockIcon", 0, true)
  clockIcon:AddAnchor("TOPRIGHT", timerLabel, "TOPLEFT", -32, -10)
  clockIcon:SetExtent(FONT_SIZE.SMALL * 2, FONT_SIZE.SMALL * 2)
  local clockIconTexture = clockIcon:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
  clockIconTexture:SetTextureInfo("clock")
  clockIconTexture:AddAnchor("TOPLEFT", clockIcon, 0, 0)
  clockIconTexture:AddAnchor("BOTTOMRIGHT", clockIcon, 0, 0)
  self.timerLabel = timerLabel

  -- Reset button
  local refreshButton = meterWnd:CreateChildWidget("button", "refreshButton", 0, true)
  refreshButton:AddAnchor("TOPRIGHT", moveWnd, -35, 6)
  refreshButton:Show(true)
  api.Interface:ApplyButtonSkin(refreshButton, BUTTON_BASIC.RESET)
  refreshButton:SetExtent(20, 20)
  refreshButton:SetHandler("OnClick", function()
    self.handlers.onReset()
  end)

  -- Stat dropdown, also used as the title
  local labels = {}
  for i, page in ipairs(self.pages) do labels[i] = page.label end
  local filterButton = api.Interface:CreateComboBox(moveWnd)
  filterButton:AddAnchor("TOPLEFT", moveWnd, -4, 0)
  filterButton:SetExtent(150, 30)
  filterButton.dropdownItem = labels
  filterButton:Select(1)
  filterButton.style:SetFontSize(FONT_SIZE.LARGE)
  filterButton.bg:SetColor(0, 0, 0, 0)
  filterButton:SetHighlightTextColor(1, 1, 1, 1)
  filterButton:SetPushedTextColor(1, 1, 1, 1)
  filterButton:SetDisabledTextColor(1, 1, 1, 1)
  filterButton:SetTextColor(1, 1, 1, 1)
  filterButton.button:Show(false) -- Hide dropdown arrow
  local owner = self
  function filterButton:SelectedProc()
    applyDropdownColors(owner)
    owner.handlers.onPageSelected(self:GetSelectedIndex())
  end
  self.filterButton = filterButton

  -- Minimize button
  local minimizeButton = meterWnd:CreateChildWidget("button", "minimizeButton", 0, true)
  minimizeButton:SetExtent(26, 28)
  minimizeButton:AddAnchor("TOPRIGHT", meterWnd, -9, 3)
  local minimizeButtonTexture = minimizeButton:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
  minimizeButtonTexture:SetTexture(TEXTURE_PATH.HUD)
  minimizeButtonTexture:SetCoords(754, 121, 26, 28)
  minimizeButtonTexture:AddAnchor("TOPLEFT", minimizeButton, 0, 0)
  minimizeButtonTexture:SetExtent(26, 28)
  minimizeButton:SetHandler("OnClick", function()
    self:setMinimized(true)
    self.handlers.onMinimizedChanged(true)
  end)

  meterWnd.bg = meterWnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
  meterWnd.bg:SetTextureInfo("bg_quest")
  meterWnd.bg:SetColor(0, 0, 0, 0.5)
  meterWnd.bg:AddAnchor("TOPLEFT", meterWnd, 0, 0)
  meterWnd.bg:AddAnchor("BOTTOMRIGHT", meterWnd, 0, 0)

  -- Mouse wheel scrolls the meter. Wheel events go to the widget under the cursor, so attach
  -- the handlers to the window and to every part of each row.
  local function onWheelUp() self.handlers.onScroll(-1) end
  local function onWheelDown() self.handlers.onScroll(1) end
  local wheelWidgets = { meterWnd }
  for _, row in ipairs(self.rows) do
    table.insert(wheelWidgets, row)
    table.insert(wheelWidgets, row.bgStatusBar)
    table.insert(wheelWidgets, row.bgStatusBar.statLabel)
    table.insert(wheelWidgets, row.bgStatusBar.statAmtLabel)
  end
  for _, widget in ipairs(wheelWidgets) do
    widget:SetHandler("OnWheelUp", onWheelUp)
    widget:SetHandler("OnWheelDown", onWheelDown)
  end

  meterWnd:Show(true)
end

local function createMinimizedWindow(self)
  local meterWnd = self.meterWnd
  local minimizedWnd = api.Interface:CreateEmptyWindow("minimizedWnd")
  minimizedWnd:SetExtent(130, 30)
  minimizedWnd:AddAnchor("TOPRIGHT", meterWnd, 0, 0)
  local minimizedLabel = minimizedWnd:CreateChildWidget("label", "minimizedLabel", 0, true)
  minimizedLabel:SetText("Stats Meter")
  minimizedLabel.style:SetFontSize(FONT_SIZE.LARGE)
  minimizedLabel.style:SetAlign(ALIGN.RIGHT)
  minimizedLabel:AddAnchor("TOPRIGHT", minimizedWnd, -40, FONT_SIZE.LARGE - 2)

  -- Draggable bar for the minimized window too (Shift + drag)
  local minimizedMoveWnd = minimizedWnd:CreateChildWidget("label", "minimizedMoveWnd", 0, true)
  minimizedMoveWnd:AddAnchor("TOPLEFT", minimizedWnd, 12, 0)
  minimizedMoveWnd:AddAnchor("TOPRIGHT", minimizedWnd, 0, 0)
  minimizedMoveWnd:SetHeight(30)
  minimizedMoveWnd:SetHandler("OnDragStart", function(_, button)
    if button == "LeftButton" and api.Input:IsShiftKeyDown() then
      minimizedWnd:StartMoving()
      api.Cursor:ClearCursor()
      api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
    end
  end)
  minimizedMoveWnd:SetHandler("OnDragStop", function()
    minimizedWnd:StopMovingOrSizing()
    api.Cursor:ClearCursor()
  end)
  minimizedMoveWnd:EnableDrag(true)

  -- Back to the full meter
  local maximizeButton = minimizedWnd:CreateChildWidget("button", "maximizeButton", 0, true)
  maximizeButton:SetExtent(26, 28)
  maximizeButton:AddAnchor("TOPRIGHT", minimizedWnd, -12, 0)
  local maximizeButtonTexture = maximizeButton:CreateImageDrawable(TEXTURE_PATH.HUD, "background")
  maximizeButtonTexture:SetTexture(TEXTURE_PATH.HUD)
  maximizeButtonTexture:SetCoords(754, 94, 26, 28)
  maximizeButtonTexture:AddAnchor("TOPLEFT", maximizeButton, 0, 0)
  maximizeButtonTexture:SetExtent(26, 28)
  maximizeButton:SetHandler("OnClick", function()
    self:setMinimized(false)
    self.handlers.onMinimizedChanged(false)
  end)

  minimizedWnd.bg = minimizedWnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
  minimizedWnd.bg:SetTextureInfo("bg_quest")
  minimizedWnd.bg:SetColor(0, 0, 0, 0.5)
  minimizedWnd.bg:AddAnchor("TOPLEFT", minimizedWnd, 0, 0)
  minimizedWnd.bg:AddAnchor("BOTTOMRIGHT", minimizedWnd, 0, 0)

  minimizedWnd:Show(false)
  self.minimizedWnd = minimizedWnd
end

local function createResetPrompt(self)
  local window = api.Interface:CreateWindow("resetPromptWnd", "Dungeon Entry Detected", 0, 0)
  window:AddAnchor("CENTER", "UIParent", 0, 0)
  window:SetExtent(300, 150)

  local label = window:CreateChildWidget("textbox", "resetPromptLabel", 0, true)
  label:SetText("You are entering a new dungeon. \n \n  Would you like to reset your meter?")
  label:SetExtent(240, FONT_SIZE.LARGE * 2.5)
  label.style:SetAlign(ALIGN.CENTER)
  ApplyTextColor(label, FONT_COLOR.DEFAULT)
  label:AddAnchor("CENTER", window, 0, 0)

  local yesButton = window:CreateChildWidget("button", "resetPromptYesBtn", 0, true)
  api.Interface:ApplyButtonSkin(yesButton, BUTTON_BASIC.DEFAULT)
  yesButton:AddAnchor("BOTTOMLEFT", window, 10, -10)
  yesButton:SetText("Yes")
  yesButton:SetHandler("OnClick", function()
    window:Show(false)
    self.handlers.onReset()
  end)

  local noButton = window:CreateChildWidget("button", "resetPromptNoBtn", 0, true)
  api.Interface:ApplyButtonSkin(noButton, BUTTON_BASIC.DEFAULT)
  noButton:AddAnchor("BOTTOMRIGHT", window, -10, -10)
  noButton:SetText("No")
  noButton:SetHandler("OnClick", function()
    window:Show(false)
  end)

  window:Show(false)
  self.resetPromptWnd = window
end

local UI = {}

-- pages: stats.PAGES. handlers: functions called on user actions (see main.lua).
function ui.create(pages, handlers)
  -- setmetatable isn't available to addons, so copy the methods onto the instance
  local self = { pages = pages, handlers = handlers }
  for name, method in pairs(UI) do self[name] = method end
  createSettingsWindow(self)
  createDetailsWindow(self)
  createMeterWindow(self)
  createMinimizedWindow(self)
  createResetPrompt(self)
  applyDropdownColors(self)
  return self
end

-- Position, selected stat and minimized state from the saved settings
function UI:applySettings(settings)
  self.meterWnd:RemoveAllAnchors()
  if settings.posX == 0 and settings.posY == 0 then
    self.meterWnd:AddAnchor("RIGHT", "UIParent", 0, 0)
  else
    self.meterWnd:AddAnchor("TOPLEFT", "UIParent", settings.posX, settings.posY)
  end
  -- Before Select, which can fire the page handler
  self:setMinimized(settings.isMinimized == 1)
  self.filterButton:Select(settings.mainFilter)
  applyDropdownColors(self)
end

function UI:getPosition()
  return self.meterWnd:GetOffset()
end

function UI:setMinimized(minimized)
  if minimized then
    self.minimizedWnd:RemoveAllAnchors()
    self.minimizedWnd:AddAnchor("TOPRIGHT", self.meterWnd, 0, 0)
  else
    self.meterWnd:RemoveAllAnchors()
    self.meterWnd:AddAnchor("TOPLEFT", self.minimizedWnd, 0, 0)
  end
  self.meterWnd:Show(not minimized)
  self.minimizedWnd:Show(minimized)
end

function UI:isMinimized()
  return self.minimizedWnd:IsVisible()
end

-- Colour each filter in the settings dropdown: green when on, red when off
function UI:setFilterColors(filters)
  for i, filterName in ipairs(FILTER_NAMES) do
    self.unitFiltersButton.dropdownItemColor[i] = filters[filterName] == 1 and FONT_COLOR.GREEN or FONT_COLOR.RED
  end
end

-- Only touch the label when the text changes
function UI:setTimerText(text)
  if self.timerText ~= text then
    self.timerText = text
    self.timerLabel:SetText(text)
  end
end

local function setRowIcon(row, skillset)
  local coords = skillset and SKILLSET_ICON_COORDS[skillset]
  if coords == nil then
    row.skillsetIcon:SetVisible(false)
    return
  end
  row.skillsetIcon:SetCoords(coords[1], coords[2], ICON_SIZE, ICON_SIZE)
  row.skillsetIcon:SetVisible(true)
end

-- Draw the rows. entries[i] is { rank, name, amountText, barPercent, category, skillset }
-- for row i, or nil to leave the row empty.
function UI:drawRows(entries, firstRank)
  for i, row in ipairs(self.rows) do
    local entry = entries[i]
    local bar = row.bgStatusBar
    if entry ~= nil then
      local style = CATEGORY_STYLES[entry.category] or CATEGORY_STYLES.player
      local nameColor = style.name or DEFAULT_NAME_COLOR
      row.unitName = entry.name
      row:SetText(tostring(entry.rank))
      bar.statLabel:SetText(entry.name)
      bar.statLabel.style:SetColor(nameColor[1], nameColor[2], nameColor[3], nameColor[4])
      bar.statAmtLabel:SetText(entry.amountText)
      bar.statAmtLabel.style:SetColor(1, 1, 1, 1)
      bar:SetValue(entry.barPercent)
      bar:SetBarColor(rgb(style.bar))
      setRowIcon(row, entry.skillset)
    else
      row.unitName = nil
      row:SetText(tostring(firstRank + i - 1))
      bar.statLabel:SetText("")
      bar.statLabel.style:SetColor(1, 1, 1, 1)
      bar.statAmtLabel:SetText("")
      bar:SetValue(0)
      setRowIcon(row, nil)
    end
  end
end

function UI:rowCount()
  return #self.rows
end

function UI:showDetails(unitName, text)
  self.detailsWindow.playerLabel:SetText("Player: " .. unitName)
  self.detailsWindow.detailsTextEdit:SetText(text)
  self.detailsWindow:Show(true)
end

function UI:showResetPrompt()
  self.resetPromptWnd:Show(true)
end

-- Release every window and remove our entry from the shared Addon Options menu
function UI:free()
  for _, window in ipairs({ self.meterWnd, self.minimizedWnd, self.settingsWindow, self.detailsWindow, self.resetPromptWnd }) do
    api.Interface:Free(window)
  end
  michaelClientLib.removeAddon(ADDON_MENU_TITLE)
end

return ui
