//============================================================================
// ecg_pipeline.v
// Top-level container for the entire ECG signal processing chain.
//
// Data flow:
//   12-bit ADC input --> sign-extend to 16-bit
//     --> qrs_detector (bandpass -> derivative -> squarer -> moving_avg
//                       -> adaptive_threshold)
//     --> feature_extractor (rr_interval, rr_stats, qrs_width, amplitude)
//     --> 80-bit feature_vector (10 x 8-bit) for MLP classifier
//
// The module also outputs:
//   - beat_detect:     Single-cycle pulse on each detected R-peak
//   - heart_rate_bpm:  Current heart rate in BPM (16-bit)
//   - filtered_ecg:    Bandpass-filtered ECG signal (for display/debug)
//   - filtered_valid:  Valid strobe for filtered_ecg
//
// Target: Xilinx Artix-7 XC7A35T (Basys 3 board).
//============================================================================

module ecg_pipeline (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] ecg_sample,
    input  wire        sample_valid,
    output wire        beat_detect,
    output wire [79:0] feature_vector,
    output wire        features_valid,
    output wire [15:0] heart_rate_bpm,
    output wire signed [15:0] filtered_ecg,
    output wire        filtered_valid
);

    // ---------------------------------------------------------------
    // Sign-extend 12-bit ADC sample to 16-bit signed
    // 12-bit unsigned [0, 4095] from ADC is offset-binary:
    //   Subtract 2048 to center around zero, then sign-extend.
    //   Or treat bit[11] as sign and sign-extend directly.
    //
    // Here we assume the ADC provides 12-bit two's complement
    // (or offset-binary converted upstream). Sign-extend bit 11.
    // ---------------------------------------------------------------
    wire signed [15:0] ecg_in_16 = {{4{ecg_sample[11]}}, ecg_sample};

    // ---------------------------------------------------------------
    // QRS Detector (bandpass -> derivative -> squarer -> moving_avg
    //               -> adaptive_threshold)
    // ---------------------------------------------------------------
    wire        qrs_beat_detect;
    wire signed [15:0] qrs_filtered_ecg;
    wire        qrs_filtered_valid;
    wire [15:0] qrs_peak_amplitude;

    qrs_detector u_qrs_detector (
        .clk            (clk),
        .rst            (rst),
        .ecg_in         (ecg_in_16),
        .ecg_valid      (sample_valid),
        .beat_detect    (qrs_beat_detect),
        .filtered_ecg   (qrs_filtered_ecg),
        .filtered_valid (qrs_filtered_valid),
        .peak_amplitude (qrs_peak_amplitude)
    );

    // ---------------------------------------------------------------
    // Feature Extractor (rr_interval, rr_stats, qrs_width, amplitude)
    // ---------------------------------------------------------------
    wire [79:0] feat_vector_w;
    wire        feat_valid_w;
    wire [15:0] hr_bpm_w;

    feature_extractor u_feature_extractor (
        .clk             (clk),
        .rst             (rst),
        .beat_detect     (qrs_beat_detect),
        .filtered_ecg    (qrs_filtered_ecg),
        .filtered_valid  (qrs_filtered_valid),
        .peak_amplitude  (qrs_peak_amplitude),
        .feature_vector  (feat_vector_w),
        .features_valid  (feat_valid_w),
        .heart_rate_bpm  (hr_bpm_w)
    );

    // ---------------------------------------------------------------
    // Output assignments
    // ---------------------------------------------------------------
    assign beat_detect    = qrs_beat_detect;
    assign feature_vector = feat_vector_w;
    assign features_valid = feat_valid_w;
    assign heart_rate_bpm = hr_bpm_w;
    assign filtered_ecg   = qrs_filtered_ecg;
    assign filtered_valid = qrs_filtered_valid;

endmodule
