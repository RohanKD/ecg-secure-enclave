// =============================================================================
// key_expansion.v
// AES-128 Key Expansion: Iterative generation of 11 round keys (rounds 0-10)
// from a 128-bit cipher key, one round key per clock cycle.
//
// Algorithm (FIPS 197, Section 5.2):
//   For AES-128 (Nk=4, Nr=10):
//     W[0..3] = cipher_key (4 words of 32 bits each)
//     For i = 4 to 43:
//       temp = W[i-1]
//       if (i mod 4 == 0):
//         temp = SubWord(RotWord(temp)) ^ Rcon[i/4]
//       W[i] = W[i-4] ^ temp
//
// Interface:
//   - Assert `start` for one cycle with `cipher_key` valid
//   - Module outputs round_key/round_num with key_valid asserted each cycle
//   - `done` asserts after all 11 keys have been produced
//
// Uses 4 S-Box instances for the SubWord transformation.
// Part of AES-128 Secure Enclave for Basys 3 (Artix-7)
// =============================================================================

module key_expansion(
    input  wire         clk,
    input  wire         rst,
    input  wire [127:0] cipher_key,
    input  wire         start,
    output reg  [127:0] round_key,
    output reg  [3:0]   round_num,
    output reg          key_valid,
    output reg          done
);

    // -------------------------------------------------------------------------
    // Rcon lookup (round constants, indexed 1..10)
    // -------------------------------------------------------------------------
    function [7:0] rcon;
        input [3:0] idx;
        begin
            case (idx)
                4'd1:    rcon = 8'h01;
                4'd2:    rcon = 8'h02;
                4'd3:    rcon = 8'h04;
                4'd4:    rcon = 8'h08;
                4'd5:    rcon = 8'h10;
                4'd6:    rcon = 8'h20;
                4'd7:    rcon = 8'h40;
                4'd8:    rcon = 8'h80;
                4'd9:    rcon = 8'h1b;
                4'd10:   rcon = 8'h36;
                default: rcon = 8'h00;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    localparam ST_IDLE   = 2'd0;
    localparam ST_ROUND0 = 2'd1;
    localparam ST_EXPAND = 2'd2;
    localparam ST_DONE   = 2'd3;

    reg [1:0]   state;
    reg [3:0]   round_cnt;

    // Current 4-word key: W[0], W[1], W[2], W[3]
    reg [31:0]  w0, w1, w2, w3;

    // S-Box I/O for SubWord(RotWord(W[3]))
    // RotWord({b0, b1, b2, b3}) = {b1, b2, b3, b0}
    // Then SubWord on each byte
    wire [7:0] rot_b0, rot_b1, rot_b2, rot_b3;
    wire [7:0] sub_b0, sub_b1, sub_b2, sub_b3;

    // RotWord: rotate left by 8 bits
    assign rot_b0 = w3[23:16];   // was byte 1
    assign rot_b1 = w3[15:8];    // was byte 2
    assign rot_b2 = w3[7:0];     // was byte 3
    assign rot_b3 = w3[31:24];   // was byte 0

    // SubWord via 4 S-Box instances
    sbox sbox_kx0 (.in(rot_b0), .out(sub_b0));
    sbox sbox_kx1 (.in(rot_b1), .out(sub_b1));
    sbox sbox_kx2 (.in(rot_b2), .out(sub_b2));
    sbox sbox_kx3 (.in(rot_b3), .out(sub_b3));

    // Compute next round's W words
    wire [31:0] subword_xor_rcon;
    wire [31:0] nw0, nw1, nw2, nw3;

    assign subword_xor_rcon = {sub_b0 ^ rcon(round_cnt + 4'd1), sub_b1, sub_b2, sub_b3};
    assign nw0 = w0 ^ subword_xor_rcon;
    assign nw1 = w1 ^ nw0;
    assign nw2 = w2 ^ nw1;
    assign nw3 = w3 ^ nw2;

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state     <= ST_IDLE;
            round_cnt <= 4'd0;
            round_key <= 128'd0;
            round_num <= 4'd0;
            key_valid <= 1'b0;
            done      <= 1'b0;
            w0        <= 32'd0;
            w1        <= 32'd0;
            w2        <= 32'd0;
            w3        <= 32'd0;
        end else begin
            // Default de-assertions
            key_valid <= 1'b0;
            done      <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                ST_IDLE: begin
                    if (start) begin
                        // Load the original cipher key as W[0..3]
                        w0 <= cipher_key[127:96];
                        w1 <= cipher_key[95:64];
                        w2 <= cipher_key[63:32];
                        w3 <= cipher_key[31:0];
                        round_cnt <= 4'd0;
                        state     <= ST_ROUND0;
                    end
                end

                // ---------------------------------------------------------
                // Output round key 0 (the original cipher key)
                ST_ROUND0: begin
                    round_key <= {w0, w1, w2, w3};
                    round_num <= 4'd0;
                    key_valid <= 1'b1;
                    round_cnt <= 4'd0;
                    state     <= ST_EXPAND;
                end

                // ---------------------------------------------------------
                // Generate round keys 1..10
                ST_EXPAND: begin
                    // Advance to next round key
                    w0 <= nw0;
                    w1 <= nw1;
                    w2 <= nw2;
                    w3 <= nw3;

                    round_key <= {nw0, nw1, nw2, nw3};
                    round_num <= round_cnt + 4'd1;
                    key_valid <= 1'b1;
                    round_cnt <= round_cnt + 4'd1;

                    if (round_cnt == 4'd9) begin
                        // This produces round key 10 (the last one)
                        done  <= 1'b1;
                        state <= ST_DONE;
                    end
                end

                // ---------------------------------------------------------
                ST_DONE: begin
                    // Stay here until next start
                    if (start) begin
                        w0 <= cipher_key[127:96];
                        w1 <= cipher_key[95:64];
                        w2 <= cipher_key[63:32];
                        w3 <= cipher_key[31:0];
                        round_cnt <= 4'd0;
                        state     <= ST_ROUND0;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
