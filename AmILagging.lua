-- Keep equal to ## Version in the .toc. The game reads the .toc only at client start,
-- so the tooltip uses this, which /reload picks up.
local VERSION = "1.1.4"
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

-- The block is a slot of the bags bar, dressed like the slots beside it. Its art and size are
-- read from the game's own frames at login (see MeasureArt); these are only the values
-- Blizzard's XML sets today, used if a frame is missing.
local art = {
	slotSize = 45,
	slotFrame = "UI-HUD-ActionBar-IconFrame",
	slotFrameSize = 46,
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
block:Hide()

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

-- Read the art from the frame the block stands among: the size and plain gray frame art of
-- the reagent bag slot (regular bag slots wear a gold frame).
local function MeasureArt()
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
	slotFrame:SetAtlas(art.slotFrame)
	slotFrame:SetSize(art.slotFrameSize, art.slotFrameSize)
	-- Lay the numbers out again for the new size.
	fpsText.value, fpsText.placedSize = nil, nil
	worldText.value, worldText.placedSize = nil, nil
end

-- The bags bar and the game call these on every button in the bags bar's list. The block is
-- square, always shown and can't be bound to a key, so it has nothing to do. (The backpack's
-- Azerite tutorial would also ask each button for its bag; Azerite items don't exist here.)
function block:UpdateOrientation() -- the bags bar turned
end

function block:SetBarExpanded() -- the bags bar opened or closed
end

function block:DoModeChange() -- Quick Keybind mode started or ended
end

-- Making room on the bar. The block joins the bags bar the way the keyring does: it goes in the
-- bags bar's own list of buttons, so the bags bar places it, spaces it and draws the divider
-- beside it like its other buttons, and widens itself to hold it. Buttons stand in the order
-- they joined, from the backpack outwards; the block joins last, so it is the first slot of
-- the bar: right of the micro menu, left of the keyring.
-- Edit Mode puts the row at a fixed spot, so a wider bags bar would make the row lean right.
-- When the bags hang off the micro menu, the whole row moves left by half the growth, so it
-- grows evenly on both sides and stays centered. What "the whole row" hangs off depends on the
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
local inBagsBar = false
local rowMovers = {} -- frame -> mover, for the frames moved so far
local xpBars = {} -- XP bar container -> its stretch
local Layout

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

-- Whether the bags bar is on screen: shown, with every frame above it up to the interface
-- shown too. Another addon may hide the bar by parenting it to a hidden frame, so it stays
-- shown but isn't seen. Hiding the whole interface (Alt+Z) hides UIParent and nothing else;
-- the bar comes back with it, so that changes nothing.
local function BagsBarOnScreen()
	local frame = BagsBar
	while frame and frame ~= UIParent do
		if not frame:IsShown() then
			return false
		end
		frame = frame:GetParent()
	end
	return true
end

-- How much wider the block makes the row, in UIParent units: the block and the bags bar's
-- spacing, at the bags bar's scale. Only a bags bar on screen that runs sideways from the
-- micro menu's right side widens the row.
local function RowGrowth()
	if not inBagsBar or not BagsBarOnScreen() or not BagsBar:IsHorizontal() then
		return 0
	end
	local point, relativeTo = BagsBar:GetPoint(1)
	if relativeTo ~= MicroMenuContainer or not point or not point:find("LEFT") then
		return 0
	end
	return (block:GetWidth() + (BagsBar.bagPadding or 0)) * BagsBar:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Offsets and widths are in each frame's own scale.
local function InFrameUnits(value, frame)
	return value * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
end

function Layout()
	-- Protected frames can't be moved in combat, so every change waits for the end of combat.
	if InCombatLockdown() then
		layoutPending = true
		return
	end
	layoutPending = false

	JoinBagsBar(not editModeOpen and not failure)
	local rowGrowth = RowGrowth()

	-- Grow evenly: each root of the row moves left by half, once; the bars stacked on it move
	-- right by half or stretch by the whole growth. Frames no longer in either set go back to
	-- where Blizzard put them.
	local shifts = {} -- frame -> shift in UIParent units
	local stretches = {} -- XP bar container -> added width in UIParent units
	if rowGrowth ~= 0 then
		for frame in pairs(RowRoots()) do
			shifts[frame] = -rowGrowth / 2
		end
		for _, bar in ipairs(BottomBars()) do
			if IsStackedOnRow(bar) then
				if CanStretch(bar) then
					stretches[bar] = rowGrowth
				else
					shifts[bar] = rowGrowth / 2
				end
			end
		end
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
	Layout()
end

local function OnEditModeExit()
	editModeOpen = false
	MeasureArt()
	DressBlock()
	Layout()
end

local function SetUp()
	-- A child of the bags bar, so it takes the bar's scale and hides with it.
	block:SetParent(BagsBar)
	-- Where the bags bar hangs, and whether it shows, decide whether the row grows.
	local function Relayout()
		Guarded(Layout)
	end
	hooksecurefunc(BagsBar, "SetPoint", Relayout)
	BagsBar:HookScript("OnShow", Relayout)
	BagsBar:HookScript("OnHide", Relayout)
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
		WatchBottomBars()
		Layout()
	end)
end

-- The pieces of the game the block can't do without.
local function CanJoinBagsBar()
	return BagsBar and BagsBar.Layout and BagsBar.IsHorizontal
		and MainMenuBarBagManager and MainMenuBarBagManager.RegisterBagButton
		and type(MainMenuBarBagManager.allBagButtons) == "table"
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		if CanJoinBagsBar() then
			SetUp()
		else
			SayProblem("can't find the game's bags bar, so the block is off.", "This version of the game may need an update of the addon.")
		end
	elseif layoutPending then
		Guarded(Layout)
	end
end)
