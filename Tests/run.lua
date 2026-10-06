-- Tests for AmILagging.lua: `luajit Tests/run.lua` in the addon folder. Exits non-zero when a
-- test fails.
--
-- Every function in the addon is local to its file, so each test loads the unchanged file into a
-- stand-in for the game and watches what it does to the frames. The stand-in is the bottom bar as
-- Camelot sets it up, copied from wow-ui-source (forever, 1.60.1): Camelot's
-- MainMenuBarBagButtons.xml (the bags bar and its frame art) and MainMenuBarMicroMenu.xml (the
-- micro menu's frame art), EditModeUtil.lua and EditModePresetLayoutConstants.lua (how the row
-- hangs together), EditModeSystemTemplates.lua (SetPointBase), EditModeManager.lua (how bars are
-- stacked), MainActionBar.lua (what the gamepad interface hides), the gamepad action bars'
-- MainActionBarFrame.xml and StatusTrackingBarConstants.lua. Strings and the gamepad API are from
-- BlizzardInterfaceResources (enUS).
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

-- Blizzard's values. Camelot's MainMenuBarBagButtons.xml: the bag slots are 45 wide with a 46
-- wide frame, and the bags bar's frame art reaches 6 past its buttons on the left and top, 5 on
-- the right and bottom. MainMenuBarMicroMenu.xml: the micro menu's frame art reaches 8 past it.
-- EditModePresetLayoutConstants.lua: the bags bar hangs off the micro menu's bottom right, 7 to
-- the right and 4 down.
local SLOT_SIZE = 45
local SLOT_FRAME_SIZE = 46
local BAR_REACH_LEFT, BAR_REACH_TOP, BAR_REACH_RIGHT, BAR_REACH_BOTTOM = 6, 6, 5, 5
local MICRO_MENU_REACH = 8
local BAGS_JOIN_X, BAGS_JOIN_Y = 7, -4
-- The gamepad action bars' frame stands 110 above the screen's bottom (MainActionBarFrame.xml);
-- the XP bar is 17 tall (StatusTrackingBarConstants.lua). ASSUMED: in the gamepad interface the
-- XP bar sits on the screen's bottom edge, as in the player's screenshot.
local GAMEPAD_BUTTONS_BOTTOM = 110
local XP_BAR_HEIGHT = 17
-- ASSUMED: the screen and the micro menu's edges in UIParent units (the stand-in doesn't lay frames
-- out; the micro menu has the same scale as UIParent).
local SCREEN_WIDTH, SCREEN_HEIGHT = 1600, 900
local MICRO_MENU_LEFT, MICRO_MENU_RIGHT, MICRO_MENU_BOTTOM, MICRO_MENU_TOP = 700, 1000, 10, 50
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

	-- Setting a point the region already has replaces it; others are kept. Like the game,
	-- SetPoint(point, x, y) anchors to the parent's same point.
	function region:SetPoint(point, relativeTo, relativePoint, x, y)
		if type(relativeTo) == "number" then
			relativeTo, relativePoint, x, y = nil, nil, relativeTo, relativePoint
		end
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
	function region:GetScale()
		return self.scale
	end
	function region:GetEffectiveScale()
		return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1)
	end
	-- ASSUMED: the stand-in doesn't lay frames out; a test gives a frame its edges in its own
	-- units when the addon reads them.
	function region:GetTop()
		return self.top
	end
	function region:GetBottom()
		return self.bottom
	end
	function region:GetLeft()
		return self.left
	end
	function region:GetRight()
		return self.right
	end
	-- ASSUMED: where a dragged frame ends up is set by the test, as the client moves it under the
	-- mouse.
	function region:GetCenter()
		return self.centerX, self.centerY
	end
	function region:SetMovable(movable)
		self.movable = movable
	end
	function region:SetClampedToScreen(clamped)
		self.clamped = clamped
	end
	function region:SetClampRectInsets(left, right, top, bottom)
		self.clampInsets = { left, right, top, bottom }
	end
	function region:RegisterForDrag(button)
		self.dragButton = button
	end
	function region:EnableKeyboard(enabled)
		self.keyboard = enabled
	end
	function region:SetPropagateKeyboardInput(propagate)
		self.propagate = propagate
	end
	-- The client refuses to move a frame that isn't movable.
	function region:StartMoving()
		assert(self.movable, "Frame is not movable")
		self.moving = true
	end
	function region:StopMovingOrSizing()
		self.moving = false
	end
	function region:SetFrameStrata(strata)
		self.strata = strata
	end
	function region:GetFrameStrata()
		return self.strata or "MEDIUM"
	end
	function region:SetFrameLevel(level)
		self.level = level
	end
	function region:GetFrameLevel()
		return self.level or 0
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
		function texture:SetTexture(file)
			self.file = file
		end
		function texture:GetTexture()
			return self.file
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
		function text:SetJustifyH(justify)
			self.justify = justify
		end
		function text:SetFontObject(fontObject)
			self.fontObject = fontObject
		end
		function text:GetFontObject()
			return self.fontObject
		end
		-- ASSUMED: one line of text is 16 high; the addon only sizes its dialog with it.
		function text:GetStringHeight()
			return 16
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
-- snapping; the stand-in only passes the point on. ASSUMED: moveErrors makes the next moves
-- fail, to see what the addon does when the game breaks under it.
local function EditModeSystem(parent)
	local frame = NewRegion(parent)
	local setPoint = frame.SetPoint
	function frame:SetPointBase(...)
		if game.moveErrors > 0 then
			game.moveErrors = game.moveErrors - 1
			error("move failed")
		end
		setPoint(self, ...)
	end
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
	game = { chat = {}, errors = {}, frames = {}, callbacks = {}, combat = false, editMode = false, net = { home = 50, world = 80 }, fps = 60, cpuBound = true, gamepad = false, moveErrors = 0, microMenuMoved = false }
	-- The saved data as the game loads it before the addon's code runs; a test sets it in before().
	AmILaggingDB = nil

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
	function IsShiftKeyDown()
		return game.shift
	end
	game.sounds = {}
	function PlaySound(soundKit)
		game.sounds[#game.sounds + 1] = soundKit
	end
	SOUNDKIT = { IG_MAINMENU_CLOSE = 851 }
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
	function GameTooltip:SetOwner(owner)
		game.tooltipOwner = owner
	end
	function GameTooltip:SetText(text)
		game.tooltip = { text }
	end
	game.tooltipShown = false
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
	function CreateFrame(_, _, parent, template)
		local frame = NewRegion(parent)
		frame.template = template
		game.frames[#game.frames + 1] = frame
		template = template or ""
		-- UIPanelButtonTemplate and UIButtonTemplate (UIButtonTemplate.lua): text, enabled
		-- state and SetOnClickHandler.
		if template:find("UIPanelButtonTemplate", 1, true) then
			frame.enabled = true
			function frame:SetText(text)
				self.text = text
			end
			function frame:GetText()
				return self.text
			end
			function frame:SetEnabled(enabled)
				self.enabled = not not enabled
			end
			function frame:IsEnabled()
				return self.enabled
			end
			function frame:SetOnClickHandler(handler)
				self.onClick = handler
			end
		end
		-- MinimalSliderWithSteppersTemplate (MinimalSlider.lua): Init sets the value without telling
		-- its callbacks; the player moving it tells them the new value.
		if template:find("MinimalSliderWithSteppersTemplate", 1, true) then
			frame.MinText, frame.MaxText = frame:CreateFontString(), frame:CreateFontString()
			frame.callbacks = {}
			function frame:Init(value, minValue, maxValue, steps, formatters)
				self.value, self.minValue, self.maxValue, self.steps, self.formatters = value, minValue, maxValue, steps, formatters
			end
			function frame:RegisterCallback(event, func, owner)
				self.callbacks[event] = function(...)
					func(owner, ...)
				end
			end
		end
		return frame
	end
	MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = "OnValueChanged" }, Label = { Left = 1, Right = 2 } }
	function CreateMinimalSliderFormatter(_, formatter)
		return formatter
	end
	function FormatPercentage(percentage)
		return string.format("%d%%", Round(percentage * 100))
	end
	HUD_EDIT_MODE_SETTING_BAGS_SIZE = "Size"
	HUD_EDIT_MODE_RESET_POSITION = "Reset To Default Position"
	HUD_EDIT_MODE_REVERT_CHANGES = "Revert Changes"
	HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT = "Click To Edit"
	-- Applies a nine-slice layout with an art kit (NineSlice.lua); the stand-in keeps the kit.
	NineSliceUtil = {}
	function NineSliceUtil.ApplyLayout(container, layout, kit)
		container.layout, container.kit = layout, kit
	end

	UIParent = NewRegion(nil)
	UIParent.scale = UI_SCALE
	UIParent.left, UIParent.bottom, UIParent.right, UIParent.top = 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT

	-- The bottom row: the micro menu hangs off the screen, the main action bar off the micro
	-- menu, the bags bar off its right side (Camelot's preset layout constants).
	BAGS_ANCHOR_POINT, BAGS_ANCHOR_RELATIVE_POINT = "BOTTOMLEFT", "BOTTOMRIGHT"
	BAGS_ANCHOR_OFFSET_X, BAGS_ANCHOR_OFFSET_Y = BAGS_JOIN_X, BAGS_JOIN_Y
	MicroMenuContainer = EditModeSystem(UIParent)
	MicroMenuContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 116.5, 6)
	MicroMenuContainer.left, MicroMenuContainer.right = MICRO_MENU_LEFT, MICRO_MENU_RIGHT
	MicroMenuContainer.bottom, MicroMenuContainer.top = MICRO_MENU_BOTTOM, MICRO_MENU_TOP
	-- Edit Mode's own test: whether the player left the micro menu in its default spot.
	function MicroMenuContainer:IsInitialized()
		return true
	end
	function MicroMenuContainer:IsInDefaultPosition()
		return not game.microMenuMoved
	end
	-- Edit Mode's box over each of its bars (EditModeSystemSelectionBaseTemplate).
	MicroMenuContainer.Selection = NewRegion(MicroMenuContainer)
	MicroMenuContainer.Selection:SetFrameStrata("MEDIUM")
	MicroMenuContainer.Selection:SetFrameLevel(1000)
	MicroMenu = NewRegion(MicroMenuContainer)
	MicroMenu.BorderArt = MicroMenu:CreateTexture()
	MicroMenu.BorderArt:SetPoint("TOPLEFT", MicroMenu, "TOPLEFT", -MICRO_MENU_REACH, MICRO_MENU_REACH)
	MicroMenu.BorderArt:SetPoint("BOTTOMRIGHT", MicroMenu, "BOTTOMRIGHT", MICRO_MENU_REACH, -MICRO_MENU_REACH)
	MainActionBar = EditModeSystem(UIParent)
	MainActionBar:SetPoint("BOTTOMRIGHT", MicroMenuContainer, "BOTTOMLEFT", -4.5, -4)
	function MainActionBar:IsInDefaultPosition()
		return not game.actionBarMoved
	end
	BagsBar = EditModeSystem(UIParent)
	BagsBar.scale = BAGS_SCALE
	BagsBar.level = 52
	BagsBar:SetPoint(BAGS_ANCHOR_POINT, MicroMenuContainer, BAGS_ANCHOR_RELATIVE_POINT, BAGS_JOIN_X, BAGS_JOIN_Y)
	-- Where Edit Mode opens a bar's settings (EditModeSystemMixin:SetupSettingsDialogAnchor).
	function BagsBar:GetSettingsDialogAnchor()
		return { Get = function() return "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -250, 200 end }
	end
	BagsBar.BorderArt = BagsBar:CreateTexture()
	BagsBar.BorderArt.atlas = "UI-HUD-ActionBar-Frame"
	BagsBar.BorderArt:SetPoint("TOPLEFT", BagsBar, "TOPLEFT", -BAR_REACH_LEFT, BAR_REACH_TOP)
	BagsBar.BorderArt:SetPoint("BOTTOMRIGHT", BagsBar, "BOTTOMRIGHT", BAR_REACH_RIGHT, -BAR_REACH_BOTTOM)

	CharacterReagentBag0Slot = NewRegion(BagsBar)
	CharacterReagentBag0Slot.width = SLOT_SIZE
	local slotFrame = CharacterReagentBag0Slot:CreateTexture()
	slotFrame.atlas, slotFrame.width = "UI-HUD-ActionBar-IconFrame", SLOT_FRAME_SIZE
	function CharacterReagentBag0Slot:GetNormalTexture()
		return slotFrame
	end

	-- The bars Camelot stacks on the main action bar by their left edge
	-- (UpdateBottomActionBarPositions with ACTION_BARS_RELATIVE_TO_BASE_POSITIONING).
	SecondaryStatusTrackingBarContainer = NewXPBarContainer()
	MainStatusTrackingBarContainer = NewXPBarContainer()
	local stacked = { "MultiBarBottomRight", "MultiBarBottomLeft", "StanceBar", "PetActionBar", "PossessActionBar", "MainMenuBarVehicleLeaveButton" }
	for _, name in ipairs(stacked) do
		_G[name] = EditModeSystem(UIParent)
		_G[name].scale = STACKED_BAR_SCALE
	end
	-- UpdateBottomActionBarPositions places each of them again, cleared and set, and the action bar
	-- too while it is in its default position (SetToLayoutAnchor).
	function game.LayOutBottomBars()
		if not game.actionBarMoved then
			MainActionBar:ClearAllPoints()
			MainActionBar:SetPoint("BOTTOMRIGHT", MicroMenuContainer, "BOTTOMLEFT", -4.5, -4)
		end
		local y = 0
		for _, bar in ipairs({ SecondaryStatusTrackingBarContainer, MainStatusTrackingBarContainer, MultiBarBottomRight, MultiBarBottomLeft, StanceBar, PetActionBar, PossessActionBar, MainMenuBarVehicleLeaveButton }) do
			y = y + 20
			bar:ClearAllPoints()
			bar:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 0, y)
		end
	end
	game.LayOutBottomBars()

	-- The gamepad interface: the gamepad action bars' frame, hidden until the game switches.
	GamepadMainActionBarFrame = NewRegion(UIParent)
	GamepadMainActionBarFrame.shown = false
	GamepadMainActionBarFrame.bottom = GAMEPAD_BUTTONS_BOTTOM
	Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }, EditModeSystem = { MicroMenu = 13, Bags = 14 }, EditModeBagsSetting = { Size = 2 } }
	-- The bags bar's Size setting (EditModeSettingDisplayInfo.lua).
	EditModeSettingDisplayInfoManager = {}
	function EditModeSettingDisplayInfoManager:GetSystemSettingDisplayInfoMap(system)
		if system == Enum.EditModeSystem.Bags then
			return { [Enum.EditModeBagsSetting.Size] = { minValue = 75, maxValue = 200, stepSize = 5 } }
		end
	end
	C_InputInterfaceStyle = {}
	function C_InputInterfaceStyle.GetCurrentStyle()
		return game.gamepad and Enum.InputDeviceInterfaceType.Gamepad or Enum.InputDeviceInterfaceType.Mkb
	end
	EditModeManagerFrame = {}
	function EditModeManagerFrame:IsEditModeActive()
		return game.editMode
	end
	-- The game's settings dialog for its bars (EditModeDialogs.xml), hidden. ASSUMED: a little off
	-- Blizzard's values, so the tests see the block's dialog read them from it.
	local gameDialog = NewRegion(UIParent)
	gameDialog.shown = false
	gameDialog:SetFrameStrata("DIALOG")
	gameDialog:SetFrameLevel(201)
	gameDialog.widthPadding, gameDialog.heightPadding = 42, 44
	gameDialog.Title = gameDialog:CreateFontString()
	gameDialog.Title:SetFontObject("GameFontHighlightLarge")
	gameDialog.Title:SetPoint("TOP", gameDialog, "TOP", 0, -16)
	gameDialog.Settings = NewRegion(gameDialog)
	gameDialog.Settings:SetPoint("TOP", gameDialog.Title, "BOTTOM", 0, -13)
	gameDialog.Buttons = NewRegion(gameDialog)
	gameDialog.Buttons.spacing = 3
	gameDialog.Buttons.RevertChangesButton = NewRegion(gameDialog.Buttons)
	gameDialog.Buttons.RevertChangesButton:SetSize(181, 29)
	gameDialog.Buttons.Divider = gameDialog.Buttons:CreateTexture()
	gameDialog.Buttons.Divider:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-OnlineDivider")
	gameDialog.Buttons.Divider:SetSize(331, 17)
	EditModeSystemSettingsDialog = gameDialog
	function EditModeManagerFrame:SelectSystem(systemFrame)
		game.selectedSystem = systemFrame
	end
	-- Unselects the game's bars and closes its settings dialog (EditModeManager.lua).
	function EditModeManagerFrame:ClearSelectedSystem()
		game.selectedSystem = nil
	end
	-- After the player drops a bar or moves it with the arrow keys (EditModeManager.lua,
	-- OnSystemPositionChange and UpdateSystemAnchorInfo): a point the client left without a
	-- relativeTo is set again on UIParent, twice (the second time to correct its height), and only
	-- then is the bar marked as moved from its default position. A bottom bar then has the bottom
	-- bars laid out again (UpdateActionBarLayout).
	function EditModeManagerFrame:OnSystemPositionChange(systemFrame)
		local point, relativeTo, relativePoint, x, y = systemFrame:GetPoint(1)
		if not relativeTo then
			systemFrame:SetPoint(point, UIParent, relativePoint, x, y)
			systemFrame:SetPoint(point, UIParent, relativePoint, x, y)
		end
		if systemFrame == MicroMenuContainer then
			game.microMenuMoved = true
		elseif systemFrame == MainActionBar then
			game.actionBarMoved = true
			game.LayOutBottomBars()
		end
	end
	-- ASSUMED: the active layout follows the interface, as Blizzard keeps a layout per style.
	function EditModeManagerFrame:GetActiveLayoutInfo()
		return { interfaceStyle = C_InputInterfaceStyle.GetCurrentStyle() }
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
	game.barFrame, game.slotFrame, game.lineLeft = game.block.textures[1], game.block.textures[3], game.block.textures[4]
	-- Edit Mode's box over the block, made right after it.
	game.editBox = game.frames[2]
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

