`default_nettype none
`timescale 1ns / 1ps

// Standalone core-level testbench for the byte-serial aes128_core:
// runs all 4 openssl-verified AES-128 encryption vectors.
// Byte-serial load: 16 key bytes, 16 data bytes (MSB first), pulse start.

module tb_core ();
    reg clk;
    reg rst_n;
    reg start;
    reg key_we;
    reg data_we;
    reg out_shift;
    reg [7:0] key_byte;
    reg [7:0] data_byte;
    wire [7:0]   out_byte;
    wire [127:0] data_out;
    wire done;
    wire busy;

    integer errors;
    integer i;

    initial begin
        $dumpfile("tb_core.fst");
        $dumpvars(0, tb_core);
        #1;
    end

    aes128_core u_core (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .key_we   (key_we),
        .key_byte (key_byte),
        .data_we  (data_we),
        .data_byte(data_byte),
        .out_shift(out_shift),
        .out_byte (out_byte),
        .data_out (data_out),
        .done     (done),
        .busy     (busy)
    );

    // Clock: 100 MHz (10 ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    task run_enc;
        input [127:0]      vec_key;
        input [127:0]      vec_data;
        input [127:0]      expected;
        input [8*16-1:0]   vec_name;
        integer cycles;
        begin
            rst_n = 1'b0; start = 1'b0; key_we = 1'b0; data_we = 1'b0; out_shift = 1'b0;
            key_byte = 8'd0; data_byte = 8'd0;
            repeat (3) @(posedge clk);
            #1;
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            for (i = 0; i < 16; i = i + 1) begin
                key_byte = vec_key[127 - 8*i -: 8];
                key_we   = 1'b1;
                @(posedge clk);
                #1;
            end
            key_we = 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                data_byte = vec_data[127 - 8*i -: 8];
                data_we   = 1'b1;
                @(posedge clk);
                #1;
            end
            data_we = 1'b0;
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
            cycles = 0;
            while (!done && cycles < 2000) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            if (!done) begin
                $display("FAIL: %0s - done never asserted after %0d cycles", vec_name, cycles);
                errors = errors + 1;
                $fatal(1, "tb_core: done timeout");
            end else if (data_out !== expected) begin
                $display("FAIL: %0s - data_out=%032h expected=%032h", vec_name, data_out, expected);
                errors = errors + 1;
                $fatal(1, "tb_core: data_out mismatch");
            end else begin
                $display("PASS: %0s - data_out=%032h (%0d cycles)", vec_name, data_out, cycles);
            end
        end
    endtask

    initial begin
        errors  = 0;
        rst_n   = 1'b0;
        start   = 1'b0;
        key_we  = 1'b0;
        data_we = 1'b0;
        out_shift = 1'b0;
        key_byte  = 8'd0;
        data_byte = 8'd0;
        repeat (3) @(posedge clk);

        // NIST-1: key 000102...0f, pt 00112233...eeff -> ct 69c4e0d8...c55a
        run_enc(128'h000102030405060708090a0b0c0d0e0f, 128'h00112233445566778899aabbccddeeff, 128'h69c4e0d86a7b0430d8cdb78070b4c55a, "NIST-1");
        // NIST-2: same key, pt 69c4e0d8... -> ct 4f638c73...4f6a
        run_enc(128'h000102030405060708090a0b0c0d0e0f, 128'h69c4e0d86a7b0430d8cdb78070b4c55a, 128'h4f638c735f614301567824b1a21a4f6a, "NIST-2");
        // NIST-3: zero key, zero pt -> ct 66e94bd4...2b2e
        run_enc(128'h00000000000000000000000000000000, 128'h00000000000000000000000000000000, 128'h66e94bd4ef8a2c3b884cfa59ca342b2e, "NIST-3");
        // NIST-4: zero key, ff*16 pt -> ct 3f5b8cc9...664e
        run_enc(128'h00000000000000000000000000000000, 128'hffffffffffffffffffffffffffffffff, 128'h3f5b8cc9ea855a0afa7347d23e8d664e, "NIST-4");

        if (errors == 0)
            $display("tb_core: ALL 4 NIST VECTOR RUNS PASS");
        else
            $display("tb_core: %0d ERRORS", errors);
        $finish;
    end

endmodule
