//============================================================================
// moving_avg.v
// Moving window integrator for Pan-Tompkins QRS detection.
//
// Window size: 75 samples (150 ms at 500 Hz Fs).
// Implements a running-sum circular buffer approach:
//   sum = sum + new_sample - oldest_sample
//   output = sum >> 6  (approximation of /75 using /64)
//
// The circular buffer is implemented in distributed RAM (75 x 16-bit).
// The running sum uses 22 bits to prevent overflow:
//   max sum = 75 * 65535 = 4,915,125 which fits in 23 bits.
//
// Target: Xilinx Artix-7 (Basys 3), 16-bit unsigned data path.
//============================================================================

module moving_avg (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] din,
    input  wire        din_valid,
    output reg  [15:0] dout,
    output reg         dout_valid
);

    // ---------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------
    localparam WINDOW_SIZE = 75;
    localparam PTR_WIDTH   = 7; // ceil(log2(75)) = 7

    // ---------------------------------------------------------------
    // Circular buffer (distributed RAM on Artix-7)
    // ---------------------------------------------------------------
    reg [15:0] buffer [0:WINDOW_SIZE-1];
    reg [PTR_WIDTH-1:0] wr_ptr;

    // ---------------------------------------------------------------
    // Running sum accumulator (23 bits safe for 75 * 16-bit unsigned)
    // ---------------------------------------------------------------
    reg [22:0] running_sum;

    // ---------------------------------------------------------------
    // Fill counter: track how many samples have been loaded
    // ---------------------------------------------------------------
    reg [PTR_WIDTH-1:0] fill_count;
    wire buffer_full = (fill_count == WINDOW_SIZE[PTR_WIDTH-1:0]);

    // ---------------------------------------------------------------
    // Pipeline registers
    // ---------------------------------------------------------------
    reg [15:0] oldest_sample;
    reg        stage1_valid;
    reg [15:0] din_delayed;

    // ---------------------------------------------------------------
    // Stage 1: Read oldest sample from buffer, register new input
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            oldest_sample <= 16'd0;
            din_delayed   <= 16'd0;
            stage1_valid  <= 1'b0;
        end else begin
            stage1_valid <= din_valid;
            if (din_valid) begin
                oldest_sample <= buffer_full ? buffer[wr_ptr] : 16'd0;
                din_delayed   <= din;
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 2: Update running sum, write new sample, advance pointer
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            running_sum <= 23'd0;
            wr_ptr      <= {PTR_WIDTH{1'b0}};
            fill_count  <= {PTR_WIDTH{1'b0}};
            dout        <= 16'd0;
            dout_valid  <= 1'b0;
        end else begin
            dout_valid <= stage1_valid;
            if (stage1_valid) begin
                // Update running sum: add new, subtract oldest
                running_sum <= running_sum + {7'd0, din_delayed} - {7'd0, oldest_sample};

                // Write new sample into circular buffer
                buffer[wr_ptr] <= din_delayed;

                // Advance write pointer with wrap-around
                if (wr_ptr == WINDOW_SIZE - 1)
                    wr_ptr <= {PTR_WIDTH{1'b0}};
                else
                    wr_ptr <= wr_ptr + {{(PTR_WIDTH-1){1'b0}}, 1'b1};

                // Track fill level
                if (!buffer_full)
                    fill_count <= fill_count + {{(PTR_WIDTH-1){1'b0}}, 1'b1};

                // Output: approximate divide by 75 using >>6 (/64)
                // Use the *updated* sum (combinational feed-forward)
                dout <= (running_sum + {7'd0, din_delayed} - {7'd0, oldest_sample}) >> 6;
            end
        end
    end

    // ---------------------------------------------------------------
    // Buffer initialization
    // ---------------------------------------------------------------
    integer k;
    initial begin
        for (k = 0; k < WINDOW_SIZE; k = k + 1)
            buffer[k] = 16'd0;
    end

endmodule
