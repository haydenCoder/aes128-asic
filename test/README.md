# Testbenches

Two testbenches cover the design at different levels:

- `test.py` (cocotb): drives the full Tiny Tapeout wrapper
  (`tt_um_haydencoder_aes128`) through the pin protocol — START pulse,
  16 key bytes + 16 plaintext bytes on `ui_in`, then 16 ciphertext bytes
  read from `uo_out` while `DATA_VALID` is high. Runs all 4 NIST/openssl
  vectors. Uses protocol timing only (no internal-register reads), so the
  same test runs unchanged on the gate-level netlist in CI (`gl_test`).
- `tb_core.v` (standalone iverilog): drives `aes128_core` directly through
  its byte-serial interface, same 4 vectors.

Expected ciphertexts were generated with openssl and are listed in the
top-level README.

## Running

```sh
make -B          # RTL simulation (cocotb + icarus)
```

Use the repo pre-flight for lint + synthesis + simulation in one go:

```sh
bash ../scripts/check.sh
```

Gate-level simulation (after hardening; copy the final netlist to
`gate_level_netlist.v` first — the CI `gds` workflow does this automatically):

```sh
make -B GATES=yes
```

## Waveforms

The simulation writes `tb.fst` (FST format). View it with:

```sh
gtkwave tb.fst tb.gtkw
# or
surfer tb.fst
```

To dump VCD instead, edit `tb.v` to use `$dumpfile("tb.vcd");` and run
`make -B FST=`.