# Problem: the handshake never selects script table A086 in the emulated overlay 6

**Repo:** `~/Programming/courier` (C glue in `src/glue/`, DSP core in `src/dsp/`, CPU core in `src/cpu/`).
Build with `make clean && make` (the Makefile has no header dependencies).
Run with `bin/courier-call --config <file> --duration <s> --out <dir>`; the log is `<dir>/log.txt`.

**Firmware notes (read-only):** `~/Programming/USR/doc/dsp-source/`
- annotated overlay 6 listing: `ov6/ov6-annotated.asm`
- base-image notes: `base/README.md`
- overlay 6 notes: `ov6/README.md`
- overlay 7 notes: `ov7/README.md`

**Rules:** never patch firmware. Changes go in the harness or the emulator only. The DSP core and the
CPU core are the emulator's own code, so changes there are allowed when justified.

## Symptom

Both modems connect at 33600 and exchange text, but the handshake stalls:

- No script table A086 runs.
- The answerer loops `A136 → A146 → A16D → A175 → A17B → A183`, about 11,753 times.
- The caller loops `A158 → A112 → A17B → A183`, about 57,300 times.

Neither side reaches the data-pump stage it reaches in the reference.

## What is established

**Selection logic** (`9DEB`, `ov6/ov6-annotated.asm` around lines 350–400). `[0x6F]` is tested with three
`BIT` instructions. The assembler's bit codes map to bits as `bit = 15 - code`:

| Instruction | Bit | Effect |
|---|---|---|
| `BIT *,1` | 14 | if set → `9E0F` → `9E15` (table A068) |
| `BIT *,14` | 1 | if set → `9E0F` → `9E15` (table A068) |
| `BIT *,4` | 11 | if clear → `9E13` (table A068) |

Table A086 is selected only when bit 11 is set and bits 14 and 1 are clear.

**What runs:**
- `9DEB` runs: answerer once, caller twice.
- `9E15` runs once on each side.
- `A3DF` runs once on the answerer.
- `A086` is never entered: 0 hits on both sides.

**Mode cell formula** (`sub_A685`, around line 2911): `[0x7D] = ACC_low`, then
`[0x6F] = ACC + [0x7D]*4 + 0x9AE4`.

`ov6_entry` (`9D00`) writes `[0x6F] = 0x4042` as its first instruction. But `9D00` and `9D0D` have
**0 hits** on both sides, while `A685`, `8CA2`, `8151`, `A6E2` and `9D93` each run once.

**End-of-run state:**
- `[0x6F]` = `0x0ECF` (answerer), `0x0ECC` (caller).
- `0x0ECF` has bit 1 set, so the selection goes to A068.
- The notes' expected value is `0x0AC0` (bit 1 clear, bit 11 set, so A086).

**Writers of `[0x6F]`** (writes counted by program counter over a 30 s run):

| PC | Writes (answerer / caller) |
|---|---|
| `8020` | 4 / 5 |
| `87E1` | 547 / 545 |
| `8CA6` | 1 / 1 |
| `8DE9` | 0 / 1 |
| `8E05` | 1 / 0 |
| `9BCC` | 0 / 1 |
| `9E4E` | 1 / 0 |
| `A3F8` | 1 / 1 |
| `A432` | 1 / 1 |
| `A44D` | 1 / 1 |
| `A44F` | 1 / 1 |
| `A4BA` | 1 / 1 |
| `A4BC` | 1 / 1 |
| `B05B` | 1 / 1 |
| `B062` | 60 / 60 |
| `D497` | 1 / 1 |
| `D587` | 2 / 1 |
| `D6DC` | 0 / 1 |
| `D973` | 1 / 1 |

No write comes from `9D00`–`9D0D`.

**Host window:** the emulator models `FF50..FF5F` as the host window and routes `FF01`, `FF18`,
`FF2E`, `FFD9` and `FF62` to program memory. This matches the hardware (confirmed by the project owner),
so those cells are not the cause.

**Script rewind** `A0B8` runs only 66 times on the answerer and 326 on the caller, so the loops do not go
through it.

**Command `0x13`** (tone-table command, handler `0x86E9`) goes to the caller once, at about 8.9 s, and never
to the answerer.

**Mode commands** `0x20`–`0x27` were never sent by the 80186 in an observed V.34 call (per the notes).

## What is not established

