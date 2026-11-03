`default_nettype none
`timescale 1ns / 1ps

module tb_core ();

    reg clk;
    reg rst_n;
    reg start;
    reg decrypt;
    reg [127:0] key;
    reg [127:0] data_in;
    wire [127:0] data_out;
    wire done;

    initial begin
        $dumpfile("tb_core.fst");
        $dumpvars(0, tb_core);
        #1;
    end

    aes128_core u_core (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .decrypt  (decrypt),
        .key      (key),
        .data_in  (data_in),
        .data_out (data_out),
        .done     (done)
    );

    // Clock: 100 MHz (10 ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // Test sequence
    initial begin
        rst_n = 0;
        start = 0;
        decrypt = 0;
        key = 128'h000102030405060708090a0b0c0d0e0f;
        data_in = 128'h00112233445566778899aabbccddeeff;

        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Pulse start
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for done
        repeat (20) begin
            @(posedge clk);
            $display("Cycle: round=%d, done=%b, data_out=%h", u_core.round, done, data_out);
            if (done) break;
        end

        if (done) begin
            $display("SUCCESS: done asserted, data_out=%h", data_out);
            $display("Expected: 69c4e0d86a7b0430d8cdb78070b4c55a");
        end else begin
            $display("FAIL: done never asserted");
        end

        $finish;
    end

endmodule