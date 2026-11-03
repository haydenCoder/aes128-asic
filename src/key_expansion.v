`default_nettype none

module aes_key_expansion (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [127:0] cipher_key,
    output reg  [127:0] rk0, rk1, rk2, rk3, rk4, rk5, rk6, rk7, rk8, rk9, rk10,
    output reg          done
);

    reg [3:0]  round;
    reg [31:0] temp;
    wire [7:0] sbox_out0, sbox_out1, sbox_out2, sbox_out3;
    wire [7:0] rcon [0:9];

    assign rcon[0] = 8'h01; assign rcon[1] = 8'h02; assign rcon[2] = 8'h04; assign rcon[3] = 8'h08;
    assign rcon[4] = 8'h10; assign rcon[5] = 8'h20; assign rcon[6] = 8'h40; assign rcon[7] = 8'h80;
    assign rcon[8] = 8'h1b; assign rcon[9] = 8'h36;

    // RotWord: [B0,B1,B2,B3] -> [B1,B2,B3,B0] where B0=temp[31:24], B1=temp[23:16], B2=temp[15:8], B3=temp[7:0]
    // SubWord applies S-box to each byte of rotated word
    aes_sbox s0 (.data_in(temp[23:16]), .data_out(sbox_out0));  // sbox(B1)
    aes_sbox s1 (.data_in(temp[15:8]),  .data_out(sbox_out1));  // sbox(B2)
    aes_sbox s2 (.data_in(temp[7:0]),   .data_out(sbox_out2));  // sbox(B3)
    aes_sbox s3 (.data_in(temp[31:24]), .data_out(sbox_out3));  // sbox(B0)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round <= 4'd0;
            done  <= 1'b0;
            temp  <= 32'd0;
            rk0 <= 128'd0; rk1 <= 128'd0; rk2 <= 128'd0; rk3 <= 128'd0;
            rk4 <= 128'd0; rk5 <= 128'd0; rk6 <= 128'd0; rk7 <= 128'd0;
            rk8 <= 128'd0; rk9 <= 128'd0; rk10 <= 128'd0;
        end else begin
            if (start) begin
                rk0 <= cipher_key;
                round <= 4'd1;
                done  <= 1'b0;
            end else if (round <= 4'd10) begin
                case (round)
                    4'd1:  temp = rk0[31:0];
                    4'd2:  temp = rk1[31:0];
                    4'd3:  temp = rk2[31:0];
                    4'd4:  temp = rk3[31:0];
                    4'd5:  temp = rk4[31:0];
                    4'd6:  temp = rk5[31:0];
                    4'd7:  temp = rk6[31:0];
                    4'd8:  temp = rk7[31:0];
                    4'd9:  temp = rk8[31:0];
                    4'd10: temp = rk9[31:0];
                endcase

                // g = SubWord(RotWord(temp)) = {sbox(B1), sbox(B2), sbox(B3), sbox(B0)}
                temp = {sbox_out0, sbox_out1, sbox_out2, sbox_out3};
                temp[31:24] = temp[31:24] ^ rcon[round-1];

                case (round)
                    4'd1: begin
                        rk1[127:96] = rk0[127:96] ^ temp;
                        rk1[95:64]  = rk0[95:64]  ^ rk1[127:96];
                        rk1[63:32]  = rk0[63:32]  ^ rk1[95:64];
                        rk1[31:0]   = rk0[31:0]   ^ rk1[63:32];
                    end
                    4'd2: begin
                        rk2[127:96] = rk1[127:96] ^ temp;
                        rk2[95:64]  = rk1[95:64]  ^ rk2[127:96];
                        rk2[63:32]  = rk1[63:32]  ^ rk2[95:64];
                        rk2[31:0]   = rk1[31:0]   ^ rk2[63:32];
                    end
                    4'd3: begin
                        rk3[127:96] = rk2[127:96] ^ temp;
                        rk3[95:64]  = rk2[95:64]  ^ rk3[127:96];
                        rk3[63:32]  = rk2[63:32]  ^ rk3[95:64];
                        rk3[31:0]   = rk2[31:0]   ^ rk3[63:32];
                    end
                    4'd4: begin
                        rk4[127:96] = rk3[127:96] ^ temp;
                        rk4[95:64]  = rk3[95:64]  ^ rk4[127:96];
                        rk4[63:32]  = rk3[63:32]  ^ rk4[95:64];
                        rk4[31:0]   = rk3[31:0]   ^ rk4[63:32];
                    end
                    4'd5: begin
                        rk5[127:96] = rk4[127:96] ^ temp;
                        rk5[95:64]  = rk4[95:64]  ^ rk5[127:96];
                        rk5[63:32]  = rk4[63:32]  ^ rk5[95:64];
                        rk5[31:0]   = rk4[31:0]   ^ rk5[63:32];
                    end
                    4'd6: begin
                        rk6[127:96] = rk5[127:96] ^ temp;
                        rk6[95:64]  = rk5[95:64]  ^ rk6[127:96];
                        rk6[63:32]  = rk5[63:32]  ^ rk6[95:64];
                        rk6[31:0]   = rk5[31:0]   ^ rk6[63:32];
                    end
                    4'd7: begin
                        rk7[127:96] = rk6[127:96] ^ temp;
                        rk7[95:64]  = rk6[95:64]  ^ rk7[127:96];
                        rk7[63:32]  = rk6[63:32]  ^ rk7[95:64];
                        rk7[31:0]   = rk6[31:0]   ^ rk7[63:32];
                    end
                    4'd8: begin
                        rk8[127:96] = rk7[127:96] ^ temp;
                        rk8[95:64]  = rk7[95:64]  ^ rk8[127:96];
                        rk8[63:32]  = rk7[63:32]  ^ rk8[95:64];
                        rk8[31:0]   = rk7[31:0]   ^ rk8[63:32];
                    end
                    4'd9: begin
                        rk9[127:96] = rk8[127:96] ^ temp;
                        rk9[95:64]  = rk8[95:64]  ^ rk9[127:96];
                        rk9[63:32]  = rk8[63:32]  ^ rk9[95:64];
                        rk9[31:0]   = rk8[31:0]   ^ rk9[63:32];
                    end
                    4'd10: begin
                        rk10[127:96] = rk9[127:96] ^ temp;
                        rk10[95:64]  = rk9[95:64]  ^ rk10[127:96];
                        rk10[63:32]  = rk9[63:32]  ^ rk10[95:64];
                        rk10[31:0]   = rk9[31:0]   ^ rk10[63:32];
                    end
                endcase

                if (round == 4'd10) begin
                    done <= 1'b1;
                end
                round <= round + 1'b1;
            end
        end
    end

endmodule


`default_nettype none

