//////////////////////////////////////////////////////////////////////////////
// seven_seg.v
// 4-digit multiplexed 7-segment display driver for Basys 3
//
// Displays a binary BPM value (0-300 range) on the rightmost 3 digits
// with a blank leftmost digit. Uses binary-to-BCD conversion and
// leading-zero blanking.
//
// Basys 3 convention: active-low segments (seg[6:0] = gfedcba)
//                     active-low anodes   (an[3:0])
//
// Refresh rate: 1 kHz (tick_1khz input), cycling through 4 digits
// gives ~250 Hz per digit - well above flicker threshold.
//////////////////////////////////////////////////////////////////////////////

module seven_seg(
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_1khz,
    input  wire [15:0] bpm_value,   // Binary BPM (0-300 range typical)
    output reg  [6:0]  seg,         // Active-low segments a-g
    output reg  [3:0]  an           // Active-low digit enables
);

    // -----------------------------------------------------------------------
    // Binary-to-BCD conversion (double-dabble)
    // Converts a 10-bit binary value (0-999) to 3 BCD digits.
    // We only use the lower 10 bits since BPM <= 300 < 1024.
    // -----------------------------------------------------------------------
    reg [3:0] bcd_hundreds;
    reg [3:0] bcd_tens;
    reg [3:0] bcd_ones;

    // Combinational double-dabble for 10-bit input
    // Maximum value 999 needs 3 BCD digits (12 bits BCD)
    integer i;
    reg [21:0] dabble; // 12 bits BCD + 10 bits binary = 22 bits

    always @(*) begin
        dabble = 22'd0;
        dabble[9:0] = bpm_value[9:0]; // Load binary value (clamp to 10 bits)

        for (i = 0; i < 10; i = i + 1) begin
            // Check each BCD digit and add 3 if >= 5
            if (dabble[13:10] >= 4'd5)
                dabble[13:10] = dabble[13:10] + 4'd3;
            if (dabble[17:14] >= 4'd5)
                dabble[17:14] = dabble[17:14] + 4'd3;
            if (dabble[21:18] >= 4'd5)
                dabble[21:18] = dabble[21:18] + 4'd3;

            // Shift left by 1
            dabble = dabble << 1;
        end

        bcd_ones     = dabble[13:10];
        bcd_tens     = dabble[17:14];
        bcd_hundreds = dabble[21:18];
    end

    // -----------------------------------------------------------------------
    // Digit multiplexer: cycle through 4 digits on each tick_1khz
    // -----------------------------------------------------------------------
    reg [1:0] digit_sel;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            digit_sel <= 2'd0;
        end else if (tick_1khz) begin
            digit_sel <= digit_sel + 2'd1;
        end
    end

    // -----------------------------------------------------------------------
    // Select active digit and its BCD value
    // -----------------------------------------------------------------------
    reg [3:0] current_bcd;
    reg       blank_digit;

    always @(*) begin
        blank_digit = 1'b0;
        current_bcd = 4'd0;
        an          = 4'b1111;   // All off by default

        case (digit_sel)
            2'd0: begin // Rightmost digit: ones
                an          = 4'b1110;
                current_bcd = bcd_ones;
            end
            2'd1: begin // Tens digit
                an          = 4'b1101;
                current_bcd = bcd_tens;
                // Blank if hundreds and tens are both zero
                if (bcd_hundreds == 4'd0 && bcd_tens == 4'd0)
                    blank_digit = 1'b1;
            end
            2'd2: begin // Hundreds digit
                an          = 4'b1011;
                current_bcd = bcd_hundreds;
                // Blank if hundreds is zero
                if (bcd_hundreds == 4'd0)
                    blank_digit = 1'b1;
            end
            2'd3: begin // Leftmost digit: always blank (BPM < 1000)
                an          = 4'b0111;
                current_bcd = 4'd0;
                blank_digit = 1'b1;
            end
            default: begin
                an          = 4'b1111;
                current_bcd = 4'd0;
                blank_digit = 1'b1;
            end
        endcase
    end

    // -----------------------------------------------------------------------
    // 7-segment decoder
    // Active-low: 0 = segment ON, 1 = segment OFF
    // Segment mapping: seg[6:0] = {g, f, e, d, c, b, a}
    //
    //    aaaa
    //   f    b
    //   f    b
    //    gggg
    //   e    c
    //   e    c
    //    dddd
    // -----------------------------------------------------------------------
    reg [6:0] seg_pattern;

    always @(*) begin
        if (blank_digit) begin
            seg_pattern = 7'b1111111; // All segments off (blank)
        end else begin
            case (current_bcd)
                //                    gfedcba
                4'd0: seg_pattern = 7'b1000000;
                4'd1: seg_pattern = 7'b1111001;
                4'd2: seg_pattern = 7'b0100100;
                4'd3: seg_pattern = 7'b0110000;
                4'd4: seg_pattern = 7'b0011001;
                4'd5: seg_pattern = 7'b0010010;
                4'd6: seg_pattern = 7'b0000010;
                4'd7: seg_pattern = 7'b1111000;
                4'd8: seg_pattern = 7'b0000000;
                4'd9: seg_pattern = 7'b0010000;
                default: seg_pattern = 7'b1111111; // Blank for invalid
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Output register (reduces glitches during digit transitions)
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            seg <= 7'b1111111;
        end else begin
            seg <= seg_pattern;
        end
    end

endmodule
