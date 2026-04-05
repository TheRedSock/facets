#include "gem_trace_material.h"
#include <cmath>

using namespace godot;

namespace gem { namespace material {

// -------------------------------------------------------------------------
// Internal helpers
// -------------------------------------------------------------------------

static double apply_contrast(double value, double contrast) {
    double centered = value - 0.5;
    double scale = lerpd(0.68, 2.1, clampd(contrast, 0.0, 1.0));
    return clampd(0.5 + centered * scale, 0.0, 1.0);
}

static Color resolve_secondary_color(const VisualProps& v, Color base) {
    if (v.material_secondary_color.a > 0.001) return v.material_secondary_color;
    if (v.gradient_color.a > 0.001) return v.gradient_color;
    return base.darkened(0.18);
}

static Color resolve_tertiary_color(const VisualProps& v, Color base) {
    if (v.material_tertiary_color.a > 0.001) return v.material_tertiary_color;
    if (v.phenomenon_color.a > 0.001) return v.phenomenon_color;
    return base.lightened(0.12);
}

static Color mix_palette(Color base, Color secondary, Color tertiary,
                         double pattern_value, double accent_value, double mix_amount) {
    if (mix_amount <= 0.0001) return base;
    Color mixed = color_lerp(base, secondary, clampd(pattern_value * mix_amount, 0.0, 1.0));
    if (tertiary.a > 0.001) {
        mixed = color_lerp(mixed, tertiary, clampd(accent_value * mix_amount * 0.75, 0.0, 1.0));
    }
    return mixed;
}

struct BasisAxes { Vector3 axis, tangent, bitangent; };

static BasisAxes basis_from_axis(Vector3 a) {
    Vector3 resolved = a.normalized();
    if (resolved.length_squared() < 0.0001) resolved = Vector3(0, 1, 0);
    Vector3 tangent = resolved.cross(Vector3(0, 1, 0));
    if (tangent.length_squared() <= 0.0001) tangent = resolved.cross(Vector3(1, 0, 0));
    tangent = tangent.normalized();
    Vector3 bitangent = resolved.cross(tangent).normalized();
    return { resolved, tangent, bitangent };
}

static Vector3 project_point(Vector3 point, const BasisAxes& b) {
    return Vector3(point.dot(b.tangent), point.dot(b.bitangent), point.dot(b.axis));
}

static Vector2 surface_coord(Vector2 uv, Vector3 obj_pos, const VisualProps& v) {
    Vector2 centered = uv - Vector2(0.5, 0.5);
    centered += Vector2(obj_pos.z, -obj_pos.z) * 0.08;
    double angle = Math::deg_to_rad(v.surface_pattern_rotation_degrees);
    double ca = cos(angle), sa = sin(angle);
    Vector2 rotated(centered.x * ca - centered.y * sa,
                    centered.x * sa + centered.y * ca);
    return Vector2(rotated.x * fmax(v.surface_pattern_scale.x, 0.1),
                   rotated.y * fmax(v.surface_pattern_scale.y, 0.1));
}

static Vector2 surface_object_coord(Vector3 obj_pos, const VisualProps& v) {
    Vector2 centered(obj_pos.x, obj_pos.y);
    double angle = Math::deg_to_rad(v.surface_pattern_rotation_degrees);
    double ca = cos(angle), sa = sin(angle);
    Vector2 rotated(centered.x * ca - centered.y * sa,
                    centered.x * sa + centered.y * ca);
    return Vector2(rotated.x * fmax(v.surface_pattern_scale.x, 0.1),
                   rotated.y * fmax(v.surface_pattern_scale.y, 0.1));
}

static Vector2 apply_procedural_facet_warp(Vector2 coord, Vector3 obj_pos,
                                           Vector3 normal, double warp) {
    double tilt = clampd(1.0 - fmax(normal.z, 0.0), 0.0, 1.0);
    Vector2 facet_axis(normal.x, -normal.y);
    if (facet_axis.length_squared() <= 0.0001) facet_axis = Vector2(1, 0);
    else facet_axis = facet_axis.normalized();
    Vector2 facet_perp(-facet_axis.y, facet_axis.x);
    double bend_angle = (normal.x * 0.8 - normal.y * 0.6) * warp * (0.08 + tilt * 0.12);
    double bc = cos(bend_angle), bs = sin(bend_angle);
    Vector2 rotated(coord.x * bc - coord.y * bs,
                    coord.x * bs + coord.y * bc);
    double along = rotated.dot(facet_axis);
    double across = rotated.dot(facet_perp);
    along *= 1.0 + tilt * warp * 0.04;
    across += along * (normal.x * normal.y) * warp * 0.08;
    across *= 1.0 - tilt * warp * 0.03;
    return facet_axis * along + facet_perp * across;
}

static Color sample_texture(Image* tex, Vector2 uv, Vector3 normal,
                             const VisualProps& v) {
    if (!tex) return v.base_color;
    int w = tex->get_width(), h = tex->get_height();
    if (w <= 0 || h <= 0) return v.base_color;
    Vector2 warped = uv;
    if (v.texture_facet_warp > 0.001) {
        warped += Vector2(normal.x, -normal.y) * v.texture_facet_warp * 0.08;
    }
    Vector2 s = warped;
    s = (s - Vector2(0.5, 0.5)) / fmax(v.texture_zoom, 1.0) + Vector2(0.5, 0.5) + v.texture_offset;
    s.x = clampd(s.x, 0.0, 1.0);
    s.y = clampd(s.y, 0.0, 1.0);
    int px = clampi((int)round(s.x * (w - 1)), 0, w - 1);
    int py = clampi((int)round(s.y * (h - 1)), 0, h - 1);
    return tex->get_pixel(px, py);
}

// -------------------------------------------------------------------------
// Noise primitives
// -------------------------------------------------------------------------

double fract(double value) { return value - floor(value); }

double hash2(Vector2 point) {
    return fract(sin(point.dot(Vector2(127.1, 311.7))) * 43758.5453123);
}

double hash3(Vector3 point) {
    return fract(sin(point.dot(Vector3(127.1, 311.7, 74.7))) * 43758.5453123);
}

double noise2(Vector2 point) {
    Vector2 cell(floor(point.x), floor(point.y));
    Vector2 local = point - cell;
    Vector2 smooth = local * local * (Vector2(3, 3) - local * 2.0);
    double a = hash2(cell);
    double b = hash2(cell + Vector2(1, 0));
    double c = hash2(cell + Vector2(0, 1));
    double d = hash2(cell + Vector2(1, 1));
    return lerpd(lerpd(a, b, smooth.x), lerpd(c, d, smooth.x), smooth.y);
}

double noise3(Vector3 point) {
    Vector3 cell(floor(point.x), floor(point.y), floor(point.z));
    Vector3 local = point - cell;
    Vector3 smooth(
        local.x * local.x * (3.0 - 2.0 * local.x),
        local.y * local.y * (3.0 - 2.0 * local.y),
        local.z * local.z * (3.0 - 2.0 * local.z)
    );
    double x00 = lerpd(hash3(cell), hash3(cell + Vector3(1, 0, 0)), smooth.x);
    double x10 = lerpd(hash3(cell + Vector3(0, 1, 0)), hash3(cell + Vector3(1, 1, 0)), smooth.x);
    double x01 = lerpd(hash3(cell + Vector3(0, 0, 1)), hash3(cell + Vector3(1, 0, 1)), smooth.x);
    double x11 = lerpd(hash3(cell + Vector3(0, 1, 1)), hash3(cell + Vector3(1, 1, 1)), smooth.x);
    double y0 = lerpd(x00, x10, smooth.y);
    double y1 = lerpd(x01, x11, smooth.y);
    return lerpd(y0, y1, smooth.z);
}

double fbm2(Vector2 point) {
    double total = 0, weight = 0.5, freq = 1.0, norm = 0;
    for (int i = 0; i < 3; ++i) {
        total += noise2(point * freq) * weight;
        norm += weight;
        weight *= 0.5; freq *= 2.0;
    }
    return total / fmax(norm, 0.0001);
}

double fbm3(Vector3 point) {
    double total = 0, weight = 0.5, freq = 1.0, norm = 0;
    for (int i = 0; i < 3; ++i) {
        total += noise3(point * freq) * weight;
        norm += weight;
        weight *= 0.5; freq *= 2.0;
    }
    return total / fmax(norm, 0.0001);
}

CellularResult cellular2(Vector2 point) {
    int bx = (int)floor(point.x), by = (int)floor(point.y);
    double nearest = 1e30, second = 1e30, best_seed = 0.5;
    for (int oy = -1; oy <= 1; ++oy) {
        for (int ox = -1; ox <= 1; ++ox) {
            Vector2 cp((double)(bx + ox), (double)(by + oy));
            Vector2 feature = cp + Vector2(hash2(cp + Vector2(17, 3)), hash2(cp + Vector2(5, 29)));
            double dist = feature.distance_to(point);
            if (dist < nearest) { second = nearest; nearest = dist; best_seed = hash2(cp + Vector2(41, 11)); }
            else if (dist < second) second = dist;
        }
    }
    return { nearest, fmax(second - nearest, 0.0), best_seed };
}

CellularResult cellular3(Vector3 point) {
    int bx = (int)floor(point.x), by = (int)floor(point.y), bz = (int)floor(point.z);
    double nearest = 1e30, second = 1e30, best_seed = 0.5;
    for (int oz = -1; oz <= 1; ++oz)
        for (int oy = -1; oy <= 1; ++oy)
            for (int ox = -1; ox <= 1; ++ox) {
                Vector3 cp((double)(bx+ox), (double)(by+oy), (double)(bz+oz));
                Vector3 feature = cp + Vector3(hash3(cp+Vector3(17,3,9)), hash3(cp+Vector3(5,29,13)), hash3(cp+Vector3(23,7,31)));
                double dist = feature.distance_to(point);
                if (dist < nearest) { second = nearest; nearest = dist; best_seed = hash3(cp + Vector3(41,11,19)); }
                else if (dist < second) second = dist;
            }
    return { nearest, fmax(second - nearest, 0.0), best_seed };
}

// -------------------------------------------------------------------------
// Pattern sampling
// -------------------------------------------------------------------------

PatternSample band_sample(Vector2 coord, double density, double contrast) {
    double phase = coord.x * density * Math_TAU * 3.2 + noise2(coord * 1.9) * 1.8;
    double raw = 0.5 + 0.5 * sin(phase);
    double value = apply_contrast(raw, contrast);
    double accent = pow(1.0 - fabs(raw * 2.0 - 1.0), lerpd(2.4, 0.8, contrast));
    return { value, clampd(accent, 0.0, 1.0) };
}

PatternSample ring_sample(Vector2 coord, double density, double contrast) {
    Vector2 scaled = coord * density * 1.7;
    auto nearest = cellular2(scaled);
    double ring_dist = nearest.distance * 9.6 + noise2(scaled * 0.45 + Vector2(3.1, 9.7)) * 1.3;
    double raw = 0.5 + 0.5 * sin(ring_dist * Math_TAU);
    double line_phase = fabs(sin(ring_dist * Math_TAU));
    double line_mask = pow(clampd(1.0 - line_phase, 0.0, 1.0), lerpd(4.5, 12.0, contrast));
    line_mask = fmax(line_mask, clampd(1.0 - nearest.edge_distance * 4.0, 0.0, 1.0) * 0.45);
    double value = apply_contrast(raw * 0.82 + fbm2(scaled * 0.28) * 0.18, contrast);
    return { value, clampd(line_mask, 0.0, 1.0) };
}

PatternSample fiber_sample(Vector2 coord, double density, double contrast) {
    double broad_noise = fbm2(Vector2(coord.x * 0.24, coord.y * 0.62) + Vector2(11.7, 3.1));
    double thickness = fbm2(Vector2(coord.y * 0.38, coord.x * 0.06) + Vector2(41, 2));
    double long_warp = (noise2(Vector2(coord.y * 0.14, 5.4)) - 0.5) * 1.1;
    long_warp += (fbm2(Vector2(coord.y * 0.08, 13.6)) - 0.5) * 1.3;
    double local_density = density * lerpd(0.36, 2.08, broad_noise * 0.72 + thickness * 0.28);
    double macro_band = 0.5 + 0.5 * sin(coord.x * density * Math_TAU * 1.18 + long_warp * 0.55 + broad_noise * 1.4);
    double phase = coord.x * local_density * Math_TAU * 4.4 + long_warp;
    double stripe = 1.0 - fabs(sin(phase));
    double width_noise = fbm2(Vector2(coord.x * 0.12, coord.y * 0.84) + Vector2(17, 8));
    double width_bias = lerpd(0.12, 0.94, width_noise);
    double softened = smoothstepd(width_bias - 0.28, width_bias + 0.10, stripe);
    double band_var = noise2(Vector2(coord.y * 0.9, coord.x * 0.05) + Vector2(23, 4));
    double accent = pow(clampd(softened, 0.0, 1.0), lerpd(1.8, 5.8, contrast));
    accent *= lerpd(0.48, 1.0, broad_noise) * lerpd(0.65, 1.0, band_var);
    double grain = fbm2(Vector2(coord.y * 1.7, coord.x * 0.12) + Vector2(31, 6));
    double grain_shadow = fbm2(Vector2(coord.y * 0.34, coord.x * 0.02) + Vector2(2, 27));
    double raw = clampd(0.04 + accent * 0.68 + macro_band * 0.30 + grain * 0.10 + band_var * 0.10 - grain_shadow * 0.12, 0.0, 1.0);
    return { apply_contrast(raw, contrast), accent };
}

PatternSample cell_sample_2d(Vector2 coord, double contrast) {
    auto nearest = cellular2(coord);
    double foam = pow(clampd(1.0 - nearest.edge_distance * 3.2, 0.0, 1.0), lerpd(1.2, 2.8, contrast));
    double body = fbm2(coord * 0.46 + Vector2(nearest.seed * 3.7, 7.1));
    double raw = clampd(body * 0.62 + (1.0 - foam) * 0.18 + nearest.seed * 0.2, 0.0, 1.0);
    return { apply_contrast(raw, contrast), foam };
}

PatternSample cloud_sample_2d(Vector2 coord, double contrast) {
    double raw = fbm2(coord);
    return { apply_contrast(raw, contrast), clampd(raw * 1.15, 0.0, 1.0) };
}

PatternSample layer_sample(Vector2 coord, double density, double contrast) {
    double phase = coord.y * density * Math_TAU * 3.8 + noise2(coord * 2.3) * 1.6;
    double raw = 0.5 + 0.5 * sin(phase);
    double accent = clampd(0.5 + 0.5 * cos(phase * 0.5), 0.0, 1.0);
    return { apply_contrast(raw, contrast), accent };
}

PatternSample cell_sample_3d(Vector3 coord, double contrast) {
    auto nearest = cellular3(coord);
    double accent = clampd(1.0 - nearest.edge_distance * 2.6, 0.0, 1.0);
    double raw = clampd(nearest.seed * 0.68 + accent * 0.32, 0.0, 1.0);
    return { apply_contrast(raw, contrast), accent };
}

PatternSample cloud_sample_3d(Vector3 coord, double contrast) {
    double raw = fbm3(coord);
    return { apply_contrast(raw, contrast), clampd(raw * 1.12, 0.0, 1.0) };
}

PatternSample volume_layer_sample(Vector3 coord, double density, double contrast) {
    double phase = coord.y * density * Math_TAU * 3.0 + noise3(coord * 1.8) * 2.2;
    double raw = 0.5 + 0.5 * sin(phase);
    double accent = clampd(0.5 + 0.5 * sin(coord.z * density * Math_TAU * 1.4 + phase), 0.0, 1.0);
    return { apply_contrast(raw, contrast), accent };
}

// -------------------------------------------------------------------------
// Surface pattern dispatch
// -------------------------------------------------------------------------

static PatternSample sample_surface_pattern(const VisualProps& v, Vector2 uv,
                                            Vector3 obj_pos, Vector3 normal) {
    Vector2 coord = (v.surface_pattern_type == MATERIAL_PATTERN_CONCENTRIC)
        ? surface_object_coord(obj_pos, v)
        : surface_coord(uv, obj_pos, v);
    double facet_warp = fmax(v.surface_pattern_warp_strength, v.texture_facet_warp * 0.75);
    if (facet_warp > 0.0001)
        coord = apply_procedural_facet_warp(coord, obj_pos, normal, facet_warp);
    if (v.surface_pattern_warp_strength > 0.0001) {
        double wn = noise2(coord * fmax(v.surface_pattern_warp_scale, 0.1));
        double wa = wn * Math_TAU;
        coord += Vector2(cos(wa), sin(wa)) * v.surface_pattern_warp_strength * 0.35;
    }
    double density = fmax(v.surface_pattern_density, 0.1);
    switch (v.surface_pattern_type) {
        case MATERIAL_PATTERN_BANDS:      return band_sample(coord, density, v.surface_pattern_contrast);
        case MATERIAL_PATTERN_CONCENTRIC: return ring_sample(coord, density, v.surface_pattern_contrast);
        case MATERIAL_PATTERN_FIBERS:     return fiber_sample(coord, density, v.surface_pattern_contrast);
        case MATERIAL_PATTERN_CELLS:      return cell_sample_2d(coord * density * 2.0, v.surface_pattern_contrast);
        case MATERIAL_PATTERN_CLOUDS:     return cloud_sample_2d(coord * density * 1.8, v.surface_pattern_contrast);
        case MATERIAL_PATTERN_LAYERS:     return layer_sample(coord, density, v.surface_pattern_contrast);
        default: return { 0.5, 0.5 };
    }
}

// -------------------------------------------------------------------------
// Volume pattern dispatch
// -------------------------------------------------------------------------

static PatternSample sample_volume_pattern(const VisualProps& v, Vector3 obj_pos) {
    double density = fmax(v.volume_pattern_density, 0.1);
    auto basis = basis_from_axis(v.volume_pattern_axis);
    Vector3 coord = project_point(obj_pos, basis);
    coord *= fmax(v.volume_pattern_scale.length(), 0.1);
    if (v.volume_pattern_warp_strength > 0.0001) {
        double wn = noise3(coord * fmax(v.volume_pattern_warp_scale, 0.1));
        coord += Vector3(cos(wn * Math_TAU), sin(wn * Math_TAU), cos((wn + 0.31) * Math_TAU))
                 * v.volume_pattern_warp_strength * 0.24;
    }
    switch (v.volume_pattern_type) {
        case MATERIAL_PATTERN_BANDS:      return band_sample(Vector2(coord.x, coord.z), density, v.volume_pattern_contrast);
        case MATERIAL_PATTERN_CONCENTRIC: return ring_sample(Vector2(coord.x, coord.y), density, v.volume_pattern_contrast);
        case MATERIAL_PATTERN_FIBERS:     return fiber_sample(Vector2(coord.x, coord.z), density, v.volume_pattern_contrast);
        case MATERIAL_PATTERN_CELLS:      return cell_sample_3d(coord * density * 2.0, v.volume_pattern_contrast);
        case MATERIAL_PATTERN_CLOUDS:     return cloud_sample_3d(coord * density * 1.7, v.volume_pattern_contrast);
        case MATERIAL_PATTERN_LAYERS:     return volume_layer_sample(coord, density, v.volume_pattern_contrast);
        default: return { 0.5, 0.5 };
    }
}

// -------------------------------------------------------------------------
// Reactive effects
// -------------------------------------------------------------------------

static Color sample_chatoyancy(const VisualProps& v, Vector3 rcoord,
                               Vector3 half_vec, const BasisAxes& basis) {
    double sweep = rcoord.x * v.reactive_density + half_vec.dot(basis.tangent) * 2.8;
    double band = exp(-sweep * sweep * lerpd(1.4, 6.0, fmin(v.reactive_sharpness / 8.0, 1.0)));
    double angle_term = pow(fmax(fabs(half_vec.dot(basis.axis)), 0.0), fmax(v.reactive_sharpness, 0.5));
    Color base = v.reactive_color.a > 0.001 ? v.reactive_color : resolve_secondary_color(v, v.base_color);
    double strength = band * angle_term * v.reactive_strength;
    return base * clampd(strength, 0.0, 4.0);
}

static Color sample_opalescence(const VisualProps& v, Vector3 rcoord,
                                Vector3 obj_pos, Vector3 normal, Vector3 half_vec) {
    double scale = v.reactive_density * 1.3;
    double ca = fbm3(rcoord * scale + obj_pos * 0.8 + Vector3(5, 11, 2));
    double cb = fbm3(rcoord * scale * 2.1 + Vector3(17, 7, 13));
    double cc = noise3(rcoord * scale * 3.1 + Vector3(3, 19, 23));
    double nebula = clampd(ca * 0.54 + cb * 0.32 + cc * 0.14, 0.0, 1.0);
    double zone_mask = smoothstepd(0.44, 0.78, nebula);
    double glint = 0.32 + 0.68 * pow(fmax(normal.normalized().dot(half_vec), 0.0),
                                       lerpd(4.0, 14.0, fmin(v.reactive_sharpness / 8.0, 1.0)));
    double prism_shift = fract(ca * 0.33 + cb * 0.27 + cc * 0.19
        + obj_pos.dot(Vector3(0.58, 0.96, 0.74)) * 0.12
        + half_vec.dot(Vector3(0.44, 0.18, 0.88)) * 0.21);
    Color spectral_a = Color::from_hsv(prism_shift, 0.92, 1.0);
    Color spectral_c = Color::from_hsv(fract(prism_shift + 0.42), 0.94, 1.0);
    Color warm = v.reactive_color.a > 0.001 ? v.reactive_color : spectral_a;
    Color cool = v.reactive_secondary_color.a > 0.001
        ? v.reactive_secondary_color : Color::from_hsv(fract(prism_shift + 0.18), 0.88, 1.0);
    double ba = noise3(rcoord * 1.1 + Vector3(9, 3, 21));
    double bb = noise3(rcoord * 1.7 + Vector3(13, 15, 7));
    Color flash = color_lerp(warm, cool, ba);
    flash = color_lerp(flash, spectral_c, bb * 0.65);
    return flash * clampd(zone_mask * glint * v.reactive_strength, 0.0, 5.0);
}

static Color sample_iridescence(const VisualProps& v, Vector3 rcoord,
                                Vector3 normal, Vector3 half_vec) {
    static const Vector3 VIEW_DIR(0, 0, 1);
    double facing = clampd(1.0 - fmax(normal.normalized().dot(VIEW_DIR), 0.0), 0.0, 1.0);
    double shift = fract(rcoord.x * v.reactive_density * 0.18 + half_vec.y * 0.33 + facing * 0.46);
    Color base = v.reactive_color.a > 0.001 ? v.reactive_color : Color::from_hsv(shift, 0.7, 1.0);
    Color secondary = v.reactive_secondary_color.a > 0.001
        ? v.reactive_secondary_color : Color::from_hsv(fract(shift + 0.28), 0.75, 1.0);
    double strength = pow(facing, fmax(v.reactive_sharpness, 0.5)) * v.reactive_strength;
    return color_lerp(base, secondary, 0.5 + 0.5 * sin(shift * Math_TAU)) * clampd(strength, 0.0, 4.0);
}

// -------------------------------------------------------------------------
// Public API
// -------------------------------------------------------------------------

double transmission_factor(const VisualProps& v) {
    switch (v.material_mode) {
        case MATERIAL_MODE_PATTERNED_OPAQUE:      return 0.0;
        case MATERIAL_MODE_PATTERNED_TRANSLUCENT:  return 0.78;
        default: return 1.0;
    }
}

SurfaceMaterialSample apply_surface_material(
    const VisualProps& v, Color base_color, Vector2 uv,
    Vector3 obj_pos, Vector3 normal, Image* texture_image) {

    Color color = base_color;
    double pattern_value = 0.5, accent_value = 0.0;
    if (v.surface_pattern_type != MATERIAL_PATTERN_NONE) {
        auto ps = sample_surface_pattern(v, uv, obj_pos, normal);
        pattern_value = ps.value;
        accent_value = ps.accent;
        color = mix_palette(color, resolve_secondary_color(v, color),
                            resolve_tertiary_color(v, color),
                            pattern_value, accent_value, v.surface_pattern_mix);
    }
    if (v.use_texture && texture_image) {
        Color tex_sample = sample_texture(texture_image, uv, normal, v);
        color = color_lerp(color, tex_sample, clampd(v.texture_blend, 0.0, 1.0));
    }
    return {
        color, pattern_value, accent_value,
        clampd(1.0 + v.surface_pattern_roughness_variation * ((pattern_value - 0.5) * 2.0), 0.25, 2.5),
        clampd(1.0 + v.surface_pattern_specular_variation * ((accent_value - 0.5) * 2.0), 0.1, 3.0),
    };
}

VolumeMaterialSample sample_volume_material(const VisualProps& v, Vector3 obj_pos) {
    Color color = v.base_color;
    if (v.volume_pattern_type == MATERIAL_PATTERN_NONE) {
        return { color, 0.5, 0.5, 1.0, 1.0 };
    }
    auto ps = sample_volume_pattern(v, obj_pos);
    color = mix_palette(color, resolve_secondary_color(v, color),
                        resolve_tertiary_color(v, color),
                        ps.value, ps.accent, v.volume_pattern_mix);
    return {
        color, ps.value, ps.accent,
        clampd(1.0 + v.volume_absorption_variation * ((ps.value - 0.5) * 2.0), 0.12, 4.0),
        clampd(1.0 + v.volume_scattering_variation * ((ps.accent - 0.5) * 2.0), 0.12, 4.0),
    };
}

Color sample_reactive_color(const VisualProps& v, Vector3 obj_pos,
                            Vector3 normal, Vector3 light_dir, Vector3 view_dir) {
    if (v.reactive_effect_type == MATERIAL_REACTIVE_NONE) return Color(0, 0, 0, 0);
    if (v.reactive_strength <= 0.0001) return Color(0, 0, 0, 0);
    Vector3 resolved_view = view_dir.normalized();
    Vector3 half_vec = (light_dir.normalized() + resolved_view).normalized();
    if (half_vec.length_squared() < 0.0001) half_vec = resolved_view;
    auto basis = basis_from_axis(v.reactive_axis);
    Vector3 rcoord = project_point(obj_pos * fmax(v.reactive_scale, 0.1), basis);
    switch (v.reactive_effect_type) {
        case MATERIAL_REACTIVE_CHATTOYANCY:  return sample_chatoyancy(v, rcoord, half_vec, basis);
        case MATERIAL_REACTIVE_OPALESCENCE:  return sample_opalescence(v, rcoord, obj_pos, normal, half_vec);
        case MATERIAL_REACTIVE_IRIDESCENCE:  return sample_iridescence(v, rcoord, normal, half_vec);
        default: return Color(0, 0, 0, 0);
    }
}

}} // namespace gem::material