- Which write leaves `[0x6F]` bit 1 set before `9DF6` runs. The final value is not the value at selection
  time; the last writer before `9DF6` is the one to find.
- Why `9D00` (`ov6_entry`) never executes, although the routines it calls do. The notes say overlay 6 is
  entered from base-image code: `A3C3` calls `8CA2`, and the script loader is base `87A2`. Which handler
  address the base loader installs for overlay 6 has not been traced.
- Whether a mode command the 80186 should send at this point (`0x20`/`0x21`, or `0x13`) is the missing input
  that sets `[0x6F]`.

## Suggested next steps

1. Add a breakpoint at `9DF6` (DSP program address) that logs `[0x6F]` and the last program counter that
   wrote it. The core has `c5x_set_bp`; the glue does not yet use it for the DSP.
2. Trace the base loader (`87A2`, `8790`): find which handler address it installs for overlay 6, and why the
   entry is not `9D00`.
3. Check which host commands the 80186 sends to each DSP during the handshake (the `host->DSP cmd` lines in the
   log), and whether the notes say that sequence should include `0x20`/`0x21` or `0x13` for each side.

## Working tree notes

- The injection hook is kept: config keys `inject_cmd`, `inject_arg`, `inject_at`.
- The temporary diagnostics (`dsp_diag`, `hit_pcs`, `dm_cells`, `watch_dm`) were reverted. The DSP hit
  counters and writer watch in the core are unchanged.
- Committed diagnostics remain: the `DSP->host msg` log line and the `d2h overwrites` counter.

## Corrections from later measurements (2026-11-18)

These come from runs with `call.conf` fixed so A auto-answers (`setup_a ... S0=1`); with the old
`call.conf` A never answered and no overlay loaded, which produced several misleading readings.

- **Table A086 does run.** It is a script table (data), not code, so "0 hits at A086" is expected.
  After ov6 loads, the caller-side DSP reaches `9DF6` with `[0x6F]=0x0AC0` and runs
  `A12B, A145, A136, A146, A158, A112, A16D, A175, A17B, A183, A18B, A19A, A1AB` in order.
  Before ov6 loads, those PCs hold base-image code; hit counts must be gated on `PM[9D00]==AE6F`.
- **Overlay 7 never loads, and nothing at `C000+` or `DC00+` executes** (0 hits at `C88B`, `C9B0`,
  `C98E`, and none in overlay 8) even though CONNECT 33600 is printed and payloads cross. The
  reference call did not load ov7 either (`ov7/README.md`).
- **The data does cross as audio.** Cutting the line at CONNECT stops delivery; the caller's audio
  is identical between two runs up to the moment the payload is sent and differs after it.
- **dm[0x3F2]/dm[0x3C0] are not tone state in this call**: `AC3A` and `ADE0` (ov6) write them at the
  sample rate. In `875A`, `[0x3C0] += [0x3F2]` (CALLD delay slots), so `[0x3F2]` is a frequency
  increment and `[0x3C0]` the phase accumulator.
- **TX path:** the main loop at `80D0` zeroes `dm[0x3C7]`, calls the tasks in `dm[0x39A]`/`dm[0x39B]`,
  then `TX = [0x47]*dm[0x392] + dm[0x3FB]`, stored by `80F4` into the odd cells of the ring at
  `dm[0x0BD0..]`; the XINT ISR `8189` stores RX into the even cells and sends the odd ones.
- **Against BinModem** (`tools/binmodem-bridge`): BinModem answering gets to `V.34 INFO0` at 2.7 s and
  gives up at 22.7 s; it never decodes an INFO0 from the emulated caller. That is the first
  concrete V.34 disagreement with an independent implementation.

## Against BinModem (2026-11-18, `tools/binmodem-bridge`)

BinModem is an independent Rust V.34 softmodem. It replaces one side of the call; the line between the
cores is 28800 Hz (see the bridge README). Findings, in the order they were established:

- **Codec rate is not constant.** 7200 Hz at first, 8640/9600 in V.8 and phase 2, 10267 in phases 3 and 4.
  Every raw-audio analysis that assumed 7200 Hz for the whole call was wrong (the "steady 1200 Hz tone"
  is 900 Hz in the raw dump, 1200 Hz at 9600), including the earlier bandwidth comparison with
  `v34_recording.wav`. It must be redone with the rate history (`rate_idx`).
