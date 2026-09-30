-- Keep equal to ## Version in the .toc. The game reads the .toc only at client start,
-- so the tooltip uses this, which /reload picks up.
local VERSION = "0.5.4"
-- The addon's name as the player sees it: the tooltip title.
local ADDON_TITLE = "Performance Block"

-- Same thresholds and colors as the latency bar on the game menu button.
local LOW_LATENCY = 300
local MEDIUM_LATENCY = 600
local UPDATE_INTERVAL = 1

-- The block is a group of one on the bar, dressed and spaced like its neighbours. Its art and
-- sizes are read from the game's own frames at login (see MeasureArt); these are only the
-- values Blizzard's XML sets today, used if a frame is missing.
local art = {
	slotSize = 45,
	slotBackground = "UI-HUD-ActionBar-IconFrame-Background",
	slotArt = "ui-hud-actionbar-iconframe-slot",
	slotFrame = "UI-HUD-ActionBar-IconFrame",
	slotFrameSize = 46,
	groupFrame = "UI-HUD-ActionBar-Frame",
	groupReach = { left = 6, top = 6, right = 5, bottom = 5 },
	microMenuReachRight = 8,
}

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
-- Room kept free on each side of a number; wider numbers (four-digit latency) shrink to fit.
local NUMBER_MARGIN = 6.5
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
-- frame art is anchored at the top left of the slot and is a pixel larger, so its opening is
-- centred half a pixel right of and below the slot's own centre.
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
	local maxWidth = art.slotSize - 2 * NUMBER_MARGIN
	local width = number.outlines[1]:GetStringWidth() + BOLD_OFFSET
	if width > maxWidth then
		SetNumberSize(number, NUMBER_SIZE * maxWidth / width)
	end
end

local block = CreateFrame("Frame", nil, UIParent)
block:EnableMouse(true)
block:Hide()

local groupFrame = block:CreateTexture(nil, "BACKGROUND", nil, -3)
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

local fpsText = CreateNumber(block, slotFrame, ROW_OFFSET)
SetNumberColor(fpsText, 1, 1, 1)

local worldText = CreateNumber(block, slotFrame, -ROW_OFFSET)

local function Update()
	local _, _, _, latencyWorld = GetNetStats()
	SetNumber(fpsText, math.floor(GetFramerate() + 0.5))
	SetNumber(worldText, latencyWorld)
	SetLatencyColor(worldText, latencyWorld)
end

-- How far a texture reaches past its frame, from its TOPLEFT and BOTTOMRIGHT anchors.
local function ReachOf(texture, fallback)
	local reach = { left = fallback.left, top = fallback.top, right = fallback.right, bottom = fallback.bottom }
	for i = 1, texture:GetNumPoints() do
		local point, _, _, x, y = texture:GetPoint(i)
		if point == "TOPLEFT" then
			reach.left, reach.top = -x, y
		elseif point == "BOTTOMRIGHT" then
			reach.right, reach.bottom = x, -y
		end
	end
	return reach
end

local function AtlasOf(texture, fallback)
	return texture and texture:GetAtlas() or fallback
end

-- Read the art from the frames the block stands among: the bags bar's group frame, the size
-- and plain gray frame art of the reagent bag slot (regular bag slots wear a gold frame), an
-- action button's empty-slot layers, and how far the micro menu's group frame reaches past
-- its buttons.
local function MeasureArt()
	if BagsBar.BorderArt then
		art.groupFrame = AtlasOf(BagsBar.BorderArt, art.groupFrame)
		art.groupReach = ReachOf(BagsBar.BorderArt, art.groupReach)
	end
	if MicroMenu and MicroMenu.BorderArt then
		art.microMenuReachRight = ReachOf(MicroMenu.BorderArt, { right = art.microMenuReachRight }).right
	end
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
	groupFrame:SetAtlas(art.groupFrame)
	groupFrame:ClearAllPoints()
	groupFrame:SetPoint("TOPLEFT", block, "TOPLEFT", -art.groupReach.left, art.groupReach.top)
	groupFrame:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", art.groupReach.right, -art.groupReach.bottom)
	background:SetAtlas(art.slotBackground)
	slotArt:SetAtlas(art.slotArt)
	slotFrame:SetAtlas(art.slotFrame)
	slotFrame:SetSize(art.slotFrameSize, art.slotFrameSize)
end

