/*
 * Copyright (c) 2026 Chung Hon Ting
 * SPDX-License-Identifier: Apache-2.0
 * 
 * AES-128 Wrapper with Synchronous Clear
 * Uses sequential core (~12 cycles latency) for reliability
 * Synchronous clear between operations for test compatibility
 */

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

    localparam IDLE        = 3'd0;
    localparam LOAD_KEY    = 3'd1;
    localparam LOAD_DATA   = 3'd2;
    localparam PROCESS     = 3'd3;
    localparam OUTPUT      = 3'd4;

    reg [2:0]  state, next_state;
    reg [4:0]  byte_cnt;
    reg [127:0] key_reg;
    reg [127:0] data_reg;
    reg [127:0] result_reg;
    reg [3:0]  out_byte_cnt;
    reg        decrypt_reg_d;
    reg        key_loaded;
    reg        data_loaded;

    wire        aes_done;
    wire [127:0] aes_data_out;
    reg         aes_start_reg;

    // Sequential AES core (12 cycles latency, proven correct)
    aes128_core u_aes_core (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (aes_start_reg),
        .decrypt  (decrypt_reg_d),
        .key      (key_reg),
        .data_in  (data_reg),
        .data_out (aes_data_out),
        .done     (aes_done)
    );

    // Synchronous clear pulse (1 cycle) - clears all registers between operations
    reg clear_pulse;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clear_pulse <= 1'b0;
        end else begin
            clear_pulse <= (state == IDLE && uio_in[0] && key_loaded && data_loaded);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            byte_cnt        <= 5'd0;
            key_reg         <= 128'd0;
            data_reg        <= 128'd0;
            result_reg      <= 128'd0;
            out_byte_cnt    <= 4'd0;
            decrypt_reg_d   <= 1'b0;
            aes_start_reg   <= 1'b0;
            key_loaded      <= 1'b0;
            data_loaded     <= 1'b0;
        end else begin
            state <= next_state;

            // Synchronous clear between operations
            if (clear_pulse) begin
                key_reg     <= 128'd0;
                data_reg    <= 128'd0;
                result_reg  <= 128'd0;
                key_loaded  <= 1'b0;
                data_loaded <= 1'b0;
            end

            // Load key/data ONLY in explicit load states
            case (state)
                LOAD_KEY: begin
                    key_reg      <= {key_reg[119:0], ui_in};
                    byte_cnt     <= byte_cnt + 1'b1;
                    if (byte_cnt == 5'd15) key_loaded <= 1'b1;
                end

                LOAD_DATA: begin
                    data_reg     <= {data_reg[119:0], ui_in};
                    byte_cnt     <= byte_cnt + 1'b1;
                    if (byte_cnt == 5'd15) data_loaded <= 1'b1;
                end

                default: begin
                    byte_cnt <= 5'd0;
                end
            endcase

            // Reset byte_cnt when entering LOAD_DATA
            if (state == LOAD_KEY && next_state == LOAD_DATA) begin
                byte_cnt <= 5'd0;
            end

            // Pulse aes_start_reg for exactly one cycle when entering PROCESS
            aes_start_reg <= (next_state == PROCESS && state != PROCESS);

            case (state)
                IDLE: begin
                    out_byte_cnt    <= 4'd0;
                    if (uio_in[0] && !key_loaded) begin
                        decrypt_reg_d <= uio_in[1];
                    end
                end

                PROCESS: begin
                    if (aes_done) begin
                        result_reg    <= aes_data_out;
                        out_byte_cnt  <= 4'd0;
                    end
                end

                OUTPUT: begin
                    out_byte_cnt <= out_byte_cnt + 1'b1;
                    result_reg   <= {result_reg[119:0], 8'd0};
                end
                default: begin
                    // hold current values
                end
            endcase
        end
    end

    always @* begin
        next_state = state;
        case (state)
            IDLE: begin
                if (uio_in[0]) begin
                    if (!key_loaded) next_state = LOAD_KEY;
                    else if (!data_loaded) next_state = LOAD_DATA;
                    else next_state = PROCESS;
                end
            end
            LOAD_KEY: begin
                if (key_loaded) next_state = LOAD_DATA;
            end
            LOAD_DATA: begin
                if (data_loaded) next_state = PROCESS;
            end
            PROCESS: begin
                if (aes_done) next_state = OUTPUT;
            end
            OUTPUT: begin
                if (out_byte_cnt == 4'd15) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // MSB-first output: first byte out is result_reg[127:120]
    assign uo_out = (state == OUTPUT) ? result_reg[127:120] : 8'd0;

    assign uio_out = {
        (state == OUTPUT),                     // uio_out[7]: data_valid
        (state == PROCESS || state == OUTPUT), // uio_out[6]: busy
        5'd0,                                  // uio_out[5:1]: unused
        1'b0                                   // uio_out[0]: error
    };

    assign uio_oe = 8'b11000001;

    wire _unused = &{ena, uio_in[7:2], 1'b0};

endmodule