module aes_key_expansion_comb (
    input  wire [127:0] cipher_key,
    output wire [127:0] rk0, rk1, rk2, rk3, rk4, rk5, rk6, rk7, rk8, rk9, rk10
);

    wire [31:0] w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11;
    wire [31:0] w12, w13, w14, w15, w16, w17, w18, w19, w20, w21, w22, w23;
    wire [31:0] w24, w25, w26, w27, w28, w29, w30, w31, w32, w33, w34, w35;
    wire [31:0] w36, w37, w38, w39, w40, w41, w42, w43;

    wire [7:0] rcon [0:9];
    assign rcon[0] = 8'h01; assign rcon[1] = 8'h02; assign rcon[2] = 8'h04; assign rcon[3] = 8'h08;
    assign rcon[4] = 8'h10; assign rcon[5] = 8'h20; assign rcon[6] = 8'h40; assign rcon[7] = 8'h80;
    assign rcon[8] = 8'h1b; assign rcon[9] = 8'h36;

    assign w0  = cipher_key[127:96];
    assign w1  = cipher_key[95:64];
    assign w2  = cipher_key[63:32];
    assign w3  = cipher_key[31:0];

    // Round 1: RotWord(w3) = [w3[23:16], w3[15:8], w3[7:0], w3[31:24]]
    // SubWord applies S-box to each byte
    wire [7:0] r1_s0, r1_s1, r1_s2, r1_s3;
    aes_sbox r1_sb0 (.data_in(w3[23:16]), .data_out(r1_s0));  // sbox(B1)
    aes_sbox r1_sb1 (.data_in(w3[15:8]),  .data_out(r1_s1));  // sbox(B2)
    aes_sbox r1_sb2 (.data_in(w3[7:0]),   .data_out(r1_s2));  // sbox(B3)
    aes_sbox r1_sb3 (.data_in(w3[31:24]), .data_out(r1_s3));  // sbox(B0)
    wire [31:0] r1_g = {r1_s0, r1_s1, r1_s2, r1_s3} ^ {rcon[0], 24'h000000};
    assign w4  = w0 ^ r1_g;
    assign w5  = w1 ^ w4;
    assign w6  = w2 ^ w5;
    assign w7  = w3 ^ w6;

    // Round 2
    wire [7:0] r2_s0, r2_s1, r2_s2, r2_s3;
    aes_sbox r2_sb0 (.data_in(w7[23:16]), .data_out(r2_s0));
    aes_sbox r2_sb1 (.data_in(w7[15:8]),  .data_out(r2_s1));
    aes_sbox r2_sb2 (.data_in(w7[7:0]),   .data_out(r2_s2));
    aes_sbox r2_sb3 (.data_in(w7[31:24]), .data_out(r2_s3));
    wire [31:0] r2_g = {r2_s0, r2_s1, r2_s2, r2_s3} ^ {rcon[1], 24'h000000};
    assign w8  = w4 ^ r2_g;
    assign w9  = w5 ^ w8;
    assign w10 = w6 ^ w9;
    assign w11 = w7 ^ w10;

    // Round 3
    wire [7:0] r3_s0, r3_s1, r3_s2, r3_s3;
    aes_sbox r3_sb0 (.data_in(w11[23:16]), .data_out(r3_s0));
    aes_sbox r3_sb1 (.data_in(w11[15:8]),  .data_out(r3_s1));
    aes_sbox r3_sb2 (.data_in(w11[7:0]),   .data_out(r3_s2));
    aes_sbox r3_sb3 (.data_in(w11[31:24]), .data_out(r3_s3));
    wire [31:0] r3_g = {r3_s0, r3_s1, r3_s2, r3_s3} ^ {rcon[2], 24'h000000};
    assign w12 = w8 ^ r3_g;
    assign w13 = w9 ^ w12;
    assign w14 = w10 ^ w13;
    assign w15 = w11 ^ w14;

    // Round 4
    wire [7:0] r4_s0, r4_s1, r4_s2, r4_s3;
    aes_sbox r4_sb0 (.data_in(w15[23:16]), .data_out(r4_s0));
    aes_sbox r4_sb1 (.data_in(w15[15:8]),  .data_out(r4_s1));
    aes_sbox r4_sb2 (.data_in(w15[7:0]),   .data_out(r4_s2));
    aes_sbox r4_sb3 (.data_in(w15[31:24]), .data_out(r4_s3));
    wire [31:0] r4_g = {r4_s0, r4_s1, r4_s2, r4_s3} ^ {rcon[3], 24'h000000};
    assign w16 = w12 ^ r4_g;
    assign w17 = w13 ^ w16;
    assign w18 = w14 ^ w17;
    assign w19 = w15 ^ w18;

    // Round 5
    wire [7:0] r5_s0, r5_s1, r5_s2, r5_s3;
    aes_sbox r5_sb0 (.data_in(w19[23:16]), .data_out(r5_s0));
    aes_sbox r5_sb1 (.data_in(w19[15:8]),  .data_out(r5_s1));
    aes_sbox r5_sb2 (.data_in(w19[7:0]),   .data_out(r5_s2));
    aes_sbox r5_sb3 (.data_in(w19[31:24]), .data_out(r5_s3));
    wire [31:0] r5_g = {r5_s0, r5_s1, r5_s2, r5_s3} ^ {rcon[4], 24'h000000};
    assign w20 = w16 ^ r5_g;
    assign w21 = w17 ^ w20;
    assign w22 = w18 ^ w21;
    assign w23 = w19 ^ w22;

    // Round 6
    wire [7:0] r6_s0, r6_s1, r6_s2, r6_s3;
    aes_sbox r6_sb0 (.data_in(w23[23:16]), .data_out(r6_s0));
    aes_sbox r6_sb1 (.data_in(w23[15:8]),  .data_out(r6_s1));
    aes_sbox r6_sb2 (.data_in(w23[7:0]),   .data_out(r6_s2));
    aes_sbox r6_sb3 (.data_in(w23[31:24]), .data_out(r6_s3));
    wire [31:0] r6_g = {r6_s0, r6_s1, r6_s2, r6_s3} ^ {rcon[5], 24'h000000};
    assign w24 = w20 ^ r6_g;
    assign w25 = w21 ^ w24;
    assign w26 = w22 ^ w25;
    assign w27 = w23 ^ w26;

    // Round 7
    wire [7:0] r7_s0, r7_s1, r7_s2, r7_s3;
    aes_sbox r7_sb0 (.data_in(w27[23:16]), .data_out(r7_s0));
    aes_sbox r7_sb1 (.data_in(w27[15:8]),  .data_out(r7_s1));
    aes_sbox r7_sb2 (.data_in(w27[7:0]),   .data_out(r7_s2));
    aes_sbox r7_sb3 (.data_in(w27[31:24]), .data_out(r7_s3));
    wire [31:0] r7_g = {r7_s0, r7_s1, r7_s2, r7_s3} ^ {rcon[6], 24'h000000};
    assign w28 = w24 ^ r7_g;
    assign w29 = w25 ^ w28;
    assign w30 = w26 ^ w29;
    assign w31 = w27 ^ w30;

    // Round 8
    wire [7:0] r8_s0, r8_s1, r8_s2, r8_s3;
    aes_sbox r8_sb0 (.data_in(w31[23:16]), .data_out(r8_s0));
    aes_sbox r8_sb1 (.data_in(w31[15:8]),  .data_out(r8_s1));
    aes_sbox r8_sb2 (.data_in(w31[7:0]),   .data_out(r8_s2));
    aes_sbox r8_sb3 (.data_in(w31[31:24]), .data_out(r8_s3));
    wire [31:0] r8_g = {r8_s0, r8_s1, r8_s2, r8_s3} ^ {rcon[7], 24'h000000};
    assign w32 = w28 ^ r8_g;
    assign w33 = w29 ^ w32;
    assign w34 = w30 ^ w33;
    assign w35 = w31 ^ w34;

    // Round 9
    wire [7:0] r9_s0, r9_s1, r9_s2, r9_s3;
    aes_sbox r9_sb0 (.data_in(w35[23:16]), .data_out(r9_s0));
    aes_sbox r9_sb1 (.data_in(w35[15:8]),  .data_out(r9_s1));
    aes_sbox r9_sb2 (.data_in(w35[7:0]),   .data_out(r9_s2));
    aes_sbox r9_sb3 (.data_in(w35[31:24]), .data_out(r9_s3));
    wire [31:0] r9_g = {r9_s0, r9_s1, r9_s2, r9_s3} ^ {rcon[8], 24'h000000};
    assign w36 = w32 ^ r9_g;
    assign w37 = w33 ^ w36;
    assign w38 = w34 ^ w37;
    assign w39 = w35 ^ w38;

    // Round 10
    wire [7:0] r10_s0, r10_s1, r10_s2, r10_s3;
    aes_sbox r10_sb0 (.data_in(w39[23:16]), .data_out(r10_s0));
    aes_sbox r10_sb1 (.data_in(w39[15:8]),  .data_out(r10_s1));
    aes_sbox r10_sb2 (.data_in(w39[7:0]),   .data_out(r10_s2));
    aes_sbox r10_sb3 (.data_in(w39[31:24]), .data_out(r10_s3));
    wire [31:0] r10_g = {r10_s0, r10_s1, r10_s2, r10_s3} ^ {rcon[9], 24'h000000};
    assign w40 = w36 ^ r10_g;
    assign w41 = w37 ^ w40;
    assign w42 = w38 ^ w41;
    assign w43 = w39 ^ w42;

    assign rk0  = {w0,  w1,  w2,  w3};
    assign rk1  = {w4,  w5,  w6,  w7};
    assign rk2  = {w8,  w9,  w10, w11};
    assign rk3  = {w12, w13, w14, w15};
    assign rk4  = {w16, w17, w18, w19};
    assign rk5  = {w20, w21, w22, w23};
    assign rk6  = {w24, w25, w26, w27};
    assign rk7  = {w28, w29, w30, w31};
    assign rk8  = {w32, w33, w34, w35};
    assign rk9  = {w36, w37, w38, w39};
    assign rk10 = {w40, w41, w42, w43};

endmodule