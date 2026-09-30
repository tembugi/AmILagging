# Performance Block

Rules for this addon. The shared rules are in `../AGENTS.md`.

A bag-slot-sized block on the bottom bar that always shows the framerate and the home and world latency, the numbers the game menu button shows only in its tooltip. Agreed with the user.

The name is "Performance Block" (folder, repo and packages `PerformanceBlock`; `ADDON_TITLE` in the code, also the tooltip title).

## Look

- One slot, the size and art of the bag buttons (45x45, `UI-HUD-ActionBar-IconFrame-Background` and `ui-hud-actionbar-iconframe-bags`).
- It sits right of the micro menu, between the red help button and the keychain.
- FPS is the main number, large and white, with a small "FPS" caption under it.
- A faint gold divider, then home and world latency side by side, smaller, each with its caption ("Home", "World") under it.
- Captions: muted gold, spaced letters (laid out letter by letter, since font strings have no letter spacing).
- Only the latency numbers change color, with the game menu button's rule: green up to 300 ms, yellow over 300, red over 600.
- The numbers update once a second.
- Tooltip: the game's own latency and framerate lines (`MAINMENUBAR_LATENCY_LABEL`, `MAINMENUBAR_FPS_LABEL`), then `v<VERSION>`.

## Never

- Never move, resize or re-anchor Blizzard's frames (the micro menu, the bags bar, the keychain). Edit Mode owns their positions.
