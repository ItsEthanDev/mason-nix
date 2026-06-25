/*
    CRT-interlaced (Shadertoy / Ghostty)

    Copyright (C) 2010-2012 cgwg, Themaister and DOLLS

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the Free
    Software Foundation; either version 2 of the License, or (at your option)
    any later version.

    (cgwg gave their consent to have the original version of this shader
    distributed under the GPL in this message:

        http://board.byuu.org/viewtopic.php?p=26075#p26075

        "Feel free to distribute my shaders under the GPL. After all, the
        barrel distortion code was taken from the Curvature shader, which is
        under the GPL."
    )

    Shadertoy usage:
      - Upload any image to iChannel0 (nearest/pixel filtering recommended).
      - iChannelResolution[0] should match the source image size.
*/

// --- tweakable parameters (RetroArch #pragma defaults) ---
#define CRTgamma 2.4
#define INV 0.0
#define monitorgamma 2.2
#define d 1.6
#define CURVATURE 1.0
#define R 2.0
#define cornersize 0.03
#define cornersmooth 1000.0
#define x_tilt 0.0
#define y_tilt 0.0
#define overscan_x 100.0
#define overscan_y 100.0
#define DOTMASK 0.3
#define SHARPER 1.0
#define scanline_weight 0.3
#define lum 0.0
// Interlacing is meaningless for a progressive font-pixel grid; keep it off so
// scanlines don't flicker frame-to-frame.
#define interlace_detect 0.0
#define SATURATION 1.0

// Native pixel size of the source bitmap font (Free CG98: 8x16 PC-98 glyphs).
// Used to derive a virtual source resolution so scanlines/dot-mask track the
// font pixel size (and therefore ctrl +/- resizing) instead of screen pixels.
#define FONT_NATIVE_PIXELS vec2(8.0, 16.0)

#define LINEAR_PROCESSING
#define OVERSAMPLE

#define FIX(c) max(abs(c), 1e-5)
#define PI 3.141592653589

#ifdef LINEAR_PROCESSING
#define TEX2D(c) pow(texture(iChannel0, (c)), vec4(CRTgamma))
#else
#define TEX2D(c) texture(iChannel0, (c))
#endif

#define pwr vec3(1.0 / ((-0.7 * (1.0 - scanline_weight) + 1.0) * (-0.5 * DOTMASK + 1.0) - 1.25))

struct CrtGeomCtx {
  vec2 one;
  float mod_factor;
  vec2 ilfac;
  vec2 aspect;
  vec3 stretch;
  vec2 sinangle;
  vec2 cosangle;
  vec2 gridOrigin;
  vec2 inputSize;
  vec2 textureSize;
  // Per-cell font-pixel geometry for vertical scanline alignment.
  float pix;     // vertical font-pixel size in screen px (== em_height / 16)
  float cellH;   // cell height in screen px
  float padTop;  // grid top padding in screen px
  float emTop;   // px from cell top to the top of the rasterized 16-row em block
};

float intersect(vec2 xy, vec2 sinangle, vec2 cosangle) {
  float A = dot(xy, xy) + d * d;
  float B = 2.0 * (R * (dot(xy, sinangle) - d * cosangle.x * cosangle.y) - d * d);
  float C = d * d + 2.0 * R * d * cosangle.x * cosangle.y;
  return (-B - sqrt(B * B - 4.0 * A * C)) / (2.0 * A);
}

vec2 bkwtrans(vec2 xy, vec2 sinangle, vec2 cosangle) {
  float c = intersect(xy, sinangle, cosangle);
  vec2 point = vec2(c) * xy;
  point -= vec2(-R) * sinangle;
  point /= vec2(R);
  vec2 tang = sinangle / cosangle;
  vec2 poc = point / cosangle;
  float A = dot(tang, tang) + 1.0;
  float B = -2.0 * dot(poc, tang);
  float C = dot(poc, poc) - 1.0;
  float a = (-B + sqrt(B * B - 4.0 * A * C)) / (2.0 * A);
  vec2 uv = (point - a * sinangle) / cosangle;
  float r = FIX(R * acos(a));
  return uv * r / sin(r / R);
}

