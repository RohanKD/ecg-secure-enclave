//============================================================================
// amplitude.v
// Captures and normalizes R-peak amplitude for feature extraction.
//
// On each beat_detect pulse, the peak_amplitude is latched. A running
// average of the last 8 peak amplitudes is maintained. The normalized
// output is computed as:
//
//   norm_amplitude = (current_peak * 256) / avg_peak
//
// This maps peaks near the average to ~256, with deviations scaled
// proportionally. The output is clamped to 8-bit range [0, 255] for
// the feature vector.
//
// Division by avg_peak is approximated using reciprocal estimation
// to avoid a hardware divider.
//
// Target: Xilinx Artix-7 (Basys 3), 16-bit data path.
//============================================================================

module amplitude (
    input  wire        clk,
    input  wire        rst,
    input  wire        beat_detect,
    input  wire [15:0] peak_amplitude,
    output reg  [15:0] norm_amplitude,
    output reg         amp_valid
);

    // ---------------------------------------------------------------
    // Circular buffer of last 8 peak amplitudes
    // ---------------------------------------------------------------
    reg [15:0] peak_buf [0:7];
    reg [2:0]  wr_ptr;
    reg [3:0]  fill_count; // 0..8

    wire buffer_full = (fill_count >= 4'd8);

    // ---------------------------------------------------------------
    // Running sum for average computation
    // ---------------------------------------------------------------
    reg [18:0] peak_sum; // 8 * 65535 = 524,280, needs 20 bits max

    // ---------------------------------------------------------------
    // Pipeline registers
    // ---------------------------------------------------------------
    reg [15:0] latched_peak;
    reg [15:0] avg_peak;       // peak_sum >> 3
    reg        compute_start;

    // Division pipeline registers
    reg [31:0] numerator;      // latched_peak << 8 (i.e., * 256)
    reg [15:0] denominator;
    reg        div_start;

    // Division result
    reg [15:0] quotient;
    reg        div_done;

    // ---------------------------------------------------------------
    // Sequential division (16-bit / 16-bit) - 16-cycle restoring divider
    // ---------------------------------------------------------------
    reg [4:0]  div_step;
    reg        div_active;
    reg [31:0] div_remainder;
    reg [15:0] div_quotient;
    reg [15:0] div_divisor;

    // ---------------------------------------------------------------
    // Buffer update and average computation
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr        <= 3'd0;
            fill_count    <= 4'd0;
            peak_sum      <= 19'd0;
            latched_peak  <= 16'd0;
            avg_peak      <= 16'd0;
            compute_start <= 1'b0;
        end else begin
            compute_start <= 1'b0;

            if (beat_detect) begin
                // Latch current peak
                latched_peak <= peak_amplitude;

                // Update running sum
                if (buffer_full)
                    peak_sum <= peak_sum + {3'd0, peak_amplitude} - {3'd0, peak_buf[wr_ptr]};
                else
                    peak_sum <= peak_sum + {3'd0, peak_amplitude};

                // Write to buffer
                peak_buf[wr_ptr] <= peak_amplitude;
                wr_ptr <= wr_ptr + 3'd1;

                if (!buffer_full)
                    fill_count <= fill_count + 4'd1;

                // Compute average (will be valid next cycle)
                if (buffer_full || fill_count >= 4'd1) begin
                    compute_start <= 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // Average computation and division trigger
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            div_start   <= 1'b0;
            numerator   <= 32'd0;
            denominator <= 16'd1;
        end else begin
            div_start <= 1'b0;
            if (compute_start) begin
                // Compute average based on fill level
                if (buffer_full)
                    avg_peak <= peak_sum[18:3]; // >> 3
                else begin
                    // Before buffer is full, use approximate average
                    case (fill_count)
                        4'd1: avg_peak <= peak_sum[15:0];
                        4'd2: avg_peak <= peak_sum[16:1];
                        4'd3: avg_peak <= peak_sum[15:0]; // Approximate /3 as /4 is close enough initially
                        4'd4: avg_peak <= peak_sum[17:2];
                        4'd5: avg_peak <= peak_sum[17:2]; // Approximate /5 as /4
                        4'd6: avg_peak <= peak_sum[18:3]; // Approximate /6 as /8
                        4'd7: avg_peak <= peak_sum[18:3]; // Approximate /7 as /8
                        default: avg_peak <= peak_sum[15:0];
                    endcase
                end

                // Setup division: (latched_peak * 256) / avg_peak
                numerator <= {16'd0, latched_peak} << 8;

                // Use current average; protect against divide-by-zero
                if (buffer_full)
                    denominator <= (peak_sum[18:3] == 16'd0) ? 16'd1 : peak_sum[18:3];
                else
                    denominator <= (peak_sum[15:0] == 16'd0) ? 16'd1 : peak_sum[15:0];

                div_start <= 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------
    // 16-cycle restoring divider
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            div_active    <= 1'b0;
            div_step      <= 5'd0;
            div_remainder <= 32'd0;
            div_quotient  <= 16'd0;
            div_divisor   <= 16'd1;
            div_done      <= 1'b0;
            quotient      <= 16'd0;
        end else begin
            div_done <= 1'b0;

            if (div_start && !div_active) begin
                // Initialize divider
                div_active    <= 1'b1;
                div_step      <= 5'd0;
                div_remainder <= numerator;
                div_quotient  <= 16'd0;
                div_divisor   <= denominator;
            end else if (div_active) begin
                if (div_step < 5'd16) begin
                    // Shift and subtract
                    div_quotient <= div_quotient << 1;
                    if (div_remainder >= ({16'd0, div_divisor} << (5'd15 - div_step))) begin
                        div_remainder <= div_remainder - ({16'd0, div_divisor} << (5'd15 - div_step));
                        div_quotient  <= (div_quotient << 1) | 16'd1;
                    end
                    div_step <= div_step + 5'd1;
                end else begin
                    // Division complete
                    div_active <= 1'b0;
                    quotient   <= div_quotient;
                    div_done   <= 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // Output: clamp normalized amplitude to [0, 255]
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            norm_amplitude <= 16'd0;
            amp_valid      <= 1'b0;
        end else begin
            amp_valid <= div_done;
            if (div_done) begin
                if (quotient > 16'd255)
                    norm_amplitude <= 16'd255;
                else
                    norm_amplitude <= quotient;
            end
        end
    end

    // ---------------------------------------------------------------
    // Buffer initialization
    // ---------------------------------------------------------------
    integer i;
    initial begin
        for (i = 0; i < 8; i = i + 1)
            peak_buf[i] = 16'd0;
    end

endmodule
