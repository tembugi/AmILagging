-- Keep equal to ## Version in the .toc. The game reads the .toc only at client start,
-- so the tooltip uses this, which /reload picks up.
local VERSION = "1.4.2"
-- The addon's name as the player sees it: the tooltip title and the start of chat lines.
local ADDON_TITLE = "Am I Lagging?"

-- The game menu button's latency rule and colors: green up to 300 ms, yellow over 300,
-- red over 600.
local LOW_LATENCY = 300
local MEDIUM_LATENCY = 600
local LATENCY_GREEN = CreateColor(0, 1, 0, 1)
local LATENCY_YELLOW = CreateColor(1, 1, 0, 1)
local LATENCY_RED = CreateColor(1, 0, 0, 1)
-- Seconds between updates of the numbers.
local UPDATE_INTERVAL = 1
-- The tooltip's line under the framerate, in English like the addon's name.
local LIMITED_BY = "Limited by: %s"

-- The block is a bar of its own: one slot in a bar frame, between the micro menu and the bags
-- bar, dressed like them. Its art and sizes are read from the game's own frames at login (see
-- MeasureArt); these are only the values Blizzard's XML sets today, used if a frame is missing.
-- A frame's reach is how far its bar frame art stands out past its buttons.
local art = {
	slotSize = 45,
	slotFrame = "UI-HUD-ActionBar-IconFrame",
	slotFrameSize = 46,
	barFrame = "UI-HUD-ActionBar-Frame",
	barReach = { left = 6, top = 6, right = 5, bottom = 5 },
	microMenuReachRight = 8,
	microMenuReachTop = 8,
}

-- The face: numbers only. FPS on top in white, world latency below in its color, both
-- centered, with a line between them at the slot's center in home latency's color. World
-- latency is the one felt in combat; home latency's number and the labeled values are in the
-- tooltip.
-- The numbers use the game's own heavy number font: the one behind NumberFont_Outline_Huge
-- (Skurri for Latin alphabets, whatever Blizzard sets for other languages), just smaller.
local NUMBER_FONT = NumberFont_Outline_Huge and NumberFont_Outline_Huge:GetFont() or STANDARD_TEXT_FONT
local NUMBER_SIZE = 15
local NUMBER_OUTLINE = "OUTLINE"
-- This font's figures are old style: 0, 1 and 2 stand at x-height, 6 and 8 rise above it,
-- 3, 4, 5, 7 and 9 drop below the baseline. Measured from Skurri in game, as parts of the
-- font size: how far figures rise above and drop below the baseline, and where the baseline
-- sits in the text box. Each number is placed so the band from its highest to its lowest
-- possible figure sits in the middle of its half of the slot, as far from the line as from
-- the border, whatever digits it shows.
local FIGURE_RISE = 0.67
local FIGURE_DROP = 0.19
local BOX_ASCENT = 0.74
local BOX_DESCENT = 0.26
-- The gray inner edge of the slot art, inside the slot's own size.
local SLOT_EDGE = 3.5
-- Room kept free on each side of a number; wider numbers (four-digit latency) shrink to fit.
local NUMBER_MARGIN = 6.5
local LINE_HALF_WIDTH = 16
local LINE_THICKNESS = 1

-- Every chat line starts with the addon's name in gold. The addon writes to chat only when
-- something stopped working: what stopped, in red, then what the player can do.
local function SayProblem(problem, advice)
	print(NORMAL_FONT_COLOR:WrapTextInColorCode(ADDON_TITLE) .. ": " .. RED_FONT_COLOR:WrapTextInColorCode(problem) .. " " .. advice)
end

-- The saved data, per account (AmILaggingDB), both set in Edit Mode: where the player put the
-- block, as its center in UIParent units from the screen's bottom left, and its size, as a
-- percentage of the bags bar's. Without a spot the block stands where the addon puts it;
-- without a size it is as big as the bags bar. Nothing else is saved.
local SAVE_FORMAT = 1
local DEFAULT_SIZE = 100
local saved = { format = SAVE_FORMAT }

-- The size slider's range and step: the bags bar's own Size setting in Edit Mode, read from the
-- game's setting list; these are Blizzard's values today, used if the list is missing.
local function SizeRange()
	local settings = EditModeSettingDisplayInfoManager and EditModeSettingDisplayInfoManager.GetSystemSettingDisplayInfoMap
		and Enum.EditModeSystem and Enum.EditModeBagsSetting
		and EditModeSettingDisplayInfoManager:GetSystemSettingDisplayInfoMap(Enum.EditModeSystem.Bags)
	local size = settings and settings[Enum.EditModeBagsSetting.Size]
	if size and size.minValue and size.maxValue and size.stepSize then
		return size.minValue, size.maxValue, size.stepSize
	end
	return 75, 200, 5
end

local function IsFiniteNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Rebuilds the saved data on every load from the fields the addon uses and drops everything
-- else: a spot stays only when both its numbers are finite, a size only when it is in the
-- slider's range and isn't the default.
local function NormalizeSaved(data)
	local result = { format = SAVE_FORMAT }
	local spot = type(data) == "table" and data.spot
	if type(spot) == "table" and IsFiniteNumber(spot.x) and IsFiniteNumber(spot.y) then
		result.spot = { x = spot.x, y = spot.y }
	end
	local size = type(data) == "table" and data.size
	local minSize, maxSize = SizeRange()
	if IsFiniteNumber(size) and size >= minSize and size <= maxSize and size ~= DEFAULT_SIZE then
		result.size = size
	end
	return result
end

local function LatencyColor(latency)
	if latency > MEDIUM_LATENCY then
		return LATENCY_RED
	elseif latency > LOW_LATENCY then
		return LATENCY_YELLOW
	end
	return LATENCY_GREEN
end

local block = CreateFrame("Frame", nil, UIParent)
block:EnableMouse(true)
-- The player can drag it in Edit Mode. It always stays on the screen by its own size, as Edit Mode
-- keeps the game's bars (clampedToScreen): its frame art may reach past the edge like theirs. In
-- the row at the screen's bottom the art does, so counting it pushed the block up off the row.
block:SetMovable(true)
block:SetClampedToScreen(true)
block:Hide()

-- The bar frame around the slot, behind everything, as the bags bar draws its own.
local barFrame = block:CreateTexture(nil, "BACKGROUND", nil, -3)

