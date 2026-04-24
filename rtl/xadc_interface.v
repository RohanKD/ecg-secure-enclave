//////////////////////////////////////////////////////////////////////////////
// xadc_interface.v
// XADC hard-macro interface for Basys 3 (Artix-7 XC7A35T)
//
// Reads analog input on VAUX6 (pins J3/K3) using the XADC primitive
// directly (no IP wizard). Continuous-sampling mode, 12-bit output.
//
// DRP address 16h = VAUX6 result register.
// The upper 12 bits of the 16-bit DO bus carry the ADC value.
//
// Flow:
//   1. Wait for tick_500hz assertion
//   2. Initiate DRP read of address 7'h16
//   3. Wait for DRDY
//   4. Capture upper 12 bits of DO, assert sample_valid for one cycle
//////////////////////////////////////////////////////////////////////////////

module xadc_interface(
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_500hz,
    // Note: VAUX6 analog pins (J3/K3) connect through dedicated XADC
    // analog routing — no top-level ports or IO buffers needed.
    output reg  [11:0] sample_data,
    output reg         sample_valid
);

    // -----------------------------------------------------------------------
    // DRP signals
    // -----------------------------------------------------------------------
    wire [15:0] do_drp;          // DRP data output
    wire        drdy;            // DRP data-ready
    reg  [6:0]  daddr;           // DRP address
    reg         den;             // DRP enable (read strobe)
    wire        dwe = 1'b0;     // DRP write enable (read-only)
    wire [15:0] di  = 16'h0000; // DRP data input  (unused)

    // XADC status / unused
    wire        busy;
    wire [4:0]  channel;
    wire        eoc;
    wire        eos;
    wire [7:0]  alarm;

    // -----------------------------------------------------------------------
    // XADC primitive instantiation
    // -----------------------------------------------------------------------
    XADC #(
        .INIT_40(16'h0000),  // Config reg 0: averaging disabled
        .INIT_41(16'h31AF),  // Config reg 1: continuous sequencer, calibration on
        .INIT_42(16'h0400),  // Config reg 2: ADCCLK = DCLK/4
        .INIT_48(16'h4701),  // Sequencer: VAUX6, calibration, temp, VCCINT
        .INIT_49(16'h0040),  // Sequencer: VAUX6 enabled
        .INIT_4A(16'h0000),  // Averaging: none
        .INIT_4B(16'h0000),  // Averaging: none
        .INIT_4C(16'h0000),  // Analog input mode: unipolar
        .INIT_4D(16'h0000),  // Analog input mode
        .INIT_4E(16'h0000),  // Settle time
        .INIT_4F(16'h0000),  // Settle time
        .INIT_50(16'hB5ED),  // Upper alarm: temperature
        .INIT_51(16'h57E4),  // Upper alarm: VCCINT
        .INIT_52(16'hA147),  // Upper alarm: VCCAUX
        .INIT_53(16'hCA33),  // Upper alarm: OT
        .INIT_54(16'hA93A),  // Lower alarm: temperature
        .INIT_55(16'h52C6),  // Lower alarm: VCCINT
        .INIT_56(16'h9555),  // Lower alarm: VCCAUX
        .INIT_57(16'hAE4E)   // Lower alarm: OT
    ) xadc_inst (
        // Clock and reset
        .DCLK       (clk),
        .RESET      (rst),
        // DRP interface
        .DADDR      (daddr),
        .DEN        (den),
        .DWE        (dwe),
        .DI         (di),
        .DO         (do_drp),
        .DRDY       (drdy),
        // XADC status
        .BUSY       (busy),
        .CHANNEL    (channel),
        .EOC        (eoc),
        .EOS        (eos),
        .ALM        (alarm),
        .OT         (),
        .MUXADDR    (),
        .JTAGBUSY   (),
        .JTAGLOCKED (),
        .JTAGMODIFIED(),
        // Dedicated analog input (unused - using auxiliary channel)
        .VP         (1'b0),
        .VN         (1'b0),
        // Auxiliary analog inputs - only VAUX6 connected
        // VAUX6 uses dedicated analog routing (no IBUF needed)
        .VAUXP      (16'b0),
        .VAUXN      (16'b0),
        // Alarm enables
        .CONVST     (1'b0),
        .CONVSTCLK  (1'b0)
    );

    // -----------------------------------------------------------------------
    // DRP read state machine
    // -----------------------------------------------------------------------
    localparam [1:0] S_IDLE     = 2'd0,
                     S_READ     = 2'd1,
                     S_WAIT     = 2'd2,
                     S_CAPTURE  = 2'd3;

    reg [1:0] state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= S_IDLE;
            daddr        <= 7'h00;
            den          <= 1'b0;
            sample_data  <= 12'd0;
            sample_valid <= 1'b0;
        end else begin
            // Default: deassert single-cycle pulses
            den          <= 1'b0;
            sample_valid <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                // IDLE: wait for the 500 Hz sample tick
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (tick_500hz) begin
                        state <= S_READ;
                    end
                end

                // ---------------------------------------------------------
                // READ: issue DRP read for VAUX6 result (address 0x16)
                // ---------------------------------------------------------
                S_READ: begin
                    daddr <= 7'h16;
                    den   <= 1'b1;
                    state <= S_WAIT;
                end

                // ---------------------------------------------------------
                // WAIT: wait for DRDY from the XADC
                // ---------------------------------------------------------
                S_WAIT: begin
                    if (drdy) begin
                        state <= S_CAPTURE;
                    end
                end

                // ---------------------------------------------------------
                // CAPTURE: latch the upper 12 bits and assert valid
                // ---------------------------------------------------------
                S_CAPTURE: begin
                    sample_data  <= do_drp[15:4];
                    sample_valid <= 1'b1;
                    state        <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
