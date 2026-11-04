# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# AES-128 encryption test vectors, verified against openssl.
# The taped-out hardware implements encryption (byte-serial core, one tile);
# decryption was verified in RTL simulation of the earlier parallel core.
TEST_VECTORS = [
    {"name": "NIST Test 1",
     "key": bytes.fromhex("000102030405060708090a0b0c0d0e0f"),
     "plaintext": bytes.fromhex("00112233445566778899aabbccddeeff"),
     "ciphertext": bytes.fromhex("69c4e0d86a7b0430d8cdb78070b4c55a")},
    {"name": "NIST Test 2",
     "key": bytes.fromhex("000102030405060708090a0b0c0d0e0f"),
     "plaintext": bytes.fromhex("69c4e0d86a7b0430d8cdb78070b4c55a"),
     "ciphertext": bytes.fromhex("4f638c735f614301567824b1a21a4f6a")},
    {"name": "NIST Test 3 - All zeros key",
     "key": bytes.fromhex("00000000000000000000000000000000"),
     "plaintext": bytes.fromhex("00000000000000000000000000000000"),
     "ciphertext": bytes.fromhex("66e94bd4ef8a2c3b884cfa59ca342b2e")},
    {"name": "NIST Test 4 - All zeros key, all ones pt",
     "key": bytes.fromhex("00000000000000000000000000000000"),
     "plaintext": bytes.fromhex("ffffffffffffffffffffffffffffffff"),
     "ciphertext": bytes.fromhex("3f5b8cc9ea855a0afa7347d23e8d664e")},
]

# ===== HELPER FUNCTIONS (defined ONCE) =====

def get_uio_in(dut):
    return int(dut.uio_in.value)

def set_uio_in(dut, val):
    dut.uio_in.value = val & 0xFF

def get_uio_out(dut):
    return int(dut.uio_out.value)

def get_state(dut):
    # Internal FSM state is not reliably readable in the gate-level netlist
    # (yosys renames it), so the driver below uses protocol timing only.
    try:
        return int(dut.user_project.state.value)
    except Exception:
        return -1

async def send_byte(dut, byte_val):
    dut.ui_in.value = byte_val
    await ClockCycles(dut.clk, 1)

async def send_bytes(dut, data_bytes):
    for b in data_bytes:
        await send_byte(dut, b)

async def pulse_start(dut, decrypt=False):
    # The wrapper latches decrypt_reg_d <= uio_in[1] only in IDLE when
    # uio_in[0] && !key_loaded, i.e. on the FIRST start pulse after reset.
    # Drive uio_in = 0x03 for decrypt, 0x01 for encrypt on that pulse.
    val = (get_uio_in(dut) & ~0x03) | 0x01 | (0x02 if decrypt else 0x00)
    set_uio_in(dut, val)
    await ClockCycles(dut.clk, 1)
    val = get_uio_in(dut) & ~0x03
    set_uio_in(dut, val)
    # Don't wait extra cycle - let state machine transition immediately

async def wait_for_state(dut, target_state, timeout=100):
    for _ in range(timeout):
        if get_state(dut) == target_state:
            return True
        await ClockCycles(dut.clk, 1)
    dut._log.error(f"Timeout waiting for state {target_state}, current state={get_state(dut)}")
    return False

async def wait_for_data_valid(dut, max_cycles=5000):
    data_valid = (get_uio_out(dut) >> 7) & 1
    if data_valid:
        return True
    for _ in range(max_cycles):
        await ClockCycles(dut.clk, 1)
        data_valid = (get_uio_out(dut) >> 7) & 1
        if data_valid:
            return True
    return False

async def wait_for_busy_low(dut, max_cycles=5000):
    for _ in range(max_cycles):
        await ClockCycles(dut.clk, 1)
        busy = (get_uio_out(dut) >> 6) & 1
        if not busy:
            return True
    return False

def uo_out_to_byte(dut):
    try:
        return int(dut.uo_out.value) & 0xFF
    except ValueError:
        bin_str = dut.uo_out.value.binstr
        if 'x' in bin_str or 'z' in bin_str:
            return 0
        return int(bin_str, 2) & 0xFF

async def read_output_bytes(dut, num_bytes=16):
    result = bytearray()
    for i in range(num_bytes):
        dv = await wait_for_data_valid(dut, max_cycles=5000)
        if not dv:
            print(f"Timeout on byte {i}")
            break
        byte_val = uo_out_to_byte(dut)
        result.append(byte_val)
        await ClockCycles(dut.clk, 1)
    return bytes(result)

async def run_aes(dut, key, data_in, expected_out, decrypt=False, test_name=""):
    dut._log.info(f"Running AES {'decrypt' if decrypt else 'encrypt'} test: {test_name}")

    # Full reset before every operation (clears key_loaded/data_loaded)
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    set_uio_in(dut, 0)
    await ClockCycles(dut.clk, 30)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # Pulse start (IDLE -> LOAD_KEY on the next edge)
    await pulse_start(dut, decrypt=decrypt)

    # Stream 16 key bytes then 16 data bytes on consecutive cycles; the
    # wrapper consumes exactly one byte per cycle in LOAD_KEY/LOAD_DATA.
    await send_bytes(dut, key)
    await send_bytes(dut, data_in)

    # Wait for the core to finish (~300 cycles) and DATA_VALID to rise
    dv = await wait_for_data_valid(dut, max_cycles=5000)
    assert dv, "Timeout waiting for DATA_VALID"
    dut._log.info("DATA_VALID seen")

    # Read 16 ciphertext bytes, MSB first
    output = await read_output_bytes(dut, 16)

    # Wait for busy low (back to IDLE)
    success = await wait_for_busy_low(dut, max_cycles=5000)
    assert success, "Timeout waiting for busy low"

    dut._log.info(f"Expected: {expected_out.hex()}")
    dut._log.info(f"Got:      {output.hex()}")

    assert output == expected_out, f"Output mismatch! Expected {expected_out.hex()}, got {output.hex()}"
    dut._log.info("Test PASSED")

    return output

# ===== TEST CASE =====
# ONE test: a single Clock is started once and shared by every operation.
# (Starting a Clock inside each @cocotb.test would put multiple drivers on dut.clk.)

@cocotb.test()
async def test_aes_vectors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await ClockCycles(dut.clk, 2)  # let the clock get running

    # Encrypt every vector through the full wrapper (START -> 16 key bytes
    # -> 16 data bytes -> BUSY -> 16 ciphertext bytes, MSB first)
    for tv in TEST_VECTORS:
        await run_aes(dut, tv["key"], tv["plaintext"], tv["ciphertext"],
                      decrypt=False, test_name=tv["name"] + " encrypt")

    dut._log.info("ALL VECTORS PASSED")
