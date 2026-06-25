/*
    CRT-RVM (Timothy Lottes "Retro Video Monitor", 2021 / Ghostty)

    PUBLIC DOMAIN CRT SHADER  --  by Timothy Lottes
    The newest and most sophisticated of his CRT shaders, with three monitor
    modes. The original is a low-resolution *upsampler* (gather4, packed 16-bit,
    non-integer INPUT_DOT): it samples a small framebuffer and blows it up. That
    is the key mismatch for a terminal, where iChannel0 is already full-res text.

    This port keeps RVM's *look* (the defining behaviour of each mode) but feeds
    it from the rasterized font-pixel grid instead of a low-res buffer, exactly
    like crt-geom / crt-lottes -- so the emulated "dots" are the 8x16 font pixels
    and everything tracks ctrl +/- zoom:

      * HORIZONTAL: emulated columns = the 8 font-pixel columns of a cell
        (pitch cell.x/8, phased to the left grid padding).
      * VERTICAL  : emulated rows / scanlines = the 16 font-pixel rows of the em
        (pitch em_height/16, phased to the rasterized em box via iCellSize.z/.w).

    The shadow masks (modes 1/2) stay in screen pixels (own grid), like the
    source. Modes (compile-time, switched live by the tuner via #if):

      0  PVM/BVM 240p : no mask. Luminance-variable scanline width -- scanlines
                        fatten at bright peaks (phosphor bloom) -- with exposure
                        normalization so peak brightness is preserved.
      1  Wega 480p    : aperture grille, scanlines suppressed.
      2  arcade       : true slot mask (every other column shifted vertically),
                        with scanlines.
*/

// --- mode -------------------------------------------------------------------
// 0 = PVM/BVM 240p, 1 = Wega 480p, 2 = arcade slot mask.
#define RVM_MODE 0

// --- tweakable parameters ---------------------------------------------------
// Horizontal pixel hardness (Gaussian along font columns). -2 soft .. -6 hard.
#define HARDPIX -3.0
// Display warp (0 = flat, 1/8 = extreme). Source RVM ~ vec2(1/64, 1/24).
#define WARPX 0.01563
#define WARPY 0.04167

// Mode 0 scanline shape (slope of the cosine window; LARGER = thinner line).
//   DARK   = slope at a dark pixel  (thin line)
//   BRIGHT = slope at a bright pixel (fat line -> phosphor bloom at peaks)
// Bright < Dark so highlights bloom; their ratio drives exposure normalization
// (thin/dark lines are boosted back up so peak brightness survives).
#define RVM_SCAN_DARK 2.4
#define RVM_SCAN_BRIGHT 1.1
// Modes 1/2 reconstruction: scanline hardness (1 suppressed, 2 visible).
#define RVM_RECON_SOFT -2.0
#define RVM_SCAN_HARD -8.0

// Shadow-mask exposure-preservation strength (modes 1/2). 0.5 .. 1.0; lower =
// darker gaps / more aggressive mask. Source RVM uses 7/8.
#define RVM_DARK 0.875
// RGB-triad width in *screen px* (modes 1/2). Source grille = 3, slot = 3 wide.
#define MASKSIZE 6.0

// Overall brightness multiply (1.0 = no change).
#define BRIGHTBOOST 1.0
// Input/output gamma.
#define GAMMA_IN 2.4
#define GAMMA_OUT 2.2

#define RVM_2PI 6.28318530718

// Native pixel grid of the source bitmap font (Free CG98: 8x16 PC-98 glyphs).
#define FONT_NATIVE_COLS 8.0
#define FONT_NATIVE_ROWS 16.0

// --- shared globals (set in mainImage) --------------------------------------
//   coord.x = font column        (pitch cell.x/8, origin at the left padding)
//   coord.y = font row from top  (pitch em_height/16, origin at the em-box top)
vec2 gOutput;    // output size in screen px
float gPixX;     // horizontal font-pixel pitch in screen px (cell.x / 8)
float gOriginX;  // left grid padding in screen px
float gPixY;     // vertical font-pixel pitch in screen px (em_height / 16)
float gPhaseTop; // px from the top of the screen to the top of row 0

float ToLinear1(float c) {
  return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, GAMMA_IN);
}
vec3 ToLinear(vec3 c) {
  return vec3(ToLinear1(c.r), ToLinear1(c.g), ToLinear1(c.b));
}
float ToSrgb1(float c) {
  return (c < 0.0031308) ? c * 12.92 : 1.055 * pow(c, 1.0 / GAMMA_OUT) - 0.055;
}
vec3 ToSrgb(vec3 c) {
  return vec3(ToSrgb1(c.r), ToSrgb1(c.g), ToSrgb1(c.b));
}

