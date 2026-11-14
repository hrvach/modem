# Host <-> DSP command protocol (USR Courier V.Everything, SV25 firmware)

Reference for the mailbox protocol between the 80186 "supervisor" firmware and the TMS320C51 DSP, as recovered from
`SV25.XMD` (Supervisor 7.3.14 / DSP 3.0.13). Everything here was derived from the firmware images and from running the
DSP image in the emulator in this directory (`c5x_core.c`, `c5x.py`, `host3.py`).

**Confidence tags**: **[code]** read directly from disassembly; **[emu]** observed by running the DSP emulator;
**[inferred]** deduced, not directly confirmed. Addresses: `flash 0xNNNN` are offsets in the decoded flash image
(`SV25.flash.bin`); 80186 code in the main segment is `8000:NNNN` = flash `0xNNNN`; DSP addresses are C5x program/data
word addresses (base image loads at `0x8000`).

## 1. Overview

* The 80186 and the DSP exchange small messages through a byte-wide I/O port window (80186 side: ports `0x58`, `0x5A`,
  `0x5C`, `0x5E`) that appears to the DSP as 16-bit ports `0x57`, `0x5E`, `0x5F` plus a memory-mapped window at data
  addresses `0xFF50-0xFF5F`. **[code]/[inferred]** for the exact mapping, see section 6.
* Direction **host -> DSP** is a queue of 16-bit command words, each `(command << 8) | argument`; the DSP polls for them in
  its main loop and acknowledges each one. **[code]**
* Direction **DSP -> host** is a ring buffer of 32-bit messages that the DSP pushes out when the host is ready; the 80186
  receives them in an interrupt handler. **[code]**
* This channel is separate from the *code download* path (ports `0x40-0x4E` burst writes with control ports
  `0x18/0x1A/0x1C/0x1E`, flash `0xE3A0-0xE705`), which loads the DSP base image and the overlays. **[code]**

## 2. 80186 side: transmit

| Item | Address / value | Tag |
|---|---|---|
| Pending-send slot | `[0x289]` (word). Low byte `[0x289]` = argument, high byte `[0x28A]` = command | [code] |
| Idle token | `0x7F3F` (command `0x7F`, arg `0x3F`) - "nothing to send". Also `0x7F0F`, `0x7F10`, `0x0D..` variants appear as hand-shake tokens; `[0x28A]=0x7F/0x80` is a state flag | [code] |
| Command ring buffer | words at `[0x29E, 0x2CE)`, read pointer `[0x29A]`, write pointer `[0x29C]` (wraps at `0x2CE` back to `0x29E`, 24 entries) | [code] |
| Enqueue | `8000:F68C` (near), `8000:F688` (far entry). `AX` = word, returns `CF=1` if the ring is full | [code] |
| Long-message enqueue | `8000:F6B8` / `F684`: checks free space (needs > 0x2A bytes), sends marker word `0xFF00`, then the payload words via `F68C` | [code] |
| Dequeue | `8000:FDA7`: `lodsw` from `[0x29A]`, wrap at `0x2CE`, `CF=1` when empty | [code] |
| Transmit ISR | flash `~0xF450-0xF53E` (ends `iret`). Entered on the DSP-mailbox interrupt | [code] |

Transmit sequence inside the ISR **[code]**:

1. `AX = 0x7F3F; xchg [0x289], AX` - takes the pending word and leaves the idle token behind.
2. If `AH == 0xFF` it is the long-message marker: call `F551` (extended send) instead.
3. Otherwise the two bytes are written out as: `out 0x58, AH` (command), `out 0x5A, 0`, `out 0x5C, AL` (argument),
   `out 0x5E, 0`.
4. `[0x285]` (interrupt/control shadow) is written twice to port `0x1C`; its role (enable/EOI) is **not decoded**.
5. If `[0x28A] == 0x7F` (idle) the ISR refills `[0x289]` from the ring via `FDA7`.

The send path therefore never exposes more than 8 command bits and 8 argument bits. Extended (`0xFF` marker) messages
carry additional words; their exact layout is **not decoded**.

## 3. 80186 side: receive

