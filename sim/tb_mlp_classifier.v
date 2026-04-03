`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_mlp_classifier.v — MLP classifier testbench
// Tests the 10→8→2 neural network with known feature vectors.
//////////////////////////////////////////////////////////////////////////////

module tb_mlp_classifier;

    reg          clk;
    reg          rst;
    reg  [79:0]  feature_vector;
    reg          features_valid;
    wire         classification;
    wire         class_valid;
    wire         busy;

    // DUT
    mlp_classifier dut (
        .clk(clk),
        .rst(rst),
        .feature_vector(feature_vector),
        .features_valid(features_valid),
        .classification(classification),
        .class_valid(class_valid),
        .busy(busy)
    );

    // Clock: 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    integer test_num;
    integer errors;

    task run_classification;
        input [79:0] features;
        input        expected_class;
        input [8*32-1:0] test_name;
        begin
            test_num = test_num + 1;
            @(posedge clk);
            feature_vector = features;
            features_valid = 1;
            @(posedge clk);
            features_valid = 0;

            // Wait for result
            wait(class_valid);
            @(posedge clk);

            $display("Test %0d [%0s]: class=%0d (expected=%0d) %s",
                     test_num, test_name, classification, expected_class,
                     (classification == expected_class) ? "PASS" : "FAIL");

            if (classification !== expected_class)
                errors = errors + 1;

            // Wait for not busy
            wait(!busy);
            repeat(5) @(posedge clk);
        end
    endtask

    // Helper to pack 10 Q3.5 values into 80-bit vector
    // Feature[0] at MSB (bits 79:72), Feature[9] at LSB (bits 7:0)
    function [79:0] pack_features;
        input signed [7:0] f0, f1, f2, f3, f4, f5, f6, f7, f8, f9;
        begin
            pack_features = {f0, f1, f2, f3, f4, f5, f6, f7, f8, f9};
        end
    endfunction

    initial begin
        $display("=== MLP Classifier Testbench ===");
        $display("Architecture: 10 -> 8 (ReLU) -> 2");
        $display("Weights: placeholder values from weights.mem");
        $display("");

        rst = 1;
        features_valid = 0;
        feature_vector = 80'h0;
        test_num = 0;
        errors = 0;
        #200;
        rst = 0;
        #100;

        // Test 1: All zeros input
        // With placeholder weights, output depends on biases
        run_classification(
            pack_features(8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
                          8'h00, 8'h00, 8'h00, 8'h00, 8'h00),
            1'b0, "all_zeros"
        );

        // Test 2: Typical normal beat features (Q3.5 format)
        // RR~1.6s=51(0x33), prev_RR similar, mean similar, low var=6(0x06)
        // ratio~1.0=32(0x20), QRS_width=16(0x10), amp=48(0x30)
        run_classification(
            pack_features(8'h33, 8'h33, 8'h33, 8'h06, 8'h20,
                          8'h20, 8'h10, 8'h30, 8'h03, 8'h30),
            1'b0, "normal_beat"
        );

        // Test 3: Typical abnormal beat features
        // Short RR=20(0x14), long prev=64(0x40), different mean=40(0x28), high var=25(0x19)
        // ratio off=12(0x0C), wide QRS=38(0x26), high amp=80(0x50)
        run_classification(
            pack_features(8'h14, 8'h40, 8'h28, 8'h19, 8'h0C,
                          8'h10, 8'h26, 8'h50, 8'h14, 8'h40),
            1'b1, "abnormal_beat"
        );

        // Test 4: Another normal pattern
        run_classification(
            pack_features(8'h30, 8'h31, 8'h30, 8'h04, 8'h1F,
                          8'h20, 8'h0E, 8'h28, 8'h02, 8'h2E),
            1'b0, "normal_beat2"
        );

        // Test 5: Edge case - maximum positive values
        run_classification(
            pack_features(8'h7F, 8'h7F, 8'h7F, 8'h7F, 8'h7F,
                          8'h7F, 8'h7F, 8'h7F, 8'h7F, 8'h7F),
            1'b1, "max_positive"
        );

        #200;
        $display("");
        $display("=== Results: %0d/%0d tests passed ===",
                 test_num - errors, test_num);
        $display("NOTE: With placeholder weights, classification accuracy");
        $display("      will improve after training with real data.");
        $finish;
    end

    // Timeout
    initial begin
        #1_000_000;
        $display("TIMEOUT");
        $finish;
    end

    initial begin
        $dumpfile("tb_mlp_classifier.vcd");
        $dumpvars(0, tb_mlp_classifier);
    end

endmodule
