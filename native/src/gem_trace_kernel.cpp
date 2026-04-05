#include "gem_trace_kernel.h"
#include "gem_trace_material.h"
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <thread>
#include <cmath>

using namespace godot;

// MSVC cannot deduce std::max/min when mixing godot::real_t (float) and double.
// These helpers accept any arithmetic types and always return double.
static inline double dmax(double a, double b) { return a > b ? a : b; }
static inline double dmin(double a, double b) { return a < b ? a : b; }

namespace gem {

// ===========================================================================
// Bind methods
// ===========================================================================

void GemTraceKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("trace_to_image", "mesh_resource", "visual", "request"), &GemTraceKernel::trace_to_image);
    ClassDB::bind_method(D_METHOD("get_last_trace_profile"), &GemTraceKernel::get_last_trace_profile);
    ClassDB::bind_static_method("GemTraceKernel", D_METHOD("max_supported_sample_count"), &GemTraceKernel::max_supported_sample_count);
}

// ===========================================================================
// extract_visual_props
// ===========================================================================

VisualProps GemTraceKernel::extract_visual_props(Ref<Resource> visual) const {
    VisualProps props;

    // Colour
    props.base_color = Color(visual->get("base_color"));
    props.material_mode = (int)(int64_t)visual->get("material_mode");
    props.material_secondary_color = Color(visual->get("material_secondary_color"));
    props.material_tertiary_color = Color(visual->get("material_tertiary_color"));
    props.use_texture = (bool)visual->get("use_texture");
    props.texture_blend = (double)(float)visual->get("texture_blend");
    props.texture_zoom = (double)(float)visual->get("texture_zoom");
    props.texture_offset = Vector2(visual->get("texture_offset"));
    props.texture_facet_warp = (double)(float)visual->get("texture_facet_warp");

    // Surface pattern
    props.surface_pattern_type = (int)(int64_t)visual->get("surface_pattern_type");
    props.surface_pattern_mix = (double)(float)visual->get("surface_pattern_mix");
    props.surface_pattern_scale = Vector2(visual->get("surface_pattern_scale"));
    props.surface_pattern_rotation_degrees = (double)(float)visual->get("surface_pattern_rotation_degrees");
    props.surface_pattern_density = (double)(float)visual->get("surface_pattern_density");
    props.surface_pattern_contrast = (double)(float)visual->get("surface_pattern_contrast");
    props.surface_pattern_warp_strength = (double)(float)visual->get("surface_pattern_warp_strength");
    props.surface_pattern_warp_scale = (double)(float)visual->get("surface_pattern_warp_scale");
    props.surface_pattern_specular_variation = (double)(float)visual->get("surface_pattern_specular_variation");
    props.surface_pattern_roughness_variation = (double)(float)visual->get("surface_pattern_roughness_variation");

    // Volume pattern
    props.volume_pattern_type = (int)(int64_t)visual->get("volume_pattern_type");
    props.volume_pattern_mix = (double)(float)visual->get("volume_pattern_mix");
    props.volume_pattern_scale = Vector3(visual->get("volume_pattern_scale"));
    props.volume_pattern_axis = Vector3(visual->get("volume_pattern_axis"));
    props.volume_pattern_density = (double)(float)visual->get("volume_pattern_density");
    props.volume_pattern_contrast = (double)(float)visual->get("volume_pattern_contrast");
    props.volume_pattern_warp_strength = (double)(float)visual->get("volume_pattern_warp_strength");
    props.volume_pattern_warp_scale = (double)(float)visual->get("volume_pattern_warp_scale");
    props.volume_absorption_variation = (double)(float)visual->get("volume_absorption_variation");
    props.volume_scattering_variation = (double)(float)visual->get("volume_scattering_variation");

    // Reactive
    props.reactive_effect_type = (int)(int64_t)visual->get("reactive_effect_type");
    props.reactive_color = Color(visual->get("reactive_color"));
    props.reactive_secondary_color = Color(visual->get("reactive_secondary_color"));
    props.reactive_strength = (double)(float)visual->get("reactive_strength");
    props.reactive_sharpness = (double)(float)visual->get("reactive_sharpness");
    props.reactive_density = (double)(float)visual->get("reactive_density");
    props.reactive_scale = (double)(float)visual->get("reactive_scale");
    props.reactive_axis = Vector3(visual->get("reactive_axis"));

    // Material properties
    props.shininess = (double)(float)visual->get("shininess");
    props.specular_intensity = (double)(float)visual->get("specular_intensity");
    props.transparency = (double)(float)visual->get("transparency");
    props.depth_tint = Color(visual->get("depth_tint"));
    props.saturation_boost = (double)(float)visual->get("saturation_boost");
    props.contrast = (double)(float)visual->get("contrast");
    props.hue_dispersion = (double)(float)visual->get("hue_dispersion");

    // Rim
    props.rim_intensity = (double)(float)visual->get("rim_intensity");
    props.rim_color = Color(visual->get("rim_color"));
    props.rim_power = (double)(float)visual->get("rim_power");

    // Translucency
    props.translucency = (double)(float)visual->get("translucency");
    props.translucency_color = Color(visual->get("translucency_color"));

    // Secondary specular
    props.secondary_specular = (double)(float)visual->get("secondary_specular");
    props.secondary_light_angle = (double)(float)visual->get("secondary_light_angle");

    // Sparkle
    props.sparkle_intensity = (double)(float)visual->get("sparkle_intensity");
    props.sparkle_threshold = (double)(float)visual->get("sparkle_threshold");

    // Gradient
    props.gradient_color = Color(visual->get("gradient_color"));
    props.gradient_strength = (double)(float)visual->get("gradient_strength");
    props.gradient_mode = (int)(int64_t)visual->get("gradient_mode");
    props.gradient_angle_degrees = (double)(float)visual->get("gradient_angle_degrees");

    // Phenomenon
    props.phenomenon_color = Color(visual->get("phenomenon_color"));
    props.phenomenon_strength = (double)(float)visual->get("phenomenon_strength");
    props.phenomenon_angle_degrees = (double)(float)visual->get("phenomenon_angle_degrees");
    props.phenomenon_sharpness = (double)(float)visual->get("phenomenon_sharpness");

    // Zone brilliance / extinction
    props.brilliance_contrast = (double)(float)visual->get("brilliance_contrast");
    props.extinction = (double)(float)visual->get("extinction");

    // Optics
    props.optics_ior = (double)(float)visual->get("optics_ior");
    props.optics_dispersion = (double)(float)visual->get("optics_dispersion");
    props.optics_absorption_color = Color(visual->get("optics_absorption_color"));
    props.optics_absorption_strength = (double)(float)visual->get("optics_absorption_strength");
    props.optics_surface_roughness = (double)(float)visual->get("optics_surface_roughness");
    props.optics_scattering_strength = (double)(float)visual->get("optics_scattering_strength");
    props.optics_scattering_color = Color(visual->get("optics_scattering_color"));
    props.optics_trace_view_scale = (double)(float)visual->get("optics_trace_view_scale");
    props.optics_birefringence_strength = (double)(float)visual->get("optics_birefringence_strength");
    props.optics_optic_axis = Vector3(visual->get("optics_optic_axis"));
    props.optics_lighting_view_pitch_degrees = (double)(float)visual->get("optics_lighting_view_pitch_degrees");
    props.optics_lighting_view_yaw_degrees = (double)(float)visual->get("optics_lighting_view_yaw_degrees");
    props.optics_rotation_view_pitch_degrees = (double)(float)visual->get("optics_rotation_view_pitch_degrees");
    props.optics_rotation_view_yaw_degrees = (double)(float)visual->get("optics_rotation_view_yaw_degrees");
    props.optics_environment_preset = (int)(int64_t)visual->get("optics_environment_preset");
    props.optics_environment_rotation_degrees = (double)(float)visual->get("optics_environment_rotation_degrees");
    props.optics_environment_energy = (double)(float)visual->get("optics_environment_energy");
    props.optics_light_energy = (double)(float)visual->get("optics_light_energy");

    props.rotation_degrees = (double)(float)visual->get("rotation_degrees");

    return props;
}

// ===========================================================================
// get_last_trace_profile
// ===========================================================================

Dictionary GemTraceKernel::get_last_trace_profile() const {
    return last_trace_profile_.duplicate(true);
}

// ===========================================================================
// View basis building
// ===========================================================================

static Basis build_view_basis(const VisualProps& v, const Dictionary& request) {
    StringName variant_type = StringName(request.get("variant_type", StringName()));
    double pitch = 0.0;
    double yaw = 0.0;
    if (variant_type == StringName("rotation")) {
        pitch = (double)(float)request.get("view_pitch_degrees", v.optics_rotation_view_pitch_degrees);
        yaw = (double)(float)request.get("view_yaw_degrees", v.optics_rotation_view_yaw_degrees);
    } else if (variant_type == StringName("lighting")) {
        pitch = (double)(float)request.get("view_pitch_degrees", v.optics_lighting_view_pitch_degrees);
        yaw = (double)(float)request.get("view_yaw_degrees", v.optics_lighting_view_yaw_degrees);
    } else {
        pitch = (double)(float)request.get("view_pitch_degrees", v.optics_rotation_view_pitch_degrees);
        yaw = (double)(float)request.get("view_yaw_degrees", v.optics_rotation_view_yaw_degrees);
    }
    Basis basis = Basis(Vector3(1, 0, 0), Math::deg_to_rad(pitch));
    bool mesh_includes_cut_rotation = (bool)request.get("mesh_includes_cut_rotation", false);
    double yaw_degrees = yaw;
    double roll_degrees = (double)(float)request.get("view_roll_degrees", 0.0);
    if (!mesh_includes_cut_rotation) {
        yaw_degrees += (double)(float)request.get("rotation_degrees", 0.0);
        roll_degrees += v.rotation_degrees;
    }
    basis = Basis(Vector3(0, 1, 0), Math::deg_to_rad(yaw_degrees)) * basis;
    if (std::abs(roll_degrees) > 1e-6) {
        basis = Basis(Vector3(0, 0, 1), Math::deg_to_rad(roll_degrees)) * basis;
    }
    return basis;
}