// Nearest emulated sample: snap X to the font-column grid and Y to the font-row
// grid, then sample the terminal texture (linearized). Off-grid reads are zero.
vec3 Fetch(vec2 c, vec2 off) {
  float ix = floor(c.x + off.x);
  float iy = floor(c.y + off.y);
  float sx = ((ix + 0.5) * gPixX + gOriginX) / gOutput.x;
  float syTop = gPhaseTop + (iy + 0.5) * gPixY;
  float sy = 1.0 - syTop / gOutput.y; // texture uses a bottom-left origin
  if (max(abs(sx - 0.5), abs(sy - 0.5)) > 0.5) {
    return vec3(0.0);
  }
  return ToLinear(texture(iChannel0, vec2(sx, sy)).rgb);
}

// Signed distance to the nearest sample center (font cols in x, font rows in y).
vec2 Dist(vec2 c) {
  return -(fract(c) - vec2(0.5));
}

float Gaus(float pos, float scale) {
  return exp2(scale * pos * pos);
}

// 3-tap Gaussian filter along the (font-column) horizontal line.
vec3 Horz3(vec2 c, float off) {
  vec3 b = Fetch(c, vec2(-1.0, off));
  vec3 d = Fetch(c, vec2(0.0, off));
  vec3 e = Fetch(c, vec2(1.0, off));
  float dst = Dist(c).x;
  float wb = Gaus(dst - 1.0, HARDPIX);
  float wd = Gaus(dst + 0.0, HARDPIX);
  float we = Gaus(dst + 1.0, HARDPIX);
  return (b * wb + d * wd + e * we) / (wb + wd + we);
}

// 5-tap Gaussian filter along the (font-column) horizontal line.
vec3 Horz5(vec2 c, float off) {
  vec3 a = Fetch(c, vec2(-2.0, off));
  vec3 b = Fetch(c, vec2(-1.0, off));
  vec3 d = Fetch(c, vec2(0.0, off));
  vec3 e = Fetch(c, vec2(1.0, off));
  vec3 f = Fetch(c, vec2(2.0, off));
  float dst = Dist(c).x;
  float wa = Gaus(dst - 2.0, HARDPIX);
  float wb = Gaus(dst - 1.0, HARDPIX);
  float wd = Gaus(dst + 0.0, HARDPIX);
  float we = Gaus(dst + 1.0, HARDPIX);
  float wf = Gaus(dst + 2.0, HARDPIX);
  return (a * wa + b * wb + d * wd + e * we + f * wf)
       / (wa + wb + wd + we + wf);
}

// Perceptual luminance (sqrt-shaped, matches RVM's colML) of a reconstructed
// row, used to drive the luminance-variable scanline.
float Luma(vec3 c) {
  return sqrt(clamp(max(max(c.r, c.g), c.b), 0.0, 1.0));
}

// Mode 0: luminance-variable scanline weight. A cosine window whose width grows
// with luminance (bright lines fatten -> phosphor bloom). `dist` is the signed
// vertical distance to the line center in font rows. The DARK (lum=0) and BRIGHT
// (lum=1) slopes set how fast the cosine falls off: larger slope = thinner band.
float RvmScan(float dist, float lum) {
  float slope = mix(RVM_SCAN_DARK, RVM_SCAN_BRIGHT, lum);
  float t = min(0.5, abs(dist) * slope);
  return 0.5 + 0.5 * cos(t * RVM_2PI);
}

// Mode 0: exposure normalization. Thin (dark) lines pass less energy, so boost
// them back toward the fat-line peak; bright lines (already fat) keep gain 1.
float RvmNorm(float lum) {
  return mix(RVM_SCAN_DARK / RVM_SCAN_BRIGHT, 1.0, lum);
}

// Modes 1/2 reconstruction with the scanline modulation normalized away (soft)
// or kept (hard), selectable by the Gaussian hardness.
vec3 Recon(vec2 c, float hard, bool normalize) {
  vec3 a = Horz3(c, -1.0);
  vec3 b = Horz5(c, 0.0);
  vec3 d = Horz3(c, 1.0);
  float wa = Gaus(Dist(c).y - 1.0, hard);
  float wb = Gaus(Dist(c).y + 0.0, hard);
  float wd = Gaus(Dist(c).y + 1.0, hard);
  vec3 col = a * wa + b * wb + d * wd;
  return normalize ? col / (wa + wb + wd) : col;
}