-- Making room on the bar. While the addon runs, the block takes the bags bar's place, joined to
-- the micro menu exactly as the bags were, and the bags move right to join the block the same
-- way. Then the whole row moves left by half that, so it grows evenly on both sides and stays
-- centred. What "the whole row" hangs off depends on the layout: in a saved layout the action
-- bar hangs off the micro menu, but Edit Mode places bars in their default position on the
-- screen itself. So the addon follows the anchors of the action bar and of the micro menu up
-- to the frames that hang off the screen, and moves each of those once.
-- Nothing is saved: the layout is never written, Edit Mode anchors these frames again on
-- every layout change, and the moves are taken off while Edit Mode is open so it only ever
-- sees and saves the layout's own positions. Without the addon the bar is exactly as the
-- layout says.
local editModeOpen = false
local layoutPending = false

-- A Blizzard frame the addon nudges sideways: it keeps the anchor Edit Mode last gave it and
-- sets it again with an extra x offset. Edit Mode replaces SetPoint and ClearAllPoints on its
-- frames with versions that also update its snapping and flag an anchor change; the moves use
-- the plain originals it keeps (SetPointBase, ClearAllPointsBase), so they change the position
-- and nothing else.
local function CreateMover(frame)
	local mover = { frame = frame, moving = false }
	local setPoint = frame.SetPointBase or frame.SetPoint
	local clearAllPoints = frame.ClearAllPointsBase or frame.ClearAllPoints

	function mover:Remember()
		local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
		if point then
			self.anchor = { point, relativeTo or frame:GetParent(), relativePoint, x, y }
		end
	end

	function mover:SetExtraX(extraX)
		if not self.anchor then
			return
		end
		self.moving = true
		clearAllPoints(frame)
		setPoint(frame, self.anchor[1], self.anchor[2], self.anchor[3], self.anchor[4] + extraX, self.anchor[5])
		self.moving = false
	end

	return mover
end

local bags
local rowMovers = {} -- frame -> mover, for the row's roots moved so far
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
	if not bags.anchor then
		return
	end
	-- These frames can be protected in combat; finish when combat ends.
	if InCombatLockdown() and AnyProtected() then
		layoutPending = true
		return
	end
	layoutPending = false

	if editModeOpen then
		bags:SetExtraX(0)
		ResetRow()
		StretchXPBars(0)
		block:Hide()
		return
	end

	local point, relativeTo, relativePoint, x, y = unpack(bags.anchor)
	block:SetScale(BagsBar:GetScale())
	block:SetFrameStrata(BagsBar:GetFrameStrata())
	block:SetFrameLevel(BagsBar:GetFrameLevel())
	block:ClearAllPoints()

	if point:find("LEFT") then
		-- The block stands where the bags were, so it joins the micro menu as they did.
		block:SetPoint(point, relativeTo, relativePoint, x, y)

		-- The bags join the block as they joined the micro menu: the same overlap of group
		-- frames. Worked in UIParent units, since the micro menu and bags can be scaled apart.
		local bagsScale = BagsBar:GetScale()
		local microMenuScale = MicroMenu and MicroMenu:GetScale() or 1
		local join = x * bagsScale
		local joinAfterBlock = join + (art.groupReach.right * bagsScale - art.microMenuReachRight * microMenuScale)
		local rowGrowth = art.slotSize * bagsScale + joinAfterBlock
		bags:SetExtraX(rowGrowth / bagsScale)

		-- Grow evenly: when the bags hang off the micro menu, each root of the row moves left by
		-- half, once. Roots no longer in the row go back to where Edit Mode put them.
		local roots = relativeTo == MicroMenuContainer and RowRoots() or {}
		for frame in pairs(roots) do
			RowMoverFor(frame)
		end
		for frame, mover in pairs(rowMovers) do
			mover:SetExtraX(roots[frame] and -rowGrowth / 2 / frame:GetScale() or 0)
		end
		StretchXPBars(relativeTo == MicroMenuContainer and rowGrowth or 0)
	else
		-- Bags placed on their own: stand just left of them, joined the same way, and move nothing.
		bags:SetExtraX(0)
		ResetRow()
		StretchXPBars(0)
		block:SetPoint("BOTTOMRIGHT", BagsBar, "BOTTOMLEFT", -(art.groupReach.right + art.groupReach.left), 0)
	end
	block:Show()
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

	if not (BagsBar and MicroMenuContainer) then
		return
	end
	bags = CreateMover(BagsBar)
	hooksecurefunc(BagsBar, "SetPoint", function() OnMovedByBlizzard(bags) end)
	EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, block)
	EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, block)
	editModeOpen = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() or false

	MeasureArt()
	DressBlock()
	bags:Remember()
	Layout()
	Update()
	C_Timer.NewTicker(UPDATE_INTERVAL, Update)
end)
