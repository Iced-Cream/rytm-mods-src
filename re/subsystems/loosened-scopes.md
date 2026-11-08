# Kit, global, pattern, song and project scopes under the loosened rule (2026-10-20)

Question: besides sounds (covered in [loosened-sound.md](loosened-sound.md)), which bytes that stock reads are only ever held at one fixed value, so core-ar2 could use them if every stock reader is hooked to see that value?

Method: static reading of stock OS 1.73 (`/tmp/claude-0/analysis/stock173.dis`), plus the emulator. A copy of rytm-emu (in `/tmp/claude-0/w-loose-scopes/emu`) was patched to log every CPU read and write over a set of address ranges, grouped by PC.
- **cb173:** a cold boot from a powered-off card, watching the whole stored project image (0x405c8f20, 0x1f9f32 B).
- **r3:** from that boot, SysEx dump requests for kit 1, pattern 1, song 1, sound 1, settings and global 0, then SAVE KIT and SAVE PATTERN.
- **r1/r2:** the live kits, watched during LEVEL turns and a push-turn fine edit.
- **Factory content:** constancy across the factory project's 129 kits, 129 patterns and 17 songs. It is used only for hints, because factory data predates many features.

Every address relied on was checked in 1.74 by byte match. Code below 0x4005702a is the same in both. 0x400a6836, 0x400a7aa6/7b2e, 0x400a7988, 0x400a709a, 0x400a6e0e, 0x400ad1b6, 0x400bc0d8, 0x40103562 (its call operand also moves), 0x4011f36c/f3f0/f6f8 and 0x4011ff8e are at +0x6c.

## The finding that shapes everything: stored records are read only by their load serializers

In cb173, every byte of the stored image was read only by:
- the record's load serializer, for patterns, kits, sounds, songs, settings and globals;
- the project-load code, for the header and the active kit index;
- whole-image memcpy and boot fill.

In r3, the dumps were serialized from live objects, not from the stored image. The saves read no stored bytes, apart from two in-place reads in the FX and sound saves.

So, for a field that exists only in the stored image (its live copy is a different struct, or the live value is rebuilt by the loader), "hook every reader" needs no new sites:
- **In the load hook:** copy the record, put the fixed values back, and run stock's load on the copy.
- **In the save hook:** write the mod bits back after stock's save has written the fixed value.

The pattern, kit, sound and global hooks already exist. Songs and settings would need new ones.

The real cost is elsewhere. **A project, file or dump from a modded device would no longer be safe on unhooked firmware:** stock OS, another person's build, or a Transfer import into a stock Rytm. Bytes that stock never reads are harmless there. Loosened bytes are not:
- A changed version long makes `pat_load` or `kit_load` fail (0x40009166, 0x4000865e), and that record loads at defaults.
- A level LSB at level 127 loads as level 100 (0x400086a6).
- Small-enum high bits are clamped to the default.

This is the main trade-off for the owner.

## 1. Kit

### Strict-rule bonus: 37 stored bytes the survey missed (traced, emulator-confirmed)

The stored performance block is at kit +0x832 and is 229 B long. Its loader 0x40007fb4 starts at +0x842 (`lea a2@(16)` at 0x40007fcc), and its saver 0x4000801a starts there too (0x40008032). Both cover only 48 × 4 B. So two runs are never read or written by stock:
- **+0x832..+0x841** (16 B);
- **+0x902..+0x916** (21 B).

Emulator evidence:
- cb173: no reader of these bytes in any kit.
- r3: no writer during SAVE KIT. The save wrote +0x842..+0x901 and +0x82a..+0x831, and nothing between them.
- They are zero in all 129 factory kits.

With these, the stored kit spare goes from 29 B to **66 B**. Like the FX spare, they need the existing file-save and file-load handling. This is not loosened room: it holds under the current rule.

### Live room (the bottleneck): stays at 8 B

