-- Keep equal to ## Version in the .toc. The game reads the .toc only at client start,
-- so the tooltip uses this, which /reload picks up.
local VERSION = "0.1.0"
-- The addon's name as the player sees it: the tooltip title.
local ADDON_TITLE = "Performance Block"

-- Same thresholds and colors as the latency bar on the game menu button.
local LOW_LATENCY = 300
local MEDIUM_LATENCY = 600
local UPDATE_INTERVAL = 1

-- A bag slot: the size and art of the bag buttons on the bar.
local SLOT_SIZE = 45
local SLOT_BACKGROUND_ATLAS = "UI-HUD-ActionBar-IconFrame-Background"
local SLOT_FRAME_ATLAS = "ui-hud-actionbar-iconframe-bags"
local SLOT_FRAME_SIZE = 46
local GAP_AFTER_MICRO_MENU = 10

-- The game's number font (NumberFont_Outline_Med uses the same file).
local NUMBER_FONT = "Fonts\\ARIALN.TTF"
local FPS_SIZE = 11.5
local LATENCY_SIZE = 7.5
local CAPTION_SIZE = 4.1
-- Font strings have no letter spacing, so captions are laid out one letter at a time.
local CAPTION_LETTER_SPACING = 0.5
local CAPTION_COLOR = { 0.72, 0.64, 0.42 }

local TOP_MARGIN = 5
local CAPTION_GAP = 0.8
local ROW_GAP = 2.8
local DIVIDER_WIDTH = 18
local DIVIDER_ALPHA = 0.5
local LATENCY_COLUMN_OFFSET = 9

local function CreateCaption(parent, label)
	local caption = CreateFrame("Frame", nil, parent)
	local x, height = 0, 0
	for i = 1, #label do
		local letter = caption:CreateFontString(nil, "OVERLAY")
		letter:SetFont(NUMBER_FONT, CAPTION_SIZE, "")
		letter:SetShadowColor(0, 0, 0, 1)
		letter:SetShadowOffset(0.5, -0.5)
		letter:SetTextColor(CAPTION_COLOR[1], CAPTION_COLOR[2], CAPTION_COLOR[3])
		letter:SetText(label:sub(i, i))
		letter:SetPoint("LEFT", caption, "LEFT", x, 0)
		x = x + letter:GetStringWidth() + CAPTION_LETTER_SPACING
		height = math.max(height, letter:GetStringHeight())
	end
	caption:SetSize(math.max(1, x - CAPTION_LETTER_SPACING), math.max(1, height))
	return caption
end

local function SetLatencyColor(text, latency)
	if latency > MEDIUM_LATENCY then
		text:SetTextColor(1, 0, 0)
	elseif latency > LOW_LATENCY then
		text:SetTextColor(1, 1, 0)
	else
		text:SetTextColor(0, 1, 0)
	end
end

local block = CreateFrame("Frame", nil, UIParent)
block:SetSize(SLOT_SIZE, SLOT_SIZE)
block:SetFrameStrata("MEDIUM")
block:EnableMouse(true)

local background = block:CreateTexture(nil, "BACKGROUND")
background:SetAtlas(SLOT_BACKGROUND_ATLAS)
background:SetAllPoints()

local slotFrame = block:CreateTexture(nil, "BORDER")
slotFrame:SetAtlas(SLOT_FRAME_ATLAS)
slotFrame:SetSize(SLOT_FRAME_SIZE, SLOT_FRAME_SIZE)
slotFrame:SetPoint("TOPLEFT")

local fpsText = block:CreateFontString(nil, "OVERLAY")
fpsText:SetFont(NUMBER_FONT, FPS_SIZE, "OUTLINE")
fpsText:SetTextColor(1, 1, 1)
fpsText:SetPoint("TOP", block, "TOP", 0, -TOP_MARGIN)

local fpsCaption = CreateCaption(block, "FPS")
fpsCaption:SetPoint("TOP", fpsText, "BOTTOM", 0, -CAPTION_GAP)

local divider = block:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(CAPTION_COLOR[1], CAPTION_COLOR[2], CAPTION_COLOR[3], DIVIDER_ALPHA)
divider:SetSize(DIVIDER_WIDTH, 1)
divider:SetPoint("TOP", fpsCaption, "BOTTOM", 0, -ROW_GAP)

local homeText = block:CreateFontString(nil, "OVERLAY")
homeText:SetFont(NUMBER_FONT, LATENCY_SIZE, "OUTLINE")
homeText:SetPoint("TOP", divider, "BOTTOM", -LATENCY_COLUMN_OFFSET, -ROW_GAP)

local homeCaption = CreateCaption(block, "Home")
homeCaption:SetPoint("TOP", homeText, "BOTTOM", 0, -CAPTION_GAP)

local worldText = block:CreateFontString(nil, "OVERLAY")
worldText:SetFont(NUMBER_FONT, LATENCY_SIZE, "OUTLINE")
worldText:SetPoint("TOP", divider, "BOTTOM", LATENCY_COLUMN_OFFSET, -ROW_GAP)

local worldCaption = CreateCaption(block, "World")
worldCaption:SetPoint("TOP", worldText, "BOTTOM", 0, -CAPTION_GAP)

local function Update()
	local _, _, latencyHome, latencyWorld = GetNetStats()
	fpsText:SetText(math.floor(GetFramerate() + 0.5))
	homeText:SetText(latencyHome)
	worldText:SetText(latencyWorld)
	SetLatencyColor(homeText, latencyHome)
	SetLatencyColor(worldText, latencyWorld)
end

-- Right of the micro menu, where the red help button ends it.
local function Place()
	block:ClearAllPoints()
	if MicroMenu then
		block:SetPoint("LEFT", MicroMenu, "RIGHT", GAP_AFTER_MICRO_MENU, 0)
		block:SetFrameLevel(MicroMenu:GetFrameLevel() + 1)
	else
		block:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -8, 8)
	end
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
events:SetScript("OnEvent", function()
	Place()
	Update()
	C_Timer.NewTicker(UPDATE_INTERVAL, Update)
end)
