// gem_trace_rng.h — Header-only per-thread xoshiro256** RNG.
// Replaces all randomness for the stochastic path tracer.
#pragma once

#include <cstdint>
#include <cmath>

namespace gem {

class TraceRNG {
    uint64_t s[4];

    static uint64_t splitmix64(uint64_t& state) {
        uint64_t z = (state += 0x9e3779b97f4a7c15ULL);
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
        z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
        return z ^ (z >> 31);
    }

    static uint64_t rotl(uint64_t x, int k) {
        return (x << k) | (x >> (64 - k));
    }

public:
    void seed(uint64_t seed_value) {
        uint64_t sm = seed_value;
        s[0] = splitmix64(sm);
        s[1] = splitmix64(sm);
        s[2] = splitmix64(sm);
        s[3] = splitmix64(sm);
    }

    // Seed from base seed + thread/pixel identifiers for deterministic parallelism.
    void seed(uint64_t base_seed, int thread_id, int pixel_index) {
        uint64_t combined = base_seed ^ ((uint64_t)thread_id * 2654435761ULL)
                                      ^ ((uint64_t)pixel_index * 40503ULL);
        seed(combined);
    }

    // Returns uniform double in [0, 1).
    double next() {
        uint64_t result = rotl(s[1] * 5, 7) * 9;
        uint64_t t = s[1] << 17;
        s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3];
        s[2] ^= t; s[3] = rotl(s[3], 45);
        return (double)(result >> 11) * 0x1.0p-53;
    }

    // Returns approximate Gaussian (Box-Muller).
    double next_gaussian() {
        double u1 = next();
        if (u1 < 1e-12) u1 = 1e-12;
        double u2 = next();
        return std::sqrt(-2.0 * std::log(u1)) * std::cos(6.283185307179586 * u2);
    }

    // Sample a point uniformly on the unit hemisphere oriented along +Z.
    // Returns (x, y, z) with z >= 0.
    void sample_hemisphere(double& x, double& y, double& z) {
        double u1 = next();
        double u2 = next();
        double val = 1.0 - u1 * u1;
        double r = std::sqrt(val > 0.0 ? val : 0.0);
        double phi = 6.283185307179586 * u2;
        x = r * std::cos(phi);
        y = r * std::sin(phi);
        z = u1;
    }

    // Cosine-weighted hemisphere sample (returns direction, pdf = cos(theta)/pi).
    void sample_cosine_hemisphere(double& x, double& y, double& z) {
        double u1 = next();
        double u2 = next();
        double r = std::sqrt(u1);
        double phi = 6.283185307179586 * u2;
        x = r * std::cos(phi);
        y = r * std::sin(phi);
        double val = 1.0 - u1;
        z = std::sqrt(val > 0.0 ? val : 0.0);
    }
};

} // namespace gem