-- Solid black behind the numbers: the game's empty-slot background lets the world show through.
local background = block:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0, 0, 0, 1)
-- Like the bag buttons' frame art: anchored at the slot's top left and a pixel larger, so its
-- opening is centered half a pixel right of and below the slot's own center. The numbers and
-- the line center on it.
local slotFrame = block:CreateTexture(nil, "BORDER")
slotFrame:SetPoint("TOPLEFT")

-- The line between the rows, fading out at both ends. UpdateNumbers colors it.
local lineLeft = block:CreateTexture(nil, "ARTWORK")
lineLeft:SetColorTexture(1, 1, 1, 1)
lineLeft:SetSize(LINE_HALF_WIDTH, LINE_THICKNESS)
lineLeft:SetPoint("RIGHT", slotFrame, "CENTER")
local lineRight = block:CreateTexture(nil, "ARTWORK")
lineRight:SetColorTexture(1, 1, 1, 1)
lineRight:SetSize(LINE_HALF_WIDTH, LINE_THICKNESS)
lineRight:SetPoint("LEFT", slotFrame, "CENTER")

local function CreateNumber(aboveLine)
	local text = block:CreateFontString(nil, "OVERLAY")
	text.aboveLine = aboveLine
	return text
end

local fpsText = CreateNumber(true)
fpsText:SetTextColor(1, 1, 1)
local worldText = CreateNumber(false)

-- The rows mirror each other: FPS stands above the line, latency hangs below it.
local function PlaceNumber(text, size)
	local half = art.slotSize / 2 - SLOT_EDGE - LINE_THICKNESS / 2
	local gap = (half - (FIGURE_RISE + FIGURE_DROP) * size) / 2
	local fromCenter = LINE_THICKNESS / 2 + gap
	text:ClearAllPoints()
	if text.aboveLine then
		text:SetPoint("BOTTOM", slotFrame, "CENTER", 0, fromCenter + (FIGURE_DROP - BOX_DESCENT) * size)
	else
		text:SetPoint("TOP", slotFrame, "CENTER", 0, -fromCenter - (FIGURE_RISE - BOX_ASCENT) * size)
	end
end

local function SetNumberSize(text, size)
	if size ~= text.fontSize then
		text.fontSize = size
		text:SetFont(NUMBER_FONT, size, NUMBER_OUTLINE)
	end
end

-- Shows a number at full size, or smaller if it is too wide for the slot. A number that did
-- not change is left as it is.
local function ShowNumber(text, value)
	if value == text.value then
		return
	end
	text.value = value
	SetNumberSize(text, NUMBER_SIZE)
	text:SetText(value)
	local size = NUMBER_SIZE
	local maxWidth = art.slotSize - 2 * NUMBER_MARGIN
	local width = text:GetStringWidth()
	if width > maxWidth then
		size = NUMBER_SIZE * maxWidth / width
		SetNumberSize(text, size)
	end
	if size ~= text.placedSize then
		text.placedSize = size
		PlaceNumber(text, size)
	end
end

-- The line takes home latency's color, with the same rule as the numbers.
local function SetLineColor(color)
	if color == lineLeft.color then
		return
	end
	lineLeft.color = color
	local r, g, b = color:GetRGB()
	local faded = CreateColor(r, g, b, 0)
	lineLeft:SetGradient("HORIZONTAL", faded, color)
	lineRight:SetGradient("HORIZONTAL", color, faded)
end

local function UpdateNumbers()
	local _, _, latencyHome, latencyWorld = GetNetStats()
	SetLineColor(LatencyColor(latencyHome))
	ShowNumber(fpsText, Round(GetFramerate()))
	ShowNumber(worldText, latencyWorld)
	worldText:SetTextColor(LatencyColor(latencyWorld):GetRGB())
end

-- The game menu button's tooltip lines, in the game's own words, FPS first as on the face.
-- Under the framerate: whether the processor or the graphics card holds it back, as the
-- game's own framerate counter (Ctrl+R) tells it; left out when the game doesn't know.
-- The tooltip calls UpdateTooltip while it is open, so the numbers stay current, as the game
-- menu button's do.
function block:UpdateTooltip()
	local _, _, latencyHome, latencyWorld = GetNetStats()
	local isCpuBound = IsCpuBound()
	GameTooltip_SetDefaultAnchor(GameTooltip, self)
	GameTooltip_SetTitle(GameTooltip, ADDON_TITLE)
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip:AddLine(format(MAINMENUBAR_FPS_LABEL, GetFramerate()), HIGHLIGHT_FONT_COLOR:GetRGB())
	if isCpuBound ~= nil then
		GameTooltip:AddLine(format(LIMITED_BY, isCpuBound and "CPU" or "GPU"), HIGHLIGHT_FONT_COLOR:GetRGB())
	end
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip:AddLine(format(MAINMENUBAR_LATENCY_LABEL, latencyHome, latencyWorld), HIGHLIGHT_FONT_COLOR:GetRGB())
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip:AddLine("v" .. VERSION, GRAY_FONT_COLOR:GetRGB())
	GameTooltip:Show()
end

block:SetScript("OnEnter", block.UpdateTooltip)
block:SetScript("OnLeave", GameTooltip_Hide)

-- The numbers update while the block is on screen. If reading them ever fails, the error is
-- reported once through the game's error handler, the numbers are cleared (old numbers would
-- mislead) and the updates stop until /reload.
local ticker
local numbersStopped = false

local function Refresh()
	if numbersStopped or not block:IsVisible() then
		return
	end
	if not xpcall(UpdateNumbers, CallErrorHandler) then
		numbersStopped = true
		ticker:Cancel()
		fpsText:SetText("")
		worldText:SetText("")
		SayProblem("couldn't read the framerate and latency, so the numbers are off.", "Type /reload to try again.")
	end
end

block:SetScript("OnShow", Refresh)

local function AtlasOf(texture, fallback)
	return texture and texture:GetAtlas() or fallback
end

local function WidthOf(region, fallback)
	local width = region and region:GetWidth()
	if width and width > 0 then
		return width
	end
	return fallback
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

-- Read the art from the frames the block stands among: the bags bar's frame art and reach, the
-- size and plain gray frame art of the reagent bag slot (regular bag slots wear a gold frame),
-- and how far the micro menu's frame art reaches past its right end.
local function MeasureArt()
	if BagsBar and BagsBar.BorderArt then
		art.barFrame = AtlasOf(BagsBar.BorderArt, art.barFrame)
		art.barReach = ReachOf(BagsBar.BorderArt, art.barReach)
	end
	if MicroMenu and MicroMenu.BorderArt then
		local reach = ReachOf(MicroMenu.BorderArt, { right = art.microMenuReachRight, top = art.microMenuReachTop })
		art.microMenuReachRight, art.microMenuReachTop = reach.right, reach.top
	end
	local bagSlot = CharacterReagentBag0Slot
	if bagSlot then
		art.slotSize = WidthOf(bagSlot, art.slotSize)
		local normal = bagSlot:GetNormalTexture()
		art.slotFrame = AtlasOf(normal, art.slotFrame)
		art.slotFrameSize = WidthOf(normal, art.slotFrameSize)
	end
