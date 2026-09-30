-- Keep equal to ## Version in the .toc. The game reads the .toc only at client start,
-- so the tooltip uses this, which /reload picks up.
local VERSION = "0.4.6"
-- The addon's name as the player sees it: the tooltip title.
local ADDON_TITLE = "Performance Block"

-- Same thresholds and colors as the latency bar on the game menu button.
local LOW_LATENCY = 300
local MEDIUM_LATENCY = 600
local UPDATE_INTERVAL = 1

-- A group of one: an empty slot drawn like the game's own (background, slot art, frame, as in
-- ActionButtonTemplate), inside the outer group frame the bags bar and micro menu use.
local SLOT_SIZE = 45
local SLOT_BACKGROUND_ATLAS = "UI-HUD-ActionBar-IconFrame-Background"
local SLOT_ART_ATLAS = "ui-hud-actionbar-iconframe-slot"
local SLOT_FRAME_ATLAS = "ui-hud-actionbar-iconframe-bags"
local SLOT_FRAME_SIZE = 46
local GROUP_FRAME_ATLAS = "UI-HUD-ActionBar-Frame"
-- The group frame reaches past the slot as the bags bar's BorderArt reaches past its slots.
local GROUP_ART_LEFT, GROUP_ART_TOP, GROUP_ART_RIGHT, GROUP_ART_BOTTOM = 6, 6, 5, 5
-- Space between bar segments, as Edit Mode leaves between the micro menu and the bags.
local SEGMENT_GAP = 7
-- Room for the group between its neighbours. The micro menu's frame art reaches 8 px past its
-- buttons and the bags bar's 6 px before its first slot (their BorderArt anchors). The block's
-- group frame keeps ART_GAP clear of both; the bags move right to make that room.
local MICRO_MENU_ART_REACH = 8
local BAGS_ART_REACH = 6
local ART_GAP = 2
local BLOCK_OFFSET = MICRO_MENU_ART_REACH + ART_GAP + GROUP_ART_LEFT - SEGMENT_GAP
local BAGS_SHIFT = BLOCK_OFFSET + SLOT_SIZE + GROUP_ART_RIGHT + ART_GAP + BAGS_ART_REACH

-- The face: numbers only. FPS on top in white, world latency below in its color, both
-- centred, with a faint gold line between them at the slot's centre. World latency is the
-- one felt in combat; home latency and the labelled values are in the tooltip.
local NUMBER_FONT = "Fonts\\ARIALN.TTF" -- the game's number font (NumberFont_Outline_Med)
local NUMBER_SIZE = 16
-- There is no bold number font, so each number is drawn four times, one pixel apart in pairs:
-- two outlined copies underneath make one outline around both, and two plain copies on top
-- fill the strokes solid. Strokes are a pixel thicker and stay clean.
local NUMBER_OUTLINE = "OUTLINE"
local BOLD_OFFSET = 1
-- The number font sits low in its text box; raise the numbers so the room above and below
-- them is even and each sits as far from the line.
local NUMBER_RAISE = 1
-- The rows mirror each other above and below the line.
local ROW_OFFSET = 9.5
-- Widest a number may be (the slot less a 5 px margin each side); wider ones shrink to fit.
local ROW_WIDTH = 32
local DIVIDER_COLOR = { 0.86, 0.74, 0.46 }
local DIVIDER_HALF_WIDTH = 16
local DIVIDER_ALPHA = 1

local function SetNumberColor(number, r, g, b)
	for _, fill in ipairs(number.fills) do
		fill:SetTextColor(r, g, b)
	end
end

local function SetLatencyColor(number, latency)
	if latency > MEDIUM_LATENCY then
		SetNumberColor(number, 1, 0, 0)
	elseif latency > LOW_LATENCY then
		SetNumberColor(number, 1, 1, 0)
	else
		SetNumberColor(number, 0, 1, 0)
	end
end

