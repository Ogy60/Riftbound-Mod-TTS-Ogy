# Riftbound Mod TTS Ogy

A Tabletop Simulator table for the Riftbound trading card game: 1v1, 2v2, FFA 3 and FFA 4 on one custom table. Paste a Piltover Archive deck code and your deck lays itself out. All controls live on the table itself, with no screen overlay, and TTS's own turn indicator shows whose turn it is.

**Found a bug or have an idea?** [Open an issue](../../issues/new/choose). In the game: press **Report a bug** on the host console or type `!rb bug` in chat.

## Install

**From the Steam Workshop:** subscribe, then TTS → Create → Singleplayer → Workshop → *Riftbound Mod TTS Ogy*.

**From GitHub:** download the zip from [Releases](../../releases) and copy `Riftbound Mod TTS Ogy.json` into `Documents\My Games\Tabletop Simulator\Saves\` (or `OneDrive\Documents\...`). Then TTS → Create → Singleplayer → Games → Save & Load → *Riftbound Mod TTS Ogy*. The table builds itself.

**One-time host setup** (only for the GitHub version or your own copy):
1. In TTS, open Upload → Cloud Manager and upload `card_back.png`, `playmat.png` and `battlefield_mat.png`.
2. Click an image in the Cloud Manager to copy its link, paste it into the matching field on the **TABLE – HOST** console (a corner of the table), then click somewhere else.
3. Press **Rebuild table** after adding the mat links, then save the game.

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
  - It has piles of markers (Buff +1, Might +2 / +3 / +5, Damage 1 / 3 / 5, Stunned, Tag) plus d6 and d20.
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
* **Button text upside down:** change `BTN_ROT_OFFSET` at the top of the script (180 by default; try 0).
* **Buttons too big / small:** change `BTN_UNITS` (default 450).
* **Mats facing the wrong way:** press **Rotate mats** on the host console.

## Development

```
src/Global.lua            the whole mod (TTS Global script)
save/Riftbound Mod TTS Ogy.json the save without its script
assets/                   original table artwork (card back, playmat, battlefield mat)
tools/build.py            checks the script, builds dist/ (playable save + release zip)
tools/make_mat.py         redraws assets/playmat.png from the zone layout in Global.lua
tools/audit_layout.py     checks every mode for overlapping or off-table elements
tools/ref_decode.py       Python mirror of the deck-code decoder for testing
tests/fixtures/           Piltover Archive's golden deck codes
```

**Making a release:**
1. Edit `src/Global.lua` and raise `MOD_VERSION`. Add a line to `CHANGELOG.md`.
2. Run `python tools/build.py`. Then test `dist/Riftbound Mod TTS Ogy.json` in TTS: import a deck with cards from the newest set, and play a few turns in 1v1 and one 4-player mode.
3. Commit, tag (`git tag v4.0.1`), push, and attach the zip from `dist/` to a GitHub release.
4. In TTS, load the tested save → Upload → Workshop Upload, and update the existing Workshop item instead of creating a new one.

**When a new set comes out:**
- Add its number to the set table at the deck-code decoder in `src/Global.lua` and in `tools/ref_decode.py`. Copy any change from [RiftboundDeckCodes](https://github.com/Piltover-Archive/RiftboundDeckCodes).
- Check that cards from the new set import with images and text.

**If imports suddenly show only card backs for everyone:** Riot has probably changed their card gallery page. The reader is `loadOfficial` / `officialItemRange` in `src/Global.lua`.

## Credits and license

Code and original artwork: Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE).

- **Deck codes:** decoded by a Lua port of Piltover Archive's open-source [RiftboundDeckCodes](https://github.com/Piltover-Archive/RiftboundDeckCodes) (Apache-2.0).
- **Card data and images:** loaded from Riot's official card gallery when you import, with the community [Riftcodex](https://api.riftcodex.com) API as fallback. No card images or other Riot assets are stored in this repository or in the save.

Riftbound Mod TTS Ogy was created under Riot Games' "Legal Jibber Jabber" policy using assets owned by Riot Games. Riot Games does not endorse or sponsor this project.
