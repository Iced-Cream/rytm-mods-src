# Sound scope under the loosened rule (2026-10-20)

Question: can core-ar2 use live sound bytes that stock reads, provided stock only ever holds them
at one fixed value and every stock reader is hooked so it still sees that value?
Stock OS 1.73 (`/tmp/claude-0/analysis/stock173.dis`), checked statically and in the emulator.
Every address below was also checked byte for byte in 1.74 (see the last table).

**Answer:** yes, for the 8 route amount low bytes. Stock only ever gives them the value 0. Only
two kinds of stock code read them in a way that could change what stock does: the engine upload
(2 sites) and the menus' getAmount (2 sites). Under the loosened rule the sound scope is
**56 bits**, set by the stored side. voice-dac (39 bits) plus lfo-rnd (16 bits) is 55 bits, so
both fit. No other live sound byte qualifies (Q2).

## Q1. The route amount low bytes

### Layout (traced, emulator-confirmed)

The live `sound_t` is 0x98 bytes. It holds two arrays of four `modTarget_t` entries. Each entry
is 3 bytes: a big-endian `s16` amount word, then a `u8` destination.

| route | velocity word / **low byte** / dest | aftertouch word / **low byte** / dest |
|---|---|---|
| 0 | +0x70 / **+0x71** / +0x72 | +0x8c / **+0x8d** / +0x8e |
| 1 | +0x73 / **+0x74** / +0x75 | +0x8f / **+0x90** / +0x91 |
| 2 | +0x76 / **+0x77** / +0x78 | +0x92 / **+0x93** / +0x94 |
| 3 | +0x79 / **+0x7a** / +0x7b | +0x95 / **+0x96** / +0x97 |

- **Correction to the brief:** the aftertouch low bytes are +0x8d, +0x90, +0x93 and +0x96.
  The offsets in the brief (+0x8e, +0x91, +0x94, +0x97) are the aftertouch *destination* bytes,
  which stock writes with real values. The velocity offsets in the brief were right. voice-dac
  uses the right offsets (`OFF_RTE_AT = 0x8d`).
- **What the word holds:** the amount is the high byte (-128..127), so the word is an 8.8 value
  with a fraction stock never sets.
  - The engine multiplies by the whole word (`0x4011ddbe`), so a low byte would add up to one
    more amount step of modulation.
  - The display rounds the whole word toward zero (`0x4004b878`: `+255` if negative, then
    `asr 8`).
  - The knob edit takes `getAmount >> 8` (`0x4004c09e..0x4004c0c2`).
- **Live address:** the working kit's sound 0 is at 0x4125590d (project 0x407c89cb +
  0xa8cf18 + 42). It holds "KICK DIST" with the default routes, which confirms the address
  formula for 1.73.

### Stock writers: all of them give the low byte 0

| writer | address (1.73) | what it writes | evidence |
|---|---|---|---|
| route load (sound_load, pool, project, library, SysEx sound/kit) | `0x40008138` (`movew (s8 stored)<<8`); loops at `0x400081b8` (velocity), `0x40008346` (aftertouch) | `byte << 8`, low byte 0 | traced |
| route defaults | `0x4001224e` (velocity: all 0), `0x40012282` (aftertouch: 0x1000, 0, 0, 0) | whole words, low byte 0 | traced; emulator (CLEAR KIT, pc 0x40012258..0x400122b0) |
| callers of the defaults | sound_init `0x400122b6` (tail at `0x400123e0`/`0x400123f6`), sound_load fallbacks `0x400081dc`/`0x40008306`/`0x4000836a`, Velocity reset `0x400c53c0`, aftertouch reset via callback (`0x40033bc6` calls `+120`, set to 0x40012282 at `0x400bd024`/`0x400bd134`) | 0 | traced |
| menu setAmount, aftertouch / velocity | `0x40033a1c` / `0x400c5246` | value from `0x4004c09e`: `((getAmount>>8)+delta)<<8`, or 0 with FUNC; clamped to -32768..32512 | traced; emulator wrote 0x100, 0x200, 0xff00, 0, 0x400 |
| menu setRoute (CLEAR/PASTE MODULATIONS, UNDO, route RX) | `0x4003391e` / `0x400c5148` | a whole route copied from getRoute (`0x400338cc` / `0x400c510a`, a live word), or from `0x40008138` (the route-only dump RX at `0x401033b0`) | traced |
| menu setDest | `0x40033b46` / `0x400c5360` | destination byte only | traced; emulator |
| whole-sound copies (kit save/reload, clipboard, step-lock temp `0x4003b8aa`, pool/library to track) | memcpy `0x40098b54` (pc 0x40098b6a/70) | copies an existing value, nothing new | emulator (SAVE KIT, RELOAD) |

- **No other writer was found.** I scanned every store at displacements +112..+123 and
  +140..+151 (244 sites). The byte stores at low-byte displacements and the word stores at
  route displacements all hit other structs:
  - packed struct `0x400097de..0x400099b6`;
  - a UI object at `0x40076c4a`;
  - an object larger than 0x98 bytes at `0x4002c0a8`.
- **MIDI input never writes them** (emulator). I sent CC 1..119 and NRPN MSB 0..3 x LSB 0..127,
  data 0x55/0x2a, on channel 1. All 42 parameter words changed (to 0x5554); the routes did not.
  Neither the manual's CC chart nor the MIDI map has a route parameter.
- **Not exercised, and the reason each is still believed to write 0:**

  | path | why |
  |---|---|
  | SysEx kit/sound receive | goes through sound_load: `<<8` |
  | Overbridge | uses the same dump and parameter paths (inferred) |
  | RANDOMIZE PAGE (`0x400380ae` → `0x400b059e`) | parameter pages only (inferred; key combination not found) |
  | performances and scenes | lock parameters, not routes (inferred) |
  | aftertouch menu, CLEAR/PASTE/UNDO | voice-dac's hardware probe, 2026-10-06 |

