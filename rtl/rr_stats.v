//============================================================================
// rr_stats.v
// Maintains a circular buffer of the last 8 RR intervals and computes:
//   - mean_rr:         Average of 8 intervals (sum >> 3)
//   - rr_variability:  max(RR) - min(RR) over the 8-beat window
//
// The stats_valid output pulses high for one clock cycle when updated
// statistics are available (after each new RR interval is added, once
// the buffer has been filled with at least 8 intervals).
//
// Target: Xilinx Artix-7 (Basys 3), 16-bit unsigned data path.
//============================================================================

module rr_stats (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] rr_interval,
    input  wire        rr_valid,
    output reg  [15:0] mean_rr,
    output reg  [15:0] rr_variability,
    output reg         stats_valid
);

    // ---------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------
    localparam BUFFER_DEPTH = 8;
    localparam PTR_WIDTH    = 3; // log2(8)

    // ---------------------------------------------------------------
    // Circular buffer of 8 RR intervals
    // ---------------------------------------------------------------
    reg [15:0] rr_buf [0:BUFFER_DEPTH-1];
    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [3:0] fill_count; // 0..8

    wire buffer_full = (fill_count >= 4'd8);

    // ---------------------------------------------------------------
    // Running sum for mean calculation
    // ---------------------------------------------------------------
    reg [18:0] rr_sum; // 19 bits: 8 * 65535 = 524,280 (needs 20 bits max, 19 safe for typical)

    // ---------------------------------------------------------------
    // Pipeline for min/max computation
    //   Compute min and max over the 8-element buffer sequentially.
    //   Since buffer is small (8 entries), use a 3-stage pipeline
    //   with parallel comparisons.
    // ---------------------------------------------------------------

    // Stage control
    reg       compute_active;
    reg [2:0] compute_step;

    // Min/max accumulators
    reg [15:0] cur_min;
    reg [15:0] cur_max;

    // Temporary pair-wise results (stage 1: 4 pairs -> 4 results each)
    reg [15:0] min_01, min_23, min_45, min_67;
    reg [15:0] max_01, max_23, max_45, max_67;

    // Stage 2 results
    reg [15:0] min_03, min_47;
    reg [15:0] max_03, max_47;

    // Pipeline valid tracking
    reg stage1_valid_r, stage2_valid_r, stage3_valid_r;

    // ---------------------------------------------------------------
    // Buffer write and sum update
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr     <= 3'd0;
            fill_count <= 4'd0;
            rr_sum     <= 19'd0;
        end else if (rr_valid) begin
            // Update running sum: add new, subtract oldest (if buffer full)
            if (buffer_full)
                rr_sum <= rr_sum + {3'd0, rr_interval} - {3'd0, rr_buf[wr_ptr]};
            else
                rr_sum <= rr_sum + {3'd0, rr_interval};

            // Write new interval
            rr_buf[wr_ptr] <= rr_interval;

            // Advance pointer
            wr_ptr <= wr_ptr + 3'd1; // Wraps naturally for 3-bit

            // Track fill
            if (!buffer_full)
                fill_count <= fill_count + 4'd1;
        end
    end

    // ---------------------------------------------------------------
    // Min/Max pipeline: 3-stage parallel comparison tree
    // ---------------------------------------------------------------

    // Stage 1: Pair-wise comparisons (4 pairs)
    always @(posedge clk) begin
        if (rst) begin
            min_01 <= 16'hFFFF; min_23 <= 16'hFFFF;
            min_45 <= 16'hFFFF; min_67 <= 16'hFFFF;
            max_01 <= 16'h0000; max_23 <= 16'h0000;
            max_45 <= 16'h0000; max_67 <= 16'h0000;
            stage1_valid_r <= 1'b0;
        end else begin
            stage1_valid_r <= rr_valid & buffer_full;
            if (rr_valid & buffer_full) begin
                // Compare pairs
                min_01 <= (rr_buf[0] < rr_buf[1]) ? rr_buf[0] : rr_buf[1];
                max_01 <= (rr_buf[0] > rr_buf[1]) ? rr_buf[0] : rr_buf[1];

                min_23 <= (rr_buf[2] < rr_buf[3]) ? rr_buf[2] : rr_buf[3];
                max_23 <= (rr_buf[2] > rr_buf[3]) ? rr_buf[2] : rr_buf[3];

                min_45 <= (rr_buf[4] < rr_buf[5]) ? rr_buf[4] : rr_buf[5];
                max_45 <= (rr_buf[4] > rr_buf[5]) ? rr_buf[4] : rr_buf[5];

                min_67 <= (rr_buf[6] < rr_buf[7]) ? rr_buf[6] : rr_buf[7];
                max_67 <= (rr_buf[6] > rr_buf[7]) ? rr_buf[6] : rr_buf[7];
            end
        end
    end

    // Stage 2: Quad-wise comparisons (2 pairs of pairs)
    always @(posedge clk) begin
        if (rst) begin
            min_03 <= 16'hFFFF; min_47 <= 16'hFFFF;
            max_03 <= 16'h0000; max_47 <= 16'h0000;
            stage2_valid_r <= 1'b0;
        end else begin
            stage2_valid_r <= stage1_valid_r;
            if (stage1_valid_r) begin
                min_03 <= (min_01 < min_23) ? min_01 : min_23;
                max_03 <= (max_01 > max_23) ? max_01 : max_23;

                min_47 <= (min_45 < min_67) ? min_45 : min_67;
                max_47 <= (max_45 > max_67) ? max_45 : max_67;
            end
        end
    end

    // Stage 3: Final comparison and output
    always @(posedge clk) begin
        if (rst) begin
            cur_min        <= 16'hFFFF;
            cur_max        <= 16'h0000;
            stage3_valid_r <= 1'b0;
        end else begin
            stage3_valid_r <= stage2_valid_r;
            if (stage2_valid_r) begin
                cur_min <= (min_03 < min_47) ? min_03 : min_47;
                cur_max <= (max_03 > max_47) ? max_03 : max_47;
            end
        end
    end

    // ---------------------------------------------------------------
    // Output registration
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            mean_rr        <= 16'd0;
            rr_variability <= 16'd0;
            stats_valid    <= 1'b0;
        end else begin
            stats_valid <= stage3_valid_r;
            if (stage3_valid_r) begin
                // Mean: sum / 8 = sum >> 3
                mean_rr <= rr_sum[18:3];

                // Variability: max - min
                rr_variability <= cur_max - cur_min;
            end
        end
    end

    // ---------------------------------------------------------------
    // Buffer initialization
    // ---------------------------------------------------------------
    integer i;
    initial begin
        for (i = 0; i < BUFFER_DEPTH; i = i + 1)
            rr_buf[i] = 16'd0;
    end

endmodule
