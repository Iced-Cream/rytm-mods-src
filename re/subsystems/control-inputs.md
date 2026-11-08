# Control inputs and performance macros

Question (2026-11-01): could the CTRL IN jacks drive a performance macro? The answer became mod 0017-ctrl-in-perf.

Method:
- Static reading of stock OS 1.73 (`m68k-elf-objdump` of `build/stock_mainos.bin`).
- The emulator, `vendor/rytm-emu` (github.com/amorgan101010/rytm-emu at e8e3601), run with `dtboot`. A local patch adds a watch log grouped by PC and caller, and pad LED colours.
- Nothing here has been run on the device.

Tags: **[measured]** = seen in the emulator; **[traced]** = read in the code; **[inferred]** = not confirmed either way.

## The input path

- **The converter.** Boot (`0x40000946`) writes ADLST1 = 0x0021, so ADC slots 0 and 1 convert AN1 and AN2. These are CTRL IN 1 and 2 [traced]. The rest of the ADC is in [compressor-hardware.md](compressor-hardware.md).
- **Each block.** The audio interrupt calls `adc_pedal_update` (`0x4013f1c8`) at `0x40120e94` [traced]. For each port it:
  - smooths the result with a one-pole (0.98 / 0.02, about 33 ms at 32 samples / 48 kHz);
  - maps it by the port's mode to 0..0x7fff at `0x8000fcf8 + 4p`;
  - posts event type 0x28 at most once every 50 blocks while the value moves. Where that event is handled was not traced.
