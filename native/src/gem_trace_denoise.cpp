// gem_trace_denoise.cpp — OIDN denoiser wrapper implementation.
// Hard dependency on Intel Open Image Denoise 2.x.
#include "gem_trace_denoise.h"
#include <OpenImageDenoise/oidn.hpp>
#include <cstring>

namespace gem {

// Persistent OIDN device — created on first use, released on shutdown.
static oidn::DeviceRef s_device;

static void ensure_device() {
    if (!s_device) {
        s_device = oidn::newDevice(oidn::DeviceType::CPU);
        s_device.commit();
    }
}

void release_denoise_device() {
    if (s_device) {
        s_device.release();
        s_device = oidn::DeviceRef();
    }
}

DenoiseResult denoise_image(
    const float* color, int width, int height,
    const float* normal_aov, const float* albedo_aov,
    float strength)
{
    int pixel_count = width * height;
    DenoiseResult result;
    result.color.resize(pixel_count * 3);
    result.success = false;

    // Strength near zero: return raw copy.
    if (strength <= 0.0001f) {
        std::memcpy(result.color.data(), color, pixel_count * 3 * sizeof(float));
        result.success = true;
        return result;
    }

    ensure_device();

    oidn::FilterRef filter = s_device.newFilter("RT");
    filter.setImage("color",  const_cast<float*>(color), oidn::Format::Float3, width, height);
    filter.setImage("output", result.color.data(), oidn::Format::Float3, width, height);
    if (normal_aov)
        filter.setImage("normal", const_cast<float*>(normal_aov), oidn::Format::Float3, width, height);
    if (albedo_aov)
        filter.setImage("albedo", const_cast<float*>(albedo_aov), oidn::Format::Float3, width, height);
    filter.set("hdr", false);
    filter.commit();
    filter.execute();

    const char* error_msg;
    if (s_device.getError(error_msg) != oidn::Error::None) {
        // Denoiser failed — return raw, don't silently degrade.
        // Per the no-fallback principle, this should be visible in logs.
        std::memcpy(result.color.data(), color, pixel_count * 3 * sizeof(float));
        return result;
    }

    // Blend denoised ↔ raw by strength.
    if (strength < 0.9999f) {
        float inv = 1.0f - strength;
        for (int i = 0; i < pixel_count * 3; i++) {
            result.color[i] = color[i] * inv + result.color[i] * strength;
        }
    }

    result.success = true;
    return result;
}

} // namespace gem
