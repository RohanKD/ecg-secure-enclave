// ============================================================================
// font_rom.v
// 8x16 ASCII font ROM for VGA text rendering
// Basys 3 / Artix-7 FPGA
//
// Stores bitmap data for 95 printable ASCII characters (codes 32-126).
// Each character: 8 pixels wide x 16 pixels tall = 16 bytes per character.
// Total: 95 * 16 = 1520 bytes (padded to 2048 for power-of-2 addressing).
//
// Address calculation: addr = (char_code - 32) * 16 + row
// Data output: 8-bit row bitmap, MSB = leftmost pixel.
//
// Initialized from external hex file: font_8x16.mem
// ============================================================================

module font_rom (
    input  wire        clk,
    input  wire [10:0] addr,   // Up to 2048 entries
    output reg  [7:0]  data    // 8-bit row bitmap
);

    // -----------------------------------------------------------------------
    // ROM storage: 2048 x 8-bit
    // -----------------------------------------------------------------------
    reg [7:0] rom [0:2047];

    // -----------------------------------------------------------------------
    // Initialize ROM from hex memory file
    // -----------------------------------------------------------------------
    initial begin
        $readmemh("font_8x16.mem", rom);
    end

    // -----------------------------------------------------------------------
    // Synchronous read (infers block RAM on Artix-7)
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        data <= rom[addr];
    end

endmodule
