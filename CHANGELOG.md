# Changelog

## [0.1.2]

- Fast taps on the commander map no longer close it: a tap that arrives before the screen was redrawn now counts where it was aimed.
- A player's counters, menu and life keypad have the rotate button too, so someone across the table can turn them. They face the player again once closed.
- A tap inside a dialog redraws only what changed, such as the number tapped, instead of the whole screen, and never flashes between taps: the flash that clears the e-ink ghosting comes when the dialog closes. The table behind a dialog is redrawn when it closes.

## [0.1.1]

- Commander damage by seat: each Magic block shows the table in miniature, as its player sees it, with the damage from each opponent's commander in that opponent's seat, instead of pills with names ("Player 1 3"). With partners, the block shows the higher of the two. Tap it to open the large map, where each opponent takes or gives damage by halves, as life does.
- A player's counters come in two tabs, Counters and Commander, and lying down, when they do not fit in one column, the counters use two columns instead of pages. Shorter labels for the tax ("Tax", "Tax 1") and partners.
- The label of a row with - and + buttons no longer runs into the minus button, and the - and + of the large map are centered.
- The monarch and initiative badges sit under the player's name.
- After a full refresh, the next update waits for it to end, so a tap right after a flash no longer leaves part of the screen white on a Kindle.

## [0.1.0]

First version, with Magic: The Gathering and the Pokémon TCG.

- Setup in steps: game (with its logo), format, number of players, layout and seats, skipping steps with a single choice.
- Layouts for 2 to 6 players, from a rule: bands of one or two blocks that mirror or step, and an empty cell only to complete a two-column grid, where the controls go. Each block faces its player, with a suggested seat and a turn button at its center, which stays under the finger as the block turns. The Pokémon panel turns only between the two seats that see its block lying down.
- Magic: Standard, Commander, Two-Headed Giant and Brawl, with their starting life, poison limit and commander rules (21 combat damage from the same commander, partners apart, tax of 2 per cast; Brawl has tax but no commander damage), and Custom: 2 to 6 players, any starting life, and poison, commander damage and commander tax turned on or off. The last custom rules are kept for the next match.
- Magic counters (poison, energy, experience, rad), commander damage that also comes off the life total, the monarch, the initiative, and day or night.
- Life by halves of the block, holds for 10, a keypad on the number, and changes that wait two seconds before going into the log.
- Defeats by life, poison or commander damage: out of the game with three or more players left, an offer to end or keep playing with two.
- Pokémon turn panel: once-per-turn reminders, a coin per player, Special Conditions of each Active Pokémon (the rotation ones replace each other), adjustable poison, Retreat and "Clear conditions" to remove them, a first turn reminder and a Confused reminder.
- Pokémon Checkup for both Active Pokémon in rule order, with the damage to put on the cards, a coin per condition that asks for one (flipped only once per turn), Paralyzed recovering after its owner's next turn, and the turn passed only when every coin is flipped.
- Dice from d4 to d20, several at once; several coins and "until tails"; who starts by a d20 for everyone or by a called coin.
- A clock in minutes with pause and a round countdown, and a turn count. Time away from the table does not count.
- Undo (a change still waiting to go into the log is simply dropped; names, dice and coins are kept), a log of the match, past matches with their logs, and the match saved after every change. Starting a new match keeps the unfinished one in past matches, without a winner.
- Magic dialogs turn to any side, with the turn button fixed at the top right corner of the screen.
- Players' menu: rename, counters, concede. End of match with a winner, a draw or no winner.
- The device stays awake while the table is open, and the power button still puts it to sleep. A table left 30 minutes without a touch lets it sleep again. If it sleeps with the plugin open and the sleep screen shows the book cover, the Matkeeper cover shows instead. Nothing is drawn while it sleeps: the clock and a waiting life change catch up when it wakes up.
- The screen opens in portrait and gives the reader's rotation back on close, also when the opening fails, which shows a warning instead of closing KOReader. A part of the screen that fails to draw shows a message with a way back.
- The Back key of devices with keys goes back one screen and closes the plugin from home. Gestures the screen does not use no longer reach what is under it.
- Saves are read part by part, so a damaged part or one from another version is dropped without losing the rest.
- Interface in Portuguese, English and Spanish.
