<!--
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The AES-128 core follows the standard FIPS-197 specification:

1. **Key Expansion** — Combinational key schedule generates 11 round keys (RK0–RK10) from the 128-bit cipher key using RotWord, SubWord, and Rcon
2. **Initial AddRoundKey** — Plaintext XORed with RK0
3. **9 Main Rounds** — Each round: SubBytes → ShiftRows → MixColumns → AddRoundKey
4. **Final Round** — SubBytes → ShiftRows → AddRoundKey (no MixColumns)
5. **Decryption** — Inverse operations in reverse order with inverse key schedule

**Serial Protocol:**
1. **Load Key** — Set `KEY_DATA_SEL=0`, send 16 bytes via `ui_in` (MSB first)
2. **Load Data** — Set `KEY_DATA_SEL=1`, send 16 bytes via `ui_in` (MSB first)
3. **Start** — Set `MODE` (0=encrypt, 1=decrypt), pulse `START` high for 1 cycle
4. **Wait** — Poll `BUSY` until low
5. **Read Output** — 16 bytes appear on `uo_out` with `DATA_VALID` high (MSB first)

## How to test

```bash
# Run full verification pipeline (lint → synth → sim)
./scripts/check.sh

# Or run individual steps:
make -C test          # Run cocotb simulation
gtkwave test/tb.fst   # View waveforms in GTKWave
```

All 4 NIST FIPS-197 test vectors pass in core isolation:
- NIST-1: Standard test vector
- NIST-2: Chained encryption (ciphertext becomes next plaintext)
- NIST-3: All-zero key and plaintext
- NIST-4: All-zero key, all-ones plaintext

## Visualizations

| Image | Description |
|-------|-------------|
| `gds-layout.png` | Full chip layout from Tiny Tapeout workflow (OpenLane/OpenROAD) |
| `waveform.png` | GTKWave simulation of NIST Test Vector 1 |
| `nist-waveforms.png` | All 4 NIST test vectors in core isolation |

*To generate these yourself after Tiny Tapeout workflow runs:*
```bash
# GDS visualizer (after GitHub Actions workflow completes)
# https://gds-viewer.tinytapeout.com/?pdk=gf180mcu&model=...

# Waveforms
cd test && make -B && gtkwave tb.fst
```

## External hardware

None required for basic operation. For FPGA testing:
- Tiny Tapeout dev board (RP2350/IcePi Zero)
- Logic analyzer (for verifying serial I/O protocol)

## Pinout

| Pin | Direction | Name | Description |
|-----|-----------|------|-------------|
| `ui_in[7:0]` | Input | `DATA_IN` | Serial byte input (key/data) |
| `uo_out[7:0]` | Output | `DATA_OUT` | Serial byte output (ciphertext/plaintext) |
| `uio_in[0]` | Input | `START` | Pulse high to begin operation |
| `uio_in[1]` | Input | `MODE` | 0 = encrypt, 1 = decrypt |
| `uio_in[2]` | Input | `KEY_DATA_SEL` | 0 = load key, 1 = load data |
| `uio_out[6]` | Output | `BUSY` | High while processing |
| `uio_out[7]` | Output | `DATA_VALID` | High during output phase |