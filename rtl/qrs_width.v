//============================================================================
// qrs_width.v
// Measures QRS complex width (duration) using the bandpass-filtered ECG
// signal. The QRS width is defined as the number of samples during which
// |filtered_ecg| exceeds a dynamic threshold derived from peak_amplitude.
//
// Algorithm:
//   - Threshold = peak_amplitude >> 2 (25% of peak)
//   - When |filtered_ecg| rises above threshold near a beat: start counting
//   - When |filtered_ecg| falls below threshold: stop, output the count
//   - A beat_detect pulse arms the measurement window
//   - Measurement window extends up to 100 samples (200 ms) after beat_detect
//
// Target: Xilinx Artix-7 (Basys 3), 16-bit data path.
//============================================================================

module qrs_width (
    input  wire        clk,
    input  wire        rst,
    input  wire signed [15:0] filtered_ecg,
    input  wire        filtered_valid,
    input  wire        beat_detect,
    input  wire [15:0] peak_amplitude,
    output reg  [15:0] qrs_width_out,
    output reg         width_valid
);

    // ---------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------
    localparam [7:0] MAX_QRS_SAMPLES = 8'd100; // Max QRS width in samples (200 ms)
    localparam [7:0] MIN_QRS_SAMPLES = 8'd5;   // Min valid QRS width

    // ---------------------------------------------------------------
    // State machine
    // ---------------------------------------------------------------
    localparam [1:0] ST_IDLE     = 2'd0; // Waiting for beat_detect
    localparam [1:0] ST_ARMED    = 2'd1; // Beat detected, looking for threshold crossing
    localparam [1:0] ST_COUNTING = 2'd2; // Above threshold, counting width
    localparam [1:0] ST_DONE     = 2'd3; // Measurement complete

    reg [1:0] state;

    // ---------------------------------------------------------------
    // Internal registers
    // ---------------------------------------------------------------
    reg [15:0] threshold;           // Dynamic threshold (peak_amplitude >> 2)
    reg [15:0] width_counter;       // Sample counter during QRS
    reg [7:0]  window_counter;      // Timeout counter for armed state
    reg [15:0] abs_ecg;             // |filtered_ecg|

    // ---------------------------------------------------------------
    // Absolute value computation (registered for timing)
    // ---------------------------------------------------------------
    reg [15:0] abs_ecg_reg;
    reg        ecg_valid_d;

    always @(posedge clk) begin
        if (rst) begin
            abs_ecg_reg <= 16'd0;
            ecg_valid_d <= 1'b0;
        end else begin
            ecg_valid_d <= filtered_valid;
            if (filtered_valid) begin
                abs_ecg_reg <= filtered_ecg[15] ? (~filtered_ecg + 16'd1) : filtered_ecg;
            end
        end
    end

    // ---------------------------------------------------------------
    // Main state machine
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state          <= ST_IDLE;
            threshold      <= 16'd0;
            width_counter  <= 16'd0;
            window_counter <= 8'd0;
            qrs_width_out  <= 16'd0;
            width_valid    <= 1'b0;
        end else begin
            // Default: clear output valid
            width_valid <= 1'b0;

            // Beat detect can preempt any state (new beat resets measurement)
            if (beat_detect) begin
                state     <= ST_ARMED;
                threshold <= peak_amplitude >> 2;
                width_counter  <= 16'd0;
                window_counter <= 8'd0;
            end else if (ecg_valid_d) begin
                case (state)
                    ST_IDLE: begin
                        // Waiting for beat_detect (handled above)
                    end

                    ST_ARMED: begin
                        // Look for signal above threshold to start counting
                        window_counter <= window_counter + 8'd1;

                        if (abs_ecg_reg > threshold) begin
                            state         <= ST_COUNTING;
                            width_counter <= 16'd1;
                        end else if (window_counter >= MAX_QRS_SAMPLES) begin
                            // Timeout: no QRS found, output zero
                            state         <= ST_IDLE;
                            qrs_width_out <= 16'd0;
                            width_valid   <= 1'b1;
                        end
                    end

                    ST_COUNTING: begin
                        if (abs_ecg_reg > threshold) begin
                            // Still above threshold
                            width_counter <= width_counter + 16'd1;

                            // Safety: clamp if QRS is unreasonably wide
                            if (width_counter >= {8'd0, MAX_QRS_SAMPLES}) begin
                                state         <= ST_DONE;
                                qrs_width_out <= width_counter;
                                width_valid   <= 1'b1;
                            end
                        end else begin
                            // Dropped below threshold: QRS ended
                            state <= ST_DONE;
                            if (width_counter >= {8'd0, MIN_QRS_SAMPLES}) begin
                                qrs_width_out <= width_counter;
                            end else begin
                                qrs_width_out <= 16'd0; // Too narrow, likely noise
                            end
                            width_valid <= 1'b1;
                        end
                    end

                    ST_DONE: begin
                        // Wait for next beat_detect (handled above)
                        state <= ST_IDLE;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
