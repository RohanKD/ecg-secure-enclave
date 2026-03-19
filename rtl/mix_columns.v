// =============================================================================
// mix_columns.v
// AES MixColumns: Galois Field multiplication of each column by the fixed
// polynomial matrix in GF(2^8) with irreducible polynomial x^8+x^4+x^3+x+1.
//
// Matrix:
//   [2 3 1 1]   [s0]
//   [1 2 3 1] * [s1]
//   [1 1 2 3]   [s2]
//   [3 1 1 2]   [s3]
//
// xtime(a): multiplication by 2 in GF(2^8)
//   = {a[6:0], 1'b0} ^ (8'h1b & {8{a[7]}})
//
// Multiplication by 3: xtime(a) ^ a
//
// Purely combinational. Operates on all 4 columns in parallel.
// Part of AES-128 Secure Enclave for Basys 3 (Artix-7)
// =============================================================================

module mix_columns(
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);

    // -------------------------------------------------------------------------
    // xtime function: multiply by 2 in GF(2^8)
    // -------------------------------------------------------------------------
    function [7:0] xtime;
        input [7:0] a;
        begin
            xtime = {a[6:0], 1'b0} ^ (8'h1b & {8{a[7]}});
        end
    endfunction

    // -------------------------------------------------------------------------
    // mix_single_column: apply MixColumns to one 32-bit column (4 bytes)
    // Input:  {s0, s1, s2, s3} (MSB first)
    // Output: {r0, r1, r2, r3}
    //
    // r0 = 2*s0 ^ 3*s1 ^ s2   ^ s3
    // r1 = s0   ^ 2*s1 ^ 3*s2 ^ s3
    // r2 = s0   ^ s1   ^ 2*s2 ^ 3*s3
    // r3 = 3*s0 ^ s1   ^ s2   ^ 2*s3
    // -------------------------------------------------------------------------
    function [31:0] mix_single_column;
        input [31:0] col;
        reg [7:0] s0, s1, s2, s3;
        reg [7:0] r0, r1, r2, r3;
        reg [7:0] xt0, xt1, xt2, xt3;
        begin
            s0 = col[31:24];
            s1 = col[23:16];
            s2 = col[15:8];
            s3 = col[7:0];

            xt0 = xtime(s0);
            xt1 = xtime(s1);
            xt2 = xtime(s2);
            xt3 = xtime(s3);

            // 3*x = xtime(x) ^ x
            r0 = xt0 ^ (xt1 ^ s1) ^ s2        ^ s3;
            r1 = s0  ^ xt1        ^ (xt2 ^ s2) ^ s3;
            r2 = s0  ^ s1         ^ xt2        ^ (xt3 ^ s3);
            r3 = (xt0 ^ s0) ^ s1  ^ s2         ^ xt3;

            mix_single_column = {r0, r1, r2, r3};
        end
    endfunction

    // -------------------------------------------------------------------------
    // Apply MixColumns to each of the 4 columns
    // State layout (column-major):
    //   Column 0: state_in[127:96]
    //   Column 1: state_in[95:64]
    //   Column 2: state_in[63:32]
    //   Column 3: state_in[31:0]
    // -------------------------------------------------------------------------
    assign state_out[127:96] = mix_single_column(state_in[127:96]);
    assign state_out[95:64]  = mix_single_column(state_in[95:64]);
    assign state_out[63:32]  = mix_single_column(state_in[63:32]);
    assign state_out[31:0]   = mix_single_column(state_in[31:0]);

endmodule
