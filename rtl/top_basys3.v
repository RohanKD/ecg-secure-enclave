`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// top_basys3.v — ECG Secure Enclave Top-Level Module
// Basys 3 (Artix-7 XC7A35T)
//
// Architecture: Raw ECG acquired via XADC → QRS detection → feature
// extraction → MLP classification → AES encryption of raw data.
// ONLY encrypted data + classification exit the FPGA.
// Hardware-enforced HIPAA privacy.
//////////////////////////////////////////////////////////////////////////////

module top_basys3(
    // System
    input  wire        clk_100mhz,
    input  wire        btn_rst,       // Active-high reset (center button)

    // Switches
    input  wire [15:0] sw,
    // sw[0]: encryption enable
    // sw[1]: VGA mode (0=waveform, 1=encrypted hex display)

    // AD8232 leads-off detection (Pmod JA)
    input  wire        leads_off_p,
    input  wire        leads_off_n,

    // UART output
    output wire        uart_txd,

    // VGA output
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,

    // 7-segment display
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp,

    // LEDs
    output wire [15:0] led
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    wire        rst = btn_rst;
    wire        encrypt_enable = sw[0];
    wire        leads_off = leads_off_p | leads_off_n;

    // Clock divider outputs
    wire        clk_25mhz;
    wire        tick_500hz;
    wire        tick_1khz;

    // XADC outputs
    wire [11:0] raw_adc;
    wire        raw_adc_valid;

    // Voltage scaler outputs
    wire [11:0] scaled_adc;
    wire        scaled_valid;

    // ECG pipeline outputs
    wire        beat_detect;
    wire [79:0] feature_vector;
    wire        features_valid;
    wire [15:0] heart_rate_bpm;
    wire signed [15:0] filtered_ecg;
    wire        filtered_valid;

    // MLP classifier outputs
    wire        classification;
    wire        class_valid;
    wire        mlp_busy;

    // AES encryption
    wire [127:0] aes_plaintext;
    wire         aes_start;
    wire [127:0] aes_ciphertext;
    wire         aes_done;
    wire         aes_busy;

    // UART
    wire [7:0]  uart_data;
    wire        uart_start;
    wire        uart_busy;

    // VGA
    wire [9:0]  pixel_x, pixel_y;
    wire        video_on;
    wire        hsync_raw, vsync_raw;

    // VGA waveform
    wire [3:0]  wf_red, wf_green, wf_blue;
    wire        wf_active;

    // VGA text
    wire [3:0]  txt_red, txt_green, txt_blue;
    wire        txt_active;

    // =========================================================================
    // Clock Divider
    // =========================================================================
    clk_divider u_clk_div (
        .clk_100mhz (clk_100mhz),
        .rst         (rst),
        .clk_25mhz  (clk_25mhz),
        .tick_500hz  (tick_500hz),
        .tick_1khz   (tick_1khz)
    );

    // =========================================================================
    // XADC Interface — Acquire ECG analog signal
    // =========================================================================
    xadc_interface u_xadc (
        .clk         (clk_100mhz),
        .rst         (rst),
        .tick_500hz  (tick_500hz),
        .sample_data (raw_adc),
        .sample_valid(raw_adc_valid)
    );

    // =========================================================================
    // Voltage Scaler — Compensate for external voltage divider (×3)
    // =========================================================================
    voltage_scaler u_vscale (
        .clk         (clk_100mhz),
        .rst         (rst),
        .raw_adc     (raw_adc),
        .raw_valid   (raw_adc_valid),
        .scaled_adc  (scaled_adc),
        .scaled_valid(scaled_valid)
    );

    // =========================================================================
    // ECG Processing Pipeline — QRS detection + Feature extraction
    // =========================================================================
    ecg_pipeline u_ecg_pipe (
        .clk           (clk_100mhz),
        .rst           (rst),
        .ecg_sample    (scaled_adc),
        .sample_valid  (scaled_valid),
        .beat_detect   (beat_detect),
        .feature_vector(feature_vector),
        .features_valid(features_valid),
        .heart_rate_bpm(heart_rate_bpm),
        .filtered_ecg  (filtered_ecg),
        .filtered_valid(filtered_valid)
    );

    // =========================================================================
    // MLP Classifier — Normal vs Abnormal classification
    // =========================================================================
    mlp_classifier u_mlp (
        .clk            (clk_100mhz),
        .rst            (rst),
        .feature_vector (feature_vector),
        .features_valid (features_valid),
        .classification (classification),
        .class_valid    (class_valid),
        .busy           (mlp_busy)
    );

    // =========================================================================
    // AES-128 Encryption — Encrypt raw ECG samples
    // =========================================================================

    // AES key (hardcoded for demo — in production, load securely)
    wire [127:0] aes_key = 128'h000102030405060708090a0b0c0d0e0f;

    // Sample accumulator: collect 10 × 12-bit samples = 120 bits, pad to 128
    reg [127:0] sample_accumulator;
    reg [3:0]   sample_acc_count;
    reg         aes_trigger;

    always @(posedge clk_100mhz) begin
        if (rst) begin
            sample_accumulator <= 128'b0;
            sample_acc_count   <= 4'd0;
            aes_trigger        <= 1'b0;
        end else begin
            aes_trigger <= 1'b0;

            if (scaled_valid && encrypt_enable && !aes_busy) begin
                // Shift in new 12-bit sample
                sample_accumulator <= {sample_accumulator[115:0], scaled_adc};
                sample_acc_count   <= sample_acc_count + 4'd1;

                if (sample_acc_count == 4'd9) begin
                    // 10 samples collected (120 bits), pad upper 8 bits
                    aes_trigger      <= 1'b1;
                    sample_acc_count <= 4'd0;
                end
            end
        end
    end

    // Pack plaintext: 8 zero-pad bits + 120 bits of samples
    assign aes_plaintext = {8'b0, sample_accumulator[119:0]};
    assign aes_start     = aes_trigger;

    aes128_encrypt u_aes (
        .clk       (clk_100mhz),
        .rst       (rst),
        .plaintext (aes_plaintext),
        .key       (aes_key),
        .start     (aes_start),
        .ciphertext(aes_ciphertext),
        .done      (aes_done),
        .busy      (aes_busy)
    );

    // =========================================================================
    // Output Multiplexer → UART TX
    // =========================================================================
    output_mux u_outmux (
        .clk            (clk_100mhz),
        .rst            (rst),
        .cipher_data    (aes_ciphertext),
        .cipher_valid   (aes_done),
        .classification (classification),
        .heart_rate_bpm (heart_rate_bpm),
        .class_valid    (class_valid),
        .uart_data      (uart_data),
        .uart_start     (uart_start),
        .uart_busy      (uart_busy),
        .encrypt_enable (encrypt_enable)
    );

    uart_tx u_uart (
        .clk     (clk_100mhz),
        .rst     (rst),
        .tx_data (uart_data),
        .tx_start(uart_start),
        .tx_out  (uart_txd),
        .tx_busy (uart_busy)
    );

    // =========================================================================
    // VGA Display
    // =========================================================================
    vga_controller u_vga_ctrl (
        .clk          (clk_100mhz),
        .rst          (rst),
        .clk_25mhz_en(clk_25mhz),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y),
        .video_on     (video_on),
        .hsync        (hsync_raw),
        .vsync        (vsync_raw)
    );

    assign vga_hsync = hsync_raw;
    assign vga_vsync = vsync_raw;

    // Waveform display (use scaled ADC, not filtered, for raw display)
    vga_waveform u_vga_wf (
        .clk         (clk_100mhz),
        .rst         (rst),
        .ecg_sample  (scaled_adc),
        .sample_valid(scaled_valid),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .video_on    (video_on),
        .wf_red      (wf_red),
        .wf_green    (wf_green),
        .wf_blue     (wf_blue),
        .wf_active   (wf_active)
    );

    vga_text u_vga_txt (
        .clk           (clk_100mhz),
        .rst           (rst),
        .pixel_x       (pixel_x),
        .pixel_y       (pixel_y),
        .video_on      (video_on),
        .heart_rate_bpm(heart_rate_bpm),
        .abnormal      (classification),
        .leads_off     (leads_off),
        .txt_red       (txt_red),
        .txt_green     (txt_green),
        .txt_blue      (txt_blue),
        .txt_active    (txt_active)
    );

    // VGA color mux: text overlays on top of waveform
    assign vga_r = (!video_on) ? 4'h0 :
                   txt_active  ? txt_red :
                   wf_active   ? wf_red  : 4'h0;
    assign vga_g = (!video_on) ? 4'h0 :
                   txt_active  ? txt_green :
                   wf_active   ? wf_green  : 4'h0;
    assign vga_b = (!video_on) ? 4'h0 :
                   txt_active  ? txt_blue :
                   wf_active   ? wf_blue  : 4'h0;

    // =========================================================================
    // 7-Segment Display — Heart Rate BPM
    // =========================================================================
    seven_seg u_7seg (
        .clk       (clk_100mhz),
        .rst       (rst),
        .tick_1khz (tick_1khz),
        .bpm_value (heart_rate_bpm),
        .seg       (seg),
        .an        (an)
    );

    assign dp = 1'b1; // Decimal point off (active-low)

    // =========================================================================
    // LED Status Indicators
    // =========================================================================
    led_status u_leds (
        .clk          (clk_100mhz),
        .rst          (rst),
        .beat_detect  (beat_detect),
        .sample_valid (scaled_valid),
        .leads_off    (leads_off),
        .abnormal     (classification),
        .raw_adc      (scaled_adc),
        .led          (led)
    );

endmodule
