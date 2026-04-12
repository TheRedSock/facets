// gem_trace_spectral.h — Spectral color science for the path tracer.
// CIE 1931 standard observer, Sellmeier dispersion, spectral uplifting.
#pragma once

#include "gem_trace_types.h"

namespace gem { namespace spectral {

// Evaluate CIE x̄, ȳ, z̄ at a given wavelength (nm) via linear interpolation.
// Returns Vector3(X_weight, Y_weight, Z_weight).
Vector3 cie_xyz(double lambda_nm);

// Sellmeier IOR at a given wavelength (nm).
double sellmeier_ior(const GemTraceProps& props, double lambda_nm);

// For birefringent gems, compute extraordinary IOR at given ray direction.
// Uses index ellipsoid: 1/ne²(θ) = cos²θ/no² + sin²θ/ne²
// where θ is angle between ray and optic axis, no = sellmeier_ior, ne = no + delta_n.
double birefringent_ior(const GemTraceProps& props, double lambda_nm,
                        Vector3 ray_dir, bool extraordinary);

// Evaluate absorption coefficient α(λ) from sampled spectrum.
// Linearly interpolates the 81-value array.
// Applies absorption_strength_scale.
// If pleochroism spectrum exists, blends based on ray_dir vs optic_axis.
double evaluate_absorption(const GemTraceProps& props, double lambda_nm,
                           Vector3 ray_dir = Vector3(0, 0, 1));

// XYZ to linear sRGB (may produce out-of-gamut values; clamp after accumulation).
Vector3 xyz_to_linear_srgb(Vector3 xyz);

// Linear sRGB to sRGB (gamma).
Vector3 linear_to_srgb(Vector3 linear);

// Spectral uplifting: given sRGB color, return approximate spectral radiance at λ.
// Simplified V1: smooth Gaussian basis functions for R, G, B channels.
double spectral_uplift(Color srgb, double lambda_nm);

// Planck blackbody spectral radiance, peak-normalized.
double planckian_radiance(double lambda_nm, double temperature_kelvin);

}} // namespace gem::spectral
