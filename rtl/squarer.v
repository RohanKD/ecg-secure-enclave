//============================================================================
// squarer.v
// Squares the derivative filter output for the Pan-Tompkins algorithm.
//
// y[n] = x[n] * x[n], scaled to 16 bits (unsigned).
//
// The input is 16-bit signed [-32768, +32767].
// The full product is 32-bit signed. Since x*x >= 0, the result is always
// non-negative. We take the upper 16 bits of the unsigned magnitude
// (right shift by 15) to preserve dynamic range while fitting in 16 bits.
//
// For 12-bit ECG data (sign-extended to 16-bit), derivative outputs are
// typically ±500. 500^2 = 250,000. We use >>8 to map this to ~976,
// preserving dynamic range for the moving average integrator.
// Saturation is applied to clamp at 16'hFFFF.
//
// Target: Xilinx Artix-7 (Basys 3) - will infer DSP48E1 slice.
//============================================================================

module squarer (
    input  wire        clk,
    input  wire        rst,
    input  wire signed [15:0] din,
    input  wire        din_valid,
    output reg  [15:0] dout,
    output reg         dout_valid
);

    // ---------------------------------------------------------------
    // Pipeline stage 1: Register input for DSP48 inference
    // ---------------------------------------------------------------
    reg signed [15:0] din_reg;
    reg        stage1_valid;

    always @(posedge clk) begin
        if (rst) begin
            din_reg      <= 16'sd0;
            stage1_valid <= 1'b0;
        end else begin
            stage1_valid <= din_valid;
            din_reg      <= din;
        end
    end

    // ---------------------------------------------------------------
    // Pipeline stage 2: Multiply (DSP48 inferred)
    // ---------------------------------------------------------------
    reg signed [31:0] product;
    reg        stage2_valid;

    always @(posedge clk) begin
        if (rst) begin
            product      <= 32'sd0;
            stage2_valid <= 1'b0;
        end else begin
            stage2_valid <= stage1_valid;
            product      <= din_reg * din_reg;
        end
    end

    // ---------------------------------------------------------------
    // Pipeline stage 3 (output): Scale and saturate
    //   product is always >= 0 (square of signed value).
    //   Right shift by 15 to map full-scale 16-bit input to 16-bit output.
    //   Saturate if the shifted result exceeds 16 bits.
    // ---------------------------------------------------------------
    wire [31:0] product_unsigned = product[31] ? 32'd0 : product; // Safety: force non-negative
    wire [16:0] scaled = product_unsigned[24:8]; // 17-bit after >>8

    always @(posedge clk) begin
        if (rst) begin
            dout       <= 16'd0;
            dout_valid <= 1'b0;
        end else begin
            dout_valid <= stage2_valid;
            if (stage2_valid) begin
                // Saturate to 16 bits
                if (scaled[16])
                    dout <= 16'hFFFF;
                else
                    dout <= scaled[15:0];
            end
        end
    end

endmodule
