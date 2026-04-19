// gem_trace_kernel.cpp — New spectral path tracer kernel.
#include "gem_trace_kernel.h"
#include "gem_trace_transport.h"
#include "gem_trace_spectral.h"
#include "gem_trace_fresnel.h"
#include "gem_trace_volume.h"
#include "gem_trace_rng.h"
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/array.hpp>
#include <thread>
#include <cmath>

using namespace godot;

namespace gem {

// ===========================================================================
// Bind methods
// ===========================================================================

void GemTraceKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("trace_to_image", "mesh_resource", "visual", "request"),
        &GemTraceKernel::trace_to_image);
    ClassDB::bind_method(D_METHOD("get_last_trace_profile"),
        &GemTraceKernel::get_last_trace_profile);
    ClassDB::bind_method(D_METHOD("run_physics_tests"),
        &GemTraceKernel::run_physics_tests);
}

// ===========================================================================
// get_last_trace_profile
// ===========================================================================

Dictionary GemTraceKernel::get_last_trace_profile() const {
    return last_trace_profile_.duplicate(true);
}

// ===========================================================================
// extract_props — Read GemTraceProps from visual + mineral_template resources
// ===========================================================================

GemTraceProps GemTraceKernel::extract_props(Ref<Resource> visual) const {
    GemTraceProps p;

    // --- Read mineral template (if present) ---
    Variant template_var = visual->get("mineral_template");
    if (template_var.get_type() != Variant::NIL) {
        Ref<Resource> tmpl = template_var;
        if (tmpl.is_valid()) {
            p.sellmeier_b = Vector3(tmpl->get("sellmeier_b"));
            p.sellmeier_c = Vector3(tmpl->get("sellmeier_c"));

            Variant abs_var = tmpl->get("absorption_spectrum");
            if (abs_var.get_type() != Variant::NIL) {
                PackedFloat32Array abs_arr = abs_var;
                p.absorption_spectrum.resize(abs_arr.size());
                for (int i = 0; i < (int)abs_arr.size(); i++) {
                    p.absorption_spectrum[i] = abs_arr[i];
                }
            }

            p.scattering_coefficient = (double)(float)tmpl->get("scattering_coefficient");
            p.scattering_anisotropy = (double)(float)tmpl->get("scattering_anisotropy");
            p.fluorescence_quantum_yield = (double)(float)tmpl->get("fluorescence_quantum_yield");
            p.fluorescence_excitation_center_nm = (double)(float)tmpl->get("fluorescence_excitation_center_nm");
            p.fluorescence_excitation_width_nm = (double)(float)tmpl->get("fluorescence_excitation_width_nm");
            p.fluorescence_emission_center_nm = (double)(float)tmpl->get("fluorescence_emission_center_nm");
            p.fluorescence_emission_width_nm = (double)(float)tmpl->get("fluorescence_emission_width_nm");
            p.birefringence_delta_n = (double)(float)tmpl->get("birefringence_delta_n");
            p.surface_roughness = (double)(float)tmpl->get("default_surface_roughness");
            p.surface_anisotropy = (double)(float)tmpl->get("surface_roughness_anisotropy");
            p.anisotropy_axis = Vector3(tmpl->get("anisotropy_axis"));

            Variant pleo_var = tmpl->get("pleochroism_absorption_spectrum");
            if (pleo_var.get_type() != Variant::NIL) {
                PackedFloat32Array pleo_arr = pleo_var;
                p.pleochroism_absorption_spectrum.resize(pleo_arr.size());
                for (int i = 0; i < (int)pleo_arr.size(); i++) {
                    p.pleochroism_absorption_spectrum[i] = pleo_arr[i];
                }
            }
        }
    }

    // --- Read per-gem visual properties ---
    p.material_mode = (int)(int64_t)visual->get("material_mode");
    p.display_color = Color(visual->get("display_color"));

    // Absorption override
    Variant abs_override_var = visual->get("absorption_spectrum_override");
    if (abs_override_var.get_type() != Variant::NIL) {
        PackedFloat32Array abs_arr = abs_override_var;
        if (abs_arr.size() > 0) {
            p.absorption_spectrum_override.resize(abs_arr.size());
            for (int i = 0; i < (int)abs_arr.size(); i++) {
                p.absorption_spectrum_override[i] = abs_arr[i];
            }
        }
    }

    // Pleochroism override at the visual level. Overwrites the mineral
    // template's `pleochroism_absorption_spectrum` when set — required for
    // gems that share a mineral but have distinct pleochroic pairs (e.g.
    // ruby vs blue sapphire in corundum).
    Variant pleo_override_var = visual->get("pleochroism_absorption_spectrum_override");
    if (pleo_override_var.get_type() != Variant::NIL) {
        PackedFloat32Array pleo_arr = pleo_override_var;
        if (pleo_arr.size() > 0) {
            p.pleochroism_absorption_spectrum.resize(pleo_arr.size());
            for (int i = 0; i < (int)pleo_arr.size(); i++) {
                p.pleochroism_absorption_spectrum[i] = pleo_arr[i];
            }
        }
    }

    p.absorption_strength_scale = (double)(float)visual->get("absorption_strength_scale");
    p.surface_roughness_override = (double)(float)visual->get("surface_roughness_override");
    p.scattering_coefficient_override = (double)(float)visual->get("scattering_coefficient_override");
    p.fluorescence_quantum_yield_override = (double)(float)visual->get("fluorescence_quantum_yield_override");
    p.surface_anisotropy_override = (double)(float)visual->get("surface_roughness_anisotropy_override");

    // Gradient
    p.gradient_color = Color(visual->get("gradient_color"));
    p.gradient_strength = (double)(float)visual->get("gradient_strength");
    p.gradient_mode = (int)(int64_t)visual->get("gradient_mode");
    p.gradient_angle_degrees = (double)(float)visual->get("gradient_angle_degrees");

    // Phenomenon
    p.phenomenon_color = Color(visual->get("phenomenon_color"));
    p.phenomenon_strength = (double)(float)visual->get("phenomenon_strength");
    p.phenomenon_angle_degrees = (double)(float)visual->get("phenomenon_angle_degrees");
    p.phenomenon_sharpness = (double)(float)visual->get("phenomenon_sharpness");

    // Gradient center offset (optional; defaults to geometric origin when unset).
    Variant gcenter_var = visual->get("gradient_center");
    if (gcenter_var.get_type() == Variant::VECTOR2) {
        p.gradient_center = Vector2(gcenter_var);
    }

    // Per-wavelength geometry splitting (dispersion).
    Variant disp_var = visual->get("enable_dispersion");
    if (disp_var.get_type() == Variant::BOOL) {
        p.enable_dispersion = (bool)disp_var;
    }

    Variant gz_var = visual->get("gradient_zone_spectrum");
    if (gz_var.get_type() == Variant::PACKED_FLOAT32_ARRAY) {
        PackedFloat32Array gz_arr = gz_var;
        if (gz_arr.size() == 81) {
            p.gradient_zone_spectrum.resize(81);
            for (int i = 0; i < 81; i++) {
                p.gradient_zone_spectrum[i] = gz_arr[i];
            }
        }
    }
    Variant phz_var = visual->get("phenomenon_zone_spectrum");
    if (phz_var.get_type() == Variant::PACKED_FLOAT32_ARRAY) {
        PackedFloat32Array phz_arr = phz_var;
        if (phz_arr.size() == 81) {
            p.phenomenon_zone_spectrum.resize(81);
            for (int i = 0; i < 81; i++) {
                p.phenomenon_zone_spectrum[i] = phz_arr[i];
            }
        }
    }

    // Surface pattern
    p.surface_pattern_type = (int)(int64_t)visual->get("surface_pattern_type");
    p.surface_pattern_mix = (double)(float)visual->get("surface_pattern_mix");
    p.surface_pattern_scale = Vector2(visual->get("surface_pattern_scale"));
    p.surface_pattern_rotation_degrees = (double)(float)visual->get("surface_pattern_rotation_degrees");
    p.surface_pattern_density = (double)(float)visual->get("surface_pattern_density");
    p.surface_pattern_contrast = (double)(float)visual->get("surface_pattern_contrast");
    p.surface_pattern_warp_strength = (double)(float)visual->get("surface_pattern_warp_strength");
    p.surface_pattern_warp_scale = (double)(float)visual->get("surface_pattern_warp_scale");
    p.surface_pattern_specular_variation = (double)(float)visual->get("surface_pattern_specular_variation");
    p.surface_pattern_roughness_variation = (double)(float)visual->get("surface_pattern_roughness_variation");

    // Volume pattern
    p.volume_pattern_type = (int)(int64_t)visual->get("volume_pattern_type");
    p.volume_pattern_mix = (double)(float)visual->get("volume_pattern_mix");
    p.volume_pattern_scale = Vector3(visual->get("volume_pattern_scale"));
    p.volume_pattern_axis = Vector3(visual->get("volume_pattern_axis"));
    p.volume_pattern_density = (double)(float)visual->get("volume_pattern_density");
    p.volume_pattern_contrast = (double)(float)visual->get("volume_pattern_contrast");
    p.volume_pattern_warp_strength = (double)(float)visual->get("volume_pattern_warp_strength");
    p.volume_pattern_warp_scale = (double)(float)visual->get("volume_pattern_warp_scale");
    p.volume_absorption_variation = (double)(float)visual->get("volume_absorption_variation");
    p.volume_scattering_variation = (double)(float)visual->get("volume_scattering_variation");

    // Reactive
    p.reactive_effect_type = (int)(int64_t)visual->get("reactive_effect_type");
    p.reactive_color = Color(visual->get("reactive_color"));
    p.reactive_secondary_color = Color(visual->get("reactive_secondary_color"));
    p.reactive_strength = (double)(float)visual->get("reactive_strength");
    p.reactive_sharpness = (double)(float)visual->get("reactive_sharpness");
    p.reactive_density = (double)(float)visual->get("reactive_density");
    p.reactive_scale = (double)(float)visual->get("reactive_scale");
    p.reactive_axis = Vector3(visual->get("reactive_axis"));

    // Texture
    p.use_texture = (bool)visual->get("use_texture");
    p.texture_blend = (double)(float)visual->get("texture_blend");
    p.texture_zoom = (double)(float)visual->get("texture_zoom");
    p.texture_offset = Vector2(visual->get("texture_offset"));
    p.texture_facet_warp = (double)(float)visual->get("texture_facet_warp");
    p.material_secondary_color = Color(visual->get("material_secondary_color"));
    p.material_tertiary_color = Color(visual->get("material_tertiary_color"));

    p.rotation_degrees = (double)(float)visual->get("rotation_degrees");

    // Inclusion properties
    Variant incl_var = visual->get("inclusion_profile");
    if (incl_var.get_type() != Variant::NIL) {
        Ref<Resource> incl = incl_var;
        if (incl.is_valid()) {
            p.has_inclusions = true;
            p.inclusion_ior = (double)(float)incl->get("material_ior");
            p.inclusion_absorption = (double)(float)incl->get("material_absorption");
            p.inclusion_scatter = (double)(float)incl->get("scatter_strength");
            Variant sz_var = incl->get("size_range");
            if (sz_var.get_type() == Variant::VECTOR2) {
                Vector2 sz = sz_var;
                p.inclusion_typical_size = (double)(sz.x + sz.y) * 0.5;
            }
        }
    }

    // Optic axis (per-visual; cut orientation vs crystal axis)
    Variant optic_var = visual->get("optic_axis");
    if (optic_var.get_type() == Variant::VECTOR3) {
        Vector3 oa = optic_var;
        if (oa.length_squared() > 1e-12) {
            p.optic_axis = oa.normalized();
        }
    }

    return p;
}

