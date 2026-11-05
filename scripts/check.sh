#!/usr/bin/env bash
# Local pre-flight: verilator lint -> yosys generic synth -> cocotb sim.
# Usage: scripts/check.sh [lint|synth|sim]
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"

# OSS CAD Suite: use its own self-consistent cocotb + python.
# Do NOT activate a venv — cocotb's embedded interpreter picks up
# OSS CAD Suite's base_prefix and dies with "failed to get the
# Python codec of the filesystem encoding".
export PATH="$HOME/oss-cad-suite/bin:$PATH"
CLEAN_PATH="$HOME/oss-cad-suite/bin:/usr/bin:/bin:/usr/sbin:/sbin"

TOP=$(awk -F'"' '/top_module/{print $2}' info.yaml | head -1)
# macOS ships bash 3.2: no mapfile, no associative arrays. Keep this a string.
SRC=$(find src -maxdepth 1 -name '*.v' | sort | tr '\n' ' ')

if [ -z "${TOP:-}" ]; then echo "ERROR: no top_module in info.yaml"; exit 1; fi
if [ -z "${SRC:-}" ]; then echo "ERROR: no .v files in src/"; exit 1; fi

STAGE="${1:-all}"
rc_total=0

echo "top module : $TOP"
echo "sources    : $SRC"
echo

# ---------------------------------------------------------------- lint
if [ "$STAGE" = "all" ] || [ "$STAGE" = "lint" ]; then
  echo "=== [1/3] verilator lint (-Wall) ==="
  # -Wno-DECLFILENAME: several modules intentionally live in one file (aes_core.v);
  # the remaining -Wall warnings are all DECLFILENAME style.
  verilator --lint-only -Wall -Wno-DECLFILENAME --top-module "$TOP" $SRC 2>&1 | sed 's/^/    /'
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 0 ]; then echo "    lint: CLEAN"; else echo "    lint: warnings/errors (exit $rc)"; rc_total=1; fi
  echo
fi

# ------------------------------------------------------- synth (size)
if [ "$STAGE" = "all" ] || [ "$STAGE" = "synth" ]; then
  echo "=== [2/3] yosys generic synthesis (size proxy, NOT GF180 cells) ==="
  echo "    note: synth_gf180 + the GF180 PDK are absent here; real gate"
  echo "    counts, area% and timing come from the CI 'gds' workflow."
  # No -q: yosys suppresses `stat` output along with the log.
  YOSYS_OUT=$(yosys -p "read_verilog $SRC; synth -top $TOP; stat" 2>&1)
  # Take the LAST "=== module ===" block -- synth prints an earlier one.
  echo "$YOSYS_OUT" | awk '/^=== /{blk=""} {blk = blk $0 ORS} END{printf "%s", blk}' | sed 's/^/    /'
  # Latches are a bug in clocked designs -- surface them loudly.
  if echo "$YOSYS_OUT" | grep -qE '\$(dlatch|adlatch)'; then
    echo "    !! LATCH INFERRED -- check for a missing 'default' in a case, or '=' vs '<='"
    rc_total=1
  fi
  echo
fi

# ---------------------------------------------------------------- sim
if [ "$STAGE" = "all" ] || [ "$STAGE" = "sim" ]; then
  echo "=== [3/3] cocotb simulation (RTL) ==="
  ( cd test && rm -rf sim_build results.xml tb.fst && \
    env -u VIRTUAL_ENV -u PYTHONHOME -u PYTHONPATH PATH="$CLEAN_PATH" make ) 2>&1 \
    | grep -E "PASS|FAIL|TESTS=|Error|error:|\*\* " | sed 's/^/    /'
  # results.xml must be checked with cocotb's own interpreter (tabbypy3);
  # the system python3 has no cocotb_tools module.
  if [ -f test/results.xml ] && "$(cocotb-config --python-bin)" -m cocotb_tools.check_results test/results.xml >/dev/null 2>&1; then
    echo "    sim: PASS"
  else
    echo "    sim: FAIL (see test/results.xml)"
    rc_total=1
  fi
  echo
fi

if [ "$rc_total" -eq 0 ]; then echo "PRE-FLIGHT: all stages passed"; else echo "PRE-FLIGHT: issues found above"; fi
exit "$rc_total"