- **Engine records.** Each port has a 40-byte record at `0x8000fd00 + 40p`. Its mode long is at +0; the rest are levels converted to raw ADC units by `0x4013f3fa`.
- **Modes** [traced; names from the MODE item's drawer, `0x401310fa`]:

| mode | name | value at `0x8000fcf8` |
|---|---|---|
| 0 | OFF | not updated |
| 1 | CV | CV ZERO LEVEL → 0x4000, CV MAX LEVEL → 0x7fff, clamped to 0..0x7fff |
| 2 | EXPR | the learned range → 0..0x7fff |
| 3 | FSW | not updated; MODE's changer only offers 0..2 |

In the emulator with stock defaults, CV ZERO (0 mV) is raw `0x3fa7` and CV MAX (5000 mV) is raw `0x6785` [measured].

## Port settings

- **Where they live.** The settings are device-wide, not per project. Each port has a 14-byte record at `0x405c8e54 + 14p` [traced, measured]:
  - a mode byte;
  - the footswitch destination byte;
  - six signed words in millivolts, clamped to ±5500, so the levels can be set from -5.5 V to +5.5 V. That is the settings range, not a measured input limit.
- **The block around them** [traced]:
  - The records sit inside the global config block at `0x405c8e10`: magic `COKI`, then a checksum at +4.
  - The checksum covers the declared size, starting at version 12 / size 100 at `0x405c8e18`. So the checksummed area ends at `0x405c8e84`.
  - The block is set up by `0x400fa44c`. `0x400fa4b0` validates it and accepts a declared size of up to 240.
- **Load and save** [traced]:
  - Load: `0x400fa778` copies a port's stored record into a working record.
  - Save: `0x400fa7ec` compares the working record with the stored one and writes it (`0x400fa542`) only if it differs.
  - Push: `0x4011f478` sends the record to the engine.
- **When changes take effect.** The CONTROL INPUT page edits a working copy in the view. Stock saves it and pushes it to the engine when the page is left (`0x40131346`). A MODE change has no effect on the port until then [measured].

## CONTROL IN MOD (stock)

- **The routes.** Each port has 4 routes in the project's `ControlInputParam` [traced]:
  - `0x4011f726` loads them into `0x8000ed78 + 16p`. Each route is an amount word and a target index (`track * 42 + 26 + param`) into the engine's working array `0x8000f774`.
  - The interrupt applies them at `0x40120f08..0x40120f52` through `0x4011ddbe`, the routine velocity and aftertouch also use.
- **CV is bipolar here.** In CV mode the value is re-centred first, `(v - 0x4000) * 2`, so CV ZERO means no modulation.
- **The menus.** CONTROL IN 1 MOD and 2 MOD are ModSetupViews (`0x400dcc56`). Their destination lists are a track's sound parameters (`ModDestListView`).

## Performance macro values

- **Engine state only.** The 12 values are the words at `0x8000e57c + 2k`, ranging 0..0x7f00 (knob value << 8). They are not kept in the kit or the project [traced].
  - Each block the engine glides its working copy (`0x8000f774[0..11]`) toward them (`0x40120c8e`; 0.97 / 0.03, about 22 ms).
  - It then adds the CTRL IN MOD routes, then applies the 48 performance locks (`0x40120f54..0x40120fa6`).
  - Kit loads leave these words alone. Nothing writes them on a timer.
- **The writers** [traced]:

| path | via |
|---|---|
| knob and pad events (PerformanceView `0x400cdf2a`, PerformanceEditView `0x400ce5e6`) | `0x400b2bfe(obj, idx, value, midiOut, notify)` |
| CC 35..47 in (`0x400b0498`) | thunk `0x400b90a4` → `0x4011f698` |
| a remote set path (`0x40103570`) | the thunk |

- **The setter `0x400b2bfe`:**
  - It writes through the thunk, which also notifies the observers of the engine-interface singleton (`0x40194888`, `0x40034470`).
  - It skips the engine write when the encoder destination is EXT only.
  - With `midiOut` set, it queues the value (`0x400850ca`), which `0x40085ab4` later sends as CC or NRPN.
  - With `notify` set, it pushes an Overbridge parameter change (`0x40102264`, `ObAsyncCommInterface`).
  - It raises no DataChangeInfo, so the kit is not marked edited. The device confirms this for a knob turn.
- **The display.** The values show on the pad LEDs in PERF mode, not on the OLED.
  - PerformanceView's draw (`0x400ce238`) reads each value back (`0x400b90cc` → `0x4011f6ac`) and scales its pad's RGB by value / 0x3fff (`0x4006d3ce`) [traced, measured].
  - The PERF key LED tracks whether any value is nonzero (`0x400b90d8`) [inferred].
- **Pad pressure.** Pad pressure 0x40 sets 0x2000. A lift that streams pressure down to 0 leaves the macro at 0 [measured].
- **The lock setup is kit data.** It is stored at kit +0x832 and live at +0x79e (see [loosened-scopes.md](loosened-scopes.md)).

## The persisted image and the gap at 0x405c8e84

- **The saved image.** The 2,096,059 bytes from `0x405c8e10` are saved and restored as a single block [traced, measured]:
  - The power-fail handler writes them to eMMC slots `0x7a000` / `0x7c000` (`0x4012259e`, reading in `0x40122156`).
  - Boot reads them back through the eMMC copy (`0x4009256e` → memcpy `0x40098b54`).
  - The reset memory clear (`0x4000085a`) zeroes the region first. Nothing else clears it.
- **The gap.** `0x405c8e84..0x405c8f0f` (140 B) lies between COKI's checksummed end and a saved random seed (`0x405c8f10`, `0x4002a6e0`) and counter (`0x405c8f14`).
  - **Static:** no absolute reference, register-relative access or table entry lands in it.
  - **Emulator:** watched over a cold boot, a power-fail save and a restore boot, only the three whole-image paths above touched it. Marker words poked into it survived a power-off and a cold boot in a fresh process [measured].
  - **Not covered:** UI settings edits beyond 0017's own, project and kit saves, OS upgrade, factory reset.
  - Nothing checksums or initialises the gap, so a user of it needs its own tag.

## ControlInputConfig (the CONTROL INPUT 1 / 2 page)

- **The view.** Its port is at `view + 432` and the working record at `view + 436` (mode first) [traced].
- **rebuild** (`0x40131496`):
  - It builds MODE (label `0x401302a4`, drawer `0x401310fa`, changer `0x4013197c`, which re-runs rebuild).
  - It then branches on the mode: CV at `0x401315c0`, EXPR at `0x40131764`, FSW at `0x40131806`, OFF at `0x40131956`.
  - All branches meet at `0x40131962`, which restores the cursor (vtable +28) and returns.
  - In the OFF branch `fp` is never loaded with the append function.
- **Items.** Each item is built like AudioRoutingMenuView's:
  - four std::functions: label, empty, drawer, changer, each `{data, -, manager, invoker}`;
  - a 0x54-byte MenuItem from `0x40072f50(item, f1, f2, f3, f4, -1, 8)`;
  - an append through the view's vtable +8;
  - the std::functions destroyed by `0x401709c6`.
- **Value drawing.** Values are drawn by `0x400712d4(canvas, 0x417e3884, x + 19, y + 2, 4, fmt, ...)`.

## Mod 0017-ctrl-in-perf

Status: built; every check passed in the emulator; not yet run on hardware.

- **PERF DEST** (OFF, PF1..PF12) is appended at `0x40131962` in CV and EXPR modes.
  - It is stored in the gap: `CIPF` at `0x405c8e84`, a version byte at +4, then one byte per port at +5 and +6.
  - A bad tag reads as OFF. The first change writes a fresh record.
- **The interrupt detour** (`0x40120e9e`, right after `adc_pedal_update`) writes each mapped macro's target every block, so the CV always wins over the knob and the pads.
  - CV maps ZERO..MAX to 0..127 (`(v - 0x4000) * 2`, clamped). EXPR maps straight through.
  - The step changes only when the port moves more than 0.75 of a step from the current one.
- **The trade-off.** Writing the target, rather than adding to the working copy as CONTROL IN MOD does, adds the engine's 22 ms glide. In return, the pad LEDs show the value.
- **Measured in the emulator:**
  - ZERO / midpoint / MAX → 0 / 63 / 127.
  - Port 2 → PF3 works on its own.
  - The value range stops at both ends.
  - The item shows and hides with the mode.
  - The setting survives a power-off and a cold boot.

## Emulator notes

- After `--load`, `--instr` counts from the snapshot's clock, but press times are absolute. Presses before the snapshot's clock are silently skipped.
- Use `DTBOOT_STEPS` for screen captures. `DTBOOT_END_PNG` returns a stale frame after a snapshot load.
- A blank flash and card boot with three notices (improved tuning, MISSING CAL. SYNTH, NO FACTORY SAMPLES). Three NO presses clear them.
- The ADC page is plain memory: poke ADRSLT0/1 at `0xfc094012` / `0xfc094014`.
- In zsh, an unquoted variable is not word-split. Pass a built-up option list as `${=P}`.