| candidate (live / stored) | writers | readers | verdict |
|---|---|---|---|
| **Track level LSBs** (13 B)<br>live kit +0x11+2t, stored +0x15+2t | See note 1 below. | 0x400a67e2 (high byte only, safe), getter 0x400a6828, 0x400a7c10, 0x400afc40 (sends to the USB host), and the engine uploads 0x4011f352, 0x4011f3a0, 0x4011f3f0 (they copy the whole word to 0x8000e57c). | **Not provable: Overbridge may write it.** If OB never sends an LSB, it gives 13 B for about 7 reader hooks plus a load-clamp hook. Confidence: traced, and the UI setter emulator-confirmed. |
| **FX word LSBs** (live +0x74a, 42 words) | The parameter path writes low bytes: fine values, and `orl` of flag bits at 0x400a93c6. | engine | **No.** FX slot 36 has nonzero LSBs in 9 factory kits. Each parameter would need its own proof. |
| **Perf/scene value LSBs** (96 B)<br>live 48 + 48 words at +0x79e and +0x88e, 5-B entries | The load gives 0 (`lsll #8` at 0x40007fdc and 0x4000809e), and the save keeps only the high byte. But the setter 0x400ad15c stores the caller's raw word (0x400ad1b6), which is a parameter value that can carry a fine LSB. | The engine copies the raw word (0x4011f6f8). | **Excluded.** The setter can store an LSB. |
| **+0x987 track mask** (19 bits)<br>live long; stored word +0x9dd (0..8191) | Bit set and clear for track 12 or below (0x400a701e). Whole-long set 0x400a709a takes the caller's long (callers not traced). | 0x400a6fdc (bit test), 0x400a7012 (whole long) | Inferred at best. |
| **+0x9bb** (live long, stored word +0xa0f) | `eor 1<<n` (0x400a6e0e) and a sign-extended word (0x400a6e68) | | No: the word can be negative. |

Note 1, writers of the level LSBs:
- **UI setter 0x400a7aa6:** masks the value with `andil #-256` at 0x400a7b2e. Emulator: 20 writes, all with a zero low byte.
- **Copies:** load 0x400086aa (clamps above 0x7f00 to 0x6400), the mirror copies 0x400a7988 and 0x400a79a8, and kit memcpys.
- **0x400a6836:** stores a caller word **unmasked**. Its only caller is 0x40103562 in the USB/Overbridge message handler (message type 14, subtype 10). That handler also echoes the level back via 0x400afc40. So the host's 16-bit value reaches the live word.

Other kit fields that stock reads but are fixed:
- the version long +0x00 (always 6; reader 0x4000865c, writer 0x400089f0). It is stored only, so it is store or kit room, not live room. See section 2.
- the +0x9d7 high byte, already in the plan.

## 2. Growing the tagged store (stored image, per project)

| field | fixed value | sole reader (cb173) | writer | bytes per project | confidence |
|---|---|---|---|---|---|
| Song version long, 17 songs (+0x000) | 0 | 0x400095a2 (load requires 0) | song save 0x40009682 `clrl` | **68** | traced + emulator |
| Pattern version long, 129 patterns | 5 | 0x40009164 | pat_save | **516** | traced + emulator |
| Kit version long, 129 kits | 6 | 0x4000865c | kit save 0x400089f0 | 516, if the kit scope does not take it | traced + emulator |
| Active kit index, upper 3 B (+0x19d3f7) | 0 (index 0..127) | 0x4000cf78 | 0x40196aee | 3 | traced + emulator (readers); value range inferred |
| Settings version long | constant | 0x40007c2c | settings save 0x40009b14, which runs at every boot | 4 | traced + emulator |
| Song entry word bits 13..15<br>(the entry word is a 13-track mute mask: the engine `btst` at 0x4011ff8e) | 0 | 0x40007446 | See note 2 below. | 204 | inferred |
| Song +0x514 / +0x516 high bytes (row and entry index) | 0 | 0x40007480, 0x400074c4, 0x40007564 | song save | 34 | inferred |
| Track +0x277 bits 3..6 (speed is 0..6) and +0x278 bit 7 (0..100), per pattern track | 0 | track loader 0x40008b2e | pat_save | about 1,048 | inferred (UI setters not traced) |

Note 2, writers of the song entry word: clear to 0 (0x400bc0d8, 0x400bb022, 0x400bb118), init 0x400121a0, and paste of buffered entries (0x400bbcd6, 0x400bbf84). The UI mute setter was not traced.

