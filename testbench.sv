// =============================================================================
// Testbench : image_similarity_top_tb
//
// Drives the complete 640×480 → dHash → Hamming → Duplicate pipeline with
// three carefully constructed image pairs.  A software reference model
// (pure Verilog tasks/functions) computes every intermediate value so the
// testbench is self-checking without hard-coded magic numbers.
//
// ─── Image pairs ─────────────────────────────────────────────────────────────
//
//  TEST 1 - IDENTICAL
//    A = column ramp : pixel(r,c) = c % 256
//    B = same image
//    ► Downscaled rows (all 8 rows identical):
//        [35, 106, 177, 147, 63, 134, 205, 74, 91]
//    ► hash_A = hash_B = 64'hB3B3_B3B3_B3B3_B3B3
//    ► dHash per-row derivation (bit 0 = leftmost comparison):
//         35<106=1  106<177=1  177<147=0  147<63=0
//         63<134=1  134<205=1  205<74=0   74<91=1
//         row byte = 1011_0011 = 0xB3
//    ► dist = 0  →  DUPLICATE
//
//  TEST 2 - NEAR-DUPLICATE  (1 hash bit flip)
//    A = column ramp (unchanged)
//    B = column ramp, but rows[0..59] × cols[213..283] set to 0
//        Box filter: ds_B[row0][col3] = 0  (was 147)
//        Comparison col3→col4:  0 < 63 = 1  (was 147 < 63 = 0)  ← bit3 flips
//    ► hash_A = 64'hB3B3_B3B3_B3B3_B3B3
//    ► hash_B = 64'hB3B3_B3B3_B3B3_B3BB   (only byte[0] changes: 0xB3→0xBB)
//    ► XOR    = 64'h0000_0000_0000_0008
//    ► dist = 1  →  DUPLICATE
//
//  TEST 3 - COMPLETELY DIFFERENT
//    A = column ramp : pixel(r,c) = c % 256
//    B = row    ramp : pixel(r,c) = r % 256
//        Each output row of B has identical values across all columns
//        → no left<right comparison is ever true
//    ► hash_A = 64'hB3B3_B3B3_B3B3_B3B3
//    ► hash_B = 64'h0000_0000_0000_0000
//    ► XOR    = 64'hB3B3_B3B3_B3B3_B3B3  popcount(0xB3)=5, 5×8 = 40
//    ► dist = 40  →  DIFFERENT (40 > threshold=10)
//
// ─── Simulation note ─────────────────────────────────────────────────────────
//   Each test iterates ~307 200 pixel assignments + 307 008 reference sums.
//   Expect a few minutes of wall-clock time on a typical workstation.
//
// ─── Compile command ─────────────────────────────────────────────────────────
//   iverilog -o sim \
//       dhash.v hamming_distance.v duplicate_detector.v \
//       downscaler.v image_similarity_top.v image_similarity_top_tb.v
//   vvp sim
// =============================================================================

