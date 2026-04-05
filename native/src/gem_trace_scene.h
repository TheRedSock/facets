#pragma once
// Embree-backed ray intersection scene.

#include "gem_trace_types.h"
#include <embree4/rtcore.h>
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

private:
    RTCDevice device_ = nullptr;
    RTCScene  scene_  = nullptr;
    int       tri_count_ = 0;

    // Side-channel data that Embree doesn't store (indexed by primID)
    std::vector<godot::Vector3>    normals_;
    std::vector<godot::StringName> zones_;
};

} // namespace gem