vec2 fwtrans(vec2 uv, vec2 sinangle, vec2 cosangle) {
  float r = FIX(sqrt(dot(uv, uv)));
  uv *= sin(r / R) / r;
  float x = 1.0 - cos(r / R);
  float D = d / R + x * cosangle.x * cosangle.y + dot(uv, sinangle);
  return d * (uv * cosangle - x * sinangle) / D;
}

vec3 maxscale(vec2 sinangle, vec2 cosangle, vec2 aspect) {
  vec2 c = bkwtrans(-R * sinangle / (1.0 + R / d * cosangle.x * cosangle.y), sinangle, cosangle);
  vec2 a = vec2(0.5, 0.5) * aspect;
  vec2 lo = vec2(fwtrans(vec2(-a.x, c.y), sinangle, cosangle).x, fwtrans(vec2(c.x, -a.y), sinangle, cosangle).y) / aspect;
  vec2 hi = vec2(fwtrans(vec2(+a.x, c.y), sinangle, cosangle).x, fwtrans(vec2(c.x, +a.y), sinangle, cosangle).y) / aspect;
  return vec3((hi + lo) * aspect * 0.5, max(hi.x - lo.x, hi.y - lo.y));
}

CrtGeomCtx crtGeomInit(vec2 texCoord, vec2 inputSize, vec2 textureSize, vec2 outputSize, vec2 gridOrigin) {
  CrtGeomCtx ctx;
  ctx.inputSize = inputSize;
  ctx.textureSize = textureSize;
  ctx.gridOrigin = gridOrigin;
  ctx.aspect = vec2(1.0, 0.75);
  ctx.sinangle = sin(vec2(x_tilt, y_tilt)) + vec2(0.001);
  ctx.cosangle = cos(vec2(x_tilt, y_tilt)) + vec2(0.001);
  ctx.stretch = maxscale(ctx.sinangle, ctx.cosangle, ctx.aspect);
  // One beam per font-pixel row: the source grid is already progressive, so the
  // RetroArch line-doubling heuristic (which keys off raw source height) must
  // not engage here.
  ctx.ilfac = vec2(1.0, 1.0);
  vec2 sharpTextureSize = vec2(SHARPER * textureSize.x, textureSize.y);
  ctx.one = ctx.ilfac / sharpTextureSize;
  ctx.mod_factor = texCoord.x * textureSize.x * outputSize.x / inputSize.x;
  return ctx;
}

vec2 transform(vec2 coord, CrtGeomCtx ctx) {
  coord *= ctx.textureSize / ctx.inputSize;
  coord = (coord - vec2(0.5)) * ctx.aspect * ctx.stretch.z + ctx.stretch.xy;
  return (bkwtrans(coord, ctx.sinangle, ctx.cosangle) / vec2(overscan_x / 100.0, overscan_y / 100.0) / ctx.aspect + vec2(0.5)) * ctx.inputSize / ctx.textureSize;
}

float corner(vec2 coord, CrtGeomCtx ctx) {
  coord *= ctx.textureSize / ctx.inputSize;
  coord = (coord - vec2(0.5)) * vec2(overscan_x / 100.0, overscan_y / 100.0) + vec2(0.5);
  coord = min(coord, vec2(1.0) - coord) * ctx.aspect;
  vec2 cdist = vec2(cornersize);
  coord = (cdist - min(coord, cdist));
  float dist = sqrt(dot(coord, coord));
  return clamp((cdist.x - dist) * cornersmooth, 0.0, 1.0) * 1.0001;
}

vec4 scanlineWeights(float distance, vec4 color) {
  vec4 wid = 2.0 + 2.0 * pow(color, vec4(4.0));
  vec4 weights = vec4(distance / scanline_weight);
  return (lum + 1.4) * exp(-pow(weights * inversesqrt(0.5 * wid), wid)) / (0.6 + 0.2 * wid);
}

