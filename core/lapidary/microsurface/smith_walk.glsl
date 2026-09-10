// Lossless isotropic dielectric Smith microsurface, in a local +Z frame.
// Heitz et al. 2016, DOI 10.1145/2897824.2925943, height-correlated walk.
// Explicit experimental option; scalar sampler also serves distribution tests.
// Height is stored as its CDF; changing the continuous height distribution
// cannot change the BSDF. Crossing the dielectric complements this CDF.
// No geometry-side rejection, Smith G2 attenuation, or energy compensation.

float smith_random(inout uint state) {
    state = state * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    word = (word >> 22u) ^ word;
    return (float(word >> 9u) + 0.5) * (1.0 / 8388608.0);
}

// Advance a ray on the positive side. False means the ray escaped upwards.
// The signed inverse Lambda form avoids the horizon singularity. It also
// avoids subtracting nearly equal terms for a steep downward direction.
bool smith_height(vec3 ray, vec2 alpha, float u, inout float cdf) {
    float z = ray.z;
    float a2 = dot(ray.xy * alpha, ray.xy * alpha);
    float length_stretched = sqrt(z * z + a2);
    if (z > 0.0 && a2 == 0.0) { return false; }
    float inv_lambda = z > 0.0 ? 2.0 * z * (length_stretched + z) / a2
        : 2.0 * z / max(length_stretched - z, 1e-30);
    float next_log_cdf = log(max(cdf, 1e-30)) - log(1.0 - u) * inv_lambda;
    if (z > 0.0 && next_log_cdf >= 0.0) { return false; }
    cdf = exp(min(next_log_cdf, 0.0));
    return true;
}

// Visible GGX normals for incident directions on either side of the horizon.
// Spherical-cap construction: Dupuy/Benyoub 2023, DOI 10.1111/cgf.14867.
// Explicit cap height avoids cancellation in h.z for below-horizon rays.
vec3 smith_normal(vec3 outgoing, vec2 alpha, vec2 u) {
    vec3 v = normalize(vec3(outgoing.xy * alpha, outgoing.z));
    float aperture = v.z < 0.0 ? dot(v.xy, v.xy) / (1.0 - v.z) : 1.0 + v.z;
    float cap_height = (1.0 - u.y) * aperture;
    float one_minus_z = u.y * aperture;
    float radius = sqrt(max(0.0, one_minus_z * (2.0 - one_minus_z)));
    float angle = 6.283185307179586 * u.x;
    vec3 h = vec3(v.xy + radius * vec2(cos(angle), sin(angle)), cap_height);
    return normalize(vec3(h.xy * alpha, h.z));
}

float smith_fresnel(float cosine, float eta) {
    if (abs(eta - 1.0) < 1e-7) { return 0.0; }
    float sine2 = eta * eta * max(0.0, 1.0 - cosine * cosine);
    if (sine2 >= 1.0) { return 1.0; }
    float ct = sqrt(1.0 - sine2);
    float rs = (eta * cosine - ct) / (eta * cosine + ct);
    float rp = (cosine - eta * ct) / (cosine + eta * ct);
    return 0.5 * (rs * rs + rp * rp);
}

struct SmithSample { vec3 direction; int order; bool transmitted; bool valid; };

// Camera ray arrives from +Z. eta is n_before/n_after. Each Fresnel decision
// samples power, so weight is 1 for reflection and eta^2 for transmission in
// radiance transport. Polarization/spectral path weights must be composed per
// micro-event by a future transport adapter, not inferred from the final ray.
SmithSample smith_sample(vec3 incoming_ray, vec2 alpha, float eta, inout uint rng, int limit) {
    SmithSample result;
    result.direction = incoming_ray; result.order = 0;
    result.transmitted = false; result.valid = false;
    if (abs(eta - 1.0) < 1e-7) {
        result.transmitted = true; result.valid = true; return result;
    }
    float cdf = 1.0;
    for (int step = 0; step <= limit; step++) {
        float side = result.transmitted ? -1.0 : 1.0;
        // cdf is always relative to the current side's upward normal.
        if (!smith_height(side * result.direction, alpha, smith_random(rng), cdf)) {
            result.valid = side * result.direction.z > 0.0;
            return result;
        }
        if (step == limit) { return result; }
        vec3 m = side * smith_normal(-side * result.direction, alpha,
            vec2(smith_random(rng), smith_random(rng)));
        float ratio = result.transmitted ? 1.0 / eta : eta;
        float cosine = clamp(-dot(result.direction, m), 0.0, 1.0);
        float reflection = smith_fresnel(cosine, ratio);
        if (smith_random(rng) < reflection) {
            result.direction = normalize(reflect(result.direction, m));
        } else {
            result.direction = normalize(refract(result.direction, m, ratio));
            result.transmitted = !result.transmitted;
            cdf = 1.0 - cdf;
        }
        result.order++;
        if (any(isnan(result.direction)) || any(isinf(result.direction))) { return result; }
    }
    return result;
}
