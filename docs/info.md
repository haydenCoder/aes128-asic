<!--
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The project is an **AES-128 encryption/decryption core** (128-bit block, 128-bit key, 10 rounds) implemented in Verilog per **FIPS-197**, wrapped for Tiny Tapeout as `tt_um_haydencoder_aes128` in a single 1×1 tile on GF180MCU.

**Datapath** (`src/aes_core.v`):

1. **Key expansion** — `aes_key_expansion_comb` (`src/key_expansion.v`) is fully combinational: it derives all 11 round keys (RK0–RK10) from the 128-bit cipher key using RotWord, SubWord and Rcon, with no external memory.
2. **Encryption** — Initial AddRoundKey with RK0, then 9 main rounds of SubBytes → ShiftRows → MixColumns → AddRoundKey (`aes_round`), and a final round of SubBytes → ShiftRows → AddRoundKey without MixColumns (`aes_final_round`). SubBytes uses 16 parallel S-box instances (`src/sbox.v`).
3. **Decryption** — The inverse cipher in reverse order: the FSM starts with AddRoundKey(RK10), runs `aes_inv_round` (InvShiftRows → InvSubBytes → AddRoundKey → InvMixColumns) for rounds 9→1, and finishes with `aes_inv_final_round` (InvShiftRows → InvSubBytes → ^RK0). The inverse S-box table is generated from the forward S-box.

The core is serial: one 128-bit round per clock, so one operation takes ~12 clock cycles.

**Serial byte I/O protocol** (8-bit `ui_in` / `uo_out`):

1. **Start** — Set `MODE` (`uio_in[1]`: 0 = encrypt, 1 = decrypt) and pulse `START` (`uio_in[0]`) high for one clock.
2. **Load key** — The wrapper automatically enters key-load: stream 16 key bytes on `ui_in`, one per clock, **MSB first**.
3. **Load data** — Then stream 16 data (plaintext/ciphertext) bytes on `ui_in`, one per clock, MSB first.
4. **Wait** — `BUSY` (`uio_out[6]`) is high while the core processes.
5. **Read output** — `DATA_VALID` (`uio_out[7]`) goes high and 16 result bytes appear on `uo_out`, one per clock, **MSB first**.

`uio_in[2]` is reserved/unused. Timing target is 50 MHz; static timing on GF180MCU is verified by the CI GDS workflow, not locally.

## How to test

**Simulation (cocotb + iverilog):**

```bash
bash scripts/check.sh   # lint + generic synthesis + cocotb
cd test && make         # cocotb simulation only
```

The test suite runs all **4 NIST FIPS-197 AES-128 test vectors**, for **both encrypt and decrypt**, plus an encrypt→decrypt round-trip checked against openssl — all pass:

| Test | Key | Plaintext | Ciphertext |
|------|-----|-----------|------------|
| NIST-1 | `000102030405060708090a0b0c0d0e0f` | `00112233445566778899aabbccddeeff` | `69c4e0d86a7b0430d8cdb78070b4c55a` |
| NIST-2 (chained) | `000102030405060708090a0b0c0d0e0f` | `69c4e0d86a7b0430d8cdb78070b4c55a` | `4f638c735f614301567824b1a21a4f6a` |
| NIST-3 (all-zero) | `00...00` | `00...00` | `66e94bd4ef8a2c3b884cfa59ca342b2e` |
| NIST-4 (zero key, all-ones pt) | `00...00` | `ff...ff` | `3f5b8cc9ea855a0afa7347d23e8d664e` |

Simulated waveforms of these runs are rendered from the VCD: `waveform.png` (vector 1, annotated round-by-round) and `nist-waveforms.png` (all 4 vectors). `schematic.png` is the Yosys `show` schematic of `aes128_core`.

**On hardware:** the design can be loaded onto an FPGA on the Tiny Tapeout dev board (RP2350 or IcePi Zero) using the standard Tiny Tapeout FPGA flow. Drive the serial protocol above from the RP2350 (pulse START, stream 32 bytes on `ui_in`, then read 16 bytes from `uo_out` while `DATA_VALID` is high); a logic analyzer on the `uio` pins is handy for debugging the byte handshake.

## Visualizations

| Image | Description |
|-------|-------------|
| GDS visualizer link | Full chip layout rendered by the CI GDS workflow (`gds.yaml`) — not committed to the repo: https://gds-viewer.tinytapeout.com/?pdk=gf180mcu&model=https%3A%2F%2FhaydenCoder.github.io%2Faes128-asic%2F%2Ftinytapeout.oas |
| `waveform.png` | Simulated timing diagram (iverilog VCD → matplotlib) of NIST test vector 1 encryption |
| `nist-waveforms.png` | All 4 NIST test vectors, simulated encryption — all PASS |
| `schematic.png` | Yosys `show` schematic of `aes128_core` (key expansion + round instances) |

## External hardware

None required for simulation. For hardware testing: Tiny Tapeout dev board (RP2350/IcePi Zero) for the FPGA flow, and optionally a logic analyzer to verify the serial I/O protocol on the `uio` pins.

## Pinout

| Pin | Direction | Name | Description |
|-----|-----------|------|-------------|
| `ui_in[7:0]` | Input | `DATA_IN` | Serial byte input (key/data) |
| `uo_out[7:0]` | Output | `DATA_OUT` | Serial byte output (ciphertext/plaintext) |
| `uio_in[0]` | Input | `START` | Pulse high to begin operation |
| `uio_in[1]` | Input | `MODE` | 0 = encrypt, 1 = decrypt |
| `uio_in[2]` | — | Reserved | Unused |
| `uio_out[6]` | Output | `BUSY` | High while processing |
| `uio_out[7]` | Output | `DATA_VALID` | High during output phase |
