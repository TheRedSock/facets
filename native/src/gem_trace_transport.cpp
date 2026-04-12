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
    Vector3 micro_normal = fresnel::sample_ggx(normal, roughness, rng);
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
// Single-wavelength path tracer (NEE at dielectric surfaces)
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
    double throughput = 1.0;
    double result = 0.0;
    bool inside_gem = false;
    int prev_triangle = -1;

    for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {

        if (inside_gem) {
            // ----- Volumetric transport (inside gem) -----
            double sigma_s = props.effective_scattering();

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
                    props, lambda_nm, scatter_dist, direction,
                    obj_pos, absorb_mult);
                volume::try_fluorescence(props, lambda_nm, rng);
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
                    props, lambda_nm, surface_dist, direction,
                    obj_pos, absorb_mult);
            }

            // --- Surface interaction (potential exit) ---
            origin = hit.position;
            prev_triangle = hit.triangle_idx;

            double eta_i = spectral::sellmeier_ior(props, lambda_nm);
            double roughness = props.effective_roughness();
            Vector3 surface_normal = hit.front_face ? hit.normal : -hit.normal;
            Vector3 micro_normal = fresnel::sample_ggx(surface_normal, roughness, rng);
            double R = fresnel::dielectric(direction, micro_normal, eta_i, AIR_IOR);

            // Attempt refraction (exit direction)
            Vector3 exit_dir = fresnel::refract(direction, micro_normal, eta_i / AIR_IOR);
            bool is_tir = (exit_dir.length_squared() < 1e-12);

            // NEE: deterministically evaluate exit contribution
            if (!is_tir) {
                double T = 1.0 - R;
                Vector3 exit_origin = hit.position + exit_dir * (float)TRACE_EPSILON;
                HitResult exit_check = scene.intersect(exit_origin, exit_dir, prev_triangle);
                if (!exit_check.did_hit) {
                    result += throughput * T
                        * environment::sample(ctx.environment, exit_dir, lambda_nm);
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
            Vector3 micro_normal = fresnel::sample_ggx(hit.normal, roughness, rng);
            double R = fresnel::dielectric(direction, micro_normal, AIR_IOR, eta_t);

            // Birefringence
            if (props.birefringence_delta_n > 1e-6 && hit.front_face) {
                if (rng.next() < 0.5) {
                    eta_t = spectral::birefringent_ior(props, lambda_nm, direction, true);
                    R = fresnel::dielectric(direction, micro_normal, AIR_IOR, eta_t);
                }
            }

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
// Multi-wavelength spectral path tracer (4-hero, NEE split).
//
// Traces a single geometric path determined by lambdas[0] (the hero).
// At each dielectric surface, the exit/entry contribution is evaluated
// deterministically for all 4 wavelengths (NEE), then the path continues
// via the non-exit direction with per-wavelength Fresnel attenuation.
//
// This eliminates the binary reflect/refract variance from the old
// stochastic branching approach. Per-wavelength effects tracked:
//   - Beer-Lambert absorption (dominant color-producing effect)
//   - Fresnel attenuation (per-wavelength, applied directly — no ratio
//     corrections needed since there's no branching)
//   - Environment spectral radiance at exit (evaluated deterministically)
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
    SpectralResult result = {};
    const double hero = lambdas[0];

    // Per-wavelength throughput. Tracks Beer-Lambert absorption and
    // Fresnel attenuation independently for each wavelength.
    // No geometric throughput separation needed — all wavelengths share
    // the same path geometry determined by the hero.
    double wl_tp[HERO_WAVELENGTHS];
    for (int w = 0; w < HERO_WAVELENGTHS; w++) wl_tp[w] = 1.0;

    bool inside_gem = false;
    int prev_triangle = -1;

    for (int bounce = 0; bounce < MAX_BOUNCES; bounce++) {

        if (inside_gem) {
            // ----- Volumetric transport (inside gem) -----
            double sigma_s = props.effective_scattering();
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
                // Normalized position for gradient/phenomenon modulation
                Vector3 obj_pos = (ctx.radius > 0.0001)
                    ? origin / (float)ctx.radius : Vector3(0, 0, 0);
                for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                    wl_tp[w] *= volume::beer_lambert_zoned(
                        props, lambdas[w], scatter_dist, direction,
                        obj_pos, absorb_mult);
                }
                double fl = hero;
                volume::try_fluorescence(props, fl, rng);
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
                        props, lambdas[w], surface_dist, direction,
                        obj_pos, absorb_mult);
                }
            }

            // --- Surface interaction (potential exit) ---
            origin = hit.position;
            prev_triangle = hit.triangle_idx;

            double roughness = props.effective_roughness();
            Vector3 surface_normal = hit.front_face ? hit.normal : -hit.normal;
            Vector3 micro_normal = fresnel::sample_ggx(surface_normal, roughness, rng);

            // Compute hero exit direction for TIR check and NEE shadow ray
            double eta_hero = spectral::sellmeier_ior(props, hero);
            Vector3 exit_dir = fresnel::refract(
                direction, micro_normal, eta_hero / AIR_IOR);
            bool is_tir = (exit_dir.length_squared() < 1e-12);

            // Compute per-wavelength Fresnel reflectance
            double R_w[HERO_WAVELENGTHS];
            for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                double eta_w = spectral::sellmeier_ior(props, lambdas[w]);
                R_w[w] = fresnel::dielectric(direction, micro_normal, eta_w, AIR_IOR);
            }

            // NEE: deterministically evaluate exit contribution
            if (!is_tir) {
                Vector3 exit_origin = hit.position + exit_dir * (float)TRACE_EPSILON;
                HitResult exit_check = scene.intersect(
                    exit_origin, exit_dir, prev_triangle);
                if (!exit_check.did_hit) {
                    // Unoccluded exit — sample environment for all wavelengths
                    for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                        double T_w = 1.0 - R_w[w];
                        double env = environment::sample(
                            ctx.environment, exit_dir, lambdas[w]);
                        result.intensities[w] += wl_tp[w] * T_w * env;
                    }
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
            Vector3 micro_normal = fresnel::sample_ggx(hit.normal, roughness, rng);

            // Hero IOR for geometry decisions (refraction direction)
            double eta_hero_t = spectral::sellmeier_ior(props, hero);

            // Birefringence (hero only — affects path geometry)
            if (props.birefringence_delta_n > 1e-6 && hit.front_face) {
                if (rng.next() < 0.5) {
                    eta_hero_t = spectral::birefringent_ior(
                        props, hero, direction, true);
                }
            }

            // Compute per-wavelength Fresnel reflectance
            double R_w[HERO_WAVELENGTHS];
            for (int w = 0; w < HERO_WAVELENGTHS; w++) {
                double eta_w = spectral::sellmeier_ior(props, lambdas[w]);
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
                            ctx.environment, reflect_dir, lambdas[w]);
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
        // Terminates paths when max per-wavelength throughput drops below
        // 0.1%, losing negligible energy. No 1/survival division means
        // throughput is always bounded and monotonically decreasing.
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

}} // namespace gem::transport
