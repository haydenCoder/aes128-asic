`default_nettype none

module aes_shift_rows (
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);

    // ShiftRows transformation:
    // Row 0: no shift
    // Row 1: shift left by 1 byte (8 bits)
    // Row 2: shift left by 2 bytes (16 bits)
    // Row 3: shift left by 3 bytes (24 bits)
    //
    // State layout (column-major):
    // s0,0  s0,1  s0,2  s0,3
    // s1,0  s1,1  s1,2  s1,3
    // s2,0  s2,1  s2,2  s2,3
    // s3,0  s3,1  s3,2  s3,3
    //
    // In linear 128-bit: [s0,0, s1,0, s2,0, s3,0, s0,1, s1,1, s2,1, s3,1, ...]
    //
    // After ShiftRows:
    // Row 0: s0,0  s0,1  s0,2  s0,3
    // Row 1: s1,1  s1,2  s1,3  s1,0
    // Row 2: s2,2  s2,3  s2,0  s2,1
    // Row 3: s3,3  s3,0  s3,1  s3,2

    assign state_out = {
        state_in[7:0],      // s0,3 -> row 0, col 3
        state_in[39:32],    // s1,3 -> row 1, col 3
        state_in[71:64],    // s2,3 -> row 2, col 3
        state_in[103:96],   // s3,3 -> row 3, col 3

        state_in[103:96],   // s3,0 -> row 0, col 0 (wrap)
        state_in[7:0],      // s0,0 -> row 1, col 0
        state_in[39:32],    // s1,0 -> row 2, col 0
        state_in[71:64],    // s2,0 -> row 3, col 0

        state_in[39:32],    // s1,1 -> row 0, col 1
        state_in[71:64],    // s2,1 -> row 1, col 1
        state_in[103:96],   // s3,1 -> row 2, col 1
        state_in[7:0],      // s0,1 -> row 3, col 1

        state_in[71:64],    // s2,2 -> row 0, col 2
        state_in[103:96],   // s3,2 -> row 1, col 2
        state_in[7:0],      // s0,2 -> row 2, col 2
        state_in[39:32]     // s1,2 -> row 3, col 2
    };

    // Wait, let me redo this properly. The state is column-major:
    // Column 0: bytes 127:120, 95:88, 63:56, 31:24  (s0,0, s1,0, s2,0, s3,0)
    // Column 1: bytes 119:112, 87:80, 55:48, 23:16  (s0,1, s1,1, s2,1, s3,1)
    // Column 2: bytes 111:104, 79:72, 47:40, 15:8   (s0,2, s1,2, s2,2, s3,2)
    // Column 3: bytes 103:96, 71:64, 39:32, 7:0     (s0,3, s1,3, s2,3, s3,3)
    //
    // ShiftRows:
    // Row 0 (s0,*): no shift
    // Row 1 (s1,*): shift left 1 -> s1,1, s1,2, s1,3, s1,0
    // Row 2 (s2,*): shift left 2 -> s2,2, s2,3, s2,0, s2,1
    // Row 3 (s3,*): shift left 3 -> s3,3, s3,0, s3,1, s3,2

endmodule


`default_nettype none

module aes_shift_rows_correct (
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);

    // State is column-major: [col3, col2, col1, col0] where each col = [s0, s1, s2, s3]
    // col0 = state_in[127:96]  = [s0,0, s1,0, s2,0, s3,0]
    // col1 = state_in[95:64]   = [s0,1, s1,1, s2,1, s3,1]
    // col2 = state_in[63:32]   = [s0,2, s1,2, s2,2, s3,2]
    // col3 = state_in[31:0]    = [s0,3, s1,3, s2,3, s3,3]

    wire [7:0] s00 = state_in[127:120];
    wire [7:0] s10 = state_in[119:112];
    wire [7:0] s20 = state_in[111:104];
    wire [7:0] s30 = state_in[103:96];

    wire [7:0] s01 = state_in[95:88];
    wire [7:0] s11 = state_in[87:80];
    wire [7:0] s21 = state_in[79:72];
    wire [7:0] s31 = state_in[71:64];

    wire [7:0] s02 = state_in[63:56];
    wire [7:0] s12 = state_in[55:48];
    wire [7:0] s22 = state_in[47:40];
    wire [7:0] s32 = state_in[39:32];

    wire [7:0] s03 = state_in[31:24];
    wire [7:0] s13 = state_in[23:16];
    wire [7:0] s23 = state_in[15:8];
    wire [7:0] s33 = state_in[7:0];

    // After ShiftRows:
    // Row 0: s00, s01, s02, s03
    // Row 1: s11, s12, s13, s10
    // Row 2: s22, s23, s20, s21
    // Row 3: s33, s30, s31, s32
    //
    // Output column-major:
    // col0: s00, s11, s22, s33
    // col1: s01, s12, s23, s30
    // col2: s02, s13, s20, s31
    // col3: s03, s10, s21, s32

    assign state_out = {
        s00, s11, s22, s33,
        s01, s12, s23, s30,
        s02, s13, s20, s31,
        s03, s10, s21, s32
    };

endmodule


`default_nettype none

module aes_inv_shift_rows (
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);

    wire [7:0] s00 = state_in[127:120];
    wire [7:0] s10 = state_in[119:112];
    wire [7:0] s20 = state_in[111:104];
    wire [7:0] s30 = state_in[103:96];

    wire [7:0] s01 = state_in[95:88];
    wire [7:0] s11 = state_in[87:80];
    wire [7:0] s21 = state_in[79:72];
    wire [7:0] s31 = state_in[71:64];

    wire [7:0] s02 = state_in[63:56];
    wire [7:0] s12 = state_in[55:48];
    wire [7:0] s22 = state_in[47:40];
    wire [7:0] s32 = state_in[39:32];

    wire [7:0] s03 = state_in[31:24];
    wire [7:0] s13 = state_in[23:16];
    wire [7:0] s23 = state_in[15:8];
    wire [7:0] s33 = state_in[7:0];

    // Inverse ShiftRows:
    // Row 0: s00, s01, s02, s03 (no shift)
    // Row 1: s10, s11, s12, s13 (shift right 1 = left 3) -> s13, s10, s11, s12
    // Row 2: s20, s21, s22, s23 (shift right 2 = left 2) -> s22, s23, s20, s21
    // Row 3: s30, s31, s32, s33 (shift right 3 = left 1) -> s31, s32, s33, s30
    //
    // Output column-major:
    // col0: s00, s13, s22, s31
    // col1: s01, s10, s23, s32
    // col2: s02, s11, s20, s33
    // col3: s03, s12, s21, s30

    assign state_out = {
        s00, s13, s22, s31,
        s01, s10, s23, s32,
        s02, s11, s20, s33,
        s03, s12, s21, s30
    };

endmodule
