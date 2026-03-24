// =============================================================================
// Module  : downscaler
// Purpose : Box-filter downscale a 640×480 greyscale image to 9×8.
//
// Input layout  : image_flat[ (row*640 + col)*8 +: 8 ]
//                 row ∈ [0..479],  col ∈ [0..639]
// Output layout : ds_flat[ (row*9 + col)*8 +: 8 ]
//                 row ∈ [0..7],    col ∈ [0..8]
//
// Tiling strategy
// ───────────────
//   Column 639 is ignored (640 ÷ 9 is not integer; we use 639 = 9 × 71).
//   Tile width  : 71 pixels   (9 × 71 = 639 ≤ 640)
//   Tile height : 60 pixels   (8 × 60 = 480)
//   Tile area   : 4 260 pixels per output pixel
//
// Division by 4 260
// ──────────────────
//   Integer reciprocal: avg ≈ (sum × 3939) >> 24
//
//   Proof of correctness:
//     max sum  = 4260 × 255 = 1 086 300        (fits in 21 bits, 2^21 = 2 097 152)
//     max prod = 1 086 300 × 3939 = 4 278 935 700  (fits in 32 bits, 2^32 = 4 294 967 296)
//     max output = 4 278 935 700 >> 24 = 255.03  → truncates to 255 ✓
//     uniform k: (4260×k×3939) >> 24 = k × 1.000174 → rounds to k for all k ∈ [0,255] ✓
//
// Synthesis note
// ──────────────
//   The always @(*) block with nested for-loops is fully synthesisable.
//   The synthesis tool unrolls the loops into a large but flat combinational
//   adder tree (72 instances of 4 260-input adders + 72 multipliers).
// =============================================================================

module downscaler (
    input  wire [640*480*8-1:0] image_flat,   // 640×480 input, row-major 8bpp
    output reg  [9*8*8-1:0]     ds_flat       // 9×8 output, row-major 8bpp
);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    localparam OUT_ROWS  = 8;
    localparam OUT_COLS  = 9;
    localparam TILE_W    = 71;   // columns per output pixel
    localparam TILE_H    = 60;   // rows    per output pixel
    localparam IMG_W     = 640;  // full image width (col 639 ignored)
    localparam RECIP     = 32'd3939;  // reciprocal factor  2^24 / 4260
    localparam RECIP_SHR = 24;        // right-shift amount

    // -------------------------------------------------------------------------
    // Combinational box filter
    // -------------------------------------------------------------------------
    integer ro, co, ri, ci;
    reg [20:0] blk_sum;   // max = 4260×255 = 1 086 300 < 2^21
    reg [31:0] product;   // max = 1 086 300×3939 = 4 278 935 700 < 2^32

    always @(*) begin
        for (ro = 0; ro < OUT_ROWS; ro = ro + 1) begin
            for (co = 0; co < OUT_COLS; co = co + 1) begin

                // ----- accumulate 4260 pixels --------------------------------
                blk_sum = 21'd0;
                for (ri = 0; ri < TILE_H; ri = ri + 1) begin
                    for (ci = 0; ci < TILE_W; ci = ci + 1) begin
                        blk_sum = blk_sum +
                            {13'd0,
                             image_flat[((ro*TILE_H + ri)*IMG_W + co*TILE_W + ci)*8 +: 8]};
                    end
                end

                // ----- reciprocal multiply, take top byte --------------------
                // {11'b0, blk_sum} zero-extends blk_sum to 32 bits
                product = {11'b0, blk_sum} * RECIP;
                ds_flat[(ro*OUT_COLS + co)*8 +: 8] = product[31:24];

            end
        end
    end

endmodule