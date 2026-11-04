`default_nettype none
`timescale 1ns / 1ps

// Standalone core-level testbench: runs all 4 openssl-verified AES-128
// vectors through aes128_core in BOTH encrypt and decrypt directions.
// PASS/FAIL per vector; $fatal on any mismatch or missing done.

module tb_core ();
    reg clk;
    reg rst_n;
    reg start;
    reg decrypt;
    reg [127:0] key;
    reg [127:0] data_in;
    wire [127:0] data_out;
    wire done;

    integer errors;

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

    // One vector = one core operation (encrypt or decrypt).
    // Reset the core, pulse start for exactly one clock, wait for done,
    // then compare data_out against the expected 128-bit value.
    task run_vector;
        input [127:0]      vec_key;
        input [127:0]      vec_data;
        input              vec_decrypt;
        input [127:0]      expected;
        input [8*16-1:0]   vec_name;
        input [8*8-1:0]    vec_mode;
        integer cycles;
        begin
            key     = vec_key;
            data_in = vec_data;
            decrypt = vec_decrypt;
            start   = 1'b0;
            rst_n   = 1'b0;
            repeat (3) @(posedge clk);
            #1;
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            // Pulse start for exactly one clock edge
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
            // Wait for done (core takes ~10 clocks after start)
            cycles = 0;
            while (!done && cycles < 100) begin
                @(posedge clk);
                #1;  // let NBA updates settle before sampling
                cycles = cycles + 1;
            end
            if (!done) begin
                $display("FAIL: %0s %0s - done never asserted after %0d cycles", vec_name, vec_mode, cycles);
                errors = errors + 1;
                $fatal(1, "tb_core: done timeout");
            end else if (data_out !== expected) begin
                $display("FAIL: %0s %0s - data_out=%032h expected=%032h", vec_name, vec_mode, data_out, expected);
                errors = errors + 1;
                $fatal(1, "tb_core: data_out mismatch");
            end else begin
                $display("PASS: %0s %0s - data_out=%032h (%0d cycles)", vec_name, vec_mode, data_out, cycles);
            end
        end
    endtask

    initial begin
        errors  = 0;
        rst_n   = 1'b0;
        start   = 1'b0;
        decrypt = 1'b0;
        key     = 128'd0;
        data_in = 128'd0;
        repeat (3) @(posedge clk);

        // NIST-1: key 000102...0f, pt 00112233...eeff <-> ct 69c4e0d8...c55a
        run_vector(128'h000102030405060708090a0b0c0d0e0f, 128'h00112233445566778899aabbccddeeff, 1'b0, 128'h69c4e0d86a7b0430d8cdb78070b4c55a, "NIST-1", "encrypt");
        run_vector(128'h000102030405060708090a0b0c0d0e0f, 128'h69c4e0d86a7b0430d8cdb78070b4c55a, 1'b1, 128'h00112233445566778899aabbccddeeff, "NIST-1", "decrypt");
        // NIST-2: same key, pt 69c4e0d8... <-> ct 4f638c73...4f6a
        run_vector(128'h000102030405060708090a0b0c0d0e0f, 128'h69c4e0d86a7b0430d8cdb78070b4c55a, 1'b0, 128'h4f638c735f614301567824b1a21a4f6a, "NIST-2", "encrypt");
        run_vector(128'h000102030405060708090a0b0c0d0e0f, 128'h4f638c735f614301567824b1a21a4f6a, 1'b1, 128'h69c4e0d86a7b0430d8cdb78070b4c55a, "NIST-2", "decrypt");
        // NIST-3: zero key, zero pt <-> ct 66e94bd4...2b2e
        run_vector(128'h00000000000000000000000000000000, 128'h00000000000000000000000000000000, 1'b0, 128'h66e94bd4ef8a2c3b884cfa59ca342b2e, "NIST-3", "encrypt");
        run_vector(128'h00000000000000000000000000000000, 128'h66e94bd4ef8a2c3b884cfa59ca342b2e, 1'b1, 128'h00000000000000000000000000000000, "NIST-3", "decrypt");
        // NIST-4: zero key, ff*16 pt <-> ct 3f5b8cc9...664e
        run_vector(128'h00000000000000000000000000000000, 128'hffffffffffffffffffffffffffffffff, 1'b0, 128'h3f5b8cc9ea855a0afa7347d23e8d664e, "NIST-4", "encrypt");
        run_vector(128'h00000000000000000000000000000000, 128'h3f5b8cc9ea855a0afa7347d23e8d664e, 1'b1, 128'hffffffffffffffffffffffffffffffff, "NIST-4", "decrypt");

        if (errors == 0)
            $display("tb_core: ALL 8 VECTOR RUNS PASS (4 vectors x enc+dec)");
        else
            $display("tb_core: %0d ERRORS", errors);
        $finish;
    end

endmodule
