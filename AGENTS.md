# Am I Lagging?

Rules for this addon. The shared rules are in `../AGENTS.md`.

A bag-slot-sized block on the bottom bar that always shows the framerate and the world latency, numbers the game menu button shows only in its tooltip. Agreed with the user.

The name is "Am I Lagging?" (title case; `ADDON_TITLE` in the code, also the tooltip title and the start of chat lines). CurseForge project ID: 1720989. Folder, repo and packages are `AmILagging`, since "?" doesn't belong in file names. Renamed from "Performance Block" on 2026-10-01: the name says what the player wants to know. CurseForge search terms (fps, latency, ping) go in the summary, since the name has none. The `.toc` has `## Category: Performance` (the addon list groups by it and its search box matches it). The package ships the MIT license, like Just the Trees (user's choice, 2026-10-01).

## Look

- The first slot of the bags bar, left of the keyring: ADDON, keyring, bags, backpack. The user chose this over a separate "group of one" (2026-10-01). It is a pitch black, fully opaque face inside the game's slot frame (the game's empty-slot background was see-through; the user chose solid black, 2026-10-01); the bags bar's own frame and divider surround it.
- It is part of the whole, not pixel-matched: the art and size are read at login (and after Edit Mode) from the frames around it, with Blizzard's XML values only as fallbacks (also when a frame reports no size yet): the slot size and plain gray frame art from `CharacterReagentBag0Slot` (regular bag slots wear a gold frame, which made the block stand out). No empty-slot picture or background art: just black behind the numbers (2026-10-01).
- Numbers only, no labels: FPS on top in white, world latency below in its color, both 15 px, centered horizontally on the slot frame art. A line runs across the frame art's center (32 px wide, fading at both ends), colored by home latency with the same green/yellow/red rule (the user's choice after trying it in game, 1.1.0, 2026-10-01; it was gold before). This font's figures are old style (6 and 8 rise; 3, 4, 5, 7 and 9 drop), so each number is placed by the band from its highest to its lowest possible figure (em ratios measured from Skurri in game), centered in its half of the slot: the same gap to the line as to the slot's gray inner edge, whatever the digits. The user asked for airiness: no digit may touch the line or the border. The font is the game's own heavy number font, read from `NumberFont_Outline_Huge` (Skurri for Latin alphabets) with a normal outline, one text line per number; `STANDARD_TEXT_FONT` if that font object is missing. The user wants a font built into the game, not a bundled one, and no faux-bold tricks (drawing copies was rejected as hacky).
- The background is uniform pitch black.
- World latency only on the face: it is the delay felt in combat and movement. Home latency (chat, mail, auction house) is in the tooltip. The user chose this after it was explained; readability at true size (45 px) was the reason.
- A number wider than the slot less a 6.5 px margin each side (four-digit latency) shrinks to fit.
- Only the latency number changes color, with the game menu button's rule: green up to 300 ms, yellow over 300, red over 600. FPS stays white. (The game menu button colors by the worse of home and world; the block colors the number it shows.)
- Look changes are mocked on the design canvas first and built after the user picks.
- The numbers update once a second while the block is on screen; a number that didn't change is left alone.
- Tooltip: the title, an empty line (as the game menu tooltip has), then the game's own framerate and latency lines, FPS first to match the face (`MAINMENUBAR_FPS_LABEL`, then `MAINMENUBAR_LATENCY_LABEL` with home and world), then `v<VERSION>`. Under the framerate, "Limited by: CPU" or "Limited by: GPU" from `IsCpuBound()`, as the game's Ctrl+R counter tells it; left out when it returns nil. The game can't report GPU load; this line is what it offers (the user chose it, 2026-10-01). The tooltip stays current while open through the block's `UpdateTooltip`, which the game's tooltip calls on its own timer, as the game menu tooltip stays current.

## Chat

- Every line starts with "Am I Lagging?:" in gold (`NORMAL_FONT_COLOR`), as in Just the Trees.
- The addon writes only when something stopped working: what stopped in red (`RED_FONT_COLOR`), then what the player can do. The user chose no other messages (no login line, no slash command, no lag warning; 2026-10-01).

## Errors

- At login the addon checks the pieces it can't do without (the bags bar and its list of buttons). If one is missing, it says so in chat and does nothing else.
- Making room runs inside the game's own code, right after Blizzard moves or resizes a frame, so every hook and callback runs through `Guarded` (`xpcall` with the game's `CallErrorHandler`). An error never breaks the code that called it. The first error is reported through the game's error handler and said once in chat; the addon then puts the bar back the way the game set it (block out of the bags bar, no moves, no stretch) and keeps it so until /reload. If even that fails, it leaves the bar alone.
- If reading the numbers fails, the error is reported once, the numbers are cleared (old numbers would mislead), the updates stop and chat says so.

## Making room (agreed with the user)