- **Phase 2 works against BinModem in both roles**: INFO0, tones, ranging, probing, INFO1c/INFO1a. The
  emulated caller's INFO0 decodes with a valid CRC.
- **Level matters, and not monotonically** (my earlier claim that it did not was wrong; BinModem's output
  scale `BM_OUTSCALE`, line gain 0.5, AC01 input gain x2, never changed by the DSP and nothing clips):
  - BinModem caller, emulated answerer, `BM_OUTSCALE=300` (about 100 rms at the emulated DSP's input):
    **full V.34 connect and data both ways**: emulated side `CONNECT 21600/ARQ/V34/LAPM/V42BIS`,
    BinModem `CONNECT 31200`; "Hello world from courier" and "Hello back from the answerer" arrived.
    MP: call_to_answer 9, answer_to_call 13.
  - same, 2000..8000: BinModem trains on the answerer's S and J, sends its S/PP/TRN/J, then times out
    ("no S from the answer modem in phase 4"); the emulated answerer never posts 0x3D/0x37/0x30/0x35/0x36
    and ends with 0x0E/0x05 (carrier lost). 600 fails the same way.
  - same, 20000: phase 4 training runs (snr 58.8 dB) and MP is exchanged, then "no E from the answer modem".
  - 150: stalls in phase 2. 1200: repeated retrains (not finished in 24 s).
  - BinModem answering, emulated caller: 3000 and 5000 get through phase 3 (S heard, snr 12.6 dB, J heard)
    into phase 4 MP, where the caller's MP never carries `acknowledge` and the call retrains; 7000 and 16384
    are not recognised at all; 300 stalls in V.8 (answer tone).
  So the emulated receiver's behaviour depends strongly on input level, and the useful level differs by
  phase. Its AC01 gain is fixed (register 4 = 0x09), so whatever adapts is in the DSP software.
- **Not established**: where the trellis and data-pump code run. The "no code at C000+/DC00+" counts above
  came from the emulator-to-emulator call; they need repeating on the call that connects against BinModem.
  What the connect does show is that the emulated DSP produces and decodes valid V.34 data (BinModem's
  decoder and V.42 CRCs accept it).
- Diagnostics: `AICDBG=1` (machine.c) prints each machine's input level, AC01 gain and clipping once a
  second; `PHASE2_TRACE`, `PHASE4_TRACE`, `MODEM_TRACE` trace BinModem.

### Trellis and coefficients: what the connecting call (BinModem caller, `BM_OUTSCALE=300`) shows

- **Trellis does run, on both sides.** BinModem's MP says `trellis: States64`; its Viterbi decoder produced
  valid V.42 frames from the emulated modem, and the emulated modem decoded BinModem's text. One side
  cannot be trellis coded without the other.
- **It is not in overlay 7 or 8.** Over the whole connecting call each emulated DSP executed 0
  instructions in `C000..CD4A` and 0 in `DC00..F8B5` (so `trellis_C88B` is not what does it; that label
  was only "inferred"). The code is in the base image and/or ov6's range `9D00..C40E`.
- **Where the time goes (A, 148.6M instructions)**: `AC71-ADF6` 27% (ov6 `mac_helper`/`mac_copy`/`mac_tail`:
  long MAC loops over pointer pairs), `8B1A-8C51` 11% (base), `9E15-A03E` 10% (ov6 sample filters),
  `AAEE-AC64` 8.5% (ov6 per-sample filter chain), `B6E5-BD15` 5.7%, `8000-80F4` 4.8% (main loop).
  Hit counts: `HITS=1 HITSFILE=<prefix>`.
- **Arrays the `AC71` MAC code works on** (pointers loaded at `AC71`/`AC7F`/`AC8B..`):
  - external RAM `D51F, D53F, D55F, D57F` (32 words each) and `D605, D64B, D691, D6D7` (70 words each):
    100% different from the base image at the end, values high-entropy (e.g. 24410 30644 -13489 ...), so
    they are written at run time: adaptive taps or sample/symbol history, not fixed tables. Which is not
    yet established.
  - external DM `089F 08BF 08DF 08FF 0985 09CB 0A11 0A57` (32 words each): all zero at the end.
  - on-chip DM `0273 02B9 04BB 04E0` (32 words each): few distinct magnitudes with sign changes (5592, 430,
    11615, 12475, 3011, 8174, 9034, 10755 ...), which looks like a constellation or coefficient table.
- **Open**: which writer fills `D51F..D71C` and `0273..04E0` (use `WATCHDM`-style writer counts), and where the
  64-state trellis encoder/Viterbi tables are. Memory dump: `DUMPMEM=<prefix>` (`.A.pm`, `.A.dm`).

### Trellis found (2026-11-18)

Method: clear the per-PC hit counters at CONNECT and run the data phase (59,524 samples at 10267 Hz,
3 samples per symbol). Code that runs once per sample, per symbol (x1/3) and per 4D symbol (x1/6) separates
cleanly. The x1/6 class holds the big blocks `AFCE-B03C`, `B6FF-B8C8`, `B97F-BA02`, `BA27-BAFB`,
`BB45-BC05` and `9FA2-A01D`. Then BinModem's `trellis.rs` tables were searched for in the DSP images.

- **TABLE_13, the V.34 symbol-to-bit converter (9.6.3.1), is in ov6 at `C3A8..C3B7`**, 16 words, four 4-bit
  entries per word, most significant nibble first (`0011 8899 | 3223 BAAB | 5544 DDCC | 6776 EFFE |
  8899 0011 | BAAB 3223 | DDCC 5544 | EFFE 6776`): row 0 of the table is 0,0,1,1,8,8,9,9, and so on for all
  eight rows. A search of the base, ov7 and ov8 images found no other copy.
- **The code that reads it** (both in the once-per-4D-symbol blocks): `B026-B037` (`LACC 0x7C,2 / ADD *,5 /
  SAMM 0x0D / BSAR 4 / ADLK #0xC3A8 / TBLR 0x7F / LACT 0x7F / BSAR 12 / ANDK 0xF`: index from the two 3-bit
  subset labels, fetch the word, shift out the nibble) and `BB45-BB53` (same lookup).
- **Neighbouring tables**, referenced by the same blocks: `C3B8..` three byte curves rising to `FF` and
  falling again (read at `BAE4` and `BB26` with `ADLK #0xC3B8`, then a byte picked with `BIT`/`XC`/`ANDK 0xFF`;
  probably the non-linear encoding or a level table, not established); `C340..C3A7` a table of odd-valued
  byte pairs (`E1 1D 25 F1 D9 09 ...`, spaced by 4 or 8; probably constellation coordinates, not established);
  `C4B0..C4DF` and `C4D8..` (more table data read by the big block at `B8D8` with `LALK #0xC4B8`).
- **Not found as a table**: BinModem's FIGURE_9 (subset labels) in any packed form searched (4-bit), and the
  16/32/64-state convolutional encoder, which is probably shift/XOR arithmetic in the same blocks (its
  parity taps would be `ANDK`/`XPLK` constants there).
- All of this is in ov6 (`9D00..C9F5`), which is loaded; ov7 (`trellis_C88B`, only "inferred") never runs.

### Trellis encoder coefficients, per mode (2026-11-18)

- **S55 cannot select a code in this emulation.** `ATS55=n` is accepted (`OK`) and changes exactly one thing the
  80186 sends the DSP: the top two bits of `cmd 0x48`'s argument (bit 7 = 16-state allowed, bit 6 = 8-state
  allowed; `FF`, `BF`, `7F`, `3F` for S55 = 0, 13, 14, 7/11). The 32- and 64-state bits never reach the DSP
  (S55=7 and S55=11 send identical commands), and between two emulated modems every setting still negotiates
  `64S-4D/64S-4D`; the DSP executes the same addresses in all of them.