end

local function DressBlock()
	block:SetSize(art.slotSize, art.slotSize)
	barFrame:SetAtlas(art.barFrame)
	barFrame:ClearAllPoints()
	barFrame:SetPoint("TOPLEFT", block, "TOPLEFT", -art.barReach.left, art.barReach.top)
	barFrame:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", art.barReach.right, -art.barReach.bottom)
	slotFrame:SetAtlas(art.slotFrame)
	slotFrame:SetSize(art.slotFrameSize, art.slotFrameSize)
	-- Lay the numbers out again for the new size.
	fpsText.value, fpsText.placedSize = nil, nil
	worldText.value, worldText.placedSize = nil, nil
end

-- Making room on the bar. The block is a bar of its own between the micro menu and the bags
-- bar: it stands where the bags bar stood, joined to the micro menu the same way, and the bags
-- bar moves right to join the block as it joined the micro menu. Being its own bar, it stays
-- when the bags bar is hidden, by another addon or by the game.
-- Edit Mode puts the row at a fixed spot, so a wider row would lean right. The whole row moves
-- left by half the growth, so it grows evenly on both sides and stays centered. What "the
-- whole row" hangs off depends on the layout: in a saved layout the action bar hangs off the
-- micro menu, but Edit Mode places bars in their default position on the screen itself. So
-- the addon follows the anchors of the action bar and of the micro menu up to the frames that
-- hang off the screen, and moves each of those once.
-- The block stands in the row only while the micro menu is where Blizzard's layout puts it.
-- When the player has customized the bar (moved the micro menu, or dragged the block somewhere
-- in Edit Mode), the block floats on its own and nothing on the bar moves. In the gamepad
-- interface the game hides the row; the block then stands on its own, centered between the
-- gamepad buttons and the XP bar.
-- The layout is never written: Edit Mode anchors these frames again on every layout change and
-- saves only what the player moves, where they drop it; the moves apply only to bars still in
-- Blizzard's arrangement, also while Edit Mode is open. Without the addon the bar is exactly as
-- the layout says.
local editModeOpen = false
local layoutPending = false
local lastPlacement -- where the last layout put the block
-- While the micro menu is selected in Edit Mode: where the block and the micro menu stood when it
-- was selected (their centers in UIParent units), so the block stays put while the menu moves.
local menuHold
local rowMovers = {} -- frame -> mover, for the frames moved so far
local xpBars = {} -- XP bar container -> its stretch
local Layout, ShowEditBox

-- Making room runs inside the game's own code: right after Blizzard moves or resizes a frame.
-- An error there must not break the code that called it, nor repeat on every move. The first
-- error is reported through the game's error handler and said once in chat; the bar is then
-- put back the way the game set it and kept so until /reload. If even that fails, the addon
-- leaves the bar alone.
local failure -- nil while making room works, then "restoring", then "stopped"

local function Guarded(func, ...)
	if failure == "stopped" then
		return
	end
	if xpcall(func, CallErrorHandler, ...) then
		return
	end
	if failure then
		failure = "stopped"
		return
	end
	failure = "restoring"
	SayProblem("couldn't make room on the bar, so it's back the way the game set it.", "Type /reload to try again.")
	Guarded(Layout)
end

-- A Blizzard frame the addon nudges sideways. It keeps the points Blizzard last set on the
-- frame and sets them again with an extra x offset. Edit Mode replaces SetPoint and
-- ClearAllPoints on its frames with versions that also update its snapping and flag an anchor
-- change; the moves use the plain original it keeps (SetPointBase), so they change the
-- position and nothing else, and never reach the addon's own hooks.
-- A frame can have two points, set one after the other (Edit Mode keeps a second one when a
-- frame is snapped to two others), so each point is remembered and moved on its own.
local function CreateMover(frame)
	local setPoint = frame.SetPointBase or frame.SetPoint
	local mover = { points = {}, applied = {} } -- point -> Blizzard's anchor, and offset added

	function mover:Remember(point)
		local name, relativeTo, relativePoint, x, y = frame:GetPointByName(point)
		if name then
			self.points[name] = { relativeTo, relativePoint, x, y }
			self.applied[name] = 0
		end
	end

	function mover:Forget()
		wipe(self.points)
		wipe(self.applied)
	end

	function mover:RememberAll()
		self:Forget()
		for i = 1, frame:GetNumPoints() do
			self:Remember((frame:GetPoint(i)))
		end
	end

	-- Only touches points whose offset has to change, so frames that stay where Blizzard put
	-- them are left alone.
	function mover:SetExtraX(extraX)
		for point, anchor in pairs(self.points) do
			if self.applied[point] ~= extraX then
				self.applied[point] = extraX
				setPoint(frame, point, anchor[1], anchor[2], anchor[3] + extraX, anchor[4])
			end
		end
	end

	return mover
end

local function OnMovedByBlizzard(mover, point)
	if type(point) == "string" then
		mover:Remember(point:upper())
	else
		mover:RememberAll()
	end
	Layout()
end

local function RowMoverFor(frame)
	local mover = rowMovers[frame]
	if not mover then
		mover = CreateMover(frame)
		mover:RememberAll()
		rowMovers[frame] = mover
		hooksecurefunc(frame, "ClearAllPoints", function()
			Guarded(mover.Forget, mover)
		end)
		hooksecurefunc(frame, "SetPoint", function(_, point)
			Guarded(OnMovedByBlizzard, mover, point)
		end)
	end
	return mover
end

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

-- Whether the player left a frame of Edit Mode's where Blizzard's layout puts it. Before Edit
-- Mode has set up its systems it can't tell yet; the frame is then taken as Blizzard's.
local function InDefaultPosition(frame)
	if not frame.IsInDefaultPosition or (frame.IsInitialized and not frame:IsInitialized()) then
		return true
	end
	return frame:IsInDefaultPosition() and true or false
end

