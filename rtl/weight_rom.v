//////////////////////////////////////////////////////////////////////////////
// weight_rom.v
// Weight / Bias ROM for MLP Neural Network
//
// Stores pre-trained quantized weights and biases for a two-layer MLP:
//   Layer 1: 10 inputs x 8 neurons = 80 weights + 8 biases  =  88 values
//   Layer 2:  8 inputs x 2 neurons = 16 weights + 2 biases  =  18 values
//   Total: 106 x 8-bit signed values (Q3.5 fixed-point)
//
// Memory map (linear addressing):
//   Addr  0 -  9 : Layer 1, neuron 0 weights (input 0..9)
//   Addr 10 - 19 : Layer 1, neuron 1 weights
//   ...
//   Addr 70 - 79 : Layer 1, neuron 7 weights
//   Addr 80 - 87 : Layer 1 biases (neuron 0..7)
//   Addr 88 - 95 : Layer 2, neuron 0 weights (hidden 0..7)
//   Addr 96 -103 : Layer 2, neuron 1 weights (hidden 0..7)
//   Addr104 -105 : Layer 2 biases (neuron 0, neuron 1)
//
// Initialized from external file: weights.mem ($readmemh)
// One registered read port (1-cycle latency).
//
// Target: Xilinx Artix-7 (Basys 3)
//////////////////////////////////////////////////////////////////////////////

module weight_rom (
    input  wire       clk,
    input  wire [6:0] addr,            // 0 .. 105 (7 bits covers 0..127)
    output reg  signed [7:0] data
);

    // 128-entry ROM (only 106 used; remaining entries are don't-care)
    reg [7:0] rom [0:127];

    // Initialize from hex memory file
    initial begin
        $readmemh("weights.mem", rom);
    end

    // Synchronous read — infers block RAM or distributed ROM on Artix-7
    always @(posedge clk) begin
        data <= rom[addr];
    end

endmodule
