# Performance Block

Rules for this addon. The shared rules are in `../AGENTS.md`.

A bag-slot-sized block on the bottom bar that always shows the framerate and the world latency, numbers the game menu button shows only in its tooltip. Agreed with the user.

The name is "Performance Block" (folder, repo and packages `PerformanceBlock`; `ADDON_TITLE` in the code, also the tooltip title).

## Look

- A group of one, like the micro menu and the bags: one slot drawn as the game draws an empty slot (background, slot art for the gray inner edge, slot frame), inside its own outer group frame.
- It is part of the whole, not pixel-matched: the art and sizes are read at login (and after Edit Mode) from the frames around it, with Blizzard's XML values only as fallbacks: the group frame and its reach from `BagsBar.BorderArt`, the slot size and plain gray frame art from `CharacterReagentBag0Slot` (regular bag slots wear a gold frame, which made the block stand out), the empty-slot layers from `ActionButton1.SlotBackground` and `.SlotArt`, and the micro menu's frame reach from `MicroMenu.BorderArt`. The user asked for this after rounds of pixel fixes.
- It sits between the red help button (end of the micro menu) and the keychain (start of the bags bar), as part of the bar.
- Numbers only, no labels: FPS on top in white, world latency below in its color, both 16 px, bold-looking (four copies: two outlined underneath, two plain on top, 1 px apart; there is no bold number font) and centered on the slot frame art, mirrored above and below a gold line at its center (32 px wide, fading at both ends). The number font sits low in its box, so numbers are raised 1 px.
- The slot background stays uniform, the same art as the game's slots.
- World latency only on the face: it is the delay felt in combat and movement. Home latency (chat, mail, auction house) is in the tooltip. The user chose this after it was explained; readability at true size (45 px) was the reason.
- A number wider than the slot less a 6.5 px margin each side (four-digit latency) shrinks to fit.
- Only the latency number changes color, with the game menu button's rule: green up to 300 ms, yellow over 300, red over 600. FPS stays white.
- Look changes are mocked on the design canvas first and built after the user picks.
- The numbers update once a second.
- Tooltip: the game's own latency and framerate lines (`MAINMENUBAR_LATENCY_LABEL`, with home and world, and `MAINMENUBAR_FPS_LABEL`), then `v<VERSION>`.

## Making room (agreed with the user)

The addon makes room for itself, and removing it leaves no trace. Edit Mode lays out the bottom row from the micro menu container: the action bar hangs off its left, the bags bar off its right, the gryphons off those.
- When the bags bar is attached by its left side, the block takes the bags bar's anchor, so it joins the micro menu exactly as the bags did.
- The bags bar moves right so it joins the block the same way: the same overlap of group frames as the micro menu and bags had. The math is in UIParent units, since the micro menu and bags can be scaled apart.
- When the bags hang off the micro menu container, the container moves left by half the row's growth, so the row grows evenly on both sides and stays centered under the XP bar and top row.
- Both moves are applied in `hooksecurefunc`s on `BagsBar:SetPoint` and `MicroMenuContainer:SetPoint`, each time Edit Mode anchors them, from the anchor Edit Mode set. The moves themselves use Edit Mode's plain `SetPointBase` and `ClearAllPointsBase`: its replaced `SetPoint` and `ClearAllPoints` also change snapping and flag anchor changes, which the addon must not do.
- While Edit Mode is open the moves are off and the block is hidden, so Edit Mode only sees and saves the layout's own positions. On leaving Edit Mode the art is measured again.
- When either frame is protected in combat, the move waits for `PLAYER_REGEN_ENABLED`.
- If the bags bar is placed on its own (not attached by its left side), nothing moves and the block stands just left of it.
- The XP bar and the top action row cannot grow with the row (the XP bar's width is an Edit Mode size setting; the row is 12 fixed buttons), so they stay centered, slightly shorter than the bottom row at both ends.

## Never

- Never save or change an Edit Mode layout (`C_EditMode.SaveLayouts` and the like). The user rejected it: removing the addon must leave the layout as it was.
- Never move Blizzard frames other than the bags bar and the micro menu container as described above, and never insert the block into Blizzard's own layout lists (taint).
- No SavedVariables: nothing the addon does may outlive it.