-- The action bar is part of the row while it is where Blizzard's layout puts it. A player who
-- moved it in Edit Mode took it out of the row, and the bars Blizzard stacks on it with it.
local function ActionBarInRow()
	return MainActionBar ~= nil and InDefaultPosition(MainActionBar)
end

-- The row's roots: where the micro menu's chain starts, and the action bar's while it is part of
-- the row.
local function RowRoots()
	local roots = { [RootOf(MicroMenuContainer)] = true }
	if ActionBarInRow() then
		roots[RootOf(MainActionBar)] = true
	end
	return roots
end

-- The bars Blizzard stacks above the row, from its own list of bottom bars: the XP bars, the
-- action bars above them and the vehicle exit button. The main action bar heads that list; it
-- is part of the row. Camelot stacks the bars on the main action bar by their left edge, so
-- they move with the row and line up with its left end.
local function BottomBars()
	local bars = {}
	if EditModeUtil and EditModeUtil.GetBottomActionBars then
		for _, bar in ipairs(EditModeUtil:GetBottomActionBars()) do
			if bar ~= MainActionBar then
				bars[#bars + 1] = bar
			end
		end
	end
	return bars
end

-- A bar the player moved elsewhere in Edit Mode is no longer stacked on the row.
local function IsStackedOnRow(bar)
	for i = 1, bar:GetNumPoints() do
		local _, relativeTo = bar:GetPoint(i)
		if relativeTo == MainActionBar then
			return true
		end
	end
	return false
end

-- The XP bars stretch by the row's growth to reach its right end again: Blizzard's own methods,
-- the ones its Size setting uses, fit the bars and tick marks inside a wider container. The
-- other stacked bars are fixed buttons and cannot stretch, so they move right by half the
-- growth to stay centered over the row.
local function CanStretch(bar)
	return bar.ResizeContainerBars and bar.UpdateDividers and bar.GetExpectedSegments
end

local function FitXPBar(container, state)
	local width = state.base + state.extra
	if math.abs(container:GetWidth() - width) < 0.01 then
		return
	end
	state.fitting = true
	container:SetWidth(width)
	container:ResizeContainerBars()
	container:UpdateDividers(container:GetExpectedSegments())
	state.fitting = false
end

-- Blizzard sized the container (its Size setting, or a layout change): that is the new base
-- width. Resizing waits for the end of combat, like the moves.
local function OnXPBarResized(container)
	local state = xpBars[container]
	if state.fitting then
		return
	end
	state.base = container:GetWidth()
	if InCombatLockdown() then
		layoutPending = true
		return
	end
	FitXPBar(container, state)
end

local function XPBarStateFor(container)
	local state = xpBars[container]
	if not state then
		state = { base = container:GetWidth(), extra = 0 }
		xpBars[container] = state
		local function OnResized()
			Guarded(OnXPBarResized, container)
		end
		hooksecurefunc(container, "SetSize", OnResized)
		hooksecurefunc(container, "SetWidth", OnResized)
		-- Moving onto the row or off it decides whether it stretches.
		hooksecurefunc(container, "SetPoint", function()
			Guarded(Layout)
		end)
	end
	return state
end

-- Watch the bars above the row from the start: Edit Mode first parks them at the screen's top
-- left and moves them onto the action bar a moment later, so their anchor at one moment says
-- little.
local function WatchBottomBars()
	for _, bar in ipairs(BottomBars()) do
		if CanStretch(bar) then
			XPBarStateFor(bar)
		else
			RowMoverFor(bar)
		end
	end
end

-- Whether a frame is on screen: shown, with every frame above it up to the interface shown
-- too. Another addon may hide a bar by parenting it to a hidden frame, so it stays shown but
-- isn't seen. Hiding the whole interface (Alt+Z) hides UIParent and nothing else; everything
-- comes back with it, so that changes nothing.
local function OnScreen(frame)
	while frame and frame ~= UIParent do
		if not frame:IsShown() then
			return false
		end
		frame = frame:GetParent()
	end
	return true
end

local function InGamepadInterface()
	return C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle and Enum.InputDeviceInterfaceType
		and C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad
end


-- Where the block stands:
-- "row": in the bottom row, right of the micro menu, while the micro menu is where Blizzard's
--   layout puts it, Edit Mode open or not;
-- "spot": where the player put it in Edit Mode;
-- "besideMicroMenu": next to a micro menu the player moved, on a side with room;
-- "aboveXPBar": on its own, centered between the XP bar and the gamepad buttons: in the gamepad
--   interface, where the game hides the row, or when the micro menu isn't on screen (another
--   addon replacing the game's bars);
-- nil: hidden, after a failure.
local function Placement()
	if failure then
		return nil
	elseif InGamepadInterface() then
		return "aboveXPBar"
	elseif saved.spot then
		return "spot"
	elseif not OnScreen(MicroMenu or MicroMenuContainer) then
		return "aboveXPBar"
	elseif not InDefaultPosition(MicroMenuContainer) then
		return "besideMicroMenu"
	end
	return "row"
end

-- How the bags bar hangs off the micro menu's right side, as Blizzard set it: its point, the
-- micro menu's point and the offsets, in the bags bar's units. Nil when it hangs elsewhere.
local function BagsJoin()
	local mover = BagsBar and rowMovers[BagsBar]
	if not mover then
		return nil
	end
	for point, anchor in pairs(mover.points) do
		local relativeTo, relativePoint, x, y = anchor[1], anchor[2], anchor[3], anchor[4]
		if relativeTo == MicroMenuContainer and point:find("LEFT") and relativePoint and relativePoint:find("RIGHT") then
			return point, relativePoint, x, y
		end
	end
	return nil
end

-- The block takes the bags bar's place by the micro menu. When the bags bar hangs elsewhere,
-- it joins the micro menu as Blizzard's layout joins the bags.
local function JoinToMicroMenu()
	local point, relativePoint, x, y = BagsJoin()
	if point then
		return point, relativePoint, x, y, true
	end
	return BAGS_ANCHOR_POINT or "BOTTOMLEFT", BAGS_ANCHOR_RELATIVE_POINT or "BOTTOMRIGHT",
		BAGS_ANCHOR_OFFSET_X or 7, BAGS_ANCHOR_OFFSET_Y or -4, false
end

-- The join's offsets are in the bags bar's units; the block can be another size.
local function BagsScale()
	return BagsBar and BagsBar:GetEffectiveScale() or UIParent:GetEffectiveScale()
end

local function BagsToBlock(value)
	return value * BagsScale() / block:GetEffectiveScale()
end

-- How much wider the block makes the row, in UIParent units. The bags join the block as they
-- joined the micro menu, with the same overlap of frame art, so the row grows by the join x,
-- the slot and the block's reach, less the micro menu's reach.
local function RowGrowth(x)
	local blockScale = block:GetEffectiveScale()
	local microMenuScale = MicroMenu and MicroMenu:GetEffectiveScale() or blockScale
	return ((art.slotSize + art.barReach.right) * blockScale + x * BagsScale()
		- art.microMenuReachRight * microMenuScale) / UIParent:GetEffectiveScale()
end

local EDGE_GETTERS = { top = "GetTop", bottom = "GetBottom", left = "GetLeft", right = "GetRight" }

-- A frame's edge in UIParent units, from the screen's bottom left.
local function EdgeOf(frame, edge)
	local value = frame and frame[EDGE_GETTERS[edge]](frame)
	if not value then
		return nil
	end
	return value * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- The block's own units to UIParent's.
local function BlockToUIParent()
	return block:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Centered between the XP bar and the gamepad buttons, where the user marked it on the gamepad
-- interface. Without the gamepad buttons' frame, just above the XP bar.
local function AboveXPBarHeight()
	local xpBar = MainStatusTrackingBarContainer
	local xpTop = xpBar and OnScreen(xpBar) and EdgeOf(xpBar, "top") or 0
	local buttonsBottom = GamepadMainActionBarFrame and EdgeOf(GamepadMainActionBarFrame, "bottom")
	if buttonsBottom and buttonsBottom > xpTop then
		return (xpTop + buttonsBottom) / 2
	end
	return xpTop + (art.slotSize / 2 + art.barReach.bottom) * BlockToUIParent()
end

-- Offsets and widths are in each frame's own scale.
local function InFrameUnits(value, frame)
	return value * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
end

-- A point's name with left and right swapped: the same join on the micro menu's other side.
local function Mirrored(point)
	return (point:gsub("LEFT", "#"):gsub("RIGHT", "LEFT"):gsub("#", "RIGHT"))
end

-- Whether a frame hangs off the micro menu's left or right side.
local function HangsOffMicroMenu(frame, side)
	if not frame then
		return false
	end
	for i = 1, frame:GetNumPoints() do
		local _, relativeTo, relativePoint = frame:GetPoint(i)
		if relativeTo == MicroMenuContainer and relativePoint and relativePoint:find(side) then
			return true
		end
	end
	return false
end

-- Just above the micro menu's right end, clear of its frame art.
local function SetAboveMicroMenu()
	block:SetPoint("BOTTOMRIGHT", MicroMenuContainer, "TOPRIGHT", 0, art.microMenuReachTop + art.barReach.bottom)
end

-- Next to a micro menu the player moved, joined as on the row: on its right side when the bags
-- bar doesn't hang there and the block fits on the screen, else on its left side when the action
-- bar doesn't hang there and the block fits, else above it.
local function SetBesideMicroMenu(point, relativePoint, x, y)
	local toUIParent = BlockToUIParent()
	local join = x * BagsScale() / UIParent:GetEffectiveScale()
	local left, right = EdgeOf(MicroMenuContainer, "left"), EdgeOf(MicroMenuContainer, "right")
	local rightEnd = right and right + join + (art.slotSize + art.barReach.right) * toUIParent
	if not HangsOffMicroMenu(BagsBar, "RIGHT") and (not rightEnd or rightEnd <= UIParent:GetRight()) then
		block:SetPoint(point, MicroMenuContainer, relativePoint, BagsToBlock(x), BagsToBlock(y))
		return
	end
	local leftEnd = left and left - join - (art.slotSize + art.barReach.left) * toUIParent
	if not HangsOffMicroMenu(MainActionBar, "LEFT") and (not leftEnd or leftEnd >= 0) then
		block:SetPoint(Mirrored(point), MicroMenuContainer, Mirrored(relativePoint), BagsToBlock(-x), BagsToBlock(y))
		return
	end
	SetAboveMicroMenu()
end

-- Where the block's center stands in the row, in UIParent units: joined to the micro menu's
-- right side as JoinToMicroMenu says. Nil when the micro menu's edges aren't known yet.
local function RowCenter()
	local point, relativePoint, x, y = JoinToMicroMenu()
	local left, right = EdgeOf(MicroMenuContainer, "left"), EdgeOf(MicroMenuContainer, "right")
	local bottom, top = EdgeOf(MicroMenuContainer, "bottom"), EdgeOf(MicroMenuContainer, "top")
	if not (left and right and bottom and top) then
		return nil
	end
	-- Where a point's name sits along an axis: -1 (left or bottom), 0 (middle) or 1.
	local function Along(name, low, high)
		return name:find(low) and -1 or name:find(high) and 1 or 0
	end
	local bagsToUIParent = BagsScale() / UIParent:GetEffectiveScale()
	local half = art.slotSize / 2 * BlockToUIParent()
	local anchorX = (left + right) / 2 + Along(relativePoint, "LEFT", "RIGHT") * (right - left) / 2
	local anchorY = (bottom + top) / 2 + Along(relativePoint, "BOTTOM", "TOP") * (top - bottom) / 2
	return anchorX + x * bagsToUIParent - Along(point, "LEFT", "RIGHT") * half,
		anchorY + y * bagsToUIParent - Along(point, "BOTTOM", "TOP") * half
end

-- In Edit Mode the block shows as Edit Mode shows the game's bars: a blue box over it, yellow
-- while it is selected or dragged, above the game's own boxes so it is easy to grab. Mouse over
-- shows its name and Edit Mode's "Click To Edit"; a click selects it and opens its settings, a
-- drag moves it. Edit Mode keeps its box layout to itself (EditModeSystemSelectionLayout, local in
-- EditModeSystemTemplates.lua), so its values are copied here; the art is the game's.
local EDIT_MODE_BOX_LAYOUT = {
	TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
	BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
	LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
	RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
	Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local EDIT_MODE_HIGHLIGHT = "editmode-actionbar-highlight"
local EDIT_MODE_SELECTED = "editmode-actionbar-selected"
-- Where Edit Mode's boxes stand (EditModeSystemSelectionBaseTemplate), if no box can be read.
local EDIT_MODE_BOX_STRATA = "MEDIUM"
local EDIT_MODE_BOX_LEVEL = 1000

local editBox = CreateFrame("Frame", nil, block, "NineSliceCodeTemplate")
editBox:SetAllPoints()
editBox:EnableMouse(true)
editBox:RegisterForDrag("LeftButton")
editBox:Hide()
local dragging, selected = false, false

function ShowEditBox(shown)
	if shown then
		-- One level above Edit Mode's own boxes, read from the micro menu's.
		local gameBox = MicroMenuContainer and MicroMenuContainer.Selection
		editBox:SetFrameStrata(gameBox and gameBox:GetFrameStrata() or EDIT_MODE_BOX_STRATA)
		editBox:SetFrameLevel((gameBox and gameBox:GetFrameLevel() or EDIT_MODE_BOX_LEVEL) + 1)
		local kit = (dragging or selected) and EDIT_MODE_SELECTED or EDIT_MODE_HIGHLIGHT
		if kit ~= editBox.kit then
			editBox.kit = kit
			NineSliceUtil.ApplyLayout(editBox, EDIT_MODE_BOX_LAYOUT, kit)
		end
	end
	editBox:SetShown(shown)
end

-- The block's settings in Edit Mode, built like the game's settings dialog for its bars
-- (EditModeSystemSettingsDialog: its border, title, close button, slider row and buttons, with
-- the game's words), since the game's own dialog only serves Edit Mode's systems. It opens where
-- the game's opens for the bags bar (its settings dialog anchor) and can be dragged.
-- Size: the bags bar's Size slider, as a percentage of the bags bar's size; 100% is the default.
-- Revert Changes: back to the spot and size the block had when Edit Mode opened, as the game's
-- button reverts what changed since the layout was saved. Reset To Default Position: back to
-- where the addon puts it (the row, or next to a moved micro menu); the size stays.
-- Its measures are read from the game's dialog, which always exists (hidden until it opens for
-- one of the game's bars): strata and level, padding, title font and place, spacing, the Revert
-- Changes button and the divider. These are Blizzard's values from EditModeDialogs.xml, used if
-- a piece is missing. The slider row and the wide button come from templates the game only makes
-- for its own bars (EditModeSettingSliderTemplate, EditModeSystemSettingsDialogExtraButtonTemplate),
-- so their sizes are Blizzard's values from those templates.
local function GameDialogMeasures()
	local measures = {
		strata = "DIALOG", level = 200, widthPadding = 40, heightPadding = 40,
		titleFont = "GameFontHighlightLarge", titleTop = 15, sectionSpacing = 12, buttonSpacing = 2,
		revertWidth = 180, buttonHeight = 28,
		dividerTexture = "Interface\\FriendsFrame\\UI-FriendsFrame-OnlineDivider", dividerWidth = 330, dividerHeight = 16,
		rowWidth = 343, rowHeight = 32, labelWidth = 100, sliderWidth = 200, extraButtonWidth = 330,
	}
	local game = EditModeSystemSettingsDialog
	if not game then
		return measures
	end
	measures.strata, measures.level = game:GetFrameStrata(), game:GetFrameLevel()
	measures.widthPadding = game.widthPadding or measures.widthPadding
	measures.heightPadding = game.heightPadding or measures.heightPadding
	if game.Title then
		measures.titleFont = game.Title:GetFontObject() or measures.titleFont
		local _, _, _, _, y = game.Title:GetPoint(1)
		measures.titleTop = y and -y or measures.titleTop
	end
	if game.Settings then
		local _, _, _, _, y = game.Settings:GetPoint(1)
		measures.sectionSpacing = y and -y or measures.sectionSpacing
	end
	local buttons = game.Buttons
	if buttons then
		measures.buttonSpacing = buttons.spacing or measures.buttonSpacing
		local revert = buttons.RevertChangesButton
		if revert and revert:GetWidth() > 0 and revert:GetHeight() > 0 then
			measures.revertWidth, measures.buttonHeight = revert:GetWidth(), revert:GetHeight()
		end
		local divider = buttons.Divider
		if divider then
			measures.dividerTexture = divider:GetTexture() or measures.dividerTexture
			if divider:GetWidth() > 0 and divider:GetHeight() > 0 then
				measures.dividerWidth, measures.dividerHeight = divider:GetWidth(), divider:GetHeight()
			end
		end
	end
	return measures
end

local dialog, sizeSlider, revertButton, resetButton
local updatingDialog = false
local editModeStart -- the spot and size when Edit Mode opened

local function CopySpot(spot)
	return spot and { x = spot.x, y = spot.y }
end

local function SameSpot(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.x == b.x and a.y == b.y
end

local function UpdateButtons()
	local changed = editModeStart ~= nil
		and (not SameSpot(saved.spot, editModeStart.spot) or saved.size ~= editModeStart.size)
	revertButton:SetEnabled(changed)
	resetButton:SetEnabled(saved.spot ~= nil)
end

local function ShowAsPercentage(value)
	return FormatPercentage(value / DEFAULT_SIZE, true)
end

local function UpdateDialog()
	if not dialog then
		return
	end
	local minSize, maxSize, step = SizeRange()
	local formatters = {
		[MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, ShowAsPercentage),
	}
	updatingDialog = true
	sizeSlider:Init(saved.size or DEFAULT_SIZE, minSize, maxSize, (maxSize - minSize) / step, formatters)
	updatingDialog = false
	UpdateButtons()
end

local function OnSizeChanged(value)
	if updatingDialog then
		return
	end
	local minSize, _, step = SizeRange()
	value = minSize + Round((value - minSize) / step) * step
	saved.size = value ~= DEFAULT_SIZE and value or nil
	Layout()
	UpdateButtons()
end

local function RevertChanges()
	saved.spot = CopySpot(editModeStart.spot)
	saved.size = editModeStart.size
	Layout()
	UpdateDialog()
end

local function ResetPosition()
	saved.spot = nil
	Layout()
	UpdateDialog()
end

local function Deselect()
	selected = false
	if dialog then
		dialog:Hide()
	end
	ShowEditBox(editBox:IsShown())
end

local function CreateDialog()
	local m = GameDialogMeasures()
	dialog = CreateFrame("Frame", nil, UIParent)
	dialog:SetFrameStrata(m.strata)
	dialog:SetFrameLevel(m.level)
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:SetClampedToScreen(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	dialog:Hide()

	local border = CreateFrame("Frame", nil, dialog, "DialogBorderTranslucentTemplate")
	border:SetAllPoints()

	local title = dialog:CreateFontString(nil, "ARTWORK")
	title:SetFontObject(m.titleFont)
	title:SetPoint("TOP", 0, -m.titleTop)
	title:SetText(ADDON_TITLE)

	local closeButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT")
	closeButton:SetScript("OnClick", function()
		Guarded(Deselect)
	end)

	local row = CreateFrame("Frame", nil, dialog)
	row:SetSize(m.rowWidth, m.rowHeight)
	row:SetPoint("TOP", title, "BOTTOM", 0, -m.sectionSpacing)
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	label:SetSize(m.labelWidth, m.rowHeight)
	label:SetJustifyH("LEFT")
	label:SetPoint("LEFT")
	label:SetText(HUD_EDIT_MODE_SETTING_BAGS_SIZE)
	sizeSlider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	sizeSlider:SetSize(m.sliderWidth, m.rowHeight)
	sizeSlider:SetPoint("LEFT", label, "RIGHT", 5, 0)
	sizeSlider.MinText:Hide()
	sizeSlider.MaxText:Hide()
	sizeSlider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		Guarded(OnSizeChanged, value)
	end, dialog)

	revertButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate, UIButtonTemplate")
	revertButton:SetSize(m.revertWidth, m.buttonHeight)
	revertButton:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -m.sectionSpacing)
	revertButton:SetText(HUD_EDIT_MODE_REVERT_CHANGES)
	revertButton:SetOnClickHandler(function()
		Guarded(RevertChanges)
	end)
	local divider = dialog:CreateTexture(nil, "ARTWORK")
	divider:SetTexture(m.dividerTexture)
	divider:SetSize(m.dividerWidth, m.dividerHeight)
	divider:SetPoint("TOPLEFT", revertButton, "BOTTOMLEFT", 0, -m.buttonSpacing)
	resetButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate, UIButtonTemplate")
	resetButton:SetSize(m.extraButtonWidth, m.buttonHeight)
	resetButton:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -m.buttonSpacing)
	resetButton:SetText(HUD_EDIT_MODE_RESET_POSITION)
	resetButton:SetOnClickHandler(function()
		Guarded(ResetPosition)
	end)

	-- Sized as the game's: its content and the padding (ResizeLayoutMixin).
	local contentHeight = title:GetStringHeight() + m.sectionSpacing + m.rowHeight + m.sectionSpacing
		+ m.buttonHeight + m.buttonSpacing + m.dividerHeight + m.buttonSpacing + m.buttonHeight
	dialog:SetSize(math.max(m.rowWidth, m.extraButtonWidth) + m.widthPadding, contentHeight + m.heightPadding)
	local anchor = BagsBar and BagsBar.GetSettingsDialogAnchor and BagsBar:GetSettingsDialogAnchor()
	if anchor and anchor.Get then
		local point, relativeTo, relativePoint, x, y = anchor:Get()
		dialog:SetPoint(point, relativeTo, relativePoint, x, y)
	else
		-- Blizzard's default dialog anchor (EditModeSystemMixin:SetupSettingsDialogAnchor).
		dialog:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -250, 200)
	end
end

-- Only one thing is selected in Edit Mode at a time, as in the game: selecting the block first
-- clears Edit Mode's own selection, which closes the game's settings dialog. Called from outside
-- Blizzard's code out of combat, ClearSelectedSystem runs its clearing through a secure delegate,
-- so it stays Blizzard's own (Edit Mode can't be open in combat).
local function Select()
	if selected then
		return
	end
	if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem and not InCombatLockdown() then
		EditModeManagerFrame:ClearSelectedSystem()
	end
	if not dialog then
		CreateDialog()
	end
	selected = true
	GameTooltip_Hide()
	UpdateDialog()
	dialog:Show()
	ShowEditBox(true)
