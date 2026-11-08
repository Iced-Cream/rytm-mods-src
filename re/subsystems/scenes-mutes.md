# Scenes and track mutes

Question (2026-11-01): could a mod make each scene store a track mute state as well as its locks?

Method: static reading of stock OS 1.73 (`build/mainos_emac.dis`), starting from the class names in the image. The scene-edit keys and the LED pass were then checked in the emulator (`vendor/rytm-emu`, with `--watch-read`; `--break` missed PCs it should have hit while the JIT was on). Nothing has been run on the device. Symbol names are in `re/symbols.toml` under "scenes and mutes".

Status: **built as mod 0018**, masks kept in each kit's stored record, emulator-verified 2026-11-01; see mods/0018-scene-mutes.

## Mutes

Mutes belong to the project, not the kit. The change notice is `ProjectSettingsTrackMuteChangedInfo`.

- The mask is a long, bit t for track t, at +0x20 of the data object behind the settings object (project + 0x30, the object `track_selection` returns; vtable +40).
- `mute_mask_get` 0x400b6cf8 returns the mask. `track_is_muted` 0x400b6d28 tests one track.
- `track_mute_set(set, track, mute, echo)` 0x400b786c is the main setter.
  - Every UI and MIDI path goes through it: CC 94 with echo 0, NRPN 0xE5, and QuickMuteMenuView through `track_mute_toggle` 0x400b79ca.
  - It sets or clears the bit, then sends the notice with its host byte at 1.
  - With echo, it also sends CC 94 or NRPN 0xE5 out.
- `track_mute_set_silent` 0x400b6d6c is used only by the Overbridge receive path.
  - It sends the notice with its host byte at 0, so the change is not sent back to the host.
  - It has no range check and no guard.

## Scenes

- The scene locks are 48 five-byte entries in the kit's `Scenes` data: +0 value word, +2 track, +3 param (0xff when free), +4 scene.
- Editing them sends `SceneChangedInfo` (`scene_lock_set`, `scene_lock_remove`, `scene_clear`, `scenes_clear_all`). That notice is about edits, not about engaging a scene.
- The active scene is the signed byte at live kit data +0x97e (`KIT_ACTIVE_SCENE`): -1 for none, 0..11 for a scene.
- `kit_scene_set_active(kit, scene, echo)` 0x400a7d04 writes it, then calls the kit's vtable +80.
- Its callers are the only ways to engage a scene at run time:

| caller | path | echo |
|---|---|---|
| 0x4008558a | MIDI CC 92 (value - 1) | 0 |
| 0x400b2ba4 | NRPN 0xE8 | 0 |
| 0x400d1506 | SceneEditView pads (`scene_edit_keys`), only without FUNC | 1 |
| 0x400d185e | SceneSelectView pads; the active scene's own pad sends -1 | 1 |
| 0x401035dc | Overbridge receive | 0 |

The byte is saved with the kit:
- The kit loader (0x40008798) sets it directly from the stored word +0x9d7, without the setter or any notice. Values outside 0..11 become -1.
- 0x4001186c also writes it; this is probably init and was not read.

## The local-off guard

Both setters check a long in the data behind project + 236 (`project_obj_ec`): +0xa0 for scenes and +0xa4 for mutes. When it is 2, the setter does not apply the change locally but still sends it out if echo is set. This is plausibly a local-off mode; the setting is not identified. Calling the stock setters respects it automatically.

## Scene edit keys

Holding SCENE (0x13) opens SceneEditView. FUNC held first and then SCENE opened the PATTERN menu in the emulator, so the order is SCENE, then FUNC.

`scene_edit_keys` (0x400d130c) handles:
- the arrows, YES and NO, for its menu (SCENE, LOCKS, `<CLEAR>`, `<CLEAR ALL>`);
- the pads (0x90..0x9b). A press makes the pad the edited scene (+192) and, without FUNC, engages it. **SCENE + FUNC + pad edits a scene without engaging it** (emulator: footer `SCENE: 2`, SD pad green instead of cyan).

