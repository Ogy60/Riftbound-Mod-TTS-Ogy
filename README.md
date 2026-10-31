# Riftbound Mod TTS Ogy

A Tabletop Simulator table for the Riftbound trading card game: 1v1, 2v2, FFA 3 and FFA 4 on one custom table. Paste a Piltover Archive deck code and your deck lays itself out. All controls live on the table itself, with no screen overlay, and TTS's own turn indicator shows whose turn it is.

*Unofficial fan project, free to use. Not endorsed or sponsored by Riot Games – see [Legal](#legal).*

**Found a bug or have an idea?** [Open an issue](../../issues/new/choose). In the game: press **Report a bug** on the host console or type `!rb bug` in chat.

## Install

**From the Steam Workshop:** subscribe, then TTS → Create → Singleplayer → Workshop → *Riftbound Mod TTS Ogy*.

**From GitHub:** download the zip from [Releases](../../releases) and copy `Riftbound Mod TTS Ogy.json` into `Documents\My Games\Tabletop Simulator\Saves\` (or `OneDrive\Documents\...`). Then TTS → Create → Singleplayer → Games → Save & Load → *Riftbound Mod TTS Ogy*. The table builds itself.

The table images (playmat, battlefield mat, card back) are built in, so there's nothing to set up.

**Your own images (optional):** the host can paste a link to their own card back, playmat or battlefield mat into the fields on the **TABLE – HOST** console (a corner of the table), then click somewhere else. For the mats, press **Rebuild table** afterwards. Clear a field with its **X** to go back to the built-in image. Steam's Cloud Manager (Upload → Cloud Manager in TTS) gives you a link for any image you upload.

## Playing

1. **Sit down:** press **Sit here** on the control strip at your edge of the table.
   Seats: 1v1 Red (south) vs Blue (north) · 2v2 Red + Yellow vs Blue + Green (partners opposite) · FFA 3 Red, Blue, Green · FFA 4 all four, one per table side.
2. **Host:** pick the mode on the host console.
3. **Everyone:** paste your Piltover Archive deck code into your strip → **Import**.
   - Each part goes to its own spot: legend to the Legend slot, runes to the Rune Deck, battlefields to the Battlefields pile, sideboard to the Sideboard, tokens to a pile on your Base. Everything else is shuffled into the Main Deck.
   - Your champion copies go into your **hand**, hidden from opponents. Drag one onto the Champion slot, or right-click it → **Keep as champion**. That confirms your choice: the other copies go into your deck and the deck is shuffled.
   - If you don't choose, this happens automatically at game start.
4. **Host:** **Start game** – *Random* or choose who goes first. Turn order, battlefields and opening hands follow the official rules for each mode.
5. **Mulligan:** drag up to 2 cards onto your Base → **Mulligan done** (empty Base = keep).
6. **Turns** run automatically: ready, scoring reminder, channel 2, draw 1. Press **End turn** on your strip, or use TTS's own turn button. Units heal at end of turn. First-turn rules and Burn Out are automatic.
   Host can switch **Auto: Off** to step through phases with **Next phase**.

### Your control strip

From left to right:
- Sit here
- Deck code (X clears it) · Import
- Draw 1 · Channel 1 · Next phase (only with Auto: Off)
- Points − / + · status
- Peek · Reveal
- Mulligan done · Ready all · Shuffle · Burn out · End turn
- XP − / +
- Clear

### Dice, markers and tokens

- **Dice:** each seat has two d6 and a d20 on its DICE spot.
- **Supply:** in 1v1 it sits at both sides of the table; otherwise in the table corners, each set facing its side.
  - It has piles of markers (Buff +1, Might +2 / +3 / +5, Damage 1 / 3 / 5, Stunned, Tag, Bomb) plus d6 and d20.
  - Grab one and a fresh one appears.
- **Token card selector:** shows one token card (Recruit, Sprite, Gold, …). Click **<** / **>** to pick, then drag it out. Dropping a token card back onto the pile returns it.
- Anything that falls off the table is put back automatically.

### Peek and reveal

- **Peek** puts your top card into your hand with a gold outline. Only you can see it. Right-click for the top 3.
- **Reveal** puts your top card face up on your REVEAL spot and names it in chat. Right-click for the top 3.
- After either, a button row appears on your mat: **Top of deck · Bottom of deck · Trash · Banish · To hand · Done**.
- Click a button to apply it to all highlighted cards, or drag a single card onto a button to apply it to just that card.

### Dragging cards and battlefields

- **Dragging a card:** pick it up and hold. Two glowing gold frames appear at your Main Deck, or at your Rune Deck when you hold a rune.
  - Let go on the frame marked **TOP** (the deck itself) to put the card on top.
  - Let go on the frame marked **BOTTOM** (just below the deck) to put it underneath.
- **Battlefields** print their text on the table around their spot, readable from every seat.
  - This happens automatically when the game starts, and whenever you drop a battlefield onto a battlefield spot.
  - Picking it up removes the text. Right-click → **Print text on table** also works.

### Right-click and chat

- **Right-click a card:** Reveal to everyone, Buff (+1 Might, max one), Might +2, Damage +1, Damage +3, Stun, Put on top of deck, To trash, Recycle (bottom of deck), Banish, Return to hand.
- **Chat:** `!rb help`, `!rb draw 2`, `!rb channel 1`, `!rb peek 5`, `!rb reveal 2`, `!rb token Recruit`, `!rb bug`, …

## If something looks off

* **Cards show only their back:** the card lookup failed. Type `!rb test OGN-007` in chat and add the output to a bug report. The import message also tells you how many cards were found.
* **Mats facing the wrong way:** press **Rotate mats** on the host console.

## Credits

- **Riot Games** created Riftbound. All card names, card text, card art, rules and the Riftbound name and logo belong to Riot Games. Card data and images come from Riot's [official card gallery](https://playriftbound.com/en-us/card-gallery/) and are loaded when you import a deck.
- **Piltover Archive:** deck codes are decoded by a Lua port of their open-source [RiftboundDeckCodes](https://github.com/Piltover-Archive/RiftboundDeckCodes) (Apache-2.0).
- **Riftcodex:** the community [Riftcodex](https://api.riftcodex.com) API is the fallback for card data.
- **Mod, code and table artwork:** Ogy.

## Legal

Riftbound Mod TTS Ogy was created under Riot Games' ["Legal Jibber Jabber"](https://www.riotgames.com/en/legal) policy using assets owned by Riot Games. Riot Games does not endorse or sponsor this project.

- This is an unofficial fan project. It is not affiliated with Riot Games.
- Riftbound and Riot Games are trademarks or registered trademarks of Riot Games, Inc.
- The mod is free and always will be. It has no paid features, ads or donations.
- No Riot Games assets are stored in this repository, the save file or the release downloads. Card data and images are loaded from Riot's website while you play.
- If you represent Riot Games and want anything changed or removed, please [open an issue](../../issues/new) and it will be handled right away.

The mod's own code and table artwork are licensed under the Apache License 2.0 (see [LICENSE](LICENSE) and [NOTICE](NOTICE)). That license does not cover any Riot Games material.
