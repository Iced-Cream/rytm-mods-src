# 0018 scene mutes - status and outstanding work

## What it does

| gesture | does |
|---|---|
| hold SCENE, then FUNC + T1..T13 | toggles that track (T13 is FX) in the edited scene's mask and marks the scene |
| SCENE + FUNC held | T1..T13 lit for the tracks the edited scene mutes |
| engage a marked scene | the mutes become its mask |
| engage an unmarked scene, or none | the mutes from before the first scene come back |
| a mute by hand or MIDI while a scene is engaged | goes into the saved state too, so disengaging keeps it |
| `<CLEAR>` / `<CLEAR ALL>` | also drop the edited scene's / every scene's mask and mark |

SCENE has to be held long enough for scene edit to open before FUNC goes down.
FUNC pressed straight after SCENE does not open it, so nothing reaches the mod
(emulator: FUNC 50M after SCENE, no footer; 250M after, footer).

FUNC + pad, stock, picks a scene to edit without engaging it, so a mask can be
set silently.

Each kit has its own marks and masks, kept with the kit in the project. Editing
them is saved at once: RELOAD KIT and 0010's A/B do not revert them.

## How

See re/subsystems/scenes-mutes.md for the trace.

- `sm_keys`, SceneEditView's vtable slot 2. Plain trigs fall through to KeyboardView's
  track select; with FUNC that path does nothing in stock.
- `sm_leds`, slot 5. Draws the trig LEDs with `led_set` before stock and clears
  LED_REGION_TRIGS, so PatternGridView and led_pass leave them alone. Lit is the
  playhead's mode 1, colour 6, level 15.
- `sm_clear` / `sm_clear_all`, the constructor's two invoker immediates.
- `ksa_hook`, kit_scene_set_active's entry: every pad, CC 92, NRPN and Overbridge
  engage goes through it. It reads the active scene back after stock, so stock's
  guard and range check decide.
- `tms_hook`, track_mute_set's entry. The mod's own changes set `sm_busy` and pass
  straight through.

All mute changes are `track_mute_set(..., echo 0)`: notices and screens follow,
nothing goes out as CC 94.

**Storage.** A kit change copies live kits with memcpy and runs no kit_load, and
the live kit has only 8 spare bytes, so the masks cannot travel with live kits.
They live instead in the current kit's record in the stored project image
(PROJECT_IMAGE + STORED_KITS + k * STORED_KIT_SIZE), read and written in place:

| offset | holds |
|---|---|
| +0x832 | marks, bit s: scene s sets mutes |
| +0x834 + 2s | scene s's mask, s = 0..6 |
| +0x902 + 2s - 14 | scene s's mask, s = 7..11 |
| +0x90c | 0x53 once written; without it the record reads empty |

Stock never reads or writes these bytes (loosened-scopes.md), and the stored image
persists whole, so they survive saves and power cycles. k is the working KitSlot's
vtable +108. `sm_open` zeroes the fields and sets the tag on the first write;
`<CLEAR ALL>` clears only the tag. Whole-image copies carry the masks; copying a
kit through a live buffer does not.

The code is split: wrappers, helpers and run-time state in cave10 (532 of 552 B),
the scene-edit hooks and mask accessors in cave18 (`.sme`, 482 of 496 B). Both
pools are full.

## Verified

Emulator, 2026-11-01, 0018 alone on stock:
- SCENE + FUNC + T3: mask 0 = 0x0004, scene marked, no track select, mutes unchanged.
- SCENE + BD: scene 1 engaged, mutes saved (0), mute mask 4.
- CC 94 on track 1 while engaged: mute mask 5, saved 1. CC 92 = 0: mute mask 1.
- SCENE + FUNC held: LED group 0 9a (T3 lit) against aa with no mask.
- `<CLEAR>` and `<CLEAR ALL>` on the engaged scene: mask and mark gone, mutes 0, CLEARED popup.

Phase 2, same day, against the stored record (kit 1's at 0x4076631b):
- SCENE + FUNC + T3: marks 0x0001 at +0x832, scene 1's mask 0x0004, tag 0x53.
- Power-off save, cold boot, SCENE + BD: mute mask 4.
- Kit change to A02, SCENE + BD: mutes untouched, kit 2's record untouched.

Not yet on hardware.

## Outstanding

- Hardware: the gestures, the LED colour, and that the timing above holds.
- Not checked: SAVE PROJECT and project load from the +Drive (the image is
  written and read whole, so expected to carry them), and the power-fail save on
  hardware.
- Kit copy/paste and SysEx kit transfer go through a live buffer and do not carry
  the masks; clearing a kit leaves them.
- A kit change while a scene is engaged keeps the old saved mutes; a kit that
  loads with a scene active never saved any, so disengaging leaves the mutes as
  they are.
- While SCENE is held the mod takes FUNC + trig in every mode. Stock's own uses,
  hidden until SCENE is released (emulator, 2026-11-01): grid record places a
  trigless lock trig; step record (RECORD + STOP) selects and previews the track.
  Live record and no record do nothing with it.
- COPY / PASTE SCENE do not carry the mask.
- track_mute_set_silent (Overbridge) bypasses tms_hook.
