-- Keep equal to ## Version in the .toc. The game reads the .toc only at client start,
-- so the tooltip uses this, which /reload picks up.
local VERSION = "0.4.0"
-- The addon's name as the player sees it: the tooltip title.
local ADDON_TITLE = "Performance Block"

-- Same thresholds and colors as the latency bar on the game menu button.
local LOW_LATENCY = 300
local MEDIUM_LATENCY = 600
local UPDATE_INTERVAL = 1

-- One bar segment: a bag slot inside the frame art the bags bar uses.
local SLOT_SIZE = 45
local SLOT_BACKGROUND_ATLAS = "UI-HUD-ActionBar-IconFrame-Background"
local SLOT_FRAME_ATLAS = "ui-hud-actionbar-iconframe-bags"
local SLOT_FRAME_SIZE = 46
local BAR_FRAME_ATLAS = "UI-HUD-ActionBar-Frame"
local BAR_FRAME_LEFT, BAR_FRAME_TOP, BAR_FRAME_RIGHT, BAR_FRAME_BOTTOM = -6, 6, 5, -5
-- Space between bar segments, as Edit Mode leaves between the micro menu and the bags.
local SEGMENT_GAP = 7
local BAGS_SHIFT = SLOT_SIZE + SEGMENT_GAP

-- The face: numbers only. FPS on top in white, world latency below in its color, both
-- centred, with a faint gold line between them at the slot's centre. World latency is the
-- one felt in combat; home latency and the labelled values are in the tooltip.
local NUMBER_FONT = "Fonts\\ARIALN.TTF" -- the game's number font (NumberFont_Outline_Med)
local NUMBER_SIZE = 18
-- The rows mirror each other above and below the line.
local ROW_OFFSET = 9.5
-- Widest a number may be (the slot less a 5 px margin each side); wider ones shrink to fit.
local ROW_WIDTH = 32
local DIVIDER_COLOR = { 0.72, 0.64, 0.42 }
local DIVIDER_HALF_WIDTH = 14
local DIVIDER_ALPHA = 0.75

local function SetLatencyColor(text, latency)
	if latency > MEDIUM_LATENCY then
		text:SetTextColor(1, 0, 0)
	elseif latency > LOW_LATENCY then
		text:SetTextColor(1, 1, 0)
	else
		text:SetTextColor(0, 1, 0)
	end
end

local function CreateNumber(parent, y)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetFont(NUMBER_FONT, NUMBER_SIZE, "OUTLINE")
	text:SetPoint("CENTER", parent, "CENTER", 0, y)
	return text
end

local function SetNumber(text, value)
	text:SetFont(NUMBER_FONT, NUMBER_SIZE, "OUTLINE")
	text:SetText(value)
	local width = text:GetStringWidth()
	if width > ROW_WIDTH then
		text:SetFont(NUMBER_FONT, NUMBER_SIZE * ROW_WIDTH / width, "OUTLINE")
	end
end

local block = CreateFrame("Frame", nil, UIParent)
block:SetSize(SLOT_SIZE, SLOT_SIZE)
block:EnableMouse(true)
block:Hide()

local barFrame = block:CreateTexture(nil, "BACKGROUND", nil, -3)
barFrame:SetAtlas(BAR_FRAME_ATLAS)
barFrame:SetPoint("TOPLEFT", block, "TOPLEFT", BAR_FRAME_LEFT, BAR_FRAME_TOP)
barFrame:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", BAR_FRAME_RIGHT, BAR_FRAME_BOTTOM)

local background = block:CreateTexture(nil, "BACKGROUND")
background:SetAtlas(SLOT_BACKGROUND_ATLAS)
background:SetAllPoints()

local slotFrame = block:CreateTexture(nil, "BORDER")
slotFrame:SetAtlas(SLOT_FRAME_ATLAS)
slotFrame:SetSize(SLOT_FRAME_SIZE, SLOT_FRAME_SIZE)
slotFrame:SetPoint("TOPLEFT")

-- A faint gold line between the rows, fading out at both ends.
local dividerColor = CreateColor(DIVIDER_COLOR[1], DIVIDER_COLOR[2], DIVIDER_COLOR[3], DIVIDER_ALPHA)
local dividerClear = CreateColor(DIVIDER_COLOR[1], DIVIDER_COLOR[2], DIVIDER_COLOR[3], 0)
local dividerLeft = block:CreateTexture(nil, "ARTWORK")
dividerLeft:SetColorTexture(1, 1, 1, 1)
dividerLeft:SetSize(DIVIDER_HALF_WIDTH, 1)
dividerLeft:SetPoint("RIGHT", block, "CENTER")
dividerLeft:SetGradient("HORIZONTAL", dividerClear, dividerColor)
local dividerRight = block:CreateTexture(nil, "ARTWORK")
dividerRight:SetColorTexture(1, 1, 1, 1)
dividerRight:SetSize(DIVIDER_HALF_WIDTH, 1)
dividerRight:SetPoint("LEFT", block, "CENTER")
dividerRight:SetGradient("HORIZONTAL", dividerColor, dividerClear)