The same ISR reads the DSP's reply **[code]**: `in 0x5A -> AH`, `in 0x58 -> AL` (message type, valid if `< 0x76`);
for types `0x1C` and `0x1D` it also reads `in 0x5E -> AH`, `in 0x5C -> AL` and stores the 16-bit word into a buffer at
`[0x14C + [0x24C]]` (`[0x24C]` advances by 2, wraps at 256 bytes; flag `[0x24D] bit1` marks a full block and a `0x3E8`
timeout is armed in `[0x24F]`). All types are then passed to the handler pointed to by `[0x298]` (`call [0x298]`).
Message types and their meaning are **not decoded**.

## 4. DSP side: receive loop

The DSP main loop (`0x80C8`) calls `0x839B` (host-command poll) every pass. **[code]**

`0x23F0` is a 3-word helper that the firmware copies into on-chip SARAM at start-up (`lacc *; lamm *; ret`): one read of data
address `*AR1` (the external `0xFF5x` window) followed by one read of the MMR/I-O register `(*AR1 & 0x7F)`. Each call
returns the value of the second read in `ACC`. The poll does three calls with `AR1 = 0xFF57`, `0xFF5E`, `0xFF5F`:

| Step | Instruction address | Register read | Meaning |
|---|---|---|---|
| 1 | `0x839D` | `0x57` | status; **bit 0 = message pending**. If clear the routine returns (`retc ntc`) | 
| 2 | `0x83A6` | `0x5E` | **command** (stored in data word `0x7D`) |
| 3 | `0x83AD` | `0x5F` | **argument** (stored in data word `0x7A`) |
| ack | `0x83B3` | write `1` to `0x57` | acknowledges, clears the pending flag |

Dispatch **[code]**: `acc = command; acc -= 0x7F; if acc > 0 return` (loose upper bound check); `acc += 0x8480` (so
the table base is `0x8480 - 0x7F = 0x8401`); `tblr` loads the handler address; `bacc` jumps to it. The argument stays
in data word `0x7A` for the handler. The jump is a plain `bacc`, so handlers return with `ret` to the loop.

Registers that are **not** read by this poll but used by other code: ports `0x50-0x56`, `0x68-0x6C` (written by the
init code and by several commands).

## 5. DSP side: transmit (DSP -> host)

Poll routine `0x83D6` **[code]**: a ring buffer of 32-bit words lives at data `0x0BD0` (write pointer data word `0x78`,
read pointer data word `0x79`, buffer wraps every `0x10` words). When the pointers differ and status register `0x57`
**bit 1** (tested as `bit 14`) says the host is ready, the DSP reads the next entry and writes it out as
`out 0x5E` (low 16 bits, bit 15 masked to 0 for the first word) then `out 0x5F` (high 16 bits), and
advances the read pointer. **[inferred]**: these two 16-bit DSP ports surface to the 80186 as its byte ports
`0x58/0x5A/0x5C/0x5E` (type in `0x58`, extra in `0x5A`, data in `0x5C/0x5E`).

## 6. Port/register map (as seen from each side)

| DSP port | Dir | Meaning | 80186 counterpart | Tag |
|---|---|---|---|---|
| `0x57` | R | status: bit0 = host->DSP message pending, bit1 = host ready for a reply | (hardware flags) | [code] |
| `0x57` | W | acknowledge (write 1) | - | [code] |
| `0x5E` | R | command byte (host->DSP) | written via `0x58` | [inferred] |
| `0x5F` | R | argument byte (host->DSP) | written via `0x5C` | [inferred] |
| `0x5E`,`0x5F` | W | DSP->host message words | read via `0x58..0x5E` | [inferred] |
| `0x50-0x56` | W | mode/line-control outputs (init writes `0x56=0x57=0xFFFF`) | - | [code]; purpose unknown |
| `0x68-0x6C` | W | written during DSP init (`0x0F, 0x02, 0x00, 0x78, 0x0901`) and by commands `55/59/5A` | - | [code]; purpose unknown |

The `0xFF50-0xFF5F` data window mirrors these registers (first read of each helper call); the emulator routes it to the
same callbacks.

## 7. Command table

Base `0x8401` in the DSP base image, index = command byte. Valid indices are `0x00-0x78`; entries `0x79-0x7F` are
instruction words of the following function (table overrun) and **must not be treated as handlers**. 12 entries are `0`.
"Region" says which image contains the handler address; overlays (`ov6` `0x9D00`, `ov7` `0xB000`, `ov8` `0xDC00`) are
alternatives that overlap each other, so a handler address inside an overlay is only valid while that overlay is
loaded by the 80186 (the loader is flash `0xE4AB/0xE60A`). Entries tagged "data" in the notes pointed at lookup tables in
my tests, not code.