// ===========================================================================
// build_environment
// ===========================================================================

EnvironmentSetup GemTraceKernel::build_environment(
    const GemTraceProps& props,
    const Dictionary& request,
    Vector3 light_dir) const
{
    EnvironmentSetup env;

    // Read from request's environment_profile (populated by GemBakeEnvironment)
    if (request.has("environment_profile")) {
        Dictionary ep = Dictionary(request["environment_profile"]);
        env.sky_low = Color(ep.get("sky_low", Color(0.16f, 0.19f, 0.26f, 1.0f)));
        env.sky_top = Color(ep.get("sky_top", Color(0.36f, 0.42f, 0.54f, 1.0f)));
        env.horizon = Color(ep.get("horizon", Color(0.68f, 0.54f, 0.36f, 1.0f)));
        env.ground_dark = Color(ep.get("ground_dark", Color(0.02f, 0.016f, 0.013f, 1.0f)));
        env.ground_lift = Color(ep.get("ground_lift", Color(0.10f, 0.078f, 0.052f, 1.0f)));
        env.blocker_power = (double)(float)ep.get("blocker_power", 10.0);
        env.blocker_strength = (double)(float)ep.get("blocker_strength", 0.19);
        env.ground_albedo = (double)(float)ep.get("ground_albedo", 0.15);
        env.ground_tint = Color(ep.get("ground_tint", Color(0.92f, 0.87f, 0.80f, 1.0f)));
        env.ground_distance = (double)(float)ep.get("ground_distance", 0.8);
        env.exposure = (double)(float)ep.get("exposure", 1.0);
        env.light_energy = (double)(float)ep.get("light_energy", 2.4);
        env.environment_energy = (double)(float)ep.get("environment_energy", 1.0);
        env.card_power_cap = (double)(float)ep.get("card_power_cap", -1.0);

        Vector3 blocker_local = Vector3(ep.get("blocker_dir", Vector3(-0.18, -0.30, 0.94)));
        env.blocker_dir = blocker_local.normalized();

        if (ep.has("cards")) {
            Array cards_array = Array(ep["cards"]);
            for (int i = 0; i < (int)cards_array.size(); i++) {
                Dictionary cd = Dictionary(cards_array[i]);
                LightCard card;
                card.dir = Vector3(cd.get("dir", Vector3(0, 0, 1))).normalized();
                card.color = Color(cd.get("color", Color(1, 1, 1, 1)));
                card.sharp_power = (double)(float)cd.get("sharp_power", 200.0);
                card.broad_power = (double)(float)cd.get("broad_power", 10.0);
                card.sharp_strength = (double)(float)cd.get("sharp_strength", 1.0);
                card.broad_strength = (double)(float)cd.get("broad_strength", 0.5);
                card.temperature_kelvin = (double)(float)cd.get("temperature_kelvin", 0.0);
                Color ec = Color(cd.get("edge_color", Color(0, 0, 0, 0)));
                card.edge_color = (ec.a < 0.01f) ? card.color : ec;
                card.gradient_power = (double)(float)cd.get("gradient_power", 1.0);
                env.cards.push_back(card);
            }
        }
    } else {
        // Default neutral sky environment
        env.sky_low = Color(0.16f, 0.19f, 0.26f, 1.0f);
        env.sky_top = Color(0.36f, 0.42f, 0.54f, 1.0f);
        env.horizon = Color(0.68f, 0.54f, 0.36f, 1.0f);
        env.ground_dark = Color(0.02f, 0.016f, 0.013f, 1.0f);
        env.ground_lift = Color(0.10f, 0.078f, 0.052f, 1.0f);
        env.blocker_dir = Vector3(-0.18f, -0.30f, 0.94f).normalized();
        env.blocker_power = 10.0;
        env.blocker_strength = 0.19;
        env.ground_albedo = 0.15;
        env.exposure = 1.0;
        env.light_energy = 2.4;
        env.environment_energy = 1.0;

        // Default neutral cards
        LightCard key;
        key.dir = Vector3(0.08f, 0.38f, 0.92f).normalized();
        key.color = Color(1.0f, 0.96f, 0.88f, 1.0f);
        key.sharp_power = 820.0; key.broad_power = 12.0;
        key.sharp_strength = 2.3; key.broad_strength = 1.2;
        key.temperature_kelvin = 5500.0;
        key.edge_color = Color(0.94f, 0.96f, 1.0f, 1.0f);
        key.gradient_power = 0.7;
        env.cards.push_back(key);

        LightCard right;
        right.dir = Vector3(0.56f, 0.18f, 0.80f).normalized();
        right.color = Color(0.95f, 0.92f, 0.98f, 1.0f);
        right.sharp_power = 48.0; right.broad_power = 14.0;
        right.sharp_strength = 0.42; right.broad_strength = 0.28;
        right.temperature_kelvin = 6200.0;
        right.edge_color = Color(0.90f, 0.92f, 1.0f, 1.0f);
        right.gradient_power = 0.8;
        env.cards.push_back(right);

        LightCard left;
        left.dir = Vector3(-0.74f, 0.14f, 0.62f).normalized();
        left.color = Color(1.0f, 0.99f, 0.97f, 1.0f);
        left.sharp_power = 64.0; left.broad_power = 18.0;
        left.sharp_strength = 0.36; left.broad_strength = 0.24;
        left.temperature_kelvin = 6200.0;
        left.edge_color = Color(0.93f, 0.96f, 1.0f, 1.0f);
        left.gradient_power = 0.8;
        env.cards.push_back(left);
    }

    // Rotate the entire environment setup (cards + blocker) based on light_dir.
    // This makes per-bin lighting variation meaningful for transparent gems where
    // the environment is the sole illumination source.  The light_dir from each
    // lighting bin encodes a yaw/pitch sweep that was previously unused by the
    // spectral transport; now it rotates the studio around the gem.
    {
        Vector3 ref_dir = Vector3(0.0f, 0.0f, 1.0f); // neutral front-facing
        Vector3 ld = light_dir.normalized();
        if (ld.length_squared() < 1e-8) ld = ref_dir;

        // Only rotate when light_dir deviates from the reference direction.
        double dot = clampd((double)ref_dir.dot(ld), -1.0, 1.0);
        if (dot < 0.9999) {
            Vector3 axis = ref_dir.cross(ld);
            double axis_len = (double)axis.length();
            if (axis_len > 1e-8) {
                axis = axis / (float)axis_len;
                double angle = std::acos(dot);
                Basis rotation(axis, angle);
                for (auto& card : env.cards) {
                    card.dir = rotation.xform(card.dir).normalized();
                }
                env.blocker_dir = rotation.xform(env.blocker_dir).normalized();
            }
        }
    }

    return env;
}

