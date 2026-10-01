# Am I Lagging?

Rules for this addon. The shared rules are in `../AGENTS.md`.

A bag-slot-sized block on the bottom bar that always shows the framerate and the world latency, numbers the game menu button shows only in its tooltip. Agreed with the user.

The name is "Am I Lagging?" (title case; `ADDON_TITLE` in the code, also the tooltip title). Folder, repo and packages are `AmILagging`, since "?" doesn't belong in file names. Renamed from "Performance Block" on 2026-10-01: the name says what the player wants to know. CurseForge search terms (fps, latency, ping) go in the summary, since the name has none.

## Look

- The first slot of the bags bar, left of the keyring: ADDON, keyring, bags, backpack. The user chose this over a separate "group of one" (2026-10-01). It is drawn as the game draws an empty slot (background, slot art for the gray inner edge, slot frame); the bags bar's own frame and divider surround it.
- It is part of the whole, not pixel-matched: the art and size are read at login (and after Edit Mode) from the frames around it, with Blizzard's XML values only as fallbacks: the slot size and plain gray frame art from `CharacterReagentBag0Slot` (regular bag slots wear a gold frame, which made the block stand out), the empty-slot layers from `ActionButton1.SlotBackground` and `.SlotArt`.
- Numbers only, no labels: FPS on top in white, world latency below in its color, both 15 px, centered horizontally on the slot frame art. A gold line runs across the frame art's center (32 px wide, fading at both ends). This font's figures are old style (6 and 8 rise; 3, 4, 5, 7 and 9 drop), so each number is placed by the band from its highest to its lowest possible figure (em ratios measured from Skurri in game), centered in its half of the slot: the same gap to the line as to the slot's gray inner edge, whatever the digits. The user asked for airiness: no digit may touch the line or the border. The font is the game's own heavy number font, read from `NumberFont_Outline_Huge` (Skurri for Latin alphabets) with a normal outline, one text line per number; `STANDARD_TEXT_FONT` if it fails to load. The user wants a font built into the game, not a bundled one, and no faux-bold tricks (drawing copies was rejected as hacky).
- The slot background stays uniform, the same art as the game's slots.
- World latency only on the face: it is the delay felt in combat and movement. Home latency (chat, mail, auction house) is in the tooltip. The user chose this after it was explained; readability at true size (45 px) was the reason.
- A number wider than the slot less a 6.5 px margin each side (four-digit latency) shrinks to fit.
- Only the latency number changes color, with the game menu button's rule: green up to 300 ms, yellow over 300, red over 600. FPS stays white.
- Look changes are mocked on the design canvas first and built after the user picks.
- The numbers update once a second.
- Tooltip: the title, an empty line (as the game menu tooltip has), then the game's own framerate and latency lines, FPS first to match the face (`MAINMENUBAR_FPS_LABEL`, then `MAINMENUBAR_LATENCY_LABEL` with home and world), then `v<VERSION>`.

## Making room (agreed with the user)

The addon makes room for itself, and removing it leaves no trace.
- The block joins the bags bar the way the keyring does: `MainMenuBarBagManager:RegisterBagButton`. The bags bar then places it, spaces it, draws its divider and widens itself (`BagsBar:Layout`). It joins after Blizzard's buttons, so it is the last in the list and the leftmost slot. The block is a child of `BagsBar`, so it takes its scale and hides with it. It answers the calls the bags bar makes on its buttons (`UpdateOrientation`, `SetBarExpanded`) with nothing, as the keyring does. (The backpack's Azerite tutorial would ask it for a bag ID; Azerite items don't exist in Forever.)
- Edit Mode has no way for an addon to add a system (a fixed game list, layouts saved on the server), and in Camelot the row sits at a fixed offset (`MICRO_MENU_ANCHOR_OFFSET_X`), so nothing in Blizzard's layout recentres a wider row. When the bags bar hangs off the micro menu by its left side and runs sideways, the whole row moves left by half the growth (the block plus the bags bar's padding, at its scale, in UIParent units). What the row hangs off depends on the layout (in a saved layout the action bar hangs off the micro menu; Edit Mode places bars in their default position on the screen itself), so the addon follows the anchor chains of `MainActionBar` and `MicroMenuContainer` to the frames that hang off the screen and moves each such root once.
- The moves are applied in `hooksecurefunc`s on `SetPoint` of each moved frame, each time Blizzard anchors them, from the anchor Blizzard set; a hook on `BagsBar:SetPoint` re-checks whether the row should grow. The moves use Edit Mode's plain `SetPointBase` and `ClearAllPointsBase`: its replaced `SetPoint` and `ClearAllPoints` also change snapping and flag anchor changes, which the addon must not do.
- While Edit Mode is open the block leaves the bags bar's list (the list is then exactly Blizzard's) and the moves are off, so Edit Mode only sees and saves the layout's own positions. On leaving Edit Mode the art is measured again and the block rejoins.
- When any moved frame or the bags bar is protected in combat, the change waits for `PLAYER_REGEN_ENABLED`.
- Taint: the list entry is the addon's, so Blizzard's bags bar layout runs tainted while the block is in it. Watch for "action blocked" errors when the bags bar lays itself out in combat (picking up an item opens it).
- In the Camelot layout the bars above the row (XP bars, the top action row) stack on the main action bar by their left edge (`ACTION_BARS_RELATIVE_TO_BASE_POSITIONING`), so they move with the row and line up with its left end. The XP bar containers (`MainStatusTrackingBarContainer`, `SecondaryStatusTrackingBarContainer`) stretch by the row's growth to reach its right end, using Blizzard's own `ResizeContainerBars` and `UpdateDividers`, as its Size setting does; a `hooksecurefunc` on their `SetSize`/`SetWidth` keeps the stretch when Blizzard resizes them. The action bars stacked above the row (`MultiBarBottomLeft`, `MultiBarBottomRight`, `StanceBar`, `PetActionBar`, `PossessActionBar`, when anchored to `MainActionBar`) are fixed buttons and cannot stretch, so they move right by half the row's growth to stay centered over it, with the same hooks, Edit Mode and combat handling as the row moves. They are watched from login: Edit Mode first parks them at the screen's top left and stacks them on the action bar a moment later. A frame is only touched when its offset has to change.

## Never

- Never save or change an Edit Mode layout (`C_EditMode.SaveLayouts` and the like). The user rejected it: removing the addon must leave the layout as it was.
- Never move Blizzard frames other than the roots of the bottom row and the bars stacked above it as described above. The bags bar's button list is the only Blizzard list the block joins (the user chose it, 2026-10-01); no other Blizzard lists (taint).
- No SavedVariables: nothing the addon does may outlive it.