`timescale 1ns/1ps

module image_similarity_top_tb;

    // =========================================================================
    // Threshold used for all three tests
    // =========================================================================
    localparam [6:0] THRESHOLD = 7'd10;

    // =========================================================================
    // DUT ports
    // =========================================================================
    reg  [640*480*8-1:0] image_a_flat;
    reg  [640*480*8-1:0] image_b_flat;
    reg  [6:0]           threshold;

    wire [9*8*8-1:0]     ds_a_flat;
    wire [9*8*8-1:0]     ds_b_flat;
    wire [63:0]          hash_a;
    wire [63:0]          hash_b;
    wire [6:0]           hamming_dist;
    wire                 is_duplicate;
    wire                 is_different;

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    image_similarity_top dut (
        .image_a_flat (image_a_flat),
        .image_b_flat (image_b_flat),
        .threshold    (threshold),
        .ds_a_flat    (ds_a_flat),
        .ds_b_flat    (ds_b_flat),
        .hash_a       (hash_a),
        .hash_b       (hash_b),
        .hamming_dist (hamming_dist),
        .is_duplicate (is_duplicate),
        .is_different (is_different)
    );

    // =========================================================================
    // Unpacked pixel scratch arrays  (row-major: index = row×640 + col)
    // =========================================================================
    reg [7:0] px_a [0:307199];
    reg [7:0] px_b [0:307199];
    integer   r, c;

    // =========================================================================
    // Pass/fail counters
    // =========================================================================
    integer pass_cnt, fail_cnt;

    // =========================================================================
    // Task: pack pixel arrays into DUT flat buses
    //   307 200 iterations - called once per test case
    // =========================================================================
    task pack_images;
        integer i;
        begin
            for (i = 0; i < 307200; i = i + 1) begin
                image_a_flat[i*8 +: 8] = px_a[i];
                image_b_flat[i*8 +: 8] = px_b[i];
            end
        end
    endtask

    // =========================================================================
    // Task: reference box-filter downscaler
    //   Mirrors downscaler.v: (sum × 3939) >> 24
    //   use_b = 0 → operate on px_a[], 1 → operate on px_b[]
    // =========================================================================
    task ref_downscale;
        input  integer  use_b;
        output [575:0]  ds_out;
        integer ro, co, ri, ci;
        reg [20:0] s;
        reg [31:0] p;
        begin
            for (ro = 0; ro < 8; ro = ro + 1) begin
                for (co = 0; co < 9; co = co + 1) begin
                    s = 21'd0;
                    for (ri = 0; ri < 60; ri = ri + 1)
                        for (ci = 0; ci < 71; ci = ci + 1)
                            s = s + (use_b
                                ? {13'd0, px_b[(ro*60+ri)*640 + co*71+ci]}
                                : {13'd0, px_a[(ro*60+ri)*640 + co*71+ci]});
                    p = {11'b0, s} * 32'd3939;
                    ds_out[(ro*9+co)*8 +: 8] = p[31:24];
                end
            end
        end
    endtask

    // =========================================================================
    // Function: reference dHash  (mirrors dhash.v)
    // =========================================================================
    function [63:0] ref_dhash;
        input [575:0] ds;
        integer rr, cc;
        reg [63:0] h;
        begin
            h = 64'd0;
            for (rr = 0; rr < 8; rr = rr + 1)
                for (cc = 0; cc < 8; cc = cc + 1)
                    if (ds[(rr*9+cc)*8 +: 8] < ds[(rr*9+cc+1)*8 +: 8])
                        h[rr*8 + cc] = 1'b1;
            ref_dhash = h;
        end
    endfunction

    // =========================================================================
    // Function: reference popcount (Hamming distance = popcount of XOR)
    // =========================================================================
    function [6:0] ref_popcount;
        input [63:0] v;
        integer k;
        reg [6:0] cnt;
        begin
            cnt = 7'd0;
            for (k = 0; k < 64; k = k + 1)
                cnt = cnt + {6'd0, v[k]};
            ref_popcount = cnt;
        end
    endfunction

    // =========================================================================
    // Task: print 9×8 downscaled pixel grid (decimal values)
    // =========================================================================
    task print_ds_grid;
        input [575:0] ds;
        integer rr, cc;
        begin
            $write("        Col:");
            for (cc = 0; cc < 9; cc = cc + 1) $write("  [%0d]", cc);
            $display("");
            $display("             ─────────────────────────────────────────────");
            for (rr = 0; rr < 8; rr = rr + 1) begin
                $write("    Row[%0d] │", rr);
                for (cc = 0; cc < 9; cc = cc + 1)
                    $write("  %3d", ds[(rr*9+cc)*8 +: 8]);
                $display("");
            end
        end
    endtask

    // =========================================================================
    // Task: print 64-bit hash with per-row byte breakdown
    // =========================================================================
    task print_hash_breakdown;
        input [63:0] h;
        integer rr;
        begin
            $display("    Full hash: 64'h%016h", h);
            $display("    Per-row bytes:");
            for (rr = 0; rr < 8; rr = rr + 1)
                $display("      Row[%0d]: 8'b%08b = 0x%02h",
                         rr, h[rr*8 +: 8], h[rr*8 +: 8]);
        end
    endtask

    // =========================================================================
    // Task: self-checking comparison of DUT vs reference
    // =========================================================================
    task check_outputs;
        input [575:0] exp_ds_a, exp_ds_b;
        input [63:0]  exp_ha, exp_hb;
        input [6:0]   exp_dist;
        input         exp_dup;

        begin
            // ---- Downscaled image A ----
            if (ds_a_flat === exp_ds_a) begin
                $display("  PASS  Downscaled A matches reference");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  Downscaled A mismatch (see grid diff)");
                fail_cnt = fail_cnt + 1;
            end

            // ---- Downscaled image B ----
            if (ds_b_flat === exp_ds_b) begin
                $display("  PASS  Downscaled B matches reference");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  Downscaled B mismatch (see grid diff)");
                fail_cnt = fail_cnt + 1;
            end

            // ---- Hash A ----
            if (hash_a === exp_ha) begin
                $display("  PASS  hash_a = 64'h%016h  ✓", hash_a);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  hash_a: DUT=64'h%016h  REF=64'h%016h",
                         hash_a, exp_ha);
                fail_cnt = fail_cnt + 1;
            end

            // ---- Hash B ----
            if (hash_b === exp_hb) begin
                $display("  PASS  hash_b = 64'h%016h  ✓", hash_b);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  hash_b: DUT=64'h%016h  REF=64'h%016h",
                         hash_b, exp_hb);
                fail_cnt = fail_cnt + 1;
            end

            // ---- Hamming distance ----
            if (hamming_dist === exp_dist) begin
                $display("  PASS  Hamming distance = %0d  ✓", hamming_dist);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  Hamming dist: DUT=%0d  REF=%0d",
                         hamming_dist, exp_dist);
                fail_cnt = fail_cnt + 1;
            end

            // ---- Duplicate flag ----
            if (is_duplicate === exp_dup) begin
                $display("  PASS  is_duplicate=%0b  →  %0s  ✓",
                         is_duplicate,
                         is_duplicate ? "*** DUPLICATE ***" : "--- DIFFERENT ---");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  is_duplicate: DUT=%0b  REF=%0b",
                         is_duplicate, exp_dup);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================================
    // Intermediate reference storage
    // =========================================================================
    reg [575:0] ref_ds_a, ref_ds_b;
    reg [63:0]  ref_ha,   ref_hb;
    reg [6:0]   ref_dist;
    reg         ref_dup;

    // =========================================================================
    // ── MAIN TEST SEQUENCE ──
    // =========================================================================
    initial begin
        pass_cnt     = 0;
        fail_cnt     = 0;
        threshold    = THRESHOLD;
        image_a_flat = {(640*480*8){1'b0}};
        image_b_flat = {(640*480*8){1'b0}};

        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  Full Pipeline Testbench                                     ║");
        $display("║  640×480 → Box Filter → dHash → Hamming → Duplicate Check   ║");
        $display("║  Threshold = %0d                                              ║", threshold);
        $display("╚══════════════════════════════════════════════════════════════╝");

        // =====================================================================
        // TEST 1 - IDENTICAL IMAGES
        // ─────────────────────────
        // A = B = column ramp:  pixel(r,c) = c % 256
        //
        // Downscaling  (tile 71×60=4260, reciprocal ×3939>>24):
        //   Tile col 0 : cols   0..70   avg(  0.. 70) = 35
        //   Tile col 1 : cols  71..141  avg( 71..141) = 106
        //   Tile col 2 : cols 142..212  avg(142..212) = 177
        //   Tile col 3 : cols 213..283  avg(213..255,0..27) = 147
        //   Tile col 4 : cols 284..354  avg( 28.. 98) = 63
        //   Tile col 5 : cols 355..425  avg( 99..169) = 134
        //   Tile col 6 : cols 426..496  avg(170..240) = 205
        //   Tile col 7 : cols 497..567  avg(241..255,0..55) = 74
        //   Tile col 8 : cols 568..638  avg( 56..126) = 91
        //   → all 8 rows downscale identically: [35,106,177,147,63,134,205,74,91]
        //
        // dHash per row (bit c = pixel[c]<pixel[c+1]):
        //   c0: 35<106=1  c1: 106<177=1  c2: 177<147=0  c3: 147<63=0
        //   c4:  63<134=1  c5: 134<205=1  c6: 205<74=0   c7:  74<91=1
        //   byte = 8'b10110011 = 0xB3
        //
        // hash_A = hash_B = 64'hB3B3_B3B3_B3B3_B3B3
        // XOR = 0, distance = 0  →  DUPLICATE
        // =====================================================================
        $display("");
        $display("════════════════════════════════════════════════════════════════");
        $display("  TEST 1 - IDENTICAL IMAGES");
        $display("  A: pixel(r,c) = c %% 256  (column ramp)");
        $display("  B: same image");
        $display("  ► Expected hash_A = hash_B = 64'hB3B3B3B3B3B3B3B3");
        $display("  ► Expected dist = 0  →  DUPLICATE");
        $display("════════════════════════════════════════════════════════════════");

        for (r = 0; r < 480; r = r + 1)
            for (c = 0; c < 640; c = c + 1) begin
                px_a[r*640 + c] = c[7:0];   // c % 256
                px_b[r*640 + c] = c[7:0];
            end
        pack_images;

        // Compute reference values
        ref_downscale(0, ref_ds_a);
        ref_downscale(1, ref_ds_b);
        ref_ha   = ref_dhash(ref_ds_a);
        ref_hb   = ref_dhash(ref_ds_b);
        ref_dist = ref_popcount(ref_ha ^ ref_hb);
        ref_dup  = (ref_dist <= threshold) ? 1'b1 : 1'b0;

        #2; // combinational propagation

        $display("");
        $display("  ── Downscaled Image A ──────────────────────────────────────");
        print_ds_grid(ds_a_flat);
        $display("");
        $display("  ── Downscaled Image B ──────────────────────────────────────");
        print_ds_grid(ds_b_flat);
        $display("");
        $display("  ── dHash A ─────────────────────────────────────────────────");
        print_hash_breakdown(hash_a);
        $display("");
        $display("  ── dHash B ─────────────────────────────────────────────────");
        print_hash_breakdown(hash_b);
        $display("");
        $display("  XOR of hashes  = 64'h%016h", hash_a ^ hash_b);
        $display("  Hamming dist   = %0d", hamming_dist);
        $display("  Verdict        = %0s", is_duplicate ? "DUPLICATE" : "DIFFERENT");
        $display("  ── Checking DUT vs Reference ────────────────────────────────");
        check_outputs(ref_ds_a, ref_ds_b, ref_ha, ref_hb, ref_dist, ref_dup);

        // =====================================================================
        // TEST 2 - NEAR-DUPLICATE  (single-block zeroing flips 1 hash bit)
        // ─────────────────────────────────────────────────────────────────────
        // A = column ramp  (unchanged from Test 1)
        // B = column ramp  BUT rows[0..59] × cols[213..283] are all set to 0
        //
        // The zeroed region is exactly output tile (row0, col3):
        //   → ds_B[row0][col3] = 0   (was 147)
        //
        // dHash row 0 changes at c3:  0 < 63 = 1  (was 147 < 63 = 0)
        //   New byte row 0 = 8'b10111011 = 0xBB
        //   All other rows unchanged = 0xB3
        //
        // hash_A = 64'hB3B3_B3B3_B3B3_B3B3
        // hash_B = 64'hB3B3_B3B3_B3B3_B3BB  (byte[0]: 0xB3 → 0xBB)
        // XOR    = 64'h0000_0000_0000_0008
        // dist   = popcount(0x08) = 1  →  DUPLICATE (1 ≤ 10)
        // =====================================================================
        $display("");
        $display("════════════════════════════════════════════════════════════════");
        $display("  TEST 2 - NEAR-DUPLICATE  (1 hash bit flip)");
        $display("  A: pixel(r,c) = c %% 256  (column ramp)");
        $display("  B: same, but rows[0..59] x cols[213..283] = 0");
        $display("     → ds_B[row0][col3]: 147 → 0");
        $display("     → bit3 of row0 hash: 0 → 1");
        $display("  ► Expected hash_A = 64'hB3B3B3B3B3B3B3B3");
        $display("  ► Expected hash_B = 64'hB3B3B3B3B3B3B3BB");
        $display("  ► Expected dist = 1  →  DUPLICATE");
        $display("════════════════════════════════════════════════════════════════");

        // px_a unchanged; rebuild px_b
        for (r = 0; r < 480; r = r + 1)
            for (c = 0; c < 640; c = c + 1)
                px_b[r*640 + c] = c[7:0];
        // Zero the block that maps to output tile (row0, col3)
        for (r = 0; r < 60; r = r + 1)
            for (c = 213; c <= 283; c = c + 1)
                px_b[r*640 + c] = 8'd0;
        pack_images;

        ref_downscale(0, ref_ds_a);
        ref_downscale(1, ref_ds_b);
        ref_ha   = ref_dhash(ref_ds_a);
        ref_hb   = ref_dhash(ref_ds_b);
        ref_dist = ref_popcount(ref_ha ^ ref_hb);
        ref_dup  = (ref_dist <= threshold) ? 1'b1 : 1'b0;

        #2;

        $display("");
        $display("  ── Downscaled Image A ──────────────────────────────────────");
        print_ds_grid(ds_a_flat);
        $display("");
        $display("  ── Downscaled Image B (note col3, row0 = 0) ────────────────");
        print_ds_grid(ds_b_flat);
        $display("");
        $display("  ── dHash A ─────────────────────────────────────────────────");
        print_hash_breakdown(hash_a);
        $display("");
        $display("  ── dHash B ─────────────────────────────────────────────────");
        print_hash_breakdown(hash_b);
        $display("");
        $display("  XOR of hashes  = 64'h%016h", hash_a ^ hash_b);
        $display("  Hamming dist   = %0d  (1 bit flipped)", hamming_dist);
        $display("  Verdict        = %0s  (within threshold %0d)",
                 is_duplicate ? "DUPLICATE" : "DIFFERENT", threshold);
        $display("  ── Checking DUT vs Reference ────────────────────────────────");
        check_outputs(ref_ds_a, ref_ds_b, ref_ha, ref_hb, ref_dist, ref_dup);

        // =====================================================================
        // TEST 3 - COMPLETELY DIFFERENT
        // ─────────────────────────────
        // A = column ramp : pixel(r,c) = c % 256
        // B = row    ramp : pixel(r,c) = r % 256
        //
        // Downscaling Image B:
        //   Each output pixel (rout, cout) = average over 71 columns of the
        //   same row-value (independent of column).
        //   → all 9 output columns in each output row are EQUAL.
        //   → no comparison pixel[c] < pixel[c+1] is ever TRUE
        //   → hash_B = 64'h0000_0000_0000_0000
        //
        // Downscaled B row averages (sum r%256 over 60-row block):
        //   Row 0: rows   0..59  → avg = 29
        //   Row 1: rows  60..119 → avg = 89
        //   Row 2: rows 120..179 → avg = 149
        //   Row 3: rows 180..239 → avg = 209
        //   Row 4: rows 240..299 → avg ≈ 81  (wraps at 255→0)
        //   Row 5: rows 300..359 → avg ≈ 73
        //   Row 6: rows 360..419 → avg ≈ 133
        //   Row 7: rows 420..479 → avg ≈ 193
        //
        // hash_A = 64'hB3B3_B3B3_B3B3_B3B3
        // hash_B = 64'h0000_0000_0000_0000
        // XOR    = 64'hB3B3_B3B3_B3B3_B3B3  → popcount(0xB3)=5, 5×8 rows = 40
        // dist   = 40  →  DIFFERENT (40 > threshold=10)
        // =====================================================================
        $display("");
        $display("════════════════════════════════════════════════════════════════");
        $display("  TEST 3 - COMPLETELY DIFFERENT");
        $display("  A: pixel(r,c) = c %% 256  (column ramp)");
        $display("  B: pixel(r,c) = r %% 256  (row ramp)");
        $display("     After downscaling, all 9 cols in each B row are equal");
        $display("     → no increasing adjacent pair → hash_B = 0");
        $display("  ► Expected hash_A = 64'hB3B3B3B3B3B3B3B3");
        $display("  ► Expected hash_B = 64'h0000000000000000");
        $display("  ► Expected dist = 40  →  DIFFERENT");
        $display("════════════════════════════════════════════════════════════════");

        // px_a unchanged (column ramp)
        for (r = 0; r < 480; r = r + 1)
            for (c = 0; c < 640; c = c + 1)
                px_b[r*640 + c] = r[7:0];   // r % 256
        pack_images;

        ref_downscale(0, ref_ds_a);
        ref_downscale(1, ref_ds_b);
        ref_ha   = ref_dhash(ref_ds_a);
        ref_hb   = ref_dhash(ref_ds_b);
        ref_dist = ref_popcount(ref_ha ^ ref_hb);
        ref_dup  = (ref_dist <= threshold) ? 1'b1 : 1'b0;

        #2;

        $display("");
        $display("  ── Downscaled Image A (column ramp) ────────────────────────");
        print_ds_grid(ds_a_flat);
        $display("");
        $display("  ── Downscaled Image B (row ramp - all cols equal per row) ──");
        print_ds_grid(ds_b_flat);
        $display("");
        $display("  ── dHash A ─────────────────────────────────────────────────");
        print_hash_breakdown(hash_a);
        $display("");
        $display("  ── dHash B ─────────────────────────────────────────────────");
        print_hash_breakdown(hash_b);
        $display("");
        $display("  XOR of hashes  = 64'h%016h", hash_a ^ hash_b);
        $display("  Hamming dist   = %0d  (40 bits differ)", hamming_dist);
        $display("  Verdict        = %0s  (exceeds threshold %0d)",
                 is_duplicate ? "DUPLICATE" : "DIFFERENT", threshold);
        $display("  ── Checking DUT vs Reference ────────────────────────────────");
        check_outputs(ref_ds_a, ref_ds_b, ref_ha, ref_hb, ref_dist, ref_dup);

        // =====================================================================
        // Summary
        // =====================================================================
        $display("");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║  FINAL RESULTS                                               ║");
        $display("╠══════════════════════════════════════════════════════════════╣");
        $display("║  PASSED : %0d / %0d checks                                    ║",
                 pass_cnt, pass_cnt + fail_cnt);
        $display("║  FAILED : %0d                                                 ║", fail_cnt);
        if (fail_cnt == 0) begin
            $display("║  ✓  ALL CHECKS PASSED                                        ║");
        end else begin
            $display("║  ✗  SOME CHECKS FAILED - see log above                       ║");
        end
        $display("╚══════════════════════════════════════════════════════════════╝");

        $finish;
    end

endmodule