// ===========================================================================
// Transform AABB by basis
// ===========================================================================

static AABB transform_aabb(const AABB& bounds, const Basis& basis) {
    Vector3 corners[8] = {
        bounds.position,
        bounds.position + Vector3(bounds.size.x, 0.0, 0.0),
        bounds.position + Vector3(0.0, bounds.size.y, 0.0),
        bounds.position + Vector3(0.0, 0.0, bounds.size.z),
        bounds.position + Vector3(bounds.size.x, bounds.size.y, 0.0),
        bounds.position + Vector3(bounds.size.x, 0.0, bounds.size.z),
        bounds.position + Vector3(0.0, bounds.size.y, bounds.size.z),
        bounds.position + bounds.size,
    };
    Vector3 min_v(1e30, 1e30, 1e30);
    Vector3 max_v(-1e30, -1e30, -1e30);
    for (int i = 0; i < 8; i++) {
        Vector3 transformed = basis.xform(corners[i]);
        min_v.x = dmin(min_v.x, (double)transformed.x);
        min_v.y = dmin(min_v.y, (double)transformed.y);
        min_v.z = dmin(min_v.z, (double)transformed.z);
        max_v.x = dmax(max_v.x, (double)transformed.x);
        max_v.y = dmax(max_v.y, (double)transformed.y);
        max_v.z = dmax(max_v.z, (double)transformed.z);
    }
    if (min_v.x >= 1e29) {
        return AABB();
    }
    return AABB(min_v, max_v - min_v);
}

// ===========================================================================
// Resolve optic axis
// ===========================================================================

static Vector3 resolve_optic_axis(const VisualProps& v) {
    Vector3 axis = v.optics_optic_axis;
    if (axis.length_squared() < 1e-8) {
        return Vector3(0, 1, 0);
    }
    return axis.normalized();
}

// ===========================================================================
// build_context
// ===========================================================================

TraceContext GemTraceKernel::build_context(
    Ref<Resource> mesh_resource,
    Ref<Resource> visual,
    Dictionary& request) const
{
    TraceContext ctx;

    Vector2i target_size = Vector2i(request.get("trace_size",
        request.get("draw_size",
            request.get("target_size", Vector2i(0, 0)))));
    ctx.target_size = target_size;

    // Extract flattened visual properties
    VisualProps v = extract_visual_props(visual);
    ctx.visual = v;

    // Build trace data from mesh resource
    Dictionary trace_data_raw = Dictionary(mesh_resource->call("build_trace_data"));
    Dictionary trace_data = trace_data_raw.duplicate(false);
    trace_data["optic_axis"] = resolve_optic_axis(v);
    // Store trace_data in request so trace_to_image can access it
    request["_trace_data"] = trace_data;

    // Build view basis
    Basis view_basis = build_view_basis(v, request);
    Basis inverse_basis = view_basis.inverse();
    ctx.inverse_basis = inverse_basis;

    // Compute bounds
    AABB source_bounds = AABB(trace_data.get("bounds", AABB()));
    AABB bounds = transform_aabb(source_bounds, view_basis);
    double radius = dmax((double)(float)trace_data.get("bounding_radius", 0.5), 0.25);
    ctx.radius = radius;

    // Camera params
    double aspect = (double)target_size.x / dmax((double)target_size.y, 1.0);
    double view_scale = clampd((double)(float)request.get("view_scale", 1.0), 0.5, 2.0);
    double half_height = dmax((double)bounds.size.y, radius * 2.0) * VIEW_MARGIN * 0.5 / view_scale;
    double half_width = half_height * aspect;
    double origin_z = (double)bounds.position.z + (double)bounds.size.z + radius * 2.4;
    ctx.half_width = half_width;
    ctx.half_height = half_height;
    ctx.origin_z = origin_z;

    Vector3 dir = inverse_basis.xform(Vector3(0.0, 0.0, -1.0)).normalized();
    Vector3 light_dir_world = Vector3(request.get("light_dir", Vector3(-0.4, -0.5, 0.75))).normalized();
    if (light_dir_world.length_squared() < 1e-8) {
        light_dir_world = Vector3(-0.4, -0.5, 0.75).normalized();
    }
    Vector3 light_dir = inverse_basis.xform(light_dir_world).normalized();
    Vector3 view_dir = -dir;
    ctx.dir = dir;
    ctx.light_dir = light_dir;
    ctx.view_dir = view_dir;

    Vector2 lighting_uv = Vector2(request.get("lighting_uv", Vector2(0, 0)));

    // Build trace flags
    ctx.flags = build_trace_flags(v);

    // Build environment and surface setup
    EnvironmentSetup env_setup = build_environment_setup(light_dir, lighting_uv, v);
    StringName variant_type = StringName(request.get("variant_type", StringName()));
    SurfaceSetup surface_setup = build_surface_setup(v, env_setup, light_dir, lighting_uv, variant_type);
    ctx.environment = env_setup;
    ctx.surface = surface_setup;

    // Spectral samples
    ctx.spectral_samples = build_spectral_samples(v);
    ctx.sample_count = clampi(
        (int)(int64_t)request.get("sample_count", DEFAULT_SAMPLE_COUNT),
        1, MAX_SAMPLE_COUNT);

    // Max bounces
    ctx.max_bounces = clampi(
        (int)(int64_t)request.get("max_trace_bounces", MAX_TRACE_BOUNCES),
        1, MAX_OVERRIDE_TRACE_BOUNCES);

    // Texture image
    if (v.use_texture) {
        Variant color_texture = visual->get("color_texture");
        if (color_texture.get_type() != Variant::NIL) {
            Ref<Resource> tex_res = color_texture;
            if (tex_res.is_valid()) {
                ctx.texture_image = Ref<Image>(tex_res->call("get_image"));
            }
        }
    }

    // Optic axis from trace data
    Vector3 optic_axis = Vector3(trace_data.get("optic_axis", Vector3(0, 1, 0)));
    if (optic_axis.length_squared() < 1e-8) {
        optic_axis = Vector3(0, 1, 0);
    }
    ctx.optic_axis = optic_axis.normalized();

    return ctx;
}

// ===========================================================================
// trace_to_image
// ===========================================================================

Ref<Image> GemTraceKernel::trace_to_image(
    Ref<Resource> mesh_resource,
    Ref<Resource> visual,
    Dictionary request)
{
    last_trace_profile_.clear();
    if (mesh_resource.is_null() || visual.is_null()) {
        return Ref<Image>();
    }

    Vector2i target_size = Vector2i(request.get("trace_size",
        request.get("draw_size",
            request.get("target_size", Vector2i(0, 0)))));
    if (target_size.x <= 0 || target_size.y <= 0) {
        return Ref<Image>();
    }

    // Build context (extracts visual, builds camera, environment, etc.)
    TraceContext ctx = build_context(mesh_resource, visual, request);

    // Build Embree scene from trace data
    Dictionary trace_data = Dictionary(request.get("_trace_data", Dictionary()));
    TraceScene scene;
    scene.build_from_trace_data(trace_data);
    if (!scene.is_valid()) {
        return Ref<Image>();
    }

    // Resolve thread count
    int thread_budget = clampi(
        (int)(int64_t)request.get("thread_budget",
            request.get("thread_count", OS::get_singleton()->get_processor_count() - 1)),
        1, 32);

    int sample_count = ctx.sample_count;
    int spectral_count = (int)ctx.spectral_samples.size();
    int thread_count = 0;
    if (request.has("thread_count")) {
        thread_count = dmax(dmin(thread_budget, dmax((int)target_size.y, 1)), 1);
    } else {
        int pixel_count = dmax(target_size.x * target_size.y, 1);
        int row_limit = dmax(target_size.y / MIN_ROWS_PER_TRACE_THREAD, 1);
        int pixel_limit = dmax(pixel_count / MIN_PIXELS_PER_TRACE_THREAD, 1);
        int work_units = pixel_count * dmax(sample_count, 1) * dmax(spectral_count, 1);
        int work_limit = dmax(work_units / MIN_WORK_UNITS_PER_TRACE_THREAD, 1);
        thread_count = dmax(
            dmin(dmin(thread_budget, row_limit), dmin(pixel_limit, work_limit)),
            1);
    }

    int total_pixels = target_size.x * target_size.y;
    std::vector<Color> pixels(total_pixels, Color(0, 0, 0, 0));

    if (thread_count <= 1) {
        trace_row_band(ctx, scene, 0, target_size.y, pixels);
    } else {
        int rows_per_thread = (target_size.y + thread_count - 1) / thread_count;
        std::vector<std::thread> threads;
        for (int t = 0; t < thread_count; t++) {
            int row_start = t * rows_per_thread;
            int row_end = dmin((t + 1) * rows_per_thread, (int)target_size.y);
            if (row_start >= target_size.y) break;
            threads.emplace_back([this, &ctx, &scene, row_start, row_end, &pixels]() {
                trace_row_band(ctx, scene, row_start, row_end, pixels);
            });
        }
        for (auto& th : threads) {
            th.join();
        }
    }

    // Encode to RGBA8
    PackedByteArray bytes;
    bytes.resize(total_pixels * 4);
    for (int i = 0; i < total_pixels; i++) {
        const Color& c = pixels[i];
        int idx = i * 4;
        bytes[idx]     = (uint8_t)std::round(clampd(c.r, 0.0, 1.0) * 255.0);
        bytes[idx + 1] = (uint8_t)std::round(clampd(c.g, 0.0, 1.0) * 255.0);
        bytes[idx + 2] = (uint8_t)std::round(clampd(c.b, 0.0, 1.0) * 255.0);
        bytes[idx + 3] = (uint8_t)std::round(clampd(c.a, 0.0, 1.0) * 255.0);
    }

    Ref<Image> image = Image::create_from_data(
        target_size.x, target_size.y, false, Image::FORMAT_RGBA8, bytes);

    clean_alpha_edges(image);
    return image;
}

// ===========================================================================
// trace_row_band
// ===========================================================================

