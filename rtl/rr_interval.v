//============================================================================
// rr_interval.v
// Measures the RR interval (in samples) between consecutive R-peak
// detections from the QRS detector.
//
// On each beat_detect pulse, the current sample counter is output as
// the RR interval, then the counter is reset. The first beat after reset
// does not produce a valid output (need two beats to form an interval).
//
// Output is clamped at 16-bit maximum (65535 samples = ~131 seconds at
// 500 Hz, far beyond any physiological RR interval).
//
// Target: Xilinx Artix-7 (Basys 3).
//============================================================================

module rr_interval (
    input  wire        clk,
    input  wire        rst,
    input  wire        beat_detect,
    output reg  [15:0] rr_interval_out,
    output reg         rr_valid
);

    // ---------------------------------------------------------------
    // Sample counter between beats
    // ---------------------------------------------------------------
    reg [15:0] sample_count;

    // ---------------------------------------------------------------
    // Track whether we have seen at least one beat (need 2 for interval)
    // ---------------------------------------------------------------
    reg first_beat_seen;

    // ---------------------------------------------------------------
    // Main logic
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            sample_count    <= 16'd0;
            rr_interval_out <= 16'd0;
            rr_valid        <= 1'b0;
            first_beat_seen <= 1'b0;
        end else begin
            // Default: clear valid pulse
            rr_valid <= 1'b0;

            if (beat_detect) begin
                if (first_beat_seen) begin
                    // Second or subsequent beat: output the interval
                    rr_interval_out <= sample_count;
                    rr_valid        <= 1'b1;
                end else begin
                    // First beat: just mark that we've started
                    first_beat_seen <= 1'b1;
                end
                // Reset counter for next interval
                sample_count <= 16'd1; // Count the current sample
            end else begin
                // Increment counter, clamped at 16-bit max
                if (sample_count < 16'hFFFF)
                    sample_count <= sample_count + 16'd1;
            end
        end
    end

endmodule