"Observed" notes come from sending `(cmd, arg=0)` into the DSP emulator ~80 codec samples after boot, base image only.

| Cmd | Handler | Region | Observed in emulator |
|---|---|---|---|
| `00` | `813A` | park / halt loop (no-op command) |  |
| `01` | `8003` | base | re-runs DSP init (acts as reset) |
| `02` | `8266` | base |  |
| `03` | `826C` | base |  |
| `04` | `8230` | base |  |
| `05` | `8234` | base |  |
| `06` | `8489` | base |  |
| `07` | `84CB` | base |  |
| `08` | `8223` | base |  |
| `09` | `9BAE` | base |  |
| `0A` | `830B` | base |  |
| `0B` | `8222` | base |  |
| `0C` | `CDB2` | base |  |
| `0D` | `CDC2` | base |  |
| `0E` | `CDD2` | base |  |
| `0F` | `8246` | base | writes port 0x50 |
| `10` | `9B58` | base |  |
| `11` | `9B5C` | base |  |
| `12` | `86DB` | base |  |
| `13` | `86E9` | base |  |
| `14` | `9E45` | base, ov6 |  |
| `15` | `9BD5` | base |  |
| `16` | `86E5` | base |  |
| `17` | `9BC5` | base |  |
| `18` | `E8E4` | base, ov8 |  |
| `19` | `8238` | base |  |
| `1A` | `823B` | base |  |
| `1B` | `8243` | base |  |
| `1C` | `9BB3` | base |  |
| `1D` | `9BB8` | base |  |
| `1E` | `9B9D` | base |  |
| `1F` | `9B9A` | base |  |
| `20` | `DC9B` | base, ov8 |  |
| `21` | `DC7B` | base, ov8 |  |
| `22` | `DC5F` | base, ov8 |  |
| `23` | `DCFE` | base, ov8 |  |
| `24` | `DCD6` | base, ov8 |  |
| `25` | `DD0B` | base, ov8 |  |
| `26` | `DCE0` | base, ov8 |  |
| `27` | `DCF1` | base, ov8 |  |
| `28` | `D2C9` | base | writes port 0x54 |
| `29` | `D2D6` | base |  |
| `2A` | `9BA8` | base |  |
| `2B` | `9BA5` | base |  |
| `2C` | `8222` | base |  |
| `2D` | `8222` | base |  |
| `2E` | `DA53` | base |  |
| `2F` | `D9DA` | base |  |
| `30` | `9BBD` | base |  |
| `31` | `8222` | base |  |
| `32` | `C811` | base, ov6, ov7 |  |
| `33` | `C543` | base, ov6, ov7 |  |
| `34` | `C52A` | base, ov6, ov7 |  |
| `35` | `C987` | base, ov6, ov7 |  |
| `36` | `C803` | base, ov6, ov7 |  |
| `37` | `C7F7` | base, ov6, ov7 |  |
| `38` | `BEE2` | base, ov6, ov7 |  |
| `39` | `C7F1` | base, ov6, ov7 |  |
| `3A` | `C983` | base, ov6, ov7 |  |
| `3B` | `C80D` | base, ov6, ov7 |  |
| `3C` | `8240` | base |  |
| `3D` | `B025` | base, ov6, ov7 |  |
| `3E` | `B039` | base, ov6, ov7 |  |
| `3F` | `B046` | base, ov6, ov7 |  |
| `40` | `B06D` | base, ov6, ov7 |  |
| `41` | `B061` | base, ov6, ov7 |  |
| `42` | `B05E` | base, ov6, ov7 |  |
| `43` | `B058` | base, ov6, ov7 |  |
| `44` | `B05B` | base, ov6, ov7 |  |
| `45` | `8623` | base |  |
| `46` | `84D3` | base |  |
| `47` | `863E` | base |  |
| `48` | `ADA5` | base, ov6 |  |
| `49` | `ADA8` | base, ov6 |  |
| `4A` | `ADAB` | base, ov6 |  |
| `4B` | `B4D7` | base, ov6, ov7 | writes ports 0x50-0x52 |
| `4C` | `0000` | unused |  |
| `4D` | `825E` | base |  |
| `4E` | `8256` | base |  |
| `4F` | `824E` | base |  |
| `50` | `D5B3` | base |  |
| `51` | `8D1F` | base |  |
| `52` | `8D22` | base |  |
| `53` | `8D2D` | base |  |
| `54` | `A456` | base, ov6 | writes MMR 0x4A |
| `55` | `8DA5` | base | writes ports 0x68,69,6B,6C |
| `56` | `A338` | base, ov6 |  |
| `57` | `8517` | base |  |
| `58` | `864E` | base |  |
| `59` | `8DF9` | base | as 0x55 |
| `5A` | `8DDD` | base | as 0x55 |
| `5B` | `0000` | unused |  |
| `5C` | `0000` | unused |  |
| `5D` | `0000` | unused |  |
| `5E` | `EAF4` | base, ov8 |  |
| `5F` | `9E41` | base, ov6 |  |
| `60` | `C4AC` | base, ov6, ov7 |  |
| `61` | `C4A4` | base, ov6, ov7 |  |
| `62` | `C4B4` | base, ov6, ov7 |  |
| `63` | `C4B0` | base, ov6, ov7 |  |
| `64` | `0000` | unused |  |
| `65` | `0000` | unused |  |
| `66` | `0000` | unused |  |
| `67` | `0000` | unused |  |
| `68` | `0000` | unused |  |
| `69` | `0000` | unused |  |
| `6A` | `0000` | unused |  |
| `6B` | `0000` | unused |  |
| `6C` | `8222` | base |  |
| `6D` | `8222` | base |  |
| `6E` | `8222` | base |  |
| `6F` | `8222` | base |  |
| `70` | `8D30` | base |  |
| `71` | `8D49` | base |  |
| `72` | `8D3F` | base |  |
| `73` | `865E` | base |  |
| `74` | `8D5A` | base |  |
| `75` | `E82D` | base, ov8 |  |
| `76` | `8D50` | base |  |
| `77` | `8D57` | base |  |
| `78` | `8671` | base |  |
| `79` | `BC00` | **not a handler** (table overrun: instruction word of the function at 0x847A) | writes ports 0x50,0x58-0x5A,0x5E; MMR 0x4A |
| `7A` | `BE41` | **not a handler** (table overrun: instruction word of the function at 0x847A) | not a handler (entry is data/instruction fragment) |
| `7B` | `7E80` | **not a handler** (table overrun: instruction word of the function at 0x847A) | re-runs DSP init (acts as reset) |
| `7C` | `23F0` | **not a handler** (table overrun: instruction word of the function at 0x847A) |  |
| `7D` | `BF09` | **not a handler** (table overrun: instruction word of the function at 0x847A) | not a handler |
| `7E` | `FF57` | **not a handler** (table overrun: instruction word of the function at 0x847A) |  |
| `7F` | `BE40` | **not a handler** (table overrun: instruction word of the function at 0x847A) |  |

