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
