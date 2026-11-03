`default_nettype none

module aes_gf_mul2 (
    input  wire [7:0] a,
    output wire [7:0] out
);
    // Multiply by x (0x02) in GF(2^8) with irreducible polynomial x^8 + x^4 + x^3 + x + 1 (0x11b)
    assign out = (a[7]) ? ((a << 1) ^ 8'h1b) : (a << 1);
endmodule


`default_nettype none

module aes_gf_mul3 (
    input  wire [7:0] a,
    output wire [7:0] out
);
    // Multiply by x+1 (0x03) = mul2(a) ^ a
    wire [7:0] mul2_a;
    aes_gf_mul2 u_mul2 (.a(a), .out(mul2_a));
    assign out = mul2_a ^ a;
endmodule


`default_nettype none

module aes_gf_mul9 (
    input  wire [7:0] a,
    output wire [7:0] out
);
    wire [7:0] mul2_a, mul4_a, mul8_a;
    aes_gf_mul2 u1 (.a(a),       .out(mul2_a));
    aes_gf_mul2 u2 (.a(mul2_a),  .out(mul4_a));
    aes_gf_mul2 u3 (.a(mul4_a),  .out(mul8_a));
    assign out = mul8_a ^ a;  // 9 = 8 + 1
endmodule


`default_nettype none

module aes_gf_mul11 (
    input  wire [7:0] a,
    output wire [7:0] out
);
    wire [7:0] mul2_a, mul4_a, mul8_a;
    aes_gf_mul2 u1 (.a(a),       .out(mul2_a));
    aes_gf_mul2 u2 (.a(mul2_a),  .out(mul4_a));
    aes_gf_mul2 u3 (.a(mul4_a),  .out(mul8_a));
    assign out = mul8_a ^ mul2_a ^ a;  // 11 = 8 + 2 + 1
endmodule


`default_nettype none

module aes_gf_mul13 (
    input  wire [7:0] a,
    output wire [7:0] out
);
    wire [7:0] mul2_a, mul4_a, mul8_a;
    aes_gf_mul2 u1 (.a(a),       .out(mul2_a));
    aes_gf_mul2 u2 (.a(mul2_a),  .out(mul4_a));
    aes_gf_mul2 u3 (.a(mul4_a),  .out(mul8_a));
    assign out = mul8_a ^ mul4_a ^ a;  // 13 = 8 + 4 + 1
endmodule


`default_nettype none

module aes_gf_mul14 (
    input  wire [7:0] a,
    output wire [7:0] out
);
    wire [7:0] mul2_a, mul4_a, mul8_a;
    aes_gf_mul2 u1 (.a(a),       .out(mul2_a));
    aes_gf_mul2 u2 (.a(mul2_a),  .out(mul4_a));
    aes_gf_mul2 u3 (.a(mul4_a),  .out(mul8_a));
    assign out = mul8_a ^ mul4_a ^ mul2_a;  // 14 = 8 + 4 + 2
endmodule


`default_nettype none

module aes_mix_column (
    input  wire [31:0] col_in,  // [s0, s1, s2, s3] - top byte is s0
    output wire [31:0] col_out
);

    wire [7:0] s0 = col_in[31:24];
    wire [7:0] s1 = col_in[23:16];
    wire [7:0] s2 = col_in[15:8];
    wire [7:0] s3 = col_in[7:0];

    wire [7:0] m2_s0, m2_s1, m2_s2, m2_s3;
    wire [7:0] m3_s0, m3_s1, m3_s2, m3_s3;

    aes_gf_mul2 u2_0 (.a(s0), .out(m2_s0));
    aes_gf_mul2 u2_1 (.a(s1), .out(m2_s1));
    aes_gf_mul2 u2_2 (.a(s2), .out(m2_s2));
    aes_gf_mul2 u2_3 (.a(s3), .out(m2_s3));

    aes_gf_mul3 u3_0 (.a(s0), .out(m3_s0));
    aes_gf_mul3 u3_1 (.a(s1), .out(m3_s1));
    aes_gf_mul3 u3_2 (.a(s2), .out(m3_s2));
    aes_gf_mul3 u3_3 (.a(s3), .out(m3_s3));

    // MixColumns matrix:
    // [2 3 1 1]   [s0]
    // [1 2 3 1] * [s1]
    // [1 1 2 3]   [s2]
    // [3 1 1 2]   [s3]

    assign col_out = {
        m2_s0 ^ m3_s1 ^ s2     ^ s3,      // 2*s0 + 3*s1 + 1*s2 + 1*s3
        s0      ^ m2_s1 ^ m3_s2 ^ s3,      // 1*s0 + 2*s1 + 3*s2 + 1*s3
        s0      ^ s1      ^ m2_s2 ^ m3_s3, // 1*s0 + 1*s1 + 2*s2 + 3*s3
        m3_s0 ^ s1      ^ s2      ^ m2_s3  // 3*s0 + 1*s1 + 1*s2 + 2*s3
    };

endmodule


`default_nettype none

