// gem_trace_environment.h — Environment sampling: sky, light cards, HDR, MIS.
#pragma once

#include "gem_trace_types.h"
#include "gem_trace_spectral.h"
#include "gem_trace_rng.h"

namespace gem { namespace environment {

// Sample the full environment (HDR map + light cards + sky gradient) at a given
// direction and wavelength. Returns spectral radiance.
double sample(const EnvironmentSetup& env, Vector3 dir, double lambda_nm);

// Sample sky gradient (fallback when no HDR map).
double sample_sky(const EnvironmentSetup& env, Vector3 dir, double lambda_nm);

// Sample light cards (additive to primary environment).
double sample_cards(const EnvironmentSetup& env, Vector3 dir, double lambda_nm,
                    double roughness = 0.01);

// Compute blocker attenuation.
double blocker_attenuation(const EnvironmentSetup& env, Vector3 dir);

// Ground bounce radiance (virtual Lambertian ground plane).
double ground_bounce(const EnvironmentSetup& env, Vector3 dir, double lambda_nm,
                     double roughness = 0.01);

// --- HDR environment map ---

// Sample HDR environment map at a given direction.
double sample_hdr(const EnvironmentSetup& env, Vector3 dir, double lambda_nm);

// Build the environment CDF from the HDR map luminance.
void build_environment_cdf(EnvironmentSetup& env);

// Importance-sample a direction from the environment CDF.
struct EnvSample {
    Vector3 dir;
    double pdf;
};
EnvSample importance_sample(const EnvironmentSetup& env, TraceRNG& rng);

// Evaluate the PDF for a given direction.
double pdf(const EnvironmentSetup& env, Vector3 dir);

// --- HDR map loading ---

// Load an equirectangular HDR image into float RGB array.
// Called from the kernel's setup, before tracing begins.
// The Image is passed from GDScript via the request dictionary.
// Returns true on success. Populates env.hdr_data/width/height/has_hdr
// and builds the importance sampling CDF.
bool load_hdr_image(EnvironmentSetup& env, const godot::Ref<godot::Image>& image);

}} // namespace gem::environment