local function OffsetX(frame, point)
	local _, _, _, x = frame:GetPointByName(point or "BOTTOMLEFT")
	return x
end

-- The game switches interfaces as MainActionBar.lua's gamepad init and uninit do: the row's bars
-- hide or show, the gamepad buttons show or hide, and the XP bar goes to the screen's bottom or
-- back onto the row. ASSUMED: the gamepad buttons' frame shows with the gamepad interface.
local function SwitchToGamepad()
	game.gamepad = true
	MainActionBar:Hide()
	StanceBar:Hide()
	MicroMenu:Hide()
	BagsBar:Hide()
	GamepadMainActionBarFrame:Show()
	MainStatusTrackingBarContainer.top = XP_BAR_HEIGHT
	MainStatusTrackingBarContainer:ClearAllPoints()
	MainStatusTrackingBarContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
	FireEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
end

local function SwitchToKeyboard()
	game.gamepad = false
	GamepadMainActionBarFrame:Hide()
	MainActionBar:Show()
	MicroMenu:Show()
	BagsBar:Show()
	MainStatusTrackingBarContainer:ClearAllPoints()
	MainStatusTrackingBarContainer:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 0, 40)
	FireEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
end

-- How much wider the block makes the row, in UIParent units, and how far right the bags bar
-- moves: the slot and the join, less the difference between the micro menu's reach and the
-- block's, so the bags join the block with the same overlap as they joined the micro menu. The
-- micro menu's reach is in its own scale (1), the rest in the bags bar's.
local GROWTH_IN_BAGS_UNITS = SLOT_SIZE + BAGS_JOIN_X + BAR_REACH_RIGHT - MICRO_MENU_REACH / BAGS_SCALE
local GROWTH = GROWTH_IN_BAGS_UNITS * BAGS_SCALE

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

