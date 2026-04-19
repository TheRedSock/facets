// gem_trace_volume.h — Volumetric transport: Beer-Lambert, HG scattering, fluorescence.
#pragma once

#include "gem_trace_types.h"
#include "gem_trace_spectral.h"
#include "gem_trace_fresnel.h"
#include "gem_trace_rng.h"

namespace gem { namespace volume {

// Beer-Lambert attenuation over a segment.
double beer_lambert(const GemTraceProps& props, double lambda_nm,
                    double distance, Vector3 ray_dir,
                    double absorption_mult = 1.0);

// Beer-Lambert with gradient/phenomenon color zoning.
// obj_pos is the current position normalized to the gem bounding radius
// (range roughly [-1, +1]).  Gradient and phenomenon properties from the
// GemVisualResource modulate the absorption spectrum spatially (gradient)
// and directionally (phenomenon), producing color zoning and color-change
// effects inside transparent gems.
double beer_lambert_zoned(const GemTraceProps& props, double lambda_nm,
                          double distance, Vector3 ray_dir,
                          Vector3 obj_pos, double absorption_mult = 1.0);

// Compute gradient-zoned absorption alpha for the current wavelength.
// Uses gradient_zone_spectrum as a target absorption curve when present; otherwise
// falls back to the legacy RGB-uplift heuristic from gradient_color.
double gradient_absorption_mod(const GemTraceProps& props,
                               Vector3 obj_pos, double lambda_nm, double base_alpha);

// Compute phenomenon-zoned absorption alpha for the current wavelength.
// Uses phenomenon_zone_spectrum as a target absorption curve when present; otherwise
// falls back to the legacy RGB-uplift heuristic from phenomenon_color.
double phenomenon_absorption_mod(const GemTraceProps& props,
                                 Vector3 ray_dir, double lambda_nm, double base_alpha);

// Sample scattering event distance from exponential distribution.
// Returns distance to next scatter event. If > surface_distance, no scatter occurs.
double sample_scatter_distance(double sigma_s, TraceRNG& rng);

// Sample new direction from Henyey-Greenstein phase function.
Vector3 sample_henyey_greenstein(Vector3 incident_dir, double g, TraceRNG& rng);

// Test for fluorescence wavelength shift.
// Returns true if fluorescence occurred (wavelength_nm is modified).
bool try_fluorescence(const GemTraceProps& props, double& wavelength_nm, TraceRNG& rng,
                      double yield_cap = 1e30);

// Throughput multiplier to keep a just-emitted fluorescence photon physically
// visible when the authored absorption at the emission wavelength is high
// enough that it would otherwise be re-absorbed before escaping. Returns 1.0
// (no boost) when the authored alpha_emission already gives >= 50% survival
// over a typical remaining escape path. Call ONCE per successful fluorescence
// shift, immediately after `try_fluorescence` returns true.
double fluorescence_emission_boost(const GemTraceProps& props,
                                   double emitted_wavelength_nm,
                                   Vector3 ray_dir);

}} // namespace gem::volume
