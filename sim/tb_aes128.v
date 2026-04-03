`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_aes128.v — AES-128 encryption testbench
// Verifies against NIST FIPS-197 test vector:
//   Key:       000102030405060708090a0b0c0d0e0f
//   Plaintext: 00112233445566778899aabbccddeeff
//   Expected:  69c4e0d86a7b0430d8cdb78070b4c55a
//////////////////////////////////////////////////////////////////////////////

module tb_aes128;

    reg          clk;
    reg          rst;
    reg  [127:0] plaintext;
    reg  [127:0] key;
    reg          start;
    wire [127:0] ciphertext;
    wire         done;
    wire         busy;

    // DUT
    aes128_encrypt dut (
        .clk(clk),
        .rst(rst),
        .plaintext(plaintext),
        .key(key),
        .start(start),
        .ciphertext(ciphertext),
        .done(done),
        .busy(busy)
    );

    // Clock: 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    integer errors = 0;

    task check_aes;
        input [127:0] pt;
        input [127:0] k;
        input [127:0] expected_ct;
        begin
            @(posedge clk);
            plaintext = pt;
            key = k;
            start = 1;
            @(posedge clk);
            start = 0;

            // Wait for done
            wait(done);
            @(posedge clk);

            if (ciphertext !== expected_ct) begin
                $display("FAIL: Key=%h, PT=%h", k, pt);
                $display("  Expected: %h", expected_ct);
                $display("  Got:      %h", ciphertext);
                errors = errors + 1;
            end else begin
                $display("PASS: Key=%h, PT=%h -> CT=%h", k, pt, ciphertext);
            end
        end
    endtask

    initial begin
        $display("=== AES-128 Encryption Testbench ===");
        rst = 1;
        start = 0;
        plaintext = 128'h0;
        key = 128'h0;
        #100;
        rst = 0;
        #20;

        // NIST FIPS-197 Appendix B test vector
        check_aes(
            128'h00112233445566778899aabbccddeeff,  // plaintext
            128'h000102030405060708090a0b0c0d0e0f,  // key
            128'h69c4e0d86a7b0430d8cdb78070b4c55a   // expected ciphertext
        );

        // Additional test: all zeros
        check_aes(
            128'h00000000000000000000000000000000,
            128'h00000000000000000000000000000000,
            128'h66e94bd4ef8a2c3b884cfa59ca342b2e
        );

        // Test: all ones key
        check_aes(
            128'h00000000000000000000000000000000,
            128'hffffffffffffffffffffffffffffffff,
            128'ha1f6258c877d5fcd8964484538bfc92c
        );

        #100;
        if (errors == 0)
            $display("\n=== ALL AES TESTS PASSED ===");
        else
            $display("\n=== %0d AES TEST(S) FAILED ===", errors);

        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("TIMEOUT: Test did not complete in time");
        $finish;
    end

endmodule
