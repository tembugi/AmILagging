-- Tests for AmILagging.lua: `luajit Tests/run.lua` in the addon folder. Exits non-zero when a
-- test fails.
--
-- Every function in the addon is local to its file, so each test loads the unchanged file into a
-- stand-in for the game and watches what it does to the frames. The stand-in is the bottom bar as
-- Camelot sets it up, copied from wow-ui-source (forever, 1.60.1): BagsBar.lua and
-- MainMenuBarBagManager.lua, Camelot's MainMenuBarBagButtons.xml, EditModeUtil.lua and
-- EditModePresetLayoutConstants.lua, EditModeSystemTemplates.lua (SetPointBase) and
-- EditModeManager.lua (how bars are stacked). Strings are from BlizzardInterfaceResources (enUS).
-- What it assumes beyond the game's code is marked ASSUMED: a stand-in that behaves better than
-- the game hides bugs.

-- This file runs under luajit, outside the game, and uses standard Lua's loadfile and io, which
-- the game doesn't have.
---@diagnostic disable: undefined-global, lowercase-global

local ADDON_FILE = "AmILagging.lua"
local SOURCE = assert(io.open(ADDON_FILE)):read("*a")

-- The addon's own numbers, read from its source, so the tests check its rules with its values.
local function Constant(name)
	return tonumber(SOURCE:match("\nlocal " .. name .. " = ([%d%.]+)"))
end
local FIGURE_RISE = Constant("FIGURE_RISE")
local FIGURE_DROP = Constant("FIGURE_DROP")
local BOX_ASCENT = Constant("BOX_ASCENT")
local BOX_DESCENT = Constant("BOX_DESCENT")
local SLOT_EDGE = Constant("SLOT_EDGE")
local NUMBER_MARGIN = Constant("NUMBER_MARGIN")
local NUMBER_SIZE = Constant("NUMBER_SIZE")
local LINE_THICKNESS = Constant("LINE_THICKNESS")

-- Blizzard's values (Camelot's MainMenuBarBagButtons.xml): the bag slots are 45 wide with a
-- 46 wide frame, and the bags bar keeps 2 between buttons.
local SLOT_SIZE = 45
local SLOT_FRAME_SIZE = 46
local BAG_PADDING = 2
-- ASSUMED: a player's UI scale and Edit Mode sizes, different from 1 so that mixing up units
-- shows. Bars and the bags bar take their own scale on top of UIParent's.
local UI_SCALE = 0.9
local BAGS_SCALE = 0.8
local STACKED_BAR_SCALE = 1.25
local XP_BAR_WIDTH = 571

--------------------------------------------------------------------------------
-- The stand-in
--------------------------------------------------------------------------------

local game -- this test's game: what the addon said, the errors, the ticker and the frames

local function CreateColorTable(r, g, b, a)
	local color = { r = r, g = g, b = b, a = a or 1 }
	function color:GetRGB()
		return self.r, self.g, self.b
	end
	function color:WrapTextInColorCode(text)
		return string.format("|c%02x%02x%02x%s|r", self.r * 255, self.g * 255, self.b * 255, text)
	end
	return color
end

-- OnShow and OnHide run when a frame becomes visible or stops being visible, also when that
-- comes from a parent: FloatingChatFrame.lua says that when the top-level parent is hidden
-- (Alt-Z), OnHide is called while IsShown() stays true. ASSUMED: a frame's script runs before
-- its children's.
local function VisibilityChanged(region, visible)
	local script = region.scripts[visible and "OnShow" or "OnHide"]
	if script then
		script(region)
	end
	for _, child in ipairs(region.children) do
		if child.shown then
			VisibilityChanged(child, visible)
		end
	end
end

