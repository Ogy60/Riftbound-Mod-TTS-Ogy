# Maintaining Riftbound Mod TTS Ogy

Notes for working on the mod. Player information is in the [README](README.md).

## Project layout

```
src/Global.lua                   the whole mod (TTS Global script)
save/Riftbound Mod TTS Ogy.json  the save without its script
assets/                          original table artwork (card back, playmat, battlefield mat)
tools/build.py                   checks the script, builds dist/ (playable save + release zip)
tools/make_mat.py                redraws assets/playmat.png from the zone layout in Global.lua
tools/audit_layout.py            checks every mode for overlapping or off-table elements
tools/ref_decode.py              Python mirror of the deck-code decoder for testing
tests/fixtures/                  Piltover Archive's golden deck codes
```

## Making a release

1. Edit `src/Global.lua` and raise `MOD_VERSION`. Add a line to `CHANGELOG.md`.
2. Run `python tools/build.py`. Then test `dist/Riftbound Mod TTS Ogy.json` in TTS: import a deck with cards from the newest set, and play a few turns in 1v1 and one 4-player mode.
3. Commit, tag (`git tag v1.1`), push, and attach the zip from `dist/` to a GitHub release.
4. In TTS, load the tested save → Upload → Workshop Upload, and update the existing Workshop item instead of creating a new one.

## When a new set comes out

- Add its number to the set table at the deck-code decoder in `src/Global.lua` and in `tools/ref_decode.py`. Copy any change from [RiftboundDeckCodes](https://github.com/Piltover-Archive/RiftboundDeckCodes).
- Check that cards from the new set import with images and text.

## If imports show only card backs for everyone

Riot has probably changed their card gallery page. The reader is `loadOfficial` / `officialItemRange` in `src/Global.lua`.

## Display tweaks in the script

* **Button text upside down:** change `BTN_ROT_OFFSET` at the top of `src/Global.lua` (180 by default; try 0).
* **Buttons too big / small:** change `BTN_UNITS` (default 450).

## Table images

The card back, playmat and battlefield mat are hosted in Ogy's Steam Cloud. Their links are `DEFAULT_BACK_URL`, `DEFAULT_MAT_URL` and `DEFAULT_BF_URL` at the top of `src/Global.lua`, and every copy of the mod loads them from there.

- **Never delete these three files from the TTS Cloud Manager**, or every copy of the mod loses its table images.
- To change an image: edit it in `assets/` (the playmat can be redrawn with `tools/make_mat.py`), upload it with Upload → Cloud Manager, put the new link into `src/Global.lua`, and release a new version. Keep the old file in the Cloud Manager so older versions keep working.