-- Versions 0.8.0 to 1.1.2 shipped AmILagging_Camelot.toc, which the game reads before
-- AmILagging.toc. An exact copy replaces a stale one when an update is unzipped over an old folder.
Test("AmILagging_Camelot.toc is an exact copy of AmILagging.toc", function()
	local toc = assert(io.open("AmILagging.toc")):read("*a")
	local camelot = assert(io.open("AmILagging_Camelot.toc"), "AmILagging_Camelot.toc missing"):read("*a")
	Equal(camelot == toc, true, "same text")
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
	UIParent:Hide()
	game.fps = 30
	Tick()
	Equal(game.fpsText.setTexts, texts, "updated while hidden")
	UIParent:Show()
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

Test("the block is a bar of its own by the micro menu, where the bags bar hung, dressed like it", function()
	NewGame()
	Login()
	local point, relativeTo, relativePoint, x, y = game.block:GetPoint(1)
	Equal(table.concat({ point, relativePoint, x, y }, " "), "BOTTOMLEFT BOTTOMRIGHT 7 -4", "anchor")
	Equal(relativeTo, MicroMenuContainer, "anchored to")
	Equal(game.block.parent, UIParent, "parent")
	Equal(game.block:IsShown(), true, "shown")
	Equal(game.block.scale, BAGS_SCALE, "the bags bar's size setting")
	Equal(game.block.level, BagsBar.level, "the bags bar's level")
	Equal(game.block:GetWidth(), SLOT_SIZE, "size")
	Equal(game.slotFrame.atlas, "UI-HUD-ActionBar-IconFrame", "slot frame art")
	Equal(game.slotFrame:GetWidth(), SLOT_FRAME_SIZE, "slot frame art size")
	Equal(game.barFrame.atlas, "UI-HUD-ActionBar-Frame", "bar frame art")
	local _, _, _, left, top = game.barFrame:GetPointByName("TOPLEFT")
	local _, _, _, right, bottom = game.barFrame:GetPointByName("BOTTOMRIGHT")
	Equal(table.concat({ left, top, right, bottom }, " "), table.concat({ -BAR_REACH_LEFT, BAR_REACH_TOP, BAR_REACH_RIGHT, -BAR_REACH_BOTTOM }, " "), "bar frame reach")
end)

Test("the bags bar joins the block as it joined the micro menu, with the same overlap", function()
	NewGame()
	Login()
	Near(OffsetX(BagsBar), BAGS_JOIN_X + GROWTH_IN_BAGS_UNITS, "bags bar, in its own units")
	-- In the bags bar's units, from the micro menu's right edge.
	local microMenuReach = MICRO_MENU_REACH / BAGS_SCALE
	local blockLeft, blockRight = BAGS_JOIN_X, BAGS_JOIN_X + SLOT_SIZE
	local bagsLeft = OffsetX(BagsBar)
	local overlapBefore = microMenuReach + BAR_REACH_LEFT - blockLeft
	local overlapAfter = (blockRight + BAR_REACH_RIGHT) - (bagsLeft - BAR_REACH_LEFT)
	Near(overlapAfter, overlapBefore, "overlap of frame art")
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

-- The player moved the action bar away from the row in Edit Mode and left the micro menu where
-- it was: the row is the micro menu, the block and the bags. The action bar and the bars Blizzard
-- stacks on it are no longer part of it.
Test("an action bar the player moved away is left alone, and so are the bars stacked on it", function()
	NewGame({ before = function()
		game.actionBarMoved = true
		MainActionBar:ClearAllPoints()
		MainActionBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 200)
	end })
	Login()
	Equal(OffsetX(MainActionBar), 10, "action bar")
	Near(OffsetX(MultiBarBottomLeft), 0, "bar stacked on the action bar")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH, "XP bar stacked on the action bar")
	Equal((game.block:GetPoint(1)), "BOTTOMLEFT", "the block in the row")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "the micro menu, still the row's root")
	Near(OffsetX(BagsBar), BAGS_JOIN_X + GROWTH_IN_BAGS_UNITS, "the bags bar")
end)

