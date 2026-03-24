// =============================================================================
// Module  : duplicate_detector
// Purpose : Compare a Hamming distance against a configurable threshold and
//           assert a 'is_duplicate' flag when the two images are similar enough.
//
// Similarity rule (standard dHash convention):
//   ● distance = 0        → bit-perfect match (identical images)
//   ● distance ≤ threshold → images are considered duplicates / near-duplicates
//   ● distance >  threshold → images are considered different
//
// Typical threshold values:
//   0  - exact duplicates only
//   10 - very similar (minor edits, slight compression artefacts)
//   20 - loosely similar
//   >20 - likely different images
//
// Ports:
//   distance     [6:0]  - Hamming distance from hamming_distance module (0..64)
//   threshold    [6:0]  - Configurable similarity threshold (0..64)
//   is_duplicate        - 1 when distance ≤ threshold (images are similar)
//   is_different        - 1 when distance >  threshold (images are different)
//                         (is_different = ~is_duplicate, provided for convenience)
// =============================================================================

module duplicate_detector (
    input  wire [6:0] distance,      // Hamming distance (0..64)
    input  wire [6:0] threshold,     // Similarity threshold (inclusive upper bound)
    output wire       is_duplicate,  // 1 → images are duplicates / near-duplicates
    output wire       is_different   // 1 → images are different
);

    // Purely combinational comparison - synthesises to a single 7-bit comparator
    assign is_duplicate = (distance <= threshold) ? 1'b1 : 1'b0;
    assign is_different = ~is_duplicate;

endmodule