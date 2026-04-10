#pragma once
// GemTraceKernel — GDExtension class exposed to GDScript.
// The sole tracer implementation for the gem bake pipeline.

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

    static int max_supported_sample_count() { return MAX_SAMPLE_COUNT; }

protected:
    static void _bind_methods();

private:
    godot::Dictionary last_trace_profile_;

    // --- Context building ---
    TraceContext build_context(
        godot::Ref<godot::Resource> mesh_resource,
        godot::Ref<godot::Resource> visual,
        godot::Dictionary& request) const;

    VisualProps extract_visual_props(godot::Ref<godot::Resource> visual) const;
    TraceFlags build_trace_flags(const VisualProps& v) const;
    EnvironmentSetup build_environment_setup(
        godot::Vector3 light_dir,
        godot::Vector2 lighting_uv,
        const VisualProps& v,
        const godot::Dictionary& request) const;
    SurfaceSetup build_surface_setup(
        const VisualProps& v,
        const EnvironmentSetup& env,
        godot::Vector3 light_dir,
        godot::Vector2 lighting_uv,
        godot::StringName variant_type) const;
    std::vector<SpectralSample> build_spectral_samples(
        const VisualProps& v,
        const godot::Dictionary& request) const;

    // --- Per-pixel tracing ---
    void trace_row_band(const TraceContext& ctx, const TraceScene& scene,
                        int row_start, int row_end,
                        std::vector<godot::Color>& out_pixels) const;

    double trace_wavelength(const TraceContext& ctx, const TraceScene& scene,
                            godot::Vector3 origin, godot::Vector3 dir,
                            double wavelength_t, double current_ior,
                            int depth, int last_tri) const;

    double trace_wavelength_from_hit(const TraceContext& ctx, const TraceScene& scene,
                                     const HitResult& hit,
                                     godot::Vector3 origin, godot::Vector3 dir,
                                     double wavelength_t, double current_ior,
                                     int depth) const;

    // --- Physics ---
    static double fresnel_dielectric(godot::Vector3 dir, godot::Vector3 normal,
                                     double eta_i, double eta_t);
    static godot::Vector3 refract_ray(godot::Vector3 dir, godot::Vector3 normal,
                                      double eta_i, double eta_t);
    static double wavelength_ior(const VisualProps& v, double wavelength_t);

    struct RefractionComponent { godot::Vector3 dir; double ior; double weight; };
    std::vector<RefractionComponent> build_refraction_components(
        godot::Vector3 dir, godot::Vector3 normal,
        const VisualProps& v, const TraceContext& ctx,
        double wavelength_t, double eta_i, double eta_t,
        bool is_entry_hit) const;

    // --- Lighting ---
    godot::Vector3 compute_surface_lighting(
        const TraceContext& ctx,
        godot::Vector3 position, godot::Vector3 normal,
        godot::StringName zone) const;

    double compute_interface_highlight(
        const TraceContext& ctx,
        godot::StringName zone, godot::Vector3 normal,
        godot::Vector3 view_dir, double wavelength_t) const;

    double sample_environment(const TraceContext& ctx,
                              godot::Vector3 dir, double wavelength_t) const;

    // --- Volume ---
    double compute_segment_attenuation(const VisualProps& v, double wavelength_t,
                                       double distance,
                                       const VolumeMaterialSample* medium) const;
    double compute_segment_scattering(const VisualProps& v, double wavelength_t,
                                      double distance,
                                      const VolumeMaterialSample* medium) const;
    VolumeMaterialSample sample_segment_volume(const VisualProps& v,
        godot::Vector3 start, godot::Vector3 end, double radius) const;

    // --- Output grading ---
    godot::Vector3 apply_output_grade(godot::Vector3 color, const TraceContext& ctx) const;
    void clean_alpha_edges(godot::Ref<godot::Image> image) const;

    // --- Helpers ---
    static godot::Vector3 spectral_rgb_basis(double wavelength_t);
    static double sample_color_wavelength(godot::Color color, double wavelength_t);
    static double planckian_radiance(double wavelength_t, double temperature_kelvin);
    static double ground_bounce_radiance(
        godot::Vector3 dir, const EnvironmentSetup& env,
        double wavelength_t, double roughness, double light_energy);
    static double apply_aces_channel(double value);
    static godot::Vector3 compress_luma_range(godot::Vector3 color, double amount);
    static godot::Vector3 soft_highlight_rolloff(godot::Vector3 color, double amount);
    static godot::Vector3 adjust_saturation(godot::Vector3 color, double amount);
    static godot::Vector3 set_luma(godot::Vector3 color, double target_luma);
    static ZoneSurfaceScales resolve_zone_surface_scales(godot::StringName zone,
        const godot::Dictionary& zone_overrides);
    static double zone_light_multiplier(godot::StringName zone, const VisualProps& v);
    godot::Color resolve_body_color(godot::Vector3 position, godot::Vector3 normal,
                                    double radius, const VisualProps& v) const;
    godot::Color resolve_highlight_tint(const VisualProps& v,
                                        godot::Color body = godot::Color(0,0,0,0)) const;
};

} // namespace gem
