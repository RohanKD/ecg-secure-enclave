// =============================================================================
// shift_rows.v
// AES ShiftRows: Cyclic left-shift of rows in the 4x4 state matrix
//
// State byte layout (column-major, 128 bits):
//   [127:120] = s[0][0]   [95:88] = s[0][1]   [63:56] = s[0][2]   [31:24] = s[0][3]
//   [119:112] = s[1][0]   [87:80] = s[1][1]   [55:48] = s[1][2]   [23:16] = s[1][3]
//   [111:104] = s[2][0]   [79:72] = s[2][1]   [47:40] = s[2][2]   [15:8]  = s[2][3]
//   [103:96]  = s[3][0]   [71:64] = s[3][1]   [39:32] = s[3][2]   [7:0]   = s[3][3]
//
// Row 0: no shift
// Row 1: cyclic left shift by 1 position
// Row 2: cyclic left shift by 2 positions
// Row 3: cyclic left shift by 3 positions
//
// Purely combinational (no clock needed).
// Part of AES-128 Secure Enclave for Basys 3 (Artix-7)
// =============================================================================

module shift_rows(
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);

    // -------------------------------------------------------------------------
    // Extract input bytes: s[row][col]
    // Column 0
    wire [7:0] s00 = state_in[127:120];
    wire [7:0] s10 = state_in[119:112];
    wire [7:0] s20 = state_in[111:104];
    wire [7:0] s30 = state_in[103:96];
    // Column 1
    wire [7:0] s01 = state_in[95:88];
    wire [7:0] s11 = state_in[87:80];
    wire [7:0] s21 = state_in[79:72];
    wire [7:0] s31 = state_in[71:64];
    // Column 2
    wire [7:0] s02 = state_in[63:56];
    wire [7:0] s12 = state_in[55:48];
    wire [7:0] s22 = state_in[47:40];
    wire [7:0] s32 = state_in[39:32];
    // Column 3
    wire [7:0] s03 = state_in[31:24];
    wire [7:0] s13 = state_in[23:16];
    wire [7:0] s23 = state_in[15:8];
    wire [7:0] s33 = state_in[7:0];

    // -------------------------------------------------------------------------
    // Apply ShiftRows
    // Row 0: no shift       -> s00, s01, s02, s03
    // Row 1: left shift 1   -> s11, s12, s13, s10
    // Row 2: left shift 2   -> s22, s23, s20, s21
    // Row 3: left shift 3   -> s33, s30, s31, s32

    // Reassemble into column-major output
    // Column 0: row0=s00, row1=s11, row2=s22, row3=s33
    // Column 1: row0=s01, row1=s12, row2=s23, row3=s30
    // Column 2: row0=s02, row1=s13, row2=s20, row3=s31
    // Column 3: row0=s03, row1=s10, row2=s21, row3=s32

    assign state_out = {
        // Column 0
        s00, s11, s22, s33,
        // Column 1
        s01, s12, s23, s30,
        // Column 2
        s02, s13, s20, s31,
        // Column 3
        s03, s10, s21, s32
    };

endmodule
