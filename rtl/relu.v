//////////////////////////////////////////////////////////////////////////////
// relu.v
// Rectified Linear Unit (ReLU) Activation Function
//
// Combinational module implementing ReLU for signed fixed-point values.
//   dout = (din >= 0) ? din : 0
//
// For signed two's complement, the sign bit (MSB) directly indicates
// whether the value is negative.
//
// Data format: 16-bit signed (Q6.10 from MAC unit output).
// Latency: 0 cycles (purely combinational).
//
// Target: Xilinx Artix-7 (Basys 3)
//////////////////////////////////////////////////////////////////////////////

module relu (
    input  wire signed [15:0] din,
    input  wire               din_valid,
    output wire signed [15:0] dout,
    output wire               dout_valid
);

    // If sign bit is set (negative), output zero; otherwise pass through.
    assign dout      = din[15] ? 16'sd0 : din;
    assign dout_valid = din_valid;

endmodule
