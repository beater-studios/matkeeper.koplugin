# Matkeeper: design and tools

How the plugin works inside, for anyone who wants to understand the code or change it. To install and use it, see the [README](../README.md). A Beater Studios table counter for trading card games in KOReader, made for e-ink. `matkeeper` is the plugin identifier. The name means the keeper of the playmat, the mat a card game is played on.

## Status

- **0.1.0 (2026-11-08):** Magic: The Gathering (Standard, Commander, Two-Headed Giant, Brawl, Custom) and the Pokémon TCG as a turn panel, layouts for 2 to 6 players, dice, coins, clock, undo, log and past matches. Tested in the desktop emulator and installed on the device for testing.

## Rules and sources

Magic values come from the Comprehensive Rules of 2026-11-06: starting life (103.4, 810.4, 903.12f), poison (704.5c, 810.8d), commander damage of 21 in combat (903.10a), partners counted apart for damage and tax (702.124d), tax of 2 per cast (903.8), Brawl without commander damage (903.12h). The Custom format keeps the same numbers for poison (10) and commander damage (21) and lets the players turn each rule on or off and pick the starting life (1 to 999); `Match.custom_format` turns those choices into a format table, saved with the match. The rules let players agree on any method to decide who chooses who starts (103.1); the plugin offers a d20 for everyone, and the highest chooses.

Pokémon values come from the official rulebook of the Scarlet & Violet era and the Professor Program update of February 2026: Energy, Supporter, Retreat and Stadium once per turn; no attack and no Supporter for the player who goes first on their first turn; the coin flip winner chooses who starts; Checkup between every turn for both Active Pokémon in the order Poisoned, Burned, Asleep, Paralyzed; Poisoned puts 1 damage counter (some cards more), Burned 2 and then a coin, Asleep a coin, Paralyzed recovers after its owner's next turn; Asleep, Confused and Paralyzed replace each other, Burned and Poisoned use markers and stay; a new Poisoned or Burned replaces the old one; going to the Bench, evolving or devolving removes every condition.

Damage, prizes and the Bench are not tracked on purpose: they stay on the physical table, where dice and markers do it better than configuring each Pokémon on an e-ink screen.

## Code

| File | What it does |
|---|---|
| `rng.lua` | Park-Miller generator, so tests can repeat a sequence. |
| `layouts.lua` | Layout generation, cell rectangles, suggested seats and the conversion of touches into a seat's coordinates. |
| `games/magic.lua`, `games/pokemon.lua` | The formats and numbers of each game. |
| `match.lua` | The match: players, life and counters, conditions and Checkup, turns, dice and coins, the clock, the log, undo and saving. No screen code. |
| `history.lua` | Past matches, newest first, capped at 30. |
| `text.lua` | Durations, dates and log entries in the player's language. |
| `ui/draw.lua` | Colors, fonts sized in pixels, shapes, icon masks and pictures. |
| `ui/surface.lua` | The screen as panes, each drawn facing its seat (see below). |
| `ui/blocks.lua` | The Magic block, the Pokémon turn panel, the bar, the round menu button and the controls cell. |
| `ui/dialogs.lua` | Modal views: lists, keypad, dice, coins, Checkup, the coin call. |
| `ui/pages.lua` | Home, setup steps, past matches, a log and settings. |
| `ui/screen.lua` | The flow: setup, the table, dialogs, saving, the clock, the awake state and the Back key. |
| `state.lua` | Reads the settings file back, part by part (see Saving). |
| `screensaver.lua`, `portrait.lua`, `refresh.lua`, `awake.lua`, `sleep.lua`, `letters.lua`, `saved_state.lua` | Modules shared by the plugins of the project, copied unchanged: the cover on the sleep screen, portrait while open, the refresh count, the awake state, nothing drawn while asleep, cutting names without breaking a letter, and reading older saves. |

## Drawing at any rotation

