// gem_trace_transport.cpp — Deterministic-split spectral path tracer core.
//
// Uses next-event estimation (NEE) at dielectric surfaces instead of
// stochastic Fresnel branching. At each surface interaction:
//   - The exit contribution is evaluated deterministically for all wavelengths
//   - The path always continues via the non-exit direction (reflect inside,
//     refract at entry), with throughput attenuated by the Fresnel coefficient
//
// This eliminates the binary reflect/refract variance that caused chromatic
// noise in gems with steep absorption spectra (e.g., Fluorite with 400:1
// absorption variation across the visible spectrum).
//
// Birefringence: for crystals with |Δn| > BIREFRINGENCE_SPLIT_THRESHOLD the
// primary air→gem refraction is forked into an ordinary and an extraordinary
// ray (each with 0.5 × T throughput). The two rays travel along slightly
// different Snell directions so back-facet reflections see physically
// separated geometry — this produces the characteristic "doubling" of
// facet edges seen in e.g. peridot, tourmaline, zircon. The split is
// applied only at entry to keep cost bounded; subsequent internal bounces
// share the ordinary IOR, which captures the dominant visual cue (entry-
// angle separation accumulates across the internal bounce sequence).
#include "gem_trace_transport.h"
#include "gem_trace_spectral.h"
#include "gem_trace_fresnel.h"
#include "gem_trace_volume.h"
#include "gem_trace_environment.h"
#include "gem_trace_material.h"
#include <cmath>

