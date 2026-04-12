// gem_trace_environment.cpp — Environment sampling implementation.
#include "gem_trace_environment.h"
#include <cmath>

namespace gem { namespace environment {

// ---------------------------------------------------------------------------
// Sky gradient sampling
// ---------------------------------------------------------------------------

double sample_sky(const EnvironmentSetup& env, Vector3 dir, double lambda_nm) {
    double t = clampd((double)dir.y * 0.5 + 0.5, 0.0, 1.0);

    // Horizon glow
    Color horizon_contribution = Color(
        env.horizon.r * (float)std::exp(-(double)dir.y * (double)dir.y / (0.22 * 0.22)),
        env.horizon.g * (float)std::exp(-(double)dir.y * (double)dir.y / (0.22 * 0.22)),
        env.horizon.b * (float)std::exp(-(double)dir.y * (double)dir.y / (0.22 * 0.22)),
        1.0f);

    double ground_mix = clampd(-(double)dir.y, 0.0, 1.0);
    Color ground = color_lerp(env.ground_dark, env.ground_lift, ground_mix * 0.22);

    Color sky = color_lerp(env.sky_low, env.sky_top, (float)std::pow(t, 1.35));
    sky = color_lerp(sky, ground, ground_mix);
    Color env_color = Color(
        (sky.r + horizon_contribution.r) * (float)env.environment_energy,
        (sky.g + horizon_contribution.g) * (float)env.environment_energy,
        (sky.b + horizon_contribution.b) * (float)env.environment_energy,
        1.0f);

    return spectral::spectral_uplift(env_color, lambda_nm);
}

// ---------------------------------------------------------------------------
// Light cards sampling
// ---------------------------------------------------------------------------

double sample_cards(const EnvironmentSetup& env, Vector3 dir, double lambda_nm,
                    double roughness) {
    double total = 0.0;

    for (const auto& card : env.cards) {
        double alignment = dmax((double)dir.dot(card.dir), 0.0);
        double power = lerpd(card.sharp_power, card.broad_power, roughness);
        double strength = lerpd(card.sharp_strength, card.broad_strength, roughness);

        // Cap effective power for stochastic sampling convergence.
        // The card power controls the angular extent of the light source
        // in the environment map. High powers create narrow cones that
        // require many samples to converge — a cos^30 lobe has ~15° half-
        // width and creates 14:1 brightness variance within typical exit
        // direction spreads. cos^8 broadens to ~45° half-width, reducing
        // variance to ~2:1 within the same spread.
        // Specular highlight sharpness comes from the GGX microfacet on
        // the gem surface, not from the card's angular power.
        power = dmin(power, 8.0);

        // Gradient card: lerp from edge_color to center color
        double grad_t = std::pow(clampd(alignment, 0.0, 1.0), card.gradient_power);
        Color card_c = color_lerp(card.edge_color, card.color, grad_t);

        double card_radiance;
        if (card.temperature_kelvin > 500.0) {
            double planck = spectral::planckian_radiance(lambda_nm, card.temperature_kelvin);
            double color_mod = spectral::spectral_uplift(card_c, lambda_nm);
            card_radiance = planck * color_mod;
        } else {
            card_radiance = spectral::spectral_uplift(card_c, lambda_nm);
        }

        total += card_radiance * std::pow(alignment, power) * strength * env.light_energy;
    }

    return total;
}

// ---------------------------------------------------------------------------
// Blocker attenuation
// ---------------------------------------------------------------------------

double blocker_attenuation(const EnvironmentSetup& env, Vector3 dir) {
    double blocker_alignment = dmax((double)dir.dot(env.blocker_dir), 0.0);
    double blocker_value = std::pow(blocker_alignment, env.blocker_power) * env.blocker_strength;
    return clampd(1.0 - blocker_value, 0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Ground bounce
// ---------------------------------------------------------------------------

double ground_bounce(const EnvironmentSetup& env, Vector3 dir, double lambda_nm,
                     double roughness) {
    if (env.ground_albedo < 0.001 || (double)dir.y >= 0.0) return 0.0;

    double card_contribution = 0.0;
    for (const auto& card : env.cards) {
        double card_to_ground = dmax(-(double)card.dir.y, 0.0);
        if (card_to_ground <= 0.0) continue;
        double card_energy = lerpd(card.sharp_strength, card.broad_strength, roughness);

        double card_radiance;
        if (card.temperature_kelvin > 500.0) {
            card_radiance = spectral::planckian_radiance(lambda_nm, card.temperature_kelvin)
                          * spectral::spectral_uplift(card.color, lambda_nm);
        } else {
            card_radiance = spectral::spectral_uplift(card.color, lambda_nm);
        }

        card_contribution += card_to_ground * card_energy * card_radiance;
    }

    double ground_tint_spectral = spectral::spectral_uplift(env.ground_tint, lambda_nm);
    double distance_falloff = 1.0 / (1.0 + env.ground_distance * 0.5);
    double up_component = dmax(-(double)dir.y, 0.0);

    return card_contribution * env.ground_albedo * INV_PI
         * ground_tint_spectral * distance_falloff * up_component * env.light_energy;
}

// ---------------------------------------------------------------------------
// HDR environment map sampling (equirectangular)
// ---------------------------------------------------------------------------

double sample_hdr(const EnvironmentSetup& env, Vector3 dir, double lambda_nm) {
    if (!env.has_hdr || env.hdr_data == nullptr) return 0.0;

    // Equirectangular mapping
    double theta = std::acos(clampd((double)dir.y, -1.0, 1.0));
    double phi = std::atan2((double)dir.z, (double)dir.x);
    if (phi < 0.0) phi += TWO_PI;

    double u = phi * (0.5 * INV_PI);
    double v = theta * INV_PI;

    // Bilinear interpolation
    double fx = u * (env.hdr_width - 1);
    double fy = v * (env.hdr_height - 1);
    int x0 = clampi((int)fx, 0, env.hdr_width - 1);
    int y0 = clampi((int)fy, 0, env.hdr_height - 1);
    int x1 = clampi(x0 + 1, 0, env.hdr_width - 1);
    int y1 = clampi(y0 + 1, 0, env.hdr_height - 1);
    double sx = fx - (double)x0;
    double sy = fy - (double)y0;

    auto pixel = [&](int px, int py) -> Color {
        int idx = (py * env.hdr_width + px) * 3;
        return Color(env.hdr_data[idx], env.hdr_data[idx + 1], env.hdr_data[idx + 2], 1.0f);
    };

    Color c00 = pixel(x0, y0);
    Color c10 = pixel(x1, y0);
    Color c01 = pixel(x0, y1);
    Color c11 = pixel(x1, y1);
    Color top = color_lerp(c00, c10, sx);
    Color bottom = color_lerp(c01, c11, sx);
    Color result = color_lerp(top, bottom, sy);

    return spectral::spectral_uplift(result, lambda_nm) * env.environment_energy;
}

// ---------------------------------------------------------------------------
// Full environment sampling
//
// Called from the transport core when a ray escapes the gem into the
// environment. Uses roughness=1.0 for card/ground sampling so that the
// broad_power lobe is selected. The sharp_power lobes (up to 900) from the
// old Whitted tracer are far too narrow for stochastic path tracing —
// they create rare extreme-value samples at specific wavelengths that
// produce chromatic fireflies. In the new architecture, specular highlight
// sharpness comes from the GGX microfacet on the gem surface, not from
// the light card's angular power.
// ---------------------------------------------------------------------------

double sample(const EnvironmentSetup& env, Vector3 dir, double lambda_nm) {
    double result = 0.0;

    // Primary environment
    if (env.has_hdr) {
        result += sample_hdr(env, dir, lambda_nm) * env.exposure;
    } else {
        result += sample_sky(env, dir, lambda_nm);
    }

    // Analytical light cards — broad lobe for transport-level sampling
    result += sample_cards(env, dir, lambda_nm, 1.0);

    // Ground bounce — broad lobe
    if ((double)dir.y < 0.0) {
        result += ground_bounce(env, dir, lambda_nm, 1.0);
    }

    // Blocker
    result *= blocker_attenuation(env, dir);

    return dmax(result, 0.0);
}

// ---------------------------------------------------------------------------
// Environment CDF for importance sampling
// ---------------------------------------------------------------------------

void build_environment_cdf(EnvironmentSetup& env) {
    if (!env.has_hdr || env.hdr_data == nullptr) return;

    int w = env.hdr_width;
    int h = env.hdr_height;

    // Compute luminance for each pixel
    env.conditional_cdf.resize(w * h);
    env.marginal_cdf.resize(h);

    for (int y = 0; y < h; y++) {
        // sin(theta) weight for equirectangular projection
        double theta = PI * ((double)y + 0.5) / (double)h;
        double sin_theta = std::sin(theta);

        double row_sum = 0.0;
        for (int x = 0; x < w; x++) {
            int idx = (y * w + x) * 3;
            double r = (double)env.hdr_data[idx];
            double g = (double)env.hdr_data[idx + 1];
            double b = (double)env.hdr_data[idx + 2];
            double lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            row_sum += lum * sin_theta;
            env.conditional_cdf[y * w + x] = (float)row_sum;
        }

        // Normalize conditional CDF for this row
        if (row_sum > 0.0) {
            for (int x = 0; x < w; x++) {
                env.conditional_cdf[y * w + x] /= (float)row_sum;
            }
        }

        env.marginal_cdf[y] = (float)(y > 0 ? (double)env.marginal_cdf[y - 1] : 0.0) + (float)row_sum;
    }

    // Normalize marginal CDF
    env.marginal_integral = env.marginal_cdf[h - 1];
    if (env.marginal_integral > 0.0f) {
        for (int y = 0; y < h; y++) {
            env.marginal_cdf[y] /= env.marginal_integral;
        }
    }
}

// Binary search in CDF
static int binary_search_cdf(const float* cdf, int count, float u) {
    int lo = 0, hi = count - 1;
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        if (cdf[mid] < u) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

EnvSample importance_sample(const EnvironmentSetup& env, TraceRNG& rng) {
    EnvSample result;
    result.pdf = 1.0 / (4.0 * PI); // uniform fallback

    if (!env.has_hdr || env.marginal_cdf.empty()) {
        // Uniform sphere sample
        double u1 = rng.next();
        double u2 = rng.next();
        double cos_theta = 1.0 - 2.0 * u1;
        double sin_theta_val = std::sqrt(1.0 - cos_theta * cos_theta);
        double phi = TWO_PI * u2;
        result.dir = Vector3(
            (float)(sin_theta_val * std::cos(phi)),
            (float)cos_theta,
            (float)(sin_theta_val * std::sin(phi)));
        return result;
    }

    int w = env.hdr_width;
    int h = env.hdr_height;

    // Sample marginal (pick row)
    float u_y = (float)rng.next();
    int y = binary_search_cdf(env.marginal_cdf.data(), h, u_y);

    // Sample conditional (pick column within row)
    float u_x = (float)rng.next();
    int x = binary_search_cdf(&env.conditional_cdf[y * w], w, u_x);

    // Convert to direction
    double theta = PI * ((double)y + 0.5) / (double)h;
    double phi = TWO_PI * ((double)x + 0.5) / (double)w;
    double sin_theta_val = std::sin(theta);

    result.dir = Vector3(
        (float)(sin_theta_val * std::cos(phi)),
        (float)std::cos(theta),
        (float)(sin_theta_val * std::sin(phi)));

    // Compute PDF
    double sin_t = dmax(sin_theta_val, 1e-12);
    // PDF = luminance(x,y) / (marginal_integral * sin(theta)) * (w*h) / (2*pi*pi)
    int idx = (y * w + x) * 3;
    double r = (double)env.hdr_data[idx];
    double g = (double)env.hdr_data[idx + 1];
    double b = (double)env.hdr_data[idx + 2];
    double lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    result.pdf = (lum * (double)w * (double)h) /
                 (2.0 * PI * PI * sin_t * dmax((double)env.marginal_integral, 1e-12));

    return result;
}

double pdf(const EnvironmentSetup& env, Vector3 dir) {
    if (!env.has_hdr || env.marginal_cdf.empty()) {
        return 1.0 / (4.0 * PI);
    }

    int w = env.hdr_width;
    int h = env.hdr_height;

    double theta = std::acos(clampd((double)dir.y, -1.0, 1.0));
    double phi = std::atan2((double)dir.z, (double)dir.x);
    if (phi < 0.0) phi += TWO_PI;

    int x = clampi((int)(phi / TWO_PI * (double)w), 0, w - 1);
    int y = clampi((int)(theta / PI * (double)h), 0, h - 1);

    double sin_t = dmax(std::sin(theta), 1e-12);
    int idx = (y * w + x) * 3;
    double r = (double)env.hdr_data[idx];
    double g = (double)env.hdr_data[idx + 1];
    double b = (double)env.hdr_data[idx + 2];
    double lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;

    return (lum * (double)w * (double)h) /
           (2.0 * PI * PI * sin_t * dmax((double)env.marginal_integral, 1e-12));
}

// ---------------------------------------------------------------------------
// HDR image loading
// ---------------------------------------------------------------------------

bool load_hdr_image(EnvironmentSetup& env, const godot::Ref<godot::Image>& image) {
    if (image.is_null()) return false;

    int w = image->get_width();
    int h = image->get_height();
    if (w <= 0 || h <= 0) return false;

    // Allocate float RGB buffer (owned by EnvironmentSetup via the vector)
    env.hdr_float_storage.resize(w * h * 3);
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            godot::Color pixel = image->get_pixel(x, y);
            int idx = (y * w + x) * 3;
            env.hdr_float_storage[idx]     = (float)pixel.r;
            env.hdr_float_storage[idx + 1] = (float)pixel.g;
            env.hdr_float_storage[idx + 2] = (float)pixel.b;
        }
    }

    env.hdr_data = env.hdr_float_storage.data();
    env.hdr_width = w;
    env.hdr_height = h;
    env.has_hdr = true;

    // Build importance sampling CDF
    build_environment_cdf(env);

    return true;
}

}} // namespace gem::environment