// Exposure-preserving mask split (RVM modes 1/2). Returns the lit-subpixel
// color in `col` and the darkened off-subpixel color in `colD`, both scaled so
// the masked average preserves the input brightness.
void RvmExpose(inout vec3 col, out vec3 colD) {
  float lim = 1.0 / ((1.0 / 3.0) + (2.0 / 3.0) * RVM_DARK);
  colD = col * col * RVM_DARK;
  vec3 amp = vec3(1.0) / (vec3(lim * (1.0 / 3.0)) + vec3(lim * (2.0 / 3.0)) * col);
  col *= amp;
  colD *= amp;
}

// Mode 1: aperture grille -- vertical RGB stripes, MASKSIZE px per triad.
vec3 RvmGrille(vec3 col, vec2 fc) {
  vec3 colD;
  RvmExpose(col, colD);
  float x = fract(fc.x / MASKSIZE);
  vec3 o = colD;
  if (x < 1.0 / 3.0) {
    o.r = col.r;
  } else if (x < 2.0 / 3.0) {
    o.g = col.g;
  } else {
    o.b = col.b;
  }
  return o;
}

// Mode 2: slot mask -- aperture grille with every other triad column shifted a
// half-slot vertically and gated into vertical slots, giving the arcade look.
vec3 RvmSlot(vec3 col, vec2 fc) {
  vec3 colD;
  RvmExpose(col, colD);
  float slotV = MASKSIZE * (4.0 / 3.0); // slot height ~ source 4 px at triad 3
  if (fract(fc.x / (2.0 * MASKSIZE)) > 0.5) {
    fc.y += slotV * 0.5;
  }
  float ylit = fract(fc.y / slotV);
  float x = fract(fc.x / MASKSIZE);
  vec3 o = colD;
  if (ylit < 0.5) {
    if (x < 1.0 / 3.0) {
      o.r = col.r;
    } else if (x < 2.0 / 3.0) {
      o.g = col.g;
    } else {
      o.b = col.b;
    }
  }
  return o;
}

// Barrel distortion of the (normalized) source coordinate.
vec2 Warp(vec2 pos) {
  pos = pos * 2.0 - 1.0;
  pos *= vec2(1.0 + (pos.y * pos.y) * WARPX, 1.0 + (pos.x * pos.x) * WARPY);
  return pos * 0.5 + 0.5;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  gOutput = iResolution.xy;

  vec2 cell = iCellSize.xy;
  float emHeight = iCellSize.w;
  bool haveCell = cell.x > 0.5 && cell.y > 0.5 && emHeight > 0.5;
  gPixX = haveCell ? cell.x / FONT_NATIVE_COLS : 6.0;
  gOriginX = max(iGridPadding.w, 0.0);
  gPixY = haveCell ? emHeight / FONT_NATIVE_ROWS : 6.0;
  gPhaseTop = max(iGridPadding.x, 0.0) + (haveCell ? iCellSize.z : 0.0);

  vec2 pos = Warp(fragCoord / gOutput);

  // Off the curved screen -> black border.
  if (max(abs(pos.x - 0.5), abs(pos.y - 0.5)) > 0.5) {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }

  // Font-pixel coordinate: column in x, row from the top in y.
  vec2 coord = vec2(
    (pos.x * gOutput.x - gOriginX) / gPixX,
    ((gOutput.y - pos.y * gOutput.y) - gPhaseTop) / gPixY);

  vec3 color;

#if RVM_MODE == 0
  // PVM/BVM 240p: luminance-variable scanlines, exposure normalized, no mask.
  vec3 rU = Horz3(coord, -1.0);
  vec3 rM = Horz5(coord, 0.0);
  vec3 rD = Horz3(coord, 1.0);
  float lU = Luma(rU);
  float lM = Luma(rM);
  float lD = Luma(rD);
  float dy = Dist(coord).y;
  color = rU * (RvmScan(dy - 1.0, lU) * RvmNorm(lU))
        + rM * (RvmScan(dy + 0.0, lM) * RvmNorm(lM))
        + rD * (RvmScan(dy + 1.0, lD) * RvmNorm(lD));
#elif RVM_MODE == 1
  // Wega 480p: aperture grille, scanlines suppressed. MASKSIZE 0 = grille off.
  vec3 rec = Recon(coord, RVM_RECON_SOFT, true);
  color = (MASKSIZE > 0.5) ? RvmGrille(rec, fragCoord) : rec;
#else
  // Arcade: slot mask with scanlines. MASKSIZE 0 = mask off.
  vec3 rec = Recon(coord, RVM_SCAN_HARD, false);
  color = (MASKSIZE > 0.5) ? RvmSlot(rec, fragCoord) : rec;
#endif

  color *= BRIGHTBOOST;
  fragColor = vec4(ToSrgb(color), 1.0);
}