void GemTraceKernel::trace_row_band(
    const TraceContext& ctx,
    const TraceScene& scene,
    int row_start,
    int row_end,
    std::vector<Color>& out_pixels) const
{
    int width = ctx.target_size.x;
    double inv_w = 1.0 / (double)ctx.target_size.x;
    double inv_h = 1.0 / (double)ctx.target_size.y;

    for (int y = row_start; y < row_end; y++) {
        for (int x = 0; x < width; x++) {
            Vector3 rgb_sum(0.0, 0.0, 0.0);
            double hit_count = 0.0;

            for (int si = 0; si < ctx.sample_count; si++) {
                double ox = SAMPLE_PATTERN[si].x;
                double oy = SAMPLE_PATTERN[si].y;
                double u = (((double)x + ox) * inv_w) * 2.0 - 1.0;
                double v = 1.0 - (((double)y + oy) * inv_h) * 2.0;
                Vector3 origin = ctx.inverse_basis.xform(
                    Vector3(u * ctx.half_width, v * ctx.half_height, ctx.origin_z));

                HitResult first_hit = scene.intersect(origin, ctx.dir, -1);
                if (!first_hit.did_hit) continue;

                hit_count += 1.0;

                for (size_t sp = 0; sp < ctx.spectral_samples.size(); sp++) {
                    double wavelength_t = ctx.spectral_samples[sp].t;
                    Vector3 weight = ctx.spectral_samples[sp].weight;

                    double intensity = trace_wavelength_from_hit(
                        ctx, scene, first_hit,
                        origin, ctx.dir,
                        wavelength_t, AIR_IOR, 0);

                    rgb_sum += Vector3(
                        weight.x * intensity,
                        weight.y * intensity,
                        weight.z * intensity);
                }

                // Surface lighting
                rgb_sum += compute_surface_lighting(
                    ctx, first_hit.position, first_hit.normal, first_hit.zone);
            }

            int pixel_index = y * width + x;
            if (hit_count <= 0.0) {
                out_pixels[pixel_index] = Color(0.0, 0.0, 0.0, 0.0);
            } else {
                Vector3 color = apply_output_grade(rgb_sum / hit_count, ctx.visual);
                out_pixels[pixel_index] = Color(
                    color.x, color.y, color.z,
                    clampd(hit_count / (double)ctx.sample_count, 0.0, 1.0));
            }
        }
    }
}

// ===========================================================================
// trace_wavelength
// ===========================================================================

double GemTraceKernel::trace_wavelength(
    const TraceContext& ctx,
    const TraceScene& scene,
    Vector3 origin,
    Vector3 dir,
    double wavelength_t,
    double current_ior,
    int depth,
    int last_tri) const
{
    if (depth >= ctx.max_bounces) {
        return sample_environment(ctx, dir, wavelength_t);
    }
    if (ctx.flags.is_patterned_opaque) {
        return 0.0;
    }

    HitResult hit = scene.intersect(origin, dir, last_tri);
    if (!hit.did_hit) {
        return sample_environment(ctx, dir, wavelength_t);
    }

    return trace_wavelength_from_hit(ctx, scene, hit, origin, dir, wavelength_t, current_ior, depth);
}

// ===========================================================================
// trace_wavelength_from_hit
// ===========================================================================

double GemTraceKernel::trace_wavelength_from_hit(
    const TraceContext& ctx,
    const TraceScene& scene,
    const HitResult& hit,
    Vector3 origin,
    Vector3 dir,
    double wavelength_t,
    double current_ior,
    int depth) const
{
    if (!hit.did_hit) {
        return sample_environment(ctx, dir, wavelength_t);
    }

    // Segment attenuation and scattering (inside gem)
    double segment_attenuation = 1.0;
    double scattering_contribution = 0.0;
    if (current_ior > AIR_IOR + 0.0001) {
        VolumeMaterialSample volume_sample;
        const VolumeMaterialSample* medium_ptr = nullptr;
        if (ctx.flags.has_volume_sampling) {
            volume_sample = sample_segment_volume(ctx.visual, origin, hit.position, ctx.radius);
            medium_ptr = &volume_sample;
        }
        segment_attenuation = compute_segment_attenuation(
            ctx.visual, wavelength_t, hit.distance, medium_ptr);
        scattering_contribution = compute_segment_scattering(
            ctx.visual, wavelength_t, hit.distance, medium_ptr);
    }

    Vector3 outward_normal = hit.normal;
    Vector3 shading_normal = hit.front_face ? outward_normal : -outward_normal;

    double eta_i = current_ior;
    double eta_t = AIR_IOR;
    if (hit.front_face) {
        eta_t = wavelength_ior(ctx.visual, wavelength_t);
    }

    double fresnel = fresnel_dielectric(dir, shading_normal, eta_i, eta_t);
    Vector3 reflection_dir = (dir - 2.0 * dir.dot(shading_normal) * shading_normal).normalized();

    double reflection = 0.0;
    if (fresnel > MIN_BRANCH_WEIGHT) {
        reflection = trace_wavelength(
            ctx, scene,
            hit.position + reflection_dir * EPSILON,
            reflection_dir,
            wavelength_t, eta_i,
            depth + 1, hit.triangle_idx);
    }

    double total = reflection * fresnel;

    double transmission_factor = ctx.flags.transmission_factor;
    std::vector<RefractionComponent> refraction_components;
    if (transmission_factor > 0.001) {
        refraction_components = build_refraction_components(
            dir, shading_normal, ctx.visual, ctx,
            wavelength_t, eta_i, eta_t, hit.front_face);
    }

    if (refraction_components.empty()) {
        // Total internal reflection
        total = reflection;
    } else {
        for (const auto& comp : refraction_components) {
            if (comp.dir.length_squared() < 1e-12) continue;
            double branch_weight = (1.0 - fresnel) * comp.weight * transmission_factor;
            if (branch_weight <= MIN_BRANCH_WEIGHT) continue;

            double transmitted = trace_wavelength(
                ctx, scene,
                hit.position + comp.dir * EPSILON,
                comp.dir,
                wavelength_t, comp.ior,
                depth + 1, hit.triangle_idx);

            double cloudiness = ctx.flags.cloudiness;
            transmitted *= 1.0 - cloudiness * (hit.front_face ? 0.12 : 0.06);
            total += transmitted * branch_weight;
        }
    }

    total *= segment_attenuation;

    // Interface highlight only on exterior front-face hits (depth 0)
    if (hit.front_face && depth == 0) {
        total += compute_interface_highlight(
            ctx, hit.zone, shading_normal,
            (-dir).normalized(), wavelength_t
        ) * (0.12 + fresnel * 0.34);
    }

    total += scattering_contribution;
    return clampd(total, 0.0, 18.0);
}

// ===========================================================================
// fresnel_dielectric (Schlick approximation)
// ===========================================================================

double GemTraceKernel::fresnel_dielectric(Vector3 dir, Vector3 normal, double eta_i, double eta_t) {
    double cos_i = clampd(-dir.dot(normal), -1.0, 1.0);
    double denom = dmax(eta_i + eta_t, 0.0001);
    double r0 = (eta_i - eta_t) / denom;
    r0 = r0 * r0;
    return clampd(r0 + (1.0 - r0) * std::pow(1.0 - std::abs(cos_i), 5.0), 0.0, 1.0);
}

// ===========================================================================
// refract_ray (Snell's law)
// ===========================================================================

Vector3 GemTraceKernel::refract_ray(Vector3 dir, Vector3 normal, double eta_i, double eta_t) {
    double eta = eta_i / dmax(eta_t, 0.0001);
    double cos_i = clampd(-dir.dot(normal), -1.0, 1.0);
    double k = 1.0 - eta * eta * (1.0 - cos_i * cos_i);
    if (k < 0.0) {
        return Vector3(0, 0, 0);
    }
    return (dir * eta + normal * (eta * cos_i - std::sqrt(k))).normalized();
}

// ===========================================================================
// wavelength_ior (Cauchy dispersion)
// ===========================================================================

double GemTraceKernel::wavelength_ior(const VisualProps& v, double wavelength_t) {
    double base = dmax(v.optics_ior, 1.0);
    double spread = dmax(v.optics_dispersion, 0.0);
    double lambda_eff = lerpd(0.38, 0.72, clampd(wavelength_t, 0.0, 1.0));
    double lambda_ref = 0.55;
    double cauchy_term = (1.0 / (lambda_eff * lambda_eff) - 1.0 / (lambda_ref * lambda_ref));
    double cauchy_scale = 1.0 / (1.0 / (0.38 * 0.38) - 1.0 / (0.72 * 0.72));
    return dmax(base + spread * cauchy_term * cauchy_scale, 1.0);
}

// Free-function refraction for use in the birefringence helper below.
static Vector3 refract_helper(Vector3 dir, Vector3 normal, double eta_i, double eta_t) {
    double eta = eta_i / dmax(eta_t, 0.0001);
    double cos_i = clampd(-(double)dir.dot(normal), -1.0, 1.0);
    double k = 1.0 - eta * eta * (1.0 - cos_i * cos_i);
    if (k < 0.0) return Vector3(0, 0, 0);
    return (dir * eta + normal * (eta * cos_i - std::sqrt(k))).normalized();
}

// ===========================================================================
// compute_extraordinary_ior (helper for birefringence)
// ===========================================================================

static double compute_extraordinary_ior(
    double base_ior,
    double birefringence_strength,
    Vector3 optic_axis,
    Vector3 dir,
    Vector3 normal)
{
    Vector3 seed_dir = refract_helper(dir, normal, (double)AIR_IOR, base_ior);
    if (seed_dir.length_squared() < 1e-12) {
        seed_dir = (-normal).normalized();
    }
    double ordinary_ior = dmax(base_ior + birefringence_strength, 1.0);
    double extraordinary_axis_ior = dmax(base_ior - birefringence_strength, 1.0);
    double cos_theta = clampd(std::abs(seed_dir.normalized().dot(optic_axis)), 0.0, 1.0);
    double sin_sq = 1.0 - cos_theta * cos_theta;
    double inv_sq = (
        cos_theta * cos_theta / dmax(ordinary_ior * ordinary_ior, 0.0001)
        + sin_sq / dmax(extraordinary_axis_ior * extraordinary_axis_ior, 0.0001)
    );
    return std::sqrt(1.0 / dmax(inv_sq, 0.0001));
}

