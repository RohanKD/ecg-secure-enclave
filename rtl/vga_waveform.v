// ============================================================================
// vga_waveform.v
// Scrolling ECG waveform display on VGA
// Basys 3 / Artix-7 FPGA
//
// Uses a 640-sample circular buffer in block RAM (dual-port).
// Port A: write new ECG samples at the write pointer.
// Port B: read samples during VGA scan for rendering.
//
// Display parameters:
//   Waveform area: x = 0..639, y = 32..320 (288 pixels tall)
//   ECG input: 12-bit unsigned (0-4095)
//   Mapping:  y_pixel = 320 - (sample * 288 / 4096)
//             Simplification: y_pixel = 320 - (sample * 9 / 128)
//   Green waveform on black background
//   Vertical red cursor at the write pointer position
//   Light gray horizontal grid lines at 1/4, 1/2, 3/4 of waveform area
// ============================================================================

module vga_waveform (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] ecg_sample,     // New ECG sample to display
    input  wire        sample_valid,   // Write enable for new sample
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        video_on,
    output reg  [3:0]  wf_red,
    output reg  [3:0]  wf_green,
    output reg  [3:0]  wf_blue,
    output reg         wf_active       // 1 if this module is driving pixels
);

    // -----------------------------------------------------------------------
    // Waveform display area boundaries
    // -----------------------------------------------------------------------
    localparam WF_X_MIN  = 10'd0;
    localparam WF_X_MAX  = 10'd639;
    localparam WF_Y_MIN  = 10'd32;
    localparam WF_Y_MAX  = 10'd320;
    localparam WF_HEIGHT = 10'd288;  // 320 - 32

    // Grid line Y positions (1/4, 1/2, 3/4 of waveform area)
    localparam GRID_Y_1 = 10'd104;  // 32 + 72
    localparam GRID_Y_2 = 10'd176;  // 32 + 144
    localparam GRID_Y_3 = 10'd248;  // 32 + 216

    // Middle of waveform area (for initial fill)
    localparam WF_Y_MID = 9'd176;  // (32 + 320) / 2

    // -----------------------------------------------------------------------
    // Dual-port BRAM: 640 x 9-bit (stores mapped Y pixel position)
    // Port A: write new samples   Port B: read during VGA scan
    //
    // Xilinx synthesis will infer true dual-port BRAM when both ports
    // are in separate always blocks with independent addresses.
    // -----------------------------------------------------------------------
    reg [8:0] waveform_ram [0:639];

    integer i;
    initial begin
        for (i = 0; i < 640; i = i + 1)
            waveform_ram[i] = WF_Y_MID;
    end

    // -----------------------------------------------------------------------
    // Write pointer (circular buffer index, 0-639)
    // -----------------------------------------------------------------------
    reg [9:0] wr_ptr;

    always @(posedge clk) begin
        if (rst)
            wr_ptr <= 10'd0;
        else if (sample_valid) begin
            if (wr_ptr == 10'd639)
                wr_ptr <= 10'd0;
            else
                wr_ptr <= wr_ptr + 10'd1;
        end
    end

    // -----------------------------------------------------------------------
    // Map 12-bit ECG sample to Y pixel position within waveform area
    //
    // Target: y_offset = sample * 288 / 4096
    // Simplify: 288/4096 = 9/128
    //   y_offset = (sample * 9) >> 7
    // Then: y_pixel = 320 - y_offset
    //
    // Range check: sample=0 -> y=320 (bottom), sample=4095 -> y~32 (top)
    // -----------------------------------------------------------------------
    wire [15:0] sample_scaled;
    wire [8:0]  y_offset;
    wire [9:0]  y_mapped;

    assign sample_scaled = ecg_sample * 16'd9;   // max: 4095*9 = 36855 (fits 16 bits)
    assign y_offset      = sample_scaled[15:7];   // >> 7, max: 36855/128 = 287
    assign y_mapped      = WF_Y_MAX - {1'b0, y_offset};

    // -----------------------------------------------------------------------
    // Port A: Write mapped Y position into BRAM
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (sample_valid) begin
            waveform_ram[wr_ptr] <= y_mapped[8:0];
        end
    end

    // -----------------------------------------------------------------------
    // Port B: Read sample for current and previous pixel columns
    //
    // Pipeline stage 0: register read addresses
    // Pipeline stage 1: BRAM outputs registered data
    // Pipeline stage 2: use data for pixel decisions (registered output)
    //
    // We read two adjacent columns to draw connected vertical segments.
    // -----------------------------------------------------------------------
    reg [9:0] rd_addr_cur;
    reg [9:0] rd_addr_prev;
    reg [8:0] rd_data_cur;
    reg [8:0] rd_data_prev;

    // Stage 0: latch addresses
    always @(posedge clk) begin
        rd_addr_cur  <= pixel_x;
        rd_addr_prev <= (pixel_x > 10'd0) ? (pixel_x - 10'd1) : 10'd0;
    end

    // Stage 1: synchronous BRAM read
    always @(posedge clk) begin
        rd_data_cur  <= waveform_ram[rd_addr_cur];
        rd_data_prev <= waveform_ram[rd_addr_prev];
    end

    // -----------------------------------------------------------------------
    // Pipeline delay for pixel coordinates and control signals
    // Must match the 2-cycle BRAM read latency.
    // -----------------------------------------------------------------------
    reg [9:0] pixel_x_d1, pixel_x_d2;
    reg [9:0] pixel_y_d1, pixel_y_d2;
    reg       video_on_d1, video_on_d2;
    reg [9:0] wr_ptr_d1, wr_ptr_d2;

    always @(posedge clk) begin
        // Delay stage 1
        pixel_x_d1  <= pixel_x;
        pixel_y_d1  <= pixel_y;
        video_on_d1 <= video_on;
        wr_ptr_d1   <= wr_ptr;
        // Delay stage 2
        pixel_x_d2  <= pixel_x_d1;
        pixel_y_d2  <= pixel_y_d1;
        video_on_d2 <= video_on_d1;
        wr_ptr_d2   <= wr_ptr_d1;
    end

    // -----------------------------------------------------------------------
    // Waveform area detection (using delayed coordinates)
    // -----------------------------------------------------------------------
    wire in_waveform_area;
    assign in_waveform_area = (pixel_x_d2 <= WF_X_MAX) &&
                              (pixel_y_d2 >= WF_Y_MIN) &&
                              (pixel_y_d2 <= WF_Y_MAX);

    // -----------------------------------------------------------------------
    // Waveform drawing: connect adjacent samples with vertical segments
    //
    // For column X, draw from min(sample[X], sample[X-1]) to
    // max(sample[X], sample[X-1]). This creates a connected trace.
    // -----------------------------------------------------------------------
    wire [9:0] sample_y_cur  = {1'b0, rd_data_cur};
    wire [9:0] sample_y_prev = {1'b0, rd_data_prev};

    wire [9:0] y_lo = (sample_y_cur < sample_y_prev) ? sample_y_cur  : sample_y_prev;
    wire [9:0] y_hi = (sample_y_cur < sample_y_prev) ? sample_y_prev : sample_y_cur;

    // Draw the vertical segment connecting this sample to the previous one
    wire pixel_is_waveform;
    assign pixel_is_waveform = in_waveform_area &&
                               (pixel_x_d2 > 10'd0) &&
                               (pixel_y_d2 >= y_lo) &&
                               (pixel_y_d2 <= y_hi);

    // Also draw the exact sample point (for column 0 and single-pixel cases)
    wire pixel_is_point;
    assign pixel_is_point = in_waveform_area && (pixel_y_d2 == sample_y_cur);

    // -----------------------------------------------------------------------
    // Cursor: vertical red line at the write pointer position
    // -----------------------------------------------------------------------
    wire pixel_is_cursor;
    assign pixel_is_cursor = in_waveform_area && (pixel_x_d2 == wr_ptr_d2);

    // -----------------------------------------------------------------------
    // Grid lines: horizontal light gray lines at 1/4, 1/2, 3/4
    // -----------------------------------------------------------------------
    wire pixel_is_grid;
    assign pixel_is_grid = in_waveform_area &&
                           ((pixel_y_d2 == GRID_Y_1) ||
                            (pixel_y_d2 == GRID_Y_2) ||
                            (pixel_y_d2 == GRID_Y_3));

    // -----------------------------------------------------------------------
    // Border: top and bottom edges of the waveform area
    // -----------------------------------------------------------------------
    wire pixel_is_border;
    assign pixel_is_border = (pixel_x_d2 <= WF_X_MAX) &&
                             ((pixel_y_d2 == WF_Y_MIN) || (pixel_y_d2 == WF_Y_MAX));

    // -----------------------------------------------------------------------
    // Output pixel color and active signal
    //
    // Priority: cursor > waveform/point > grid > border > black background
    // All outputs are registered for clean timing.
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            wf_red    <= 4'h0;
            wf_green  <= 4'h0;
            wf_blue   <= 4'h0;
            wf_active <= 1'b0;
        end else if (video_on_d2 && in_waveform_area) begin
            wf_active <= 1'b1;
            if (pixel_is_cursor) begin
                // Red cursor line at write pointer
                wf_red   <= 4'hF;
                wf_green <= 4'h0;
                wf_blue  <= 4'h0;
            end else if (pixel_is_waveform || pixel_is_point) begin
                // Green waveform trace
                wf_red   <= 4'h0;
                wf_green <= 4'hF;
                wf_blue  <= 4'h0;
            end else if (pixel_is_grid) begin
                // Light gray grid lines
                wf_red   <= 4'h4;
                wf_green <= 4'h4;
                wf_blue  <= 4'h4;
            end else if (pixel_is_border) begin
                // Dim gray border
                wf_red   <= 4'h3;
                wf_green <= 4'h3;
                wf_blue  <= 4'h3;
            end else begin
                // Black background within waveform area
                wf_red   <= 4'h0;
                wf_green <= 4'h0;
                wf_blue  <= 4'h0;
            end
        end else begin
            wf_red    <= 4'h0;
            wf_green  <= 4'h0;
            wf_blue   <= 4'h0;
            wf_active <= 1'b0;
        end
    end

endmodule
