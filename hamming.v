// =============================================================================
// Module  : hamming_distance
// Purpose : Compute the Hamming Distance between two 64-bit dHash signatures.
//
// Algorithm:
//   1. XOR the two hashes  →  xor_result[63:0]
//      Each '1' bit in xor_result marks a position where the hashes differ.
//   2. Count the number of '1' bits in xor_result  (population count / popcount)
//      Result range: 0 (identical) … 64 (completely different)
//
// Implementation:
//   Balanced binary adder tree - fully combinational, synthesisable to LUTs.
//   Stage widths grow by 1 bit per level to prevent overflow:
//     Stage 0  : 64 × 1-bit  (raw XOR bits)
//     Stage 1  : 32 × 2-bit  (sum pairs)
//     Stage 2  : 16 × 3-bit  (sum quads)
//     Stage 3  :  8 × 4-bit  (sum oct)
//     Stage 4  :  4 × 5-bit
//     Stage 5  :  2 × 6-bit
//     Stage 6  :  1 × 7-bit  (final count, 0..64)
// =============================================================================

module hamming_distance (
    input  wire [63:0] hash_a,      // dHash of image A
    input  wire [63:0] hash_b,      // dHash of image B
    output wire [ 6:0] distance     // Hamming distance: 0 (same) .. 64 (all differ)
);

    // -------------------------------------------------------------------------
    // Step 1: XOR - mark differing bit positions
    // -------------------------------------------------------------------------
    wire [63:0] xor_bits;
    assign xor_bits = hash_a ^ hash_b;

    // -------------------------------------------------------------------------
    // Step 2: Popcount via balanced adder tree
    // -------------------------------------------------------------------------

    // Stage 1 - 32 two-bit partial sums
    wire [1:0] s1 [0:31];
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : stage1
            assign s1[i] = {1'b0, xor_bits[i*2]} + {1'b0, xor_bits[i*2+1]};
        end
    endgenerate

    // Stage 2 - 16 three-bit partial sums
    wire [2:0] s2 [0:15];
    generate
        for (i = 0; i < 16; i = i + 1) begin : stage2
            assign s2[i] = {1'b0, s1[i*2]} + {1'b0, s1[i*2+1]};
        end
    endgenerate

    // Stage 3 - 8 four-bit partial sums
    wire [3:0] s3 [0:7];
    generate
        for (i = 0; i < 8; i = i + 1) begin : stage3
            assign s3[i] = {1'b0, s2[i*2]} + {1'b0, s2[i*2+1]};
        end
    endgenerate

    // Stage 4 - 4 five-bit partial sums
    wire [4:0] s4 [0:3];
    generate
        for (i = 0; i < 4; i = i + 1) begin : stage4
            assign s4[i] = {1'b0, s3[i*2]} + {1'b0, s3[i*2+1]};
        end
    endgenerate

    // Stage 5 - 2 six-bit partial sums
    wire [5:0] s5 [0:1];
    generate
        for (i = 0; i < 2; i = i + 1) begin : stage5
            assign s5[i] = {1'b0, s4[i*2]} + {1'b0, s4[i*2+1]};
        end
    endgenerate

    // Stage 6 - final 7-bit result
    assign distance = {1'b0, s5[0]} + {1'b0, s5[1]};

endmodule