// ===========================================================================
// build_refraction_components
// ===========================================================================

std::vector<GemTraceKernel::RefractionComponent> GemTraceKernel::build_refraction_components(
    Vector3 dir,
    Vector3 normal,
    const VisualProps& v,
    const TraceContext& ctx,
    double wavelength_t,
    double eta_i,
    double eta_t,
    bool is_entry_hit) const
{
    std::vector<RefractionComponent> components;

    if (!is_entry_hit || eta_i > AIR_IOR + 0.0001 || v.optics_birefringence_strength <= 0.0001) {
        Vector3 single_dir = refract_ray(dir, normal, eta_i, eta_t);
        if (single_dir.length_squared() > 1e-12) {
            components.push_back({single_dir, eta_t, 1.0});
        }
        return components;
    }

    Vector3 optic_axis = ctx.optic_axis;
    if (optic_axis.length_squared() < 1e-8) {
        optic_axis = Vector3(0, 1, 0);
    }
    optic_axis = optic_axis.normalized();

    double base_ior = eta_t;
    double split = v.optics_birefringence_strength;
    double ordinary_ior = dmax(base_ior + split, 1.0);
    double extraordinary_ior = dmax(
        compute_extraordinary_ior(base_ior, v.optics_birefringence_strength, optic_axis, dir, normal),
        1.0);

    Vector3 ordinary_dir = refract_ray(dir, normal, eta_i, ordinary_ior);
    Vector3 extraordinary_dir = refract_ray(dir, normal, eta_i, extraordinary_ior);

    if (ordinary_dir.length_squared() > 1e-12) {
        components.push_back({ordinary_dir, ordinary_ior, 0.5});
    }
    if (extraordinary_dir.length_squared() > 1e-12) {
        components.push_back({extraordinary_dir, extraordinary_ior, 0.5});
    }

    if (components.empty()) {
        Vector3 fallback_dir = refract_ray(dir, normal, eta_i, eta_t);
        if (fallback_dir.length_squared() > 1e-12) {
            components.push_back({fallback_dir, eta_t, 1.0});
        }
    } else if (components.size() == 1) {
        components[0].weight = 1.0;
    }

    return components;
}

// ===========================================================================
// spectral_rgb_basis
// ===========================================================================

Vector3 GemTraceKernel::spectral_rgb_basis(double wavelength_t) {
    double t = clampd(wavelength_t, 0.0, 1.0);
    if (t < 0.16) {
        return Vector3(1.0, lerpd(0.02, 0.34, t / 0.16), 0.0);
    }
    if (t < 0.32) {
        double local_t = (t - 0.16) / 0.16;
        return Vector3(lerpd(1.0, 0.42, local_t), lerpd(0.34, 0.92, local_t), lerpd(0.0, 0.04, local_t));
    }
    if (t < 0.5) {
        double local_t = (t - 0.32) / 0.18;
        return Vector3(lerpd(0.42, 0.08, local_t), 1.0, lerpd(0.04, 0.14, local_t));
    }
    if (t < 0.68) {
        double local_t = (t - 0.5) / 0.18;
        return Vector3(lerpd(0.08, 0.0, local_t), lerpd(1.0, 0.72, local_t), lerpd(0.14, 1.0, local_t));
    }
    if (t < 0.84) {
        double local_t = (t - 0.68) / 0.16;
        return Vector3(lerpd(0.0, 0.02, local_t), lerpd(0.72, 0.12, local_t), 1.0);
    }
    // Violet tail
    double tail_t = (t - 0.84) / 0.16;
    return Vector3(lerpd(0.02, 0.05, tail_t), 0.0, lerpd(1.0, 0.45, tail_t));
}

// ===========================================================================
// sample_color_wavelength
// ===========================================================================

double GemTraceKernel::sample_color_wavelength(Color color, double wavelength_t) {
    Vector3 basis = spectral_rgb_basis(wavelength_t);
    double weight_sum = dmax(basis.x + basis.y + basis.z, 0.0001);
    return clampd(
        ((double)color.r * basis.x + (double)color.g * basis.y + (double)color.b * basis.z) / weight_sum,
        0.0, 8.0);
}

// ===========================================================================
// build_trace_flags
// ===========================================================================

TraceFlags GemTraceKernel::build_trace_flags(const VisualProps& v) const {
    TraceFlags flags;
    flags.is_patterned_opaque = (v.material_mode == MATERIAL_MODE_PATTERNED_OPAQUE);
    flags.has_volume_sampling = (v.volume_pattern_mix > 0.001
        && v.volume_pattern_type != MATERIAL_PATTERN_NONE);
    flags.has_surface_material = (
        (v.surface_pattern_mix > 0.001 && v.surface_pattern_type != MATERIAL_PATTERN_NONE)
        || v.use_texture);
    flags.has_reactive = (v.reactive_strength > 0.0001
        && v.reactive_effect_type != MATERIAL_REACTIVE_NONE);
    flags.transmission_factor = material::transmission_factor(v);
    flags.cloudiness = clampd(
        v.optics_scattering_strength * 1.2
        + v.optics_surface_roughness * 0.3
        + v.translucency * 0.1,
        0.0, 0.5);
    return flags;
}

// ===========================================================================
// build_spectral_samples
// ===========================================================================

std::vector<SpectralSample> GemTraceKernel::build_spectral_samples(const VisualProps& v) const {
    // Choose wavelength set
    bool high_fire = (v.optics_dispersion >= 0.02 || v.sparkle_intensity >= 0.8);

    static const double LOW_FIRE[] = {0.0, 0.5, 1.0};
    static const double HIGH_FIRE[] = {0.0, 0.16, 0.32, 0.5, 0.68, 0.84, 1.0};
    const double* wavelengths = high_fire ? HIGH_FIRE : LOW_FIRE;
    int count = high_fire ? 7 : 3;

    Vector3 normalizer(0, 0, 0);
    std::vector<Vector3> raw_weights;
    raw_weights.reserve(count);

    for (int i = 0; i < count; i++) {
        Vector3 basis = spectral_rgb_basis(wavelengths[i]);
        raw_weights.push_back(basis);
        normalizer += basis;
    }
    normalizer.x = dmax(normalizer.x, 0.0001);
    normalizer.y = dmax(normalizer.y, 0.0001);
    normalizer.z = dmax(normalizer.z, 0.0001);

    std::vector<SpectralSample> result;
    result.reserve(count);
    for (int i = 0; i < count; i++) {
        SpectralSample s;
        s.t = wavelengths[i];
        s.weight = Vector3(
            raw_weights[i].x / normalizer.x,
            raw_weights[i].y / normalizer.y,
            raw_weights[i].z / normalizer.z);
        result.push_back(s);
    }
    return result;
}

// ===========================================================================
// sample_environment
// ===========================================================================

double GemTraceKernel::sample_environment(
    const TraceContext& ctx,
    Vector3 dir,
    double wavelength_t) const
{
    double t = clampd(dir.y * 0.5 + 0.5, 0.0, 1.0);
    double env_energy = dmax(ctx.visual.optics_environment_energy, 0.01);

    const EnvironmentSetup& env = ctx.environment;
    Color horizon_contribution = Color(
        env.horizon.r * std::exp(-std::pow(dir.y / 0.22, 2.0)),
        env.horizon.g * std::exp(-std::pow(dir.y / 0.22, 2.0)),
        env.horizon.b * std::exp(-std::pow(dir.y / 0.22, 2.0)),
        1.0);

    double ground_mix = clampd(-dir.y, 0.0, 1.0);
    Color ground = color_lerp(env.ground_dark, env.ground_lift, ground_mix * 0.22);

    Color sky = color_lerp(env.sky_low, env.sky_top, std::pow(t, 1.35));
    sky = color_lerp(sky, ground, ground_mix);
    Color env_color = Color(
        (sky.r + horizon_contribution.r) * env_energy,
        (sky.g + horizon_contribution.g) * env_energy,
        (sky.b + horizon_contribution.b) * env_energy,
        1.0);

    double roughness = clampd(ctx.visual.optics_surface_roughness, 0.0, 1.0);
    double total = sample_color_wavelength(env_color, wavelength_t);

    for (const auto& card : env.cards) {
        double alignment = dmax((double)dir.dot(card.dir), 0.0);
        double power = lerpd(card.sharp_power, card.broad_power, roughness);
        double strength = lerpd(card.sharp_strength, card.broad_strength, roughness);
        total += sample_color_wavelength(card.color, wavelength_t)
            * std::pow(alignment, power) * strength * ctx.visual.optics_light_energy;
    }

    double blocker_alignment = dmax((double)dir.dot(env.blocker_dir), 0.0);
    total -= std::pow(blocker_alignment, env.blocker_power) * env.blocker_strength;

    return clampd(total, 0.0, 18.0);
}

// ===========================================================================
// _resolve_environment_profile (static helper)
// ===========================================================================

static LightCard make_light_card(
    Vector3 local_dir,
    Color color,
    double sharp_power,
    double broad_power,
    double sharp_strength,
    double broad_strength)
{
    LightCard card;
    card.dir = local_dir.normalized(); // will be overwritten during rotation, but store local_dir for now
    card.color = color;
    card.sharp_power = sharp_power;
    card.broad_power = broad_power;
    card.sharp_strength = sharp_strength;
    card.broad_strength = broad_strength;
    return card;
}

struct EnvironmentProfile {
    Color sky_low;
    Color sky_top;
    Color horizon;
    Color ground_dark;
    Color ground_lift;
    std::vector<LightCard> cards; // cards still have local dirs
    Vector3 blocker_local_dir;
    double blocker_power;
    double blocker_strength;
};