Test("a bags bar the player hung elsewhere stays there; the block joins the micro menu as the layout would", function()
	NewGame()
	Login()
	BagsBar:ClearAllPoints()
	BagsBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
	Equal(OffsetX(BagsBar, "BOTTOMRIGHT"), -10, "bags bar")
	local point, relativeTo, relativePoint, x, y = game.block:GetPoint(1)
	Equal(table.concat({ point, relativePoint, x, y }, " "), "BOTTOMLEFT BOTTOMRIGHT 7 -4", "block anchor")
	Equal(relativeTo, MicroMenuContainer, "block anchored to")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu")
	BagsBar:ClearAllPoints()
	BagsBar:SetPoint(BAGS_ANCHOR_POINT, MicroMenuContainer, BAGS_ANCHOR_RELATIVE_POINT, BAGS_JOIN_X, BAGS_JOIN_Y)
	Near(OffsetX(BagsBar), BAGS_JOIN_X + GROWTH_IN_BAGS_UNITS, "bags bar back on the micro menu")
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
	-- The bags bar placed again by Edit Mode, a little further out.
	BagsBar:ClearAllPoints()
	BagsBar:SetPoint(BAGS_ANCHOR_POINT, MicroMenuContainer, BAGS_ANCHOR_RELATIVE_POINT, 9, BAGS_JOIN_Y)
	Near(OffsetX(BagsBar), 9 + (GROWTH_IN_BAGS_UNITS + 9 - BAGS_JOIN_X), "bags bar")
	-- The Size setting resizes the XP bar: the new width is the base for the stretch.
	MainStatusTrackingBarContainer:SetWidth(600)
	Near(MainStatusTrackingBarContainer:GetWidth(), 600 + GROWTH + (9 - BAGS_JOIN_X) * BAGS_SCALE, "resized XP bar")
end)

-- Where the block's center stands in the row, in UIParent units: its bottom left joined to the
-- micro menu's bottom right as the bags bar is.
local ROW_CENTER_X = MICRO_MENU_RIGHT + (BAGS_JOIN_X + SLOT_SIZE / 2) * BAGS_SCALE
local ROW_CENTER_Y = MICRO_MENU_BOTTOM + (BAGS_JOIN_Y + SLOT_SIZE / 2) * BAGS_SCALE

local function BlockAnchor()
	local point, relativeTo, relativePoint, x, y = game.block:GetPoint(1)
	return point, relativeTo, relativePoint, x, y
end

-- The player drags the block in Edit Mode and drops it with its center at x, y (UIParent units).
local function DragTo(x, y)
	local editBox = game.editBox
	editBox.scripts.OnDragStart(editBox, "LeftButton")
	game.kitWhileDragging, game.movingWhileDragging = editBox.kit, game.block.moving
	local toBlock = 1 / BAGS_SCALE
	game.block.centerX, game.block.centerY = x * toBlock, y * toBlock
	editBox.scripts.OnDragStop(editBox)
end

-- Nothing on the bar moved: everything stands where Blizzard put it.
local function BarAsTheGameSetIt(when)
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu " .. when)
	Near(OffsetX(BagsBar), BAGS_JOIN_X, "bags bar " .. when)
	Near(OffsetX(MultiBarBottomLeft), 0, "stacked bar " .. when)
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH, "XP bar " .. when)
end

-- The block's settings dialog and its parts, once the player opened it.
local function FrameWithTemplate(template, text)
	for _, frame in ipairs(game.frames) do
		if frame.template == template and (text == nil or frame.text == text) then
			return frame
		end
	end
end

local function SettingsDialog()
	local slider = FrameWithTemplate("MinimalSliderWithSteppersTemplate")
	return {
		frame = slider and slider.parent.parent,
		slider = slider,
		close = FrameWithTemplate("UIPanelCloseButton"),
		revert = FrameWithTemplate("UIPanelButtonTemplate, UIButtonTemplate", "Revert Changes"),
		reset = FrameWithTemplate("UIPanelButtonTemplate, UIButtonTemplate", "Reset To Default Position"),
	}
end

local function ClickBlock()
	game.editBox.scripts.OnMouseDown(game.editBox, "LeftButton")
end

local function MoveSlider(value)
	SettingsDialog().slider.callbacks.OnValueChanged(value)
end

Test("in Edit Mode the block stays in its place in the row, in Edit Mode's box on top of the game's boxes", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	local point, relativeTo, relativePoint, x, y = BlockAnchor()
	Equal(table.concat({ point, relativePoint, x, y }, " "), "BOTTOMLEFT BOTTOMRIGHT 7 -4", "in the row")
	Equal(relativeTo, MicroMenuContainer, "anchored to")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "the row keeps its room")
	Near(OffsetX(BagsBar), BAGS_JOIN_X + GROWTH_IN_BAGS_UNITS, "bags bar")
	Equal(game.editBox:IsShown(), true, "Edit Mode box")
	Equal(game.editBox.kit, "editmode-actionbar-highlight", "the blue box")
	Equal(game.editBox.template, "NineSliceCodeTemplate", "the box's template")
	Equal(game.editBox.strata .. " " .. game.editBox.level, "MEDIUM 1001", "above the game's boxes")
	game.editBox.scripts.OnEnter(game.editBox)
	Equal(table.concat(game.tooltip, "|"), "Am I Lagging?|Click To Edit", "name and hint on mouse over")
	game.callbacks["EditMode.Exit"]()
	Equal(game.editBox:IsShown(), false, "Edit Mode box after")
	Equal((BlockAnchor()), "BOTTOMLEFT", "still in the row")
end)

Test("starting in Edit Mode keeps the block in its place", function()
	NewGame({ before = function() game.editMode = true end })
	Login()
	Equal((BlockAnchor()), "BOTTOMLEFT", "in the row")
	Equal(game.editBox:IsShown(), true, "Edit Mode box")
end)

Test("clicking the block in Edit Mode selects it and opens its settings where the game opens the bags bar's", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	ClickBlock()
	Equal(game.editBox.kit, "editmode-actionbar-selected", "the yellow box")
	local dialog = SettingsDialog()
	Equal(dialog.frame:IsShown(), true, "settings shown")
	-- Measured from the game's dialog.
	Equal(dialog.frame.strata .. " " .. dialog.frame.level, "DIALOG 201", "the game's dialog strata and level")
	Equal(dialog.revert:GetWidth() .. "x" .. dialog.revert:GetHeight(), "181x29", "the game's Revert Changes button size")
	Equal(dialog.reset:GetHeight(), 29, "the game's button height")
	Equal(dialog.frame:GetWidth(), 343 + 42, "the slider row and the game's padding")
	Equal(dialog.frame:GetHeight(), 16 + 13 + 32 + 13 + 29 + 3 + 17 + 3 + 29 + 44, "the content and the game's padding")
	local point, relativeTo, relativePoint, x, y = dialog.frame:GetPoint(1)
	Equal(table.concat({ point, relativePoint, x, y }, " ") .. " " .. tostring(relativeTo == UIParent), "BOTTOMRIGHT BOTTOMRIGHT -250 200 true", "where the game opens the bags bar's")
	Equal(table.concat({ dialog.slider.value, dialog.slider.minValue, dialog.slider.maxValue, dialog.slider.steps }, " "), "100 75 200 25", "the bags bar's Size slider")
	Equal(dialog.slider.formatters[MinimalSliderWithSteppersMixin.Label.Right](150), "150%", "shown as a percentage")
	Equal(dialog.revert:IsEnabled(), false, "nothing to revert")
	Equal(dialog.reset:IsEnabled(), false, "already in its default place")
	game.editBox.scripts.OnEnter(game.editBox)
	Equal(game.tooltipOwner, nil, "no tooltip while selected")
	dialog.close.scripts.OnClick(dialog.close)
	Equal(dialog.frame:IsShown(), false, "closed")
	Equal(game.editBox.kit, "editmode-actionbar-highlight", "the blue box again")
end)

Test("the size slider resizes the block, the bags bar still joins it the same way, and 100% saves nothing", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	ClickBlock()
	MoveSlider(151)
	Equal(AmILaggingDB.size, 150, "saved size, on the slider's step")
	Near(game.block.scale, BAGS_SCALE * 1.5, "the block's scale")
	-- In UIParent units, from the micro menu's right edge: the bags bar joins the block with the
	-- overlap it had with the micro menu.
	local blockScale, bagsScale = BAGS_SCALE * 1.5, BAGS_SCALE
	local join = BAGS_JOIN_X * bagsScale
	local overlapBefore = MICRO_MENU_REACH + BAR_REACH_LEFT * bagsScale - join
	local blockRightArt = join + (SLOT_SIZE + BAR_REACH_RIGHT) * blockScale
	local bagsLeftArt = OffsetX(BagsBar) * bagsScale - BAR_REACH_LEFT * bagsScale
	Near(blockRightArt - bagsLeftArt, overlapBefore, "overlap of frame art")
	local growth = join + (SLOT_SIZE + BAR_REACH_RIGHT) * blockScale - MICRO_MENU_REACH
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - growth / 2, "the row grows evenly")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH + growth, "XP bar")
	local _, _, _, x = BlockAnchor()
	Near(x, BAGS_JOIN_X / 1.5, "the join, in the block's own units")
	MoveSlider(100)
	Equal(AmILaggingDB.size, nil, "100% saved")
	Near(game.block.scale, BAGS_SCALE, "back to the bags bar's size")
	Near(OffsetX(BagsBar), BAGS_JOIN_X + GROWTH_IN_BAGS_UNITS, "bags bar")