- **A partner that asks for a code can select it.** BinModem's MP request is hard-coded to 16 states; the
  trace patch now reads `BM_TRELLIS=16|32|64`. The firmware's `ATI11` then reports one code per direction,
  receive/transmit: `64S-4D/16S-4D`, `64S-4D/32S-2D`, `64S-4D/64S-4D` (the first is the emulated modem's receive
  decoder, which asked BinModem for 64 states; the second is its transmit encoder, which BinModem asked for).
  Data crossed both ways in all three. The firmware's own label for the 32-state code is "32S-2D".
- **The encoder is data-driven.** Over the data phase only one address differs between modes: `B041`
  (`XORI *`), 4.02 / 4.50 / 5.02 executions per 4D symbol for 16 / 32 / 64 states.
- **The loop is `B039-B045`**: `RPTB B043` runs 10 times; each pass shifts the next input bit out of ACC
  (`SFR`), and if it was 1 (`XC 1,C`) XORs the next coefficient word (`XORI *`, `AR1` walking down from
  `0x084F`) into the running state in ACCB. A bit-serial GF(2) matrix multiply.
- **Coefficient words** (on-chip SARAM, data-visible because OVLY=1), `DM[0x084F]` first, one per input bit:

  | Code | `084F` `084E` `084D` ... `0846` |
  |---|---|
  | 16S-4D | 010 020 000 000 040 090 020 010 000 000 |
  | 32S-2D | 040 090 000 020 100 010 020 040 080 000 |
  | 64S-4D | 022 011 040 080 100 23C 0E2 0C0 010 040 |

  The rest of `0x0840..0x0867` is identical in all three modes (`7208 737B 7501 FFFF FC94 F752` at `0840`,
  state area `0860..0867` = `0000 0000 007F 0001 0100 FE00 2011 0001`). Other mode-dependent cells:
  `0888, 089B, 08B5, 08D0, 08D4, 08D9, 08DF, 08FB, 08FD` (flags and small counts).
