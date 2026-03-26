// ============================================================================
// vga_controller.v
// Standard 640x480 @ 60Hz VGA sync generator
// Basys 3 / Artix-7 FPGA
//
// Uses a 25MHz pixel clock enable derived from the 100MHz system clock.
// Generates hsync, vsync (active-low), pixel coordinates, and video_on.
//
// Horizontal timing (pixels @ 25MHz):
//   Visible:     640
//   Front porch:  16
//   Sync pulse:   96
//   Back porch:   48
//   Total:       800
//
// Vertical timing (lines):
//   Visible:     480
//   Front porch:  10
//   Sync pulse:    2
//   Back porch:   33
//   Total:       525
// ============================================================================

module vga_controller (
    input  wire       clk,          // 100MHz system clock
    input  wire       rst,
    input  wire       clk_25mhz_en, // 25MHz pixel clock enable (1 in 4)
    output reg  [9:0] pixel_x,      // Current pixel X (0-799)
    output reg  [9:0] pixel_y,      // Current pixel Y (0-524)
    output wire       video_on,     // High when in visible area
    output reg        hsync,
    output reg        vsync
);

    // -----------------------------------------------------------------------
    // Horizontal timing parameters
    // -----------------------------------------------------------------------
    localparam H_VISIBLE    = 10'd640;
    localparam H_FRONT      = 10'd16;
    localparam H_SYNC       = 10'd96;
    localparam H_BACK       = 10'd48;
    localparam H_TOTAL      = 10'd800;  // 640+16+96+48

    // -----------------------------------------------------------------------
    // Vertical timing parameters
    // -----------------------------------------------------------------------
    localparam V_VISIBLE    = 10'd480;
    localparam V_FRONT      = 10'd10;
    localparam V_SYNC       = 10'd2;
    localparam V_BACK       = 10'd33;
    localparam V_TOTAL      = 10'd525;  // 480+10+2+33

    // -----------------------------------------------------------------------
    // Sync pulse start / end positions
    // -----------------------------------------------------------------------
    localparam H_SYNC_START = H_VISIBLE + H_FRONT;         // 656
    localparam H_SYNC_END   = H_VISIBLE + H_FRONT + H_SYNC; // 752
    localparam V_SYNC_START = V_VISIBLE + V_FRONT;         // 490
    localparam V_SYNC_END   = V_VISIBLE + V_FRONT + V_SYNC; // 492

    // -----------------------------------------------------------------------
    // Horizontal counter
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            pixel_x <= 10'd0;
        end else if (clk_25mhz_en) begin
            if (pixel_x == H_TOTAL - 1)
                pixel_x <= 10'd0;
            else
                pixel_x <= pixel_x + 10'd1;
        end
    end

    // -----------------------------------------------------------------------
    // Vertical counter (increments at end of each horizontal line)
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            pixel_y <= 10'd0;
        end else if (clk_25mhz_en) begin
            if (pixel_x == H_TOTAL - 1) begin
                if (pixel_y == V_TOTAL - 1)
                    pixel_y <= 10'd0;
                else
                    pixel_y <= pixel_y + 10'd1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Horizontal sync (active-low)
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            hsync <= 1'b1;
        else if (clk_25mhz_en)
            hsync <= ~((pixel_x >= H_SYNC_START) && (pixel_x < H_SYNC_END));
    end

    // -----------------------------------------------------------------------
    // Vertical sync (active-low)
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            vsync <= 1'b1;
        else if (clk_25mhz_en)
            vsync <= ~((pixel_y >= V_SYNC_START) && (pixel_y < V_SYNC_END));
    end

    // -----------------------------------------------------------------------
    // Video-on signal: high when within the visible display area
    // -----------------------------------------------------------------------
    assign video_on = (pixel_x < H_VISIBLE) && (pixel_y < V_VISIBLE);

endmodule
