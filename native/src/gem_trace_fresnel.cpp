// gem_trace_fresnel.cpp — Exact Fresnel, GGX microfacet, Snell's law.
#include "gem_trace_fresnel.h"
#include <cmath>

namespace gem { namespace fresnel {

// ---------------------------------------------------------------------------
// build_orthonormal_basis
// ---------------------------------------------------------------------------

void build_orthonormal_basis(Vector3 n, Vector3& tangent, Vector3& bitangent) {
    Vector3 a = (std::abs((double)n.x) > 0.9) ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
    bitangent = n.cross(a).normalized();
    tangent = bitangent.cross(n).normalized();
}

// ---------------------------------------------------------------------------
// Exact unpolarized dielectric Fresnel reflectance
// ---------------------------------------------------------------------------

double dielectric(Vector3 dir, Vector3 normal, double eta_i, double eta_t) {
    double cos_i = clampd(std::abs((double)(-dir).dot(normal)), 0.0, 1.0);
    double sin2_t = (eta_i / eta_t) * (eta_i / eta_t) * (1.0 - cos_i * cos_i);
    if (sin2_t >= 1.0) return 1.0; // TIR

    double cos_t = std::sqrt(1.0 - sin2_t);
    double rs = (eta_i * cos_i - eta_t * cos_t) / (eta_i * cos_i + eta_t * cos_t);
    double rp = (eta_t * cos_i - eta_i * cos_t) / (eta_t * cos_i + eta_i * cos_t);
    return clampd(0.5 * (rs * rs + rp * rp), 0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Snell's law refraction
// ---------------------------------------------------------------------------

Vector3 refract(Vector3 dir, Vector3 normal, double eta_ratio) {
    double cos_i = clampd(-(double)dir.dot(normal), -1.0, 1.0);
    double sin2_t = eta_ratio * eta_ratio * (1.0 - cos_i * cos_i);
    if (sin2_t >= 1.0) return Vector3(0, 0, 0); // TIR
    double cos_t = std::sqrt(1.0 - sin2_t);
    return (dir * eta_ratio + normal * (eta_ratio * cos_i - cos_t)).normalized();
}

// ---------------------------------------------------------------------------
// Reflection
// ---------------------------------------------------------------------------

Vector3 reflect(Vector3 dir, Vector3 normal) {
    return (dir - normal * (2.0 * (double)dir.dot(normal))).normalized();
}

// ---------------------------------------------------------------------------
// GGX microfacet normal sampling (Trowbridge-Reitz)
// ---------------------------------------------------------------------------

Vector3 sample_ggx(Vector3 geometric_normal, double roughness, TraceRNG& rng) {
    if (roughness < 1e-6) return geometric_normal;

    double alpha = roughness * roughness;
    double alpha2 = alpha * alpha;
    double u1 = rng.next();
    double u2 = rng.next();

    // Sample theta from GGX distribution
    double denom = u1 * (alpha2 - 1.0) + 1.0;
    double cos_theta = std::sqrt((1.0 - u1) / dmax(denom, 1e-12));
    double sin_theta = std::sqrt(dmax(0.0, 1.0 - cos_theta * cos_theta));
    double phi = TWO_PI * u2;

    // Build local frame from geometric normal
    Vector3 tangent, bitangent;
    build_orthonormal_basis(geometric_normal, tangent, bitangent);

    // Transform to world space
    Vector3 micro = tangent * (float)(sin_theta * std::cos(phi))
                   + bitangent * (float)(sin_theta * std::sin(phi))
                   + geometric_normal * (float)cos_theta;
    return micro.normalized();
}

}} // namespace gem::fresnel
