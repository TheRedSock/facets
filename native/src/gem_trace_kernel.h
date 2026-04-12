// gem_trace_kernel.h — GDExtension class exposed to GDScript.
// New spectral path tracer entry point.
#pragma once

#include "gem_trace_types.h"
#include "gem_trace_scene.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace gem {

class GemTraceKernel : public godot::RefCounted {
    GDCLASS(GemTraceKernel, godot::RefCounted)

public:
    GemTraceKernel() = default;
    ~GemTraceKernel() override = default;

    /// Trace a gem to an image. Primary entry point for the bake pipeline.
    godot::Ref<godot::Image> trace_to_image(
        godot::Ref<godot::Resource> mesh_resource,
        godot::Ref<godot::Resource> visual,
        godot::Dictionary request);

    godot::Dictionary get_last_trace_profile() const;

    /// Run built-in physics validation tests. Returns results dictionary.
    godot::Dictionary run_physics_tests() const;

protected:
    static void _bind_methods();

private:
    godot::Dictionary last_trace_profile_;

    // --- Context building ---
    TraceContext build_context(
        godot::Ref<godot::Resource> mesh_resource,
        godot::Ref<godot::Resource> visual,
        godot::Dictionary& request) const;

    GemTraceProps extract_props(godot::Ref<godot::Resource> visual) const;
    EnvironmentSetup build_environment(
        const GemTraceProps& props,
        const godot::Dictionary& request,
        godot::Vector3 light_dir) const;

    // --- Per-pixel tracing ---
    void trace_row_band(const TraceContext& ctx, const TraceScene& scene,
                        int row_start, int row_end,
                        std::vector<godot::Color>& out_pixels) const;

    // --- Output ---
    static double apply_aces_channel(double value);
    void clean_alpha_edges(godot::Ref<godot::Image> image) const;
};

} // namespace gem
