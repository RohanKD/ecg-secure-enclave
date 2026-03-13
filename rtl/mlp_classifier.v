//////////////////////////////////////////////////////////////////////////////
// mlp_classifier.v
// Top-Level MLP Neural Network Classifier
//
// Two-layer feedforward neural network for ECG heartbeat classification:
//   Input  : 10 features (Q3.5 signed fixed-point, 80-bit vector)
//   Layer 1: 10 -> 8 neurons, ReLU activation
//   Layer 2:  8 -> 2 neurons, linear (no activation)
//   Output : argmax of 2 logits => 0 (normal) or 1 (abnormal)
//
// Architecture: single MAC unit, time-multiplexed across all neurons.
// Total cycles per classification:
//   Layer 1: 8 neurons x (1 clear + 10 MAC + 1 bias) = 96 cycles
//   Layer 2: 2 neurons x (1 clear +  8 MAC + 1 bias) = 20 cycles
//   Overhead (ROM latency, state transitions)          ~ 30 cycles
//   Total                                             ~ 146 cycles
//   At 100 MHz => ~1.5 us (well within 2 ms heartbeat interval)
//
// State machine: IDLE -> LOAD -> LAYER1 -> LAYER2 -> CLASSIFY -> DONE
//   (ReLU is applied combinationally at the end of each Layer 1 neuron)
//
// Target: Xilinx Artix-7 (Basys 3)
//////////////////////////////////////////////////////////////////////////////