static EnvironmentProfile resolve_environment_profile(const VisualProps& v) {
    EnvironmentProfile p;

    switch (v.optics_environment_preset) {
        case OPTICS_ENVIRONMENT_GAMEPLAY_STUDIO:
            p.sky_low = Color(0.08f, 0.09f, 0.12f, 1.0f);
            p.sky_top = Color(0.20f, 0.23f, 0.30f, 1.0f);
            p.horizon = Color(0.46f, 0.40f, 0.34f, 1.0f);
            p.ground_dark = Color(0.016f, 0.014f, 0.014f, 1.0f);
            p.ground_lift = Color(0.06f, 0.052f, 0.048f, 1.0f);
            p.cards = {
                make_light_card(Vector3(0.02, 0.30, 0.95), Color(1.0f, 0.99f, 0.97f, 1.0f), 820.0, 12.0, 2.4, 2.0),
                make_light_card(Vector3(0.72, 0.12, 0.68), Color(1.0f, 0.94f, 0.88f, 1.0f), 92.0, 8.0, 0.34, 0.36),
                make_light_card(Vector3(-0.72, 0.14, 0.64), Color(0.92f, 0.97f, 1.0f, 1.0f), 92.0, 8.0, 0.32, 0.34),
                make_light_card(Vector3(-0.06, -0.54, 0.84), Color(1.0f, 0.92f, 0.82f, 1.0f), 24.0, 6.0, 0.10, 0.14),
            };
            p.blocker_local_dir = Vector3(-0.10, -0.18, 0.98);
            p.blocker_power = 8.0;
            p.blocker_strength = 0.10;
            break;

        case OPTICS_ENVIRONMENT_DARK_STUDIO:
            p.sky_low = Color(0.018f, 0.020f, 0.028f, 1.0f);
            p.sky_top = Color(0.055f, 0.060f, 0.085f, 1.0f);
            p.horizon = Color(0.16f, 0.12f, 0.09f, 1.0f);
            p.ground_dark = Color(0.003f, 0.003f, 0.004f, 1.0f);
            p.ground_lift = Color(0.020f, 0.016f, 0.012f, 1.0f);
            p.cards = {
                make_light_card(Vector3(0.02, 0.44, 0.90), Color(1.0f, 0.99f, 0.97f, 1.0f), 1150.0, 14.0, 4.8, 2.8),
                make_light_card(Vector3(0.72, 0.12, 0.68), Color(0.96f, 0.94f, 1.0f, 1.0f), 120.0, 8.0, 0.56, 0.44),
                make_light_card(Vector3(-0.78, 0.18, 0.56), Color(1.0f, 0.985f, 0.95f, 1.0f), 220.0, 10.0, 0.62, 0.48),
                make_light_card(Vector3(-0.10, -0.70, 0.70), Color(1.0f, 0.90f, 0.80f, 1.0f), 42.0, 6.0, 0.28, 0.22),
            };
            p.blocker_local_dir = Vector3(-0.26, -0.30, 0.92);
            p.blocker_power = 10.0;
            p.blocker_strength = 0.30;
            break;

        case OPTICS_ENVIRONMENT_GEM_BOOTH:
            p.sky_low = Color(0.06f, 0.07f, 0.09f, 1.0f);
            p.sky_top = Color(0.16f, 0.18f, 0.22f, 1.0f);
            p.horizon = Color(0.36f, 0.30f, 0.24f, 1.0f);
            p.ground_dark = Color(0.012f, 0.010f, 0.010f, 1.0f);
            p.ground_lift = Color(0.05f, 0.04f, 0.03f, 1.0f);
            p.cards = {
                make_light_card(Vector3(0.00, 0.36, 0.94), Color(1.0f, 0.985f, 0.96f, 1.0f), 900.0, 14.0, 3.8, 2.4),
                make_light_card(Vector3(0.86, 0.08, 0.50), Color(1.0f, 0.96f, 0.92f, 1.0f), 160.0, 8.0, 0.48, 0.38),
                make_light_card(Vector3(-0.72, 0.10, 0.62), Color(0.92f, 0.96f, 1.0f, 1.0f), 120.0, 8.0, 0.44, 0.36),
            };
            p.blocker_local_dir = Vector3(-0.14, -0.24, 0.96);
            p.blocker_power = 9.0;
            p.blocker_strength = 0.16;
            break;

        default: // OPTICS_ENVIRONMENT_NEUTRAL
            p.sky_low = Color(0.12f, 0.15f, 0.20f, 1.0f);
            p.sky_top = Color(0.28f, 0.33f, 0.42f, 1.0f);
            p.horizon = Color(0.62f, 0.48f, 0.32f, 1.0f);
            p.ground_dark = Color(0.015f, 0.012f, 0.010f, 1.0f);
            p.ground_lift = Color(0.08f, 0.06f, 0.04f, 1.0f);
            p.cards = {
                make_light_card(Vector3(0.00, 0.24, 0.97), Color(1.0f, 0.96f, 0.88f, 1.0f), 900.0, 90.0, 4.6, 2.0),
                make_light_card(Vector3(0.56, 0.18, 0.80), Color(0.95f, 0.92f, 0.98f, 1.0f), 48.0, 14.0, 0.42, 0.26),
                make_light_card(Vector3(-0.74, 0.14, 0.62), Color(1.0f, 0.99f, 0.97f, 1.0f), 64.0, 18.0, 0.34, 0.20),
            };
            p.blocker_local_dir = Vector3(-0.18, -0.30, 0.94);
            p.blocker_power = 10.0;
            p.blocker_strength = 0.18;
            break;
    }

    return p;
}

// ===========================================================================
// build_environment_setup
// ===========================================================================

EnvironmentSetup GemTraceKernel::build_environment_setup(
    Vector3 light_dir,
    Vector2 lighting_uv,
    const VisualProps& v) const
{
    EnvironmentProfile profile = resolve_environment_profile(v);

    Vector3 side_axis = light_dir.cross(Vector3(0, 1, 0));
    if (side_axis.length_squared() <= 0.0001) {
        side_axis = light_dir.cross(Vector3(1, 0, 0));
    }
    side_axis = side_axis.normalized();

    Vector3 key_dir = (
        light_dir
        + side_axis * lighting_uv.x * 0.65
        + Vector3(0, 1, 0) * (-lighting_uv.y) * 0.30
    ).normalized();
    Vector3 up_axis = side_axis.cross(key_dir).normalized();

    double env_rotation = Math::deg_to_rad(v.optics_environment_rotation_degrees);
    double rot_cos = std::cos(env_rotation);
    double rot_sin = std::sin(env_rotation);
    Vector3 rotated_right = side_axis * rot_cos + up_axis * rot_sin;
    Vector3 rotated_up = up_axis * rot_cos - side_axis * rot_sin;

    EnvironmentSetup env;
    env.sky_low = profile.sky_low;
    env.sky_top = profile.sky_top;
    env.horizon = profile.horizon;
    env.ground_dark = profile.ground_dark;
    env.ground_lift = profile.ground_lift;

    for (const auto& src_card : profile.cards) {
        LightCard card;
        // src_card.dir holds local_dir (already normalized from make_light_card)
        Vector3 local_dir = src_card.dir;
        card.dir = (
            rotated_right * local_dir.x
            + rotated_up * local_dir.y
            + key_dir * local_dir.z
        ).normalized();
        card.color = src_card.color;
        card.sharp_power = src_card.sharp_power;
        card.broad_power = src_card.broad_power;
        card.sharp_strength = src_card.sharp_strength;
        card.broad_strength = src_card.broad_strength;
        env.cards.push_back(card);
    }

    Vector3 blocker_local = profile.blocker_local_dir;
    env.blocker_dir = (
        rotated_right * blocker_local.x
        + rotated_up * blocker_local.y
        + key_dir * blocker_local.z
    ).normalized();
    env.blocker_power = profile.blocker_power;
    env.blocker_strength = profile.blocker_strength * (1.0 + lighting_uv.length() * 0.08);

    return env;
}

// ===========================================================================
// build_surface_setup
// ===========================================================================

SurfaceSetup GemTraceKernel::build_surface_setup(
    const VisualProps& v,
    const EnvironmentSetup& env,
    Vector3 light_dir,
    Vector2 lighting_uv,
    StringName variant_type) const
{
    SurfaceSetup s;
    s.variant_type = variant_type;
    s.lighting_uv = lighting_uv;

    Color scatter_color = v.optics_scattering_color;
    if (scatter_color.a <= 0.001) {
        scatter_color = (v.translucency_color.a > 0.001) ? v.translucency_color : v.base_color;
    }
    s.scatter_color = scatter_color;

    Color highlight_tint = resolve_highlight_tint(v);
    s.highlight_tint = highlight_tint;
    s.specular_color = highlight_tint;

    s.rim_tint = (v.rim_color.a > 0.001) ? v.rim_color : Color(1, 1, 1, 1);
    s.optics_ior_mid = wavelength_ior(v, 0.5);
    s.default_light_dir = light_dir;

    return s;
}

// ===========================================================================
// resolve_body_color
// ===========================================================================

Color GemTraceKernel::resolve_body_color(
    Vector3 position,
    Vector3 normal,
    double radius,
    const VisualProps& v) const
{
    Color body_color = v.base_color;

    if (v.gradient_strength > 0.001 && v.gradient_color.a > 0.001 && radius > 0.0001) {
        Vector2 normalized_position(position.x / radius, position.y / radius);
        double gradient_mix = 0.0;

        switch (v.gradient_mode) {
            case GRADIENT_MODE_RADIAL:
                gradient_mix = clampd(normalized_position.length(), 0.0, 1.0);
                break;
            case GRADIENT_MODE_RADIAL_INVERSE:
                gradient_mix = 1.0 - clampd(normalized_position.length(), 0.0, 1.0);
                break;
            default: { // LINEAR
                double gradient_angle = Math::deg_to_rad(v.gradient_angle_degrees);
                Vector2 gradient_dir = Vector2(std::cos(gradient_angle), -std::sin(gradient_angle)).normalized();
                gradient_mix = clampd(normalized_position.dot(gradient_dir) * 0.5 + 0.5, 0.0, 1.0);
                break;
            }
        }
        body_color = color_lerp(body_color, v.gradient_color, gradient_mix * v.gradient_strength);
    }

    if (v.phenomenon_strength > 0.001 && v.phenomenon_color.a > 0.001) {
        double phenomenon_angle = Math::deg_to_rad(v.phenomenon_angle_degrees);
        Vector2 phenomenon_dir = Vector2(std::cos(phenomenon_angle), std::sin(phenomenon_angle)).normalized();
        Vector2 facet_dir(normal.x, -normal.y);
        if (facet_dir.length_squared() > 1e-8) {
            double phenomenon_mix = clampd(facet_dir.normalized().dot(phenomenon_dir) * 0.5 + 0.5, 0.0, 1.0);
            phenomenon_mix = std::pow(phenomenon_mix, dmax(v.phenomenon_sharpness, 0.01));
            body_color = color_lerp(body_color, v.phenomenon_color, phenomenon_mix * v.phenomenon_strength);
        }
    }

    if (radius > 0.0001 && v.volume_pattern_mix > 0.001 && v.volume_pattern_type != MATERIAL_PATTERN_NONE) {
        Vector3 obj_pos = position / radius;
        VolumeMaterialSample vol = material::sample_volume_material(v, obj_pos);
        double volume_mix = v.volume_pattern_mix * (
            (v.material_mode == MATERIAL_MODE_PATTERNED_TRANSLUCENT) ? 0.32 : 0.16
        );
        body_color = color_lerp(body_color, vol.color, clampd(volume_mix, 0.0, 1.0));
    }

    return body_color;
}