Not usable:
- **Project header magic and version:** read by 11 sites (the version dispatch at 0x4000b91a etc. and 0x4000e810), and the core's image finder relies on them.
- **Song byte +3:** this is the pattern number, written from 0x4009a830.
- **Row count and repeat words:** ranges not established.

Lead, not pursued: the pool header (+0x1f4393, 4 B) was not read during a version-9 project load. It is written by pool save 0x4000857e and used only by the upgrade path 0x4000a20c, so it may even be strict-free. It still needs a check.

Hooks for the store:
- **Scrub at load:** song load (0x40009594 → 0x400073ac, new), and the existing pattern and kit loads, plus project load for the active kit index.
- **Write back after save:** song save (0x400095ae, new; it rewrites the version and used entries), and the existing pat_save and kit save.
- File images are built by the same serializers, so the existing file-save and file-load hooks cover them.

The traced part adds about **587 B** (+13 %), or 1,103 B if the kit versions are pooled. The inferred part adds about 1,286 B more.

## 3. Global slot (stored +0x00..+0x4f, 4 slots)

The cb173 readers are one load instruction per byte (0x4000765a..0x40007a32). Bytes 54..69 are the name (also 0x4002b7a8 and memcpy 0x40098b6a). The load ranges below are traced. That the UI setters stay inside them is inferred.
- **Version long** (= 2): 4 B.
- **0..1 fields:** +4, +9, +32..+40, +46..+49 and +70 give 7 bits each.
- **Other small ranges:**
  - +5 (0..15): 4 bits
  - +6 (0..4): 5 bits
  - +7 (0..16): 3 bits
  - +8 and +10 (0..127): 1 bit each
  - +28..+31 and +41..+45 (0..2 or 0..3): 6 bits each
  - +73 (0..3): 6 bits
  - +74 (0..5): 5 bits
  - the words +50 and +52 (0..4095): 4 bits each
- **No room:** +11..+27 (they can hold -1), +71 and +72 (full bytes).
  - +12..+24 are the 13 track MIDI channels (TRACK 1..12, then FX). They are not single load instructions: a loop at 0x40007706 reads each as a signed byte, takes one outside -1..15 (-1 is OFF) as the track's own index, and stores it to the live long at +32+4i; the save writes them back in a loop at 0x40007ab4 (traced). 0013 kept DAC SUM at +12 and +13, over TRACK 1's and TRACK 2's, until it moved to +79.
- **Spare under the strict rule:** +75..+79 (0x4b..0x4f), the 5 B below. Neither the load nor the save touches them. 0013's DAC SUM takes +79. Another developer's allocator outside this repo also uses them for persistent storage, so builds that use both disagree on a project moved between them.

That totals about **28 B** per slot on top of today's 5 B. The scrub and restore go inside the existing globals load and save hooks (0x4000763c, 0x40007a5c), so there are no new sites. The live home stays the core table.

## 4. Project settings

Settings are still not offered. They are read only by the load 0x40007c0e, and the save runs on every power cycle, so any use needs a write-back. The version long gives 4 B. The clamped fields were not surveyed in detail.

## Table

| scope | room today | extra under the loosened rule | hooks needed |
|---|---|---|---|
| Kit (live) | 8 B | **0 proven**. Level LSBs give 13 B only if Overbridge never sends an LSB (inferred); perf, scene and FX LSBs are excluded. | 7 reader sites + load clamp + OB writer (0x400a6836) |
| Kit (stored) | 29 B | **+37 B under the strict rule** (perf pads; traced + emulator). +4 B version (traced + emulator). | none new / the existing kit load and save |
| Global slot (stored) | 5 B | about +28 B (inferred ranges, traced readers) | the existing globals load and save hooks |
| Tagged store | 4,352 B | +587 B traced + emulator (+516 B with kit versions); +1,286 B inferred | new song load and save hooks; the existing pattern and kit hooks |
| Pattern track / pattern | share the store | as the store above (track speed and +0x278 bits are about 1 KB of it, inferred) | the existing pat_load and pat_save hooks |
| Project settings | not offered | 4 B (version) + not surveyed | settings load and save, with write-back |

The cost of all loosened room is that modded images become unsafe on unhooked firmware: records fail to load or values get clamped. The strict-rule perf pads have no such cost.
