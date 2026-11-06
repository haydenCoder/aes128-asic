`default_nettype none

module aes_sbox (
    input  wire [7:0] data_in,
    output wire [7:0] data_out
);
    // Compact Canright S-box (GF(2^8) inversion in composite field + affine),
    // ~150 gates instead of a 256-entry LUT. Verified against the FIPS-197
    // table for all 256 inputs (see test/tb_core.v NIST vectors).

    function [1:0] mul_gf2p2;
        input [1:0] g, d;
        reg a, b, c;
        begin
            a = g[1] & d[1];
            b = (g[0]^g[1]) & (d[0]^d[1]);
            c = g[0] & d[0];
            mul_gf2p2 = {a^b, c^b};
        end
    endfunction

    function [1:0] sq_gf2p2;
        input [1:0] g;
        sq_gf2p2 = {g[0], g[1]};
    endfunction

    function [1:0] scl_om2;   // scale by Omega^2 = N
        input [1:0] g;
        scl_om2 = {g[0], g[1]^g[0]};
    endfunction

    function [1:0] scl_om;    // scale by Omega = N^2
        input [1:0] g;
        scl_om = {g[1]^g[0], g[1]};
    endfunction

    function [3:0] mul_gf2p4;
        input [3:0] g, d;
        reg [1:0] a, b, c, e;
        begin
            a = mul_gf2p2(g[3:2], d[3:2]);
            b = mul_gf2p2(g[3:2]^g[1:0], d[3:2]^d[1:0]);
            c = mul_gf2p2(g[1:0], d[1:0]);
            e = scl_om2(b);
            mul_gf2p4 = {a^e, c^e};
        end
    endfunction

    function [3:0] sq_scl_gf2p4;
        input [3:0] g;
        reg [1:0] a, b;
        begin
            a = g[3:2]^g[1:0];
            b = sq_gf2p2(g[1:0]);
            sq_scl_gf2p4 = {sq_gf2p2(a), scl_om(b)};
        end
    endfunction

    function [3:0] inv_gf2p4;
        input [3:0] g;
        reg [1:0] a, b, c, d, p, q;
        begin
            a = g[3:2]^g[1:0];
            b = mul_gf2p2(g[3:2], g[1:0]);
            c = scl_om2(sq_gf2p2(a));
            d = sq_gf2p2(c^b);
            p = mul_gf2p2(d, g[1:0]);
            q = mul_gf2p2(d, g[3:2]);
            inv_gf2p4 = {p, q};
        end
    endfunction

    function [7:0] inv_gf2p8;
        input [7:0] g;
        reg [3:0] a, b, c, d, p, q;
        begin
            a = g[7:4]^g[3:0];
            b = mul_gf2p4(g[7:4], g[3:0]);
            c = sq_scl_gf2p4(a);
            d = inv_gf2p4(c^b);
            p = mul_gf2p4(d, g[3:0]);
            q = mul_gf2p4(d, g[7:4]);
            inv_gf2p8 = {p, q};
        end
    endfunction

    // bit-matrix multiply: output = XOR of m[i] for each set bit i of x
    // (m[0] is applied to x[7], matching the Canright reference tables)
    function [7:0] mvm;
        input [7:0] x;
        input [7:0] m0, m1, m2, m3, m4, m5, m6, m7;
        begin
            mvm = (x[7] ? m0 : 8'h00) ^ (x[6] ? m1 : 8'h00) ^ (x[5] ? m2 : 8'h00)
                ^ (x[4] ? m3 : 8'h00) ^ (x[3] ? m4 : 8'h00) ^ (x[2] ? m5 : 8'h00)
                ^ (x[1] ? m6 : 8'h00) ^ (x[0] ? m7 : 8'h00);
        end
    endfunction

    localparam [7:0] A2X_0 = 8'h98, A2X_1 = 8'hF3, A2X_2 = 8'hF2, A2X_3 = 8'h48,
                     A2X_4 = 8'h09, A2X_5 = 8'h81, A2X_6 = 8'hA9, A2X_7 = 8'hFF;
    localparam [7:0] X2S_0 = 8'h58, X2S_1 = 8'h2D, X2S_2 = 8'h9E, X2S_3 = 8'h0B,
                     X2S_4 = 8'hDC, X2S_5 = 8'h04, X2S_6 = 8'h03, X2S_7 = 8'h24;

    wire [7:0] basis_x = mvm(data_in, A2X_0, A2X_1, A2X_2, A2X_3, A2X_4, A2X_5, A2X_6, A2X_7);
    wire [7:0] inv     = inv_gf2p8(basis_x);

    assign data_out = mvm(inv, X2S_0, X2S_1, X2S_2, X2S_3, X2S_4, X2S_5, X2S_6, X2S_7) ^ 8'h63;

endmodule
