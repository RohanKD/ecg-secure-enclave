//////////////////////////////////////////////////////////////////////////////
// output_mux.v — Multiplexes encrypted ECG data and classification results
//                onto a single UART TX channel with framing
//////////////////////////////////////////////////////////////////////////////
// Protocol:
//   Frame type 0xAA: Encrypted ECG block (16 bytes of AES ciphertext)
//     [0xAA] [16 bytes ciphertext] [0x55] = 18 bytes total
//   Frame type 0xBB: Classification result
//     [0xBB] [class: 0x00=normal, 0x01=abnormal] [HR high] [HR low] [0x55] = 5 bytes
//////////////////////////////////////////////////////////////////////////////

module output_mux(
    input  wire         clk,
    input  wire         rst,

    // Encrypted ECG data input
    input  wire [127:0] cipher_data,
    input  wire         cipher_valid,   // Pulse when new ciphertext ready

    // Classification result input
    input  wire         classification, // 0=normal, 1=abnormal
    input  wire [15:0]  heart_rate_bpm,
    input  wire         class_valid,    // Pulse when new classification ready

    // UART TX interface
    output reg  [7:0]   uart_data,
    output reg          uart_start,
    input  wire         uart_busy,

    // Encryption enable (from switch)
    input  wire         encrypt_enable
);

    // State machine
    localparam S_IDLE        = 4'd0;
    localparam S_SEND_ENC_HDR = 4'd1;
    localparam S_SEND_ENC_DAT = 4'd2;
    localparam S_SEND_ENC_FTR = 4'd3;
    localparam S_SEND_CLS_HDR = 4'd4;
    localparam S_SEND_CLS_DAT = 4'd5;
    localparam S_SEND_CLS_HR1 = 4'd6;
    localparam S_SEND_CLS_HR2 = 4'd7;
    localparam S_SEND_CLS_FTR = 4'd8;
    localparam S_WAIT_TX      = 4'd9;

    reg [3:0]   state, next_after_wait;
    reg [127:0] cipher_buf;
    reg         class_buf;
    reg [15:0]  hr_buf;
    reg [3:0]   byte_cnt;       // 0-15 for 16 cipher bytes

    // Pending flags
    reg cipher_pending;
    reg class_pending;

    // Latch incoming data
    always @(posedge clk) begin
        if (rst) begin
            cipher_pending <= 1'b0;
            class_pending  <= 1'b0;
        end else begin
            if (cipher_valid && encrypt_enable) begin
                cipher_buf     <= cipher_data;
                cipher_pending <= 1'b1;
            end
            if (class_valid) begin
                class_buf     <= classification;
                hr_buf        <= heart_rate_bpm;
                class_pending <= 1'b1;
            end
            // Clear pending when we start sending
            if (state == S_SEND_ENC_HDR)
                cipher_pending <= 1'b0;
            if (state == S_SEND_CLS_HDR)
                class_pending <= 1'b0;
        end
    end

    // UART send helper
    task send_byte;
        input [7:0] data;
        input [3:0] next_state;
        begin
            uart_data       = data;
            uart_start      = 1'b1;
            state           = S_WAIT_TX;
            next_after_wait = next_state;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            uart_data  <= 8'h00;
            uart_start <= 1'b0;
            byte_cnt   <= 4'd0;
            next_after_wait <= S_IDLE;
        end else begin
            uart_start <= 1'b0;  // Default: no start pulse

            case (state)
                S_IDLE: begin
                    if (cipher_pending && !uart_busy) begin
                        state <= S_SEND_ENC_HDR;
                    end else if (class_pending && !uart_busy) begin
                        state <= S_SEND_CLS_HDR;
                    end
                end

                S_SEND_ENC_HDR: begin
                    if (!uart_busy) begin
                        uart_data  <= 8'hAA;
                        uart_start <= 1'b1;
                        state      <= S_WAIT_TX;
                        next_after_wait <= S_SEND_ENC_DAT;
                        byte_cnt   <= 4'd0;
                    end
                end

                S_SEND_ENC_DAT: begin
                    if (!uart_busy) begin
                        // Send byte_cnt-th byte of ciphertext (MSB first)
                        uart_data  <= cipher_buf[127 - (byte_cnt * 8) -: 8];
                        uart_start <= 1'b1;
                        state      <= S_WAIT_TX;
                        if (byte_cnt == 4'd15)
                            next_after_wait <= S_SEND_ENC_FTR;
                        else
                            next_after_wait <= S_SEND_ENC_DAT;
                        byte_cnt <= byte_cnt + 4'd1;
                    end
                end

                S_SEND_ENC_FTR: begin
                    if (!uart_busy) begin
                        uart_data  <= 8'h55;
                        uart_start <= 1'b1;
                        state      <= S_WAIT_TX;
                        next_after_wait <= S_IDLE;
                    end
                end

                S_SEND_CLS_HDR: begin
                    if (!uart_busy) begin
                        uart_data  <= 8'hBB;
                        uart_start <= 1'b1;
                        state      <= S_WAIT_TX;
                        next_after_wait <= S_SEND_CLS_DAT;
                    end
                end

                S_SEND_CLS_DAT: begin
                    if (!uart_busy) begin
                        uart_data  <= {7'b0, class_buf};
                        uart_start <= 1'b1;
                        state      <= S_WAIT_TX;
                        next_after_wait <= S_SEND_CLS_HR1;
                    end
                end

                S_SEND_CLS_HR1: begin
                    if (!uart_busy) begin
                        uart_data  <= hr_buf[15:8];
                        uart_start <= 1'b1;
                        state      <= S_WAIT_TX;
                        next_after_wait <= S_SEND_CLS_HR2;
                    end
                end

                S_SEND_CLS_HR2: begin
                    if (!uart_busy) begin
                        uart_data  <= hr_buf[7:0];
                        uart_start <= 1'b1;
                        state      <= S_WAIT_TX;
                        next_after_wait <= S_SEND_CLS_FTR;
                    end
                end

                S_SEND_CLS_FTR: begin
                    if (!uart_busy) begin
                        uart_data  <= 8'h55;
                        uart_start <= 1'b1;
                        state      <= S_WAIT_TX;
                        next_after_wait <= S_IDLE;
                    end
                end

                S_WAIT_TX: begin
                    // Wait for UART to become busy (accepted byte) then not busy
                    if (!uart_busy && !uart_start) begin
                        state <= next_after_wait;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
