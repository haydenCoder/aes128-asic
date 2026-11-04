/*
 * Copyright (c) 2026 Chung Hon Ting
 * SPDX-License-Identifier: Apache-2.0
 *
 * AES-128 encryption core, byte-serial implementation for a Tiny Tapeout tile.
 *
 * Area-optimized: one shared compact (Canright) S-box time-multiplexed over
 * state bytes and key schedule, SubBytes via 128-bit rotation, in-place
 * round-key updates through a 32-bit g register. ~285 flops + ~1.5K gates.
 *
 * Interface (byte-serial load, MSB-first):
 *   key_we/key_byte   : shift one key byte into the round-key register
 *   data_we/data_byte : shift one plaintext byte into the state register
 *   start             : pulse -> state <= state ^ rk (round 0 AddRoundKey),
 *                       then 10 rounds of SubBytes/ShiftRows/MixColumns/AddRoundKey
 *   done              : 1-cycle pulse when the ciphertext is in data_out
 *   out_shift/out_byte: while asserted, shifts the result out MSB-first
 *
 * Latency: 1 + 10*(8 key + 16 sub + 1 mix) = 251 cycles per operation.
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
    localparam PH_KEY  = 3'd1;   // round-key update for current round (8 cycles)
    localparam PH_SUB  = 3'd2;   // SubBytes via rotation, one byte per cycle (16 cycles)
    localparam PH_MIX  = 3'd3;   // ShiftRows + MixColumns + AddRoundKey (1 cycle)

    reg [127:0] state;
    reg [127:0] rk;              // round key (key schedule sliding window)
    reg [31:0]  g;               // SubWord(RotWord(w3)) ^ Rcon, assembled over 4 cycles
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

    // Rcon for round 1..10
    function [7:0] rcon;
        input [3:0] r;
        case (r)
            4'd1:  rcon = 8'h01;
            4'd2:  rcon = 8'h02;
            4'd3:  rcon = 8'h04;
            4'd4:  rcon = 8'h08;
            4'd5:  rcon = 8'h10;
            4'd6:  rcon = 8'h20;
            4'd7:  rcon = 8'h40;
            4'd8:  rcon = 8'h80;
            4'd9:  rcon = 8'h1b;
            4'd10: rcon = 8'h36;
            default: rcon = 8'h00;
        endcase
    endfunction

    wire [127:0] state_sr;
    wire [127:0] state_mc;
    aes_shift_rows_correct u_sr (
        .state_in (state),
        .state_out(state_sr)
    );
    aes_mix_columns u_mc (
        .state_in (state_sr),
        .state_out(state_mc)
    );

    assign data_out = state;
    assign out_byte = state[127:120];
    assign done     = done_r;
    assign busy     = running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= 128'd0;
            rk      <= 128'd0;
            g       <= 32'd0;
            round   <= 4'd0;
            cnt     <= 5'd0;
            phase   <= PH_IDLE;
            running <= 1'b0;
            done_r  <= 1'b0;
        end else begin
            done_r <= 1'b0;

            // byte-serial load
            if (key_we)  rk    <= {rk[119:0], key_byte};
            if (data_we) state <= {state[119:0], data_byte};

            // output shift (result already latched in state)
            if (out_shift) state <= {state[119:0], 8'h00};

            if (start) begin
                state   <= state ^ rk;   // round 0 AddRoundKey (rk holds the key)
                round   <= 4'd1;
                cnt     <= 5'd0;
                phase   <= PH_KEY;
                running <= 1'b1;
                done_r  <= 1'b0;
            end else if (running) begin
                case (phase)
                    PH_KEY: begin
                        if (cnt < 5'd4) begin
                            // assemble g = SubWord(RotWord(w3)) ^ Rcon, MSB first
                            g <= {g[23:0], sbox_out ^ ((cnt == 5'd0) ? rcon(round) : 8'h00)};
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
                            cnt   <= 5'd0;
                            phase <= PH_SUB;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end

                    PH_SUB: begin
                        // SubBytes via rotation: 16 x 8-bit rotations = identity order
                        state <= {state[119:0], sbox_out};
                        if (cnt == 5'd15) begin
                            cnt   <= 5'd0;
                            phase <= PH_MIX;
                        end else begin
                            cnt <= cnt + 1'b1;
                        end
                    end

                    PH_MIX: begin
                        if (round < 4'd10) begin
                            state <= state_mc ^ rk;   // ShiftRows+MixColumns+AddRoundKey
                            round <= round + 1'b1;
                            cnt   <= 5'd0;
                            phase <= PH_KEY;
                        end else begin
                            state   <= state_sr ^ rk; // final round: no MixColumns
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
