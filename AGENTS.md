# Performance Block

Rules for this addon. The shared rules are in `../AGENTS.md`.

A bag-slot-sized block on the bottom bar that always shows the framerate and the world latency, numbers the game menu button shows only in its tooltip. Agreed with the user.

The name is "Performance Block" (folder, repo and packages `PerformanceBlock`; `ADDON_TITLE` in the code, also the tooltip title).

## Look

- A slot the size and art of the bag buttons (45x45, `UI-HUD-ActionBar-IconFrame-Background` and `ui-hud-actionbar-iconframe-bags`), and nothing more: an outer frame of its own made it pop next to the bag slots.
- It sits between the red help button (end of the micro menu) and the keychain (start of the bags bar), as part of the bar.
- Numbers only, no labels: FPS on top in white, world latency below in its color, both 16 px, bold-looking (four copies: two outlined underneath, two plain on top, 1 px apart; there is no bold number font) and centered on the slot frame art, mirrored above and below a gold line at its center (32 px wide, fading at both ends). The number font sits low in its box, so numbers are raised 1 px.
- The slot background stays uniform, the same art as the bag slots.
- World latency only on the face: it is the delay felt in combat and movement. Home latency (chat, mail, auction house) is in the tooltip. The user chose this after it was explained; readability at true size (45 px) was the reason.
- A number wider than the slot less a 5 px margin each side (four-digit latency) shrinks to fit.
- Only the latency number changes color, with the game menu button's rule: green up to 300 ms, yellow over 300, red over 600. FPS stays white.
- Look changes are mocked on the design canvas first and built after the user picks.
- The numbers update once a second.
- Tooltip: the game's own latency and framerate lines (`MAINMENUBAR_LATENCY_LABEL`, with home and world, and `MAINMENUBAR_FPS_LABEL`), then `v<VERSION>`.

## Making room (agreed with the user)

The addon makes room for itself, and removing it leaves no trace:
- When Edit Mode attaches the bags bar by its left side, the bags bar moves right (`BAGS_SHIFT`) while the addon runs, and the block takes the room. The slot art keeps 2 px clear of the micro menu's frame art (which reaches 8 px past its buttons) and of the bags bar's (6 px before its first slot). Frames Edit Mode attached to the bags bar (the right gryphon) follow it.
- The shift is applied in a `hooksecurefunc` on `BagsBar:SetPoint`, each time Edit Mode anchors the bags bar, from the anchor Edit Mode set.
- While Edit Mode is open the shift is off and the block is hidden, so Edit Mode only sees and saves the layout's own positions.
- When the bags bar is protected in combat, the move waits for `PLAYER_REGEN_ENABLED`.
- If the bags bar is placed on its own (not attached by its left side), nothing moves and the block sits just left of it.

## Never

- Never save or change an Edit Mode layout (`C_EditMode.SaveLayouts` and the like). The user rejected it: removing the addon must leave the layout as it was.
- Never move Blizzard frames other than the bags bar as described above.
- No SavedVariables: nothing the addon does may outlive it.
