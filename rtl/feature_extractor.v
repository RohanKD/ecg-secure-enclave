//============================================================================
// feature_extractor.v
// Combines all feature sub-modules and packs a 10-feature vector for the
// MLP classifier. Each feature is quantized to 8-bit unsigned [0, 255].
//
// Features (10 x 8-bit = 80-bit packed vector):
//   [0] Current RR interval (scaled)
//   [1] Previous RR interval (scaled)
//   [2] Mean RR (scaled)
//   [3] RR variability (scaled)
//   [4] Current RR / Previous RR ratio (scaled)
//   [5] Current RR / Mean RR ratio (scaled)
//   [6] QRS width (scaled)
//   [7] Normalized amplitude
//   [8] RR interval deviation from mean (|current - mean|, scaled)
//   [9] Heart rate (derived from mean RR, BPM scaled to 8 bits)
//
// Scaling strategy:
//   - RR intervals at 500 Hz: typical range 250-750 samples (30-120 BPM)
//     Scale: (rr * 256) / 1024 = rr >> 2, clamp to [0,255]
//   - Ratios: computed as (a * 128) / b, giving ~128 for ratio=1.0
//   - QRS width: typical 15-50 samples. Scale: width * 5, clamp to [0,255]
//   - Heart rate: 30-220 BPM mapped to 0-255
//
// Target: Xilinx Artix-7 (Basys 3).
//============================================================================