vec3 saturation(vec3 textureColor) {
  float luma = length(textureColor) * 0.5775;
  vec3 luminanceWeighting = vec3(0.3, 0.6, 0.1);
  if (luma < 0.5) {
    luminanceWeighting.rgb = (luminanceWeighting.rgb * luminanceWeighting.rgb) + (luminanceWeighting.rgb * luminanceWeighting.rgb);
  }
  float luminance = dot(textureColor, luminanceWeighting);
  vec3 greyScaleColor = vec3(luminance);
  return mix(greyScaleColor, textureColor, SATURATION);
}

vec3 inv_gamma(vec3 col, vec3 power) {
  vec3 cir = col - 1.0;
  cir *= cir;
  col = mix(sqrt(col), sqrt(1.0 - cir), power);
  return col;
}

vec3 crtGeomSample(vec2 texCoord, CrtGeomCtx ctx, vec2 outputSize, int frameCount) {
  vec2 xy = (CURVATURE > 0.5) ? transform(texCoord * 1.0001, ctx) : texCoord * 1.0001;

  float cval = corner(xy, ctx);

  vec2 sourceScale = ctx.textureSize / outputSize;

  // Horizontal: font-pixel columns tile the cell exactly (advance == 8 px, no
  // gap), so a single global grid aligned to the left padding lands on every
  // cell. This is the original crt-geom mapping, restricted to X.
  float ratioX = (xy.x * outputSize.x - ctx.gridOrigin.x) * sourceScale.x - 0.5;

  // Vertical: the 16 font rows have pitch ctx.pix and sit at the rasterizer's
  // exact em-box placement (ctx.emTop from the cell top). The scanline phase must
  // reset per cell -- the cell can be a touch taller than the em box, so a single
  // global grid would drift. Work in screen px from the top to match the grid
  // padding, then map back into the bottom-origin sample coordinate.
  float yTop = outputSize.y - xy.y * outputSize.y;
  float row = floor((yTop - ctx.padTop) / ctx.cellH);
  float emTopTop = ctx.padTop + row * ctx.cellH + ctx.emTop;
  float emBotBot = outputSize.y - (emTopTop + FONT_NATIVE_PIXELS.y * ctx.pix);
  float ratioY = (xy.y * outputSize.y - emBotBot) / ctx.pix - 0.5;

#ifdef OVERSAMPLE
  float filter_ = ctx.inputSize.y / outputSize.y;
#endif
  vec2 uv_ratio = fract(vec2(ratioX, ratioY));

  // Snap to the center of the current scanline / column.
  float sampleX = ((floor(ratioX) + 0.5) / sourceScale.x + ctx.gridOrigin.x) / outputSize.x;
  float sampleY = (emBotBot + (floor(ratioY) + 0.5) * ctx.pix) / outputSize.y;
  xy = vec2(sampleX, sampleY);

  vec4 coeffs = PI * vec4(1.0 + uv_ratio.x, uv_ratio.x, 1.0 - uv_ratio.x, 2.0 - uv_ratio.x);
  coeffs = FIX(coeffs);
  coeffs = 2.0 * sin(coeffs) * sin(coeffs / 2.0) / (coeffs * coeffs);
  coeffs /= dot(coeffs, vec4(1.0));

  vec4 col = clamp(mat4(
    TEX2D(xy + vec2(-ctx.one.x, 0.0)),
    TEX2D(xy),
    TEX2D(xy + vec2(ctx.one.x, 0.0)),
    TEX2D(xy + vec2(2.0 * ctx.one.x, 0.0))) * coeffs,
    0.0, 1.0);
  vec4 col2 = clamp(mat4(
    TEX2D(xy + vec2(-ctx.one.x, ctx.one.y)),
    TEX2D(xy + vec2(0.0, ctx.one.y)),
    TEX2D(xy + ctx.one),
    TEX2D(xy + vec2(2.0 * ctx.one.x, ctx.one.y))) * coeffs,
    0.0, 1.0);

#ifndef LINEAR_PROCESSING
  col = pow(col, vec4(CRTgamma));
  col2 = pow(col2, vec4(CRTgamma));
#endif

  vec4 weights = scanlineWeights(uv_ratio.y, col);
  vec4 weights2 = scanlineWeights(1.0 - uv_ratio.y, col2);
#ifdef OVERSAMPLE
  uv_ratio.y = uv_ratio.y + 1.0 / 3.0 * filter_;
  weights = (weights + scanlineWeights(uv_ratio.y, col)) / 3.0;
  weights2 = (weights2 + scanlineWeights(abs(1.0 - uv_ratio.y), col2)) / 3.0;
  uv_ratio.y = uv_ratio.y - 2.0 / 3.0 * filter_;
  weights = weights + scanlineWeights(abs(uv_ratio.y), col) / 3.0;
  weights2 = weights2 + scanlineWeights(abs(1.0 - uv_ratio.y), col2) / 3.0;
#endif

  vec3 mul_res = (col * weights + col2 * weights2).rgb * vec3(cval);

  vec3 dotMaskWeights = mix(
    vec3(1.0, 1.0 - DOTMASK, 1.0),
    vec3(1.0 - DOTMASK, 1.0, 1.0 - DOTMASK),
    floor(mod(ctx.mod_factor, 2.0)));

  mul_res *= dotMaskWeights;

  if (INV == 1.0) {
    mul_res = inv_gamma(mul_res, pwr);
  } else {
    mul_res = pow(mul_res, vec3(1.0 / monitorgamma));
  }

  return saturation(mul_res);
}