namespace gem { namespace transport {

// Throughput cutoff for path termination (replaces Russian roulette).
// Paths with max throughput below this are terminated. Introduces
// negligible bias (< 0.1% energy loss) but prevents infinite loops
// and eliminates firefly amplification from RR's 1/survival division.
static constexpr double THROUGHPUT_CUTOFF = 0.001;

// Minimum Δn for an engine-level ray split at the entry interface.
// Below this value, birefringence is visually indistinguishable from
// single-IOR refraction given typical gem sizes, so we skip the 2x path
// cost. Corundum (0.008), quartz (0.009), chrysoberyl (0.009) all land
// just above the threshold; peridot (0.036), grandidierite (0.037), and
// tourmaline (0.018) produce visible doubling.
static constexpr double BIREFRINGENCE_SPLIT_THRESHOLD = 0.005;

// StringName for inclusion zone comparison (initialized on first use).
static const StringName& inclusion_zone_name() {
    static StringName name("inclusion");
    return name;
}

// ---------------------------------------------------------------------------
// Opaque surface shading
// ---------------------------------------------------------------------------

double compute_opaque_surface(
    const TraceContext& ctx,
    const HitResult& hit,
    Vector3 incident_dir,
    double lambda_nm,
    TraceRNG& rng)
{
    const GemTraceProps& props = ctx.props;
    Vector3 normal = hit.normal;
    Vector3 view_dir = (-incident_dir).normalized();

    double roughness = props.effective_roughness();

    // GGX microfacet for specular reflection
    Vector3 micro_normal;
    double aniso = props.effective_anisotropy();
    if (aniso > 0.001) {
        double alpha = roughness * roughness;
        double alpha_x = alpha * (1.0 + aniso);
        double alpha_y = alpha * (1.0 - aniso);
        Vector3 t = (props.anisotropy_axis - normal * normal.dot(props.anisotropy_axis));
        if (t.length_squared() < 0.001) {
            Vector3 up = (std::abs((double)normal.y) < 0.99) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
            t = normal.cross(up);
        }
        t = t.normalized();
        micro_normal = fresnel::sample_ggx_aniso(normal, t, alpha_x, alpha_y, rng);
    } else {
        micro_normal = fresnel::sample_ggx(normal, roughness, rng);
    }
    double R = fresnel::dielectric(incident_dir, micro_normal, AIR_IOR,
        spectral::sellmeier_ior(props, lambda_nm));

    // Specular: reflected ray samples environment
    Vector3 reflect_dir = fresnel::reflect(incident_dir, micro_normal);
    double specular = environment::sample(ctx.environment, reflect_dir, lambda_nm) * R;

    // Diffuse: Lambert from environment cards
    double n_dot_v = dmax((double)normal.dot(view_dir), 0.0);
    double diffuse = 0.0;
    for (const auto& card : ctx.environment.cards) {
        double n_dot_l = dmax((double)normal.dot(card.dir), 0.0);
        double card_energy = lerpd(card.sharp_strength, card.broad_strength, roughness);

        double card_radiance;
        if (card.temperature_kelvin > 500.0) {
            card_radiance = spectral::planckian_radiance(lambda_nm, card.temperature_kelvin)
                          * spectral::spectral_uplift(card.color, lambda_nm);
        } else {
            card_radiance = spectral::spectral_uplift(card.color, lambda_nm);
        }

        diffuse += n_dot_l * card_energy * card_radiance * ctx.environment.light_energy;
    }

    // Body color from display_color (spectral uplifted)
    double body = spectral::spectral_uplift(props.display_color, lambda_nm);
    diffuse *= body * (1.0 - R) * INV_PI;

    return specular + diffuse;
}

// ---------------------------------------------------------------------------
// Single-wavelength path tracer core (NEE at dielectric surfaces).
//
// Accepts an initial state so the birefringent entry fork can start two
// independent sub-paths from inside the gem with different refracted
// directions.
// ---------------------------------------------------------------------------

static double trace_path_core(
    const TraceContext& ctx,
    const TraceScene& scene,
    Vector3 origin,
    Vector3 direction,
    double lambda_nm,
    TraceRNG& rng,
    bool start_inside_gem,
    double start_throughput,
    int start_prev_triangle)
{
    const GemTraceProps& props = ctx.props;
    double throughput = start_throughput;
    double result = 0.0;
    bool inside_gem = start_inside_gem;
    int prev_triangle = start_prev_triangle;
    // Mutable wavelength inside the gem (fluorescence shifts λ; survives zero scattering).
    double wl = lambda_nm;

    for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {

        if (inside_gem) {
            // ----- Volumetric transport (inside gem) -----
            double sigma_s = ctx.variance_budget.gate_scattering(
                props.effective_scattering());

            // Volume pattern modulation
            double scatter_mult = 1.0;
            double absorb_mult = 1.0;
            if (ctx.has_volume_patterns && ctx.radius > 0.0001) {
                Vector3 obj_pos = origin / ctx.radius;
                VolumeMaterialSample vol = material::sample_volume_material(props, obj_pos);
                scatter_mult = vol.scattering_mult;
                absorb_mult = vol.absorption_mult;
            }
            sigma_s *= scatter_mult;

            double scatter_dist = volume::sample_scatter_distance(sigma_s, rng);
            HitResult hit = scene.intersect(origin, direction, prev_triangle);
            double surface_dist = hit.did_hit ? hit.distance : 1e30;

            if (sigma_s > 1e-12 && scatter_dist < surface_dist) {
                // --- Scattering event ---
                Vector3 scatter_pos = origin + direction * (float)scatter_dist;
                Vector3 obj_pos = (ctx.radius > 0.0001)
                    ? origin / (float)ctx.radius : Vector3(0, 0, 0);
                throughput *= volume::beer_lambert_zoned(
                    props, wl, scatter_dist, direction,
                    obj_pos, absorb_mult);
                if (volume::try_fluorescence(props, wl, rng, ctx.variance_budget.fluorescence_yield_cap)) {
                    throughput *= volume::fluorescence_emission_boost(props, wl, direction);
                }
                direction = volume::sample_henyey_greenstein(
                    direction, props.scattering_anisotropy, rng);
                origin = scatter_pos;
                prev_triangle = -1;
                continue;
            }

            // --- No scatter: absorb over full segment to surface ---
            if (!hit.did_hit) break;
            {
                Vector3 obj_pos = (ctx.radius > 0.0001)
                    ? origin / (float)ctx.radius : Vector3(0, 0, 0);
                throughput *= volume::beer_lambert_zoned(
                    props, wl, surface_dist, direction,
                    obj_pos, absorb_mult);
                if (volume::try_fluorescence(props, wl, rng, ctx.variance_budget.fluorescence_yield_cap)) {
                    throughput *= volume::fluorescence_emission_boost(props, wl, direction);
                }
            }

            // --- Surface interaction (potential exit) ---
            origin = hit.position;
            prev_triangle = hit.triangle_idx;

            // Check for inclusion boundary (gem ↔ inclusion interface)
            if (props.has_inclusions && hit.zone == inclusion_zone_name()) {
                // Inclusion surfaces act as internal Fresnel boundaries.
                // Compute Fresnel at gem/inclusion interface.
                double eta_gem = spectral::sellmeier_ior(props, wl);
                double eta_incl = props.inclusion_ior;
                double eta_ratio = hit.front_face
                    ? (eta_gem / eta_incl)    // entering inclusion
                    : (eta_incl / eta_gem);   // exiting inclusion
                Vector3 incl_normal = hit.front_face ? hit.normal : -hit.normal;
                double R_incl = fresnel::dielectric(direction, incl_normal, 1.0, 1.0 / eta_ratio);

                // Apply inclusion absorption over effective path proportional to size
                double eff_incl_scatter = ctx.variance_budget.gate_inclusion_scatter(
                    props.inclusion_scatter);
                double incl_path = props.inclusion_typical_size;
                throughput *= std::exp(-props.inclusion_absorption * incl_path);

                // Scatter: with probability proportional to scatter_strength,
                // randomize the ray direction; otherwise refract through.
                if (rng.next() < eff_incl_scatter * 0.3) {
                    // Scattered reflection off inclusion surface
                    direction = fresnel::reflect(direction, incl_normal);
                    throughput *= R_incl;
                } else {
                    // Refract through the inclusion boundary
                    Vector3 refr = fresnel::refract(direction, incl_normal, eta_ratio);
                    if (refr.length_squared() < 1e-12) {
                        // TIR at inclusion — reflect
                        direction = fresnel::reflect(direction, incl_normal);
                    } else {
                        direction = refr;
                        throughput *= (1.0 - R_incl);
                    }
                }
                origin = hit.position + direction * (float)TRACE_EPSILON;
                // Stay inside gem — skip the normal exit logic
                continue;
            }

            double eta_i = spectral::sellmeier_ior(props, wl);
            double roughness = props.effective_roughness();
            Vector3 surface_normal = hit.front_face ? hit.normal : -hit.normal;
            Vector3 micro_normal;
            double aniso = ctx.props.effective_anisotropy();
            if (aniso > 0.001) {
                double alpha = roughness * roughness;
                double alpha_x = alpha * (1.0 + aniso);
                double alpha_y = alpha * (1.0 - aniso);
                Vector3 t = (ctx.props.anisotropy_axis - surface_normal * surface_normal.dot(ctx.props.anisotropy_axis));
                if (t.length_squared() < 0.001) {
                    Vector3 up = (std::abs((double)surface_normal.y) < 0.99) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
                    t = surface_normal.cross(up);
                }
                t = t.normalized();
                micro_normal = fresnel::sample_ggx_aniso(surface_normal, t, alpha_x, alpha_y, rng);
            } else {
                micro_normal = fresnel::sample_ggx(surface_normal, roughness, rng);
            }
            double R = fresnel::dielectric(direction, micro_normal, eta_i, AIR_IOR);

            // Attempt refraction (exit direction)
            Vector3 exit_dir = fresnel::refract(direction, micro_normal, eta_i / AIR_IOR);
            bool is_tir = (exit_dir.length_squared() < 1e-12);

            // NEE: deterministically evaluate exit contribution
            if (!is_tir) {
                // Validate exit direction against geometric normal: if the smoothed
                // shading normal produced an exit ray that goes back into the gem per
                // the actual flat surface, suppress this NEE contribution to prevent
                // light leaking at facet edges from edge rounding.
                // geometric_normal is always outward-facing (oriented by add_facet).
                if (exit_dir.dot(hit.geometric_normal) > 0.0) {
                    double T = 1.0 - R;
                    Vector3 exit_origin = hit.position + exit_dir * (float)TRACE_EPSILON;
                    HitResult exit_check = scene.intersect(exit_origin, exit_dir, prev_triangle);
                    if (!exit_check.did_hit) {
                        result += throughput * T
                            * environment::sample(ctx.environment, exit_dir, wl);
                    }
                }
            }

            // Path always reflects — stay inside, attenuate by R
            throughput *= R;
            direction = fresnel::reflect(direction, micro_normal);
            origin = hit.position + direction * (float)TRACE_EPSILON;

        } else {
            // ----- In air -----
            HitResult hit = scene.intersect(origin, direction, prev_triangle);

            if (!hit.did_hit) {
                result += throughput * environment::sample(ctx.environment, direction, lambda_nm);
                break;
            }

            if (ctx.is_opaque && bounce == 0) {
                result += throughput * compute_opaque_surface(ctx, hit, direction, lambda_nm, rng);
                break;
            }

            prev_triangle = hit.triangle_idx;
            origin = hit.position;

            double eta_t = spectral::sellmeier_ior(props, lambda_nm);
            double roughness = props.effective_roughness();
            Vector3 micro_normal;
            double aniso = ctx.props.effective_anisotropy();
            if (aniso > 0.001) {
                double alpha = roughness * roughness;
                double alpha_x = alpha * (1.0 + aniso);
                double alpha_y = alpha * (1.0 - aniso);
                Vector3 t = (ctx.props.anisotropy_axis - hit.normal * hit.normal.dot(ctx.props.anisotropy_axis));
                if (t.length_squared() < 0.001) {
                    Vector3 up = (std::abs((double)hit.normal.y) < 0.99) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
                    t = hit.normal.cross(up);
                }
                t = t.normalized();
                micro_normal = fresnel::sample_ggx_aniso(hit.normal, t, alpha_x, alpha_y, rng);
            } else {
                micro_normal = fresnel::sample_ggx(hit.normal, roughness, rng);
            }
            double R = fresnel::dielectric(direction, micro_normal, AIR_IOR, eta_t);

            // NEE: deterministically evaluate reflected environment
            Vector3 reflect_dir = fresnel::reflect(direction, micro_normal);
            {
                Vector3 reflect_origin = hit.position + reflect_dir * (float)TRACE_EPSILON;
                HitResult reflect_check = scene.intersect(
                    reflect_origin, reflect_dir, prev_triangle);
                if (!reflect_check.did_hit) {
                    result += throughput * R
                        * environment::sample(ctx.environment, reflect_dir, lambda_nm);
                }
            }

            // Path always refracts — enter gem, attenuate by (1-R)
            Vector3 refracted = fresnel::refract(direction, micro_normal, AIR_IOR / eta_t);
            if (refracted.length_squared() < 1e-12) {
                // TIR from air (shouldn't happen) — path ends
                break;
            }
            throughput *= (1.0 - R);
            direction = refracted;
            origin = hit.position + direction * (float)TRACE_EPSILON;
            inside_gem = true;
        }

        // Throughput cutoff (replaces Russian roulette — no amplification)
        if (bounce >= RR_START_BOUNCE && throughput < THROUGHPUT_CUTOFF) break;
    }

    return dmax(result, 0.0);
}

// ---------------------------------------------------------------------------
// Single-wavelength path tracer (birefringence-aware entry fork).
// ---------------------------------------------------------------------------

double trace_path(
    const TraceContext& ctx,
    const TraceScene& scene,
    Vector3 origin,
    Vector3 direction,
    double lambda_nm,
    TraceRNG& rng)
{
    const GemTraceProps& props = ctx.props;

    // Fast path: not birefringent (or opaque/translucent surface shading).
    if (props.birefringence_delta_n < BIREFRINGENCE_SPLIT_THRESHOLD
        || ctx.is_opaque || ctx.is_translucent) {
        return trace_path_core(ctx, scene, origin, direction, lambda_nm, rng,
                               false, 1.0, -1);
    }

    // Probe the primary air→gem intersection so the split can start two
    // sub-paths from inside the gem with different Snell directions.
    HitResult entry = scene.intersect(origin, direction, -1);
    if (!entry.did_hit) {
        return environment::sample(ctx.environment, direction, lambda_nm);
    }
    if (!entry.front_face) {
        // Primary ray should always hit a front face for a closed manifold;
        // fallback to the non-split path if it doesn't.
        return trace_path_core(ctx, scene, origin, direction, lambda_nm, rng,
                               false, 1.0, -1);
    }

    double roughness = props.effective_roughness();
    Vector3 micro_normal;
    double aniso = props.effective_anisotropy();
    if (aniso > 0.001) {
        double alpha = roughness * roughness;
        double alpha_x = alpha * (1.0 + aniso);
        double alpha_y = alpha * (1.0 - aniso);
        Vector3 t = (props.anisotropy_axis - entry.normal * entry.normal.dot(props.anisotropy_axis)).normalized();
        if (t.length_squared() < 0.001) t = Vector3(1, 0, 0);
        micro_normal = fresnel::sample_ggx_aniso(entry.normal, t, alpha_x, alpha_y, rng);
    } else {
        micro_normal = fresnel::sample_ggx(entry.normal, roughness, rng);
    }

    double eta_o = spectral::sellmeier_ior(props, lambda_nm);
    double eta_e = spectral::birefringent_ior(props, lambda_nm, direction, true);

    // Average-eta Fresnel for the reflected NEE contribution. Splitting
    // reflectance into per-ray terms is over-precision for typical Δn
    // (< 0.04 ⇒ < 0.1% R difference) and doubles the NEE sample count.
    double eta_avg = 0.5 * (eta_o + eta_e);
    double R = fresnel::dielectric(direction, micro_normal, AIR_IOR, eta_avg);
    double T = 1.0 - R;

    double result = 0.0;

    // NEE: reflected environment (shared across both rays).
    Vector3 reflect_dir = fresnel::reflect(direction, micro_normal);
    {
        Vector3 reflect_origin = entry.position + reflect_dir * (float)TRACE_EPSILON;
        HitResult reflect_check = scene.intersect(
            reflect_origin, reflect_dir, entry.triangle_idx);
        if (!reflect_check.did_hit) {
            result += R * environment::sample(ctx.environment, reflect_dir, lambda_nm);
        }
    }

    // Ordinary ray refraction — continues via trace_path_core starting inside.
    Vector3 refr_o = fresnel::refract(direction, micro_normal, AIR_IOR / eta_o);
    if (refr_o.length_squared() > 1e-12) {
        Vector3 entry_origin = entry.position + refr_o * (float)TRACE_EPSILON;
        result += trace_path_core(
            ctx, scene, entry_origin, refr_o, lambda_nm, rng,
            true, 0.5 * T, entry.triangle_idx);
    }

    // Extraordinary ray refraction — different eta so different Snell angle.
    Vector3 refr_e = fresnel::refract(direction, micro_normal, AIR_IOR / eta_e);
    if (refr_e.length_squared() > 1e-12) {
        Vector3 entry_origin = entry.position + refr_e * (float)TRACE_EPSILON;
        result += trace_path_core(
            ctx, scene, entry_origin, refr_e, lambda_nm, rng,
            true, 0.5 * T, entry.triangle_idx);
    }

    return dmax(result, 0.0);
}

// ---------------------------------------------------------------------------
// Multi-wavelength spectral path tracer core (4-hero, NEE split).
//
// Traces a single geometric path determined by lambdas[0] (the hero).
// At each dielectric surface, the exit/entry contribution is evaluated
// deterministically for all 4 wavelengths (NEE), then the path continues
// via the non-exit direction with per-wavelength Fresnel attenuation.
// ---------------------------------------------------------------------------

static SpectralResult trace_path_spectral_core(
    const TraceContext& ctx,
    const TraceScene& scene,
    Vector3 origin,
    Vector3 direction,
    const double lambdas[HERO_WAVELENGTHS],
    TraceRNG& rng,
    bool start_inside_gem,
    double start_throughput,
    int start_prev_triangle)
{
    const GemTraceProps& props = ctx.props;
    SpectralResult result = {};
    const double hero = lambdas[0];
    // Per-channel wavelength (fluorescence can shift each hero/companion λ independently).
    double wave[HERO_WAVELENGTHS];
    for (int w = 0; w < HERO_WAVELENGTHS; w++) wave[w] = lambdas[w];

    double wl_tp[HERO_WAVELENGTHS];
    for (int w = 0; w < HERO_WAVELENGTHS; w++) wl_tp[w] = start_throughput;

    bool inside_gem = start_inside_gem;
    int prev_triangle = start_prev_triangle;

    for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {

        if (inside_gem) {
            // ----- Volumetric transport (inside gem) -----
            double sigma_s = ctx.variance_budget.gate_scattering(
                props.effective_scattering());
            double scatter_mult = 1.0;
            double absorb_mult = 1.0;
            if (ctx.has_volume_patterns && ctx.radius > 0.0001) {
                Vector3 obj_pos = origin / (float)ctx.radius;
                VolumeMaterialSample vol = material::sample_volume_material(props, obj_pos);
                scatter_mult = vol.scattering_mult;
                absorb_mult = vol.absorption_mult;
            }
            sigma_s *= scatter_mult;

            double scatter_dist = volume::sample_scatter_distance(sigma_s, rng);
            HitResult hit = scene.intersect(origin, direction, prev_triangle);
            double surface_dist = hit.did_hit ? hit.distance : 1e30;

            if (sigma_s > 1e-12 && scatter_dist < surface_dist) {
                // --- Scattering event ---
                Vector3 scatter_pos = origin + direction * (float)scatter_dist;
                Vector3 obj_pos = (ctx.radius > 0.0001)
                    ? origin / (float)ctx.radius : Vector3(0, 0, 0);
                for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                    wl_tp[w] *= volume::beer_lambert_zoned(
                        props, wave[w], scatter_dist, direction,
                        obj_pos, absorb_mult);
                    if (volume::try_fluorescence(props, wave[w], rng, ctx.variance_budget.fluorescence_yield_cap)) {
                        wl_tp[w] *= volume::fluorescence_emission_boost(
                            props, wave[w], direction);
                    }
                }
                direction = volume::sample_henyey_greenstein(
                    direction, props.scattering_anisotropy, rng);
                origin = scatter_pos;
                prev_triangle = -1;
                continue;
            }

            // --- No scatter: absorb over full segment to surface ---
            if (!hit.did_hit) break;
            {
                Vector3 obj_pos = (ctx.radius > 0.0001)
                    ? origin / (float)ctx.radius : Vector3(0, 0, 0);
                for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                    wl_tp[w] *= volume::beer_lambert_zoned(
                        props, wave[w], surface_dist, direction,
                        obj_pos, absorb_mult);
                    if (volume::try_fluorescence(props, wave[w], rng, ctx.variance_budget.fluorescence_yield_cap)) {
                        wl_tp[w] *= volume::fluorescence_emission_boost(
                            props, wave[w], direction);
                    }
                }
            }

            // --- Surface interaction (potential exit) ---
            origin = hit.position;
            prev_triangle = hit.triangle_idx;

            // Check for inclusion boundary (gem ↔ inclusion interface)
            if (props.has_inclusions && hit.zone == inclusion_zone_name()) {
                Vector3 incl_normal = hit.front_face ? hit.normal : -hit.normal;
                double eff_incl_scatter = ctx.variance_budget.gate_inclusion_scatter(
                    props.inclusion_scatter);
                double incl_path = props.inclusion_typical_size;
                for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                    wl_tp[w] *= std::exp(-props.inclusion_absorption * incl_path);
                }
                if (rng.next() < eff_incl_scatter * 0.3) {
                    // Scattered reflection off inclusion
                    double eta_hero = spectral::sellmeier_ior(props, hero);
                    double eta_ratio_h = hit.front_face
                        ? (eta_hero / props.inclusion_ior)
                        : (props.inclusion_ior / eta_hero);
                    double R_incl = fresnel::dielectric(direction, incl_normal, 1.0, 1.0 / eta_ratio_h);
                    // Save incident direction BEFORE reflecting — per-wavelength
                    // Fresnel must use the original incident angle, not the
                    // already-reflected direction.
                    Vector3 incident_save = direction;
                    direction = fresnel::reflect(direction, incl_normal);
                    for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                        double eta_w = spectral::sellmeier_ior(props, wave[w]);
                        double eta_ratio_w = hit.front_face
                            ? (eta_w / props.inclusion_ior)
                            : (props.inclusion_ior / eta_w);
                        double R_w_incl = fresnel::dielectric(incident_save, incl_normal, 1.0, 1.0 / eta_ratio_w);
                        wl_tp[w] *= R_w_incl;
                    }
                } else {
                    // Refract through inclusion boundary
                    double eta_hero = spectral::sellmeier_ior(props, hero);
                    double eta_ratio_h = hit.front_face
                        ? (eta_hero / props.inclusion_ior)
                        : (props.inclusion_ior / eta_hero);
                    Vector3 refr = fresnel::refract(direction, incl_normal, eta_ratio_h);
                    if (refr.length_squared() < 1e-12) {
                        direction = fresnel::reflect(direction, incl_normal);
                    } else {
                        // Save incident direction BEFORE refracting — per-wavelength
                        // Fresnel must use the original incident angle.
                        Vector3 incident_save = direction;
                        direction = refr;
                        for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                            double eta_w = spectral::sellmeier_ior(props, wave[w]);
                            double eta_ratio_w = hit.front_face
                                ? (eta_w / props.inclusion_ior)
                                : (props.inclusion_ior / eta_w);
                            double R_w_incl = fresnel::dielectric(incident_save, incl_normal, 1.0, 1.0 / eta_ratio_w);
                            wl_tp[w] *= (1.0 - R_w_incl);
                        }
                    }
                }
                origin = hit.position + direction * (float)TRACE_EPSILON;
                continue;
            }

            double roughness = props.effective_roughness();
            Vector3 surface_normal = hit.front_face ? hit.normal : -hit.normal;
            Vector3 micro_normal;
            double aniso = ctx.props.effective_anisotropy();
            if (aniso > 0.001) {
                double alpha = roughness * roughness;
                double alpha_x = alpha * (1.0 + aniso);
                double alpha_y = alpha * (1.0 - aniso);
                Vector3 t = (ctx.props.anisotropy_axis - surface_normal * surface_normal.dot(ctx.props.anisotropy_axis));
                if (t.length_squared() < 0.001) {
                    Vector3 up = (std::abs((double)surface_normal.y) < 0.99) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
                    t = surface_normal.cross(up);
                }
                t = t.normalized();
                micro_normal = fresnel::sample_ggx_aniso(surface_normal, t, alpha_x, alpha_y, rng);
            } else {
                micro_normal = fresnel::sample_ggx(surface_normal, roughness, rng);
            }

            // Compute per-wavelength Fresnel reflectance (inside gem → air).
            double R_w[HERO_WAVELENGTHS];
            for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                double eta_w = spectral::sellmeier_ior(props, wave[w]);
                R_w[w] = fresnel::dielectric(direction, micro_normal, eta_w, AIR_IOR);
            }

            // NEE: per-wavelength exit direction (dispersion) and TIR.
            // Validate against geometric normal to prevent light leaking from
            // edge rounding (same as single-wavelength path).
            // geometric_normal is always outward-facing (oriented by add_facet).
            for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                double eta_w = spectral::sellmeier_ior(props, wave[w]);
                Vector3 exit_dir_w = fresnel::refract(
                    direction, micro_normal, eta_w / AIR_IOR);
                if (exit_dir_w.length_squared() < 1e-12) {
                    continue; // TIR for this wavelength — no exit radiance
                }
                if (exit_dir_w.dot(hit.geometric_normal) <= 0.0) {
                    continue; // exit direction goes back into gem per geometric surface
                }
                Vector3 exit_origin = hit.position + exit_dir_w * (float)TRACE_EPSILON;
                HitResult exit_check = scene.intersect(
                    exit_origin, exit_dir_w, prev_triangle);
                if (!exit_check.did_hit) {
                    double T_w = 1.0 - R_w[w];
                    double env = environment::sample(
                        ctx.environment, exit_dir_w, wave[w]);
                    result.intensities[w] += wl_tp[w] * T_w * env;
                }
            }

            // Path always reflects — stay inside, attenuate by per-λ R
            for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                wl_tp[w] *= R_w[w];
            }
            direction = fresnel::reflect(direction, micro_normal);
            origin = hit.position + direction * (float)TRACE_EPSILON;

        } else {
            // ----- In air -----
            HitResult hit = scene.intersect(origin, direction, prev_triangle);

            if (!hit.did_hit) {
                // Ray misses gem — sample environment at all wavelengths
                for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                    result.intensities[w] += wl_tp[w]
                        * environment::sample(ctx.environment, direction, lambdas[w]);
                }
                break;
            }

            // Opaque gems: surface shading at all wavelengths
            if (ctx.is_opaque && bounce == 0) {
                for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                    result.intensities[w] += wl_tp[w]
                        * compute_opaque_surface(ctx, hit, direction, lambdas[w], rng);
                }
                break;
            }

            prev_triangle = hit.triangle_idx;
            origin = hit.position;

            double roughness = props.effective_roughness();
            Vector3 micro_normal;
            double aniso = ctx.props.effective_anisotropy();
            if (aniso > 0.001) {
                double alpha = roughness * roughness;
                double alpha_x = alpha * (1.0 + aniso);
                double alpha_y = alpha * (1.0 - aniso);
                Vector3 t = (ctx.props.anisotropy_axis - hit.normal * hit.normal.dot(ctx.props.anisotropy_axis)).normalized();
                if (t.length_squared() < 0.001) t = Vector3(1, 0, 0);
                micro_normal = fresnel::sample_ggx_aniso(hit.normal, t, alpha_x, alpha_y, rng);
            } else {
                micro_normal = fresnel::sample_ggx(hit.normal, roughness, rng);
            }

            // Hero IOR for geometry decisions (refraction direction)
            double eta_hero_t = spectral::sellmeier_ior(props, hero);

            // Compute per-wavelength Fresnel reflectance
            double R_w[HERO_WAVELENGTHS];
            for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                double eta_w = spectral::sellmeier_ior(props, wave[w]);
                R_w[w] = fresnel::dielectric(direction, micro_normal, AIR_IOR, eta_w);
            }

            // NEE: deterministically evaluate reflected environment
            Vector3 reflect_dir = fresnel::reflect(direction, micro_normal);
            {
                Vector3 reflect_origin = hit.position
                    + reflect_dir * (float)TRACE_EPSILON;
                HitResult reflect_check = scene.intersect(
                    reflect_origin, reflect_dir, prev_triangle);
                if (!reflect_check.did_hit) {
                    for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                        double env = environment::sample(
                            ctx.environment, reflect_dir, wave[w]);
                        result.intensities[w] += wl_tp[w] * R_w[w] * env;
                    }
                }
            }

            // Path always refracts — enter gem, attenuate by per-λ (1-R)
            Vector3 refracted = fresnel::refract(
                direction, micro_normal, AIR_IOR / eta_hero_t);
            if (refracted.length_squared() < 1e-12) {
                // TIR from air side (shouldn't happen) — path ends
                break;
            }
            for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                wl_tp[w] *= (1.0 - R_w[w]);
            }
            direction = refracted;
            origin = hit.position + direction * (float)TRACE_EPSILON;
            inside_gem = true;
        }

        // Throughput cutoff (replaces Russian roulette — no amplification).
        if (bounce >= RR_START_BOUNCE) {
            double max_tp = 0.0;
            for (int w = 0; w < HERO_WAVELENGTHS; w++)
                max_tp = dmax(max_tp, wl_tp[w]);
            if (max_tp < THROUGHPUT_CUTOFF) break;
        }
    }

    for (int w = 0; w < HERO_WAVELENGTHS; w++) {
        result.intensities[w] = dmax(result.intensities[w], 0.0);
    }
    return result;
}