end)

Test("Revert Changes puts back the spot and size the block had when Edit Mode opened", function()
	NewGame({ before = function() AmILaggingDB = { format = 1, spot = { x = 300, y = 400 }, size = 120 } end })
	Login()
	game.callbacks["EditMode.Enter"]()
	ClickBlock()
	MoveSlider(150)
	DragTo(600, 500)
	local dialog = SettingsDialog()
	Equal(dialog.revert:IsEnabled(), true, "something to revert")
	dialog.revert.onClick()
	Equal(AmILaggingDB.size, 120, "size")
	Equal(AmILaggingDB.spot.x .. " " .. AmILaggingDB.spot.y, "300 400", "spot")
	Equal(dialog.slider.value, 120, "slider")
	Equal(dialog.revert:IsEnabled(), false, "nothing left to revert")
	Near(game.block.scale, BAGS_SCALE * 1.2, "the block's scale")
	-- After leaving and opening Edit Mode again there is nothing to revert, as in the game.
	game.callbacks["EditMode.Exit"]()
	game.callbacks["EditMode.Enter"]()
	ClickBlock()
	Equal(SettingsDialog().revert:IsEnabled(), false, "nothing to revert in a new Edit Mode")
end)

Test("Reset To Default Position puts the block back where the addon puts it and keeps its size", function()
	NewGame({ before = function() AmILaggingDB = { format = 1, spot = { x = 300, y = 400 }, size = 150 } end })
	Login()
	game.callbacks["EditMode.Enter"]()
	ClickBlock()
	local dialog = SettingsDialog()
	Equal(dialog.reset:IsEnabled(), true, "moved, so it can be reset")
	dialog.reset.onClick()
	Equal(AmILaggingDB.spot, nil, "spot")
	Equal(AmILaggingDB.size, 150, "size kept")
	Equal((BlockAnchor()), "BOTTOMLEFT", "back in the row")
	Equal(dialog.reset:IsEnabled(), false, "nothing left to reset")
	Equal(dialog.revert:IsEnabled(), true, "the reset can be reverted")
end)

Test("selecting one of the game's bars, or leaving Edit Mode, closes the block's settings", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	ClickBlock()
	EditModeManagerFrame:SelectSystem(BagsBar)
	Equal(game.selectedSystem, BagsBar, "the game selected its bar")
	Equal(SettingsDialog().frame:IsShown(), false, "settings after the game selected its bar")
	Equal(game.editBox.kit, "editmode-actionbar-highlight", "the blue box")
	ClickBlock()
	game.callbacks["EditMode.Exit"]()
	Equal(SettingsDialog().frame:IsShown(), false, "settings after Edit Mode")
end)

Test("selecting the block clears the game's selection, so only one thing is selected", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	EditModeManagerFrame:SelectSystem(BagsBar)
	ClickBlock()
	Equal(game.selectedSystem, nil, "the game's selection")
	Equal(SettingsDialog().frame:IsShown(), true, "the block's settings")
	Equal(game.editBox.kit, "editmode-actionbar-selected", "the block selected")
	-- Clicking it again keeps it selected.
	ClickBlock()
	Equal(SettingsDialog().frame:IsShown(), true, "the block's settings after another click")
	Equal(game.editBox.kit, "editmode-actionbar-selected", "still selected")
end)

Test("when the game clears its selection, the block is deselected too", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	ClickBlock()
	EditModeManagerFrame:ClearSelectedSystem()
	Equal(SettingsDialog().frame:IsShown(), false, "the block's settings")
	Equal(game.editBox.kit, "editmode-actionbar-highlight", "the blue box")
end)

-- ASSUMED: where the client laid out the block and the micro menu (the stand-in doesn't lay frames
-- out), as centers in each frame's own units.
local function LaidOut(blockX, blockY, menuX, menuY)
	game.block.centerX, game.block.centerY = blockX / BAGS_SCALE, blockY / BAGS_SCALE
	MicroMenuContainer.centerX, MicroMenuContainer.centerY = menuX, menuY
end

-- The player drags one of the game's bars in Edit Mode and drops it (EditModeSystemMixin's
-- OnDragStart and OnDragStop). The client moves the bar itself (StartMoving, StopMovingOrSizing):
-- it replaces the bar's points without the Lua SetPoint, so no hook sees it, and leaves the point
-- without a relativeTo (UpdateSystemAnchorInfo: "If we don't have a relativeTo"). Edit Mode then
-- takes it from there (OnSystemPositionChange). during() runs while the bar is in the player's
-- hand: the game's own work going on meanwhile.
-- ASSUMED: the point the client anchors the dragged bar by; a test passes it.
local function EditModeDrag(frame, point, x, y, during)
	frame.isDragging = true
	frame.points = { { point, nil, point, x, y } }
	if during then
		during()
	end
	frame.isDragging = false
	frame.points = { { point, nil, point, x, y } }
	EditModeManagerFrame:OnSystemPositionChange(frame)
end

-- The player drags the micro menu in Edit Mode and drops it with its center at menuX, menuY.
local function MoveMicroMenu(menuX, menuY)
	MicroMenuContainer.centerX, MicroMenuContainer.centerY = menuX, menuY
	EditModeDrag(MicroMenuContainer, "CENTER", menuX, menuY)
end

-- Edit Mode's Revert All Changes, also what leaving it without saving does (RevertAllChanges):
-- it clears the selection, then lays out the saved layout again, which puts the micro menu back
-- where Blizzard's layout puts it.
local function RevertAllChanges()
	EditModeManagerFrame:ClearSelectedSystem()
	game.microMenuMoved = false
	MicroMenuContainer.centerX, MicroMenuContainer.centerY = 850, 30
	MicroMenuContainer:ClearAllPoints()
	MicroMenuContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 116.5, 6)
end

Test("in Edit Mode the block lets go of the micro menu: moving the menu leaves it where it was, and it keeps that spot", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	LaidOut(ROW_CENTER_X, ROW_CENTER_Y, 850, 30)
	EditModeManagerFrame:SelectSystem(MicroMenuContainer)
	local point, relativeTo, relativePoint, x, y = BlockAnchor()
	Equal(point .. " " .. relativePoint .. " " .. tostring(relativeTo == UIParent), "CENTER BOTTOMLEFT true", "standing on its own while the menu is selected")
	Near(x, ROW_CENTER_X / BAGS_SCALE, "where it stood, x")
	Near(y, ROW_CENTER_Y / BAGS_SCALE, "where it stood, y")
	MoveMicroMenu(1400, 300)
	Equal((BlockAnchor()), "CENTER", "still where it stood after the menu moved")
	Near(OffsetX(BagsBar), BAGS_JOIN_X, "the bags bar joins the menu again")
	EditModeManagerFrame:ClearSelectedSystem()
	Near(AmILaggingDB.spot.x, ROW_CENTER_X, "kept spot, x")
	Near(AmILaggingDB.spot.y, ROW_CENTER_Y, "kept spot, y")
	point, relativeTo = BlockAnchor()
	Equal(point .. " " .. tostring(relativeTo == UIParent), "CENTER true", "on its own spot")
	game.callbacks["EditMode.Exit"]()
	Equal((BlockAnchor()), "CENTER", "still there after Edit Mode")
end)