// ===========================================================================
// resolve_highlight_tint
// ===========================================================================

Color GemTraceKernel::resolve_highlight_tint(const VisualProps& v, Color body) const {
    Color tint_source = body;
    if (tint_source.a <= 0.001) {
        tint_source = v.optics_absorption_color;
    }
    if (tint_source.a <= 0.001) {
        tint_source = (v.depth_tint.a > 0.001) ? v.depth_tint : v.base_color;
    }
    Vector3 tint_rgb(
        dmax((double)tint_source.r, 0.0001),
        dmax((double)tint_source.g, 0.0001),
        dmax((double)tint_source.b, 0.0001));
    double max_channel = dmax(tint_rgb.x, dmax(tint_rgb.y, tint_rgb.z));
    if (max_channel > 0.0001) {
        tint_rgb /= max_channel;
    }
    Vector3 pastel_tint(
        lerpd(0.42, 0.96, tint_rgb.x),
        lerpd(0.42, 0.96, tint_rgb.y),
        lerpd(0.42, 0.96, tint_rgb.z));
    double tint_strength = clampd(
        0.08
        + dmin(v.optics_absorption_strength, 3.0) * 0.090
        + dmax(v.saturation_boost, 0.0) * 0.22
        + v.contrast * 0.06,
        0.08, 0.56);
    if (v.optics_absorption_strength <= 0.35 && v.hue_dispersion > 0.05) {
        tint_strength *= 0.45;
    } else if (v.optics_absorption_strength <= 0.6 && dmax(v.saturation_boost, 0.0) <= 0.05) {
        tint_strength *= 0.65;
    }
    Vector3 resolved = Vector3(1, 1, 1).lerp(pastel_tint, tint_strength);
    return Color(resolved.x, resolved.y, resolved.z, 1.0);
}

// ===========================================================================
// zone_light_multiplier
// ===========================================================================

double GemTraceKernel::zone_light_multiplier(StringName zone, const VisualProps& v) {
    double contrast = clampd(v.brilliance_contrast, 0.0, 1.0);
    if (zone == StringName("table")) {
        return 1.0 + contrast * 0.28;
    }
    if (zone == StringName("star")) {
        return 1.0 + contrast * 0.16;
    }
    if (zone == StringName("girdle")) {
        return 1.0 - contrast * 0.18;
    }
    if (zone == StringName("pavilion") || zone == StringName("culet")) {
        return 1.0 - v.extinction * 0.42;
    }
    return 1.0;
}

// ===========================================================================
// resolve_zone_surface_scales
// ===========================================================================

ZoneSurfaceScales GemTraceKernel::resolve_zone_surface_scales(StringName zone) {
    ZoneSurfaceScales s;
    if (zone == StringName("table")) {
        s.front = 0.56; s.back = 0.90; s.spec = 0.62;
        s.body = 0.92; s.caustic = 1.06; s.interface_ = 0.48;
    } else if (zone == StringName("rose_center")) {
        s.front = 0.54; s.back = 0.92; s.spec = 0.60;
        s.body = 0.94; s.caustic = 1.08; s.interface_ = 0.50;
    } else if (zone == StringName("rose")) {
        s.front = 0.72; s.back = 1.0; s.spec = 0.76;
        s.body = 1.08; s.caustic = 1.04; s.interface_ = 0.72;
    } else if (zone == StringName("girdle")) {
        s.front = 0.78; s.back = 1.0; s.spec = 0.80;
        s.body = 1.06; s.caustic = 1.02; s.interface_ = 0.80;
    } else if (zone == StringName("step")) {
        s.front = 0.80; s.back = 1.0; s.spec = 0.82;
        s.body = 1.06; s.caustic = 1.03; s.interface_ = 0.78;
    } else if (zone == StringName("star")) {
        s.front = 0.68; s.back = 1.0; s.spec = 0.72;
        s.body = 0.96; s.caustic = 1.02; s.interface_ = 0.70;
    } else if (zone == StringName("bezel")) {
        s.front = 0.76; s.back = 1.0; s.spec = 0.78;
        s.body = 0.98; s.caustic = 1.02; s.interface_ = 0.76;
    } else {
        // Default
        s.front = 1.0; s.back = 1.0; s.spec = 1.0;
        s.body = 1.0; s.caustic = 1.0; s.interface_ = 1.0;
    }
    return s;
}

// ===========================================================================
// compute_surface_lighting
// ===========================================================================

