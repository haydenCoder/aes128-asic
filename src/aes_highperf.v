/*
 * Copyright (c) 2026 Chung Hon Ting
 * SPDX-License-Identifier: Apache-2.0
 *
 * Optional high-performance variant: fully unrolled AES-128 ENCRYPTION.
 * Latency: 1 cycle, throughput: 1 block/cycle, area ~2x the sequential core.
 * Not instantiated by the Tiny Tapeout top (project.v uses aes128_core);
 * swap it in if you need maximum throughput and have tile area to spare.
 * Note: encryption only - no decrypt path in this variant.
 */

`default_nettype none

// ============================================================
// Ultra-High-Speed: Fully Unrolled AES (10 rounds parallel)
// Latency: 1 cycle, Throughput: 1 block/cycle
// Area: ~10x baseline - only for speed-critical paths
// ============================================================
module aes128_unrolled (
    input  wire [127:0] key,
    input  wire [127:0] data_in,
    output wire [127:0] data_out
);

    wire [127:0] rk0, rk1, rk2, rk3, rk4, rk5, rk6, rk7, rk8, rk9, rk10;
    aes_key_expansion_comb u_key_exp (
        .cipher_key(key),
        .rk0(rk0), .rk1(rk1), .rk2(rk2), .rk3(rk3), .rk4(rk4),
        .rk5(rk5), .rk6(rk6), .rk7(rk7), .rk8(rk8), .rk9(rk9), .rk10(rk10)
    );

    wire [127:0] s0  = data_in ^ rk0;
    wire [127:0] s1, s2, s3, s4, s5, s6, s7, s8, s9, s10;

    aes_round  u_r1  (.state_in(s0),  .round_key(rk1),  .state_out(s1));
    aes_round  u_r2  (.state_in(s1),  .round_key(rk2),  .state_out(s2));
    aes_round  u_r3  (.state_in(s2),  .round_key(rk3),  .state_out(s3));
    aes_round  u_r4  (.state_in(s3),  .round_key(rk4),  .state_out(s4));
    aes_round  u_r5  (.state_in(s4),  .round_key(rk5),  .state_out(s5));
    aes_round  u_r6  (.state_in(s5),  .round_key(rk6),  .state_out(s6));
    aes_round  u_r7  (.state_in(s6),  .round_key(rk7),  .state_out(s7));
    aes_round  u_r8  (.state_in(s7),  .round_key(rk8),  .state_out(s8));
    aes_round  u_r9  (.state_in(s8),  .round_key(rk9),  .state_out(s9));
    aes_final_round u_r10 (.state_in(s9),  .round_key(rk10), .state_out(s10));

    assign data_out = s10;

endmodule