module aes_inv_mix_column (
    input  wire [31:0] col_in,
    output wire [31:0] col_out
);

    wire [7:0] s0 = col_in[31:24];
    wire [7:0] s1 = col_in[23:16];
    wire [7:0] s2 = col_in[15:8];
    wire [7:0] s3 = col_in[7:0];

    wire [7:0] m9_s0, m9_s1, m9_s2, m9_s3;
    wire [7:0] m11_s0, m11_s1, m11_s2, m11_s3;
    wire [7:0] m13_s0, m13_s1, m13_s2, m13_s3;
    wire [7:0] m14_s0, m14_s1, m14_s2, m14_s3;

    aes_gf_mul9  u9_0  (.a(s0), .out(m9_s0));  aes_gf_mul9  u9_1  (.a(s1), .out(m9_s1));
    aes_gf_mul9  u9_2  (.a(s2), .out(m9_s2));  aes_gf_mul9  u9_3  (.a(s3), .out(m9_s3));
    aes_gf_mul11 u11_0 (.a(s0), .out(m11_s0)); aes_gf_mul11 u11_1 (.a(s1), .out(m11_s1));
    aes_gf_mul11 u11_2 (.a(s2), .out(m11_s2)); aes_gf_mul11 u11_3 (.a(s3), .out(m11_s3));
    aes_gf_mul13 u13_0 (.a(s0), .out(m13_s0)); aes_gf_mul13 u13_1 (.a(s1), .out(m13_s1));
    aes_gf_mul13 u13_2 (.a(s2), .out(m13_s2)); aes_gf_mul13 u13_3 (.a(s3), .out(m13_s3));
    aes_gf_mul14 u14_0 (.a(s0), .out(m14_s0)); aes_gf_mul14 u14_1 (.a(s1), .out(m14_s1));
    aes_gf_mul14 u14_2 (.a(s2), .out(m14_s2)); aes_gf_mul14 u14_3 (.a(s3), .out(m14_s3));

    // Inverse MixColumns matrix:
    // [14 11 13 9]   [s0]
    // [9  14 11 13] * [s1]
    // [13 9  14 11]   [s2]
    // [11 13 9  14]   [s3]

    assign col_out = {
        m14_s0 ^ m11_s1 ^ m13_s2 ^ m9_s3,
        m9_s0  ^ m14_s1 ^ m11_s2 ^ m13_s3,
        m13_s0 ^ m9_s1  ^ m14_s2 ^ m11_s3,
        m11_s0 ^ m13_s1 ^ m9_s2  ^ m14_s3
    };

endmodule


`default_nettype none

module aes_mix_columns (
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);

    wire [31:0] col0_in = state_in[127:96];
    wire [31:0] col1_in = state_in[95:64];
    wire [31:0] col2_in = state_in[63:32];
    wire [31:0] col3_in = state_in[31:0];

    wire [31:0] col0_out, col1_out, col2_out, col3_out;

    aes_mix_column u0 (.col_in(col0_in), .col_out(col0_out));
    aes_mix_column u1 (.col_in(col1_in), .col_out(col1_out));
    aes_mix_column u2 (.col_in(col2_in), .col_out(col2_out));
    aes_mix_column u3 (.col_in(col3_in), .col_out(col3_out));

    assign state_out = {col0_out, col1_out, col2_out, col3_out};

endmodule


`default_nettype none

module aes_inv_mix_columns (
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);

    wire [31:0] col0_in = state_in[127:96];
    wire [31:0] col1_in = state_in[95:64];
    wire [31:0] col2_in = state_in[63:32];
    wire [31:0] col3_in = state_in[31:0];

    wire [31:0] col0_out, col1_out, col2_out, col3_out;

    aes_inv_mix_column u0 (.col_in(col0_in), .col_out(col0_out));
    aes_inv_mix_column u1 (.col_in(col1_in), .col_out(col1_out));
    aes_inv_mix_column u2 (.col_in(col2_in), .col_out(col2_out));
    aes_inv_mix_column u3 (.col_in(col3_in), .col_out(col3_out));

    assign state_out = {col0_out, col1_out, col2_out, col3_out};

endmodule