Test("leaving Edit Mode with the micro menu still selected keeps the block where it stood", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	LaidOut(ROW_CENTER_X, ROW_CENTER_Y, 850, 30)
	EditModeManagerFrame:SelectSystem(MicroMenuContainer)
	MoveMicroMenu(1400, 300)
	game.callbacks["EditMode.Exit"]()
	Near(AmILaggingDB.spot.x, ROW_CENTER_X, "kept spot")
	Equal((BlockAnchor()), "CENTER", "on its own spot")
end)

Test("selecting the micro menu without moving it leaves the block in its place", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	LaidOut(ROW_CENTER_X, ROW_CENTER_Y, 850, 30)
	EditModeManagerFrame:SelectSystem(MicroMenuContainer)
	EditModeManagerFrame:SelectSystem(BagsBar)
	Equal(AmILaggingDB.spot, nil, "spot")
	local point, relativeTo = BlockAnchor()
	Equal(point .. " " .. tostring(relativeTo == MicroMenuContainer), "BOTTOMLEFT true", "back by the micro menu")
	Near(OffsetX(BagsBar), BAGS_JOIN_X + GROWTH_IN_BAGS_UNITS, "the row still makes room")
end)

Test("a block on a spot of its own stays there when the micro menu is selected and moved", function()
	NewGame({ before = function() AmILaggingDB = { format = 1, spot = { x = 300, y = 400 } } end })
	Login()
	game.callbacks["EditMode.Enter"]()
	LaidOut(300, 400, 850, 30)
	EditModeManagerFrame:SelectSystem(MicroMenuContainer)
	MoveMicroMenu(1400, 300)
	EditModeManagerFrame:ClearSelectedSystem()
	Equal(AmILaggingDB.spot.x .. " " .. AmILaggingDB.spot.y, "300 400", "its spot")
end)

-- Whether the client anchors a dragged bar by its old point or by another, the bar keeps only the
-- point the game gave it, where the player dropped it.
Test("a micro menu dropped in Edit Mode stays where the player dropped it, by the one point the game gave it", function()
	for _, point in ipairs({ "BOTTOM", "TOPLEFT" }) do
		NewGame()
		Login()
		game.callbacks["EditMode.Enter"]()
		LaidOut(ROW_CENTER_X, ROW_CENTER_Y, 850, 30)
		EditModeManagerFrame:SelectSystem(MicroMenuContainer)
		EditModeDrag(MicroMenuContainer, point, 400, 300)
		Equal(MicroMenuContainer:GetNumPoints(), 1, point .. ": points after the drop")
		Near(OffsetX(MicroMenuContainer, point), 400, point .. ": where it was dropped")
		Near(OffsetX(BagsBar), BAGS_JOIN_X, point .. ": the bags bar joins the menu again")
		-- The player clicks something else: the block keeps its spot and everything is laid out again.
		LaidOut(ROW_CENTER_X, ROW_CENTER_Y, 400, 300)
		EditModeManagerFrame:ClearSelectedSystem()
		Equal(MicroMenuContainer:GetNumPoints(), 1, point .. ": points later")
		Near(OffsetX(MicroMenuContainer, point), 400, point .. ": still there")
	end
end)

Test("while the player drags one of the game's bars in Edit Mode, the addon leaves it in their hand", function()
	for _, point in ipairs({ "BOTTOM", "TOPLEFT" }) do
		NewGame()
		Login()
		game.callbacks["EditMode.Enter"]()
		LaidOut(ROW_CENTER_X, ROW_CENTER_Y, 850, 30)
		EditModeManagerFrame:SelectSystem(MicroMenuContainer)
		EditModeDrag(MicroMenuContainer, point, 400, 300)
		-- Picked up again right away, while the game lays out the bars above the row (a target
		-- change does), so the addon lays out again.
		EditModeDrag(MicroMenuContainer, point, 600, 300, function()
			game.LayOutBottomBars()
			Equal(MicroMenuContainer:GetNumPoints(), 1, point .. ": micro menu points in the hand")
			Near(OffsetX(MicroMenuContainer, point), 600, point .. ": micro menu in the hand")
		end)
		Near(OffsetX(MicroMenuContainer, point), 600, point .. ": micro menu where it was dropped")
		-- The action bar in the hand hangs off nothing, like a row of its own. Meanwhile Edit Mode
		-- places the bags bar again.
		NewGame()
		Login()
		game.callbacks["EditMode.Enter"]()
		EditModeManagerFrame:SelectSystem(MainActionBar)
		EditModeDrag(MainActionBar, point, 300, 200, function()
			BagsBar:ClearAllPoints()
			BagsBar:SetPoint(BAGS_ANCHOR_POINT, MicroMenuContainer, BAGS_ANCHOR_RELATIVE_POINT, BAGS_JOIN_X, BAGS_JOIN_Y)
			Equal(MainActionBar:GetNumPoints(), 1, point .. ": action bar points in the hand")
			Near(OffsetX(MainActionBar, point), 300, point .. ": action bar in the hand")
		end)
		Equal(MainActionBar:GetNumPoints(), 1, point .. ": action bar points after the drop")
		Near(OffsetX(MainActionBar, point), 300, point .. ": action bar where it was dropped")
	end
end)

Test("a bags bar dragged away in Edit Mode stays where it was dropped", function()
	for _, point in ipairs({ "BOTTOMLEFT", "TOPLEFT" }) do
		NewGame()
		Login()
		game.callbacks["EditMode.Enter"]()
		EditModeManagerFrame:SelectSystem(BagsBar)
		EditModeDrag(BagsBar, point, 1200, 400)
		Equal(BagsBar:GetNumPoints(), 1, point .. ": points")
		Near(OffsetX(BagsBar, point), 1200, point .. ": where it was dropped")
	end
end)

Test("Revert All Changes, or leaving Edit Mode without saving, puts the block back in the row with the micro menu", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	LaidOut(ROW_CENTER_X, ROW_CENTER_Y, 850, 30)
	EditModeManagerFrame:SelectSystem(MicroMenuContainer)
	MoveMicroMenu(1400, 300)
	RevertAllChanges()
	Equal(AmILaggingDB.spot, nil, "spot")
	local point, relativeTo = BlockAnchor()
	Equal(point .. " " .. tostring(relativeTo == MicroMenuContainer), "BOTTOMLEFT true", "back in the row")
	Near(OffsetX(BagsBar), BAGS_JOIN_X + GROWTH_IN_BAGS_UNITS, "the bags bar joins the block")
	-- Also when the micro menu was let go first.
	EditModeManagerFrame:SelectSystem(MicroMenuContainer)
	MoveMicroMenu(1400, 300)
	EditModeManagerFrame:ClearSelectedSystem()
	Near(AmILaggingDB.spot.x, ROW_CENTER_X, "kept spot")
	RevertAllChanges()
	Equal(AmILaggingDB.spot, nil, "spot after a later revert")
	Equal((BlockAnchor()), "BOTTOMLEFT", "back in the row after a later revert")
	-- Once Edit Mode closes, the kept spot is the player's: a layout that puts the micro menu back
	-- later leaves the block on it.
	EditModeManagerFrame:SelectSystem(MicroMenuContainer)
	MoveMicroMenu(1400, 300)
	game.callbacks["EditMode.Exit"]()
	RevertAllChanges()
	Near(AmILaggingDB.spot.x, ROW_CENTER_X, "spot kept after Edit Mode closed")
end)

local function PressKey(key)
	local dialog = SettingsDialog().frame
	dialog.scripts.OnKeyDown(dialog, key)
	return dialog.propagate
end

