//============================================================================
// qrs_detector.v
// Top-level Pan-Tompkins QRS detection pipeline.
//
// Signal chain:
//   ecg_in --> bandpass_filter --> derivative_filter --> squarer
//          --> moving_avg --> adaptive_threshold --> beat_detect
//
// Also outputs the bandpass-filtered ECG for downstream feature extraction,
// and the peak amplitude for template matching / amplitude features.
//
// Target: Xilinx Artix-7 (Basys 3), 16-bit signed/unsigned data path.
//============================================================================

module qrs_detector (
    input  wire        clk,
    input  wire        rst,
    input  wire signed [15:0] ecg_in,
    input  wire        ecg_valid,
    output wire        beat_detect,
    output wire signed [15:0] filtered_ecg,
    output wire        filtered_valid,
    output wire [15:0] peak_amplitude
);

    // ---------------------------------------------------------------
    // Internal wires
    // ---------------------------------------------------------------
    // Bandpass filter outputs
    wire signed [15:0] bp_out;
    wire               bp_valid;

    // Derivative filter outputs
    wire signed [15:0] deriv_out;
    wire               deriv_valid;

    // Squarer outputs
    wire [15:0]        sq_out;
    wire               sq_valid;

    // Moving average outputs
    wire [15:0]        ma_out;
    wire               ma_valid;

    // ---------------------------------------------------------------
    // Stage 1: Bandpass filter (5-15 Hz)
    // ---------------------------------------------------------------
    bandpass_filter u_bandpass (
        .clk        (clk),
        .rst        (rst),
        .din        (ecg_in),
        .din_valid  (ecg_valid),
        .dout       (bp_out),
        .dout_valid (bp_valid)
    );

    // ---------------------------------------------------------------
    // Stage 2: 5-point derivative filter
    // ---------------------------------------------------------------
    derivative_filter u_derivative (
        .clk        (clk),
        .rst        (rst),
        .din        (bp_out),
        .din_valid  (bp_valid),
        .dout       (deriv_out),
        .dout_valid (deriv_valid)
    );

    // ---------------------------------------------------------------
    // Stage 3: Squarer (magnitude emphasis)
    // ---------------------------------------------------------------
    squarer u_squarer (
        .clk        (clk),
        .rst        (rst),
        .din        (deriv_out),
        .din_valid  (deriv_valid),
        .dout       (sq_out),
        .dout_valid (sq_valid)
    );

    // ---------------------------------------------------------------
    // Stage 4: Moving window integrator (75 samples / 150 ms)
    // ---------------------------------------------------------------
    moving_avg u_moving_avg (
        .clk        (clk),
        .rst        (rst),
        .din        (sq_out),
        .din_valid  (sq_valid),
        .dout       (ma_out),
        .dout_valid (ma_valid)
    );

    // ---------------------------------------------------------------
    // Stage 5: Adaptive dual-threshold detector
    // ---------------------------------------------------------------
    adaptive_threshold u_threshold (
        .clk            (clk),
        .rst            (rst),
        .integrated     (ma_out),
        .data_valid     (ma_valid),
        .beat_detect    (beat_detect),
        .peak_amplitude (peak_amplitude)
    );

    // ---------------------------------------------------------------
    // Pass through bandpass-filtered ECG for feature extraction
    // ---------------------------------------------------------------
    assign filtered_ecg  = bp_out;
    assign filtered_valid = bp_valid;

endmodule
