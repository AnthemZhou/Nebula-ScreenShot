// SPDX-License-Identifier: GPL-3.0-only
// Optical functions below are adapted under MIT from Liquid Glass Engineering
// (Rokas Rudzianskas) and Glass HQ. See THIRD_PARTY_NOTICES.md.
enum GlassShader {
    static let source = #"""
// Liquid Glass Engineering: the optical model in Metal Shading Language.
//
// A line-by-line translation of spec/shaders/liquid-glass.glsl (itself a port
// of spec/reference.mjs). Keep the three in sync; the unit tests evaluate these
// functions on the GPU against spec/vectors.json.
//
// Units: points. `pixel` is one device pixel in points (1 / scale).
// Colors: sRGB gamma-encoded. "premul" means premultiplied alpha.

#ifndef LIQUID_GLASS_CORE_H
#define LIQUID_GLASS_CORE_H

#include <metal_stdlib>
using namespace metal;

constant float LG_BEVEL = 20.0;
constant float LG_CONTINUOUS_EXTENT = 1.528;
constant float LG_CONTINUOUS_EXPONENT = 3.26;
constant float3 LG_LUMA = float3(0.213, 0.715, 0.072);

inline float lgSat(float x) { return clamp(x, 0.0, 1.0); }

// ---------------------------------------------------------------------------
// Shape

// Corner extent and superellipse exponent. A negative radius means capsule.
inline float2 lgShapeParams(float2 size, float radius) {
    float halfMin = max(0.0, min(size.x, size.y) * 0.5);
    if (radius < 0.0) return float2(halfMin, 2.0);
    float raw = LG_CONTINUOUS_EXTENT * radius;
    float extent = min(raw, halfMin);
    float t = halfMin > 0.0 ? smoothstep(0.75, 1.0, raw / halfMin) : 1.0;
    return float2(extent, mix(LG_CONTINUOUS_EXPONENT, 2.0, t));
}

// Signed distance (negative inside) and outward normal at p, measured from
// the shape center with y down. Returns float3(distance, normal.x, normal.y).
inline float3 lgShapeField(float2 p, float2 size, float2 shape) {
    float e = shape.x;
    float n = shape.y;
    float2 s = float2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
    float2 q = abs(p) - (size * 0.5 - e);
    if (q.x > 0.0 && q.y > 0.0) {
        // Normalize by the larger component so pow() never overflows.
        float k = max(q.x, q.y);
        float2 u = q / k;
        float m = k * pow(pow(u.x, n) + pow(u.y, n), 1.0 / n);
        if (m < 1e-6) return float3(-e, s * 0.70710678);
        float2 g = pow(q / m, float2(n - 1.0));
        float gl = length(g);
        return float3((m - e) / gl, s * g / gl);
    }
    if (q.x > q.y) return float3(q.x - e, s.x, 0.0);
    return float3(q.y - e, 0.0, s.y);
}

// ---------------------------------------------------------------------------
// Refraction

inline float lgEdgeProfile(float distance) {
    float depth = lgSat(-distance / LG_BEVEL);
    return 1.0 - lgSat(sqrt((2.0 - depth) * depth));
}

// Offset from the pixel to the backdrop point it shows.
inline float2 lgRefractionOffset(float3 field, float refraction) {
    return -field.yz * lgEdgeProfile(field.x) * refraction;
}

inline float lgCoverage(float distance, float pixel) {
    return lgSat(0.5 - distance / pixel);
}

// ---------------------------------------------------------------------------
// Color

inline float3 lgSaturate(float3 c, float s) {
    return clamp(float3(
        (0.213 + 0.787 * s) * c.r + (0.715 - 0.715 * s) * c.g + (0.072 - 0.072 * s) * c.b,
        (0.213 - 0.213 * s) * c.r + (0.715 + 0.285 * s) * c.g + (0.072 - 0.072 * s) * c.b,
        (0.213 - 0.213 * s) * c.r + (0.715 - 0.715 * s) * c.g + (0.072 + 0.928 * s) * c.b), 0.0, 1.0);
}

inline float3 lgClearTone(float3 v, float dark, float nested) {
    float lift = mix(0.18, 0.15, dark);
    float rolloff = mix(0.0, 0.2, dark);
    float3 inv = 1.0 - v;
    float3 tone = v + lift * inv * inv * inv - rolloff * v * v * v;
    float3 veil = mix(0.78 * v + 0.26, 0.38 * v + 0.2, dark);
    float weight = mix(0.06, 0.14, dark);
    float3 layerLight = dark * nested * 0.08 * inv;
    return clamp((1.0 - weight) * tone + weight * veil + layerLight, 0.0, 1.0);
}

inline float3 lgRegularTone(float3 v, float dark) {
    float3 abq = mix(float3(0.36, 0.67, -0.1113), float3(0.105, 0.83, -0.2091), dark);
    float weight = mix(0.8, 0.9, dark);
    float3 toned = clamp(weight * (abq.x + abq.y * v + abq.z * v * v) + (1.0 - weight) * v, 0.0, 1.0);
    return lgSaturate(toned, mix(1.1031, 1.0648, dark));
}

// material: 0 = clear, 1 = regular.
inline float3 lgMaterialColor(float3 c, float material, float dark, float nested) {
    return material > 0.5 ? lgRegularTone(c, dark) : lgClearTone(c, dark, nested);
}

inline float3 lgTintColor(float3 c, float3 tint, float material) {
    float body = material > 0.5 ? 0.78 : 0.68;
    return clamp(tint * (body + (1.0 - body) * dot(c, LG_LUMA)), 0.0, 1.0);
}

// Regular glass: `frost` is the backdrop blurred with sigma 7.33, `fill` with
// sigma 23 (light) or 21.8 (dark).
inline float3 lgFrostColor(float3 frost, float3 fill, float dark) {
    float3 blended = dark > 0.5 ? min(frost, fill) : max(frost, fill);
    float opacity = mix(0.34, 0.65, dark);
    return opacity * blended + (1.0 - opacity) * frost;
}

// Menu panels mix their glass toward a solid backing so text always reads:
// #F5F5F7 light, #1C1C1E dark. amount is 0.6 on menu panels (times the open
// progress of the menu), 0 elsewhere.
inline float3 lgLegibility(float3 c, float dark, float amount) {
    float3 backing = mix(float3(0.960784, 0.960784, 0.968627), float3(0.109804, 0.109804, 0.117647), dark);
    return mix(c, backing, amount);
}

// ---------------------------------------------------------------------------
// Rim light (premul). tintOn: 0 or 1.

inline float4 lgRimOverlay(float3 field, float dark, float pixel, float3 tint, float tintOn) {
    float d = field.x;
    float2 n = field.yz;
    float aa = max(pixel, 1e-6);
    float cover = lgSat(0.5 - d / aa);
    const float spread = 1.08;
    float directional = pow(lgSat((abs(n.y) - cos(spread)) / (1.0 - cos(spread))), 1.25);
    float diffuseDir = pow(lgSat((abs(n.y) - cos(spread * 0.65)) / (1.0 - cos(spread * 0.65))), 1.25);
    float stroke = lgSat((d + 0.9) / aa + 0.5) * lgSat(0.5 - d / aa);
    float specular = directional * stroke;
    specular = specular / (1.0 + 0.5 * (1.0 - specular));
    float inner = 1.0 - lgSat(-d / 4.5);
    float diffuse = diffuseDir * 0.18 * inner * inner * cover;
    float highlight = lgSat(specular * mix(1.0, 0.82, dark) + diffuse * mix(1.0, 0.4, dark));
    float adjusted = d - 0.5;
    float falloff = 1.0 - lgSat(-adjusted / 0.5);
    float ramp = mix(falloff > 0.0 ? 1.0 : 0.0, falloff, 0.75);
    float outline = ramp * lgSat((adjusted + 0.5) / aa + 0.5) * lgSat(-adjusted / aa + 0.5);
    const float sideSpread = 0.98;
    float2 w = clamp((float2(n.x, -n.x) - cos(sideSpread)) / (1.0 - cos(sideSpread)), 0.0, 1.0) * outline;
    float2 shaded = w / (1.0 + 0.4 * (1.0 - w));
    float shade = (shaded.x + shaded.y) * mix(0.48, 0.6, dark);
    float alpha = highlight + shade * (1.0 - highlight);
    float3 light = tintOn > 0.5 ? highlight * (0.45 + 0.55 * tint) : float3(mix(1.0, 0.82, dark) * highlight);
    return float4(light, alpha);
}

// ---------------------------------------------------------------------------
// Composite

// src: refracted backdrop at p + lgRefractionOffset (unpremul; regular glass
// passes lgFrostColor). base: unrefracted backdrop at p (premul).
inline float4 lgCompose(float4 src, float4 base, float3 field, float material, float dark, float nested,
                        float3 tint, float tintOn, float pixel, float legibility) {
    float3 rgb = lgMaterialColor(src.rgb, material, dark, nested);
    float a = src.a;
    if (tintOn > 0.5) {
        float body = material > 0.5 ? 0.78 : 0.68;
        rgb = lgTintColor(rgb, tint, material);
        a = body + (1.0 - body) * a;
    }
    rgb = lgLegibility(rgb, dark, legibility);
    float ga = a * lgCoverage(field.x, pixel);
    float4 result = float4(rgb * ga, ga) + base * (1.0 - ga);
    float4 rim = lgRimOverlay(field, dark, pixel, tint, tintOn);
    return rim + result * (1.0 - rim.a);
}

// Pointer glow for interactive glass, premul white. Paint after lgCompose,
// clipped to coverage. glowAmount is the glow spring value (0..1).
inline float4 lgGlow(float2 p, float2 center, float radius, float dark, float glowAmount, float cover) {
    float alpha = mix(0.3, 0.16, dark) * glowAmount * (1.0 - lgSat(length(p - center) / radius)) * cover;
    return float4(float3(alpha), alpha);
}

#endif


struct NebulaGlassUniforms {
    float4 viewport; // size in points, backing scale, shade opacity
    float4 canvas;   // toolbar origin in canvas, canvas size
    float4 crop;
    float4 row;
    float4 hint;
    float4 radii;    // row, hint, crop, refraction multiplier
};
struct NebulaGlassVertex { float4 position [[position]]; float2 uv; };

vertex NebulaGlassVertex nebulaGlassVertex(uint id [[vertex_id]]) {
    const float2 vertices[6] = {float2(-1, 1), float2(-1, -1), float2(1, 1),
                               float2(1, 1), float2(-1, -1), float2(1, -1)};
    float2 p = vertices[id];
    return {float4(p, 0, 1), float2((p.x + 1) * 0.5, (1 - p.y) * 0.5)};
}

// Match the frozen canvas shade, including when a short screen places the
// toolbar over the crop. Sampling is from the existing capture, never the screen.
inline float3 nebulaBackdrop(texture2d<float> image, float2 p,
                             constant NebulaGlassUniforms &u) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 rgb = image.sample(linearSampler, p / u.canvas.zw).rgb;
    float2 q = abs(p - u.crop.xy - u.crop.zw * 0.5) - (u.crop.zw * 0.5 - u.radii.z);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u.radii.z;
    float outside = smoothstep(-0.5 / u.viewport.z, 0.5 / u.viewport.z, d);
    return rgb * (1.0 - u.viewport.w * outside);
}

