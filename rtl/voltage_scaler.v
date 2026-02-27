//////////////////////////////////////////////////////////////////////////////
// voltage_scaler.v
// Compensates for external 20k/10k voltage divider (1/3 attenuation)
//
// The ADC reads 1/3 of the actual signal voltage due to the resistive
// divider on the AD8232 output. This module multiplies by 3 using
// shift-and-add:  out = (in << 1) + in = in * 3
//
// Output is clamped to 12 bits (4095) to avoid wrap-around.
// Pipeline: 1 clock cycle latency.
//////////////////////////////////////////////////////////////////////////////

module voltage_scaler(
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] raw_adc,
    input  wire        raw_valid,
    output reg  [11:0] scaled_adc,
    output reg         scaled_valid
);

    // 12-bit input * 3 can be at most 12285 (4095 * 3), which needs 14 bits.
    wire [13:0] product;

    assign product = {raw_adc, 1'b0} + {2'b00, raw_adc};  // (raw << 1) + raw

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scaled_adc   <= 12'd0;
            scaled_valid <= 1'b0;
        end else begin
            scaled_valid <= raw_valid;

            if (raw_valid) begin
                // Clamp to 12-bit maximum
                if (product > 14'd4095) begin
                    scaled_adc <= 12'hFFF;
                end else begin
                    scaled_adc <= product[11:0];
                end
            end
        end
    end

endmodule