module mlp_classifier (
    input  wire        clk,
    input  wire        rst,
    input  wire [79:0] feature_vector,     // 10 x 8-bit features (Q3.5)
    input  wire        features_valid,     // Pulse: latch features
    output reg         classification,     // 0 = normal, 1 = abnormal
    output reg         class_valid,        // Pulse: classification ready
    output reg         busy                // High while processing
);

    // ===================================================================
    // Local parameters
    // ===================================================================
    localparam NUM_INPUTS        = 10;
    localparam NUM_HIDDEN        = 8;
    localparam NUM_OUTPUTS       = 2;

    // Weight ROM address map
    localparam L1_WEIGHT_BASE    = 7'd0;    // 0..79
    localparam L1_BIAS_BASE      = 7'd80;   // 80..87
    localparam L2_WEIGHT_BASE    = 7'd88;   // 88..103
    localparam L2_BIAS_BASE      = 7'd104;  // 104..105

    // State encoding
    localparam [2:0]
        S_IDLE     = 3'd0,
        S_LOAD     = 3'd1,
        S_LAYER1   = 3'd2,
        S_LAYER2   = 3'd3,
        S_CLASSIFY = 3'd4,
        S_DONE     = 3'd5;

    // Sub-state for MAC sequencing within a neuron
    localparam [1:0]
        SUB_CLEAR    = 2'd0,   // Clear accumulator
        SUB_ADDR     = 2'd1,   // Present ROM address (wait for data next cycle)
        SUB_MAC      = 2'd2,   // Perform MAC with ROM data now available
        SUB_BIAS     = 2'd3;   // Add bias (ROM data is bias value)

    // ===================================================================
    // Registers
    // ===================================================================
    reg [2:0]  state;
    reg [1:0]  sub_state;

    // Input feature register file
    reg signed [7:0] features [0:NUM_INPUTS-1];

    // Hidden layer activations (after ReLU)
    reg signed [15:0] hidden [0:NUM_HIDDEN-1];

    // Output layer values (pre-argmax)
    reg signed [15:0] output_val [0:NUM_OUTPUTS-1];

    // Neuron and input counters
    reg [3:0] neuron_idx;       // Current neuron being computed
    reg [3:0] input_idx;        // Current input index within neuron
    reg [3:0] num_inputs_cur;   // Number of inputs for current layer

    // Pipeline delay counter for ROM read latency
    reg        rom_read_pending;

    // ===================================================================
    // MAC unit signals
    // ===================================================================
    reg                mac_clear;
    reg  signed [7:0]  mac_a;
    reg  signed [7:0]  mac_b;
    reg                mac_valid;
    reg  signed [7:0]  mac_bias;
    reg                mac_add_bias;
    wire signed [15:0] mac_result;
    wire               mac_result_valid;

    // ===================================================================
    // Weight ROM signals
    // ===================================================================
    reg  [6:0]         rom_addr;
    wire signed [7:0]  rom_data;

    // ===================================================================
    // ReLU signals
    // ===================================================================
    wire signed [15:0] relu_out;
    wire               relu_valid;

    // ===================================================================
    // Module instantiations
    // ===================================================================
    mac_unit u_mac (
        .clk          (clk),
        .rst          (rst),
        .clear        (mac_clear),
        .a            (mac_a),
        .b            (mac_b),
        .valid        (mac_valid),
        .bias         (mac_bias),
        .add_bias     (mac_add_bias),
        .result       (mac_result),
        .result_valid (mac_result_valid)
    );

    weight_rom u_weight_rom (
        .clk  (clk),
        .addr (rom_addr),
        .data (rom_data)
    );

    relu u_relu (
        .din       (mac_result),
        .din_valid (mac_result_valid),
        .dout      (relu_out),
        .dout_valid(relu_valid)
    );

    // ===================================================================
    // Feature vector unpacking (active during S_LOAD)
    // ===================================================================
    integer k;

    // ===================================================================
    // Main FSM
    // ===================================================================
    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            sub_state      <= SUB_CLEAR;
            classification <= 1'b0;
            class_valid    <= 1'b0;
            busy           <= 1'b0;
            mac_clear      <= 1'b0;
            mac_valid      <= 1'b0;
            mac_add_bias   <= 1'b0;
            mac_a          <= 8'sd0;
            mac_b          <= 8'sd0;
            mac_bias       <= 8'sd0;
            rom_addr       <= 7'd0;
            neuron_idx     <= 4'd0;
            input_idx      <= 4'd0;
            num_inputs_cur <= 4'd0;
            rom_read_pending <= 1'b0;
            for (k = 0; k < NUM_INPUTS; k = k + 1)
                features[k] <= 8'sd0;
            for (k = 0; k < NUM_HIDDEN; k = k + 1)
                hidden[k] <= 16'sd0;
            for (k = 0; k < NUM_OUTPUTS; k = k + 1)
                output_val[k] <= 16'sd0;
        end else begin
            // Defaults — deassert one-shot controls each cycle
            mac_clear    <= 1'b0;
            mac_valid    <= 1'b0;
            mac_add_bias <= 1'b0;
            class_valid  <= 1'b0;

            case (state)

            // ----------------------------------------------------------
            // IDLE: Wait for new feature vector
            // ----------------------------------------------------------
            S_IDLE: begin
                busy <= 1'b0;
                if (features_valid) begin
                    state <= S_LOAD;
                    busy  <= 1'b1;
                end
            end

            // ----------------------------------------------------------
            // LOAD: Latch the 80-bit feature vector into registers
            // ----------------------------------------------------------
            S_LOAD: begin
                // Unpack: feature[0] = MSB byte, feature[9] = LSB byte
                // feature_vector[79:72] = feature 0, ... [7:0] = feature 9
                for (k = 0; k < NUM_INPUTS; k = k + 1)
                    features[k] <= feature_vector[(NUM_INPUTS-1-k)*8 +: 8];

                // Initialize for Layer 1 processing
                neuron_idx     <= 4'd0;
                input_idx      <= 4'd0;
                num_inputs_cur <= NUM_INPUTS[3:0];
                sub_state      <= SUB_CLEAR;
                state          <= S_LAYER1;
            end

            // ----------------------------------------------------------
            // LAYER1: Compute 8 hidden neurons sequentially
            //   Each neuron: CLEAR -> (ADDR->MAC) x 10 -> ADDR(bias)->BIAS
            // ----------------------------------------------------------
            S_LAYER1: begin
                case (sub_state)

                SUB_CLEAR: begin
                    // Clear the MAC accumulator
                    mac_clear <= 1'b1;
                    input_idx <= 4'd0;
                    // Pre-fetch first weight address for this neuron
                    rom_addr  <= L1_WEIGHT_BASE
                                 + {3'b0, neuron_idx} * NUM_INPUTS;
                    sub_state <= SUB_ADDR;
                end

                SUB_ADDR: begin
                    // ROM address was set last cycle; data arrives next cycle.
                    // Set address for weight[neuron_idx][input_idx].
                    rom_addr  <= L1_WEIGHT_BASE
                                 + {3'b0, neuron_idx} * NUM_INPUTS
                                 + {3'b0, input_idx};
                    sub_state <= SUB_MAC;
                end

                SUB_MAC: begin
                    // rom_data now holds weight[neuron_idx][input_idx]
                    mac_a     <= features[input_idx];
                    mac_b     <= rom_data;
                    mac_valid <= 1'b1;

                    if (input_idx == num_inputs_cur - 1) begin
                        // All inputs processed; next fetch bias
                        rom_addr  <= L1_BIAS_BASE + {3'b0, neuron_idx};
                        sub_state <= SUB_BIAS;
                    end else begin
                        // Fetch next weight
                        input_idx <= input_idx + 1;
                        rom_addr  <= L1_WEIGHT_BASE
                                     + {3'b0, neuron_idx} * NUM_INPUTS
                                     + {3'b0, input_idx} + 1;
                        sub_state <= SUB_MAC;  // stay in MAC (ROM pipeline)
                    end
                end

                SUB_BIAS: begin
                    // rom_data now holds bias[neuron_idx]
                    mac_bias     <= rom_data;
                    mac_add_bias <= 1'b1;
                    sub_state    <= SUB_CLEAR;
                    // Result will appear next cycle via mac_result_valid
                end

                default: sub_state <= SUB_CLEAR;
                endcase

                // Capture Layer 1 result (comes back with 1-cycle delay)
                if (mac_result_valid) begin
                    // Apply ReLU (relu_out is combinational from mac_result)
                    hidden[neuron_idx] <= relu_out;

                    if (neuron_idx == NUM_HIDDEN - 1) begin
                        // All hidden neurons done; move to Layer 2
                        neuron_idx     <= 4'd0;
                        input_idx      <= 4'd0;
                        num_inputs_cur <= NUM_HIDDEN[3:0];
                        sub_state      <= SUB_CLEAR;
                        state          <= S_LAYER2;
                    end else begin
                        neuron_idx <= neuron_idx + 1;
                        // sub_state already set to SUB_CLEAR
                    end
                end
            end

            // ----------------------------------------------------------
            // LAYER2: Compute 2 output neurons sequentially
            //   Same sub-state machine, but inputs are hidden[] and
            //   weights/biases from Layer 2 region of ROM.
            // ----------------------------------------------------------
            S_LAYER2: begin
                case (sub_state)

                SUB_CLEAR: begin
                    mac_clear <= 1'b1;
                    input_idx <= 4'd0;
                    rom_addr  <= L2_WEIGHT_BASE
                                 + {3'b0, neuron_idx} * NUM_HIDDEN;
                    sub_state <= SUB_ADDR;
                end

                SUB_ADDR: begin
                    rom_addr  <= L2_WEIGHT_BASE
                                 + {3'b0, neuron_idx} * NUM_HIDDEN
                                 + {3'b0, input_idx};
                    sub_state <= SUB_MAC;
                end

                SUB_MAC: begin
                    // For layer 2, inputs are the hidden activations.
                    // hidden[] is 16-bit Q6.10. We need 8-bit Q3.5 input
                    // to the MAC. Truncate: take bits [12:5] which
                    // represents the Q3.5 portion of Q6.10, with saturation.
                    mac_a     <= truncate_q610_to_q35(hidden[input_idx]);
                    mac_b     <= rom_data;
                    mac_valid <= 1'b1;

                    if (input_idx == num_inputs_cur - 1) begin
                        rom_addr  <= L2_BIAS_BASE + {3'b0, neuron_idx};
                        sub_state <= SUB_BIAS;
                    end else begin
                        input_idx <= input_idx + 1;
                        rom_addr  <= L2_WEIGHT_BASE
                                     + {3'b0, neuron_idx} * NUM_HIDDEN
                                     + {3'b0, input_idx} + 1;
                        sub_state <= SUB_MAC;
                    end
                end

                SUB_BIAS: begin
                    mac_bias     <= rom_data;
                    mac_add_bias <= 1'b1;
                    sub_state    <= SUB_CLEAR;
                end

                default: sub_state <= SUB_CLEAR;
                endcase

                // Capture Layer 2 result
                if (mac_result_valid) begin
                    output_val[neuron_idx] <= mac_result;

                    if (neuron_idx == NUM_OUTPUTS - 1) begin
                        state <= S_CLASSIFY;
                    end else begin
                        neuron_idx <= neuron_idx + 1;
                    end
                end
            end

            // ----------------------------------------------------------
            // CLASSIFY: Argmax of 2 output logits
            // ----------------------------------------------------------
            S_CLASSIFY: begin
                // output_val[0] = logit for class 0 (normal)
                // output_val[1] = logit for class 1 (abnormal)
                // classification = 1 if output_val[1] > output_val[0]
                if (output_val[1] > output_val[0])
                    classification <= 1'b1;
                else
                    classification <= 1'b0;

                state <= S_DONE;
            end

            // ----------------------------------------------------------
            // DONE: Assert class_valid for one cycle, return to IDLE
            // ----------------------------------------------------------
            S_DONE: begin
                class_valid <= 1'b1;
                busy        <= 1'b0;
                state       <= S_IDLE;
            end

            default: state <= S_IDLE;

            endcase
        end
    end

    // ===================================================================
    // Truncation function: Q6.10 (16-bit) -> Q3.5 (8-bit) with saturation
    // Drop 5 LSBs (fractional precision) and 3 MSBs (integer headroom).
    // Equivalent to arithmetic right-shift by 5, then saturate to 8-bit.
    // ===================================================================
    function signed [7:0] truncate_q610_to_q35;
        input signed [15:0] val;
        reg signed [15:0] shifted;
        begin
            shifted = val >>> 5;  // arithmetic right shift: Q6.10 -> Q6.5
            // Now saturate the Q6.5 value (11 significant bits) to Q3.5 (8 bits)
            if (shifted > 16'sd127)
                truncate_q610_to_q35 = 8'sd127;    // +3.96875
            else if (shifted < -16'sd128)
                truncate_q610_to_q35 = -8'sd128;   // -4.0
            else
                truncate_q610_to_q35 = shifted[7:0];
        end
    endfunction

endmodule
