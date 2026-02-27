//////////////////////////////////////////////////////////////////////////////
// clk_divider.v
// Clock-enable generator for Basys 3 (100 MHz Artix-7 XC7A35T)
//
// Outputs:
//   clk_25mhz  - 25 MHz toggled clock (VGA pixel clock)
//   tick_500hz  - one-cycle pulse at 500 Hz (ADC sample trigger)
//   tick_1khz   - one-cycle pulse at 1 kHz (7-segment refresh)
//
// 100 MHz / 4       (toggle every 2 cycles) = 25 MHz
// 100 MHz / 200000  = 500 Hz
// 100 MHz / 100000  = 1 kHz
//////////////////////////////////////////////////////////////////////////////

module clk_divider(
    input  wire clk_100mhz,
    input  wire rst,
    output reg  clk_25mhz,      // VGA pixel clock (toggle)
    output reg  tick_500hz,      // ADC sample trigger (1-cycle pulse)
    output reg  tick_1khz        // 7-seg refresh (1-cycle pulse)
);

    // -----------------------------------------------------------------------
    // 25 MHz pixel clock - toggle every 2 cycles of 100 MHz
    // 100 MHz / 2 = 50 MHz toggle rate -> 25 MHz output clock
    // Counter counts 0,1 and toggles at terminal count.
    // -----------------------------------------------------------------------
    reg cnt_25;

    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin
            cnt_25    <= 1'b0;
            clk_25mhz <= 1'b0;
        end else begin
            if (cnt_25 == 1'b1) begin
                cnt_25     <= 1'b0;
                clk_25mhz <= ~clk_25mhz;
            end else begin
                cnt_25 <= cnt_25 + 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // 500 Hz tick - divide 100 MHz by 200,000
    // Counter range: 0 to 199,999
    // Pulse high for exactly one clock cycle at terminal count.
    // -----------------------------------------------------------------------
    localparam [17:0] DIV_500HZ = 18'd199_999;  // 200,000 - 1

    reg [17:0] cnt_500;

    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin
            cnt_500    <= 18'd0;
            tick_500hz <= 1'b0;
        end else begin
            if (cnt_500 == DIV_500HZ) begin
                cnt_500    <= 18'd0;
                tick_500hz <= 1'b1;
            end else begin
                cnt_500    <= cnt_500 + 18'd1;
                tick_500hz <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // 1 kHz tick - divide 100 MHz by 100,000
    // Counter range: 0 to 99,999
    // Pulse high for exactly one clock cycle at terminal count.
    // -----------------------------------------------------------------------
    localparam [16:0] DIV_1KHZ = 17'd99_999;  // 100,000 - 1

    reg [16:0] cnt_1k;

    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin
            cnt_1k    <= 17'd0;
            tick_1khz <= 1'b0;
        end else begin
            if (cnt_1k == DIV_1KHZ) begin
                cnt_1k    <= 17'd0;
                tick_1khz <= 1'b1;
            end else begin
                cnt_1k    <= cnt_1k + 17'd1;
                tick_1khz <= 1'b0;
            end
        end
    end

endmodule