- **Not verified**: how these words relate to BinModem's next-state equations (`trellis.rs`, `Code::next`).
  There is no one-to-one match (for example, 16S `Y2` has a single-bit word here but feeds two delays there),
  so the routine probably does only part of the update, in a different basis. Simulating `B026-B045` with these
  words against BinModem's encoder would settle it.
- **Diagnostic bug fixed**: `DMTRACE` read addresses `0x800..0xBFF` from the unified-memory array; with OVLY=1
  they are on-chip SARAM and must be read from the data-memory array. Earlier candidate cells at `0x08xx`
  (for example `0860..0865`) were read from the wrong array.

#### Where the coefficient words live (fixed addresses, not allocated)

- **Master tables, program memory, in ov6**: 10 words each at `A80C` (k=0, 16-state), `A816` (k=1, 32-state),
  `A820` (k=2, 64-state). `A82A` (k=3) is not a coefficient set. In ascending order: `000 000 010 020 090 040 000
  000 020 010` / `000 080 040 020 010 100 020 000 090 040` / `040 010 0C0 0E2 23C 100 080 040 011 022`.
- **Working copy, data memory `0x0846..0x084F`**: filled by the routine at `B1AC-B1C6` when the mode is installed
  (`SAMM 0x1F` sets BMAR to `0xA80C + 10*k`, with `k` a 2-bit field read at `B1BA`; `LRLK AR1,#0x0846; RPTK #9;
  BLPD BMAR,*+`). The encoder at `B039` reads it back from the top, `LRLK AR1,#0x084F`, walking down.
- **Both addresses are immediates in the code**, and the DSP has no allocator, so the layout is the same in every
  run and in both modems. What varies is which of the three sets is copied in. The master tables vanish with
  ov6, which the host loads (`9D00..C9F5`).

### Forcing 16/32/64 states and the constellation (2026-11-18)

- The page's constellation scope plots DM `0x0224` (x) and `0x0228` (y). In a 33600 call between two emulated modems
  these hold 42 levels per axis at spacing 256 (about 1,400 distinct points, radius to about 5,360); in the BinModem
  call at 3200 baud, 40 levels (1,280 points). They are the transmitted points (exact lattice, no noise), not the
  received equalized ones, which have not been found (`0211/0212` is a featureless cloud, not the symbol).
- **Forcing the code does not change the constellation**: with BinModem asking for 16, 32 or 64 states the emulated
  transmitter's pair covers the same 1,280 points, with identical radius statistics. The sequences are the same
  until the data phase starts (symbol 16,270) and differ after it (only 17-22% of consecutive symbols coincide).
- **Sequence test, inconclusive**: feeding each run's point sequence (labels from Figure 9, `Y` from TABLE_13) through
  BinModem's three encoders and comparing the predicted `Y0` with a parity bit taken from the two labels, the code
  that was requested scores highest in each run (0.555, 0.575, 0.575 against 0.51-0.52 for the other codes; chance
  is 0.50 +- 0.01), but nowhere near 100%. The observed-`Y0` definition (and the superframe bit inversion, Table 12)
  is probably wrong or incomplete; not settled.
- **S55 cannot force a code on the page** (only the 8-/16-state flags reach the DSP, and both modems still request
  64 states). Forcing 16 between two emulated modems would need an emulator-level override of the trellis field
  the firmware puts in its MP, which has not been located.
