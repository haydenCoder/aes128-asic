/* Copyright (c) 2026 Chung Hon Ting - SPDX-License-Identifier: Apache-2.0
 * Tiny Tapeout wrapper: streams key/data bytes into the core, MSB first. */

`default_nettype none

module tt_um_haydencoder_aes128 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    localparam IDLE      = 3'd0;
    localparam LOAD_KEY  = 3'd1;
    localparam LOAD_DATA = 3'd2;
    localparam PROCESS   = 3'd3;
    localparam OUTPUT    = 3'd4;

    reg [2:0] state, next_state;
    reg [4:0] byte_cnt;
    reg [3:0] out_byte_cnt;
    reg       start_r;

    wire        core_done;
    wire        core_busy;
    wire [7:0]  core_out_byte;
    wire [127:0] core_data_out;

    aes128_core u_aes_core (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start_r),
        .key_we    (state == LOAD_KEY),
        .key_byte  (ui_in),
        .data_we   (state == LOAD_DATA),
        .data_byte (ui_in),
        .out_shift (state == OUTPUT),
        .out_byte  (core_out_byte),
        .data_out  (core_data_out),
        .done      (core_done),
        .busy      (core_busy)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            byte_cnt     <= 5'd0;
            out_byte_cnt <= 4'd0;
            start_r      <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                LOAD_KEY:  byte_cnt <= byte_cnt + 1'b1;
                LOAD_DATA: byte_cnt <= byte_cnt + 1'b1;
                OUTPUT:    out_byte_cnt <= out_byte_cnt + 1'b1;
                default: begin
                    byte_cnt     <= 5'd0;
                    out_byte_cnt <= 4'd0;
                end
            endcase

            // reset byte_cnt on the LOAD_KEY -> LOAD_DATA transition
            if (state == LOAD_KEY && next_state == LOAD_DATA)
                byte_cnt <= 5'd0;

            // pulse core start exactly one cycle when entering PROCESS
            start_r <= (next_state == PROCESS && state != PROCESS);
        end
    end

    always @* begin
        next_state = state;
        case (state)
            IDLE:      if (uio_in[0])                  next_state = LOAD_KEY;
            LOAD_KEY:  if (byte_cnt == 5'd15)           next_state = LOAD_DATA;
            LOAD_DATA: if (byte_cnt == 5'd15)           next_state = PROCESS;
            PROCESS:   if (core_done)                  next_state = OUTPUT;
            OUTPUT:    if (out_byte_cnt == 4'd15)       next_state = IDLE;
            default:                                    next_state = IDLE;
        endcase
    end

    // MSB-first output straight from the core's shift register
    assign uo_out = (state == OUTPUT) ? core_out_byte : 8'd0;

    assign uio_out = {
        (state == OUTPUT),                      // uio_out[7]: data_valid
        (state == PROCESS || state == OUTPUT),  // uio_out[6]: busy
        5'd0,                                   // uio_out[5:1]: unused
        1'b0                                    // uio_out[0]: error
    };

    assign uio_oe = 8'b11000001;

    wire _unused = &{ena, uio_in[7:1], core_data_out, core_busy, 1'b0};

endmodule

`default_nettype none
