// Font-pixel / cell alignment debug overlay for Ghostty.
//
// Purpose
// -------
// Draws, on top of the (un-warped) terminal image:
//   * a box around every character cell,
//   * a line at every font-pixel column / row boundary,
//   * a tick at every font-pixel row *center* (where a CRT scanline beam sits).
//
// Because nothing here warps or resamples, the overlay sits 1:1 on the real
// rasterized glyphs, so you can judge honestly whether the grid the CRT shader
// assumes actually lands on the font's pixels as you ctrl +/- the font size.
//
// Uniforms supplied by the cell-size patch (see patches/ghostty-cell-size-uniform.patch):
//   iCellSize.xy  = cell size in screen px (tracks font-size + zoom)
//   iCellSize.z   = em top:    px from cell top to the top of the rasterized em box
//   iCellSize.w   = em height: rasterized height of the full 16-row em box
//   iGridPadding  = grid padding {top, right, bottom, left} in screen px
//
// iCellSize.z/.w come from rendering a full-em reference glyph (U+E000), so they
// describe exactly where and how tall the on-screen font-pixel grid is.
//
// fragCoord uses a bottom-left origin (custom_shader_y_is_down == false), and
// iGridPadding is {top,right,bottom,left}; both are handled below.

// Native font-pixel grid of one cell (Free CG98: 8x16 PC-98 glyphs).
#define FONT_COLS 8.0
#define FONT_ROWS 16.0

// Vertical reference for the 16 font-pixel rows:
//   0 = EXACT   : rows taken straight from the rasterized em box the patch reports
//                 (origin = iCellSize.z, pitch = iCellSize.w/16). This is exactly
//                 what crt-geom.glsl now uses, and lands on the real font pixels.
//   1 = CELL    : 16 rows stretched across the WHOLE cell height (pitch =
//                 cell.y/16, offset = 0). The old crt-geom assumption; produces
//                 tall rectangles because the cell can be taller than the em box.
//   2 = SQUARE  : square pixels (pitch = cell.x/8) centered in the cell. A decent
//                 approximation, but off by the cell_baseline rounding the EXACT
//                 mode folds in.
#define ROW_ALIGN_MODE 0

// Draw font-pixel row centers (scanline beam centers) as well as boundaries.
#define SHOW_ROW_CENTERS 1

// How much to dim the underlying terminal so the overlay reads clearly.
#define BG_DIM 0.40

// Line half-widths in screen px (full width ~= 2*half, plus 1px AA falloff).
#define CELL_LINE_HALF   0.75
#define PIXEL_LINE_HALF  0.40
#define CENTER_LINE_HALF 0.40

// Overlay colors (linear-ish sRGB, drawn straight over the dimmed image).
#define COL_CELL    vec3(0.10, 1.00, 0.25)   // cell box        : green
#define COL_COLLINE vec3(0.20, 0.85, 1.00)   // font columns    : cyan
#define COL_ROWLINE vec3(1.00, 0.25, 0.25)   // font rows       : red
#define COL_CENTER  vec3(1.00, 0.95, 0.20)   // row centers     : yellow

// Coverage (0..1) of a line, given the pixel distance to it.
float lineCoverage(float distPx, float halfPx) {
  return 1.0 - smoothstep(halfPx, halfPx + 1.0, distPx);
}

// Distance, in the same units as `coord`, to the nearest k*pitch boundary whose
// index lies in [loIdx, hiIdx]. Returns a large number when out of range.
float nearestBoundaryDist(float coord, float pitch, float loIdx, float hiIdx) {
  float f = coord / pitch;
  float k = clamp(floor(f + 0.5), loIdx, hiIdx);
  return abs(coord - k * pitch);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 res = iResolution.xy;
  vec3 bg = texture(iChannel0, fragCoord / res).rgb;

  vec2 cell = iCellSize.xy;
  float emTop = iCellSize.z;
  float emHeight = iCellSize.w;
  vec4 pad = max(iGridPadding, vec4(0.0)); // {top,right,bottom,left}

  // Without the patch's metrics there's nothing meaningful to draw.
  if (cell.x <= 0.5 || cell.y <= 0.5) {
    fragColor = vec4(bg, 1.0);
    return;
  }

  // Move into a top-left origin and subtract the grid's top/left padding so the
  // origin is the top-left corner of cell (0,0).
  vec2 grid = vec2(fragCoord.x - pad.w, (res.y - fragCoord.y) - pad.x);

  // Coordinates within the current cell, [0,cell).
  vec2 inCell = vec2(
      grid.x - floor(grid.x / cell.x) * cell.x,
      grid.y - floor(grid.y / cell.y) * cell.y);

  vec3 col = bg * BG_DIM;

  // --- font-pixel columns ----------------------------------------------------
  // Columns span the full cell width with no gap, so this is the true (square)
  // font-pixel size. Boundaries 1..FONT_COLS-1 are interior (0 and FONT_COLS
  // coincide with the cell box).
  float colPitch = cell.x / FONT_COLS;
  float dCol = nearestBoundaryDist(inCell.x, colPitch, 1.0, FONT_COLS - 1.0);
  col = mix(col, COL_COLLINE, lineCoverage(dCol, PIXEL_LINE_HALF));

  // --- font-pixel rows -------------------------------------------------------
  float rowOrigin;
  float rowPitch;
  float rowLo = 0.0;
  float rowHi = FONT_ROWS;
#if ROW_ALIGN_MODE == 1
  // Stretch 16 rows across the whole cell (old production assumption). The
  // top/bottom boundaries coincide with the cell box, so only draw interior.
  rowOrigin = 0.0;
  rowPitch = cell.y / FONT_ROWS;
  rowLo = 1.0;
  rowHi = FONT_ROWS - 1.0;
#elif ROW_ALIGN_MODE == 2
  // Square font pixels centered in the cell (approximation).
  rowPitch = colPitch;
  rowOrigin = (cell.y - FONT_ROWS * rowPitch) * 0.5;
#else
  // Exact rasterized em box: origin and pitch straight from the patch uniforms.
  rowOrigin = emTop;
  rowPitch = (emHeight > 0.5 ? emHeight : cell.y) / FONT_ROWS;
#endif

  float rowCoord = inCell.y - rowOrigin;
  float dRow = nearestBoundaryDist(rowCoord, rowPitch, rowLo, rowHi);
  col = mix(col, COL_ROWLINE, lineCoverage(dRow, PIXEL_LINE_HALF));

#if SHOW_ROW_CENTERS
  // Centers sit halfway between boundaries: (k+0.5)*pitch, k in [0, FONT_ROWS-1].
  float fc = rowCoord / rowPitch - 0.5;
  float kc = clamp(floor(fc + 0.5), 0.0, FONT_ROWS - 1.0);
  float dCenter = abs(rowCoord - (kc + 0.5) * rowPitch);
  col = mix(col, COL_CENTER, lineCoverage(dCenter, CENTER_LINE_HALF));
#endif

  // --- cell box (drawn last so it sits on top) -------------------------------
  float dCellEdgeX = min(inCell.x, cell.x - inCell.x);
  float dCellEdgeY = min(inCell.y, cell.y - inCell.y);
  float cellCov = max(
      lineCoverage(dCellEdgeX, CELL_LINE_HALF),
      lineCoverage(dCellEdgeY, CELL_LINE_HALF));
  col = mix(col, COL_CELL, cellCov);

  fragColor = vec4(col, 1.0);
}
