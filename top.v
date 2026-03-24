// =============================================================================
// Module  : image_similarity_top
// Purpose : Full image-similarity pipeline for two 640×480 greyscale images.
//
// Pipeline stages
// ───────────────
//   1. downscaler  (×2) : 640×480 → 9×8 via box filter (column 639 ignored)
//   2. dhash       (×2) : 9×8 → 64-bit difference hash
//   3. hamming_distance : 64b × 64b → 7-bit popcount of XOR
//   4. duplicate_detector: distance ≤ threshold → is_duplicate
//
// All stages are combinational; the entire module is a purely combinational
// network and is fully synthesisable.
//
// Port summary
// ────────────
//   image_a_flat  [640×480×8-1 : 0]  Image A pixel data, row-major 8bpp
//   image_b_flat  [640×480×8-1 : 0]  Image B pixel data, row-major 8bpp
//   threshold     [6:0]              Hamming distance threshold (typical: 10)
//
//   ds_a_flat     [9×8×8-1 : 0]      Downscaled 9×8 image A (for inspection)
//   ds_b_flat     [9×8×8-1 : 0]      Downscaled 9×8 image B (for inspection)
//   hash_a        [63:0]             64-bit dHash of image A
//   hash_b        [63:0]             64-bit dHash of image B
//   hamming_dist  [6:0]              Hamming distance (0 = identical, 64 = max)
//   is_duplicate                     1 when distance ≤ threshold
//   is_different                     1 when distance >  threshold
// =============================================================================

module image_similarity_top (
    // ----- Inputs ------------------------------------------------------------
    input  wire [640*480*8-1:0] image_a_flat,
    input  wire [640*480*8-1:0] image_b_flat,
    input  wire [6:0]            threshold,

    // ----- Intermediate outputs (observable in testbench) --------------------
    output wire [9*8*8-1:0]      ds_a_flat,
    output wire [9*8*8-1:0]      ds_b_flat,

    // ----- Final outputs -----------------------------------------------------
    output wire [63:0]           hash_a,
    output wire [63:0]           hash_b,
    output wire [6:0]            hamming_dist,
    output wire                  is_duplicate,
    output wire                  is_different
);

    // -------------------------------------------------------------------------
    // Stage 1 - Box-filter downscale: 640×480 → 9×8
    // -------------------------------------------------------------------------
    downscaler u_ds_a (
        .image_flat (image_a_flat),
        .ds_flat    (ds_a_flat)
    );

    downscaler u_ds_b (
        .image_flat (image_b_flat),
        .ds_flat    (ds_b_flat)
    );

    // -------------------------------------------------------------------------
    // Stage 2 - Difference hash: 9×8 → 64-bit signature
    // -------------------------------------------------------------------------
    dhash u_hash_a (
        .image_flat (ds_a_flat),
        .hash       (hash_a)
    );

    dhash u_hash_b (
        .image_flat (ds_b_flat),
        .hash       (hash_b)
    );

    // -------------------------------------------------------------------------
    // Stage 3 - Hamming distance: XOR + popcount
    // -------------------------------------------------------------------------
    hamming_distance u_hd (
        .hash_a   (hash_a),
        .hash_b   (hash_b),
        .distance (hamming_dist)
    );

    // -------------------------------------------------------------------------
    // Stage 4 - Duplicate detector: distance vs threshold
    // -------------------------------------------------------------------------
    duplicate_detector u_dd (
        .distance    (hamming_dist),
        .threshold   (threshold),
        .is_duplicate(is_duplicate),
        .is_different(is_different)
    );

endmodule