local fpsText = CreateNumber(block, ROW_OFFSET)
fpsText:SetTextColor(1, 1, 1)

local worldText = CreateNumber(block, -ROW_OFFSET)

local function Update()
	local _, _, _, latencyWorld = GetNetStats()
	SetNumber(fpsText, math.floor(GetFramerate() + 0.5))
	SetNumber(worldText, latencyWorld)
	SetLatencyColor(worldText, latencyWorld)
end

-- Making room on the bar. When Edit Mode attaches the bags bar by its left side (after the
-- micro menu), the bags bar moves one segment right while the addon runs, and whatever Edit
-- Mode attached to it (the right gryphon) follows. The block takes the freed spot.
-- Nothing is saved: the layout is never written, Edit Mode anchors the bags again on every
-- layout change, and the shift is taken off while Edit Mode is open so it only ever sees and
-- saves the layout's own positions. Without the addon the bar is exactly as the layout says.
local bagsAnchor -- the bags bar's anchor as Edit Mode set it
local movingBags = false
local editModeOpen = false
local layoutPending = false

local function RememberBagsAnchor()
	local point, relativeTo, relativePoint, x, y = BagsBar:GetPoint(1)
	if point then
		bagsAnchor = { point, relativeTo or BagsBar:GetParent(), relativePoint, x, y }
	end
end

local function SetBagsOffset(extraX)
	movingBags = true
	BagsBar:ClearAllPoints()
	BagsBar:SetPoint(bagsAnchor[1], bagsAnchor[2], bagsAnchor[3], bagsAnchor[4] + extraX, bagsAnchor[5])
	movingBags = false
end

local function Layout()
	if not bagsAnchor then
		return
	end
	-- The bar can be protected in combat; finish when combat ends.
	if InCombatLockdown() and BagsBar:IsProtected() then
		layoutPending = true
		return
	end
	layoutPending = false

	if editModeOpen then
		SetBagsOffset(0)
		block:Hide()
		return
	end

	block:ClearAllPoints()
	if bagsAnchor[1]:find("LEFT") then
		SetBagsOffset(BAGS_SHIFT)
		block:SetPoint(bagsAnchor[1], bagsAnchor[2], bagsAnchor[3], bagsAnchor[4], bagsAnchor[5])
	else
		-- Bags placed on their own: sit just left of them without moving anything.
		block:SetPoint("BOTTOMRIGHT", BagsBar, "BOTTOMLEFT", -SEGMENT_GAP, 0)
	end
	block:SetScale(BagsBar:GetScale())
	block:SetFrameStrata(BagsBar:GetFrameStrata())
	block:SetFrameLevel(BagsBar:GetFrameLevel())
	block:Show()
end

local function OnBagsBarSetPoint()
	if movingBags then
		return
	end
	RememberBagsAnchor()
	Layout()
end

local function OnEditModeEnter()
	editModeOpen = true
	Layout()
end

local function OnEditModeExit()
	editModeOpen = false
	Layout()
end

-- The same lines as the game menu button's tooltip, in the game's own words.
block:SetScript("OnEnter", function(self)
	local _, _, latencyHome, latencyWorld = GetNetStats()
	GameTooltip_SetDefaultAnchor(GameTooltip, self)
	GameTooltip_SetTitle(GameTooltip, ADDON_TITLE)
	GameTooltip:AddLine(format(MAINMENUBAR_LATENCY_LABEL, latencyHome, latencyWorld), 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format(MAINMENUBAR_FPS_LABEL, GetFramerate()), 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("v" .. VERSION, 0.5, 0.5, 0.5)
	GameTooltip:Show()
end)
block:SetScript("OnLeave", GameTooltip_Hide)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if layoutPending then
			Layout()
		end
		return
	end

	if not BagsBar then
		return
	end
	hooksecurefunc(BagsBar, "SetPoint", OnBagsBarSetPoint)
	EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, block)
	EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, block)
	editModeOpen = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() or false
	RememberBagsAnchor()
	Layout()
	Update()
	C_Timer.NewTicker(UPDATE_INTERVAL, Update)
end)