Vector3 GemTraceKernel::compute_surface_lighting(
    const TraceContext& ctx,
    Vector3 position,
    Vector3 normal,
    StringName zone) const
{
    const VisualProps& v = ctx.visual;
    const SurfaceSetup& ss = ctx.surface;

    StringName variant_type = ss.variant_type;
    Vector2 lighting_uv = ss.lighting_uv;
    Vector3 light_dir = ctx.light_dir;
    Vector3 view_dir = ctx.view_dir;
    double radius = ctx.radius;

    Color body_color = resolve_body_color(position, normal, radius, v);
    Vector3 object_position = position / dmax(radius, 0.0001);
    Vector2 uv(
        clampd(object_position.x * 0.5 + 0.5, 0.0, 1.0),
        clampd(object_position.y * 0.5 + 0.5, 0.0, 1.0));

    // Surface material application
    SurfaceMaterialSample surface_material;
    surface_material.color = body_color;
    surface_material.roughness_mult = 1.0;
    surface_material.specular_mult = 1.0;

    if (ctx.flags.has_surface_material) {
        surface_material = material::apply_surface_material(
            v, body_color, uv, object_position, normal,
            ctx.texture_image.is_valid() ? ctx.texture_image.ptr() : nullptr);
    }
    body_color = surface_material.color;

    Color reactive_color(0, 0, 0, 0);
    Color scatter_color = ss.scatter_color;

    Color highlight_tint = resolve_highlight_tint(v,
        (body_color.a > 0.001) ? body_color : Color(0, 0, 0, 0));

    // Absorption tint factor for specular bias toward body color
    double absorption_tint_factor = clampd(v.optics_absorption_strength * 0.25, 0.0, 0.72);
    Color specular_color = color_lerp(highlight_tint, body_color, absorption_tint_factor);

    Color rim_tint = ss.rim_tint;
    Color face_color = color_lerp(body_color, specular_color, 0.02 + v.specular_intensity * 0.02);
    Color caustic_base = color_lerp(body_color, specular_color,
        0.12 + v.hue_dispersion * 0.14 + v.sparkle_intensity * 0.03);

    double roughness = clampd(
        v.optics_surface_roughness * surface_material.roughness_mult,
        0.0, 1.0);
    double specular_mult = surface_material.specular_mult;
    double optics_ior = ss.optics_ior_mid;

    Vector3 effective_light_dir = light_dir;
    if (variant_type == StringName("lighting") && radius > 0.0001) {
        Vector3 key_origin(
            (light_dir.x + lighting_uv.x * 0.95) * radius * 2.8,
            (light_dir.y - lighting_uv.y * 0.70) * radius * 2.4,
            dmax((double)light_dir.z, 0.22) * radius * 3.4);
        effective_light_dir = (key_origin - position).normalized();
    }

    if (ctx.flags.has_reactive) {
        reactive_color = material::sample_reactive_color(
            v, object_position, normal, effective_light_dir, view_dir);
    }

    double front_alignment = dmax((double)normal.dot(effective_light_dir), 0.0);
    double back_alignment = dmax(-(double)normal.dot(effective_light_dir), 0.0);
    double front_power = lerpd(18.0, 4.0, roughness);
    double front_strength = std::pow(front_alignment, front_power)
        * v.optics_light_energy * (0.08 + v.contrast * 0.18);
    double scatter_strength = dmax(v.optics_scattering_strength, v.translucency * 0.55);
    double back_strength = std::pow(back_alignment, 3.2)
        * v.optics_light_energy * scatter_strength * 0.08;

    // Blinn-Phong specular
    Vector3 half_vec = (effective_light_dir + view_dir).normalized();
    double spec_alignment = dmax((double)normal.dot(half_vec), 0.0);
    double spec_power = lerpd(120.0, 16.0, roughness);
    double spec_strength = std::pow(spec_alignment, spec_power)
        * v.optics_light_energy * (0.12 + v.specular_intensity * 0.52) * specular_mult;

    // Secondary specular
    Vector3 secondary_light_dir = Basis(Vector3(0, 1, 0), Math::deg_to_rad(v.secondary_light_angle))
        .xform(effective_light_dir).normalized();
    Vector3 secondary_half = (secondary_light_dir + view_dir).normalized();
    double secondary_alignment = dmax((double)normal.dot(secondary_half), 0.0);
    double secondary_strength = std::pow(secondary_alignment, lerpd(96.0, 18.0, roughness))
        * v.secondary_specular * v.optics_light_energy * 0.16 * specular_mult;

    // Environment card contributions
    double card_glare_strength = 0.0;
    double card_return_strength = 0.0;
    double card_fill_strength = 0.0;

    for (const auto& card : ctx.environment.cards) {
        double card_front = dmax((double)normal.dot(card.dir), 0.0);
        if (card_front <= 0.0) continue;

        Vector3 card_half = (card.dir + view_dir).normalized();
        double card_spec_alignment = dmax((double)normal.dot(card_half), 0.0);
        double card_power = lerpd(card.sharp_power, dmax(card.broad_power, 8.0), roughness);
        double card_energy = lerpd(card.sharp_strength, card.broad_strength, roughness);

        card_glare_strength += std::pow(card_spec_alignment, card_power) * card_energy * 0.16;
        card_fill_strength += std::pow(card_front, lerpd(10.0, 3.5, roughness)) * card_energy * 0.05;

        Vector3 refracted_card = refract_ray(-card.dir, normal, AIR_IOR, optics_ior);
        if (refracted_card.length_squared() < 1e-12) continue;
        double return_alignment = dmax((double)(-refracted_card).dot(view_dir), 0.0);
        double fresnel_in = fresnel_dielectric(-card.dir, normal, AIR_IOR, optics_ior);
        card_return_strength += std::pow(return_alignment, lerpd(42.0, 10.0, roughness))
            * card_energy * (1.0 - fresnel_in) * (0.24 + v.extinction * 0.10);
    }

    // Lateral mask and caustic band
    Vector2 planar_light(effective_light_dir.x, effective_light_dir.y);
    Vector2 normalized_position(object_position.x, object_position.y);
    double lateral_mask = 0.5;
    double caustic_band = 0.0;

    if (planar_light.length_squared() > 0.0001) {
        Vector2 planar_dir = planar_light.normalized();
        double side_alignment = clampd(normalized_position.dot(planar_dir), -1.0, 1.0);
        lateral_mask = clampd(side_alignment * 0.5 + 0.5, 0.0, 1.0);
        caustic_band = std::exp(-std::pow((side_alignment - 0.24) / 0.46, 2.0))
            * dmax(front_alignment, 0.0);
    }

    if (variant_type == StringName("lighting")) {
        front_strength *= lerpd(0.80, 1.16, lateral_mask);
        spec_strength *= lerpd(0.50, 1.45, lateral_mask);
        back_strength *= lerpd(0.28, 0.52, 1.0 - lateral_mask);
    }

    double zone_mult = zone_light_multiplier(zone, v);
    ZoneSurfaceScales zs = resolve_zone_surface_scales(zone);

    front_strength *= zone_mult * zs.front;
    back_strength *= zs.back;
    spec_strength += card_glare_strength * lerpd(zone_mult, 1.0 + v.sparkle_intensity * 0.10, 0.4);
    spec_strength *= lerpd(zone_mult, 1.0 + v.sparkle_intensity * 0.14, 0.35);
    spec_strength *= zs.spec;
    secondary_strength *= lerpd(zone_mult, 1.0, 0.35) * zs.spec;

    Color caustic_color = color_lerp(body_color, caustic_base, 0.42 + v.hue_dispersion * 0.20);

    double body_strength = (
        0.006
        + scatter_strength * 0.10
        + roughness * 0.03
        + v.translucency * 0.02
        + card_fill_strength
    ) * v.optics_light_energy * lerpd(0.82, 1.02, front_alignment);

    if (variant_type == StringName("lighting")) {
        body_strength *= lerpd(0.84, 1.08, lateral_mask);
    }
    body_strength *= lerpd(0.82, 1.04, zone_mult - 1.0 + 0.5) * zs.body;

    double caustic_strength = (
        card_return_strength
        + caustic_band * (0.018 + v.sparkle_intensity * 0.012)
    ) * v.optics_light_energy * zs.caustic;

    double sparkle_strength = dmax(
        std::pow(spec_alignment, lerpd(260.0, 48.0, roughness)) - v.sparkle_threshold, 0.0)
        * v.sparkle_intensity * v.optics_light_energy * 2.4 * specular_mult;

    double rim_alignment = dmax(1.0 - dmax((double)normal.dot(view_dir), 0.0), 0.0);
    double rim_strength = std::pow(rim_alignment, lerpd(5.8, 2.2, v.rim_power / 5.0))
        * v.rim_intensity * v.optics_light_energy * 0.26;

    double facet_glare_strength = 0.0;

    switch (v.material_mode) {
        case MATERIAL_MODE_PATTERNED_OPAQUE:
            facet_glare_strength = (
                std::pow(spec_alignment, lerpd(92.0, 18.0, roughness)) * 0.46
                + card_glare_strength * 0.72
                + std::pow(front_alignment, lerpd(12.0, 4.2, roughness)) * 0.08
            ) * v.optics_light_energy * (0.16 + v.specular_intensity * 0.32) * specular_mult;
            face_color = color_lerp(body_color, specular_color, 0.08);
            front_strength *= 0.18;
            back_strength = 0.0;
            spec_strength *= 0.34;
            secondary_strength *= 0.24;
            sparkle_strength = 0.0;
            caustic_strength = 0.0;
            rim_strength *= 0.44;
            body_strength = 0.12 + front_alignment * 0.11 + zone_mult * 0.02;
            break;
        case MATERIAL_MODE_PATTERNED_TRANSLUCENT:
            front_strength *= 0.72;
            spec_strength *= 0.44;
            secondary_strength *= 0.34;
            sparkle_strength *= 0.18;
            caustic_strength *= 0.2;
            body_strength *= 1.18;
            break;
        default:
            break;
    }

    double surface_absorption_scale = 1.0 / (1.0 + v.optics_absorption_strength * 0.42);

    double combined_spec = spec_strength + secondary_strength + sparkle_strength + facet_glare_strength;
    return Vector3(
        face_color.r * front_strength + scatter_color.r * back_strength
            + specular_color.r * combined_spec + rim_tint.r * rim_strength
            + caustic_color.r * caustic_strength + body_color.r * body_strength + reactive_color.r,
        face_color.g * front_strength + scatter_color.g * back_strength
            + specular_color.g * combined_spec + rim_tint.g * rim_strength
            + caustic_color.g * caustic_strength + body_color.g * body_strength + reactive_color.g,
        face_color.b * front_strength + scatter_color.b * back_strength
            + specular_color.b * combined_spec + rim_tint.b * rim_strength
            + caustic_color.b * caustic_strength + body_color.b * body_strength + reactive_color.b
    ) * surface_absorption_scale;
}

// ===========================================================================
// compute_interface_highlight
// ===========================================================================

double GemTraceKernel::compute_interface_highlight(
    const TraceContext& ctx,
    StringName zone,
    Vector3 normal,
    Vector3 view_dir,
    double wavelength_t) const
{
    const VisualProps& v = ctx.visual;
    double roughness = clampd(v.optics_surface_roughness, 0.0, 1.0);
    Color highlight_tint = ctx.surface.highlight_tint;

    // If no environment cards, use a default card from the light direction
    const std::vector<LightCard>& cards = ctx.environment.cards;
    bool use_default = cards.empty();

    double total = 0.0;

    if (use_default) {
        Vector3 card_dir = ctx.light_dir;
        Vector3 card_half = (card_dir + view_dir).normalized();
        double spec_alignment = dmax((double)normal.dot(card_half), 0.0);
        if (spec_alignment > 0.0) {
            double core_power = lerpd(dmax(420.0, 240.0), 48.0, roughness);
            double halo_power = lerpd(dmax(46.0, 24.0), 10.0, roughness);
            double card_energy = lerpd(1.0, 0.4, roughness);
            double core = std::pow(spec_alignment, core_power)
                * v.optics_light_energy * card_energy
                * (0.020 + v.sparkle_intensity * 0.030 + v.specular_intensity * 0.020);
            double halo = std::pow(spec_alignment, halo_power)
                * v.optics_light_energy * card_energy
                * (0.006 + v.specular_intensity * 0.010);
            total += core + halo;
        }
    } else {
        for (const auto& card : cards) {
            Vector3 card_half = (card.dir + view_dir).normalized();
            double spec_alignment = dmax((double)normal.dot(card_half), 0.0);
            if (spec_alignment <= 0.0) continue;

            double core_power = lerpd(dmax(card.sharp_power, 240.0), 48.0, roughness);
            double halo_power = lerpd(dmax(card.broad_power, 24.0), 10.0, roughness);
            double card_energy = lerpd(card.sharp_strength, card.broad_strength, roughness);

            double core = std::pow(spec_alignment, core_power)
                * v.optics_light_energy * card_energy
                * (0.020 + v.sparkle_intensity * 0.030 + v.specular_intensity * 0.020);
            double halo = std::pow(spec_alignment, halo_power)
                * v.optics_light_energy * card_energy
                * (0.006 + v.specular_intensity * 0.010);
            total += core + halo;
        }
    }

    ZoneSurfaceScales zs = resolve_zone_surface_scales(zone);
    return sample_color_wavelength(highlight_tint, wavelength_t) * total * zs.interface_;
}

// ===========================================================================
// compute_segment_attenuation (Beer-Lambert)
// ===========================================================================

double GemTraceKernel::compute_segment_attenuation(
    const VisualProps& v,
    double wavelength_t,
    double distance,
    const VolumeMaterialSample* medium) const
{
    Color tint = (medium != nullptr) ? medium->color : v.optics_absorption_color;
    if (tint.a <= 0.001) {
        tint = (v.depth_tint.a > 0.001) ? v.depth_tint : v.base_color;
    }
    double channel_tint = sample_color_wavelength(tint, wavelength_t);
    double absorption_mult = (medium != nullptr) ? medium->absorption_mult : 1.0;
    double coeff = dmax(1.0 - channel_tint, 0.0) * dmax(
        v.optics_absorption_strength * absorption_mult, 0.0);
    return std::exp(-coeff * dmax(distance, 0.0));
}

// ===========================================================================
// compute_segment_scattering
// ===========================================================================

