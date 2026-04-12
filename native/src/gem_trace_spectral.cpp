// gem_trace_spectral.cpp — CIE 1931 standard observer, Sellmeier, spectral uplifting.
#include "gem_trace_spectral.h"
#include <cmath>

namespace gem { namespace spectral {

// ---------------------------------------------------------------------------
// CIE 1931 2-degree standard observer, 5nm intervals, 380-780nm (81 entries).
// Source: CIE 15:2004, Table T.1
// ---------------------------------------------------------------------------

static const double CIE_X[81] = {
    0.001368, 0.002236, 0.004243, 0.007650, 0.014310,  // 380-400
    0.023190, 0.043510, 0.077630, 0.134380, 0.214770,  // 405-425
    0.283900, 0.328500, 0.348280, 0.348060, 0.336200,  // 430-450
    0.318700, 0.290800, 0.233700, 0.175560, 0.123200,  // 455-475
    0.078250, 0.042160, 0.020300, 0.008750, 0.002100,  // 480-500
    0.003900, 0.021000, 0.050000, 0.090100, 0.138200,  // 505-525
    0.208020, 0.284900, 0.368180, 0.460200, 0.567690,  // 530-550
    0.676000, 0.793200, 0.904000, 1.007300, 1.084000,  // 555-575
    1.152500, 1.148600, 1.089100, 0.999110, 0.884930,  // 580-600
    0.771610, 0.658340, 0.527960, 0.398090, 0.283490,  // 605-625
    0.196550, 0.132180, 0.088120, 0.057860, 0.037840,  // 630-650
    0.024160, 0.015340, 0.009690, 0.005850, 0.003710,  // 655-675
    0.002120, 0.001390, 0.000890, 0.000580, 0.000370,  // 680-700
    0.000210, 0.000150, 0.000100, 0.000070, 0.000050,  // 705-725
    0.000030, 0.000020, 0.000010, 0.000010, 0.000000,  // 730-750
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,  // 755-775
    0.000000                                             // 780
};

static const double CIE_Y[81] = {
    0.000039, 0.000064, 0.000120, 0.000217, 0.000396,  // 380-400
    0.000640, 0.001210, 0.002180, 0.004000, 0.007300,  // 405-425
    0.011600, 0.016840, 0.023000, 0.029800, 0.038000,  // 430-450
    0.048000, 0.060000, 0.073900, 0.090980, 0.112600,  // 455-475
    0.139020, 0.169300, 0.208020, 0.258600, 0.323000,  // 480-500
    0.407300, 0.503000, 0.608200, 0.710000, 0.793200,  // 505-525
    0.862000, 0.914850, 0.954000, 0.980300, 0.994950,  // 530-550
    1.000000, 0.995000, 0.978600, 0.952000, 0.915400,  // 555-575
    0.870000, 0.816300, 0.757000, 0.694900, 0.631000,  // 580-600
    0.566800, 0.503000, 0.441200, 0.381000, 0.321000,  // 605-625
    0.265000, 0.217000, 0.175000, 0.138200, 0.107000,  // 630-650
    0.081600, 0.061000, 0.044580, 0.032000, 0.023200,  // 655-675
    0.017000, 0.011920, 0.008210, 0.005723, 0.004102,  // 680-700
    0.002929, 0.002091, 0.001484, 0.001047, 0.000740,  // 705-725
    0.000520, 0.000361, 0.000249, 0.000172, 0.000120,  // 730-750
    0.000085, 0.000060, 0.000042, 0.000030, 0.000021,  // 755-775
    0.000015                                             // 780
};

static const double CIE_Z[81] = {
    0.006450, 0.010550, 0.020050, 0.036210, 0.067850,  // 380-400
    0.110200, 0.207400, 0.371300, 0.645600, 1.039050,  // 405-425
    1.385600, 1.622960, 1.747060, 1.782600, 1.772110,  // 430-450
    1.744100, 1.669200, 1.528100, 1.287640, 1.041900,  // 455-475
    0.812950, 0.616200, 0.465180, 0.353300, 0.272000,  // 480-500
    0.212300, 0.158200, 0.111700, 0.078250, 0.057250,  // 505-525
    0.042160, 0.029840, 0.020300, 0.013400, 0.008750,  // 530-550
    0.005750, 0.003900, 0.002750, 0.002100, 0.001800,  // 555-575
    0.001650, 0.001400, 0.001100, 0.001000, 0.000800,  // 580-600
    0.000600, 0.000340, 0.000240, 0.000190, 0.000100,  // 605-625
    0.000050, 0.000030, 0.000020, 0.000010, 0.000000,  // 630-650
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,  // 655-675
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,  // 680-700
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,  // 705-725
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,  // 730-750
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,  // 755-775
    0.000000                                             // 780
};

// ---------------------------------------------------------------------------
// CIE XYZ lookup with linear interpolation
// ---------------------------------------------------------------------------

Vector3 cie_xyz(double lambda_nm) {
    double t = (lambda_nm - LAMBDA_MIN) / SPECTRUM_STEP;
    if (t <= 0.0) return Vector3((float)CIE_X[0], (float)CIE_Y[0], (float)CIE_Z[0]);
    if (t >= 80.0) return Vector3((float)CIE_X[80], (float)CIE_Y[80], (float)CIE_Z[80]);
    int i = (int)t;
    double frac = t - (double)i;
    return Vector3(
        (float)(CIE_X[i] + (CIE_X[i + 1] - CIE_X[i]) * frac),
        (float)(CIE_Y[i] + (CIE_Y[i + 1] - CIE_Y[i]) * frac),
        (float)(CIE_Z[i] + (CIE_Z[i + 1] - CIE_Z[i]) * frac));
}

// ---------------------------------------------------------------------------
// Sellmeier IOR
// ---------------------------------------------------------------------------

double sellmeier_ior(const GemTraceProps& p, double lambda_nm) {
    double l = lambda_nm * 0.001; // nm → μm
    double l2 = l * l;
    double n2 = 1.0
        + (double)p.sellmeier_b.x * l2 / (l2 - (double)p.sellmeier_c.x)
        + (double)p.sellmeier_b.y * l2 / (l2 - (double)p.sellmeier_c.y)
        + (double)p.sellmeier_b.z * l2 / (l2 - (double)p.sellmeier_c.z);
    return std::sqrt(dmax(n2, 1.0));
}

// ---------------------------------------------------------------------------
// Birefringent IOR
// ---------------------------------------------------------------------------

double birefringent_ior(const GemTraceProps& props, double lambda_nm,
                        Vector3 ray_dir, bool extraordinary) {
    double no = sellmeier_ior(props, lambda_nm);
    if (!extraordinary || props.birefringence_delta_n <= 1e-8) return no;

    double ne = no + props.birefringence_delta_n;
    // Index ellipsoid: 1/n²(θ) = cos²θ/no² + sin²θ/ne²
    Vector3 optic = props.optic_axis.normalized();
    double cos_theta = clampd(std::abs((double)ray_dir.normalized().dot(optic)), 0.0, 1.0);
    double sin2_theta = 1.0 - cos_theta * cos_theta;
    double inv_n2 = cos_theta * cos_theta / (no * no) + sin2_theta / (ne * ne);
    return std::sqrt(1.0 / dmax(inv_n2, 0.0001));
}

// ---------------------------------------------------------------------------
// Absorption spectrum evaluation
// ---------------------------------------------------------------------------

double evaluate_absorption(const GemTraceProps& props, double lambda_nm, Vector3 ray_dir) {
    const std::vector<float>& spectrum = props.effective_absorption();
    if (spectrum.empty()) return 0.0;

    // Linearly interpolate the 81-value array
    double t = (lambda_nm - LAMBDA_MIN) / SPECTRUM_STEP;
    double alpha;
    if (t <= 0.0) {
        alpha = (double)spectrum[0];
    } else if (t >= 80.0) {
        alpha = (double)spectrum[80];
    } else {
        int i = (int)t;
        double frac = t - (double)i;
        alpha = (double)spectrum[i] + ((double)spectrum[i + 1] - (double)spectrum[i]) * frac;
    }

    // Pleochroism: blend between ordinary and extraordinary absorption
    if (!props.pleochroism_absorption_spectrum.empty()) {
        const std::vector<float>& pleo = props.pleochroism_absorption_spectrum;
        double alpha_e;
        if (t <= 0.0) {
            alpha_e = (double)pleo[0];
        } else if (t >= 80.0) {
            alpha_e = (double)pleo[80];
        } else {
            int i = (int)t;
            double frac = t - (double)i;
            alpha_e = (double)pleo[i] + ((double)pleo[i + 1] - (double)pleo[i]) * frac;
        }

        // Blend based on angle to optic axis
        Vector3 optic = props.optic_axis.normalized();
        double cos_angle = std::abs((double)ray_dir.normalized().dot(optic));
        double cos2 = cos_angle * cos_angle;
        alpha = alpha * (1.0 - cos2) + alpha_e * cos2;
    }

    return dmax(alpha * props.absorption_strength_scale, 0.0);
}

// ---------------------------------------------------------------------------
// XYZ to linear sRGB (IEC 61966-2-1 matrix)
// ---------------------------------------------------------------------------

Vector3 xyz_to_linear_srgb(Vector3 xyz) {
    return Vector3(
        (float)( 3.2406 * (double)xyz.x - 1.5372 * (double)xyz.y - 0.4986 * (double)xyz.z),
        (float)(-0.9689 * (double)xyz.x + 1.8758 * (double)xyz.y + 0.0415 * (double)xyz.z),
        (float)( 0.0557 * (double)xyz.x - 0.2040 * (double)xyz.y + 1.0570 * (double)xyz.z));
}

// ---------------------------------------------------------------------------
// Linear sRGB to sRGB (gamma)
// ---------------------------------------------------------------------------

static double srgb_gamma(double c) {
    if (c <= 0.0031308) return 12.92 * c;
    return 1.055 * std::pow(c, 1.0 / 2.4) - 0.055;
}

Vector3 linear_to_srgb(Vector3 linear) {
    return Vector3(
        (float)srgb_gamma(clampd((double)linear.x, 0.0, 1.0)),
        (float)srgb_gamma(clampd((double)linear.y, 0.0, 1.0)),
        (float)srgb_gamma(clampd((double)linear.z, 0.0, 1.0)));
}

// ---------------------------------------------------------------------------
// Spectral uplifting (simplified V1: smooth Gaussian basis functions)
// For each RGB channel, define a smooth spectral basis centered at:
//   R: 610nm, G: 540nm, B: 460nm, each with ~40nm width.
// ---------------------------------------------------------------------------

static double gaussian_basis(double lambda_nm, double center, double width) {
    double delta = (lambda_nm - center) / width;
    return std::exp(-0.5 * delta * delta);
}

double spectral_uplift(Color srgb, double lambda_nm) {
    double r_basis = gaussian_basis(lambda_nm, 610.0, 40.0);
    double g_basis = gaussian_basis(lambda_nm, 540.0, 42.0);
    double b_basis = gaussian_basis(lambda_nm, 460.0, 38.0);

    double sum = (double)srgb.r * r_basis
               + (double)srgb.g * g_basis
               + (double)srgb.b * b_basis;

    // Normalize so equal-energy white (1,1,1) integrates to roughly 1.0
    double norm = r_basis + g_basis + b_basis;
    return dmax(sum / dmax(norm, 0.001), 0.0);
}

// ---------------------------------------------------------------------------
// Planck blackbody spectral radiance, peak-normalized.
// ---------------------------------------------------------------------------

double planckian_radiance(double lambda_nm, double temperature_kelvin) {
    if (temperature_kelvin < 500.0) return 1.0;

    double lambda_m = lambda_nm * 1e-9;

    // Planck constants: hc/k ≈ 0.014388 m·K
    double hc_over_lkt = 0.014388 / (lambda_m * temperature_kelvin);
    double exponent = dmin(hc_over_lkt, 700.0); // prevent overflow
    double spectral = 1.0 / (lambda_m * lambda_m * lambda_m * lambda_m * lambda_m)
                    / (std::exp(exponent) - 1.0);

    // Normalize to Wien peak: λ_peak = 2.898e-3 / T
    double lambda_peak = 2.898e-3 / temperature_kelvin;
    double peak_hc = 0.014388 / (lambda_peak * temperature_kelvin);
    double peak_spectral = 1.0 / (lambda_peak * lambda_peak * lambda_peak * lambda_peak * lambda_peak)
                         / (std::exp(peak_hc) - 1.0);

    return clampd(spectral / dmax(peak_spectral, 1e-30), 0.0, 8.0);
}

}} // namespace gem::spectral