## 8. Known limitations / unknowns

* **Argument semantics** per command are not decoded; all emulator trials used argument `0`.
* **Overlay selection**: which command (or sequence) makes the 80186 download `ov6/ov7/ov8` and switch modes is unknown.
  Handlers living in overlay ranges were only exercised with the overlay force-loaded.
* **No audio observed yet**: no command, called cold, produced samples on the serial/TDM ports (see `audio_scan.py`).
  The real `ATA` sequence (which command words the supervisor queues) is not yet known.
* **Extended (`0xFF`) messages**, DSP message types (`< 0x76`), and the use of control ports `0x18`, `0x1A`, `0x1C` in
  the transmit path are not decoded.
* The emulator needs `CMPR` to compare with **AR0** (not `ARCR`) for the DSP main loop to return to its mailbox poll
  (`lar ar0,[0x390]; cmpr` at `0x80D0`, `0x8105`, `0x810D`); whether that is real silicon behaviour is unconfirmed.
* The DSP is TMS320C51 silicon with a custom on-chip mask ROM that is **not** in the firmware. Interrupt vectors are
  assumed to be `B *(data[0x60+n])` stubs (n = IFR bit); no other ROM dependency has been seen.

## 9. Reproducing

```
cd dsp
gcc -O2 -fwrapv -shared -fPIC -o libc5x.so c5x_core.c
python3 -I host3.py          # sweeps commands 0x00-0x7E with arg 0 and groups outcomes
```

`host3.py` models the three host registers (`0x57` status, `0x5E` command, `0x5F` argument), acknowledges on a write to
`0x57`, and raises the serial/TDM interrupts once per codec sample (assumed 2083 DSP cycles per sample).