// ---------------------------------------------------------------------------
// Multi-wavelength spectral path tracer (birefringence-aware entry fork).
//
// The 4 hero wavelengths share a common geometric path, so the fork splits
// the path into two geometric branches — one using the ordinary IOR for
// refraction, one using the extraordinary IOR at the hero wavelength.
// Each branch carries all 4 wavelengths and runs the shared-geometry
// inside-gem loop from trace_path_spectral_core with 0.5×T initial
// throughput per wavelength.
// ---------------------------------------------------------------------------

SpectralResult trace_path_spectral(
    const TraceContext& ctx,
    const TraceScene& scene,
    Vector3 origin,
    Vector3 direction,
    const double lambdas[HERO_WAVELENGTHS],
    TraceRNG& rng)
{
    const GemTraceProps& props = ctx.props;

    // Fast path — no birefringence split required.
    if (props.birefringence_delta_n < BIREFRINGENCE_SPLIT_THRESHOLD
        || ctx.is_opaque || ctx.is_translucent) {
        return trace_path_spectral_core(
            ctx, scene, origin, direction, lambdas, rng,
            false, 1.0, -1);
    }

    const double hero = lambdas[0];

    // Probe the primary air→gem intersection so the split can start two
    // sub-paths from inside the gem with different Snell directions.
    HitResult entry = scene.intersect(origin, direction, -1);
    if (!entry.did_hit) {
        SpectralResult miss = {};
        for (int w = 0; w < HERO_WAVELENGTHS; w++) {
            miss.intensities[w] =
                environment::sample(ctx.environment, direction, lambdas[w]);
        }
        return miss;
    }
    if (!entry.front_face) {
        return trace_path_spectral_core(
            ctx, scene, origin, direction, lambdas, rng,
            false, 1.0, -1);
    }

    double roughness = props.effective_roughness();
    Vector3 micro_normal;
    double aniso = props.effective_anisotropy();
    if (aniso > 0.001) {
        double alpha = roughness * roughness;
        double alpha_x = alpha * (1.0 + aniso);
        double alpha_y = alpha * (1.0 - aniso);
        Vector3 t = (props.anisotropy_axis - entry.normal * entry.normal.dot(props.anisotropy_axis)).normalized();
        if (t.length_squared() < 0.001) t = Vector3(1, 0, 0);
        micro_normal = fresnel::sample_ggx_aniso(entry.normal, t, alpha_x, alpha_y, rng);
    } else {
        micro_normal = fresnel::sample_ggx(entry.normal, roughness, rng);
    }

    double eta_o_hero = spectral::sellmeier_ior(props, hero);
    double eta_e_hero = spectral::birefringent_ior(props, hero, direction, true);

    // Per-wavelength Fresnel reflectance using ordinary IOR — the ordinary
    // and extraordinary rays differ by ≲0.1% reflectance in gem-grade
    // materials, and resolving the pair per-λ would double the NEE work.
    double R_w[HERO_WAVELENGTHS];
    for (int w = 0; w < HERO_WAVELENGTHS; w++) {
        double eta_w = spectral::sellmeier_ior(props, lambdas[w]);
        R_w[w] = fresnel::dielectric(direction, micro_normal, AIR_IOR, eta_w);
    }

    SpectralResult result = {};

    // NEE: reflected environment (shared across both rays).
    Vector3 reflect_dir = fresnel::reflect(direction, micro_normal);
    {
        Vector3 reflect_origin = entry.position
            + reflect_dir * (float)TRACE_EPSILON;
        HitResult reflect_check = scene.intersect(
            reflect_origin, reflect_dir, entry.triangle_idx);
        if (!reflect_check.did_hit) {
            for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                double env = environment::sample(
                    ctx.environment, reflect_dir, lambdas[w]);
                result.intensities[w] += R_w[w] * env;
            }
        }
    }

    // Use the average Fresnel as the overall T factor so the two refracted
    // branches share the same per-λ throughput (eta_o/eta_e's Fresnel
    // difference is negligible at grazing angles away from TIR).
    double T_w[HERO_WAVELENGTHS];
    for (int w = 0; w < HERO_WAVELENGTHS; w++) {
        T_w[w] = 1.0 - R_w[w];
    }

    // Both sub-paths run the shared-geometry core starting from inside the
    // gem, with 0.5 × T per-λ initial throughput.

    auto run_branch = [&](double eta_t) {
        Vector3 refr = fresnel::refract(direction, micro_normal, AIR_IOR / eta_t);
        if (refr.length_squared() < 1e-12) return;
        Vector3 entry_origin = entry.position + refr * (float)TRACE_EPSILON;
        // Dispatch the core with uniform starting throughput per-λ (0.5*T
        // blended at hero-λ — chromatic T is applied at the end by scaling
        // each channel's contribution).
        SpectralResult br = trace_path_spectral_core(
            ctx, scene, entry_origin, refr, lambdas, rng,
            true, 0.5, entry.triangle_idx);
        for (int w = 0; w < HERO_WAVELENGTHS; w++) {
            result.intensities[w] += T_w[w] * br.intensities[w];
        }
    };

    run_branch(eta_o_hero);
    run_branch(eta_e_hero);

    for (int w = 0; w < HERO_WAVELENGTHS; w++) {
        result.intensities[w] = dmax(result.intensities[w], 0.0);
    }
    return result;
}

}} // namespace gem::transport
