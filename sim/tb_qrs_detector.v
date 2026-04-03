`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// tb_qrs_detector.v — QRS detector testbench
// Generates a synthetic ECG-like signal and verifies R-peak detection.
//////////////////////////////////////////////////////////////////////////////

module tb_qrs_detector;

    reg          clk;
    reg          rst;
    reg  signed [15:0] ecg_in;
    reg          ecg_valid;
    wire         beat_detect;
    wire signed [15:0] filtered_ecg;
    wire         filtered_valid;
    wire [15:0]  peak_amplitude;

    // DUT
    qrs_detector dut (
        .clk(clk),
        .rst(rst),
        .ecg_in(ecg_in),
        .ecg_valid(ecg_valid),
        .beat_detect(beat_detect),
        .filtered_ecg(filtered_ecg),
        .filtered_valid(filtered_valid),
        .peak_amplitude(peak_amplitude)
    );

    // Clock: 100 MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // Synthetic ECG signal parameters
    // Simulate a simple ECG with R-peaks every 500 samples (1 second at 500Hz)
    // R-peak: sharp positive spike
    integer sample_count;
    integer beat_count;
    integer peak_positions [0:19]; // Store detected peak positions
    integer expected_peaks;

    // Generate a simplified synthetic ECG waveform
    // Models the bandpass-filtered ECG: sharp R-peak on flat baseline
    // This is what the 5-15 Hz bandpass produces from real ECG
    reg signed [15:0] ecg_signal;
    integer phase;

    task generate_ecg_sample;
        output signed [15:0] sample;
        begin
            phase = sample_count % 500; // 500 samples per beat at 500Hz = 60 BPM

            if (phase == 199)      sample = 16'sd500;
            else if (phase == 200) sample = 16'sd2000;  // R-peak
            else if (phase == 201) sample = 16'sd500;
            else                   sample = 16'sd0;     // Flat baseline
        end
    endtask

    // Monitor beat detections
    always @(posedge clk) begin
        if (beat_detect && !rst) begin
            $display("  Beat detected at sample %0d (time=%0.3f s), amplitude=%0d",
                     sample_count, sample_count / 500.0, peak_amplitude);
            if (beat_count < 20) begin
                peak_positions[beat_count] = sample_count;
            end
            beat_count = beat_count + 1;
        end
    end

    initial begin
        $display("=== QRS Detector Testbench ===");
        $display("Generating synthetic ECG: 60 BPM, 500 Hz sampling");
        $display("");

        rst = 1;
        ecg_in = 0;
        ecg_valid = 0;
        sample_count = 0;
        beat_count = 0;
        expected_peaks = 0;
        #200;
        rst = 0;
        #100;

        // Generate 10 seconds of ECG (5000 samples at 500 Hz)
        // Should produce ~10 beats at 60 BPM
        repeat(5000) begin
            generate_ecg_sample(ecg_signal);

            // Use #1 delay after posedge to avoid Verilog race condition
            // between blocking assignments and always @(posedge clk) blocks
            @(posedge clk);
            #1;
            ecg_in = ecg_signal;
            ecg_valid = 1;
            @(posedge clk);
            #1;
            ecg_valid = 0;

            // Wait between samples (compress 500 Hz timing for simulation)
            repeat(10) @(posedge clk);

            sample_count = sample_count + 1;

            // Track expected peaks
            if ((sample_count % 500) == 200)
                expected_peaks = expected_peaks + 1;
        end

        // Wait for pipeline to flush
        repeat(1000) @(posedge clk);

        $display("");
        $display("Results:");
        $display("  Expected ~%0d beats (some missed at start is OK)", expected_peaks);
        $display("  Detected %0d beats", beat_count);

        if (beat_count >= expected_peaks - 2 && beat_count <= expected_peaks + 2)
            $display("  PASS: Beat count within acceptable range");
        else
            $display("  WARNING: Beat count outside expected range");

        // Check RR interval consistency (should be ~500 samples between beats)
        if (beat_count >= 3) begin
            $display("");
            $display("RR Intervals:");
            begin : rr_check
                integer i, rr;
                for (i = 1; i < beat_count && i < 20; i = i + 1) begin
                    rr = peak_positions[i] - peak_positions[i-1];
                    $display("  Beat %0d-%0d: RR = %0d samples (%0.0f BPM)",
                             i-1, i, rr, 30000.0 / rr);
                end
            end
        end

        $display("");
        $display("=== QRS Detector Test Complete ===");
        $finish;
    end

    // Timeout
    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end

    // Optional VCD dump
    initial begin
        $dumpfile("tb_qrs_detector.vcd");
        $dumpvars(0, tb_qrs_detector);
    end

endmodule
