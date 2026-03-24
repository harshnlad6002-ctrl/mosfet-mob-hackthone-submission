// =============================================================================
// Module  : dhash
// Purpose : Compute a 64-bit Difference Hash (dHash) from a 9×8 greyscale
//           image.
//
// Image layout (row-major, left-to-right, top-to-bottom):
//   pixel[row][col]  →  image_flat[ (row*9 + col)*8 +: 8 ]
//   row ∈ [0..7],  col ∈ [0..8]   → 72 pixels × 8 bits = 576-bit input
//
// Algorithm:
//   For each row r (0..7) and each column c (0..7):
//     hash_bit[ r*8 + c ] = (pixel[r][c] < pixel[r][c+1]) ? 1 : 0
//
// The module is purely combinational; wrap in registers if pipelining needed.
// =============================================================================

module dhash (
    input  wire [575:0] image_flat,   // 72 pixels × 8 bits, row-major
    output wire [63:0]  hash          // 64-bit dHash signature
);

    // -------------------------------------------------------------------------
    // Unpack all 72 pixels into a 2-D array using a generate block.
    // pixel_arr[row][col] = 8-bit greyscale value.
    // -------------------------------------------------------------------------
    wire [7:0] pixel_arr [0:7][0:8];   // [row 0..7][col 0..8]

    genvar gr, gc;
    generate
        for (gr = 0; gr < 8; gr = gr + 1) begin : gen_row
            for (gc = 0; gc < 9; gc = gc + 1) begin : gen_col
                assign pixel_arr[gr][gc] =
                    image_flat[ (gr * 9 + gc) * 8 +: 8 ];
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Compute 64 hash bits: one per (row, column-pair) comparison.
    // hash[ r*8 + c ] = 1  when pixel[r][c] < pixel[r][c+1]
    // -------------------------------------------------------------------------
    genvar hr, hc;
    generate
        for (hr = 0; hr < 8; hr = hr + 1) begin : gen_hash_row
            for (hc = 0; hc < 8; hc = hc + 1) begin : gen_hash_col
                assign hash[ hr * 8 + hc ] =
                    (pixel_arr[hr][hc] < pixel_arr[hr][hc + 1]) ? 1'b1 : 1'b0;
            end
        end
    endgenerate

endmodule