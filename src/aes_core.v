/*
 * Copyright (c) 2026 Chung Hon Ting
 * SPDX-License-Identifier: Apache-2.0
 *
 * AES-128 encryption core, byte-serial implementation for a Tiny Tapeout tile.
 *
 * Area-optimized: one shared compact (Canright) S-box time-multiplexed over
 * state bytes and key schedule, SubBytes and MixColumns via register
 * rotation, in-place round-key updates through a 32-bit g register,
 * algorithmic Rcon (xtime). ~306 flops, ~3.5K combinational gates.
 *
 * Interface (byte-serial load, MSB-first):
 *   key_we/key_byte   : shift one key byte into the round-key register
 *   data_we/data_byte : shift one plaintext byte into the state register
 *   start             : pulse -> state <= state ^ rk (round 0 AddRoundKey),
 *                       then 10 rounds
 *   done              : 1-cycle pulse when the ciphertext is in data_out
 *   out_shift/out_byte: while asserted, shifts the result out MSB-first
 *
 * Latency: 1 + 9*(8 key + 1 sr + 16 sub + 4 mc + 1 ark) + (8 + 1 + 16 + 1) = 297 cycles.
 */

`default_nettype none

module aes128_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         key_we,
    input  wire [7:0]   key_byte,
    input  wire         data_we,
    input  wire [7:0]   data_byte,
    input  wire         out_shift,
    output wire [7:0]   out_byte,
    output wire [127:0] data_out,
    output wire         done,
    output wire         busy
);

    localparam PH_IDLE = 3'd0;
    localparam PH_KEY  = 3'd1;   // round-key update (8 cycles: 4 g + 4 word xors)
    localparam PH_SR   = 3'd2;   // ShiftRows (1 cycle, pure permutation)
    localparam PH_SUB  = 3'd3;   // SubBytes via 8-bit rotation (16 cycles)
    localparam PH_MC   = 3'd4;   // MixColumns via 32-bit rotation (4 cycles)
    localparam PH_ARK  = 3'd5;   // AddRoundKey (1 cycle)

    reg [127:0] state;
    reg [127:0] rk;              // round key (sliding window, updated in place)
    reg [31:0]  g;               // SubWord(RotWord(w3)) ^ Rcon
    reg [7:0]   rcon_r;          // Rcon for the current round (xtime chain)
    reg [3:0]   round;           // 1..10
    reg [4:0]   cnt;
    reg [2:0]   phase;
    reg         running;
    reg         done_r;

    // shared S-box: key phase reads rotated last word, sub phase reads top byte
    wire [7:0] sbox_in;
    wire [7:0] sbox_out;
    assign sbox_in = (phase == PH_KEY) ?
                        ((cnt == 5'd0) ? rk[23:16] :
                         (cnt == 5'd1) ? rk[15:8]  :
                         (cnt == 5'd2) ? rk[7:0]   : rk[31:24]) :
                        state[127:120];

    aes_sbox u_sbox (
        .data_in (sbox_in),
        .data_out(sbox_out)
    );

    // xtime: multiply by 2 in GF(2^8) with the AES polynomial
    function [7:0] xtime;
        input [7:0] b;
        xtime = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
    endfunction

    wire [127:0] state_sr;
    aes_shift_rows_correct u_sr (
        .state_in (state),
        .state_out(state_sr)
    );

    // one MixColumns column on the top 32 bits of the (ShiftRows-applied) state
    wire [31:0] mc_col;
    aes_mix_column u_mc (
        .col_in (state[127:96]),
        .col_out(mc_col)
    );

    // shared AddRoundKey XOR tree
    wire [127:0] ark = state ^ rk;

    // merged 8-bit rotation source: load byte / output shift / SubBytes
    wire [7:0] rot8_byte = data_we   ? data_byte :
                           out_shift ? 8'h00     : sbox_out;
    wire       rot8_en   = data_we || out_shift || (phase == PH_SUB);

    assign data_out = state;
    assign out_byte = state[127:120];
    assign done     = done_r;
    assign busy     = running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= 128'd0;
            rk      <= 128'd0;
            g       <= 32'd0;
            rcon_r  <= 8'h01;
            round   <= 4'd0;
            cnt     <= 5'd0;
            phase   <= PH_IDLE;
            running <= 1'b0;
            done_r  <= 1'b0;
        end else begin
            done_r <= 1'b0;

            // byte-serial key load
            if (key_we) rk <= {rk[119:0], key_byte};

            // byte-serial data load / output shift / SubBytes share one rotation port
            if (rot8_en) state <= {state[119:0], rot8_byte};

            if (start) begin
                state   <= ark;          // round 0 AddRoundKey (ark = state ^ rk)
                round   <= 4'd1;
                rcon_r  <= 8'h01;
                cnt     <= 5'd0;
                phase   <= PH_KEY;
                running <= 1'b1;
                done_r  <= 1'b0;
            end else if (running) begin
                case (phase)
                    PH_KEY: begin
                        if (cnt < 5'd4) begin
                            // g = SubWord(RotWord(w3)) ^ Rcon, assembled MSB first
                            g <= {g[23:0], sbox_out ^ ((cnt == 5'd0) ? rcon_r : 8'h00)};
                        end else begin
                            // in-place round-key update: new wj = old wj ^ new w(j-1)
                            case (cnt)
                                5'd4:  rk[127:96] <= rk[127:96] ^ g;
                                5'd5:  rk[95:64]  <= rk[95:64]  ^ rk[127:96];
                                5'd6:  rk[63:32]  <= rk[63:32]  ^ rk[95:64];
                                5'd7:  rk[31:0]   <= rk[31:0]   ^ rk[63:32];
                                default: ;
                            endcase
                        end
                        if (cnt == 5'd7) begin
                            cnt    <= 5'd0;
                            rcon_r <= xtime(rcon_r);
                            phase  <= PH_SR;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end

                    PH_SR: begin
                        state <= state_sr;
                        cnt   <= 5'd0;
                        phase <= PH_SUB;
                    end

                    PH_SUB: begin
                        // SubBytes via rotation (handled by rot8_en above):
                        // 16 x 8-bit rotations = identity order
                        if (cnt == 5'd15) begin
                            cnt   <= 5'd0;
                            phase <= (round == 4'd10) ? PH_ARK : PH_MC;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end

                    PH_MC: begin
                        // MixColumns one column per cycle (state already ShiftRows'd);
                        // 4 x 32-bit rotations = identity order
                        state <= {state[95:0], mc_col};
                        if (cnt == 5'd3) begin
                            cnt   <= 5'd0;
                            phase <= PH_ARK;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end

                    PH_ARK: begin
                        state <= ark;   // AddRoundKey (state already ShiftRows'd)
                        if (round < 4'd10) begin
                            round <= round + 1'b1;
                            cnt   <= 5'd0;
                            phase <= PH_KEY;
                        end else begin
                            running <= 1'b0;
                            done_r  <= 1'b1;
                            phase   <= PH_IDLE;
                        end
                    end

                    default: phase <= PH_IDLE;
                endcase
            end
        end
    end

endmodule

`default_nettype none
