`default_nettype none

module aes_round (
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    output wire [127:0] state_out
);

    wire [127:0] after_sbox;
    wire [127:0] after_shiftrows;
    wire [127:0] after_mixcolumns;

    aes_sbox_16 u_sbox (
        .data_in(state_in),
        .data_out(after_sbox)
    );

    aes_shift_rows_correct u_shiftrows (
        .state_in(after_sbox),
        .state_out(after_shiftrows)
    );

    aes_mix_columns u_mixcolumns (
        .state_in(after_shiftrows),
        .state_out(after_mixcolumns)
    );

    assign state_out = after_mixcolumns ^ round_key;

endmodule


`default_nettype none

module aes_final_round (
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    output wire [127:0] state_out
);

    wire [127:0] after_sbox;
    wire [127:0] after_shiftrows;

    aes_sbox_16 u_sbox (
        .data_in(state_in),
        .data_out(after_sbox)
    );

    aes_shift_rows_correct u_shiftrows (
        .state_in(after_sbox),
        .state_out(after_shiftrows)
    );

    assign state_out = after_shiftrows ^ round_key;

endmodule


`default_nettype none

module aes_inv_round (
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    output wire [127:0] state_out
);

    // FIPS-197 InvCipher round: InvShiftRows -> InvSubBytes -> AddRoundKey -> InvMixColumns
    wire [127:0] after_inv_shiftrows;
    wire [127:0] after_inv_sbox;
    wire [127:0] after_addkey;

    aes_inv_shift_rows u_inv_shiftrows (
        .state_in(state_in),
        .state_out(after_inv_shiftrows)
    );

    aes_inv_sbox_16 u_inv_sbox (
        .data_in(after_inv_shiftrows),
        .data_out(after_inv_sbox)
    );

    assign after_addkey = after_inv_sbox ^ round_key;

    aes_inv_mix_columns u_inv_mixcolumns (
        .state_in(after_addkey),
        .state_out(state_out)
    );

endmodule


`default_nettype none

module aes_inv_final_round (
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    output wire [127:0] state_out
);

    // FIPS-197 final inverse round: InvShiftRows -> InvSubBytes -> AddRoundKey (no InvMixColumns)
    wire [127:0] after_inv_shiftrows;
    wire [127:0] after_inv_sbox;

    aes_inv_shift_rows u_inv_shiftrows (
        .state_in(state_in),
        .state_out(after_inv_shiftrows)
    );

    aes_inv_sbox_16 u_inv_sbox (
        .data_in(after_inv_shiftrows),
        .data_out(after_inv_sbox)
    );

    assign state_out = after_inv_sbox ^ round_key;

endmodule


`default_nettype none

module aes128_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         decrypt,
    input  wire [127:0] key,
    input  wire [127:0] data_in,
    output reg  [127:0] data_out,
    output reg          done
);

    wire [127:0] rk0, rk1, rk2, rk3, rk4, rk5, rk6, rk7, rk8, rk9, rk10;
    aes_key_expansion_comb u_key_exp (
        .cipher_key(key),
        .rk0(rk0), .rk1(rk1), .rk2(rk2), .rk3(rk3), .rk4(rk4),
        .rk5(rk5), .rk6(rk6), .rk7(rk7), .rk8(rk8), .rk9(rk9), .rk10(rk10)
    );

    reg [3:0]  round;
    reg [127:0] state;
    reg         running;

    wire [127:0] round_key_enc;
    wire [127:0] round_key_dec;

    assign round_key_enc = (round == 4'd1)  ? rk1  :
                           (round == 4'd2)  ? rk2  :
                           (round == 4'd3)  ? rk3  :
                           (round == 4'd4)  ? rk4  :
                           (round == 4'd5)  ? rk5  :
                           (round == 4'd6)  ? rk6  :
                           (round == 4'd7)  ? rk7  :
                           (round == 4'd8)  ? rk8  :
                           (round == 4'd9)  ? rk9  :
                           (round == 4'd10) ? rk10 : 128'd0;

    assign round_key_dec = (round == 4'd10) ? rk10 :
                           (round == 4'd9)  ? rk9  :
                           (round == 4'd8)  ? rk8  :
                           (round == 4'd7)  ? rk7  :
                           (round == 4'd6)  ? rk6  :
                           (round == 4'd5)  ? rk5  :
                           (round == 4'd4)  ? rk4  :
                           (round == 4'd3)  ? rk3  :
                           (round == 4'd2)  ? rk2  :
                           (round == 4'd1)  ? rk1  :
                           (round == 4'd0)  ? rk0  : 128'd0;

    wire [127:0] enc_round_out;
    aes_round u_enc_round (
        .state_in(state),
        .round_key(round_key_enc),
        .state_out(enc_round_out)
    );

    wire [127:0] enc_final_out;
    aes_final_round u_enc_final (
        .state_in(state),
        .round_key(rk10),
        .state_out(enc_final_out)
    );

    wire [127:0] dec_round_out;
    aes_inv_round u_dec_round (
        .state_in(state),
        .round_key(round_key_dec),
        .state_out(dec_round_out)
    );

    wire [127:0] dec_final_out;
    aes_inv_final_round u_dec_final (
        .state_in(state),
        .round_key(rk0),
        .state_out(dec_final_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round   <= 4'd0;
            state   <= 128'd0;
            data_out <= 128'd0;
            done    <= 1'b0;
            running <= 1'b0;
        end else begin
            if (start) begin
                // Decryption starts with AddRoundKey(rk10); encryption with rk0
                state   <= data_in ^ (decrypt ? rk10 : rk0);
                round   <= decrypt ? 4'd9 : 4'd1;
                done    <= 1'b0;
                running <= 1'b1;
            end else if (running) begin
                if (!decrypt) begin
                    if (round < 4'd10) begin
                        state <= enc_round_out;
                        round <= round + 1'b1;
                    end else begin
                        data_out <= enc_final_out;
                        done    <= 1'b1;
                        running <= 1'b0;
                    end
                end else begin
                    if (round > 4'd0) begin
                        state <= dec_round_out;
                        round <= round - 1'b1;
                    end else begin
                        data_out <= dec_final_out;
                        done     <= 1'b1;
                        running  <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