-- Numbers and the line centre on the slot frame art, not the slot: like the bag buttons', the
-- 46 px frame is anchored at the top left of the 45 px slot, so its opening is centred half a
-- pixel right of and below the slot's own centre.
-- Each pair is centred as one: one copy half the offset left, the other half right.
local function CreateNumber(parent, centre, y)
	local number = { outlines = {}, fills = {} }
	for i, x in ipairs({ -BOLD_OFFSET / 2, BOLD_OFFSET / 2 }) do
		local outline = parent:CreateFontString(nil, "OVERLAY")
		outline:SetPoint("CENTER", centre, "CENTER", x, y + NUMBER_RAISE)
		outline:SetTextColor(0, 0, 0)
		number.outlines[i] = outline
		local fill = parent:CreateFontString(nil, "OVERLAY")
		fill:SetDrawLayer("OVERLAY", 1)
		fill:SetPoint("CENTER", centre, "CENTER", x, y + NUMBER_RAISE)
		number.fills[i] = fill
	end
	return number
end

local function SetNumberSize(number, size)
	for i = 1, 2 do
		number.outlines[i]:SetFont(NUMBER_FONT, size, NUMBER_OUTLINE)
		number.fills[i]:SetFont(NUMBER_FONT, size, "")
	end
end

local function SetNumber(number, value)
	SetNumberSize(number, NUMBER_SIZE)
	for i = 1, 2 do
		number.outlines[i]:SetText(value)
		number.fills[i]:SetText(value)
	end
	local width = number.outlines[1]:GetStringWidth() + BOLD_OFFSET
	if width > ROW_WIDTH then
		SetNumberSize(number, NUMBER_SIZE * ROW_WIDTH / width)
	end
end

local block = CreateFrame("Frame", nil, UIParent)
block:SetSize(SLOT_SIZE, SLOT_SIZE)
block:EnableMouse(true)
block:Hide()

local groupFrame = block:CreateTexture(nil, "BACKGROUND", nil, -3)
groupFrame:SetAtlas(GROUP_FRAME_ATLAS)
groupFrame:SetPoint("TOPLEFT", block, "TOPLEFT", -GROUP_ART_LEFT, GROUP_ART_TOP)
groupFrame:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", GROUP_ART_RIGHT, -GROUP_ART_BOTTOM)

local background = block:CreateTexture(nil, "BACKGROUND")
background:SetAtlas(SLOT_BACKGROUND_ATLAS)
background:SetAllPoints()

local slotArt = block:CreateTexture(nil, "BACKGROUND", nil, 1)
slotArt:SetAtlas(SLOT_ART_ATLAS)
slotArt:SetAllPoints()

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
dividerLeft:SetPoint("RIGHT", slotFrame, "CENTER")
dividerLeft:SetGradient("HORIZONTAL", dividerClear, dividerColor)
local dividerRight = block:CreateTexture(nil, "ARTWORK")
dividerRight:SetColorTexture(1, 1, 1, 1)
dividerRight:SetSize(DIVIDER_HALF_WIDTH, 1)
dividerRight:SetPoint("LEFT", slotFrame, "CENTER")
dividerRight:SetGradient("HORIZONTAL", dividerColor, dividerClear)

local fpsText = CreateNumber(block, slotFrame, ROW_OFFSET)
SetNumberColor(fpsText, 1, 1, 1)

local worldText = CreateNumber(block, slotFrame, -ROW_OFFSET)

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
		block:SetPoint(bagsAnchor[1], bagsAnchor[2], bagsAnchor[3], bagsAnchor[4] + BLOCK_OFFSET, bagsAnchor[5])
	else
		-- Bags placed on their own: sit just left of them without moving anything.
		block:SetPoint("BOTTOMRIGHT", BagsBar, "BOTTOMLEFT", -(BAGS_ART_REACH + ART_GAP + GROUP_ART_RIGHT), 0)
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
