// gem_trace_transport.h — Stochastic spectral path tracer core.
#pragma once

#include "gem_trace_types.h"
#include "gem_trace_scene.h"
#include "gem_trace_rng.h"

namespace gem { namespace transport {

// Result from multi-wavelength path trace.
struct SpectralResult {
    double intensities[HERO_WAVELENGTHS] = {};
};

// Trace a single spectral path from origin in direction.
// Returns the spectral radiance at the given wavelength.
double trace_path(
    const TraceContext& ctx,
    const TraceScene& scene,
    Vector3 origin,
    Vector3 direction,
    double lambda_nm,
    TraceRNG& rng,
    TraceStats* stats = nullptr);

// Trace a single geometric path carrying HERO_WAVELENGTHS wavelengths.
// All wavelengths share the same bounce geometry (determined by lambdas[0]).
// Per-wavelength Beer-Lambert absorption and Fresnel corrections are tracked
// independently, giving ~4x chromatic noise reduction vs single-wavelength.
SpectralResult trace_path_spectral(
    const TraceContext& ctx,
    const TraceScene& scene,
    Vector3 origin,
    Vector3 direction,
    const double lambdas[HERO_WAVELENGTHS],
    TraceRNG& rng,
    TraceStats* stats = nullptr);

// Compute opaque surface shading (Lambert diffuse + GGX specular from environment).
// Used for MATERIAL_MODE_PATTERNED_OPAQUE gems.
double compute_opaque_surface(
    const TraceContext& ctx,
    const HitResult& hit,
    Vector3 incident_dir,
    double lambda_nm,
    TraceRNG& rng);

}} // namespace gem::transport
