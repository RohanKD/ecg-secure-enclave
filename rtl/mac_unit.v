//////////////////////////////////////////////////////////////////////////////
// mac_unit.v
// Multiply-Accumulate Unit for MLP Neural Network
//
// Performs sequential MAC operations for a single neuron.
// Arithmetic: Q3.5 signed fixed-point (8-bit).
//   - Inputs a, b are Q3.5 => product is Q6.10 (16-bit signed).
//   - Accumulator is 24-bit signed to prevent overflow when summing
//     up to 10 products (need ~4 extra bits beyond 16).
//   - Bias is Q3.5 (8-bit), left-shifted by 10 to align with Q6.10
//     accumulated scale before addition (bias <<< 10, not 5, because
//     the accumulator holds Q6.10 values).
//   - Result output is the full 16-bit truncation of the 24-bit
//     accumulator for downstream ReLU / further processing.
//
// Target: Xilinx Artix-7 (Basys 3)
//////////////////////////////////////////////////////////////////////////////

module mac_unit (
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,              // Clear accumulator to zero
    input  wire signed [7:0]  a,           // Input activation  (Q3.5)
    input  wire signed [7:0]  b,           // Weight             (Q3.5)
    input  wire        valid,              // MAC enable: acc += a * b
    input  wire signed [7:0]  bias,        // Bias value         (Q3.5)
    input  wire        add_bias,           // Add bias and produce result
    output reg  signed [15:0] result,      // Accumulated result (Q6.10 truncated)
    output reg         result_valid        // Pulses high for one cycle when result ready
);

    // 24-bit signed accumulator — sufficient for 10 Q6.10 products
    // Max magnitude per product: ~4.0 * 4.0 = 16.0 => Q6.10 = 16384
    // Sum of 10: 163840, fits in 18 bits unsigned / 19 bits signed.
    // 24 bits provides comfortable headroom.
    reg signed [23:0] acc;

    // 16-bit signed product of two Q3.5 operands => Q6.10
    wire signed [15:0] product;
    assign product = a * b;

    // Bias aligned to Q6.10: shift left by 10 (5 fractional bits of
    // each operand contribute 10 fractional bits in the product domain).
    wire signed [23:0] bias_aligned;
    assign bias_aligned = {{6{bias[7]}}, bias, 10'b0};  // sign-extend then shift

    always @(posedge clk) begin
        if (rst) begin
            acc          <= 24'sd0;
            result       <= 16'sd0;
            result_valid <= 1'b0;
        end else begin
            // Default: de-assert result_valid after one cycle
            result_valid <= 1'b0;

            if (clear) begin
                acc <= 24'sd0;
            end else if (valid) begin
                // Accumulate: acc += a * b  (sign-extend product to 24 bits)
                acc <= acc + {{8{product[15]}}, product};
            end else if (add_bias) begin
                // Add aligned bias, latch result, and signal valid
                // Truncate 24-bit accumulator to 16-bit output (keep lower
                // 16 bits which represent Q6.10 with possible saturation).
                // We saturate to prevent wrap-around.
                result       <= saturate_16(acc + bias_aligned);
                result_valid <= 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------
    // Saturation function: clamp 24-bit value to signed 16-bit range
    // ---------------------------------------------------------------
    function signed [15:0] saturate_16;
        input signed [23:0] val;
        begin
            if (val > 24'sd32767)
                saturate_16 = 16'sd32767;       // positive saturation
            else if (val < -24'sd32768)
                saturate_16 = -16'sd32768;       // negative saturation
            else
                saturate_16 = val[15:0];
        end
    endfunction

endmodule