end

-- A frame's center in UIParent units.
local function CenterOf(frame)
	local x, y = frame:GetCenter()
	if not x then
		return nil
	end
	local toUIParent = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return x * toUIParent, y * toUIParent
end

-- The block is its own thing: when the player selects the micro menu in Edit Mode (to drag it or
-- move it with the arrow keys), the block lets go of it and stays where it stands on the screen.
-- Only a block standing by the micro menu needs to; one on a spot of its own stands by the screen.
local function HoldBlock()
	if menuHold or (lastPlacement ~= "row" and lastPlacement ~= "besideMicroMenu") then
		return
	end
	local x, y = CenterOf(block)
	local menuX, menuY = CenterOf(MicroMenuContainer)
	if not (x and menuX) then
		return
	end
	menuHold = { x = x, y = y, menuX = menuX, menuY = menuY }
	Layout()
end

-- When the micro menu is let go: if the player moved it away from where Blizzard's layout puts
-- it, the block keeps the spot where it stood, as if the player had put it there; otherwise it
-- goes back to standing by the micro menu.
local function ReleaseBlock()
	if not menuHold then
		return
	end
	local hold = menuHold
	menuHold = nil
	local menuX, menuY = CenterOf(MicroMenuContainer)
	local moved = menuX and (math.abs(menuX - hold.menuX) > 0.5 or math.abs(menuY - hold.menuY) > 0.5)
	if moved and not InDefaultPosition(MicroMenuContainer) and not saved.spot then
		saved.spot = { x = hold.x, y = hold.y }
	end
	Layout()
	UpdateDialog()
