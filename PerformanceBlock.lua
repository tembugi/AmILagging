-- Keep equal to ## Version in the .toc. The game reads the .toc only at client start,
-- so the tooltip uses this, which /reload picks up.
local VERSION = "0.7.1"
-- The addon's name as the player sees it: the tooltip title.
local ADDON_TITLE = "Performance Block"

-- Same thresholds and colors as the latency bar on the game menu button.
local LOW_LATENCY = 300
local MEDIUM_LATENCY = 600
local UPDATE_INTERVAL = 1

-- The block is a slot of the bags bar, dressed like the slots beside it. Its art and size are
-- read from the game's own frames at login (see MeasureArt); these are only the values
-- Blizzard's XML sets today, used if a frame is missing.
local art = {
	slotSize = 45,
	slotBackground = "UI-HUD-ActionBar-IconFrame-Background",
	slotArt = "ui-hud-actionbar-iconframe-slot",
	slotFrame = "UI-HUD-ActionBar-IconFrame",
	slotFrameSize = 46,
}

-- The face: numbers only. FPS on top in white, world latency below in its color, both
-- centred, with a faint gold line between them at the slot's centre. World latency is the
-- one felt in combat; home latency and the labelled values are in the tooltip.
-- The numbers use the game's own heavy number font: the one behind NumberFont_Outline_Huge
-- (Skurri for Latin alphabets, whatever Blizzard sets for other languages), just smaller.
-- The standard game font stands in if that font is missing.
local NUMBER_FONT_OBJECT = "NumberFont_Outline_Huge"
local NUMBER_SIZE = 15
local NUMBER_OUTLINE = "OUTLINE"
-- This font's figures are old style: 0, 1 and 2 stand at x-height, 6 and 8 rise above it,
-- 3, 4, 5, 7 and 9 drop below the baseline. Measured from Skurri in game, as parts of the
-- font size: how far figures rise above and drop below the baseline, and where the baseline
-- sits in the text box. Each number is placed so the band from its highest to its lowest
-- possible figure sits in the middle of its half of the slot, as far from the line as from
-- the border, whatever digits it shows. (The fallback font's figures sit a little off.)
local FIGURE_RISE = 0.67
local FIGURE_DROP = 0.19
local BOX_ASCENT = 0.74
local BOX_DESCENT = 0.26
-- The gray inner edge of the slot art, inside the slot's own size.
local SLOT_EDGE = 3.5
local LINE_THICKNESS = 1
-- Room kept free on each side of a number; wider numbers (four-digit latency) shrink to fit.
local NUMBER_MARGIN = 6.5
local DIVIDER_COLOR = { 0.86, 0.74, 0.46 }
local DIVIDER_HALF_WIDTH = 16
local DIVIDER_ALPHA = 1

local numberFontObject = _G[NUMBER_FONT_OBJECT]
local numberFont = numberFontObject and numberFontObject:GetFont() or STANDARD_TEXT_FONT

local function SetLatencyColor(text, latency)
	if latency > MEDIUM_LATENCY then
		text:SetTextColor(1, 0, 0)
	elseif latency > LOW_LATENCY then
		text:SetTextColor(1, 1, 0)
	else
		text:SetTextColor(0, 1, 0)
	end
end

-- Numbers and the line centre on the slot frame art, not the slot: like the bag buttons', the
-- frame art is anchored at the top left of the slot and is a pixel larger, so its opening is
-- centred half a pixel right of and below the slot's own centre. The rows mirror each other.
local function PlaceNumber(text, size)
	local half = art.slotSize / 2 - SLOT_EDGE - LINE_THICKNESS / 2
	local gap = (half - (FIGURE_RISE + FIGURE_DROP) * size) / 2
	local fromCentre = LINE_THICKNESS / 2 + gap
	text:ClearAllPoints()
	if text.aboveLine then
		text:SetPoint("BOTTOM", text.centre, "CENTER", 0, fromCentre + (FIGURE_DROP - BOX_DESCENT) * size)
	else
		text:SetPoint("TOP", text.centre, "CENTER", 0, -fromCentre - (FIGURE_RISE - BOX_ASCENT) * size)
	end
end

local function CreateNumber(parent, centre, aboveLine)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text.centre = centre
	text.aboveLine = aboveLine
	return text
end

local function SetNumberSize(text, size)
	if not text:SetFont(numberFont, size, NUMBER_OUTLINE) then
		numberFont = STANDARD_TEXT_FONT
		text:SetFont(numberFont, size, NUMBER_OUTLINE)
	end
end

local function SetNumber(text, value)
	SetNumberSize(text, NUMBER_SIZE)
	text:SetText(value)
	local maxWidth = art.slotSize - 2 * NUMBER_MARGIN
	local width = text:GetStringWidth()
	local size = NUMBER_SIZE
	if width > maxWidth then
		size = NUMBER_SIZE * maxWidth / width
		SetNumberSize(text, size)
	end
	if size ~= text.placedSize then
		text.placedSize = size
		PlaceNumber(text, size)
	end
end

local block = CreateFrame("Frame", nil, UIParent)
block:EnableMouse(true)
block:Hide()

local background = block:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
local slotArt = block:CreateTexture(nil, "BACKGROUND", nil, 1)
slotArt:SetAllPoints()
local slotFrame = block:CreateTexture(nil, "BORDER")
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

local fpsText = CreateNumber(block, slotFrame, true)
fpsText:SetTextColor(1, 1, 1)

local worldText = CreateNumber(block, slotFrame, false)

local function Update()
	local _, _, _, latencyWorld = GetNetStats()
	SetNumber(fpsText, math.floor(GetFramerate() + 0.5))
	SetNumber(worldText, latencyWorld)
	SetLatencyColor(worldText, latencyWorld)
end

local function AtlasOf(texture, fallback)
	return texture and texture:GetAtlas() or fallback
end

-- Read the art from the frames the block stands among: the size and plain gray frame art of
-- the reagent bag slot (regular bag slots wear a gold frame) and an action button's empty-slot
-- layers.
local function MeasureArt()
	local bagSlot = CharacterReagentBag0Slot
	if bagSlot then
		art.slotSize = bagSlot:GetWidth()
		local normal = bagSlot:GetNormalTexture()
		if normal then
			art.slotFrame = AtlasOf(normal, art.slotFrame)
			art.slotFrameSize = normal:GetWidth()
		end
	end
	local actionButton = ActionButton1
	if actionButton then
		art.slotBackground = AtlasOf(actionButton.SlotBackground, art.slotBackground)
		art.slotArt = AtlasOf(actionButton.SlotArt, art.slotArt)
	end
end

local function DressBlock()
	block:SetSize(art.slotSize, art.slotSize)
	fpsText.placedSize = nil
	worldText.placedSize = nil
	background:SetAtlas(art.slotBackground)
	slotArt:SetAtlas(art.slotArt)
	slotFrame:SetAtlas(art.slotFrame)
	slotFrame:SetSize(art.slotFrameSize, art.slotFrameSize)
end

-- Making room on the bar. The block joins the bags bar the way the keyring does: it goes in the
-- bags bar's own list of buttons, so the bags bar places it, spaces it and draws the divider
-- beside it like its other buttons, and widens itself to hold it. Buttons stand in the order
-- they joined, from the backpack outwards; the block joins last, so it is the first slot of
-- the bar: right of the micro menu, left of the keyring.
-- Edit Mode puts the row at a fixed spot, so a wider bags bar would make the row lean right.
-- When the bags hang off the micro menu, the whole row moves left by half the growth, so it
-- grows evenly on both sides and stays centred. What "the whole row" hangs off depends on the
-- layout: in a saved layout the action bar hangs off the micro menu, but Edit Mode places bars
-- in their default position on the screen itself. So the addon follows the anchors of the
-- action bar and of the micro menu up to the frames that hang off the screen, and moves each
-- of those once.
-- Nothing is saved: the layout is never written, Edit Mode anchors these frames again on
-- every layout change, and while Edit Mode is open the block leaves the bags bar and the moves
-- are taken off, so Edit Mode only ever sees and saves the layout's own positions. Without the
-- addon the bar is exactly as the layout says.
local editModeOpen = false
local layoutPending = false

-- A Blizzard frame the addon nudges sideways: it keeps the anchor Edit Mode last gave it and
-- sets it again with an extra x offset. Edit Mode replaces SetPoint and ClearAllPoints on its
-- frames with versions that also update its snapping and flag an anchor change; the moves use
-- the plain originals it keeps (SetPointBase, ClearAllPointsBase), so they change the position
-- and nothing else.
local function CreateMover(frame)
	local mover = { frame = frame, moving = false, applied = 0 }
	local setPoint = frame.SetPointBase or frame.SetPoint
	local clearAllPoints = frame.ClearAllPointsBase or frame.ClearAllPoints

	function mover:Remember()
		local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
		if point then
			self.anchor = { point, relativeTo or frame:GetParent(), relativePoint, x, y }
		end
		-- Blizzard just placed the frame, so it stands where Blizzard wants it.
		self.applied = 0
	end

	-- Only touches the frame when its offset has to change, so frames that stay where Blizzard
	-- put them (protected action bars among them) are left alone.
	function mover:SetExtraX(extraX)
		if not self.anchor or extraX == self.applied then
			return
		end
		self.applied = extraX
		self.moving = true
		clearAllPoints(frame)
		setPoint(frame, self.anchor[1], self.anchor[2], self.anchor[3], self.anchor[4] + extraX, self.anchor[5])
		self.moving = false
	end

	return mover
end

local inBagsBar = false
local rowMovers = {} -- frame -> mover, for the row's roots and stacked bars moved so far
local OnMovedByBlizzard

-- The frame at the top of a frame's anchor chain: the one that hangs off the screen itself.
local function RootOf(frame)
	local current = frame
	for _ = 1, 10 do
		local _, relativeTo = current:GetPoint(1)
		if not relativeTo or relativeTo == UIParent or not relativeTo.GetPoint then
			return current
		end
		current = relativeTo
	end
	return current
end

local function RowMoverFor(frame)
	local mover = rowMovers[frame]
	if not mover then
		mover = CreateMover(frame)
		mover:Remember()
		rowMovers[frame] = mover
		hooksecurefunc(frame, "SetPoint", function() OnMovedByBlizzard(mover) end)
	end
	return mover
end

-- The row's roots: where the action bar's chain and the micro menu's chain start.
local function RowRoots()
	local roots = {}
	for _, frame in ipairs({ MainActionBar, MicroMenuContainer }) do
		if frame then
			roots[RootOf(frame)] = true
		end
	end
	return roots
end

-- The XP bars stack on the action bar by their left edge (the Camelot layout anchors the bars
-- above the row to the main action bar), so they line up with the row's left end and stop
-- short of the block. They stretch by the row's growth to reach its right end again, and
-- Blizzard's own methods, the ones its Size setting uses, fit the bars and tick marks inside.
local xpBars = {} -- container -> { base = Blizzard's width, extra = added width, setting }

local function FitXPBar(container, state)
	state.setting = true
	container:SetWidth(state.base + state.extra)
	container:ResizeContainerBars()
	container:UpdateDividers(container:GetExpectedSegments())
	state.setting = false
end

local function StretchXPBars(rowGrowth)
	for _, container in ipairs({ MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer }) do
		if container and container.ResizeContainerBars and container.UpdateDividers then
			local state = xpBars[container]
			if not state then
				state = { base = container:GetWidth(), extra = 0 }
				xpBars[container] = state
				local function OnResizedByBlizzard(_, width)
					if not state.setting then
						state.base = width
						FitXPBar(container, state)
					end
				end
				hooksecurefunc(container, "SetSize", OnResizedByBlizzard)
				hooksecurefunc(container, "SetWidth", OnResizedByBlizzard)
			end
			-- The growth is in UIParent units; the container may sit in a scaled parent.
			state.extra = rowGrowth * UIParent:GetEffectiveScale() / container:GetEffectiveScale()
			FitXPBar(container, state)
		end
	end
end

-- The action bars stacked above the row (Camelot anchors them to the main action bar by their
-- left edge). They are fixed buttons and cannot stretch like the XP bars, so they move right by
-- half the row's growth to stay centred over it.
local STACKED_BAR_NAMES = { "MultiBarBottomLeft", "MultiBarBottomRight", "StanceBar", "PetActionBar", "PossessActionBar" }

-- Watch every bar that can stack above the row from the start: Edit Mode first parks them at
-- the screen's top left and moves them onto the action bar a moment later, so their anchor at
-- one moment says little.
local function WatchStackedBars()
	for _, name in ipairs(STACKED_BAR_NAMES) do
		local bar = _G[name]
		if bar and bar.GetPoint then
			RowMoverFor(bar)
		end
	end
end

local function StackedBars()
	local bars = {}
	for _, name in ipairs(STACKED_BAR_NAMES) do
		local bar = _G[name]
		if bar and bar.GetPoint then
			local _, relativeTo = bar:GetPoint(1)
			if relativeTo == MainActionBar then
				bars[bar] = true
			end
		end
	end
	return bars
end

-- Put the block in the bags bar's list of buttons or take it out, and let the bags bar lay
-- itself out again. Taking it out leaves the list as Blizzard made it.
local function JoinBagsBar(join)
	if join == inBagsBar then
		return
	end
	inBagsBar = join
	if join then
		MainMenuBarBagManager:RegisterBagButton(block)
	else
		local buttons = MainMenuBarBagManager.allBagButtons
		for i = #buttons, 1, -1 do
			if buttons[i] == block then
				table.remove(buttons, i)
			end
		end
	end
	block:SetShown(join)
	BagsBar:Layout()
end

local function AnyProtected()
	if BagsBar:IsProtected() then
		return true
	end
	for frame in pairs(rowMovers) do
		if frame:IsProtected() then
			return true
		end
	end
	for container in pairs(xpBars) do
		if container:IsProtected() then
			return true
		end
	end
	return false
end

local function ResetRow()
	for _, mover in pairs(rowMovers) do
		mover:SetExtraX(0)
	end
end

local function Layout()
	-- These frames can be protected in combat; finish when combat ends.
	if InCombatLockdown() and AnyProtected() then
		layoutPending = true
		return
	end
	layoutPending = false

	JoinBagsBar(not editModeOpen)

	-- How much wider the row is, in UIParent units: the block and the bags bar's spacing, at the
	-- bags bar's scale. Only a bags bar that runs sideways from the micro menu widens the row.
	local rowGrowth = 0
	local point, relativeTo = BagsBar:GetPoint(1)
	if inBagsBar and BagsBar:IsHorizontal() and relativeTo == MicroMenuContainer and point and point:find("LEFT") then
		rowGrowth = (block:GetWidth() + (BagsBar.bagPadding or 0)) * BagsBar:GetScale()
	end

	-- Grow evenly: each root of the row moves left by half, once, and the action bars stacked
	-- above it move right by half to stay centred over it. Frames no longer in either set go
	-- back to where Blizzard put them.
	local shifts = {} -- frame -> shift in UIParent units
	if rowGrowth ~= 0 then
		for frame in pairs(RowRoots()) do
			shifts[frame] = -rowGrowth / 2
		end
		for bar in pairs(StackedBars()) do
			shifts[bar] = rowGrowth / 2
		end
	end
	for frame in pairs(shifts) do
		RowMoverFor(frame)
	end
	for frame, mover in pairs(rowMovers) do
		mover:SetExtraX((shifts[frame] or 0) / frame:GetScale())
	end
	StretchXPBars(rowGrowth)
end

function OnMovedByBlizzard(mover)
	if mover.moving then
		return
	end
	mover:Remember()
	Layout()
end

local function OnEditModeEnter()
	editModeOpen = true
	Layout()
end

local function OnEditModeExit()
	editModeOpen = false
	MeasureArt()
	DressBlock()
	Layout()
end

-- The bags bar asks its buttons to follow its orientation and expand state; the block is
-- square and always shown, like the keyring.
function block:UpdateOrientation()
end

function block:SetBarExpanded()
end

-- The same lines as the game menu button's tooltip, in the game's own words.
block:SetScript("OnEnter", function(self)
	local _, _, latencyHome, latencyWorld = GetNetStats()
	GameTooltip_SetDefaultAnchor(GameTooltip, self)
	GameTooltip_SetTitle(GameTooltip, ADDON_TITLE)
	GameTooltip:AddLine(format(MAINMENUBAR_FPS_LABEL, GetFramerate()), 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format(MAINMENUBAR_LATENCY_LABEL, latencyHome, latencyWorld), 1, 1, 1)
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

	if not (BagsBar and BagsBar.Layout and MicroMenuContainer and MainMenuBarBagManager
		and MainMenuBarBagManager.RegisterBagButton and MainMenuBarBagManager.allBagButtons) then
		return
	end
	-- A child of the bags bar, so it takes the bar's scale and hides with it (in vehicles).
	block:SetParent(BagsBar)
	-- Whether the bags hang off the micro menu decides whether the row grows.
	hooksecurefunc(BagsBar, "SetPoint", function() Layout() end)
	EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, block)
	EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, block)
	editModeOpen = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() or false

	MeasureArt()
	DressBlock()
	WatchStackedBars()
	Layout()
	Update()
	C_Timer.NewTicker(UPDATE_INTERVAL, Update)
end)
