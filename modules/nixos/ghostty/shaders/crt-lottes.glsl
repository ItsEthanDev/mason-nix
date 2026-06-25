/*
    CRT-Lottes (Shadertoy XsjSzR / Ghostty)

    PUBLIC DOMAIN CRT STYLED SCAN-LINE SHADER
      by Timothy Lottes  --  https://www.shadertoy.com/view/XsjSzR
    "More along the style of a really good CGA arcade monitor with RGB inputs."

    Ghostty port. The Gaussian pixel/scanline reconstruction is locked to the
    rasterized font-pixel grid on BOTH axes (so the image and its scanlines line
    up with crt-geom and track ctrl +/- zoom):

      * HORIZONTAL: emulated columns = the 8 font-pixel columns of a cell
        (pitch cell.x/8, phased to the left grid padding).
      * VERTICAL: emulated rows / scanlines = the 16 font-pixel rows of the em
        (pitch em_height/16, phased to the rasterized em box via iCellSize.z/.w),
        i.e. one scanline per font-pixel row.

    Everything that is NOT the sampling grid -- the shadow mask, the warp, gamma
    -- mirrors the source shader (screen-space, font-independent) with the
    original constants exposed as #define sliders.
*/

// --- tweakable parameters (source defaults) ---
// Hardness of scanline. -8 soft, -16 medium.
#define HARDSCAN -8.0
// Hardness of pixels within a scanline. -2 soft, -4 hard.
#define HARDPIX -3.0
// Display warp (0 = none, 1/8 = extreme). Source: vec2(1/32, 1/24).
#define WARPX 0.03125
#define WARPY 0.04167
// Shadow mask darkness/brightness and RGB-triad width in *screen px*.
#define MASKDARK 0.5
#define MASKLIGHT 1.5
#define MASKSIZE 6.0
// Mask style (Timothy Lottes' four variants):
//   0 = aperture-grille        (vertical RGB stripes)
//   1 = compressed TV          (RGB stripes + 2px dot darkening, staggered)
//   2 = stretched VGA          (diagonal aperture grille -- the previous default)
//   3 = VGA shadow mask        (true 2D dot mask, rows quantized to MASKSIZE/3)
#define MASKTYPE 2.0
// 0 = no mask, 1 = mask on.
#define SHADOWMASK 1.0
// Overall brightness multiply (1.0 = source, no change).
#define BRIGHTBOOST 1.0
// Input/output gamma (source hard-codes 2.4 in / ~2.2 out).
#define GAMMA_IN 2.4
#define GAMMA_OUT 2.2

// Native pixel grid of the source bitmap font (Free CG98: 8x16 PC-98 glyphs).
#define FONT_NATIVE_COLS 8.0
#define FONT_NATIVE_ROWS 16.0

// --- shared globals (set in mainImage) --------------------------------------
// Coordinate convention fed to the Lottes pipeline (integer+0.5 = a sample
// center on each axis):
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
  return (a * wa + b * wb + d * wd + e * we + f * wf) / (wa + wb + wd + we + wf);
}

// Scanline weight from the vertical (font-row) distance.
float Scan(vec2 c, float off) {
  float dst = Dist(c).y;
  return Gaus(dst + off, HARDSCAN);
}

// Allow the nearest three font rows to affect this pixel.
vec3 Tri(vec2 c) {
  vec3 a = Horz3(c, -1.0);
  vec3 b = Horz5(c, 0.0);
  vec3 d = Horz3(c, 1.0);
  float wa = Scan(c, -1.0);
  float wb = Scan(c, 0.0);
  float wd = Scan(c, 1.0);
  return a * wa + b * wb + d * wd;
}

// Barrel distortion of the (normalized) source coordinate.
vec2 Warp(vec2 pos) {
  pos = pos * 2.0 - 1.0;
  pos *= vec2(1.0 + (pos.y * pos.y) * WARPX, 1.0 + (pos.x * pos.x) * WARPY);
  return pos * 0.5 + 0.5;
}

// Split one triad-wide x position into an R/G/B multiplier.
vec3 triadRGB(float x) {
  vec3 mask = vec3(MASKDARK);
  if (x < 1.0 / 3.0) {
    mask.r = MASKLIGHT;
  } else if (x < 2.0 / 3.0) {
    mask.g = MASKLIGHT;
  } else {
    mask.b = MASKLIGHT;
  }
  return mask;
}

// All masks work in screen pixels; MASKSIZE is the RGB-triad width. The source
// hard-codes the triad at 3 px (grille/TV) or 6 px (VGA); here every secondary
// period (line darkening, diagonal slant, dot row height) is derived from
// MASKSIZE so a single slider scales the whole pattern proportionally.

// 0: aperture-grille -- pure vertical RGB stripes.
vec3 maskAperture(vec2 pos) {
  return triadRGB(fract(pos.x / MASKSIZE));
}

// 1: compressed TV -- stripes plus a 2-row dot darkening, staggered per triad.
vec3 maskTV(vec2 pos) {
  float vert = (2.0 / 3.0) * MASKSIZE; // source 2 px at triad 3
  float odd = (fract(pos.x / (2.0 * MASKSIZE)) < 0.5) ? (vert * 0.5) : 0.0;
  float line = (fract((pos.y + odd) / vert) < 0.5) ? MASKDARK : MASKLIGHT;
  return triadRGB(fract(pos.x / MASKSIZE)) * line;
}

// 2: stretched VGA -- diagonal aperture grille (half-triad slant per row).
vec3 maskStretchedVGA(vec2 pos) {
  pos.x += pos.y * (MASKSIZE * 0.5);
  return triadRGB(fract(pos.x / MASKSIZE));
}

// 3: VGA shadow mask -- rows quantized into MASKSIZE/3-tall cells, slanted half
// a triad per cell, giving a true 2D phosphor-dot grid.
vec3 maskVGA(vec2 pos) {
  float vh = MASKSIZE / 3.0; // source 2 px at triad 6
  float yCell = floor(pos.y / vh);
  float x = floor(pos.x) + yCell * (MASKSIZE * 0.5);
  return triadRGB(fract(x / MASKSIZE));
}

vec3 Mask(vec2 pos) {
  if (MASKTYPE < 0.5) {
    return maskAperture(pos);
  } else if (MASKTYPE < 1.5) {
    return maskTV(pos);
  } else if (MASKTYPE < 2.5) {
    return maskStretchedVGA(pos);
  }
  return maskVGA(pos);
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

  // Off the curved screen -> black border (matches the source's guard).
  if (max(abs(pos.x - 0.5), abs(pos.y - 0.5)) > 0.5) {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }

  // Font-pixel coordinate: column in x, row from the top in y.
  vec2 coord = vec2(
    (pos.x * gOutput.x - gOriginX) / gPixX,
    ((gOutput.y - pos.y * gOutput.y) - gPhaseTop) / gPixY);

  vec3 color = Tri(coord) * BRIGHTBOOST;
  if (SHADOWMASK > 0.5 && MASKSIZE > 0.5) {
    color *= Mask(fragCoord);
  }

  fragColor = vec4(ToSrgb(color), 1.0);
}
