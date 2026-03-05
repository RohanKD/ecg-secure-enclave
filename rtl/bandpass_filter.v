//============================================================================
// bandpass_filter.v
// IIR bandpass filter for QRS isolation (5-15 Hz) at 500 Hz sampling rate.
//
// Architecture: First-order IIR HPF (fc ~5 Hz) cascaded with first-order
// IIR LPF (fc ~15 Hz). Uses 8-bit fractional fixed-point (scale = 256).
//
// HPF: y[n] = alpha_hp * (y[n-1] + x[n] - x[n-1])
//      alpha_hp = 248/256  (~0.969, fc ~5 Hz at 500 Hz Fs)
//
// LPF: y[n] = (1 - alpha_lp) * x[n] + alpha_lp * y[n-1]
//      alpha_lp = 233/256  (~0.910, fc ~15 Hz at 500 Hz Fs)
//
// Target: Xilinx Artix-7 (Basys 3), 16-bit signed fixed-point throughout.
//============================================================================

module bandpass_filter (
    input  wire        clk,
    input  wire        rst,
    input  wire signed [15:0] din,
    input  wire        din_valid,
    output reg  signed [15:0] dout,
    output reg         dout_valid
);

    // ---------------------------------------------------------------
    // Coefficients (8-bit fractional, scale factor = 256)
    // ---------------------------------------------------------------
    localparam signed [8:0] ALPHA_HP = 9'sd248;   // 248/256 ~ 0.969
    localparam signed [8:0] ALPHA_LP = 9'sd233;   // 233/256 ~ 0.910
    localparam signed [8:0] ONE_MINUS_ALPHA_LP = 9'sd23; // (256 - 233)/256

    // ---------------------------------------------------------------
    // HPF state registers
    // ---------------------------------------------------------------
    reg signed [15:0] hp_x_prev;     // x[n-1] for HPF
    reg signed [15:0] hp_y_prev;     // y[n-1] for HPF (Q8 scaled removed)

    // ---------------------------------------------------------------
    // LPF state registers
    // ---------------------------------------------------------------
    reg signed [15:0] lp_y_prev;     // y[n-1] for LPF

    // ---------------------------------------------------------------
    // Pipeline stage registers
    // ---------------------------------------------------------------
    // Stage 1: HPF computation
    reg signed [15:0] hp_diff;       // x[n] - x[n-1]
    reg        stage1_valid;

    // Stage 2: HPF multiply and accumulate
    reg signed [31:0] hp_sum_scaled; // alpha * (y_prev + diff), full precision
    reg        stage2_valid;

    // Stage 3: HPF output / LPF input
    reg signed [15:0] hp_out;        // HPF output, truncated
    reg        stage3_valid;

    // Stage 4: LPF computation
    reg signed [31:0] lp_term_new;   // (1 - alpha_lp) * hp_out
    reg signed [31:0] lp_term_old;   // alpha_lp * lp_y_prev
    reg        stage4_valid;

    // ---------------------------------------------------------------
    // Stage 1: Compute HPF difference x[n] - x[n-1]
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            hp_diff      <= 16'sd0;
            stage1_valid <= 1'b0;
            hp_x_prev    <= 16'sd0;
        end else begin
            stage1_valid <= din_valid;
            if (din_valid) begin
                hp_diff   <= din - hp_x_prev;
                hp_x_prev <= din;
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 2: HPF multiply: alpha_hp * (y[n-1] + diff)
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            hp_sum_scaled <= 32'sd0;
            stage2_valid  <= 1'b0;
        end else begin
            stage2_valid <= stage1_valid;
            if (stage1_valid) begin
                hp_sum_scaled <= ALPHA_HP * (hp_y_prev + hp_diff);
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 3: HPF output truncation (>> 8 to remove scale of 256)
    //          and state update
    // ---------------------------------------------------------------
    wire signed [15:0] hp_result = hp_sum_scaled[23:8]; // Arithmetic right shift by 8

    always @(posedge clk) begin
        if (rst) begin
            hp_out       <= 16'sd0;
            stage3_valid <= 1'b0;
            hp_y_prev    <= 16'sd0;
        end else begin
            stage3_valid <= stage2_valid;
            if (stage2_valid) begin
                hp_out    <= hp_result;
                hp_y_prev <= hp_result;
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 4: LPF computation
    //   y[n] = (1 - alpha_lp) * x[n] + alpha_lp * y[n-1]
    //   Both terms computed in parallel
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            lp_term_new  <= 32'sd0;
            lp_term_old  <= 32'sd0;
            stage4_valid <= 1'b0;
        end else begin
            stage4_valid <= stage3_valid;
            if (stage3_valid) begin
                lp_term_new <= ONE_MINUS_ALPHA_LP * hp_out;
                lp_term_old <= ALPHA_LP * lp_y_prev;
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 5 (output): LPF truncation and state update
    // ---------------------------------------------------------------
    wire signed [31:0] lp_sum    = lp_term_new + lp_term_old;
    wire signed [15:0] lp_result = lp_sum[23:8]; // >> 8

    always @(posedge clk) begin
        if (rst) begin
            dout       <= 16'sd0;
            dout_valid <= 1'b0;
            lp_y_prev  <= 16'sd0;
        end else begin
            dout_valid <= stage4_valid;
            if (stage4_valid) begin
                dout      <= lp_result;
                lp_y_prev <= lp_result;
            end
        end
    end

endmodule
