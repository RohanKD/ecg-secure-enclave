//////////////////////////////////////////////////////////////////////////////
// led_status.v
// LED status indicators for Basys 3 ECG secure enclave
//
// LED assignments:
//   LED[0]     - Heartbeat indicator (toggles on each R-peak detection)
//   LED[1]     - Sample-valid activity (pulses/stretches on each sample)
//   LED[6:2]   - Raw ADC upper 5 bits [11:7] for debug visualization
//   LED[12:7]  - Unused, driven low
//   LED[14:13] - Abnormal classification alert (blink pattern ~2 Hz)
//   LED[15]    - Leads-off warning (steady on when leads disconnected)
//////////////////////////////////////////////////////////////////////////////

module led_status(
    input  wire        clk,
    input  wire        rst,
    input  wire        beat_detect,    // Pulse on R-peak
    input  wire        sample_valid,
    input  wire        leads_off,      // OR of LO+ and LO-
    input  wire        abnormal,       // Classification result
    input  wire [11:0] raw_adc,        // For debug display
    output reg  [15:0] led
);

    // -----------------------------------------------------------------------
    // LED[0]: Heartbeat toggle - toggles state on every R-peak detection
    // -----------------------------------------------------------------------
    reg beat_toggle;

    always @(posedge clk or posedge rst) begin
        if (rst)
            beat_toggle <= 1'b0;
        else if (beat_detect)
            beat_toggle <= ~beat_toggle;
    end

    // -----------------------------------------------------------------------
    // LED[1]: Sample-valid activity stretcher
    // Extends the single-cycle sample_valid pulse to ~10 ms so the LED
    // is visible. Uses a 20-bit counter (~10 ms at 100 MHz).
    // -----------------------------------------------------------------------
    reg [19:0] activity_cnt;
    reg        activity_led;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            activity_cnt <= 20'd0;
            activity_led <= 1'b0;
        end else if (sample_valid) begin
            activity_cnt <= 20'd999_999;  // ~10 ms stretch
            activity_led <= 1'b1;
        end else if (activity_cnt != 20'd0) begin
            activity_cnt <= activity_cnt - 20'd1;
        end else begin
            activity_led <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // LED[14:13]: Abnormal classification alert
    // When 'abnormal' is asserted, blink at ~2 Hz (toggle every 25M cycles).
    // When normal, LEDs are off.
    // -----------------------------------------------------------------------
    localparam [24:0] BLINK_HALF = 25'd24_999_999; // 250 ms at 100 MHz

    reg [24:0] blink_cnt;
    reg        blink_phase;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            blink_cnt   <= 25'd0;
            blink_phase <= 1'b0;
        end else begin
            if (blink_cnt == BLINK_HALF) begin
                blink_cnt   <= 25'd0;
                blink_phase <= ~blink_phase;
            end else begin
                blink_cnt <= blink_cnt + 25'd1;
            end
        end
    end

    wire abnormal_blink = abnormal & blink_phase;

    // -----------------------------------------------------------------------
    // LED output assignment (active-high on Basys 3)
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            led <= 16'd0;
        end else begin
            led[0]     <= beat_toggle;           // Heartbeat toggle
            led[1]     <= activity_led;          // Sample activity
            led[6:2]   <= raw_adc[11:7];         // ADC debug (upper 5 bits)
            led[12:7]  <= 6'd0;                  // Unused
            led[14:13] <= {2{abnormal_blink}};   // Abnormal alert blink
            led[15]    <= leads_off;             // Leads-off warning
        end
    end

endmodule
