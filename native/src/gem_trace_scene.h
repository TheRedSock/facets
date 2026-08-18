#pragma once
// Embree-backed ray intersection scene.

#include "gem_trace_types.h"
#include <embree4/rtcore.h>
#include <array>
#include <vector>

namespace gem {

class TraceScene {
public:
    TraceScene();
    ~TraceScene();

    // Non-copyable (owns Embree handles)
    TraceScene(const TraceScene&) = delete;
    TraceScene& operator=(const TraceScene&) = delete;

    /// Build from GDScript trace_data Dictionary.
    /// Reads triangle_vertices_a/b/c, triangle_normals, triangle_zones.
    void build_from_trace_data(const godot::Dictionary& trace_data);

    /// Cast a ray and return the closest hit.
    /// skip_triangle: triangle index to ignore (-1 for none).
    HitResult intersect(godot::Vector3 origin, godot::Vector3 dir,
                        int skip_triangle = -1) const;

    bool is_valid() const { return scene_ != nullptr; }
    int  triangle_count() const { return tri_count_; }
    int  surface_wear_count() const { return (int)surface_wear_.size(); }
    void set_surface_wear_pixel_floor(double bounding_radius, godot::Vector2i target_size);

private:
    RTCDevice device_ = nullptr;
    RTCScene  scene_  = nullptr;
    int       tri_count_ = 0;

    // Side-channel data that Embree doesn't store (indexed by primID)
    std::vector<godot::Vector3>    normals_;
    std::vector<godot::StringName> zones_;
    std::vector<int>               facet_indices_;
    std::vector<SurfaceWearEntry>  surface_wear_;
    double surface_wear_pixel_radius_ = 0.0;

    // Per-vertex smoothed normals for facet edge rounding (indexed by primID)
    bool has_vertex_normals_ = false;
    std::vector<std::array<godot::Vector3, 3>> vertex_normals_; // [primID] = {n_a, n_b, n_c}

    double evaluate_surface_wear(const SurfaceWearEntry& entry, godot::Vector3 point) const;
};

} // namespace gem
