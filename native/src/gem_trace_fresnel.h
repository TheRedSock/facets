// gem_trace_fresnel.h — Exact Fresnel equations, GGX microfacet, Snell's law.
#pragma once

#include "gem_trace_types.h"
#include "gem_trace_rng.h"

namespace gem { namespace fresnel {

// Build orthonormal basis from a single normal vector.
void build_orthonormal_basis(Vector3 n, Vector3& tangent, Vector3& bitangent);

// Exact unpolarized dielectric Fresnel reflectance.
// dir: incident ray direction (pointing INTO the surface)
// normal: surface normal (pointing outward, same side as the incident ray)
// eta_i: IOR of the medium the ray is coming FROM
// eta_t: IOR of the medium the ray is going INTO
// Returns reflectance R in [0, 1]. R=1 for total internal reflection.
double dielectric(Vector3 dir, Vector3 normal, double eta_i, double eta_t);

// Snell's law refraction. Returns zero vector if TIR.
Vector3 refract(Vector3 dir, Vector3 normal, double eta_ratio);

// Reflect direction about normal.
Vector3 reflect(Vector3 dir, Vector3 normal);

// Sample microfacet normal from GGX (Trowbridge-Reitz) distribution.
// geometric_normal: the flat facet normal
// roughness: GGX α parameter (0 = perfect mirror → returns geometric_normal)
// Returns a sampled microfacet normal in world space.
Vector3 sample_ggx(Vector3 geometric_normal, double roughness, TraceRNG& rng);

// Sample microfacet normal from anisotropic GGX (Trowbridge-Reitz) distribution.
// geometric_normal: the flat facet normal
// tangent: preferred tangent direction on the surface (anisotropy elongation axis)
// alpha_x, alpha_y: directional roughness parameters
// Returns a sampled microfacet normal in world space.
Vector3 sample_ggx_aniso(Vector3 geometric_normal, Vector3 tangent, double alpha_x, double alpha_y, TraceRNG& rng);

}} // namespace gem::fresnel