Test("Escape closes the block's settings with the game's close sound, and other keys go on to the game", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	ClickBlock()
	Equal(SettingsDialog().frame.keyboard, true, "takes keys")
	Equal(PressKey("W"), true, "W goes on to the game")
	Equal(PressKey("ESCAPE"), false, "Escape kept")
	Equal(SettingsDialog().frame:IsShown(), false, "closed")
	Equal(game.editBox.kit, "editmode-actionbar-highlight", "deselected")
	Equal(game.sounds[#game.sounds], SOUNDKIT.IG_MAINMENU_CLOSE, "the game's close sound")
end)

Test("the arrow keys move the selected block a step, ten with Shift, as Edit Mode moves its bars", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	LaidOut(ROW_CENTER_X, ROW_CENTER_Y, 850, 30)
	ClickBlock()
	Equal(PressKey("RIGHT"), false, "the arrow key kept")
	Near(AmILaggingDB.spot.x, ROW_CENTER_X + BAGS_SCALE, "a step right, in the block's units")
	Near(AmILaggingDB.spot.y, ROW_CENTER_Y, "same height")
	Equal((BlockAnchor()), "CENTER", "on its own now")
	BarAsTheGameSetIt("with the block moved off the bar")
	game.shift = true
	PressKey("UP")
	Near(AmILaggingDB.spot.y, ROW_CENTER_Y + 10 * BAGS_SCALE, "ten steps up with Shift")
	Equal(SettingsDialog().revert:IsEnabled(), true, "the move can be reverted")
end)

Test("the saved size is kept only inside the slider's range and when it isn't the default", function()
	for _, case in ipairs({ { 150, 150 }, { 75, 75 }, { 200, 200 }, { 100, nil }, { 74, nil }, { 201, nil }, { "150", nil }, { 0 / 0, nil } }) do
		NewGame({ before = function() AmILaggingDB = { format = 1, size = case[1] } end })
		Login()
		Equal(AmILaggingDB.size, case[2], "saved " .. tostring(case[1]))
	end
end)

Test("dragging the block in Edit Mode floats it where it's dropped, remembers the spot and gives the bar back", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	DragTo(300, 400)
	Equal(game.kitWhileDragging, "editmode-actionbar-selected", "the yellow box while dragging")
	Equal(game.movingWhileDragging, true, "moved by the player")
	Equal(game.editBox.kit, "editmode-actionbar-highlight", "the blue box after")
	Equal(AmILaggingDB.spot.x .. " " .. AmILaggingDB.spot.y, "300 400", "saved spot")
	local point, relativeTo, relativePoint, x, y = BlockAnchor()
	Equal(point .. " " .. relativePoint, "CENTER BOTTOMLEFT", "anchor")
	Equal(relativeTo, UIParent, "anchored to")
	Near(x, 300 / BAGS_SCALE, "x in the block's units")
	Near(y, 400 / BAGS_SCALE, "y in the block's units")
	game.callbacks["EditMode.Exit"]()
	Equal((BlockAnchor()), "CENTER", "still there after Edit Mode")
	BarAsTheGameSetIt("with the block floating")
end)

Test("dragging the block back by the micro menu puts it back in the row and forgets the spot", function()
	NewGame({ before = function() AmILaggingDB = { format = 1, spot = { x = 300, y = 400 } } end })
	Login()
	BarAsTheGameSetIt("with a saved spot")
	game.callbacks["EditMode.Enter"]()
	DragTo(ROW_CENTER_X + 10, ROW_CENTER_Y - 10)
	Equal(AmILaggingDB.spot, nil, "saved spot")
	game.callbacks["EditMode.Exit"]()
	local point, relativeTo = BlockAnchor()
	Equal(point .. " " .. tostring(relativeTo == MicroMenuContainer), "BOTTOMLEFT true", "back in the row")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "the row makes room again")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH + GROWTH, "XP bar stretched again")
end)

Test("while the player drags the block, the bar's own changes leave it in their hand", function()
	NewGame()
	Login()
	game.callbacks["EditMode.Enter"]()
	local editBox = game.editBox
	editBox.scripts.OnDragStart(editBox, "LeftButton")
	local points = game.block.points
	MicroMenuContainer:ClearAllPoints()
	MicroMenuContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 116.5, 6)
	Equal(game.block.points, points, "block re-anchored while dragged")
	Equal(game.block.moving, true, "still moving")
	game.block.centerX, game.block.centerY = 300 / BAGS_SCALE, 400 / BAGS_SCALE
	editBox.scripts.OnDragStop(editBox)
	Equal((BlockAnchor()), "CENTER", "dropped")
end)

Test("a saved spot puts the block there at login", function()
	NewGame({ before = function() AmILaggingDB = { format = 1, spot = { x = 250, y = 500 } } end })
	Login()
	local point, relativeTo, _, x, y = BlockAnchor()
	Equal(point .. " " .. tostring(relativeTo == UIParent), "CENTER true", "anchor")
	Near(x, 250 / BAGS_SCALE, "x")
	Near(y, 500 / BAGS_SCALE, "y")
	Equal(game.block.clamped, true, "kept on the screen")
	-- By its own size, as Edit Mode keeps the game's bars: in the row at the screen's bottom its
	-- frame art reaches past the edge, and counting the art pushed the block up off the row.
	Equal(game.block.clampInsets, nil, "frame art counted for the screen's edge")
end)

Test("the saved data keeps a valid spot and drops everything else", function()
	NewGame({ before = function() AmILaggingDB = { format = 1, spot = { x = 120.5, y = -3, extra = 1 }, junk = true } end })
	Login()
	Equal(AmILaggingDB.format, 1, "format")
	Equal(AmILaggingDB.spot.x .. " " .. AmILaggingDB.spot.y, "120.5 -3", "spot")
	Equal(AmILaggingDB.spot.extra, nil, "extra field in the spot")
	Equal(AmILaggingDB.junk, nil, "unknown field")
end)

Test("broken saved data is dropped and the block stands in the row", function()
	local cases = {
		{ "nothing saved", nil },
		{ "not a table", "here" },
		{ "a spot that isn't a table", { spot = "here" } },
		{ "a spot with text", { spot = { x = "1", y = 2 } } },
		{ "a spot with half of it", { spot = { x = 1 } } },
		{ "a spot that isn't a number", { spot = { x = 0 / 0, y = 2 } } },
		{ "a spot at infinity", { spot = { x = math.huge, y = 2 } } },
	}
	for _, case in ipairs(cases) do
		NewGame({ before = function() AmILaggingDB = case[2] end })
		Login()
		Equal(type(AmILaggingDB), "table", case[1] .. ": saved data")
		Equal(AmILaggingDB.format, 1, case[1] .. ": format")
		Equal(AmILaggingDB.spot, nil, case[1] .. ": spot")
		Equal((BlockAnchor()), "BOTTOMLEFT", case[1] .. ": in the row")
	end
end)

Test("next to a moved micro menu, the block floats on a free side and nothing on the bar moves", function()
	-- The bags bar still hangs off the micro menu's right and the action bar off its left:
	-- neither side is free, so the block stands above the micro menu.
	NewGame({ before = function() game.microMenuMoved = true end })
	Login()
	Equal((BlockAnchor()), "BOTTOMRIGHT", "above the micro menu")
	BarAsTheGameSetIt("with the micro menu moved")
	-- The player moved the bags bar away: the right side is free.
	BagsBar:ClearAllPoints()
	BagsBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
	local point, relativeTo, relativePoint, x, y = BlockAnchor()
	Equal(table.concat({ point, relativePoint, x, y }, " "), "BOTTOMLEFT BOTTOMRIGHT 7 -4", "on the right")
	Equal(relativeTo, MicroMenuContainer, "anchored to")
	-- The action bar moved away, then the micro menu moved to the screen's right edge: the
	-- left side.
	MainActionBar:ClearAllPoints()
	MainActionBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 10)
	MicroMenuContainer.left, MicroMenuContainer.right = SCREEN_WIDTH - 310, SCREEN_WIDTH - 10
	MicroMenuContainer:ClearAllPoints()
	MicroMenuContainer:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
	point, relativeTo, relativePoint, x, y = BlockAnchor()
	Equal(table.concat({ point, relativePoint, x, y }, " "), "BOTTOMRIGHT BOTTOMLEFT -7 -4", "on the left")
	Equal(OffsetX(BagsBar, "BOTTOMRIGHT"), -10, "bags bar")
end)

Test("in the gamepad interface the block can't be dragged in Edit Mode", function()
	NewGame()
	Login()
	SwitchToGamepad()
	game.callbacks["EditMode.Enter"]()
	Equal(game.block:IsShown(), true, "block shown")
	Equal(game.editBox:IsShown(), false, "Edit Mode box")
	Equal((BlockAnchor()), "CENTER", "between the gamepad buttons and the XP bar")
end)