The addon makes room for itself, and removing it leaves no trace.
- The block joins the bags bar the way the keyring does: `MainMenuBarBagManager:RegisterBagButton`. The bags bar then places it, spaces it, draws its divider and widens itself (`BagsBar:Layout`). It joins after Blizzard's buttons, so it is the last in the list and the leftmost slot. The block is a child of `BagsBar`, so it takes its scale and hides with it.
- Blizzard calls methods on every button in that list, so the block has them, doing nothing: `UpdateOrientation` (bags bar turned), `SetBarExpanded` (bags bar opened or closed) and `DoModeChange` (Quick Keybind mode; without it, Quick Keybind mode threw an error). The backpack's Azerite tutorial would ask each button for its bag; Azerite items don't exist in Forever.
- Edit Mode has no way for an addon to add a system (a fixed game list, layouts saved on the server), and in Camelot the row sits at a fixed offset (`MICRO_MENU_ANCHOR_OFFSET_X`), so nothing in Blizzard's layout recenters a wider row. When the bags bar is on screen, runs sideways and hangs off the micro menu by its left side, the whole row moves left by half the growth (the block plus the bags bar's padding, at its scale, in UIParent units). What the row hangs off depends on the layout (in a saved layout the action bar hangs off the micro menu; Edit Mode places bars in their default position on the screen itself), so the addon follows the anchor chains of `MainActionBar` and `MicroMenuContainer` to the frames that hang off the screen and moves each such root once.
- The bars above the row come from Blizzard's own list of bottom bars (`EditModeUtil:GetBottomActionBars()`, without `MainActionBar`): the XP bars, the action bars stacked above them (`MultiBarBottomLeft`, `MultiBarBottomRight`, `StanceBar`, `PetActionBar`, `PossessActionBar`) and the vehicle exit button. Camelot stacks them on `MainActionBar` by their left edge (`ACTION_BARS_RELATIVE_TO_BASE_POSITIONING`), so they move with the row and line up with its left end. Only bars anchored to `MainActionBar` are touched; a bar the player moved elsewhere is left as it is.
  - The XP bar containers (the bars with `ResizeContainerBars`, `UpdateDividers` and `GetExpectedSegments`) stretch by the row's growth to reach its right end, with Blizzard's own methods, as its Size setting does. `hooksecurefunc`s on their `SetSize`/`SetWidth` keep the stretch when Blizzard resizes them, and on `SetPoint` notice them moving onto or off the row. A container is only resized when its width has to change.
  - The other bars are fixed buttons and cannot stretch, so they move right by half the growth to stay centered over the row.
  - They are watched from login: Edit Mode first parks them at the screen's top left and stacks them on the action bar a moment later.
- Moves are applied in `hooksecurefunc`s on `SetPoint` and `ClearAllPoints` of each moved frame, each time Blizzard anchors it, from the points Blizzard set. Each point is remembered and moved on its own: Edit Mode gives a frame a second point when it is snapped to two others, and sets the two one after the other. The moves use Edit Mode's plain `SetPointBase`: its replaced `SetPoint` and `ClearAllPoints` also change snapping and flag anchor changes, which the addon must not do, and the plain original never reaches the addon's own hooks. A point is only set when its offset has to change. Offsets and widths are converted with effective scales, since frames can be scaled apart.
- A hook on `BagsBar:SetPoint`, and on its `OnShow`/`OnHide`, re-checks whether the row should grow. `OnShow`/`OnHide` also run when a frame above the bar is shown or hidden. "On screen" means the bar and every frame above it up to UIParent are shown: another addon may hide the bar by parenting it to a hidden frame, which leaves it shown but unseen. Hiding the whole interface (Alt+Z) hides only UIParent and changes nothing.
- While Edit Mode is open the block leaves the bags bar's list (the list is then exactly Blizzard's) and the moves and stretch are off, so Edit Mode only sees and saves the layout's own positions. On leaving Edit Mode the art is measured again and the block rejoins.
- In combat every change waits for `PLAYER_REGEN_ENABLED`: protected frames can't be moved then.
- Taint: the list entry is the addon's, so Blizzard's bags bar layout runs tainted while the block is in it. Watch for "action blocked" errors when the bags bar lays itself out in combat (picking up an item opens it).

## Never

- Never save or change an Edit Mode layout (`C_EditMode.SaveLayouts` and the like). The user rejected it: removing the addon must leave the layout as it was.
- Never move Blizzard frames other than the roots of the bottom row and the bars stacked on it as described above. The bags bar's button list is the only Blizzard list the block joins (the user chose it, 2026-10-01); no other Blizzard lists (taint).
- No SavedVariables: nothing the addon does may outlive it.

## Logo

`Logo/AmILagging-logo.svg` is the logo (the block's slot frame, white "FPS" over green "ping" and the line between them), redrawn as SVG from the first PIL script on 2026-10-04 (97% of pixels within 8 levels of the old PNG). `Logo/make_logo.py` renders the 400 x 400 CurseForge PNG and `Icon.tga`, the addon list's icon (`## IconTexture`; the user asked for the logos in game, 2026-10-04).
