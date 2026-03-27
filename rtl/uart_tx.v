//////////////////////////////////////////////////////////////////////////////
// uart_tx.v
// 115200-baud 8N1 UART transmitter for Basys 3 (100 MHz clock)
//
// Baud divider: 100,000,000 / 115,200 = 868 (rounded)
//
// Protocol: idle-high, start bit (low), 8 data bits LSB-first,
//           1 stop bit (high).
//
// Interface:
//   tx_start - assert for one cycle to begin transmission
//   tx_data  - must be stable when tx_start is asserted
//   tx_busy  - high while a byte is being transmitted
//   tx_out   - serial output (directly drives FPGA pin)
//////////////////////////////////////////////////////////////////////////////

module uart_tx(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx_out,
    output reg        tx_busy
);

    // -----------------------------------------------------------------------
    // Baud rate parameters
    // -----------------------------------------------------------------------
    localparam BAUD_DIV = 868 - 1;  // 0 to 867 = 868 counts
    localparam DIV_W    = 10;       // ceil(log2(868))

    // -----------------------------------------------------------------------
    // State encoding
    // -----------------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]        state;
    reg [DIV_W-1:0]  baud_cnt;      // Baud-rate counter
    reg [2:0]        bit_idx;       // Data bit index (0-7)
    reg [7:0]        shift_reg;     // Transmit shift register

    // Baud tick: high for one clk when baud_cnt reaches terminal count
    wire baud_tick = (baud_cnt == BAUD_DIV[DIV_W-1:0]);

    // -----------------------------------------------------------------------
    // Baud counter
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt <= {DIV_W{1'b0}};
        end else begin
            if (state == S_IDLE) begin
                baud_cnt <= {DIV_W{1'b0}};
            end else if (baud_tick) begin
                baud_cnt <= {DIV_W{1'b0}};
            end else begin
                baud_cnt <= baud_cnt + {{(DIV_W-1){1'b0}}, 1'b1};
            end
        end
    end

    // -----------------------------------------------------------------------
    // Transmit FSM
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            tx_out    <= 1'b1;       // Idle high
            tx_busy   <= 1'b0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                // IDLE: wait for tx_start
                // ---------------------------------------------------------
                S_IDLE: begin
                    tx_out  <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        tx_out    <= 1'b0;   // Drive start bit immediately
                        state     <= S_START;
                    end
                end

                // ---------------------------------------------------------
                // START: hold start bit for one baud period
                // ---------------------------------------------------------
                S_START: begin
                    tx_out <= 1'b0;
                    if (baud_tick) begin
                        tx_out  <= shift_reg[0];  // First data bit
                        state   <= S_DATA;
                        bit_idx <= 3'd0;
                    end
                end

                // ---------------------------------------------------------
                // DATA: shift out 8 bits LSB-first
                // ---------------------------------------------------------
                S_DATA: begin
                    tx_out <= shift_reg[0];
                    if (baud_tick) begin
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_idx == 3'd7) begin
                            tx_out <= 1'b1;  // Stop bit
                            state  <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                            tx_out  <= shift_reg[1]; // Next bit ready
                        end
                    end
                end

                // ---------------------------------------------------------
                // STOP: hold stop bit for one baud period
                // ---------------------------------------------------------
                S_STOP: begin
                    tx_out <= 1'b1;
                    if (baud_tick) begin
                        state  <= S_IDLE;
                        tx_busy <= 1'b0;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