local function NewRegion(parent)
	local region = { points = {}, width = 0, height = 0, scale = 1, shown = true, parent = parent, children = {}, scripts = {}, events = {}, textures = {}, fontStrings = {} }
	if parent then
		parent.children[#parent.children + 1] = region
	end

	-- Setting a point the region already has replaces it; others are kept.
	function region:SetPoint(point, relativeTo, relativePoint, x, y)
		point = point:upper()
		local anchor = { point, relativeTo or self.parent, (relativePoint or point):upper(), x or 0, y or 0 }
		for i, existing in ipairs(self.points) do
			if existing[1] == point then
				self.points[i] = anchor
				return
			end
		end
		self.points[#self.points + 1] = anchor
	end
	function region:ClearAllPoints()
		self.points = {}
	end
	function region:GetNumPoints()
		return #self.points
	end
	function region:GetPoint(index)
		local anchor = self.points[index or 1]
		if anchor then
			return unpack(anchor)
		end
	end
	-- ASSUMED: brokenPoints makes reading points fail, to see what the addon does when the game
	-- keeps failing under it.
	function region:GetPointByName(name)
		if game.brokenPoints then
			error("points failed")
		end
		for _, anchor in ipairs(self.points) do
			if anchor[1] == name then
				return unpack(anchor)
			end
		end
	end
	function region:SetAllPoints() end
	function region:SetSize(width, height)
		self.width, self.height = width, height
	end
	function region:SetWidth(width)
		self.width = width
	end
	function region:GetWidth()
		return self.width
	end
	function region:GetHeight()
		return self.height
	end
	function region:SetScale(scale)
		self.scale = scale
	end
	function region:GetEffectiveScale()
		return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1)
	end
	function region:IsShown()
		return self.shown
	end
	function region:IsVisible()
		return self.shown and (not self.parent or self.parent:IsVisible())
	end
	function region:GetParent()
		return self.parent
	end
	function region:SetParent(newParent)
		local wasVisible = self:IsVisible()
		if self.parent then
			for i, child in ipairs(self.parent.children) do
				if child == self then
					table.remove(self.parent.children, i)
					break
				end
			end
		end
		self.parent = newParent
		if newParent then
			newParent.children[#newParent.children + 1] = self
		end
		if self:IsVisible() ~= wasVisible then
			VisibilityChanged(self, not wasVisible)
		end
	end
	function region:SetShown(shown)
		shown = not not shown
		if shown == self.shown then
			return
		end
		local wasVisible = self:IsVisible()
		self.shown = shown
		if self:IsVisible() ~= wasVisible then
			VisibilityChanged(self, not wasVisible)
		end
	end
	function region:Show()
		self:SetShown(true)
	end
	function region:Hide()
		self:SetShown(false)
	end
	function region:SetScript(name, func)
		self.scripts[name] = func
	end
	function region:HookScript(name, func)
		local old = self.scripts[name]
		self.scripts[name] = function(...)
			if old then
				old(...)
			end
			func(...)
		end
	end
	function region:RegisterEvent(event)
		self.events[event] = true
	end
	function region:UnregisterEvent(event)
		self.events[event] = nil
	end
	function region:EnableMouse() end

	function region:CreateTexture()
		local texture = NewRegion(self)
		function texture:SetColorTexture() end
		function texture:SetAtlas(atlas)
			self.atlas = atlas
		end
		function texture:GetAtlas()
			return self.atlas
		end
		function texture:SetGradient(_, from, to)
			self.gradient = { from, to }
		end
		self.textures[#self.textures + 1] = texture
		return texture
	end

	function region:CreateFontString()
		local text = NewRegion(self)
		text.setTexts, text.setFonts = 0, 0
		function text:SetFont(font, size, flags)
			self.font = { font, size, flags }
			self.setFonts = self.setFonts + 1
		end
		function text:SetText(value)
			self.text = tostring(value)
			self.setTexts = self.setTexts + 1
		end
		function text:SetTextColor(r, g, b)
			self.color = { r, g, b }
		end
		-- ASSUMED: each figure is 0.55 of the font size wide (Skurri's figures are close to it).
		function text:GetStringWidth()
			return #(self.text or "") * 0.55 * self.font[2]
		end
		self.fontStrings[#self.fontStrings + 1] = text
		return text
	end

	return region
end

-- The frames Edit Mode manages keep their own SetPoint as SetPointBase and get Edit Mode's
-- SetPoint in its place (EditModeSystemMixin:OnSystemLoad). Edit Mode's version also updates
-- snapping; the stand-in only passes the point on.
local function EditModeSystem(parent)
	local frame = NewRegion(parent)
	frame.SetPointBase = frame.SetPoint
	frame.ClearAllPointsBase = frame.ClearAllPoints
	function frame:SetPoint(...)
		self:SetPointBase(...)
	end
	function frame:ClearAllPoints()
		self:ClearAllPointsBase()
	end
	return frame
end

local function NewXPBarContainer()
	local container = EditModeSystem(UIParent)
	container.width = XP_BAR_WIDTH
	container.resized = 0
	function container:ResizeContainerBars()
		self.resized = self.resized + 1
	end
	function container:UpdateDividers(segments)
		self.dividers = segments
	end
	-- ASSUMED: the number of tick-mark segments; the addon only passes it on.
	function container:GetExpectedSegments()
		return 20
	end
	return container
end

-- A new game for each test: Blizzard's frames, laid out as Camelot's default layout does,
-- then the addon loaded. Options change the game before the addon loads.
local function NewGame(options)
	options = options or {}
	game = { chat = {}, errors = {}, frames = {}, callbacks = {}, combat = false, editMode = false, net = { home = 50, world = 80 }, fps = 60, cpuBound = true, layoutErrors = 0, layouts = 0 }

	print = function(...)
		game.chat[#game.chat + 1] = table.concat({ ... }, " ")
	end
	format = string.format
	function wipe(t)
		for key in pairs(t) do
			t[key] = nil
		end
		return t
	end
	function tContains(list, value)
		for _, item in ipairs(list) do
			if item == value then
				return true
			end
		end
		return false
	end
	-- The game's math.round, for the positive numbers the addon rounds.
	function Round(value)
		return math.floor(value + 0.5)
	end
	function CallErrorHandler(message)
		game.errors[#game.errors + 1] = tostring(message)
	end
	-- hooksecurefunc runs the hook after the original, with the same arguments.
	function hooksecurefunc(owner, name, hook)
		local original = owner[name]
		owner[name] = function(...)
			local results = { original(...) }
			hook(...)
			return unpack(results)
		end
	end
	function InCombatLockdown()
		return game.combat
	end
	function GetNetStats()
		if game.net.fail then
			error("no stats")
		end
		return 0, 0, game.net.home, game.net.world
	end
	function GetFramerate()
		return game.fps
	end
	function IsCpuBound()
		return game.cpuBound
	end

	CreateColor = CreateColorTable
	NORMAL_FONT_COLOR = CreateColor(1, 0.82, 0)
	RED_FONT_COLOR = CreateColor(1, 0.1, 0.1)
	HIGHLIGHT_FONT_COLOR = CreateColor(1, 1, 1)
	GRAY_FONT_COLOR = CreateColor(0.5, 0.5, 0.5)
	STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
	NumberFont_Outline_Huge = { GetFont = function() return "Fonts\\SKURRI.TTF", 30, "THICKOUTLINE" end }
	MAINMENUBAR_FPS_LABEL = "Framerate: %.0f fps"
	MAINMENUBAR_LATENCY_LABEL = "Latency:\n%.0f ms (home)\n%.0f ms (world)"

	game.tooltip = {}
	GameTooltip = {}
	function GameTooltip:AddLine(text)
		game.tooltip[#game.tooltip + 1] = text
	end
	function GameTooltip:Show() end
	function GameTooltip_SetDefaultAnchor() end
	function GameTooltip_SetTitle(_, text)
		game.tooltip = { text }
	end
	function GameTooltip_AddBlankLineToTooltip()
		game.tooltip[#game.tooltip + 1] = " "
	end
	function GameTooltip_Hide() end

	C_Timer = {}
	function C_Timer.NewTicker(_, func)
		local ticker = { func = func }
		function ticker:Cancel()
			self.cancelled = true
		end
		game.ticker = ticker
		return ticker
	end
	EventRegistry = {}
	function EventRegistry:RegisterCallback(event, func)
		game.callbacks[event] = func
	end
	function CreateFrame(_, _, parent)
		local frame = NewRegion(parent)
		game.frames[#game.frames + 1] = frame
		return frame
	end

	UIParent = NewRegion(nil)
	UIParent.scale = UI_SCALE

	-- The bottom row: the micro menu hangs off the screen, the main action bar off the micro
	-- menu, the bags bar off its right side (Camelot's preset layout constants).
	MicroMenuContainer = EditModeSystem(UIParent)
	MicroMenuContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 116.5, 6)
	MainActionBar = EditModeSystem(UIParent)
	MainActionBar:SetPoint("BOTTOMRIGHT", MicroMenuContainer, "BOTTOMLEFT", -4.5, -4)
	BagsBar = EditModeSystem(UIParent)
	BagsBar.scale = BAGS_SCALE
	BagsBar.isHorizontal = true
	BagsBar.bagPadding = BAG_PADDING
	BagsBar:SetPoint("BOTTOMLEFT", MicroMenuContainer, "BOTTOMRIGHT", 7, -4)
	function BagsBar:IsHorizontal()
		return self.isHorizontal
	end
	-- Lays out the buttons in its list (not modeled). ASSUMED: layoutErrors makes it fail, to
	-- see what the addon does when Blizzard's code breaks under it.
	function BagsBar:Layout()
		game.layouts = game.layouts + 1
		if game.layoutErrors > 0 then
			game.layoutErrors = game.layoutErrors - 1
			error("layout failed")
		end
	end

	CharacterReagentBag0Slot = NewRegion(BagsBar)
	CharacterReagentBag0Slot.width = SLOT_SIZE
	local slotFrame = CharacterReagentBag0Slot:CreateTexture()
	slotFrame.atlas, slotFrame.width = "UI-HUD-ActionBar-IconFrame", SLOT_FRAME_SIZE
	function CharacterReagentBag0Slot:GetNormalTexture()
		return slotFrame
	end
	MainMenuBarBagManager = { allBagButtons = { "backpack", "bag 1", "bag 2", "bag 3", "bag 4", CharacterReagentBag0Slot, "keyring" } }
	function MainMenuBarBagManager:RegisterBagButton(bagButton)
		if not tContains(self.allBagButtons, bagButton) then
			table.insert(self.allBagButtons, bagButton)
		end
	end
	game.blizzardBagButtons = { unpack(MainMenuBarBagManager.allBagButtons) }

	-- The bars Camelot stacks on the main action bar by their left edge
	-- (UpdateBottomActionBarPositions with ACTION_BARS_RELATIVE_TO_BASE_POSITIONING).
	SecondaryStatusTrackingBarContainer = NewXPBarContainer()
	MainStatusTrackingBarContainer = NewXPBarContainer()
	local stacked = { "MultiBarBottomRight", "MultiBarBottomLeft", "StanceBar", "PetActionBar", "PossessActionBar", "MainMenuBarVehicleLeaveButton" }
	for _, name in ipairs(stacked) do
		_G[name] = EditModeSystem(UIParent)
		_G[name].scale = STACKED_BAR_SCALE
	end
	local y = 0
	for _, bar in ipairs({ SecondaryStatusTrackingBarContainer, MainStatusTrackingBarContainer, MultiBarBottomRight, MultiBarBottomLeft, StanceBar, PetActionBar, PossessActionBar, MainMenuBarVehicleLeaveButton }) do
		y = y + 20
		bar:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 0, y)
	end
	Enum = { InputDeviceInterfaceType = { Gamepad = 1 } }
	EditModeManagerFrame = {}
	function EditModeManagerFrame:IsEditModeActive()
		return game.editMode
	end
	function EditModeManagerFrame:GetActiveLayoutInfo()
		return {}
	end
	EditModeUtil = {}
	function EditModeUtil.GetBottomActionBars()
		local activeLayoutInfo = EditModeManagerFrame:GetActiveLayoutInfo()
		if activeLayoutInfo and (activeLayoutInfo.interfaceStyle == Enum.InputDeviceInterfaceType.Gamepad) then
			return {}
		end
		return {
			MainActionBar,
			SecondaryStatusTrackingBarContainer,
			MainStatusTrackingBarContainer,
			MultiBarBottomRight,
			MultiBarBottomLeft,
			StanceBar,
			PetActionBar,
			PossessActionBar,
			MainMenuBarVehicleLeaveButton,
		}
	end

	if options.before then
		options.before()
	end
	assert(loadfile(ADDON_FILE))("AmILagging", {})
	-- The addon's frames, in the order it makes them: the block, then its event frame.
	game.block = game.frames[1]
	game.fpsText, game.worldText = game.block.fontStrings[1], game.block.fontStrings[2]
	game.slotFrame, game.lineLeft = game.block.textures[2], game.block.textures[3]
	return game
end

local function FireEvent(event)
	for _, frame in ipairs(game.frames) do
		if frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event)
		end
	end
end

local function Login()
	FireEvent("PLAYER_LOGIN")
end

local function Tick()
	game.ticker.func()
end

local function InBagsBar()
	return tContains(MainMenuBarBagManager.allBagButtons, game.block)
end

local function OffsetX(frame, point)
	local _, _, _, x = frame:GetPointByName(point or "BOTTOMLEFT")
	return x
end

-- How much wider the block makes the row, in UIParent units: the block and the bags bar's
-- spacing, at the bags bar's scale.
local GROWTH = (SLOT_SIZE + BAG_PADDING) * BAGS_SCALE

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

local failures = 0

local function Test(name, func)
	local ok, problem = pcall(func)
	if ok then
		io.write("ok    " .. name .. "\n")
	else
		failures = failures + 1
		io.write("FAIL  " .. name .. ": " .. tostring(problem) .. "\n")
	end
end

local function Equal(actual, expected, what)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
	end
end

local function Near(actual, expected, what)
	if type(actual) ~= "number" or math.abs(actual - expected) > 1e-6 then
		error(string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
	end
end

local function ColorName(r, g, b)
	return ({ ["0,1,0"] = "green", ["1,1,0"] = "yellow", ["1,0,0"] = "red" })[table.concat({ r, g, b }, ",")] or "other"
end

Test("the version matches the .toc", function()
	local toc = assert(io.open("AmILagging.toc")):read("*a")
	Equal(SOURCE:match('\nlocal VERSION = "([^"]+)"'), toc:match("## Version: (%S+)"), "VERSION")
end)

Test("latency is green up to 300 ms, yellow over 300 and red over 600", function()
	NewGame()
	Login()
	for _, case in ipairs({ { 0, "green" }, { 300, "green" }, { 301, "yellow" }, { 600, "yellow" }, { 601, "red" }, { 4000, "red" } }) do
		game.net.world, game.net.home = case[1], case[1]
		Tick()
		Equal(ColorName(unpack(game.worldText.color)), case[2], case[1] .. " ms number")
		Equal(ColorName(game.lineLeft.gradient[2]:GetRGB()), case[2], case[1] .. " ms line")
	end
end)

Test("the line follows home latency, the number world latency", function()
	NewGame()
	Login()
	game.net.home, game.net.world = 700, 100
	Tick()
	Equal(ColorName(unpack(game.worldText.color)), "green", "number")
	Equal(ColorName(game.lineLeft.gradient[2]:GetRGB()), "red", "line")
	Equal(game.worldText.text, "100", "world latency shown")
	Equal(game.fpsText.text, "60", "framerate shown")
end)

Test("a number that didn't change is left alone", function()
	NewGame()
	Login()
	local texts, fonts = game.fpsText.setTexts, game.fpsText.setFonts
	Tick()
	Tick()
	Equal(game.fpsText.setTexts, texts, "framerate set again")
	Equal(game.fpsText.setFonts, fonts, "font set again")
	game.fps = 59.6
	Tick()
	Equal(game.fpsText.text, "60", "rounded framerate")
	Equal(game.fpsText.setTexts, texts, "same number after rounding set again")
	game.fps = 72
	Tick()
	Equal(game.fpsText.text, "72", "new framerate")
end)

Test("no updates while the block is hidden", function()
	NewGame()
	Login()
	local texts = game.fpsText.setTexts
	BagsBar:Hide()
	game.fps = 30
	Tick()
	Equal(game.fpsText.setTexts, texts, "updated while hidden")
	BagsBar:Show()
	Tick()
	Equal(game.fpsText.text, "30", "updated when shown again")
end)

Test("a four-digit latency shrinks to fit the slot, and grows back", function()
	NewGame()
	Login()
	local room = SLOT_SIZE - 2 * NUMBER_MARGIN
	game.net.world = 1234
	Tick()
	Near(game.worldText:GetStringWidth(), room, "shrunk width")
	game.net.world = 120
	Tick()
	Equal(game.worldText.font[2], NUMBER_SIZE, "size back")
	Equal(game.worldText.font[1], "Fonts\\SKURRI.TTF", "the game's number font")
end)

Test("each number has the same gap to the line as to the border, and touches neither", function()
	NewGame()
	Login()
	local border = SLOT_SIZE / 2 - SLOT_EDGE
	local line = LINE_THICKNESS / 2
	for _, world in ipairs({ 80, 1234 }) do
		game.net.world = world
		Tick()
		-- Above the line: the box's bottom is at y, the baseline above it by the box's descent.
		local size = game.fpsText.font[2]
		local point, relativeTo, relativePoint, _, y = game.fpsText:GetPoint(1)
		Equal(point .. " " .. relativePoint, "BOTTOM CENTER", "framerate anchor")
		Equal(relativeTo, game.slotFrame, "framerate on the slot art")
		local baseline = y + BOX_DESCENT * size
		local lowest, highest = baseline - FIGURE_DROP * size, baseline + FIGURE_RISE * size
		Near(lowest - line, border - highest, "framerate gaps")
		Equal(lowest - line > 0, true, "framerate clear of the line")
		-- Below the line: the box's top is at y, the baseline below it by the box's ascent.
		size = game.worldText.font[2]
		point, relativeTo, relativePoint, _, y = game.worldText:GetPoint(1)
		Equal(point .. " " .. relativePoint, "TOP CENTER", "latency anchor")
		baseline = y - BOX_ASCENT * size
		lowest, highest = baseline - FIGURE_DROP * size, baseline + FIGURE_RISE * size
		Near(-line - highest, lowest + border, world .. " ms gaps")
		Equal(-line - highest > 0, true, world .. " ms clear of the line")
	end
end)

Test("if reading the numbers fails, they clear, stop and say so once", function()
	NewGame()
	Login()
	game.net.fail = true
	Tick()
	Equal(game.fpsText.text, "", "framerate cleared")
	Equal(game.worldText.text, "", "latency cleared")
	Equal(game.ticker.cancelled, true, "updates stopped")
	Equal(#game.errors, 1, "errors reported")
	Equal(#game.chat, 1, "chat lines")
	local gold = NORMAL_FONT_COLOR:WrapTextInColorCode("Am I Lagging?")
	local red = RED_FONT_COLOR:WrapTextInColorCode("couldn't")
	Equal(game.chat[1]:sub(1, #gold + 2 + #red - 2), gold .. ": " .. red:sub(1, -3), "gold name, then red")
	Tick()
	Equal(#game.chat, 1, "chat lines after another tick")
end)

Test("the tooltip shows the game's lines and leaves out what the game doesn't know", function()
	NewGame()
	Login()
	game.block:UpdateTooltip()
	local version = SOURCE:match('\nlocal VERSION = "([^"]+)"')
	Equal(table.concat(game.tooltip, "|"), "Am I Lagging?| |Framerate: 60 fps|Limited by: CPU| |Latency:\n50 ms (home)\n80 ms (world)| |v" .. version, "lines")
	game.cpuBound = false
	game.block:UpdateTooltip()
	Equal(game.tooltip[4], "Limited by: GPU", "GPU line")
	game.cpuBound = nil
	game.block:UpdateTooltip()
	Equal(game.tooltip[4], " ", "no limited-by line")
end)

Test("the block joins the bags bar as its last button, dressed from the reagent slot", function()
	NewGame()
	Login()
	local buttons = MainMenuBarBagManager.allBagButtons
	Equal(buttons[#buttons], game.block, "last button")
	Equal(#buttons, #game.blizzardBagButtons + 1, "buttons")
	Equal(game.block.parent, BagsBar, "parent")
	Equal(game.block:GetWidth(), SLOT_SIZE, "size")
	Equal(game.slotFrame.atlas, "UI-HUD-ActionBar-IconFrame", "frame art")
	Equal(game.slotFrame:GetWidth(), SLOT_FRAME_SIZE, "frame art size")
	Equal(game.layouts > 0, true, "bags bar laid out")
end)

Test("the row grows evenly: the row moves left by half, the bars above move right by half or stretch", function()
	NewGame()
	Login()
	-- The micro menu hangs off the screen, so it is the row's root; the action bar hangs off it.
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu, in its own units")
	Near(OffsetX(MainActionBar, "BOTTOMRIGHT"), -4.5, "action bar stays on the micro menu")
	-- Stacked bars convert UIParent units to their own scale.
	Near(OffsetX(MultiBarBottomLeft), GROWTH / 2 / STACKED_BAR_SCALE, "stacked bar")
	Near(OffsetX(MainMenuBarVehicleLeaveButton), GROWTH / 2 / STACKED_BAR_SCALE, "vehicle exit button")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH + GROWTH, "XP bar")
	Equal(MainStatusTrackingBarContainer.resized > 0 and MainStatusTrackingBarContainer.dividers, 20, "XP bar fitted with Blizzard's methods")
	Near(OffsetX(MainStatusTrackingBarContainer), 0, "XP bar stays on the left end")
end)

Test("a bar the player moved elsewhere is left alone", function()
	NewGame({ before = function()
		MultiBarBottomRight:ClearAllPoints()
		MultiBarBottomRight:SetPoint("CENTER", UIParent, "CENTER", 10, 0)
	end })
	Login()
	Equal(OffsetX(MultiBarBottomRight, "CENTER"), 10, "moved bar")
	Near(OffsetX(MultiBarBottomLeft), GROWTH / 2 / STACKED_BAR_SCALE, "stacked bar")
end)

Test("when Blizzard places a frame again, the move goes on top of Blizzard's new point", function()
	NewGame()
	Login()
	-- UpdateBottomActionBarPositions clears and sets each stacked bar.
	MultiBarBottomLeft:ClearAllPoints()
	MultiBarBottomLeft:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 3, 80)
	Near(OffsetX(MultiBarBottomLeft), 3 + GROWTH / 2 / STACKED_BAR_SCALE, "stacked bar")
	-- Edit Mode snaps a frame to two others by setting two points, one after the other.
	MicroMenuContainer:ClearAllPoints()
	MicroMenuContainer:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 100, 0)
	MicroMenuContainer:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -900)
	Near(OffsetX(MicroMenuContainer, "BOTTOMLEFT"), 100 - GROWTH / 2, "first point")
	Near(OffsetX(MicroMenuContainer, "TOPLEFT"), 100 - GROWTH / 2, "second point")
	-- The Size setting resizes the XP bar: the new width is the base for the stretch.
	MainStatusTrackingBarContainer:SetWidth(600)
	Near(MainStatusTrackingBarContainer:GetWidth(), 600 + GROWTH, "resized XP bar")
end)

Test("in Edit Mode the bar is exactly the layout's, and it comes back after", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	Equal(InBagsBar(), false, "block in the bags bar")
	Equal(table.concat(MainMenuBarBagManager.allBagButtons, ",", 1, 5) .. #MainMenuBarBagManager.allBagButtons, table.concat(game.blizzardBagButtons, ",", 1, 5) .. #game.blizzardBagButtons, "Blizzard's own list")
	Equal(game.block:IsShown(), false, "block shown")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu")
	Near(OffsetX(MultiBarBottomLeft), 0, "stacked bar")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH, "XP bar")
	game.callbacks["EditMode.Exit"]()
	Equal(InBagsBar(), true, "block back")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu after")
end)

Test("starting in Edit Mode keeps the block out until it closes", function()
	NewGame({ before = function() game.editMode = true end })
	Login()
	Equal(InBagsBar(), false, "block in the bags bar")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu")
end)

Test("in combat every change waits for the end of combat", function()
	NewGame()
	Login()
	game.combat = true
	BagsBar:Hide()
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu in combat")
	MainStatusTrackingBarContainer:SetWidth(600)
	Equal(MainStatusTrackingBarContainer:GetWidth(), 600, "XP bar in combat")
	game.combat = false
	FireEvent("PLAYER_REGEN_ENABLED")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu after combat (bags hidden)")
	Near(MainStatusTrackingBarContainer:GetWidth(), 600, "XP bar after combat (bags hidden)")
end)

Test("the row grows only when the bags bar runs sideways off the micro menu's right side", function()
	NewGame()
	Login()
	BagsBar.isHorizontal = false
	BagsBar:SetPoint("BOTTOMLEFT", MicroMenuContainer, "BOTTOMRIGHT", 7, -4)
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "vertical bags bar")
	BagsBar.isHorizontal = true
	BagsBar:ClearAllPoints()
	BagsBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "bags bar on the screen's corner")
	BagsBar:ClearAllPoints()
	BagsBar:SetPoint("BOTTOMLEFT", MicroMenuContainer, "BOTTOMRIGHT", 7, -4)
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "back on the micro menu")
end)

-- ASSUMED: how another addon hides the bags bar. Parenting a Blizzard bar to a hidden frame of
-- its own is a common way; the bar then stays shown but isn't on screen.
Test("a bags bar another addon hid by parenting it to a hidden frame doesn't grow the row", function()
	NewGame()
	Login()
	local hiddenFrame = CreateFrame("Frame", nil, UIParent)
	hiddenFrame:Hide()
	BagsBar:SetParent(hiddenFrame)
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu with the bags bar hidden")
	Near(OffsetX(MultiBarBottomLeft), 0, "stacked bar with the bags bar hidden")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH, "XP bar with the bags bar hidden")
	BagsBar:SetParent(UIParent)
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu with the bags bar back")
end)

Test("hiding the whole interface (Alt+Z) moves nothing", function()
	NewGame()
	Login()
	UIParent:Hide()
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu while the interface is hidden")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH + GROWTH, "XP bar while the interface is hidden")
	UIParent:Show()
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu after")
end)

Test("if making room fails, the bar goes back to the game's and it says so once", function()
	NewGame({ before = function() game.layoutErrors = 1 end })
	Login()
	Equal(#game.errors, 1, "errors reported")
	Equal(#game.chat, 1, "chat lines")
	Equal(InBagsBar(), false, "block in the bags bar")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu")
	-- Later moves keep the bar as the game set it, without more messages.
	MultiBarBottomLeft:ClearAllPoints()
	MultiBarBottomLeft:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 0, 80)
	BagsBar:Hide()
	BagsBar:Show()
	Near(OffsetX(MultiBarBottomLeft), 0, "stacked bar")
	Equal(InBagsBar(), false, "block in the bags bar after")
	Equal(#game.chat, 1, "chat lines after")
end)

Test("if even putting the bar back fails, the addon leaves the bar alone", function()
	NewGame({ before = function() game.layoutErrors = 2 end })
	Login()
	Equal(#game.errors, 2, "errors reported")
	Equal(#game.chat, 1, "chat lines")
	local layouts = game.layouts
	BagsBar:Hide()
	BagsBar:Show()
	MainStatusTrackingBarContainer:SetWidth(600)
	Equal(game.layouts, layouts, "bags bar laid out again")
	Equal(MainStatusTrackingBarContainer:GetWidth(), 600, "XP bar")
	-- Its hooks stay quiet even while the game keeps failing.
	game.brokenPoints = true
	MultiBarBottomLeft:ClearAllPoints()
	MultiBarBottomLeft:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 0, 80)
	Equal(#game.errors, 2, "errors reported after")
	Equal(#game.chat, 1, "chat lines after")
end)

Test("without the bags bar it says so and stays off", function()
	NewGame({ before = function() BagsBar = nil end })
	Login()
	Equal(#game.chat, 1, "chat lines")
	Equal(game.chat[1]:find("bags bar", 1, true) ~= nil, true, "names the bags bar")
	Equal(game.ticker, nil, "updates")
end)

if failures > 0 then
	io.write(failures .. " failed\n")
	os.exit(1)
end
io.write("all passed\n")