Every pane of the screen (a block, the bar, a dialog) is drawn into a blitbuffer of its own. Before drawing, the buffer is rotated with `rotateAbsolute` to face its seat (bottom 0, left 90, top 180, right 270); the view draws in its owner's coordinates (`ctx.w` and `ctx.h` are the size the owner sees), and then the buffer is turned back to 0 and copied to the screen with a plain `blitFrom`, the fast path. KOReader's text, rectangles and colorized masks all honor the rotation, so the same view code serves every seat.

Touches go the other way: `Layouts.to_local` turns a point inside a pane into the owner's coordinates before matching the touch areas the view marked with `ctx:hit`. So "the right half of the block" is always the owner's right.

The round menu button is a transparent pane: it draws over a copy of what is under it, so it can sit on the junction of the blocks. Dialogs are a modal pane over the darkened screen, facing the player of the turn in Pokémon and a chosen side in Magic (a round button turns them; it sits at the top right corner of the screen whatever the side, so it can be tapped again in the same place, and dialogs that have it keep that corner clear). On the seats step the turn button of each block sits at its center, the one point that does not move when the block turns. The Pokémon panel is drawn only for a block wider than tall, so its blocks turn only between the two seats that see them that way (`Layouts.wide_seats`).

Each pane keeps its buffer until it changes, so a tap redraws one block and refreshes only its rectangle with a `ui` refresh, which does not flash. `refresh.lua` counts them by what is on screen: a new page or the table opening flashes once (`full`), changes inside a page or the table do not, and a flash of the whole screen comes after 8 changes in a row on the pages (redrawn whole) or 30 pane refreshes at the table. The minute clock stays out of the count. After waking up, the next refresh flashes.

A pane whose view fails to draw does not lock the screen: the error goes to the log, and the pane shows a short message that leads back to home (or closes the plugin from home). The rest of the table keeps working.

The screen opens in portrait and ignores rotation while open (`portrait.lua`), giving the reader's rotation back on close, also when the opening fails; the blocks turn inside the portrait screen. The menu opens the screen protected, and a failed opening shows a warning in the reader's language. The Back key of devices with keys closes a dialog, goes back one setup step, leaves the table for home (the match stays) and closes the plugin from home.

## Layouts

A layout is a list of bands (rows, or two columns) with one or two cells each; a cell is a player (`p`) or empty (`e`). The id encodes it: `r:p.pp.p` is one player at the top, two in the middle and one at the bottom. Every combination is generated and then filtered:

- band sizes must mirror (1-2-1, 2-2) or step (1-2, 2-2-1);
- an empty cell only completes a two-column grid: bottom right of a 2x2, middle right of a 2x3;
- every cell keeps at least 30% of the screen's smaller side.

That leaves 2 layouts for 2 players, 6 for 3, 5 for 4, 6 for 5 and 5 for 6. The face to face layout for two keeps a bar between the halves; layouts with an empty cell put the controls there; the rest get the round button at the gap junction closest to the center.

Suggested seats: cells in a band of two face the sides when there are three or more bands (or a single one); otherwise the first band faces the top and the last the bottom; columns face their side. The player turns any block on the seats step.

## Saving

`koreader/settings/matkeeper.lua` keeps the language, the current match (serialized after every change), the last setup and the layout and seats chosen for each game and player count. `koreader/settings/matkeeper_history.lua` keeps up to 30 finished matches with their logs, written only when a match ends.

`state.lua` reads every part on its own, so a part that cannot be read drops only itself: the language from a closed list, the last setup and the saved layouts only while their game, format, layout and seats still exist, the custom rules clamped, and the match through `Match.restore`, protected, which checks the type of each part, gives missing fields their defaults (a player saved before a field existed) and drops a match with a hole in the players or a format that left. A finished match never comes back. `tests/saves/` keeps files written by earlier versions, which `tests/state_spec.lua` and `check_layout.lua` open.