double GemTraceKernel::compute_segment_scattering(
    const VisualProps& v,
    double wavelength_t,
    double distance,
    const VolumeMaterialSample* medium) const
{
    double scattering_mult = (medium != nullptr) ? medium->scattering_mult : 1.0;
    double strength = dmax(
        v.optics_scattering_strength * scattering_mult,
        v.translucency * 0.6);
    if (strength <= 0.0001) return 0.0;

    Color scatter_color = (medium != nullptr) ? medium->color : v.optics_scattering_color;
    if (scatter_color.a <= 0.001) {
        scatter_color = v.translucency_color;
    }
    double raw_scatter = sample_color_wavelength(scatter_color, wavelength_t)
        * (1.0 - std::exp(-strength * dmax(distance, 0.0))) * 0.42;

    // Attenuate scattered light by absorption along exit path
    Color tint = (medium != nullptr) ? medium->color : v.optics_absorption_color;
    if (tint.a <= 0.001) {
        tint = (v.depth_tint.a > 0.001) ? v.depth_tint : v.base_color;
    }
    double absorption_mult = (medium != nullptr) ? medium->absorption_mult : 1.0;
    double abs_coeff = dmax(1.0 - sample_color_wavelength(tint, wavelength_t), 0.0)
        * dmax(v.optics_absorption_strength * absorption_mult, 0.0);
    double exit_attenuation = std::exp(-abs_coeff * dmax(distance * 0.5, 0.0));

    return raw_scatter * exit_attenuation;
}

// ===========================================================================
// sample_segment_volume (3-point volume sampling)
// ===========================================================================

VolumeMaterialSample GemTraceKernel::sample_segment_volume(
    const VisualProps& v,
    Vector3 start,
    Vector3 end,
    double radius) const
{
    VolumeMaterialSample result;
    if (radius <= 0.0001) return result;
    if (v.volume_pattern_mix <= 0.0001 || v.volume_pattern_type == MATERIAL_PATTERN_NONE) {
        return result;
    }

    static const double sample_positions[3] = {0.22, 0.5, 0.78};
    double sum_r = 0.0, sum_g = 0.0, sum_b = 0.0, sum_a = 0.0;
    double sum_absorption = 0.0, sum_scattering = 0.0;

    for (int i = 0; i < 3; i++) {
        double t = sample_positions[i];
        Vector3 object_position = start.lerp(end, t) / radius;
        VolumeMaterialSample sample = material::sample_volume_material(v, object_position);
        sum_r += sample.color.r;
        sum_g += sample.color.g;
        sum_b += sample.color.b;
        sum_a += sample.color.a;
        sum_absorption += sample.absorption_mult;
        sum_scattering += sample.scattering_mult;
    }

    double count = 3.0;
    result.color = Color(sum_r / count, sum_g / count, sum_b / count, sum_a / count);
    result.absorption_mult = sum_absorption / count;
    result.scattering_mult = sum_scattering / count;
    return result;
}

// ===========================================================================
// apply_aces_channel
// ===========================================================================

double GemTraceKernel::apply_aces_channel(double value) {
    double v = dmax(value, 0.0);
    return clampd(
        (v * (ACES_A * v + ACES_B)) / (v * (ACES_C * v + ACES_D) + ACES_E),
        0.0, 1.0);
}

// ===========================================================================
// compress_luma_range
// ===========================================================================

Vector3 GemTraceKernel::compress_luma_range(Vector3 color, double amount) {
    if (amount <= 0.0001) return color;
    double luma = color.dot(Vector3(0.2126, 0.7152, 0.0722));
    double pivot = 0.46;
    double compressed_luma = pivot + (luma - pivot) * (1.0 - amount * 0.78);
    return set_luma(color, clampd(compressed_luma, 0.0, 1.0));
}

// ===========================================================================
// soft_highlight_rolloff
// ===========================================================================

Vector3 GemTraceKernel::soft_highlight_rolloff(Vector3 color, double amount) {
    if (amount <= 0.0001) return color;
    Vector3 rolled;
    for (int i = 0; i < 3; i++) {
        double channel = (i == 0) ? color.x : ((i == 1) ? color.y : color.z);
        double shoulder = smoothstepd(0.58, 1.0, channel);
        double result = clampd(channel - shoulder * amount * (channel - 0.58), 0.0, 1.0);
        if (i == 0) rolled.x = result;
        else if (i == 1) rolled.y = result;
        else rolled.z = result;
    }
    return rolled;
}

// ===========================================================================
// adjust_saturation
// ===========================================================================

Vector3 GemTraceKernel::adjust_saturation(Vector3 color, double amount) {
    double luma = color.dot(Vector3(0.2126, 0.7152, 0.0722));
    Vector3 gray(luma, luma, luma);
    return gray.lerp(color, 1.0 + amount);
}

// ===========================================================================
// set_luma
// ===========================================================================

Vector3 GemTraceKernel::set_luma(Vector3 color, double target_luma) {
    double current_luma = color.dot(Vector3(0.2126, 0.7152, 0.0722));
    if (current_luma <= 0.0001) {
        return Vector3(target_luma, target_luma, target_luma);
    }
    double ratio = target_luma / current_luma;
    return Vector3(
        clampd(color.x * ratio, 0.0, 1.0),
        clampd(color.y * ratio, 0.0, 1.0),
        clampd(color.z * ratio, 0.0, 1.0));
}

// ===========================================================================
// apply_output_grade
// ===========================================================================

Vector3 GemTraceKernel::apply_output_grade(Vector3 color, const VisualProps& v) const {
    double exposure = (
        0.72
        + v.optics_light_energy * 0.08
        + v.specular_intensity * 0.06
        + v.sparkle_intensity * 0.008
    );
    switch (v.material_mode) {
        case MATERIAL_MODE_PATTERNED_OPAQUE:
            exposure *= 0.60;
            break;
        case MATERIAL_MODE_PATTERNED_TRANSLUCENT:
            exposure *= 0.82;
            break;
        default:
            break;
    }

    Vector3 graded = color * exposure;
    graded = Vector3(
        apply_aces_channel(graded.x),
        apply_aces_channel(graded.y),
        apply_aces_channel(graded.z));

    double range_compression = clampd(
        0.04
        + v.specular_intensity * 0.03
        + v.contrast * 0.05
        + dmin(v.sparkle_intensity, 1.2) * 0.01,
        0.04, 0.14);
    graded = compress_luma_range(graded, range_compression);

    double highlight_rolloff = clampd(
        0.08
        + v.specular_intensity * 0.08
        + dmin(v.sparkle_intensity, 1.2) * 0.03,
        0.08, 0.22);
    graded = soft_highlight_rolloff(graded, highlight_rolloff);

    double saturation = clampd(
        v.saturation_boost
        + v.contrast * 0.08
        + v.hue_dispersion * 0.16
        + v.specular_intensity * 0.03
        + dmin(v.optics_absorption_strength, 3.0) * 0.022
        + 0.01,
        -0.2, 0.48);
    graded = adjust_saturation(graded, saturation);

    // Gamma
    Vector3 post_gamma(
        clampd(std::pow(dmax(graded.x, 0.0), 1.0 / 2.2), 0.0, 1.0),
        clampd(std::pow(dmax(graded.y, 0.0), 1.0 / 2.2), 0.0, 1.0),
        clampd(std::pow(dmax(graded.z, 0.0), 1.0 / 2.2), 0.0, 1.0));
    post_gamma = soft_highlight_rolloff(post_gamma, highlight_rolloff * 0.5);

    // Body-color saturation floor
    double body_push_strength = clampd(v.optics_absorption_strength * 0.18, 0.0, 0.55);
    if (body_push_strength > 0.01) {
        Vector3 body_hue(v.base_color.r, v.base_color.g, v.base_color.b);
        double body_hue_len = body_hue.length();
        if (body_hue_len > 0.001) {
            body_hue /= body_hue_len;
            double pg_len = post_gamma.length();
            if (pg_len > 0.001) {
                Vector3 pg_dir = post_gamma / pg_len;
                double hue_distance = clampd((pg_dir - body_hue).length() * 0.7, 0.0, 1.0);
                post_gamma = post_gamma.lerp(body_hue * pg_len, body_push_strength * hue_distance);
            }
        }
    }

    double post_sat = clampd(
        0.01
        + dmin(v.optics_absorption_strength, 2.5) * 0.016
        + dmax(v.saturation_boost, 0.0) * 0.10,
        0.01, 0.08);
    return adjust_saturation(post_gamma, post_sat);
}

// ===========================================================================
// clean_alpha_edges
// ===========================================================================

void GemTraceKernel::clean_alpha_edges(Ref<Image> image) const {
    if (image.is_null()) return;
    int width = image->get_width();
    int height = image->get_height();
    if (width <= 0 || height <= 0) return;

    Ref<Image> source = image->duplicate();

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            Color pixel = source->get_pixel(x, y);
            if (pixel.a <= 0.0001) {
                image->set_pixel(x, y, Color(0, 0, 0, 0));
                continue;
            }
            if (pixel.a >= 0.995) continue;

            Vector3 neighbor_sum(0, 0, 0);
            double neighbor_weight = 0.0;

            for (int oy = -1; oy <= 1; oy++) {
                for (int ox = -1; ox <= 1; ox++) {
                    if (ox == 0 && oy == 0) continue;
                    int nx = x + ox;
                    int ny = y + oy;
                    if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;

                    Color neighbor = source->get_pixel(nx, ny);
                    if (neighbor.a <= pixel.a + 0.05) continue;

                    double w = (double)neighbor.a / (double)(std::abs(ox) + std::abs(oy) + 1);
                    neighbor_sum += Vector3(neighbor.r, neighbor.g, neighbor.b) * w;
                    neighbor_weight += w;
                }
            }

            Vector3 cleaned_rgb(pixel.r, pixel.g, pixel.b);
            if (neighbor_weight > 0.0001) {
                Vector3 neighbor_rgb = neighbor_sum / neighbor_weight;
                double mix_amount = clampd((1.0 - pixel.a) * 0.78, 0.0, 0.92);
                cleaned_rgb = cleaned_rgb.lerp(neighbor_rgb, mix_amount);
            }

            if (pixel.a < 0.03) {
                image->set_pixel(x, y, Color(0, 0, 0, 0));
                continue;
            }
            image->set_pixel(x, y, Color(cleaned_rgb.x, cleaned_rgb.y, cleaned_rgb.z, pixel.a));
        }
    }
}

} // namespace gem