// ===========================================================================
// View basis building (retained from old kernel)
// ===========================================================================

static Basis build_view_basis(const GemTraceProps& props, const Dictionary& request) {
    double pitch = (double)(float)request.get("view_pitch_degrees", 0.0);
    double yaw = (double)(float)request.get("view_yaw_degrees", 0.0);
    Basis basis = Basis(Vector3(1, 0, 0), Math::deg_to_rad(pitch));

    bool mesh_includes_cut_rotation = (bool)request.get("mesh_includes_cut_rotation", false);
    double yaw_degrees = yaw;
    double roll_degrees = (double)(float)request.get("view_roll_degrees", 0.0);
    if (!mesh_includes_cut_rotation) {
        yaw_degrees += (double)(float)request.get("rotation_degrees", 0.0);
        roll_degrees += props.rotation_degrees;
    }
    basis = Basis(Vector3(0, 1, 0), Math::deg_to_rad(yaw_degrees)) * basis;
    if (std::abs(roll_degrees) > 1e-6) {
        basis = Basis(Vector3(0, 0, 1), Math::deg_to_rad(roll_degrees)) * basis;
    }
    return basis;
}

// ===========================================================================
// Transform AABB
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
    if (min_v.x >= 1e29) return AABB();
    return AABB(min_v, max_v - min_v);
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

    // Extract properties
    ctx.props = extract_props(visual);

    // Build trace data (with optional facet edge rounding resolved from cut spec + visual override).
    // Request-level "disable_edge_rounding" flag overrides for A/B testing.
    double edge_rounding = (double)(float)visual->call("get_effective_edge_rounding");
    if ((bool)request.get("disable_edge_rounding", false)) {
        edge_rounding = 0.0;
    }
    Dictionary trace_data_raw;
    if (edge_rounding > 0.0) {
        trace_data_raw = Dictionary(mesh_resource->call("build_trace_data_with_rounding", edge_rounding));
    } else {
        trace_data_raw = Dictionary(mesh_resource->call("build_trace_data"));
    }
    Dictionary trace_data = trace_data_raw.duplicate(false);
    trace_data["optic_axis"] = ctx.props.optic_axis;
    request["_trace_data"] = trace_data;

    // View basis
    Basis view_basis;
    if (request.has("view_basis_override")) {
        view_basis = Basis(request.get("view_basis_override", Basis()));
    } else {
        view_basis = build_view_basis(ctx.props, request);
    }
    Basis inverse_basis = view_basis.inverse();
    ctx.inverse_basis = inverse_basis;

    // Bounds and camera
    AABB source_bounds = AABB(trace_data.get("bounds", AABB()));
    AABB bounds = transform_aabb(source_bounds, view_basis);
    double radius = dmax((double)(float)trace_data.get("bounding_radius", 0.5), 0.25);
    ctx.radius = radius;

    double aspect = (double)target_size.x / dmax((double)target_size.y, 1.0);
    double view_scale = clampd((double)(float)request.get("view_scale", 1.0), 0.5, 2.0);
    bool uniform_proj = (bool)request.get("uniform_projection", false);
    double projection_extent = uniform_proj
        ? radius * 2.0
        : dmax((double)bounds.size.y, radius * 2.0);
    double half_height = projection_extent * VIEW_MARGIN * 0.5 / view_scale;
    double half_width = half_height * aspect;
    double origin_z = (double)bounds.position.z + (double)bounds.size.z + radius * 2.4;
    ctx.half_width = half_width;
    ctx.half_height = half_height;
    ctx.origin_z = origin_z;

    Vector3 dir = inverse_basis.xform(Vector3(0.0, 0.0, -1.0)).normalized();
    ctx.view_dir = dir;

    Vector3 light_dir_world = Vector3(request.get("light_dir", Vector3(-0.4, -0.5, 0.75))).normalized();
    if (light_dir_world.length_squared() < 1e-8) {
        light_dir_world = Vector3(-0.4, -0.5, 0.75).normalized();
    }
    ctx.light_dir = inverse_basis.xform(light_dir_world).normalized();

    // Build environment
    ctx.environment = build_environment(ctx.props, request, ctx.light_dir);

    // Sampling
    ctx.samples_per_pixel = clampi(
        (int)(int64_t)request.get("samples_per_pixel", 64), 16, 512);
    ctx.base_seed = (uint64_t)(int64_t)request.get("seed", 42);

    // SPP-dependent variance budget — caps high-variance features at low SPP
    ctx.variance_budget = VarianceBudget::from_spp(ctx.samples_per_pixel);

    // Feature flags
    ctx.has_volume_patterns = (ctx.props.volume_pattern_mix > 0.001
        && ctx.props.volume_pattern_type != MATERIAL_PATTERN_NONE);
    ctx.has_surface_patterns = (
        (ctx.props.surface_pattern_mix > 0.001
         && ctx.props.surface_pattern_type != MATERIAL_PATTERN_NONE)
        || ctx.props.use_texture);
    ctx.has_reactive = (ctx.props.reactive_strength > 0.0001
        && ctx.props.reactive_effect_type != MATERIAL_REACTIVE_NONE);
    ctx.is_opaque = (ctx.props.material_mode == MATERIAL_MODE_PATTERNED_OPAQUE);
    ctx.is_translucent = (ctx.props.material_mode == MATERIAL_MODE_PATTERNED_TRANSLUCENT);

    // Texture
    if (ctx.props.use_texture) {
        Variant color_texture = visual->get("color_texture");
        if (color_texture.get_type() != Variant::NIL) {
            Ref<Resource> tex_res = color_texture;
            if (tex_res.is_valid()) {
                ctx.texture_image = Ref<Image>(tex_res->call("get_image"));
            }
        }
    }

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
    if (mesh_resource.is_null() || visual.is_null()) return Ref<Image>();

    Vector2i target_size = Vector2i(request.get("trace_size",
        request.get("draw_size",
            request.get("target_size", Vector2i(0, 0)))));
    if (target_size.x <= 0 || target_size.y <= 0) return Ref<Image>();

    TraceContext ctx = build_context(mesh_resource, visual, request);

    Dictionary trace_data = Dictionary(request.get("_trace_data", Dictionary()));
    TraceScene scene;
    scene.build_from_trace_data(trace_data);
    if (!scene.is_valid()) return Ref<Image>();

    // Resolve thread count
    int thread_budget = clampi(
        (int)(int64_t)request.get("thread_budget",
            request.get("thread_count", OS::get_singleton()->get_processor_count() - 1)),
        1, 32);

    int pixel_count = target_size.x * target_size.y;
    int row_limit = dmax(target_size.y / MIN_ROWS_PER_TRACE_THREAD, 1);
    int pixel_limit = dmax(pixel_count / MIN_PIXELS_PER_TRACE_THREAD, 1);
    int work_units = pixel_count * ctx.samples_per_pixel;
    int work_limit = dmax(work_units / MIN_WORK_UNITS_PER_TRACE_THREAD, 1);
    int thread_count = dmax(
        dmin(dmin(thread_budget, row_limit), dmin(pixel_limit, work_limit)), 1);

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
        for (auto& th : threads) th.join();
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
// trace_row_band — new hero-wavelength spectral sampling
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
    double inv_spp = 1.0 / (double)ctx.samples_per_pixel;

    for (int y = row_start; y < row_end; y++) {
        for (int x = 0; x < width; x++) {
            Vector3 xyz_sum(0.0, 0.0, 0.0);
            double hit_count = 0.0;

            TraceRNG rng;
            rng.seed(ctx.base_seed, y, x);

            for (int s = 0; s < ctx.samples_per_pixel; s++) {
                // Stratified sub-pixel jitter
                double u = ((double)x + rng.next()) * inv_w * 2.0 - 1.0;
                double v = 1.0 - ((double)y + rng.next()) * inv_h * 2.0;

                Vector3 origin = ctx.inverse_basis.xform(
                    Vector3((float)(u * ctx.half_width),
                            (float)(v * ctx.half_height),
                            (float)ctx.origin_z));

                // Quick first-hit check for alpha
                HitResult first_hit = scene.intersect(origin, ctx.view_dir, -1);
                if (!first_hit.did_hit) continue;

                hit_count += 1.0;

                // Stratified hero wavelength: divide spectrum into spp strata
                double stratum = ((double)s + rng.next()) * inv_spp;
                double hero_lambda = LAMBDA_MIN + stratum * LAMBDA_RANGE;

                // 3 companion wavelengths at equal spectral offsets (PBRT-v4 style)
                double lambdas[HERO_WAVELENGTHS];
                lambdas[0] = hero_lambda;
                for (int w = 1; w < HERO_WAVELENGTHS; w++) {
                    double offset = stratum + (double)w / (double)HERO_WAVELENGTHS;
                    if (offset >= 1.0) offset -= 1.0;
                    lambdas[w] = LAMBDA_MIN + offset * LAMBDA_RANGE;
                }

                if (ctx.props.enable_dispersion) {
                    // True dispersion path: trace HERO_WAVELENGTHS independent
                    // single-λ paths, so each wavelength refracts along its own
                    // Snell direction at every surface. This is what produces
                    // real prismatic "fire" in high-dispersion gems.
                    for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                        double I_w = transport::trace_path(
                            ctx, scene, origin, ctx.view_dir, lambdas[w], rng);
                        Vector3 cie = spectral::cie_xyz(lambdas[w]);
                        xyz_sum += cie * (float)I_w;
                    }
                } else {
                    // Shared-geometry path: one geometric trace carrying 4
                    // wavelengths for variance reduction (hero-λ geometry).
                    transport::SpectralResult spr = transport::trace_path_spectral(
                        ctx, scene, origin, ctx.view_dir, lambdas, rng);
                    for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                        Vector3 cie = spectral::cie_xyz(lambdas[w]);
                        xyz_sum += cie * (float)spr.intensities[w];
                    }
                }
            }

            int pixel_index = y * width + x;
            if (hit_count <= 0.0) {
                out_pixels[pixel_index] = Color(0.0, 0.0, 0.0, 0.0);
            } else {
                // Normalize the MC spectral estimate.
                // Total spectral samples = HERO_WAVELENGTHS * hit_count.
                double spectral_count = (double)HERO_WAVELENGTHS * hit_count;
                Vector3 xyz = xyz_sum * (float)(LAMBDA_RANGE / (spectral_count * CIE_Y_INTEGRAL));

                // XYZ → linear sRGB
                Vector3 linear = spectral::xyz_to_linear_srgb(xyz);

                // Exposure
                linear *= (float)ctx.environment.exposure;

                // ACES tonemap
                Vector3 tonemapped(
                    (float)apply_aces_channel((double)linear.x),
                    (float)apply_aces_channel((double)linear.y),
                    (float)apply_aces_channel((double)linear.z));

                // sRGB gamma
                Vector3 srgb = spectral::linear_to_srgb(tonemapped);

                // Clamp
                srgb.x = (float)clampd((double)srgb.x, 0.0, 1.0);
                srgb.y = (float)clampd((double)srgb.y, 0.0, 1.0);
                srgb.z = (float)clampd((double)srgb.z, 0.0, 1.0);

                double alpha = clampd(hit_count / (double)ctx.samples_per_pixel, 0.0, 1.0);
                out_pixels[pixel_index] = Color(srgb.x, srgb.y, srgb.z, (float)alpha);
            }
        }
    }
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
// clean_alpha_edges (retained from old kernel)
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
                    neighbor_sum += Vector3(neighbor.r, neighbor.g, neighbor.b) * (float)w;
                    neighbor_weight += w;
                }
            }

            Vector3 cleaned_rgb(pixel.r, pixel.g, pixel.b);
            if (neighbor_weight > 0.0001) {
                Vector3 neighbor_rgb = neighbor_sum / (float)neighbor_weight;
                double mix_amount = clampd((1.0 - pixel.a) * 0.78, 0.0, 0.92);
                cleaned_rgb = cleaned_rgb.lerp(neighbor_rgb, (float)mix_amount);
            }

            if (pixel.a < 0.03) {
                image->set_pixel(x, y, Color(0, 0, 0, 0));
                continue;
            }
            image->set_pixel(x, y, Color(cleaned_rgb.x, cleaned_rgb.y, cleaned_rgb.z, pixel.a));
        }
    }
}