Undo keeps up to 60 snapshots of the players, the turn and the table states, without the clock (undoing must not turn time back) and without the log (it is cut back to its old length, keeping dice and coin results, which undo does not take back). Renaming a player and the last coin are kept too. Checkup coins are kept per turn outside the snapshots, so undoing or reopening the Checkup never flips a coin twice.

## Awake on the table

While the table is open the device stays awake (`awake.lua`): KOReader's auto suspend is paused and, on a Kindle, the idle timer of the system is reset every 4 minutes, as a touch would. powerd's `preventScreenSaver` is not used, so the power button still puts the device to sleep and a crash leaves nothing behind. Every touch at the table holds it for another 30 minutes; a table left without a touch for that long lets the device sleep again, and the next touch holds it once more. While charging the timer is not reset, as KOReader also does, so a table left 10 minutes without a touch on the charger can still go to sleep.

While the device sleeps the screen draws nothing and its timers wait (`sleep.lua`): the minute clock, the life change waiting to go into the log and the idle limit run once when it wakes up, and the screen is repainted then.

## Sleep screen

If the device sleeps with the plugin open (the table keeps it awake, so this happens on home, during setup or with the power button) and the KOReader sleep screen is set to the book cover, `assets/screensaver.png` shows instead. `matkeeper/screensaver.lua` wraps KOReader's `Screensaver.setup`: KOReader picks the image as usual, and the plugin swaps it only when the topmost full-screen window is named `matkeeper_*`. Nothing is saved, so closing the plugin brings back the book cover; powering off, restarting and the other sleep screen modes are left alone. The image is 1200x1600, twice 600x800, drawn by `tools/make_assets.py` with the plugin's own art (no game logos). The same module is used by the other plugins of the project.

## Tools

- `tools/check.sh`: every check that runs without KOReader, the same on a computer and in the CI: the tests, the texts and the package.
- `tools/check_texts.lua "t:matkeeper/ui"`: the three languages have the same keys and format markers, no dashes and no brand of e-reader, and every key the screens read exists.
- `tests/table_spec.lua`: layouts, touch conversion, the rules of both games, undo, the clock, saving, the history and the log in every language.
- `tests/state_spec.lua`: the saves of earlier versions, a match round trip, content that left, a damaged save and fields missing from an older one.
- `tools/koreader/render_screens.lua`: opens the real screens in a headless KOReader, saves each as a PNG and checks the rotated touches.
- `tools/koreader/check_layout.lua`, run in four screen sizes by `tools/koreader/check_all_sizes.sh`: every page, table and dialog in the three languages, touch areas inside their pane, interface texts that do not fit, the version on the settings page, a match resumed by a new screen (also one saved by 0.1.0), the refresh modes, the Back key and a pane that fails to draw.
- `tools/koreader/fuzz_ui.lua`, with `tools/koreader/fuzz.lua`: random taps, holds and swipes on home, setup and every layout of both games in the three languages, each run from nothing saved; it prints how to repeat each error (`SEED`, `ACTIONS`, `ONLY`).
- `tools/koreader/check_screensaver.lua`: checks when the cover replaces the sleep screen image (plugin on top, a dialog over it, another full-screen window, power off, other modes, after closing) and saves the resulting screen.
- `tools/koreader/check_rotation.lua` (cases in `rotation_cases.lua`), `check_awake.lua` and `check_sleep.lua` (cases in `sleep_cases.lua`, the table with its timers running): portrait, the awake state and nothing drawn while asleep.
- `tools/make_assets.py`: draws the icon masks, coins, dice, the banner, the header and the sleep screen cover with Pillow, and reduces the logos to the screen's 16 grays.
- `tools/package.sh`, with `tools/package_lib.sh`: builds `dist/matkeeper.koplugin.zip` and its checksum, the same zip byte for byte on any machine, and checks that every file the code loads is in it.

The emulator checks run from the plugin folder with `KOREADER_DIR` pointing at the desktop KOReader, as `tools/koreader/run_headless.sh tools/koreader/<check>.lua`, before each release and after changing the screens. The CI does not have KOReader.
