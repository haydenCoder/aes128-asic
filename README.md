[![gds](https://github.com/haydenCoder/aes128-asic/workflows/gds/badge.svg)](/haydenCoder/aes128-asic/workflows/gds/badge.svg) [![docs](https://github.com/haydenCoder/aes128-asic/workflows/docs/badge.svg)](/haydenCoder/aes128-asic/workflows/docs/badge.svg) [![test](https://github.com/haydenCoder/aes128-asic/workflows/test/badge.svg)](/haydenCoder/aes128-asic/workflows/test/badge.svg) [![fpga](https://github.com/haydenCoder/aes128-asic/workflows/fpga/badge.svg)](/haydenCoder/aes128-asic/workflows/fpga/badge.svg)

# AES-128 Core for Tiny Tapeout GF180

So I built my own AES-128 ASIC. It's a byte-serial encryption core that fits in a 1×2 Tiny Tapeout tile on GF180MCU (180nm). The whole point was to learn how you actually get a chip from RTL all the way to real silicon.

I'll be honest — the first version was a fully parallel encrypt/decrypt core. It passed every single NIST vector in simulation, which felt great at the time. But it came out to ~712,000 µm². That's... a lot. It could never fit a tile. The GDS CI placement error literally proved it: 1559% utilization. So I threw it out and rewrote the thing as a byte-serial core with one shared S-box. Now it's ~297 clock cycles per encryption and ~3.3K generic cells, which comfortably fits in a 1×2 tile. Way more relaxed.

**[View the GDS visualizer here](https://gds-viewer.tinytapeout.com/?pdk=gf180mcu&model=https%3A%2F%2FhaydenCoder.github.io%2Faes128-asic%2F%2Ftinytapeout.oas)** (it generates after the Tiny Tapeout workflow runs).

![GDS Layout](docs/gds-layout.png)
*Figure 1: Rendered GDS layout from the CI GDS workflow (`gds.yaml`, run on commit 636a855). Also viewable interactively in the [GDS visualizer](https://gds-viewer.tinytapeout.com/?pdk=gf180mcu&model=https%3A%2F%2FhaydenCoder.github.io%2Faes128-asic%2F%2Ftinytapeout.oas).*

![Simulation Waveform](docs/waveform.png)
*Figure 2: Simulated timing diagram of NIST test vector 1 encryption (iverilog VCD rendered with matplotlib). Key/data byte loads, START pulse, rounds 1–10, DONE with the ciphertext.*

## What it actually does

Yeah, it encrypts AES-128: 128-bit block, 128-bit key, 10 rounds, FIPS-197 compliant. But the interesting part is how. It's area-optimized and byte-serial — one shared compact (Canright composite-field) S-box gets time-multiplexed over the state and key bytes. SubBytes happen by 128-bit rotation, and the round keys update in place through a 32-bit `g` register. That's roughly 306 flops total, ~3.3K generic cells.

The timing math is a bit of a mess to write out: ~297 cycles per encryption, which is 1 + 9×(8 key + 1 ShiftRows + 16 SubBytes + 4 MixColumns + 1 AddRoundKey) + 26. That last +26 is the final round and output phase.

I/O is all serial — 8-bit `ui_in` on the way in, 8-bit `uo_out` on the way out. The whole core lands in a 1×2 tile on GF180MCU (~340×320 µm), and it stays under the 60% density cap. Runs at 20 MHz, and the CI GDS workflow (`gds.yaml`) verifies it.

One thing that bugs me a little: the taped-out hardware is encrypt-only. The earlier parallel version had decryption (4/4 NIST, openssl round-trip), but to fit the tile I had to cut it. I'll probably add it back eventually. Maybe.

## How it runs

So here's the thing about how this thing actually works, byte by byte. The key streams in first — 16 bytes, MSB-first. The register updates in place as the rounds run, so at any given moment it's holding the current round key. Then the 16 plaintext bytes stream in, also MSB-first. Hit START and the whole thing kicks off: state ^= round key, then 10 rounds of key update (8 cycles), SubBytes (16), and ShiftRows+MixColumns+AddRoundKey (1). Wait, round 10 skips MixColumns — that's the one that always gets me. When it's done, the ciphertext is sitting in the state register and it streams out 16 bytes on `uo_out`.

The serial protocol itself is:

1. Pulse `START` (`uio_in[0]`)
2. Stream 16 key bytes, then 16 plaintext bytes, on `ui_in`, one per clock, MSB first
3. Wait: `BUSY` (`uio_out[6]`) stays high ~300 cycles
4. Read 16 ciphertext bytes on `uo_out` while `DATA_VALID` (`uio_out[7]`) is high

(`uio_in[7:1]` are unused.)

## Pinout

| Pin | Direction | Name | Description |
|-----|-----------|------|-------------|
| `ui_in[7:0]` | Input | `DATA_IN` | Serial byte input (key, then plaintext) |
| `uo_out[7:0]` | Output | `DATA_OUT` | Serial byte output (ciphertext) |
| `uio_in[0]` | Input | `START` | Pulse high to begin operation |
| `uio_in[7:1]` | — | Unused | Blank in info.yaml |
| `uio_out[6]` | Output | `BUSY` | High while processing |
| `uio_out[7]` | Output | `DATA_VALID` | High during output phase |

## Problems I hit

There were more of these than I'd like to admit. Some took forever.

| Problem | Solution |
|---------|----------|
| Parallel core was 712,000 µm² (13.7× over the 1×1 tile; GDS CI: utilization 1559.533%, GPL-0301) | Rewrote as byte-serial core with one shared S-box; moved to a 1×2 tile |
| LUT S-box (~2K mux cells) too big | Replaced with the compact Canright composite-field S-box (GF(2⁸) inversion in GF((2²)²) + affine transform, ~150 gates); verified 256/256 against the FIPS-197 table in Python and Verilog |
| 16-way byte-write muxes in the key schedule blew up area | Round key updated in place word-by-word through a 32-bit `g` register |
| Variable-index SubBytes part-select needed a 16:1 mux per state bit | SubBytes via 128-bit rotation (16 × 8-bit rotations = identity ordering) |
| Streaming wrapper sampled a stale byte on immediate LOAD_KEY→LOAD_DATA transition (wrong result `775a29b2…`) | Registered `key_loaded`/`data_loaded` flags replicate the original wrapper's one-cycle bubble |
| Inverse S-box table had 23 mis-transcribed entries (parallel core) | Regenerated the 256-entry inverse S-box programmatically from the forward S-box |
| Inverse round used the wrong operation order (parallel core) | Corrected to FIPS-197 InvCipher order: InvShiftRows → InvSubBytes → AddRoundKey → InvMixColumns |
| Decrypt FSM started with rk0 and skipped the final rk0 round (parallel core) | Decrypt started at AddRoundKey(rk10), rounds 9→1, ending with InvShiftRows/InvSubBytes/^rk0 |
| Test expected ciphertexts for vectors 2 and 4 were wrong | Corrected to openssl values `4f638c73…` and `3f5b8cc9…` |
| CI stub workflows referenced nonexistent `tt-gds-action@v1` and never installed cocotb | Real template workflows pinned to `TinyTapeout/tt-gds-action@ttgf26c` with `cocotb==2.1.0` |
| Stale token in git remote blocked push | Fixed credential helper via `gh auth setup-git` |
| Cocotb testbench drove concurrent clocks per test, causing contention | Single clock, one test running all 4 vectors sequentially |

## Test Bench

All 4 NIST FIPS-197 vectors pass, and I cross-checked them with openssl just to be safe:

| Test | Key | Plaintext | Ciphertext |
|------|-----|-----------|------------|
| NIST-1 (FIPS-197 C.1) | `000102030405060708090a0b0c0d0e0f` | `00112233445566778899aabbccddeeff` | `69c4e0d86a7b0430d8cdb78070b4c55a` |
| NIST-2 (chained) | same | `69c4e0d86a7b0430d8cdb78070b4c55a` | `4f638c735f614301567824b1a21a4f6a` |
| NIST-3 (all-zero) | `00...00` | `00...00` | `66e94bd4ef8a2c3b884cfa59ca342b2e` |
| NIST-4 (all-zero key, all-ones pt) | `00...00` | `ff...ff` | `3f5b8cc9ea855a0afa7347d23e8d664e` |

The testbenches: `test/tb_core.v` drives the core directly with iverilog — 4/4 PASS. `test/test.py` is the cocotb one and drives the full Tiny Tapeout wrapper — also 4/4 PASS. And the decrypt round-trip was 4/4 PASS back in the earlier parallel version, before I cut decryption.

![NIST Test Vectors Waveform](docs/nist-waveforms.png)
*Figure 3: All 4 NIST test vectors, simulated encryption (iverilog VCD rendered with matplotlib). All PASS.*

![Schematic](docs/schematic.png)
*Figure 4: Yosys `show` schematic of the byte-serial `aes128_core`. Shared S-box, rotation datapath, key-update logic.*

## Testing

```bash
bash scripts/check.sh   # lint + generic synthesis + cocotb (full pre-flight)
cd test && make         # cocotb simulation only
```

## Setup

You'll need `iverilog`, `verilator`, `yosys`, and `cocotb` on your PATH (e.g. via `oss-cad-suite`). Then:

```bash
git clone https://github.com/haydenCoder/aes128-asic
cd aes128-asic
./scripts/check.sh     # lint → synth → cocotb
make -C test           # cocotb simulation
gtkwave test/sim_build/tb_core.fst   # view waveforms in GTKWave
```

## Screenshots & Visualizations

Here's the rest of the visual stuff. I kept it as a quick reference:

| Visualization | Description |
|---------------|-------------|
| ![GDS Layout](docs/gds-layout.png) | Full tile layout, rendered by the CI GDS workflow (`gds.yaml`). Also in the [GDS visualizer](https://gds-viewer.tinytapeout.com/?pdk=gf180mcu&model=https%3A%2F%2FhaydenCoder.github.io%2Faes128-asic%2F%2Ftinytapeout.oas) |
| ![Simulation Waveform](docs/waveform.png) | Timing diagram (VCD → PNG) of NIST vector 1 encryption |
| ![NIST Waveforms](docs/nist-waveforms.png) | All 4 NIST test vectors, simulated encryption. All PASS |
| ![Schematic](docs/schematic.png) | Yosys `show` schematic of `aes128_core` |

## Programming Configuration

The `fpga` workflow (`.github/workflows/fpga.yaml`, manual dispatch) builds an ICE40UP5K bitstream. To actually test it on hardware, you'd drive the serial protocol from a Tiny Tapeout dev board — RP2350 or IcePi Zero — and check the ciphertext against the NIST vectors above.

## Inspiration

This whole project runs on the Tiny Tapeout template, which comes with all the workflows to build your project and get it ready for manufacturing. Big thanks to the Tiny Tapeout community and Matt Venn for making silicon accessible at all.

## License

Apache-2.0 (compatible with Tiny Tapeout submission requirements).

## Author

Chung Hon Ting (Diocesan Boys' School, 8M #4)