// Font pixels per screen pixel, used to build the virtual source resolution.
// Horizontally we use cell.width / 8 (a monospace cell has no horizontal gap, so
// that is the exact column pitch). Vertically we use the rasterizer-reported em
// height / 16 (iCellSize.w), which is the exact row pitch of the on-screen font
// pixels -- this avoids the line-gap stretch and the rounding mismatch that come
// from naively dividing the full cell height by 16.
vec2 ghosttyPixelScale() {
  vec2 cell = iCellSize.xy;
  float emHeight = iCellSize.w;
  if (cell.x <= 0.0 || emHeight <= 0.0) {
    return vec2(1.0);
  }
  return vec2(FONT_NATIVE_PIXELS.x / cell.x, FONT_NATIVE_PIXELS.y / emHeight);
}

// iGridPadding is {top, right, bottom, left}; fragCoord uses a bottom-left
// origin, so the font grid starts at {left, bottom} for scanline phase.
vec2 ghosttyGridOrigin() {
  vec4 padding = max(iGridPadding, vec4(0.0));
  return vec2(padding.w, padding.z);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 outputSize = iResolution.xy;

  // Virtual source resolution measured in font pixels. crt-geom places one
  // scanline (and snaps sampling) per source texel, so tying the source grid to
  // the font cell makes scanlines, beam width and the Lanczos sharpening all
  // scale 1:1 with the on-screen font pixels, even while resizing.
  vec2 sourceSize = max(outputSize * ghosttyPixelScale(), vec2(1.0));

  vec2 texCoord = fragCoord / outputSize;

  CrtGeomCtx ctx = crtGeomInit(texCoord, sourceSize, sourceSize, outputSize, ghosttyGridOrigin());

  // Per-cell vertical geometry, taken from the exact rasterized em box that the
  // cell-size patch measures (iCellSize.z = em top from cell top, .w = em height
  // in screen px). The scanline grid then sits precisely where Ghostty placed
  // the font pixels, so the top/bottom margins match the rendered glyphs instead
  // of a mathematically-centered approximation.
  vec2 cell = iCellSize.xy;
  float emHeight = iCellSize.w;
  bool haveCell = cell.x > 0.5 && cell.y > 0.5 && emHeight > 0.5;
  ctx.pix = haveCell ? emHeight / FONT_NATIVE_PIXELS.y : 1.0;
  ctx.cellH = haveCell ? cell.y : FONT_NATIVE_PIXELS.y;
  ctx.padTop = max(iGridPadding.x, 0.0);
  ctx.emTop = haveCell ? iCellSize.z : 0.0;

  fragColor = vec4(crtGeomSample(texCoord, ctx, outputSize, int(iFrame)), 1.0);
}