Test("in combat every change waits for the end of combat", function()
	NewGame()
	Login()
	game.combat = true
	MicroMenu:Hide()
	Equal(game.block:IsShown(), true, "block in combat")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu in combat")
	MainStatusTrackingBarContainer:SetWidth(600)
	Equal(MainStatusTrackingBarContainer:GetWidth(), 600, "XP bar in combat")
	game.combat = false
	FireEvent("PLAYER_REGEN_ENABLED")
	Equal((BlockAnchor()), "CENTER", "block floats after combat (no micro menu)")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu after combat")
	Near(MainStatusTrackingBarContainer:GetWidth(), 600, "XP bar after combat")
end)

-- ASSUMED: how another addon hides the bags bar. Parenting a Blizzard bar to a hidden frame of
-- its own is a common way; the bar then stays shown but isn't on screen.
Test("the block stays when the bags bar is hidden, however it was hidden", function()
	NewGame()
	Login()
	BagsBar:Hide()
	Equal(game.block:IsVisible(), true, "block with the bags bar hidden")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu with the bags bar hidden")
	BagsBar:Show()
	local hiddenFrame = CreateFrame("Frame", nil, UIParent)
	hiddenFrame:Hide()
	BagsBar:SetParent(hiddenFrame)
	Equal(game.block:IsVisible(), true, "block with the bags bar in a hidden frame")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu with the bags bar in a hidden frame")
end)

Test("without the micro menu on screen the block floats above the XP bar and nothing moves, until it's back", function()
	NewGame()
	Login()
	local hiddenFrame = CreateFrame("Frame", nil, UIParent)
	hiddenFrame:Hide()
	MicroMenu:SetParent(hiddenFrame)
	Equal(game.block:IsShown(), true, "block without the micro menu")
	local point, relativeTo, relativePoint, _, y = BlockAnchor()
	Equal(point .. " " .. relativePoint .. " " .. tostring(relativeTo == UIParent), "CENTER BOTTOM true", "above the XP bar")
	Near(y, (GAMEPAD_BUTTONS_BOTTOM + 0) / 2 / BAGS_SCALE, "between the gamepad buttons' place and the screen's bottom (no XP bar edge known)")
	BarAsTheGameSetIt("without the micro menu")
	game.callbacks["EditMode.Enter"]()
	Equal(game.editBox:IsShown(), true, "can be dragged in Edit Mode")
	game.callbacks["EditMode.Exit"]()
	MicroMenu:SetParent(MicroMenuContainer)
	point, relativeTo = BlockAnchor()
	Equal(point .. " " .. tostring(relativeTo == MicroMenuContainer), "BOTTOMLEFT true", "back in the row")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu back")
end)

Test("hiding the whole interface (Alt+Z) moves nothing", function()
	NewGame()
	Login()
	UIParent:Hide()
	Equal(game.block:IsShown(), true, "block while the interface is hidden")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu while the interface is hidden")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH + GROWTH, "XP bar while the interface is hidden")
	UIParent:Show()
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu after")
end)

-- Where the block stands in the gamepad interface: centered between the XP bar's top and the
-- gamepad buttons' bottom, in the block's own units (UIParent units over the bags bar's scale).
local GAMEPAD_HEIGHT = (XP_BAR_HEIGHT + GAMEPAD_BUTTONS_BOTTOM) / 2 / BAGS_SCALE

Test("in the gamepad interface the block stands between the gamepad buttons and the XP bar, and nothing moves", function()
	NewGame()
	Login()
	SwitchToGamepad()
	Equal(game.block:IsVisible(), true, "block shown")
	local point, relativeTo, relativePoint, x, y = game.block:GetPoint(1)
	Equal(table.concat({ point, relativePoint, x }, " "), "CENTER BOTTOM 0", "anchor")
	Equal(relativeTo, UIParent, "anchored to")
	Near(y, GAMEPAD_HEIGHT, "height")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu")
	Near(OffsetX(BagsBar), BAGS_JOIN_X, "bags bar")
	Near(OffsetX(MultiBarBottomLeft), 0, "stacked bar")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH, "XP bar")
	SwitchToKeyboard()
	point, relativeTo = game.block:GetPoint(1)
	Equal(point .. " " .. tostring(relativeTo == MicroMenuContainer), "BOTTOMLEFT true", "back by the micro menu")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5 - GROWTH / 2, "micro menu back")
	Near(MainStatusTrackingBarContainer:GetWidth(), XP_BAR_WIDTH + GROWTH, "XP bar back")
end)

Test("logging in with the gamepad interface puts the block between the gamepad buttons and the XP bar", function()
	NewGame({ before = function()
		game.gamepad = true
		MicroMenu.shown, BagsBar.shown, MainActionBar.shown = false, false, false
		GamepadMainActionBarFrame.shown = true
		MainStatusTrackingBarContainer.top = XP_BAR_HEIGHT
		MainStatusTrackingBarContainer:ClearAllPoints()
		MainStatusTrackingBarContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
	end })
	Login()
	local point, _, _, _, y = game.block:GetPoint(1)
	Equal(point, "CENTER", "anchor")
	Near(y, GAMEPAD_HEIGHT, "height")
	-- Blizzard moves the XP bar up (a second bar to track): the block follows.
	MainStatusTrackingBarContainer.top = XP_BAR_HEIGHT * 2
	MainStatusTrackingBarContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, XP_BAR_HEIGHT)
	_, _, _, _, y = game.block:GetPoint(1)
	Near(y, (XP_BAR_HEIGHT * 2 + GAMEPAD_BUTTONS_BOTTOM) / 2 / BAGS_SCALE, "height after the XP bar moved")
end)

Test("if making room fails, the bar goes back to the game's and it says so once", function()
	NewGame({ before = function() game.moveErrors = 1 end })
	Login()
	Equal(#game.errors, 1, "errors reported")
	Equal(#game.chat, 1, "chat lines")
	Equal(game.block:IsShown(), false, "block shown")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu")
	Near(OffsetX(BagsBar), BAGS_JOIN_X, "bags bar")
	-- Later moves keep the bar as the game set it, without more messages.
	MultiBarBottomLeft:ClearAllPoints()
	MultiBarBottomLeft:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 0, 80)
	MicroMenu:Hide()
	MicroMenu:Show()
	Near(OffsetX(MultiBarBottomLeft), 0, "stacked bar")
	Equal(game.block:IsShown(), false, "block shown after")
	Equal(#game.chat, 1, "chat lines after")
end)

Test("if a move fails after the row made room, the bar still goes back to the game's", function()
	NewGame()
	Login()
	game.moveErrors = 1
	MicroMenu:Hide()
	Equal(#game.errors, 1, "errors reported")
	Equal(#game.chat, 1, "chat lines")
	Near(OffsetX(MicroMenuContainer, "BOTTOM"), 116.5, "micro menu")
	Near(OffsetX(BagsBar), BAGS_JOIN_X, "bags bar")
	for _, name in ipairs({ "MultiBarBottomRight", "MultiBarBottomLeft", "StanceBar", "PetActionBar", "PossessActionBar", "MainMenuBarVehicleLeaveButton" }) do
		Near(OffsetX(_G[name]), 0, name)
	end
end)

Test("if even putting the bar back fails, the addon leaves the bar alone", function()
	NewGame()
	Login()
	-- The game starts failing after the row made room: the next move fails, and so does putting
	-- the bar back.
	game.moveErrors = 2
	MicroMenu:Hide()
	Equal(#game.errors, 2, "errors reported")
	Equal(#game.chat, 1, "chat lines")
	MicroMenu:Show()
	MainStatusTrackingBarContainer:SetWidth(600)
	Equal(MainStatusTrackingBarContainer:GetWidth(), 600, "XP bar")
	-- Its hooks stay quiet even while the game keeps failing.
	game.brokenPoints = true
	MultiBarBottomLeft:ClearAllPoints()
	MultiBarBottomLeft:SetPoint("BOTTOMLEFT", MainActionBar, "BOTTOMLEFT", 0, 80)
	Equal(#game.errors, 2, "errors reported after")
	Equal(#game.chat, 1, "chat lines after")
end)

Test("without the micro menu it says so and stays off", function()
	NewGame({ before = function() MicroMenuContainer = nil end })
	Login()
	Equal(#game.chat, 1, "chat lines")
	Equal(game.chat[1]:find("micro menu", 1, true) ~= nil, true, "names the micro menu")
	Equal(game.ticker, nil, "updates")
end)

if failures > 0 then
	io.write(failures .. " failed\n")
	os.exit(1)
end
io.write("all passed\n")
