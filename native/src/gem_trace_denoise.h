// gem_trace_denoise.h — OIDN denoiser wrapper for the gem trace pipeline.
// Requires Intel Open Image Denoise 2.x linked at build time (hard dependency).
#pragma once

#include <vector>

namespace gem {

struct DenoiseResult {
    std::vector<float> color;  // denoised RGB, width*height*3
    bool success;
};

/// Denoise a traced image using OIDN's RT filter with optional feature guides.
///
/// @param color     Input RGB float3 buffer (width*height*3), tonemapped [0,1].
/// @param width     Image width in pixels.
/// @param height    Image height in pixels.
/// @param normal_aov  First-hit shading normal in world space (may be nullptr).
/// @param albedo_aov  First-hit base material color (may be nullptr).
/// @param strength  Blend factor: 0.0 = raw, 1.0 = fully denoised.
/// @return          DenoiseResult with denoised color buffer.
DenoiseResult denoise_image(
    const float* color, int width, int height,
    const float* normal_aov,   // may be nullptr (no feature guide)
    const float* albedo_aov,   // may be nullptr
    float strength);

/// Release the persistent OIDN device and its TBB thread pool.
/// Call during extension teardown to prevent shutdown hangs.
void release_denoise_device();

} // namespace gem
