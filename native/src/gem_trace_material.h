#pragma once
// Ported procedural material sampling from GemMaterialSampler.gd.
// All functions are stateless free functions.

#include "gem_trace_types.h"

namespace gem { namespace material {

// --- Public API (called by tracer) ---

double transmission_factor(const VisualProps& v);

SurfaceMaterialSample apply_surface_material(
    const VisualProps& v,
    godot::Color base_color,
    godot::Vector2 uv,
    godot::Vector3 object_position,
    godot::Vector3 normal,
    godot::Image* texture_image);

VolumeMaterialSample sample_volume_material(
    const VisualProps& v,
    godot::Vector3 object_position);

godot::Color sample_reactive_color(
    const VisualProps& v,
    godot::Vector3 object_position,
    godot::Vector3 normal,
    godot::Vector3 light_dir,
    godot::Vector3 view_dir);

// --- Noise primitives ---

double noise2(godot::Vector2 point);
double noise3(godot::Vector3 point);
double fbm2(godot::Vector2 point);
double fbm3(godot::Vector3 point);
CellularResult cellular2(godot::Vector2 point);
CellularResult cellular3(godot::Vector3 point);
double hash2(godot::Vector2 point);
double hash3(godot::Vector3 point);
double fract(double value);

// --- Pattern sampling ---

PatternSample band_sample(godot::Vector2 coord, double density, double contrast);
PatternSample ring_sample(godot::Vector2 coord, double density, double contrast);
PatternSample fiber_sample(godot::Vector2 coord, double density, double contrast);
PatternSample cell_sample_2d(godot::Vector2 coord, double contrast);
PatternSample cloud_sample_2d(godot::Vector2 coord, double contrast);
PatternSample layer_sample(godot::Vector2 coord, double density, double contrast);
PatternSample cell_sample_3d(godot::Vector3 coord, double contrast);
PatternSample cloud_sample_3d(godot::Vector3 coord, double contrast);
PatternSample volume_layer_sample(godot::Vector3 coord, double density, double contrast);

}} // namespace gem::material