module feature_extractor (
    input  wire        clk,
    input  wire        rst,
    input  wire        beat_detect,
    input  wire signed [15:0] filtered_ecg,
    input  wire        filtered_valid,
    input  wire [15:0] peak_amplitude,
    output reg  [79:0] feature_vector,
    output reg         features_valid,
    output reg  [15:0] heart_rate_bpm
);

    // ---------------------------------------------------------------
    // Internal wires from sub-modules
    // ---------------------------------------------------------------
    wire [15:0] rr_interval_w;
    wire        rr_valid_w;

    wire [15:0] mean_rr_w;
    wire [15:0] rr_variability_w;
    wire        stats_valid_w;

    wire [15:0] qrs_width_w;
    wire        width_valid_w;

    wire [15:0] norm_amplitude_w;
    wire        amp_valid_w;

    // ---------------------------------------------------------------
    // Sub-module instantiations
    // ---------------------------------------------------------------
    rr_interval u_rr_interval (
        .clk             (clk),
        .rst             (rst),
        .beat_detect     (beat_detect),
        .rr_interval_out (rr_interval_w),
        .rr_valid        (rr_valid_w)
    );

    rr_stats u_rr_stats (
        .clk             (clk),
        .rst             (rst),
        .rr_interval     (rr_interval_w),
        .rr_valid        (rr_valid_w),
        .mean_rr         (mean_rr_w),
        .rr_variability  (rr_variability_w),
        .stats_valid     (stats_valid_w)
    );

    qrs_width u_qrs_width (
        .clk             (clk),
        .rst             (rst),
        .filtered_ecg    (filtered_ecg),
        .filtered_valid  (filtered_valid),
        .beat_detect     (beat_detect),
        .peak_amplitude  (peak_amplitude),
        .qrs_width_out   (qrs_width_w),
        .width_valid     (width_valid_w)
    );

    amplitude u_amplitude (
        .clk             (clk),
        .rst             (rst),
        .beat_detect     (beat_detect),
        .peak_amplitude  (peak_amplitude),
        .norm_amplitude  (norm_amplitude_w),
        .amp_valid       (amp_valid_w)
    );

    // ---------------------------------------------------------------
    // Latched feature values (updated as each sub-module produces output)
    // ---------------------------------------------------------------
    reg [15:0] current_rr;
    reg [15:0] previous_rr;
    reg [15:0] mean_rr_latched;
    reg [15:0] variability_latched;
    reg [15:0] qrs_width_latched;
    reg [15:0] norm_amp_latched;

    // Feature readiness flags
    reg rr_ready;
    reg stats_ready;
    reg width_ready;
    reg amp_ready;

    // ---------------------------------------------------------------
    // Latch RR interval values
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            current_rr  <= 16'd0;
            previous_rr <= 16'd0;
            rr_ready    <= 1'b0;
        end else if (rr_valid_w) begin
            previous_rr <= current_rr;
            current_rr  <= rr_interval_w;
            rr_ready    <= 1'b1;
        end
    end

    // ---------------------------------------------------------------
    // Latch stats values
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            mean_rr_latched     <= 16'd0;
            variability_latched <= 16'd0;
            stats_ready         <= 1'b0;
        end else if (stats_valid_w) begin
            mean_rr_latched     <= mean_rr_w;
            variability_latched <= rr_variability_w;
            stats_ready         <= 1'b1;
        end
    end

    // ---------------------------------------------------------------
    // Latch QRS width
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            qrs_width_latched <= 16'd0;
            width_ready       <= 1'b0;
        end else if (width_valid_w) begin
            qrs_width_latched <= qrs_width_w;
            width_ready       <= 1'b1;
        end
    end

    // ---------------------------------------------------------------
    // Latch amplitude
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            norm_amp_latched <= 16'd0;
            amp_ready        <= 1'b0;
        end else if (amp_valid_w) begin
            norm_amp_latched <= norm_amplitude_w;
            amp_ready        <= 1'b1;
        end
    end

    // ---------------------------------------------------------------
    // Feature computation pipeline
    // Triggered after all sub-modules have produced at least one output
    // and a new RR interval arrives (synchronizes to heartbeat).
    // ---------------------------------------------------------------

    // Pipeline stages for feature scaling
    reg        feat_pipe_start;
    reg        feat_pipe_s1;
    reg        feat_pipe_s2;
    reg        feat_pipe_s3;

    // Scaled 8-bit features
    reg [7:0] feat_current_rr;
    reg [7:0] feat_previous_rr;
    reg [7:0] feat_mean_rr;
    reg [7:0] feat_variability;
    reg [7:0] feat_rr_ratio;
    reg [7:0] feat_rr_mean_ratio;
    reg [7:0] feat_qrs_width;
    reg [7:0] feat_norm_amp;
    reg [7:0] feat_rr_deviation;
    reg [7:0] feat_heart_rate;

    // Intermediate computation registers
    reg [31:0] ratio_num1;     // current_rr * 128
    reg [31:0] ratio_num2;     // current_rr * 128 (for mean ratio)
    reg [15:0] rr_dev_abs;     // |current_rr - mean_rr|

    // ---------------------------------------------------------------
    // Trigger feature computation on new RR interval
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            feat_pipe_start <= 1'b0;
        end else begin
            // Start feature packing when we have a new RR and all modules ready
            feat_pipe_start <= rr_valid_w & rr_ready & stats_ready;
        end
    end

    // ---------------------------------------------------------------
    // Stage 1: Simple scaling (shift-based)
    // ---------------------------------------------------------------
    // Saturating 8-bit clamp function
    function [7:0] clamp8;
        input [15:0] val;
        begin
            clamp8 = (val > 16'd255) ? 8'd255 : val[7:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            feat_current_rr  <= 8'd0;
            feat_previous_rr <= 8'd0;
            feat_mean_rr     <= 8'd0;
            feat_variability <= 8'd0;
            feat_qrs_width   <= 8'd0;
            feat_norm_amp    <= 8'd0;
            ratio_num1       <= 32'd0;
            ratio_num2       <= 32'd0;
            rr_dev_abs       <= 16'd0;
            feat_pipe_s1     <= 1'b0;
        end else begin
            feat_pipe_s1 <= feat_pipe_start;
            if (feat_pipe_start) begin
                // RR intervals: scale by >> 2 (maps 0-1023 to 0-255)
                feat_current_rr  <= clamp8(current_rr >> 2);
                feat_previous_rr <= clamp8(previous_rr >> 2);
                feat_mean_rr     <= clamp8(mean_rr_latched >> 2);

                // Variability: scale by >> 1
                feat_variability <= clamp8(variability_latched >> 1);

                // QRS width: multiply by 5 (shift+add: x*4 + x = (x<<2)+x)
                feat_qrs_width <= clamp8((qrs_width_latched << 2) + qrs_width_latched);

                // Normalized amplitude (already in 0-255 range)
                feat_norm_amp <= norm_amp_latched[7:0];

                // Prepare ratio computations
                ratio_num1 <= {16'd0, current_rr} << 7; // * 128
                ratio_num2 <= {16'd0, current_rr} << 7; // * 128

                // RR deviation from mean
                if (current_rr > mean_rr_latched)
                    rr_dev_abs <= current_rr - mean_rr_latched;
                else
                    rr_dev_abs <= mean_rr_latched - current_rr;
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 2: Ratio and deviation computations
    //   Ratio = (a * 128) / b => ~128 when a==b
    //   Use simple shift-based approximation: find MSB of denominator,
    //   then shift numerator accordingly.
    // ---------------------------------------------------------------

    // Approximate division: (num) / denom using shift
    // Returns result clamped to 8 bits
    // Approximation: num / denom ≈ num >> log2(denom)
    // More accurate: use the upper bits of denom to index a shift amount

    always @(posedge clk) begin
        if (rst) begin
            feat_rr_ratio      <= 8'd0;
            feat_rr_mean_ratio <= 8'd0;
            feat_rr_deviation  <= 8'd0;
            feat_pipe_s2       <= 1'b0;
        end else begin
            feat_pipe_s2 <= feat_pipe_s1;
            if (feat_pipe_s1) begin
                // Current RR / Previous RR ratio
                // = (current_rr * 128) / previous_rr
                if (previous_rr == 16'd0)
                    feat_rr_ratio <= 8'd128; // Default to 1.0 if no previous
                else if (previous_rr >= current_rr)
                    // Ratio <= 1.0, result in [0, 128]
                    feat_rr_ratio <= clamp8(ratio_num1 / {16'd0, previous_rr});
                else
                    // Ratio > 1.0, result in [128, ...]
                    feat_rr_ratio <= clamp8(ratio_num1 / {16'd0, previous_rr});

                // Current RR / Mean RR ratio
                if (mean_rr_latched == 16'd0)
                    feat_rr_mean_ratio <= 8'd128;
                else
                    feat_rr_mean_ratio <= clamp8(ratio_num2 / {16'd0, mean_rr_latched});

                // RR deviation from mean: scale by >> 1
                feat_rr_deviation <= clamp8(rr_dev_abs >> 1);
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 3: Heart rate computation and feature vector packing
    //   HR (BPM) = 60 * Fs / mean_rr = 30000 / mean_rr
    //   Scale to 8-bit: (HR - 30) * 255 / 190 ≈ HR * 1.34
    //   Simpler: HR >> 0 with offset, clamp to [0, 255]
    //   Or just: feat = HR - 30, clamp to [0, 255]
    // ---------------------------------------------------------------
    reg [31:0] hr_calc;

    always @(posedge clk) begin
        if (rst) begin
            feat_heart_rate  <= 8'd0;
            heart_rate_bpm   <= 16'd0;
            feat_pipe_s3     <= 1'b0;
        end else begin
            feat_pipe_s3 <= feat_pipe_s2;
            if (feat_pipe_s2) begin
                // BPM = 30000 / mean_rr (where 30000 = 60 * 500)
                if (mean_rr_latched > 16'd0) begin
                    hr_calc = 32'd30000 / {16'd0, mean_rr_latched};
                    heart_rate_bpm <= hr_calc[15:0];

                    // Scale to 8-bit: subtract 30 BPM baseline, clamp
                    if (hr_calc > 32'd30)
                        feat_heart_rate <= clamp8(hr_calc[15:0] - 16'd30);
                    else
                        feat_heart_rate <= 8'd0;
                end else begin
                    heart_rate_bpm  <= 16'd0;
                    feat_heart_rate <= 8'd0;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 4: Pack feature vector and assert valid
    //   feature_vector[79:72] = feat[0] (current RR)
    //   feature_vector[71:64] = feat[1] (previous RR)
    //   ...
    //   feature_vector[7:0]   = feat[9] (heart rate)
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            feature_vector <= 80'd0;
            features_valid <= 1'b0;
        end else begin
            features_valid <= feat_pipe_s3;
            if (feat_pipe_s3) begin
                feature_vector <= {
                    feat_current_rr,     // [79:72] Feature 0
                    feat_previous_rr,    // [71:64] Feature 1
                    feat_mean_rr,        // [63:56] Feature 2
                    feat_variability,    // [55:48] Feature 3
                    feat_rr_ratio,       // [47:40] Feature 4
                    feat_rr_mean_ratio,  // [39:32] Feature 5
                    feat_qrs_width,      // [31:24] Feature 6
                    feat_norm_amp,       // [23:16] Feature 7
                    feat_rr_deviation,   // [15:8]  Feature 8
                    feat_heart_rate      // [7:0]   Feature 9
                };
            end
        end
    end

endmodule