end

-- Where the player drops the block: back in its place when dropped by the micro menu's right
-- end (within a slot's size of where it stands in the row), else on its own right there.
local function OnDropped()
	dragging = false
	block:StopMovingOrSizing()
	local x, y = block:GetCenter()
	local toUIParent = BlockToUIParent()
	x, y = x * toUIParent, y * toUIParent
	local rowX, rowY = RowCenter()
	local reach = art.slotSize * toUIParent
	if rowX and math.abs(x - rowX) <= reach and math.abs(y - rowY) <= reach then
		saved.spot = nil
	else
		saved.spot = { x = x, y = y }
	end
	Layout()
	UpdateDialog()
end

editBox:SetScript("OnMouseDown", function(_, button)
	if button == "LeftButton" then
		Guarded(Select)
	end
end)
editBox:SetScript("OnDragStart", function()
	Guarded(function()
		dragging = true
		ShowEditBox(true)
		block:StartMoving()
	end)
end)
editBox:SetScript("OnDragStop", function()
	Guarded(OnDropped)
end)
editBox:SetScript("OnEnter", function(self)
	if selected then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
	GameTooltip:SetText(ADDON_TITLE)
	GameTooltip:AddLine(HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT, HIGHLIGHT_FONT_COLOR:GetRGB())
	GameTooltip:Show()
end)
editBox:SetScript("OnLeave", GameTooltip_Hide)

function Layout()
	-- Protected frames can't be moved in combat, so every change waits for the end of combat.
	if InCombatLockdown() then
		layoutPending = true
		return
	end
	layoutPending = false
	-- While the player drags the block, it stays in their hand; dropping it lays everything out.
	if dragging then
		return
	end

	local placement = Placement()
	local rowGrowth, bagsShift = 0, 0
	block:ClearAllPoints()
	if placement then
		-- The block takes the bags bar's size setting, times its own size, and stands on its level.
		block:SetScale((BagsBar and BagsBar:GetScale() or 1) * (saved.size or DEFAULT_SIZE) / DEFAULT_SIZE)
		if BagsBar then
			block:SetFrameStrata(BagsBar:GetFrameStrata())
			block:SetFrameLevel(BagsBar:GetFrameLevel())
		end
	end
	if placement == "row" then
		local point, relativePoint, x, y, bagsJoined = JoinToMicroMenu()
		block:SetPoint(point, MicroMenuContainer, relativePoint, BagsToBlock(x), BagsToBlock(y))
		rowGrowth = RowGrowth(x)
		if bagsJoined then
			bagsShift = rowGrowth
		end
	elseif placement == "besideMicroMenu" then
		SetBesideMicroMenu(JoinToMicroMenu())
	elseif placement == "spot" then
		block:SetPoint("CENTER", UIParent, "BOTTOMLEFT", InFrameUnits(saved.spot.x, block), InFrameUnits(saved.spot.y, block))
	elseif placement == "aboveXPBar" then
		block:SetPoint("CENTER", UIParent, "BOTTOM", 0, InFrameUnits(AboveXPBarHeight(), block))
	end
	if menuHold and placement then
		block:ClearAllPoints()
		block:SetPoint("CENTER", UIParent, "BOTTOMLEFT", InFrameUnits(menuHold.x, block), InFrameUnits(menuHold.y, block))
	end
	lastPlacement = placement
	block:SetShown(placement ~= nil)
	ShowEditBox(editModeOpen and placement ~= nil and not InGamepadInterface())
	if selected and not editBox:IsShown() then
		Deselect()
	end

	-- Grow evenly: each root of the row moves left by half, once; the bars stacked on it move
	-- right by half or stretch by the whole growth, and the bags bar moves right by the whole
	-- growth to join the block. Frames no longer in either set go back to where Blizzard put
	-- them.
	local shifts = {} -- frame -> shift in UIParent units
	local stretches = {} -- XP bar container -> added width in UIParent units
	if rowGrowth ~= 0 then
		for frame in pairs(RowRoots()) do
			shifts[frame] = -rowGrowth / 2
		end
		for _, bar in ipairs(ActionBarInRow() and BottomBars() or {}) do
			if IsStackedOnRow(bar) then
				if CanStretch(bar) then
					stretches[bar] = rowGrowth
				else
					shifts[bar] = rowGrowth / 2
				end
			end
		end
	end
	if bagsShift ~= 0 then
		shifts[BagsBar] = bagsShift
	end
	for frame in pairs(shifts) do
		RowMoverFor(frame)
	end
	for container in pairs(stretches) do
		XPBarStateFor(container)
	end
	for frame, mover in pairs(rowMovers) do
		mover:SetExtraX(InFrameUnits(shifts[frame] or 0, frame))
	end
	for container, state in pairs(xpBars) do
		state.extra = InFrameUnits(stretches[container] or 0, container)
		FitXPBar(container, state)
	end
end

local function OnEditModeEnter()
	editModeOpen = true
	editModeStart = { spot = CopySpot(saved.spot), size = saved.size }
	Layout()
end

local function OnEditModeExit()
	if dragging then
		OnDropped()
	end
	ReleaseBlock()
	Deselect()
	editModeStart = nil
	editModeOpen = false
	MeasureArt()
	DressBlock()
	Layout()
end

local function SetUp(events)
	local function Relayout()
		Guarded(Layout)
	end
	-- Where the block goes depends on the micro menu showing, on the gamepad interface (its
	-- buttons' frame, and the switch itself) and on where the XP bar is.
	for _, frame in pairs({ MicroMenu or MicroMenuContainer, GamepadMainActionBarFrame, MainStatusTrackingBarContainer }) do
		frame:HookScript("OnShow", Relayout)
		frame:HookScript("OnHide", Relayout)
	end
	events:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		Guarded(OnEditModeEnter)
	end, block)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		Guarded(OnEditModeExit)
	end, block)
	editModeOpen = EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() or false

	ticker = C_Timer.NewTicker(UPDATE_INTERVAL, Refresh)
	Guarded(function()
		MeasureArt()
		DressBlock()
		-- The micro menu and the bags bar are watched from the start: where Blizzard puts them
		-- decides where the block stands. So is the XP bar, for the gamepad interface.
		RowMoverFor(MicroMenuContainer)
		if BagsBar then
			RowMoverFor(BagsBar)
		end
		-- Selecting one of the game's bars in Edit Mode deselects the block, as it does the others,
		-- and so does Edit Mode clearing its selection (its dialog closed, a layout change). Selecting
		-- the micro menu makes the block let go of it; selecting anything else, or clearing the
		-- selection, lets the micro menu go.
		if EditModeManagerFrame and EditModeManagerFrame.SelectSystem then
			hooksecurefunc(EditModeManagerFrame, "SelectSystem", function(_, systemFrame)
				Guarded(function()
					if selected then
						Deselect()
					end
					if systemFrame == MicroMenuContainer then
						HoldBlock()
					else
						ReleaseBlock()
					end
				end)
			end)
		end
		if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
			hooksecurefunc(EditModeManagerFrame, "ClearSelectedSystem", function()
				Guarded(function()
					if selected then
						Deselect()
					end
					ReleaseBlock()
				end)
			end)
		end
		if MainStatusTrackingBarContainer and CanStretch(MainStatusTrackingBarContainer) then
			XPBarStateFor(MainStatusTrackingBarContainer)
		end
		WatchBottomBars()
		Layout()
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		saved = NormalizeSaved(AmILaggingDB)
		AmILaggingDB = saved
		-- The piece of the game the block can't do without: the micro menu it stands by.
		if MicroMenuContainer and MicroMenuContainer.GetPoint then
			SetUp(self)
		else
			SayProblem("can't find the game's micro menu, so the block is off.", "This version of the game may need an update of the addon.")
		end
	elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" or layoutPending then
		Guarded(Layout)
	end
end)
