//============================================================================
// adaptive_threshold.v
// Pan-Tompkins adaptive dual-threshold detector with refractory period
// and search-back capability.
//
// Algorithm:
//   - Maintain exponential moving averages: signal_level, noise_level
//   - threshold1 = noise_level + (signal_level - noise_level) >> 2
//     i.e., noise + 0.25 * (signal - noise)
//   - threshold2 = threshold1 >> 1  (half of threshold1)
//   - R-peak detected when integrated signal > threshold1 AND outside
//     refractory period (200 ms = 100 samples at 500 Hz).
//   - Search-back: if signal crossed threshold2 but not threshold1 during
//     the window after refractory, re-check with lower threshold.
//   - On peak: signal_level += (peak - signal_level) >> 3
//   - On noise: noise_level += (sample - noise_level) >> 3
//
// Target: Xilinx Artix-7 (Basys 3), 16-bit unsigned data path.
//============================================================================

module adaptive_threshold (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] integrated,
    input  wire        data_valid,
    output reg         beat_detect,
    output reg  [15:0] peak_amplitude
);

    // ---------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------
    localparam [15:0] REFRACTORY_SAMPLES = 16'd250; // 500 ms at 500 Hz (covers full QT interval)
    localparam [15:0] SEARCHBACK_WINDOW  = 16'd250; // 500 ms at 500 Hz
    localparam [15:0] INIT_SIGNAL_LEVEL  = 16'd100; // Initial estimate (tuned for >>8 squarer)
    localparam [15:0] INIT_NOISE_LEVEL   = 16'd10;  // Initial estimate
    localparam [15:0] MIN_THRESHOLD      = 16'd8;   // Minimum threshold floor to prevent noise triggers

    // ---------------------------------------------------------------
    // State registers
    // ---------------------------------------------------------------
    reg [15:0] signal_level;        // Exponential average of signal peaks
    reg [15:0] noise_level;         // Exponential average of noise
    reg [15:0] threshold1;          // Primary detection threshold
    reg [15:0] threshold2;          // Secondary (search-back) threshold

    reg [15:0] refractory_counter;  // Counts down during refractory period
    reg        in_refractory;       // High during refractory period

    // ---------------------------------------------------------------
    // Peak tracking within current beat window
    // ---------------------------------------------------------------
    reg [15:0] local_peak;          // Maximum value since last beat
    reg [15:0] samples_since_beat;  // Counter for search-back timing
    reg        searchback_candidate;// Threshold2 was crossed but not threshold1
    reg [15:0] searchback_peak;     // Peak amplitude during search-back region
    reg        above_threshold;     // Currently above threshold1 (for peak detection)
    reg [15:0] prev_integrated;     // Previous sample for peak finding
    reg        rising;              // Signal was rising (for peak detection)

    // ---------------------------------------------------------------
    // Pipeline: register threshold computation for timing
    // ---------------------------------------------------------------
    reg [15:0] thresh_diff;         // signal_level - noise_level (clamped)

    // ---------------------------------------------------------------
    // Threshold computation (combinational, registered output)
    // ---------------------------------------------------------------
    wire [15:0] sig_minus_noise = (signal_level > noise_level) ?
                                   (signal_level - noise_level) : 16'd0;

    // Threshold = noise + 0.375 * (signal - noise), more robust than 0.25
    wire [15:0] thresh1_raw  = noise_level + (sig_minus_noise >> 2) + (sig_minus_noise >> 3);
    wire [15:0] thresh1_calc = (thresh1_raw > MIN_THRESHOLD) ? thresh1_raw : MIN_THRESHOLD;
    wire [15:0] thresh2_calc = thresh1_calc >> 1;

    // ---------------------------------------------------------------
    // Main detection logic
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            signal_level        <= INIT_SIGNAL_LEVEL;
            noise_level         <= INIT_NOISE_LEVEL;
            threshold1          <= INIT_NOISE_LEVEL + ((INIT_SIGNAL_LEVEL - INIT_NOISE_LEVEL) >> 2);
            threshold2          <= (INIT_NOISE_LEVEL + ((INIT_SIGNAL_LEVEL - INIT_NOISE_LEVEL) >> 2)) >> 1;
            refractory_counter  <= 16'd0;
            in_refractory       <= 1'b0;
            local_peak          <= 16'd0;
            samples_since_beat  <= 16'd0;
            searchback_candidate <= 1'b0;
            searchback_peak     <= 16'd0;
            above_threshold     <= 1'b0;
            prev_integrated     <= 16'd0;
            rising              <= 1'b0;
            beat_detect         <= 1'b0;
            peak_amplitude      <= 16'd0;
        end else if (data_valid) begin
            // Default: no beat this cycle
            beat_detect <= 1'b0;

            // Update thresholds each cycle
            threshold1 <= thresh1_calc;
            threshold2 <= thresh2_calc;

            // Track time since last beat for search-back
            if (samples_since_beat < 16'hFFFF)
                samples_since_beat <= samples_since_beat + 16'd1;

            // -------------------------------------------------------
            // Refractory period management
            // -------------------------------------------------------
            if (in_refractory) begin
                if (refractory_counter > 16'd0) begin
                    refractory_counter <= refractory_counter - 16'd1;
                end else begin
                    in_refractory <= 1'b0;
                end
                // Track local peak even during refractory (for amplitude)
                if (integrated > local_peak)
                    local_peak <= integrated;
            end
            // -------------------------------------------------------
            // Active detection (outside refractory)
            // Uses PEAK detection: finds local maximum above threshold
            // rather than triggering on first threshold crossing.
            // -------------------------------------------------------
            else begin
                // Track previous value and rising/falling state
                prev_integrated <= integrated;
                rising <= (integrated > prev_integrated);

                // Track local peak above threshold
                if (integrated > local_peak)
                    local_peak <= integrated;

                if (integrated > threshold1) begin
                    above_threshold <= 1'b1;

                    // Detect peak: was rising, now falling (or equal), above threshold
                    // This is the local maximum
                    if (above_threshold && rising && (integrated <= prev_integrated)) begin
                        beat_detect    <= 1'b1;
                        peak_amplitude <= local_peak;

                        // Update signal level
                        if (local_peak > signal_level)
                            signal_level <= signal_level + ((local_peak - signal_level) >> 3);
                        else
                            signal_level <= signal_level - ((signal_level - local_peak) >> 3);

                        // Enter refractory period
                        in_refractory      <= 1'b1;
                        refractory_counter <= REFRACTORY_SAMPLES;
                        local_peak         <= 16'd0;
                        samples_since_beat <= 16'd0;
                        searchback_candidate <= 1'b0;
                        searchback_peak    <= 16'd0;
                        above_threshold    <= 1'b0;
                    end
                end else begin
                    // Fell below threshold without finding peak while above
                    // If we were above threshold, the local_peak IS the peak
                    if (above_threshold && (local_peak > threshold1)) begin
                        beat_detect    <= 1'b1;
                        peak_amplitude <= local_peak;

                        if (local_peak > signal_level)
                            signal_level <= signal_level + ((local_peak - signal_level) >> 3);
                        else
                            signal_level <= signal_level - ((signal_level - local_peak) >> 3);

                        in_refractory      <= 1'b1;
                        refractory_counter <= REFRACTORY_SAMPLES;
                        local_peak         <= 16'd0;
                        samples_since_beat <= 16'd0;
                        searchback_candidate <= 1'b0;
                        searchback_peak    <= 16'd0;
                    end
                    above_threshold <= 1'b0;

                    // Track search-back candidate (above threshold2 but not threshold1)
                    if (integrated > threshold2) begin
                        searchback_candidate <= 1'b1;
                        if (integrated > searchback_peak)
                            searchback_peak <= integrated;
                    end

                    // Update noise level
                    if (integrated > noise_level)
                        noise_level <= noise_level + ((integrated - noise_level) >> 3);
                    else
                        noise_level <= noise_level - ((noise_level - integrated) >> 3);
                end

                // -------------------------------------------------------
                // Search-back: if no threshold1 crossing for too long,
                // and we had a threshold2 crossing, accept it as a beat
                // -------------------------------------------------------
                if (searchback_candidate &&
                    (samples_since_beat > SEARCHBACK_WINDOW) &&
                    (searchback_peak > threshold2)) begin

                    beat_detect    <= 1'b1;
                    peak_amplitude <= searchback_peak;

                    if (searchback_peak > signal_level)
                        signal_level <= signal_level + ((searchback_peak - signal_level) >> 3);
                    else
                        signal_level <= signal_level - ((signal_level - searchback_peak) >> 3);

                    in_refractory      <= 1'b1;
                    refractory_counter <= REFRACTORY_SAMPLES;
                    local_peak         <= 16'd0;
                    samples_since_beat <= 16'd0;
                    searchback_candidate <= 1'b0;
                    searchback_peak    <= 16'd0;
                    above_threshold    <= 1'b0;
                end
            end
        end else begin
            // No valid data: clear single-cycle pulse
            beat_detect <= 1'b0;
        end
    end

endmodule
