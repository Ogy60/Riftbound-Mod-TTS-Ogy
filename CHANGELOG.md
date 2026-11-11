# Changelog

## 1.0.11

- Fixed: printed battlefield text still showed on top of cards lying on the battlefield. It now sits directly on the mat surface, below the cards.

## 1.0.10

- Fixed: buttons could drift out of place and pile up on top of other buttons. The blocks that carry them are now created already locked.

## 1.0.9

- Fixed: after the host switched Auto on or off, a player's control strip could show a second, shifted set of buttons.

## 1.0.8

- Token selector: added Mech, Bomb, Sand Soldier, Shadow Clone and Tentacle. Riot's gallery has no cards for them, so they show the card back with their name and stats printed on it.

## 1.0.7

- Turn phases are manual by default: press **Next phase** to go through ready, channel and draw. The host can switch **Auto: On** to run them automatically.

## 1.0.6

- Fixed: printed battlefield text floated above cards on the battlefield. It now lies on the mat, under the cards.

## 1.0.5

- Mulligan by dragging cards from your hand back onto your Main Deck, then press Mulligan done. You draw the same number; the cards you put back go to the bottom. Setting cards aside on your Base still works.

## 1.0.4

- Fixed: importing a deck stopped with a Lua error in 1.0.3.

## 1.0.3

- Fixed: runes whose printing isn't in Riot's card gallery (for example UNL-R05a) showed only a card back. They now use the same rune from another set.
- New **Bomb** marker in the supply. Riot's gallery has no Bomb token card yet.

## 1.0.2

- Fixed: after Peek, the Trash and Banish buttons sent the cards back to your hand instead of moving them.

## 1.0.1

- Table images are built in: no more pasting image links before the first game. The host can still use their own card back and mats.

## 1.0 – first public release

- Renamed to **Riftbound Mod TTS Ogy**.
- **Report a bug** button and copyable issue link on the host console; `!rb bug` in chat.
- Name, version and Riot disclaimer shown on the host console, in chat on load and in the notebook.
- Rules text is now read correctly from Riot's card data (hover text and printed battlefield text).

## Before 1.0 – private test versions

- Table with 1v1, 2v2, FFA 3 and FFA 4, one mat per table side.
- Piltover Archive deck-code import with automatic placement of legend, runes, battlefields, sideboard and tokens; champion choice from the hand.
- Mulligan, automatic turn phases, Burn Out, end-of-turn healing.
- Peek and reveal with action buttons; TOP and BOTTOM drop zones for the main deck and the rune deck.
- Marker and dice supplies, token card selector, battlefield text printed on the table.
