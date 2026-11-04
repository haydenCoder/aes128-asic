<!--
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The project is an **AES-128 encryption core** (128-bit block, 128-bit key, 10 rounds per FIPS-197), byte-serial and area-optimized, wrapped for Tiny Tapeout as `tt_um_haydencoder_aes128` in a **1×2 tile** on GF180MCU.

**Datapath** (`src/aes_core.v`, module `aes128_core`):

1. **Byte-serial load** — 16 key bytes stream into the 128-bit round-key register, then 16 plaintext bytes into the 128-bit state register (MSB first, one byte per clock).
2. **Start** — state ^= round key (round-0 AddRoundKey), then 10 rounds of:
   - **Key update (8 cycles/round)** — `g = SubWord(RotWord(w3)) ^ Rcon` is assembled one byte per cycle through the single shared S-box, then the four 32-bit key words are updated in place (`w[j] ^= w[j-1]`).
   - **SubBytes (16 cycles/round)** — one state byte per cycle through the same shared S-box; the state register rotates left by 8 bits each cycle, so after 16 rotations the byte order is restored.
   - **ShiftRows + MixColumns + AddRoundKey (1 cycle/round)** — purely combinational (`aes_shift_rows_correct`, `aes_mix_columns`); the final round skips MixColumns.
3. **S-box** (`src/sbox.v`) — compact Canright composite-field S-box: GF(2⁸) inversion computed in the composite field GF((2²)²) plus the affine transform (~150 gates instead of a 256-entry LUT). Verified entry-for-entry against the FIPS-197 table.
4. **Done** — after 1 + 9×(8+1+16+4+1) + (8+1+16+1) = **297 cycles** the ciphertext sits in the state register and streams out 16 bytes, MSB first.

Decryption was implemented and verified (all 4 NIST vectors + openssl round-trip) in the earlier parallel-core version in RTL simulation; the taped-out hardware is **encrypt-only** to fit the tile area budget.

**Serial byte I/O protocol** (8-bit `ui_in` / `uo_out`):

1. **Start** — pulse `START` (`uio_in[0]`) high for one clock.
2. **Load key** — the wrapper enters key-load automatically: stream 16 key bytes on `ui_in`, one per clock, **MSB first**.
3. **Load data** — then stream 16 plaintext bytes on `ui_in`, one per clock, MSB first.
4. **Wait** — `BUSY` (`uio_out[6]`) is high while the core processes (~297 cycles).
5. **Read output** — `DATA_VALID` (`uio_out[7]`) goes high and 16 ciphertext bytes appear on `uo_out`, one per clock, **MSB first**.

`uio_in[7:1]` are unused. Timing target is 20 MHz; static timing on GF180MCU is verified by the CI GDS workflow, not locally.

## How to test

**Simulation (cocotb + iverilog):**

```bash
bash scripts/check.sh   # lint + generic synthesis + cocotb
cd test && make         # cocotb simulation only
```

The test suite runs all **4 NIST FIPS-197 AES-128 test vectors** through the full Tiny Tapeout wrapper (encrypt), checked against openssl-generated expected values — all pass:

| Test | Key | Plaintext | Ciphertext |
|------|-----|-----------|------------|
| NIST-1 | `000102030405060708090a0b0c0d0e0f` | `00112233445566778899aabbccddeeff` | `69c4e0d86a7b0430d8cdb78070b4c55a` |
| NIST-2 (chained) | `000102030405060708090a0b0c0d0e0f` | `69c4e0d86a7b0430d8cdb78070b4c55a` | `4f638c735f614301567824b1a21a4f6a` |
| NIST-3 (all-zero) | `00...00` | `00...00` | `66e94bd4ef8a2c3b884cfa59ca342b2e` |
| NIST-4 (zero key, all-ones pt) | `00...00` | `ff...ff` | `3f5b8cc9ea855a0afa7347d23e8d664e` |

`test/tb_core.v` additionally drives the core directly (bypassing the wrapper) — 4/4 PASS. Simulated waveforms of these runs are rendered from the VCD: `waveform.png` (vector 1, annotated round-by-round) and `nist-waveforms.png` (all 4 vectors). `schematic.png` is the Yosys `show` schematic of `aes128_core`.

**On hardware:** the design can be loaded onto an FPGA on the Tiny Tapeout dev board (RP2350 or IcePi Zero) using the standard Tiny Tapeout FPGA flow. Drive the serial protocol above from the RP2350 (pulse START, stream 32 bytes on `ui_in`, then read 16 bytes from `uo_out` while `DATA_VALID` is high); a logic analyzer on the `uio` pins is handy for debugging the byte handshake.

## Visualizations

| Image | Description |
|-------|-------------|
| `gds-layout.png` | Full tile layout rendered by the CI GDS workflow (`gds.yaml`, commit 636a855); interactive: https://gds-viewer.tinytapeout.com/?pdk=gf180mcu&model=https%3A%2F%2FhaydenCoder.github.io%2Faes128-asic%2F%2Ftinytapeout.oas |
| `waveform.png` | Simulated timing diagram (iverilog VCD → matplotlib) of NIST test vector 1 encryption |
| `nist-waveforms.png` | All 4 NIST test vectors, simulated encryption — all PASS |
| `schematic.png` | Yosys `show` schematic of the byte-serial `aes128_core` |

## External hardware

None required for simulation. For hardware testing: Tiny Tapeout dev board (RP2350/IcePi Zero) for the FPGA flow, and optionally a logic analyzer to verify the serial I/O protocol on the `uio` pins.

## Pinout

| Pin | Direction | Name | Description |
|-----|-----------|------|-------------|
| `ui_in[7:0]` | Input | `DATA_IN` | Serial byte input (key, then plaintext) |
| `uo_out[7:0]` | Output | `DATA_OUT` | Serial byte output (ciphertext) |
| `uio_in[0]` | Input | `START` | Pulse high to begin operation |
| `uio_in[7:1]` | — | Unused | Blank in info.yaml |
| `uio_out[6]` | Output | `BUSY` | High while processing |
| `uio_out[7]` | Output | `DATA_VALID` | High during output phase |
