`timescale 1ns / 1ps
// Minimal test to verify adaptive_threshold refractory period
module tb_debug_refractory;
    reg clk, rst;
    reg [15:0] integrated;
    reg data_valid;
    wire beat_detect;
    wire [15:0] peak_amplitude;

    adaptive_threshold dut (
        .clk(clk), .rst(rst),
        .integrated(integrated), .data_valid(data_valid),
        .beat_detect(beat_detect), .peak_amplitude(peak_amplitude)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer sample_num;
    integer last_beat;

    always @(posedge clk) begin
        if (beat_detect)
            $display("  BEAT at sample %0d (gap=%0d)", sample_num, sample_num - last_beat);
    end

    initial begin
        $display("=== Refractory Period Debug Test ===");
        rst = 1; integrated = 0; data_valid = 0;
        sample_num = 0; last_beat = 0;
        #100; rst = 0; #20;

        // Send 500 samples: all LOW (value=1) except spikes every 200 samples
        repeat(500) begin
            @(posedge clk);
            if (sample_num == 50 || sample_num == 250 || sample_num == 450)
                integrated = 16'd500;  // High spike
            else
                integrated = 16'd1;    // Low baseline

            data_valid = 1;
            @(posedge clk);
            data_valid = 0;

            if (beat_detect) last_beat = sample_num;

            // Wait gap between samples (like the pipeline)
            repeat(10) @(posedge clk);
            sample_num = sample_num + 1;
        end

        $display("=== Done ===");
        $finish;
    end
endmodule