fragment float4 nebulaGlassFragment(NebulaGlassVertex v [[stage_in]],
                                    texture2d<float> image [[texture(0)]],
                                    constant NebulaGlassUniforms &u [[buffer(0)]]) {
    float2 p = v.uv * u.viewport.xy;
    bool inRow = p.y <= u.row.y + u.row.w + 1.0;
    float4 rect = inRow ? u.row : u.hint;
    float radius = inRow ? u.radii.x : u.radii.y;
    float2 size = rect.zw;
    // Keep Nebula's existing circular corner silhouette, including its CPU
    // fallback; material readiness must not resize the visible controls.
    float3 field = lgShapeField(p - rect.xy - size * 0.5, size,
                               float2(min(radius, min(size.x, size.y) * 0.5), 2.0));
    float pixel = 1.0 / u.viewport.z;
    float cover = lgCoverage(field.x, pixel);
    if (cover <= 0.0) return float4(0);

    // Scale the upstream convex bevel to these compact 40/24 pt controls.
    // Keep the refraction localized, without a time-varying wobble.
    float bevel = min(12.0, min(size.x, size.y) * 0.32);
    float depth = lgSat(-field.x / bevel);
    float edge = 1.0 - sqrt((2.0 - depth) * depth);
    float strength = min(18.0, min(size.x, size.y) * 0.45) * u.radii.w;
    float2 q = u.canvas.xy + p - field.yz * edge * strength;

    // Small fixed kernel keeps background detail soft without a full-screen
    // Gaussian pass. Text and icons are drawn separately above the glass.
    const float blur = 1.35;
    float3 src = nebulaBackdrop(image, q, u) * 0.20;
    src += (nebulaBackdrop(image, q + float2(blur, 0), u)
          + nebulaBackdrop(image, q - float2(blur, 0), u)
          + nebulaBackdrop(image, q + float2(0, blur), u)
          + nebulaBackdrop(image, q - float2(0, blur), u)) * 0.12;
    src += (nebulaBackdrop(image, q + float2(blur, blur), u)
          + nebulaBackdrop(image, q + float2(-blur, blur), u)
          + nebulaBackdrop(image, q + float2(blur, -blur), u)
          + nebulaBackdrop(image, q - float2(blur, blur), u)) * 0.08;

    float3 rgb = lgClearTone(src, 1.0, 0.0);
    // Stable charcoal backing, with more transmission at the optical edge.
    rgb = mix(rgb, float3(0.055, 0.058, 0.065), mix(0.58, 0.38, edge));
    float4 result = float4(rgb * cover, cover);
    float4 rim = lgRimOverlay(field, 1.0, pixel, float3(1), 0.0);
    // Keep the contour inside the surface: do not create an outer white stroke.
    rim *= cover;
    return rim + result * (1.0 - rim.a);
}
"""#
}
