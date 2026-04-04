`timescale 1ns / 1ps
// Debug: trace valid pulse count through the full QRS pipeline
module tb_debug_pipeline;
    reg clk, rst;
    reg signed [15:0] ecg_in;
    reg ecg_valid;
    wire beat_detect;
    wire signed [15:0] filtered_ecg;
    wire filtered_valid;
    wire [15:0] peak_amplitude;

    qrs_detector dut (
        .clk(clk), .rst(rst),
        .ecg_in(ecg_in), .ecg_valid(ecg_valid),
        .beat_detect(beat_detect),
        .filtered_ecg(filtered_ecg), .filtered_valid(filtered_valid),
        .peak_amplitude(peak_amplitude)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Count valid pulses at each stage
    integer input_count, bp_count, deriv_count, sq_count, ma_count;
    integer sample_num, beat_count;

    always @(posedge clk) begin
        if (!rst) begin
            if (ecg_valid) input_count = input_count + 1;
            if (dut.bp_valid) bp_count = bp_count + 1;
            if (dut.deriv_valid) deriv_count = deriv_count + 1;
            if (dut.sq_valid) sq_count = sq_count + 1;
            if (dut.ma_valid) ma_count = ma_count + 1;
            if (beat_detect) begin
                beat_count = beat_count + 1;
                $display("  BEAT #%0d at sample %0d", beat_count, sample_num);
            end
        end
    end

    integer phase;

    initial begin
        $display("=== Pipeline Valid-Pulse Debug ===");
        rst = 1; ecg_in = 0; ecg_valid = 0;
        sample_num = 0; beat_count = 0;
        input_count = 0; bp_count = 0; deriv_count = 0;
        sq_count = 0; ma_count = 0;
        #100; rst = 0; #20;

        // Send 1000 samples with R-peaks every 500 samples (60 BPM at 500Hz)
        repeat(1000) begin
            phase = sample_num % 500;

            @(posedge clk);
            if (phase >= 198 && phase <= 202)
                ecg_in = 16'sd2000;  // R-peak
            else
                ecg_in = 16'sd0;     // Baseline

            ecg_valid = 1;
            @(posedge clk);
            ecg_valid = 0;
            repeat(10) @(posedge clk);
            sample_num = sample_num + 1;
        end

        repeat(100) @(posedge clk);

        $display("");
        $display("Valid pulse counts after %0d input samples:", sample_num);
        $display("  Input ecg_valid:    %0d", input_count);
        $display("  Bandpass dout_valid:%0d", bp_count);
        $display("  Derivative dout_valid: %0d", deriv_count);
        $display("  Squarer dout_valid: %0d", sq_count);
        $display("  Moving avg dout_valid: %0d", ma_count);
        $display("  Beats detected:     %0d (expected ~2)", beat_count);
        $finish;
    end
endmodule
