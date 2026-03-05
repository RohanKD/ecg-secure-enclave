//============================================================================
// derivative_filter.v
// 5-point derivative filter for Pan-Tompkins QRS detection algorithm.
//
// Transfer function (causal form):
//   y[n] = (-x[n-4] - 2*x[n-3] + 2*x[n-1] + x[n]) / 8
//
// Implementation: 5-stage shift register, combinational multiply-accumulate,
// output registered. Division by 8 via arithmetic right shift (>>>3).
//
// Target: Xilinx Artix-7 (Basys 3), 16-bit signed fixed-point.
//============================================================================

module derivative_filter (
    input  wire        clk,
    input  wire        rst,
    input  wire signed [15:0] din,
    input  wire        din_valid,
    output reg  signed [15:0] dout,
    output reg         dout_valid
);

    // ---------------------------------------------------------------
    // Shift register: x[n], x[n-1], x[n-2], x[n-3], x[n-4]
    // ---------------------------------------------------------------
    reg signed [15:0] sr [0:4];
    integer i;

    // ---------------------------------------------------------------
    // Pipeline registers
    // ---------------------------------------------------------------
    // Stage 1: register the shift register outputs for timing
    reg signed [17:0] sum_stage1; // Needs extra bits for accumulation
    reg        stage1_valid;

    // ---------------------------------------------------------------
    // Fill count to ensure we have 5 valid samples before producing
    // first output
    // ---------------------------------------------------------------
    reg [2:0] fill_count;
    wire      pipeline_ready = (fill_count >= 3'd4);

    // ---------------------------------------------------------------
    // Shift register update
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 5; i = i + 1)
                sr[i] <= 16'sd0;
            fill_count <= 3'd0;
        end else if (din_valid) begin
            sr[0] <= din;
            sr[1] <= sr[0];
            sr[2] <= sr[1];
            sr[3] <= sr[2];
            sr[4] <= sr[3];
            if (fill_count < 3'd4)
                fill_count <= fill_count + 3'd1;
        end
    end

    // ---------------------------------------------------------------
    // Stage 1: Compute weighted sum
    //   sum = -x[n-4] - 2*x[n-3] + 2*x[n-1] + x[n]
    //   x[n-2] has coefficient 0, so it is unused.
    // ---------------------------------------------------------------
    wire signed [16:0] two_sr1 = {sr[1][15], sr[1], 1'b0}; // 2 * x[n-1] (sign-extended shift left)
    wire signed [16:0] two_sr3 = {sr[3][15], sr[3], 1'b0}; // 2 * x[n-3]

    always @(posedge clk) begin
        if (rst) begin
            sum_stage1   <= 18'sd0;
            stage1_valid <= 1'b0;
        end else begin
            stage1_valid <= din_valid & pipeline_ready;
            if (din_valid) begin
                // Full precision sum before division
                sum_stage1 <= ({sr[0][15], sr[0][15], sr[0]})     // + x[n]
                            + ({two_sr1[16], two_sr1})             // + 2*x[n-1]
                            - ({two_sr3[16], two_sr3})             // - 2*x[n-3]
                            - ({sr[4][15], sr[4][15], sr[4]});     // - x[n-4]
            end
        end
    end

    // ---------------------------------------------------------------
    // Stage 2 (output): Divide by 8 (arithmetic right shift by 3)
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            dout       <= 16'sd0;
            dout_valid <= 1'b0;
        end else begin
            dout_valid <= stage1_valid;
            if (stage1_valid) begin
                dout <= sum_stage1[17:3]; // >>> 3 for signed, taking bits [17:3] preserves sign
            end
        end
    end

endmodule