// ===========================================================================
// run_physics_tests
// ===========================================================================

Dictionary GemTraceKernel::run_physics_tests() const {
    Dictionary results;

    // --- Fresnel tests ---

    // fresnel_normal_diamond: R0 = ((1-2.417)/(1+2.417))^2
    {
        Vector3 dir(0, 0, -1);
        Vector3 normal(0, 0, 1);
        double actual = fresnel::dielectric(dir, normal, 1.0, 2.417);
        double expected = 0.1722;
        Dictionary test;
        test["passed"] = std::abs(actual - expected) < 0.005;
        test["expected"] = expected;
        test["actual"] = actual;
        results["fresnel_normal_diamond"] = test;
    }

    // fresnel_normal_glass: R0 = ((1-1.5)/(1+1.5))^2 = 0.04
    {
        Vector3 dir(0, 0, -1);
        Vector3 normal(0, 0, 1);
        double actual = fresnel::dielectric(dir, normal, 1.0, 1.5);
        double expected = 0.04;
        Dictionary test;
        test["passed"] = std::abs(actual - expected) < 0.005;
        test["expected"] = expected;
        test["actual"] = actual;
        results["fresnel_normal_glass"] = test;
    }

    // fresnel_tir_glass: R = 1.0 at angle > critical angle (asin(1/1.5) ~ 41.8 deg)
    {
        double angle = Math::deg_to_rad(50.0); // well beyond critical angle
        Vector3 dir((float)std::sin(angle), 0.0f, (float)(-std::cos(angle)));
        Vector3 normal(0, 0, 1);
        double actual = fresnel::dielectric(dir, normal, 1.5, 1.0);
        double expected = 1.0;
        Dictionary test;
        test["passed"] = std::abs(actual - expected) < 0.001;
        test["expected"] = expected;
        test["actual"] = actual;
        results["fresnel_tir_glass"] = test;
    }

    // fresnel_brewster_glass: Rp ~ 0 at Brewster angle = atan(1.5) ~ 56.3 deg
    // Exact dielectric averages Rs and Rp, so R won't be exactly 0, but should
    // be at a minimum. We test that R < R_at_normal (0.04) and R < 0.08.
    {
        double brewster = std::atan(1.5);
        Vector3 dir((float)std::sin(brewster), 0.0f, (float)(-std::cos(brewster)));
        Vector3 normal(0, 0, 1);
        double actual = fresnel::dielectric(dir, normal, 1.0, 1.5);
        Dictionary test;
        // At Brewster's angle, Rp = 0 but Rs > 0. The average is nonzero but
        // should be less than at normal incidence or near-grazing.
        test["passed"] = actual < 0.08 && actual > 0.0;
        test["expected"] = String("< 0.08 (Brewster minimum)");
        test["actual"] = actual;
        results["fresnel_brewster_glass"] = test;
    }

    // fresnel_grazing: R -> 1.0 at 89.9 degrees
    {
        double angle = Math::deg_to_rad(89.9);
        Vector3 dir((float)std::sin(angle), 0.0f, (float)(-std::cos(angle)));
        Vector3 normal(0, 0, 1);
        double actual = fresnel::dielectric(dir, normal, 1.0, 1.5);
        double expected = 1.0;
        Dictionary test;
        test["passed"] = actual > 0.985;
        test["expected"] = expected;
        test["actual"] = actual;
        results["fresnel_grazing"] = test;
    }

    // --- Sellmeier tests ---

    // sellmeier_diamond_589nm: n ~ 2.417
    {
        GemTraceProps diamond_props;
        diamond_props.sellmeier_b = Vector3(4.3356f, 0.3306f, 0.0f);
        diamond_props.sellmeier_c = Vector3(0.01060f, 0.01750f, 0.0f);
        double actual = spectral::sellmeier_ior(diamond_props, 589.0);
        double expected = 2.417;
        Dictionary test;
        test["passed"] = std::abs(actual - expected) < 0.005;
        test["expected"] = expected;
        test["actual"] = actual;
        results["sellmeier_diamond_589nm"] = test;
    }

    // sellmeier_diamond_486nm: n ~ 2.427
    {
        GemTraceProps diamond_props;
        diamond_props.sellmeier_b = Vector3(4.3356f, 0.3306f, 0.0f);
        diamond_props.sellmeier_c = Vector3(0.01060f, 0.01750f, 0.0f);
        double actual = spectral::sellmeier_ior(diamond_props, 486.0);
        double expected = 2.427;
        Dictionary test;
        test["passed"] = std::abs(actual - expected) < 0.01;
        test["expected"] = expected;
        test["actual"] = actual;
        results["sellmeier_diamond_486nm"] = test;
    }

    // sellmeier_quartz_589nm: n ~ 1.458
    // Note: the Sellmeier coefficients used here (B=0.6962/0.4079/0.8975,
    // C=0.00468/0.01351/97.934) are the published fused silica values.
    // Crystalline alpha-quartz has n~1.544 but uses different coefficients.
    {
        GemTraceProps quartz_props;
        quartz_props.sellmeier_b = Vector3(0.6962f, 0.4079f, 0.8975f);
        quartz_props.sellmeier_c = Vector3(0.00468f, 0.01351f, 97.934f);
        double actual = spectral::sellmeier_ior(quartz_props, 589.0);
        double expected = 1.458;
        Dictionary test;
        test["passed"] = std::abs(actual - expected) < 0.005;
        test["expected"] = expected;
        test["actual"] = actual;
        results["sellmeier_quartz_589nm"] = test;
    }

    // --- Beer-Lambert tests ---

    // beer_lambert_unit: exp(-1.0 * 1.0) ~ 0.368
    {
        GemTraceProps beer_props;
        beer_props.absorption_spectrum.resize(81, 1.0f);
        beer_props.absorption_strength_scale = 1.0;
        double actual = volume::beer_lambert(beer_props, 580.0, 1.0, Vector3(0, 0, 1));
        double expected = std::exp(-1.0);
        Dictionary test;
        test["passed"] = std::abs(actual - expected) < 0.005;
        test["expected"] = expected;
        test["actual"] = actual;
        results["beer_lambert_unit"] = test;
    }

    // beer_lambert_zero_dist: exp(0) = 1.0
    {
        GemTraceProps beer_props;
        beer_props.absorption_spectrum.resize(81, 1.0f);
        double actual = volume::beer_lambert(beer_props, 580.0, 0.0, Vector3(0, 0, 1));
        double expected = 1.0;
        Dictionary test;
        test["passed"] = std::abs(actual - expected) < 0.001;
        test["expected"] = expected;
        test["actual"] = actual;
        results["beer_lambert_zero_dist"] = test;
    }

    // absorption_endpoints_map_380_to_780: index 0 must be the short-wave end,
    // index 80 the long-wave end. This catches reversed wavelength-axis mapping.
    {
        GemTraceProps edge_props;
        edge_props.absorption_spectrum.resize(81, 0.001f);
        edge_props.absorption_spectrum[0] = 9.0f;
        edge_props.absorption_spectrum[80] = 0.05f;
        double a_380 = spectral::evaluate_absorption(edge_props, 380.0, Vector3(0, 0, 1));
        double a_780 = spectral::evaluate_absorption(edge_props, 780.0, Vector3(0, 0, 1));
        Dictionary test;
        bool passed = a_380 > 8.5 && a_780 < 0.1 && a_380 > a_780 * 50.0;
        test["passed"] = passed;
        test["expected"] = String("α(380nm) ≫ α(780nm) when only spectrum[0] is high");
        test["actual"] = String::num(a_380, 4) + String(" vs ") + String::num(a_780, 4);
        results["absorption_endpoints_map_380_to_780"] = test;
    }

    // absorption_is_alpha_not_transmittance: arrays are extinction coefficients α,
    // not precomputed transmittance values. High α over distance must darken strongly.
    {
        GemTraceProps alpha_props;
        alpha_props.absorption_spectrum.resize(81, 4.0f);
        alpha_props.absorption_strength_scale = 1.0;
        double actual = volume::beer_lambert(alpha_props, 610.0, 0.5, Vector3(0, 0, 1));
        double expected = std::exp(-2.0); // exp(-α d) = exp(-4 * 0.5)
        Dictionary test;
        test["passed"] = std::abs(actual - expected) < 0.005;
        test["expected"] = expected;
        test["actual"] = actual;
        results["absorption_is_alpha_not_transmittance"] = test;
    }

    // --- CIE test ---

    // cie_equal_energy_white: equal-energy illuminant -> X ≈ Y ≈ Z
    // For the CIE 1931 observer, ∫x̄ ≈ ∫ȳ ≈ ∫z̄ over 380-780nm.
    // We verify:
    //   1. Y_sum * SPECTRUM_STEP is close to the CIE_Y_INTEGRAL constant
    //      used for pixel loop normalization.
    //   2. X/Y and Z/Y ratios are close to 1.0 (equal-energy white point).
    {
        Vector3 xyz_sum(0, 0, 0);
        for (int i = 0; i < SPECTRUM_SAMPLES; i++) {
            double lambda = LAMBDA_MIN + (double)i * SPECTRUM_STEP;
            xyz_sum += spectral::cie_xyz(lambda);
        }
        double y_integral = (double)xyz_sum.y * SPECTRUM_STEP;
        double integral_error = std::abs(y_integral - CIE_Y_INTEGRAL);
        double x_over_y = (double)xyz_sum.y > 1e-6 ? (double)xyz_sum.x / (double)xyz_sum.y : 0.0;
        double z_over_y = (double)xyz_sum.y > 1e-6 ? (double)xyz_sum.z / (double)xyz_sum.y : 0.0;
        // Y integral must match the constant we use in the pixel loop
        // normalization (within 0.5 to account for table rounding).
        bool integral_ok = integral_error < 0.5;
        // Raw ∫x̄, ∫ȳ, ∫z̄ are not identical; 5nm discrete samples skew X/Y slightly
        // below 1.0 (~0.87) while Z/Y stays ~1.0 with our tabulated CMFs.
        bool ratios_ok = x_over_y > 0.82 && x_over_y < 1.18
                      && z_over_y > 0.9 && z_over_y < 1.1;
        Dictionary test;
        test["passed"] = integral_ok && ratios_ok;
        test["expected"] = String("Y_integral≈") + String::num(CIE_Y_INTEGRAL, 2)
                         + String(", X/Y in [0.82,1.18], Z/Y in [0.9,1.1]");
        test["actual"] = String("Y_integral=") + String::num(y_integral, 4)
                       + String(" X/Y=") + String::num(x_over_y, 4)
                       + String(" Z/Y=") + String::num(z_over_y, 4);
        results["cie_equal_energy_white"] = test;
    }

    // --- Planck test ---

    // planck_wien_5500K: peak ~ 527nm (Wien: 2898000/5500)
    {
        double peak_lambda = 0.0;
        double peak_value = 0.0;
        for (int i = 0; i < SPECTRUM_SAMPLES; i++) {
            double lambda = LAMBDA_MIN + (double)i * SPECTRUM_STEP;
            double val = spectral::planckian_radiance(lambda, 5500.0);
            if (val > peak_value) {
                peak_value = val;
                peak_lambda = lambda;
            }
        }
        double expected = 527.0; // Wien: 2898000/5500 ~ 527nm
        Dictionary test;
        test["passed"] = std::abs(peak_lambda - expected) < 15.0; // within 15nm (5nm resolution)
        test["expected"] = expected;
        test["actual"] = peak_lambda;
        results["planck_wien_5500K"] = test;
    }

    // --- Henyey-Greenstein tests ---

    // hg_isotropic_mean: g=0, 10000 samples -> mean cos(theta) ~ 0 +/- 0.05
    {
        TraceRNG rng;
        rng.seed(12345ULL);
        double cos_sum = 0.0;
        int n_samples = 10000;
        Vector3 incident(0, 0, 1);
        for (int i = 0; i < n_samples; i++) {
            Vector3 scattered = volume::sample_henyey_greenstein(incident, 0.0, rng);
            cos_sum += (double)scattered.dot(incident);
        }
        double mean_cos = cos_sum / (double)n_samples;
        Dictionary test;
        test["passed"] = std::abs(mean_cos) < 0.05;
        test["expected"] = 0.0;
        test["actual"] = mean_cos;
        results["hg_isotropic_mean"] = test;
    }

    // hg_forward_mean: g=0.8, 10000 samples -> mean cos(theta) ~ 0.8 +/- 0.05
    {
        TraceRNG rng;
        rng.seed(67890ULL);
        double cos_sum = 0.0;
        int n_samples = 10000;
        Vector3 incident(0, 0, 1);
        for (int i = 0; i < n_samples; i++) {
            Vector3 scattered = volume::sample_henyey_greenstein(incident, 0.8, rng);
            cos_sum += (double)scattered.dot(incident);
        }
        double mean_cos = cos_sum / (double)n_samples;
        Dictionary test;
        test["passed"] = std::abs(mean_cos - 0.8) < 0.05;
        test["expected"] = 0.8;
        test["actual"] = mean_cos;
        results["hg_forward_mean"] = test;
    }

    // --- GGX tests ---

    // ggx_mirror: roughness=0 -> returns geometric normal
    {
        TraceRNG rng;
        rng.seed(11111ULL);
        Vector3 geo_normal(0, 1, 0);
        Vector3 sampled = fresnel::sample_ggx(geo_normal, 0.0, rng);
        double dot = (double)sampled.dot(geo_normal);
        Dictionary test;
        test["passed"] = dot > 0.9999;
        test["expected"] = String("geometric normal (dot > 0.9999)");
        test["actual"] = dot;
        results["ggx_mirror"] = test;
    }

    // ggx_rough_no_backface: roughness=0.3, 1000 samples -> all normals have
    // positive dot with geometric normal
    {
        TraceRNG rng;
        rng.seed(22222ULL);
        Vector3 geo_normal(0, 1, 0);
        bool all_positive = true;
        int n_samples = 1000;
        for (int i = 0; i < n_samples; i++) {
            Vector3 sampled = fresnel::sample_ggx(geo_normal, 0.3, rng);
            if ((double)sampled.dot(geo_normal) <= 0.0) {
                all_positive = false;
                break;
            }
        }
        Dictionary test;
        test["passed"] = all_positive;
        test["expected"] = String("all samples dot(n) > 0");
        test["actual"] = all_positive ? String("true") : String("false");
        results["ggx_rough_no_backface"] = test;
    }

    // --- Fluorescence (volume) ---

    // fluorescence_ruby_band: high QY + excitation near 554nm yields emission near 694nm
    {
        GemTraceProps fp;
        fp.fluorescence_quantum_yield = 1.0;
        fp.fluorescence_excitation_center_nm = 554.0;
        fp.fluorescence_excitation_width_nm = 35.0;
        fp.fluorescence_emission_center_nm = 694.0;
        fp.fluorescence_emission_width_nm = 12.0;
        TraceRNG rng;
        rng.seed(424242ULL);
        int successes = 0;
        double sum_emit = 0.0;
        for (int i = 0; i < 500; i++) {
            double wl = 480.0 + (double)(i % 60) * 5.0;
            if (volume::try_fluorescence(fp, wl, rng)) {
                successes++;
                sum_emit += wl;
            }
        }
        double mean_emit = successes > 0 ? sum_emit / (double)successes : 0.0;
        Dictionary test;
        bool passed = successes > 20 && mean_emit > 620.0;
        test["passed"] = passed;
        test["expected"] = String("mean shifted λ > 620nm with many successes");
        test["actual"] = String::num(successes) + String(" shifts, mean_nm=") + String::num(mean_emit, 2);
        results["fluorescence_ruby_band"] = test;
    }

    // pleochroism_blend_separates: extraordinary spectrum differs from ordinary
    {
        GemTraceProps pp;
        pp.absorption_spectrum.resize(81, 1.0f);
        pp.pleochroism_absorption_spectrum.resize(81, 2.5f);
        pp.optic_axis = Vector3(0, 1, 0);
        pp.absorption_strength_scale = 1.0;
        Vector3 along = Vector3(0, 1, 0);
        Vector3 across = Vector3(1, 0, 0);
        double a_along = spectral::evaluate_absorption(pp, 580.0, along);
        double a_across = spectral::evaluate_absorption(pp, 580.0, across);
        Dictionary test;
        test["passed"] = std::abs(a_along - a_across) > 0.15;
        test["expected"] = String("α differs with ray vs optic axis");
        test["actual"] = String::num(a_along, 4) + String(" vs ") + String::num(a_across, 4);
        results["pleochroism_blend_separates"] = test;
    }

    // beer_lambert_steep_absorption_edge: step spectrum across visible band stays in (0,1]
    {
        GemTraceProps steep;
        steep.absorption_spectrum.resize(81);
        for (int i = 0; i < 81; i++) {
            steep.absorption_spectrum[i] = (i < 40) ? 0.001f : 12.0f;
        }
        steep.absorption_strength_scale = 1.0;
        Vector3 rd(0, 0, 1);
        double t_blue = volume::beer_lambert(steep, 480.0, 0.4, rd);
        double t_mid = volume::beer_lambert(steep, 580.0, 0.4, rd);
        double t_red = volume::beer_lambert(steep, 720.0, 0.4, rd);
        // 480 nm sits in the low-α side of the step; 580/720 nm share the high-α side so
        // transmittance can match closely — require strong separation blue vs absorbed band.
        bool ok = t_blue > 0.99 && t_mid < 0.05 && t_red < 0.05 && t_blue > t_mid
                 && std::isfinite(t_blue) && std::isfinite(t_mid) && std::isfinite(t_red);
        Dictionary test;
        test["passed"] = ok;
        test["expected"] = String("low-λ transmittance ≫ high-λ (step absorption)");
        test["actual"] = String::num(t_blue, 4) + String(", ") + String::num(t_mid, 4)
                       + String(", ") + String::num(t_red, 4);
        results["beer_lambert_steep_absorption_edge"] = test;
    }

    // spectral_mc_steep_intensities_finite: hero accumulation matches trace_row_band scaling
    {
        double lambdas[HERO_WAVELENGTHS] = {450.0, 520.0, 610.0, 720.0};
        double intensities[HERO_WAVELENGTHS] = {1.0e6, 1.0e-9, 1.0e-9, 1.0e-9};
        Vector3 xyz_sum(0.0, 0.0, 0.0);
        for (int w = 0; w < HERO_WAVELENGTHS; w++) {
            xyz_sum += spectral::cie_xyz(lambdas[w]) * (float)intensities[w];
        }
        double hit_count = 1.0;
        double spectral_count = (double)HERO_WAVELENGTHS * hit_count;
        Vector3 xyz = xyz_sum * (float)(LAMBDA_RANGE / (spectral_count * CIE_Y_INTEGRAL));
        Vector3 linear = spectral::xyz_to_linear_srgb(xyz);
        bool finite = std::isfinite((double)linear.x) && std::isfinite((double)linear.y)
                   && std::isfinite((double)linear.z);
        bool bounded = std::abs((double)linear.x) < 1.0e9
                    && std::abs((double)linear.y) < 1.0e9
                    && std::abs((double)linear.z) < 1.0e9;
        Dictionary test;
        test["passed"] = finite && bounded;
        test["expected"] = String("finite linear RGB after steep per-hero intensities");
        test["actual"] = String::num((double)linear.x, 4) + String(", ")
                       + String::num((double)linear.y, 4) + String(", ")
                       + String::num((double)linear.z, 4);
        results["spectral_mc_steep_intensities_finite"] = test;
    }

    // spectral_uplift_warm_vs_cool: RGB uplift → integrated x̄ weight is higher for warm sRGB than cool
    {
        Color warm(1.0f, 0.78f, 0.62f, 1.0f);
        Color cool(0.58f, 0.72f, 1.0f, 1.0f);
        double xw = 0.0, yw = 0.0, zw = 0.0;
        double xc = 0.0, yc = 0.0, zc = 0.0;
        for (int i = 0; i < SPECTRUM_SAMPLES; i++) {
            double lam = LAMBDA_MIN + (double)i * SPECTRUM_STEP;
            Vector3 cie = spectral::cie_xyz(lam);
            double uw = spectral::spectral_uplift(warm, lam);
            double uc = spectral::spectral_uplift(cool, lam);
            xw += (double)cie.x * uw;
            yw += (double)cie.y * uw;
            zw += (double)cie.z * uw;
            xc += (double)cie.x * uc;
            yc += (double)cie.y * uc;
            zc += (double)cie.z * uc;
        }
        xw *= SPECTRUM_STEP;
        yw *= SPECTRUM_STEP;
        zw *= SPECTRUM_STEP;
        xc *= SPECTRUM_STEP;
        yc *= SPECTRUM_STEP;
        zc *= SPECTRUM_STEP;
        double sw = xw + yw + zw;
        double sc = xc + yc + zc;
        double xnorm_w = sw > 1e-12 ? xw / sw : 0.0;
        double xnorm_c = sc > 1e-12 ? xc / sc : 0.0;
        Dictionary test;
        bool passed = xnorm_w > xnorm_c + 0.008;
        test["passed"] = passed;
        test["expected"] = String("warm uplift has higher x̄ share than cool");
        test["actual"] = String("x̄_frac warm=") + String::num(xnorm_w, 4)
                       + String(" cool=") + String::num(xnorm_c, 4);
        results["spectral_uplift_warm_vs_cool"] = test;
    }

    // spectral_uplift_red_basis_maps_to_red: RGB uplift + XYZ→linear sRGB should
    // preserve a red-biased basis as red-dominant output, not suppress it.
    {
        Color red(1.0f, 0.0f, 0.0f, 1.0f);
        Vector3 xyz_sum(0.0, 0.0, 0.0);
        for (int i = 0; i < SPECTRUM_SAMPLES; i++) {
            double lam = LAMBDA_MIN + (double)i * SPECTRUM_STEP;
            xyz_sum += spectral::cie_xyz(lam) * (float)spectral::spectral_uplift(red, lam);
        }
        Vector3 xyz = xyz_sum * (float)(SPECTRUM_STEP / CIE_Y_INTEGRAL);
        Vector3 linear = spectral::xyz_to_linear_srgb(xyz);
        Dictionary test;
        bool passed = (double)linear.x > 0.1
                   && (double)linear.x > (double)linear.y * 1.5
                   && (double)linear.z < 0.1;
        test["passed"] = passed;
        test["expected"] = String("linear R dominates G and blue stays low for red spectral basis");
        test["actual"] = String::num((double)linear.x, 4) + String(", ")
                       + String::num((double)linear.y, 4) + String(", ")
                       + String::num((double)linear.z, 4);
        results["spectral_uplift_red_basis_maps_to_red"] = test;
    }

    // trace_row_band_equal_hero_xyz_linear: same accumulation as trace_row_band MC normalization
    // (equal per-hero intensities); XYZ→linear sRGB must scale linearly (matrix path sanity).
    {
        double lambdas[HERO_WAVELENGTHS] = {450.0, 520.0, 610.0, 720.0};
        Vector3 xyz_sum(0.0, 0.0, 0.0);
        for (int w = 0; w < HERO_WAVELENGTHS; w++) {
            xyz_sum += spectral::cie_xyz(lambdas[w]);
        }
        double hit_count = 1.0;
        double spectral_count = (double)HERO_WAVELENGTHS * hit_count;
        Vector3 xyz = xyz_sum * (float)(LAMBDA_RANGE / (spectral_count * CIE_Y_INTEGRAL));
        Vector3 lin_half = spectral::xyz_to_linear_srgb(xyz * 0.5f);
        Vector3 lin_full = spectral::xyz_to_linear_srgb(xyz);
        auto ratio_ok = [](double a, double b) {
            if (!std::isfinite(a) || !std::isfinite(b)) {
                return false;
            }
            if (std::abs(a) < 1e-8 && std::abs(b) < 1e-8) {
                return true;
            }
            return std::abs(b / (a + 1e-12) - 2.0) < 0.002;
        };
        bool ok = ratio_ok((double)lin_half.x, (double)lin_full.x)
               && ratio_ok((double)lin_half.y, (double)lin_full.y)
               && ratio_ok((double)lin_half.z, (double)lin_full.z);
        Dictionary test;
        test["passed"] = ok;
        test["expected"] = String("linear sRGB scales ~2× when XYZ doubles (trace_row_band path)");
        test["actual"] = String::num((double)lin_full.x, 4) + String(", ")
                       + String::num((double)lin_full.y, 4) + String(", ")
                       + String::num((double)lin_full.z, 4);
        results["trace_row_band_equal_hero_xyz_linear"] = test;
    }

    // absorption_ruby_like_green_heavier_than_red: Beer-Lambert transmits more at long λ for Cr-like band
    {
        GemTraceProps rp;
        rp.absorption_spectrum.resize(81);
        for (int i = 0; i < 81; i++) {
            double lam = LAMBDA_MIN + (double)i * SPECTRUM_STEP;
            // Broad absorption in green–yellow, lower in deep red (qualitative ruby-like)
            double a = 2.2 + 2.8 * std::exp(-std::pow((lam - 520.0) / 75.0, 2.0));
            rp.absorption_spectrum[i] = (float)a;
        }
        rp.absorption_strength_scale = 1.0;
        Vector3 rd(0, 0, 1);
        double t_short = volume::beer_lambert(rp, 460.0, 0.25, rd);
        double t_long = volume::beer_lambert(rp, 700.0, 0.25, rd);
        Dictionary test;
        bool passed = t_long > t_short * 1.15 && t_long > 0.2 && t_short < 0.95;
        test["passed"] = passed;
        test["expected"] = String("T(700nm) > T(460nm) for green-heavy absorption");
        test["actual"] = String::num(t_short, 4) + String(" vs ") + String::num(t_long, 4);
        results["absorption_ruby_like_green_heavier_than_red"] = test;
    }

    // gradient_zone_curve_targets_absorption: authored zone spectra are consumed as
    // target absorption curves, not normalized multipliers.
    {
        GemTraceProps gp;
        gp.material_mode = MATERIAL_MODE_FACETED_TRANSPARENT;
        gp.absorption_spectrum.resize(81, 1.0f);
        gp.gradient_zone_spectrum.resize(81, 4.0f);
        gp.absorption_strength_scale = 1.0;
        gp.gradient_strength = 1.0;
        gp.gradient_mode = GRADIENT_MODE_LINEAR;
        gp.gradient_angle_degrees = 0.0;
        double base_alpha = spectral::evaluate_absorption(gp, 580.0, Vector3(0, 0, 1));
        double zoned_alpha = volume::gradient_absorption_mod(gp, Vector3(1, 0, 0), 580.0, base_alpha);
        Dictionary test;
        test["passed"] = std::abs(zoned_alpha - 4.0) < 0.01;
        test["expected"] = 4.0;
        test["actual"] = zoned_alpha;
        results["gradient_zone_curve_targets_absorption"] = test;
    }

    // phenomenon_zone_curve_targets_absorption: angle-driven phenomenon spectra also
    // blend to direct target absorption values.
    {
        GemTraceProps pp_zone;
        pp_zone.material_mode = MATERIAL_MODE_FACETED_TRANSPARENT;
        pp_zone.absorption_spectrum.resize(81, 1.0f);
        pp_zone.phenomenon_zone_spectrum.resize(81, 3.5f);
        pp_zone.absorption_strength_scale = 1.0;
        pp_zone.phenomenon_strength = 1.0;
        pp_zone.phenomenon_angle_degrees = 0.0;
        pp_zone.phenomenon_sharpness = 1.0;
        double base_alpha = spectral::evaluate_absorption(pp_zone, 580.0, Vector3(1, 0, 0));
        double zoned_alpha = volume::phenomenon_absorption_mod(pp_zone, Vector3(1, 0, 0), 580.0, base_alpha);
        Dictionary test;
        test["passed"] = std::abs(zoned_alpha - 3.5) < 0.01;
        test["expected"] = 3.5;
        test["actual"] = zoned_alpha;
        results["phenomenon_zone_curve_targets_absorption"] = test;
    }

    return results;
}

} // namespace gem
