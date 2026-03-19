// =============================================================================
// aes128_encrypt.v
// Top-Level AES-128 Encryption Module (Iterative Architecture)
//
// Architecture:
//   Phase 1 - KEY_EXPAND: Pre-expand all 11 round keys into a register array
//             (12 clock cycles: 1 for load + 11 for key output)
//   Phase 2 - ENCRYPT: Perform encryption rounds (11 clock cycles)
//             Round 0:    AddRoundKey (XOR with key 0)
//             Rounds 1-9: SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
//             Round 10:   SubBytes -> ShiftRows -> AddRoundKey (no MixColumns)
//
// Total latency: ~23 clock cycles from start to done
// At 100 MHz with ECG at 500 Hz: 200,000 cycles available per sample
//
// Instantiates:
//   - 16 x sbox (parallel SubBytes for all 16 bytes)
//   - 1  x shift_rows
//   - 1  x mix_columns
//   - 1  x key_expansion
//
// Part of AES-128 Secure Enclave for Basys 3 (Artix-7)
// =============================================================================

module aes128_encrypt(
    input  wire         clk,
    input  wire         rst,
    input  wire [127:0] plaintext,
    input  wire [127:0] key,
    input  wire         start,
    output reg  [127:0] ciphertext,
    output reg          done,
    output reg          busy
);

    // =========================================================================
    // State Machine Definitions
    // =========================================================================
    localparam ST_IDLE       = 3'd0;
    localparam ST_KEY_START  = 3'd1;
    localparam ST_KEY_EXPAND = 3'd2;
    localparam ST_ENC_INIT   = 3'd3;
    localparam ST_ENC_ROUND  = 3'd4;
    localparam ST_DONE       = 3'd5;

    reg [2:0]   state;
    reg [3:0]   enc_round;        // Current encryption round (0-10)

    // =========================================================================
    // Round Key Storage (11 keys x 128 bits)
    // =========================================================================
    reg [127:0] rk [0:10];

    // =========================================================================
    // Key Expansion Interface
    // =========================================================================
    reg          ke_start;
    wire [127:0] ke_round_key;
    wire [3:0]   ke_round_num;
    wire         ke_key_valid;
    wire         ke_done;

    key_expansion u_key_expansion (
        .clk        (clk),
        .rst        (rst),
        .cipher_key (key),
        .start      (ke_start),
        .round_key  (ke_round_key),
        .round_num  (ke_round_num),
        .key_valid  (ke_key_valid),
        .done       (ke_done)
    );

    // =========================================================================
    // Encryption State Register
    // =========================================================================
    reg [127:0] aes_state;

    // =========================================================================
    // SubBytes: 16 parallel S-Box instances
    // =========================================================================
    wire [127:0] sub_bytes_out;

    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : gen_sbox
            sbox u_sbox (
                .in  (aes_state[(15-gi)*8 +: 8]),
                .out (sub_bytes_out[(15-gi)*8 +: 8])
            );
        end
    endgenerate

    // =========================================================================
    // ShiftRows
    // =========================================================================
    wire [127:0] shift_rows_out;

    shift_rows u_shift_rows (
        .state_in  (sub_bytes_out),
        .state_out (shift_rows_out)
    );

    // =========================================================================
    // MixColumns
    // =========================================================================
    wire [127:0] mix_columns_out;

    mix_columns u_mix_columns (
        .state_in  (shift_rows_out),
        .state_out (mix_columns_out)
    );

    // =========================================================================
    // AddRoundKey results (pre-computed for both paths)
    // =========================================================================
    wire [127:0] after_mix_add_rk    = mix_columns_out   ^ rk[enc_round];
    wire [127:0] after_shift_add_rk  = shift_rows_out    ^ rk[enc_round];
    wire [127:0] initial_add_rk      = aes_state         ^ rk[0];

    // =========================================================================
    // Main State Machine
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state     <= ST_IDLE;
            enc_round <= 4'd0;
            aes_state <= 128'd0;
            ciphertext<= 128'd0;
            done      <= 1'b0;
            busy      <= 1'b0;
            ke_start  <= 1'b0;
        end else begin
            // Default de-assertions
            done     <= 1'b0;
            ke_start <= 1'b0;

            case (state)
                // -------------------------------------------------------------
                // IDLE: Wait for start signal
                // -------------------------------------------------------------
                ST_IDLE: begin
                    if (start) begin
                        busy      <= 1'b1;
                        aes_state <= plaintext;
                        ke_start  <= 1'b1;   // Trigger key expansion
                        state     <= ST_KEY_START;
                    end
                end

                // -------------------------------------------------------------
                // KEY_START: One-cycle delay for key expansion to begin
                // -------------------------------------------------------------
                ST_KEY_START: begin
                    state <= ST_KEY_EXPAND;
                end

                // -------------------------------------------------------------
                // KEY_EXPAND: Collect all 11 round keys
                // -------------------------------------------------------------
                ST_KEY_EXPAND: begin
                    if (ke_key_valid) begin
                        rk[ke_round_num] <= ke_round_key;
                    end
                    if (ke_done) begin
                        // All keys collected; last key stored this cycle
                        state     <= ST_ENC_INIT;
                    end
                end

                // -------------------------------------------------------------
                // ENC_INIT: Round 0 - AddRoundKey only
                // -------------------------------------------------------------
                ST_ENC_INIT: begin
                    aes_state <= aes_state ^ rk[0];
                    enc_round <= 4'd1;
                    state     <= ST_ENC_ROUND;
                end

                // -------------------------------------------------------------
                // ENC_ROUND: Rounds 1-10
                // SubBytes -> ShiftRows -> [MixColumns] -> AddRoundKey
                // -------------------------------------------------------------
                ST_ENC_ROUND: begin
                    if (enc_round <= 4'd9) begin
                        // Rounds 1-9: full round with MixColumns
                        aes_state <= after_mix_add_rk;
                        enc_round <= enc_round + 4'd1;
                    end else begin
                        // Round 10: no MixColumns
                        aes_state  <= after_shift_add_rk;
                        ciphertext <= after_shift_add_rk;
                        done       <= 1'b1;
                        busy       <= 1'b0;
                        enc_round  <= 4'd0;
                        state      <= ST_DONE;
                    end
                end

                // -------------------------------------------------------------
                // DONE: Output available, return to idle
                // -------------------------------------------------------------
                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