Every other key goes to `view_keys_base`, which acts only on FUNC + REC/PLAY/STOP (copy, clear, paste), and then to the views below. The trig keys reach KeyboardView (`keyboard_view_keys`, 0x400c7b18):
- **Plain trig:** plays the track and queues it for `select_track` through a 50 ms timer job. This is how a track is chosen for locking while SCENE is held (emulator: T3 shows track 3's page, with or without SCENE).
- **FUNC + trig:** returns false at 0x400c7c62 unless 0x400363bc is true. In the emulator, FUNC + T3 and SCENE + FUNC + T3/T13 caused no track select, no MIDI and no LED change (transport stopped, no record mode).
- **In the record modes** (sequencer UI state flags in `keyboard_view_keys`'s note; emulator, 2026-11-01), FUNC + trig in stock:
  - grid record (RECORD): passed down to PatternGridView, which places a trigless lock trig on an empty step;
  - step record (RECORD + STOP): KeyboardView plays and selects the track, as a plain trig does outside step record;
  - live record (RECORD + PLAY) and no record: nothing.
- Trig 13..16 have no track to select.

## LED pass

- `led_pass` (0x400a0c80) runs about 20 times a second with all 18 region bits (0x3ffff).
- `view_stack_leds` calls each view's slot 5 top first. A view draws the regions it owns and clears their bits; whatever is left, `led_pass` switches off.
- Bit 0 is the trig LEDs, bit 1 the pads. `scene_edit_leds` claims the pads and passes bit 0 on. PatternGridView draws the trig LEDs under bit 0. With the transport stopped and no record mode, nobody claims it and the trig LEDs are off.
- LEDs are set by key code with `led_set(led_manager(), code, mode, colour, level)`, which only sends a change. The playhead uses mode 1, colour 6, level 15.

So a view on top that clears bit 0 owns the trig LEDs for that pass, with no redraw request needed.

## Design

**Controls.** With SCENE held:
- FUNC + T1..T13 toggles that track's bit (T13 is FX, mute bit 12) in the edited scene's mask.
- If that scene is engaged, the toggle applies at once.
- FUNC + pad already picks a scene to edit without engaging it, so mutes can be set silently.

**Feedback.** While FUNC is held in scene edit, T1..T13 light for the tracks the edited scene mutes. Wrap `scene_edit_leds`: draw them with `led_set` and clear bit 0. The mode and colour for "muted" are to be chosen on hardware.

**Behaviour** (decided 2026-11-01):
- Engaging a scene that sets mutes **replaces** the mute state (a per-scene "sets mutes" flag; scenes without it leave mutes alone).
- Disengaging **restores** the mutes from before the scene. Hand toggles made while a scene is engaged go into that saved mask.
- The masks are kept per kit in the stored record and edited in place, so they are saved at once (decided 2026-11-01; RELOAD does not revert them).

**Hooks.**
1. **`scene_edit_keys`:** before stock, take FUNC + trig 0..12 presses (`key_pressed`, not `key_flag3`, `key_func`), toggle the bit for scene +192, set the scene's flag, and return true.
2. **`scene_edit_leds`:** after stock, if `is_key_held(KEY_FUNC)`, draw T1..T13 and clear bit 0.
3. **Wrap `kit_scene_set_active`:**
   - Before stock, if no scene is active, save `mute_mask_get` as the mask to restore later.
   - After it, if the new scene has its flag set, call `track_mute_set(set, t, m, 0)` for each track whose bit differs.
   - When the scene goes to -1, restore the saved mask the same way.
   - Read `KIT_ACTIVE_SCENE` after stock rather than trusting the argument, so the guard and the range check are respected.
   - This one hook covers pads, CC 92, NRPN and Overbridge.
4. **Wrap `track_mute_set`:** a hand toggle while a scene is engaged also goes into the saved mask. The mod's own calls must not re-enter this path.
5. **No kit load or save hooks.** A kit change runs no kit_load: it re-saves the working record and memcpys live kits, so masks attached to live buffers would be lost. Two cases still bypass the setter: a kit that loads with a scene already active, and a kit change while a scene is engaged.

**Data.**
- Per kit: 12 scenes x (13-bit mask + 1 flag) = 168 bits = 21 B.
- Stored: in the kit bytes that stock never reads (+0x832..+0x841 and +0x902..+0x916, 37 B; see [loosened-scopes.md](loosened-scopes.md)).
- Live: none. The live kit has only 8 B spare, so the mod reads and writes the current kit's stored record directly (PROJECT_IMAGE + STORED_KITS + k * STORED_KIT_SIZE, k from the working KitSlot's vtable +108). Layout in mods/0018-scene-mutes/design.md.

**Open.**
- Whether COPY/PASTE/CLEAR SCENE carry the mask.
- Whether to echo the mute changes as CC 94 out (echo 1) or keep them local (echo 0).
- With SCENE held, the mod takes FUNC + trig in every mode, so grid record's lock-trig placement and step record's track select are unavailable until SCENE is released.

**Not traced.**
- The copy/paste paths.
- Whether any engine code reads the mute mask directly rather than through the notice.
- SysEx kit dump and receive for the 21 bytes.
- The solo setters (`ProjectSettingsTrackSoloChangedInfo`) and how solo interacts with the mask.
- The 1.74 addresses.
