local statsMeterWnd = api.Interface:CreateEmptyWindow("statsMeterWnd", "UIParent")
statsMeterWnd:AddAnchor("RIGHT", "UIParent", 0, 0)
statsMeterWnd:SetExtent(280, 280)
--statsMeterWnd:SetTitle("dps meter")
--statsMeterWnd:SetCloseOnEscape(false)
--statsMeterWnd.titleBar.closeButton:Show(false)
statsMeterWnd.child = {}
local offsetX = 30
local offsetY = 70
local labelHeight = 20
for k = 1, 10 do
  -- Overall child widget and ranking # text
  local id = tostring(k) .. "."
  statsMeterWnd.child[k] = api.Interface:CreateWidget("label", id, statsMeterWnd)
  local child = statsMeterWnd.child[k]
  child:AddAnchor("TOPLEFT", 12, offsetY)
  child:SetExtent(255, labelHeight)
  child:SetText(id)
  child.style:SetColor(1, 1, 1, 1)
  child.style:SetAlign(ALIGN.LEFT)

  -- Status bar and background
  local statusBar = api.Interface:CreateStatusBar("bgStatusBar", child, "item_evolving_material")
  child.bgStatusBar = statusBar
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
  --statLabel:SetText("statLabel" .. tostring(k))
  statLabel.style:SetShadow(true)
  statLabel.style:SetAlign(ALIGN.LEFT)
  ApplyTextColor(statLabel, FONT_COLOR.WHITE)
  statLabel:AddAnchor("LEFT", 5, 0)
  local statAmtLabel = child.bgStatusBar:CreateChildWidget("label", "statAmtLabel", 0, true)
  --statAmtLabel:SetText("statAmtLabel" .. tostring(k))
  statAmtLabel.style:SetShadow(true)
  statAmtLabel.style:SetAlign(ALIGN.RIGHT)
  ApplyTextColor(statAmtLabel, FONT_COLOR.WHITE)
  statAmtLabel:AddAnchor("RIGHT", -5, 0)
  
  offsetY = offsetY + labelHeight
end
--local nextButton = statsMeterWnd:CreateChildWidget("button", "nextButton", 0, true)
--nextButton:AddAnchor("TOPRIGHT", statsMeterWnd, "TOPRIGHT", -30, 40)
--nextButton:SetText("\226\150\183")
--nextButton:Show(true)
--ApplyButtonSkin(nextButton, BUTTON_BASIC.DEFAULT)

-- Timer clock icon and label
local timerLabel = statsMeterWnd:CreateChildWidget("label", "timerLabel", 0, true)
timerLabel.style:SetShadow(true)
timerLabel.style:SetAlign(ALIGN.RIGHT)
timerLabel:AddAnchor("TOPRIGHT", statsMeterWnd, "TOPRIGHT", -30, 55)
timerLabel:SetText(tostring(api.Time:GetUiMsec()))
timerLabel.style:SetFontSize(FONT_SIZE.LARGE)
--local clockIcon = timerLabel:CreateChildWidget("emptywidget", "timerClockIcon", 0, true)  
--clockIcon:AddAnchor("LEFT", clockIcon, "LEFT", -30, -5)
--local clockIconTexture = clockIcon:CreateImageDrawable(TEXTURE_PATH.EXPEDITION_RECRUIT, "background")
--local textureCoords = { GetTextureInfo(TEXTURE_PATH.EXPEDITION_RECRUIT, "clock_blue"):GetCoords() }
--clockIconTexture:SetCoords(textureCoords[1], textureCoords[2], textureCoords[3], textureCoords[4])
--clockIconTexture:AddAnchor("TOPLEFT", clockIcon, 0, 0)
--clockIconTexture:AddAnchor("BOTTOMRIGHT", clockIcon, 0, 0)
--clockIcon:SetExtent(textureCoord[3], textureCoord[4])


local refreshButton = statsMeterWnd:CreateChildWidget("button", "refreshButton", 0, true)
refreshButton:SetExtent(55, 26)
refreshButton:AddAnchor("TOPLEFT", statsMeterWnd, "TOPLEFT", 30, 40)
--refreshButton:SetText("\226\151\129")
refreshButton:Show(true)
ApplyButtonSkin(refreshButton, BUTTON_BASIC.RESET)


--- Add dragable bar across top
local moveWnd = statsMeterWnd:CreateChildWidget("label", "moveWnd", 0, true)
moveWnd:AddAnchor("TOPLEFT", statsMeterWnd, 12, 0)
moveWnd:AddAnchor("TOPRIGHT", statsMeterWnd, 0, 0)
moveWnd:SetHeight(30)
moveWnd.style:SetFontSize(FONT_SIZE.XLARGE)
moveWnd.style:SetAlign(ALIGN.LEFT)
moveWnd:SetText("")
ApplyTextColor(moveWnd, FONT_COLOR.WHITE)
-- moveWnd:SetWidth(200)
-- Drag handlers for dragable bar
function moveWnd:OnDragStart(arg)
  if arg == "LeftButton" and api.Input:IsShiftKeyDown() then
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
moveWnd:RegisterForDrag("LeftButton")
-- Add stats category selection
local filters = {
  "Total Damage",
  "Damage Per Second",
  "Total Healing",
  "Healing Per Second",
  "Damage Taken"
}

-- Dropdown Menu (Also used as title)
local filterButton = api.Interface:CreateComboBox(moveWnd)
filterButton:AddAnchor("TOPLEFT", moveWnd, 0, 3)
filterButton:SetExtent(200, 30)
filterButton.dropdownItem = filters
filterButton:Select(1)
filterButton.style:SetFontSize(FONT_SIZE.XLARGE)
ApplyTextColor(filterButton, FONT_COLOR.WHITE)
filterButton.bg:SetColor(0,0,0,0)
moveWnd.filterButton = filterButton


-- Background Styling
statsMeterWnd.bg = statsMeterWnd:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
statsMeterWnd.bg:SetTextureInfo("bg_quest")
statsMeterWnd.bg:SetColor(0, 0, 0, 0.5)
statsMeterWnd.bg:AddAnchor("TOPLEFT", statsMeterWnd, 0, 0)
statsMeterWnd.bg:AddAnchor("BOTTOMRIGHT", statsMeterWnd, 0, 0)

-- Show the damn thing.
statsMeterWnd:Show(true)

return statsMeterWnd