- **Confidence that stock only ever holds 0:** high. Traced, plus emulator for the menu,
  play, kit save/reload/clear and MIDI. Writes through computed pointers outside the two models
  cannot be fully ruled out.

### Stock readers

| reader | address (1.73) | effect of a non-zero low byte | hook? |
|---|---|---|---|
| sound push to the engine, velocity | `0x4011f63c` (copies to 0x8000ea3c + 32·track; only reader 0x40120ea4) | changes the sound | **yes** |
| sound push to the engine, aftertouch | `0x4011f660` | changes the sound | **yes** |
| getAmount, aftertouch / velocity menu (display, knob edit) | `0x40033a96` / `0x400c52c0` | the display shows negative amounts one step nearer 0 | **yes** (2) |
| getRoute (clipboard, undo copies) | `0x400338cc` / `0x400c510a` | none by itself; it feeds setRoute | covered by the setRoute hooks |
| route serializer: sound_save, kit save, SysEx dumps out, route dump TX `0x4010243a`, model `0x40033b80` | `0x4000816c` | none: reads only the high byte (`moveb (a0)`), the emulator saw only pc 0x4000817e on the high byte | no |
| memcpy | `0x40098b54` | none: a copy | no |

- **Nothing sends the low byte out.** There is no MIDI CC/NRPN output for routes. The SysEx
  sound and kit dumps and the stored record carry the high byte only.
- **Reader hooks: 4** (2 push, 2 getAmount), exactly voice-dac's `rte_pushv`, `rte_pusha`,
  `rte_get_at` and `rte_get_vel`.
- **Write hooks that keep the data: 4** (setAmount x2, setRoute x2). Without them, edits and
  pastes reset the low byte to 0, so data is lost but stock is not affected.

### Stored side

- The stored route block has no room for the low bytes. It is 2 bytes per route: amount byte
  and destination, velocity at +0x8e..+0x95 and aftertouch at +0x96..+0x9d, then the sentinel at
  +0x9e.
- So the low bytes can only be persisted in the spare slots 42..47 (+0x70..+0x7b), as voice-dac
  does with slots 44..47.
- **Stored budget:**
  - 12 B, minus the 5 B core uses for layout ID and generation, leaves 7 B = **56 bits** per
    sound.
  - Core already plans to load and save +0x6d..+0x6f through these slots (3 B), which leaves
    4 B for the route bytes.
  - So core can persist 4 of the 8 route low bytes (32 bits). The other 4 can only hold
    unsaved state.

## Q2. Other live sound bytes held at a fixed value

The scan covered the working kit's 12 sounds and the 128 pool sounds in the 1.73 snapshot,
plus the load and init code. No byte passes the strict standard:

| candidate | why it fails or is unproven |
|---|---|
| parameter words' low byte, bit 0 (+0x14..+0x67) | 83 of 5,880 words in the snapshot have it set (fine values). Not fixed. |
| +0x68 (machine) high bits | load keeps 0xff (`mvzb +1 < 54`), so it is not fixed |
| bits 2..7 of +0x69..+0x6c | loaded as 2-bit fields, seen as 0..3 only. But sound_init never writes +0x6c (allocator garbage), and the bytes have about 19 direct readers plus accessors (inferred). Not traced, too many hooks. |
| +0x88..+0x8b (last word of the +0x7c sample sub-object) | 0 in all 140 sounds, but the whole 16 B goes to files (`0x40007ed6`) and to the sample-matching code. Unproven; not recommended. |

## Capacity

- **Per sound, live:** 3 B + 8 route low bytes = 88 bits.
- **Per sound, stored:** 7 B = **56 bits**.
- **The scope is 56 bits, set by the stored side.** voice-dac 39 + lfo-rnd 16 = 55 bits, so
  **both fit, with 1 bit left**.
- This needs 4 reader hooks and 4 write-keeping hooks, in addition to core's existing
  load/save/init hooks.

## 1.74 addresses (checked byte for byte)

| site | 1.73 | 1.74 |
|---|---|---|
| push, velocity / aftertouch | `0x4011f63c` / `0x4011f660` | `0x4011f6a8` / `0x4011f6cc` |
| Velocity setRoute / setAmount / getAmount | `0x400c5148` / `0x400c5246` / `0x400c52c0` | `0x400c51b4` / `0x400c52b2` / `0x400c532c` |
| route dump TX | `0x4010243a` | `0x401024a6` |
| aftertouch menu, sound_load / save helpers, defaults, `0x4004c0c2`, `0x4004b878` | | unchanged |

## Emulator notes

- Runs and logs are in `/tmp/claude-0/w-loose-sound/`, under v5, m1..m5:

  | run | what it covered |
  |---|---|
  | v5, m1 | VELOCITY MOD edits |
  | m2 | PLAY, pad, SAVE KIT |
  | m3 | RELOAD, CLEAR KIT |
  | m4 | MIDI sweep |
  | m5 | FUNC+YES, which turned out not to randomize |

- Menu paths: VELOCITY MOD is FUNC+FLTR, then DOWN x4 and YES. The KIT menu is FUNC+PLAYMODE.
  SAVE KIT is YES+PLAYMODE.
- **The stock `dtboot --watch-read` misses most hits:** it prints only the first 40, and
  JIT-compiled code bypasses the watch. A patched copy that logs every read and write is at
  `/tmp/claude-0/w-loose-sound/emu`.
