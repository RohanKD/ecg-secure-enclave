// ============================================================================
// vga_text.v
// Text overlay on VGA display for ECG Secure Enclave
// Basys 3 / Artix-7 FPGA
//
// Display layout:
//   Row 0 (y=0..15):    "HR: XXX BPM"          left-aligned
//   Row 1 (y=16..31):   "STATUS: NORMAL"        left-aligned (or ABNORMAL/LEADS OFF)
//   Bottom (y=464..479): "ECG SECURE ENCLAVE"   centered
//
// Characters are 8 pixels wide x 16 pixels tall.
// Uses font_rom for bitmap rendering.
//
// Color scheme:
//   HR value + BPM label:  white
//   STATUS: NORMAL:        green
//   STATUS: ABNORMAL:      red
//   STATUS: LEADS OFF:     yellow
//   Bottom banner:         cyan
// ============================================================================

module vga_text (
    input  wire        clk,
    input  wire        rst,
    input  wire [9:0]  pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        video_on,
    input  wire [15:0] heart_rate_bpm,  // Binary BPM value
    input  wire        abnormal,        // 0=normal, 1=abnormal
    input  wire        leads_off,       // Leads disconnected
    output reg  [3:0]  txt_red,
    output reg  [3:0]  txt_green,
    output reg  [3:0]  txt_blue,
    output reg         txt_active       // 1 if this module is driving pixels
);

    // -----------------------------------------------------------------------
    // Character cell size
    // -----------------------------------------------------------------------
    localparam CHAR_W = 4'd8;
    localparam CHAR_H = 5'd16;

    // -----------------------------------------------------------------------
    // Text row Y boundaries
    // -----------------------------------------------------------------------
    localparam ROW0_Y_MIN = 10'd0;
    localparam ROW0_Y_MAX = 10'd15;
    localparam ROW1_Y_MIN = 10'd16;
    localparam ROW1_Y_MAX = 10'd31;
    localparam ROW2_Y_MIN = 10'd464;
    localparam ROW2_Y_MAX = 10'd479;

    // -----------------------------------------------------------------------
    // Maximum string lengths
    // -----------------------------------------------------------------------
    localparam ROW0_LEN = 5'd11;  // "HR: XXX BPM"
    localparam ROW1_MAX = 5'd17;  // "STATUS: LEADS OFF" (longest)
    localparam ROW2_LEN = 5'd18;  // "ECG SECURE ENCLAVE"

    // -----------------------------------------------------------------------
    // Bottom row centering: (640 - 18*8) / 2 = (640-144)/2 = 248
    // -----------------------------------------------------------------------
    localparam ROW2_X_OFFSET = 10'd248;

    // -----------------------------------------------------------------------
    // BPM binary-to-BCD conversion (3 digits, 0-999)
    // Using repeated subtraction (combinational, small values)
    // -----------------------------------------------------------------------
    reg [3:0] bpm_hundreds;
    reg [3:0] bpm_tens;
    reg [3:0] bpm_ones;

    reg [15:0] bpm_temp;

    always @(*) begin
        bpm_temp = heart_rate_bpm;

        // Clamp to 999
        if (bpm_temp > 16'd999)
            bpm_temp = 16'd999;

        // Hundreds
        bpm_hundreds = 4'd0;
        if (bpm_temp >= 16'd900) begin bpm_hundreds = 4'd9; bpm_temp = bpm_temp - 16'd900; end
        else if (bpm_temp >= 16'd800) begin bpm_hundreds = 4'd8; bpm_temp = bpm_temp - 16'd800; end
        else if (bpm_temp >= 16'd700) begin bpm_hundreds = 4'd7; bpm_temp = bpm_temp - 16'd700; end
        else if (bpm_temp >= 16'd600) begin bpm_hundreds = 4'd6; bpm_temp = bpm_temp - 16'd600; end
        else if (bpm_temp >= 16'd500) begin bpm_hundreds = 4'd5; bpm_temp = bpm_temp - 16'd500; end
        else if (bpm_temp >= 16'd400) begin bpm_hundreds = 4'd4; bpm_temp = bpm_temp - 16'd400; end
        else if (bpm_temp >= 16'd300) begin bpm_hundreds = 4'd3; bpm_temp = bpm_temp - 16'd300; end
        else if (bpm_temp >= 16'd200) begin bpm_hundreds = 4'd2; bpm_temp = bpm_temp - 16'd200; end
        else if (bpm_temp >= 16'd100) begin bpm_hundreds = 4'd1; bpm_temp = bpm_temp - 16'd100; end

        // Tens
        bpm_tens = 4'd0;
        if (bpm_temp >= 16'd90) begin bpm_tens = 4'd9; bpm_temp = bpm_temp - 16'd90; end
        else if (bpm_temp >= 16'd80) begin bpm_tens = 4'd8; bpm_temp = bpm_temp - 16'd80; end
        else if (bpm_temp >= 16'd70) begin bpm_tens = 4'd7; bpm_temp = bpm_temp - 16'd70; end
        else if (bpm_temp >= 16'd60) begin bpm_tens = 4'd6; bpm_temp = bpm_temp - 16'd60; end
        else if (bpm_temp >= 16'd50) begin bpm_tens = 4'd5; bpm_temp = bpm_temp - 16'd50; end
        else if (bpm_temp >= 16'd40) begin bpm_tens = 4'd4; bpm_temp = bpm_temp - 16'd40; end
        else if (bpm_temp >= 16'd30) begin bpm_tens = 4'd3; bpm_temp = bpm_temp - 16'd30; end
        else if (bpm_temp >= 16'd20) begin bpm_tens = 4'd2; bpm_temp = bpm_temp - 16'd20; end
        else if (bpm_temp >= 16'd10) begin bpm_tens = 4'd1; bpm_temp = bpm_temp - 16'd10; end

        // Ones
        bpm_ones = bpm_temp[3:0];
    end

    // -----------------------------------------------------------------------
    // ASCII code for BPM digits
    // -----------------------------------------------------------------------
    wire [6:0] ascii_hundreds = 7'd48 + {3'd0, bpm_hundreds};  // '0' + digit
    wire [6:0] ascii_tens     = 7'd48 + {3'd0, bpm_tens};
    wire [6:0] ascii_ones     = 7'd48 + {3'd0, bpm_ones};

    // -----------------------------------------------------------------------
    // Determine which text row the current pixel is in
    // -----------------------------------------------------------------------
    wire in_row0 = (pixel_y >= ROW0_Y_MIN) && (pixel_y <= ROW0_Y_MAX);
    wire in_row1 = (pixel_y >= ROW1_Y_MIN) && (pixel_y <= ROW1_Y_MAX);
    wire in_row2 = (pixel_y >= ROW2_Y_MIN) && (pixel_y <= ROW2_Y_MAX);

    wire in_any_row = in_row0 || in_row1 || in_row2;

    // -----------------------------------------------------------------------
    // Character column index within the current text row
    // -----------------------------------------------------------------------
    wire [4:0] char_col_row0 = pixel_x[7:3];  // pixel_x / 8
    wire [4:0] char_col_row1 = pixel_x[7:3];
    wire [4:0] char_col_row2;

    // Row 2 is centered: subtract offset, then divide by 8
    wire [9:0] row2_rel_x = pixel_x - ROW2_X_OFFSET;
    assign char_col_row2 = row2_rel_x[7:3];

    wire in_row2_range = in_row2 &&
                         (pixel_x >= ROW2_X_OFFSET) &&
                         (pixel_x < ROW2_X_OFFSET + 10'd144);  // 18*8

    // -----------------------------------------------------------------------
    // Pixel position within the character cell
    // -----------------------------------------------------------------------
    wire [2:0] pixel_col = pixel_x[2:0];          // x % 8
    wire [3:0] pixel_row = pixel_y[3:0];          // y % 16

    wire [2:0] pixel_col_row2 = row2_rel_x[2:0];

    // -----------------------------------------------------------------------
    // Row 1 string length depends on status
    // -----------------------------------------------------------------------
    reg [4:0] row1_len;
    always @(*) begin
        if (leads_off)
            row1_len = 5'd17;  // "STATUS: LEADS OFF"
        else if (abnormal)
            row1_len = 5'd17;  // "STATUS: ABNORMAL "  (padded)
        else
            row1_len = 5'd15;  // "STATUS: NORMAL "  (padded)
    end

    // -----------------------------------------------------------------------
    // Character lookup: determine ASCII code for current pixel
    // -----------------------------------------------------------------------
    reg [6:0] char_code;
    reg       char_valid;

    always @(*) begin
        char_code  = 7'd32;  // space by default
        char_valid = 1'b0;

        if (in_row0 && (char_col_row0 < ROW0_LEN)) begin
            char_valid = 1'b1;
            case (char_col_row0)
                5'd0:  char_code = 7'd72;  // 'H'
                5'd1:  char_code = 7'd82;  // 'R'
                5'd2:  char_code = 7'd58;  // ':'
                5'd3:  char_code = 7'd32;  // ' '
                5'd4:  char_code = ascii_hundreds;
                5'd5:  char_code = ascii_tens;
                5'd6:  char_code = ascii_ones;
                5'd7:  char_code = 7'd32;  // ' '
                5'd8:  char_code = 7'd66;  // 'B'
                5'd9:  char_code = 7'd80;  // 'P'
                5'd10: char_code = 7'd77;  // 'M'
                default: char_code = 7'd32;
            endcase
        end else if (in_row1 && (char_col_row1 < row1_len)) begin
            char_valid = 1'b1;
            // First 8 characters are always "STATUS: "
            case (char_col_row1)
                5'd0:  char_code = 7'd83;  // 'S'
                5'd1:  char_code = 7'd84;  // 'T'
                5'd2:  char_code = 7'd65;  // 'A'
                5'd3:  char_code = 7'd84;  // 'T'
                5'd4:  char_code = 7'd85;  // 'U'
                5'd5:  char_code = 7'd83;  // 'S'
                5'd6:  char_code = 7'd58;  // ':'
                5'd7:  char_code = 7'd32;  // ' '
                default: begin
                    if (leads_off) begin
                        // "LEADS OFF"
                        case (char_col_row1)
                            5'd8:  char_code = 7'd76;  // 'L'
                            5'd9:  char_code = 7'd69;  // 'E'
                            5'd10: char_code = 7'd65;  // 'A'
                            5'd11: char_code = 7'd68;  // 'D'
                            5'd12: char_code = 7'd83;  // 'S'
                            5'd13: char_code = 7'd32;  // ' '
                            5'd14: char_code = 7'd79;  // 'O'
                            5'd15: char_code = 7'd70;  // 'F'
                            5'd16: char_code = 7'd70;  // 'F'
                            default: char_code = 7'd32;
                        endcase
                    end else if (abnormal) begin
                        // "ABNORMAL "
                        case (char_col_row1)
                            5'd8:  char_code = 7'd65;  // 'A'
                            5'd9:  char_code = 7'd66;  // 'B'
                            5'd10: char_code = 7'd78;  // 'N'
                            5'd11: char_code = 7'd79;  // 'O'
                            5'd12: char_code = 7'd82;  // 'R'
                            5'd13: char_code = 7'd77;  // 'M'
                            5'd14: char_code = 7'd65;  // 'A'
                            5'd15: char_code = 7'd76;  // 'L'
                            5'd16: char_code = 7'd32;  // ' '
                            default: char_code = 7'd32;
                        endcase
                    end else begin
                        // "NORMAL "
                        case (char_col_row1)
                            5'd8:  char_code = 7'd78;  // 'N'
                            5'd9:  char_code = 7'd79;  // 'O'
                            5'd10: char_code = 7'd82;  // 'R'
                            5'd11: char_code = 7'd77;  // 'M'
                            5'd12: char_code = 7'd65;  // 'A'
                            5'd13: char_code = 7'd76;  // 'L'
                            5'd14: char_code = 7'd32;  // ' '
                            default: char_code = 7'd32;
                        endcase
                    end
                end
            endcase
        end else if (in_row2_range) begin
            char_valid = 1'b1;
            // "ECG SECURE ENCLAVE"
            case (char_col_row2)
                5'd0:  char_code = 7'd69;  // 'E'
                5'd1:  char_code = 7'd67;  // 'C'
                5'd2:  char_code = 7'd71;  // 'G'
                5'd3:  char_code = 7'd32;  // ' '
                5'd4:  char_code = 7'd83;  // 'S'
                5'd5:  char_code = 7'd69;  // 'E'
                5'd6:  char_code = 7'd67;  // 'C'
                5'd7:  char_code = 7'd85;  // 'U'
                5'd8:  char_code = 7'd82;  // 'R'
                5'd9:  char_code = 7'd69;  // 'E'
                5'd10: char_code = 7'd32;  // ' '
                5'd11: char_code = 7'd69;  // 'E'
                5'd12: char_code = 7'd78;  // 'N'
                5'd13: char_code = 7'd67;  // 'C'
                5'd14: char_code = 7'd76;  // 'L'
                5'd15: char_code = 7'd65;  // 'A'
                5'd16: char_code = 7'd86;  // 'V'
                5'd17: char_code = 7'd69;  // 'E'
                default: char_code = 7'd32;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Font ROM address calculation
    // addr = (char_code - 32) * 16 + pixel_row
    // -----------------------------------------------------------------------
    wire [10:0] font_addr;
    wire [6:0]  char_offset = char_code - 7'd32;
    assign font_addr = {char_offset, pixel_row};  // char_offset * 16 + pixel_row

    // -----------------------------------------------------------------------
    // Font ROM instantiation
    // -----------------------------------------------------------------------
    wire [7:0] font_data;

    font_rom u_font_rom (
        .clk  (clk),
        .addr (font_addr),
        .data (font_data)
    );

    // -----------------------------------------------------------------------
    // Pipeline delay: font ROM has 1-cycle read latency.
    // Delay control signals by 1 cycle to match.
    // -----------------------------------------------------------------------
    reg       char_valid_d1;
    reg [2:0] pixel_col_d1;
    reg       in_row0_d1, in_row1_d1, in_row2_d1;
    reg       abnormal_d1, leads_off_d1;
    reg       video_on_d1;
    reg       in_row2_range_d1;
    reg [2:0] pixel_col_row2_d1;

    always @(posedge clk) begin
        char_valid_d1     <= char_valid;
        pixel_col_d1      <= pixel_col;
        in_row0_d1        <= in_row0;
        in_row1_d1        <= in_row1;
        in_row2_d1        <= in_row2;
        abnormal_d1       <= abnormal;
        leads_off_d1      <= leads_off;
        video_on_d1       <= video_on;
        in_row2_range_d1  <= in_row2_range;
        pixel_col_row2_d1 <= pixel_col_row2;
    end

    // -----------------------------------------------------------------------
    // Determine the pixel bit from the font bitmap row
    // MSB (bit 7) = leftmost pixel of the character cell
    // -----------------------------------------------------------------------
    wire [2:0] sel_col = in_row2_d1 ? pixel_col_row2_d1 : pixel_col_d1;
    wire pixel_on = char_valid_d1 & font_data[3'd7 - sel_col];

    // -----------------------------------------------------------------------
    // Output color
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            txt_red    <= 4'h0;
            txt_green  <= 4'h0;
            txt_blue   <= 4'h0;
            txt_active <= 1'b0;
        end else if (video_on_d1 && pixel_on) begin
            txt_active <= 1'b1;
            if (in_row0_d1) begin
                // HR line: white text
                txt_red   <= 4'hF;
                txt_green <= 4'hF;
                txt_blue  <= 4'hF;
            end else if (in_row1_d1) begin
                if (leads_off_d1) begin
                    // LEADS OFF: yellow
                    txt_red   <= 4'hF;
                    txt_green <= 4'hF;
                    txt_blue  <= 4'h0;
                end else if (abnormal_d1) begin
                    // ABNORMAL: red
                    txt_red   <= 4'hF;
                    txt_green <= 4'h0;
                    txt_blue  <= 4'h0;
                end else begin
                    // NORMAL: green
                    txt_red   <= 4'h0;
                    txt_green <= 4'hF;
                    txt_blue  <= 4'h0;
                end
            end else if (in_row2_d1) begin
                // Bottom banner: cyan
                txt_red   <= 4'h0;
                txt_green <= 4'hF;
                txt_blue  <= 4'hF;
            end else begin
                txt_red   <= 4'hF;
                txt_green <= 4'hF;
                txt_blue  <= 4'hF;
            end
        end else begin
            txt_red    <= 4'h0;
            txt_green  <= 4'h0;
            txt_blue   <= 4'h0;
            txt_active <= 1'b0;
        end
    end

endmodule
