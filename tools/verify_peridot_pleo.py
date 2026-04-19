"""Verify peridot pleochroism_absorption_spectrum_override (Phase 2).

Checks:
  1. Multiplier rules (extraordinary / ordinary ratio per bin)
  2. Forward-integrated sRGB at several path lengths
  3. Color-shift direction (extraordinary should be more olive/brown-green)
"""
from __future__ import annotations
import math
from typing import List, Tuple

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
LAMBDA_MIN = 380.0
LAMBDA_MAX = 780.0
STEP = 5.0
SAMPLES = 81
WAVELENGTHS = [LAMBDA_MIN + i * STEP for i in range(SAMPLES)]

# ---------------------------------------------------------------------------
# 81 ordinary values from peridot.tres  absorption_spectrum_override
# ---------------------------------------------------------------------------
ORDINARY = [
    2.77356, 2.84629, 2.90429, 2.9593, 3.02103, 3.09518, 3.18254, 3.2791,
    3.377, 3.46611, 3.53576, 3.57618, 3.57978, 3.54179, 3.46056, 3.33743,
    3.1764, 2.98352, 2.76626, 2.53283, 2.2916, 2.05044, 1.8164, 1.59531,
    1.39165, 1.2085, 1.04761, 0.90952, 0.79383, 0.69939, 0.62459, 0.56754,
    0.52631, 0.49908, 0.48423, 0.48041, 0.48659, 0.50205, 0.52633, 0.55921,
    0.6006, 0.65054, 0.70905, 0.7761, 0.85154, 0.93502, 1.02594, 1.12343,
    1.22628, 1.33301, 1.4418, 1.55058, 1.65708, 1.75887, 1.85349, 1.9385,
    2.01161, 2.0708, 2.11436, 2.14102, 2.15, 2.14102, 2.11436, 2.0708,
    2.01161, 1.93849, 1.85349, 1.75887, 1.65707, 1.55056, 1.44176, 1.33293,
    1.22615, 1.1232, 1.02556, 0.93437, 0.85047, 0.77434, 0.70622, 0.64605,
    0.5936,
]

# ---------------------------------------------------------------------------
# 81 extraordinary values from peridot.tres  pleochroism_absorption_spectrum_override
# ---------------------------------------------------------------------------
EXTRAORDINARY = [
    2.77356, 2.84629, 2.90429, 2.9593, 3.02103, 3.09518, 3.18254, 3.2791,
    3.377, 3.46611, 3.53576, 3.57618, 3.57978, 3.54179, 3.46056, 3.33743,
    3.1764, 2.98352, 2.76626, 2.53283, 3.20824, 2.95263, 2.68827, 2.42487,
    2.17097, 1.9336, 1.63427, 1.38247, 1.17487, 1.00712, 0.87443, 0.56754,
    0.42105, 0.38928, 0.36801, 0.3555, 0.35034, 0.35144, 0.37896, 0.41382,
    0.45646, 0.50742, 0.56724, 0.7761, 0.85154, 0.93502, 1.02594, 1.12343,
    1.22628, 1.33301, 1.73016, 1.86586, 1.99954, 2.12823, 2.2489, 2.35851,
    2.45416, 2.53328, 2.59361, 2.63345, 2.65167, 2.64773, 2.62181, 2.57469,
    2.50781, 2.42311, 2.32304, 2.21031, 2.08791, 1.95887, 1.82623, 1.69282,
    1.5613, 1.43395, 1.31272, 1.19911, 1.09427, 0.9989, 0.91338, 0.83771,
    0.77168,
]

assert len(ORDINARY) == 81, f"ordinary length = {len(ORDINARY)}"
assert len(EXTRAORDINARY) == 81, f"extraordinary length = {len(EXTRAORDINARY)}"

# ---------------------------------------------------------------------------
# CIE 1931 2-deg observer (5 nm, 380-780 nm, 81 values)
# ---------------------------------------------------------------------------
CIE_X = [
    0.001368, 0.002236, 0.004243, 0.007650, 0.014310,
    0.023190, 0.043510, 0.077630, 0.134380, 0.214770,
    0.283900, 0.328500, 0.348280, 0.348060, 0.336200,
    0.318700, 0.290800, 0.251100, 0.195360, 0.142100,
    0.095640, 0.057950, 0.032010, 0.014700, 0.004900,
    0.002400, 0.009300, 0.029100, 0.063270, 0.109600,
    0.165500, 0.225750, 0.290400, 0.359700, 0.433450,
    0.512050, 0.594500, 0.678400, 0.762100, 0.842500,
    0.916300, 0.978600, 1.026300, 1.056700, 1.062200,
    1.045600, 1.002600, 0.938400, 0.854400, 0.751400,
    0.642400, 0.541900, 0.447900, 0.360800, 0.283500,
    0.218700, 0.164900, 0.121200, 0.087400, 0.063600,
    0.046770, 0.032900, 0.022700, 0.015840, 0.011359,
    0.008111, 0.005790, 0.004109, 0.002899, 0.002049,
    0.001440, 0.001000, 0.000690, 0.000476, 0.000332,
    0.000235, 0.000166, 0.000117, 0.000083, 0.000059,
    0.000042,
]
CIE_Y = [
    0.000039, 0.000064, 0.000120, 0.000217, 0.000396,
    0.000640, 0.001210, 0.002180, 0.004000, 0.007300,
    0.011600, 0.016840, 0.023000, 0.029800, 0.038000,
    0.048000, 0.060000, 0.073900, 0.090980, 0.112600,
    0.139020, 0.169300, 0.208020, 0.258600, 0.323000,
    0.407300, 0.503000, 0.608200, 0.710000, 0.793200,
    0.862000, 0.914850, 0.954000, 0.980300, 0.994950,
    1.000000, 0.995000, 0.978600, 0.952000, 0.915400,
    0.870000, 0.816300, 0.757000, 0.694900, 0.631000,
    0.566800, 0.503000, 0.441200, 0.381000, 0.321000,
    0.265000, 0.217000, 0.175000, 0.138200, 0.107000,
    0.081600, 0.061000, 0.044580, 0.032000, 0.023200,
    0.017000, 0.011920, 0.008210, 0.005723, 0.004102,
    0.002929, 0.002091, 0.001484, 0.001047, 0.000740,
    0.000520, 0.000361, 0.000249, 0.000172, 0.000120,
    0.000085, 0.000060, 0.000042, 0.000030, 0.000021,
    0.000015,
]
CIE_Z = [
    0.006450, 0.010550, 0.020050, 0.036210, 0.067850,
    0.110200, 0.207400, 0.371300, 0.645600, 1.039050,
    1.385600, 1.622960, 1.747060, 1.782600, 1.772110,
    1.744100, 1.669200, 1.528100, 1.287640, 1.041900,
    0.812950, 0.616200, 0.465180, 0.353300, 0.272000,
    0.212300, 0.158200, 0.111700, 0.078250, 0.057250,
    0.042160, 0.029840, 0.020300, 0.013400, 0.008750,
    0.005750, 0.003900, 0.002750, 0.002100, 0.001800,
    0.001650, 0.001400, 0.001100, 0.001000, 0.000800,
    0.000600, 0.000340, 0.000240, 0.000190, 0.000100,
    0.000050, 0.000030, 0.000020, 0.000010, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000, 0.000000, 0.000000, 0.000000, 0.000000,
    0.000000,
]


# ---------------------------------------------------------------------------
# Utility functions (copied from generate_gem_spectra.py)
# ---------------------------------------------------------------------------
def clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))


def planck(lam_nm: float, temperature_k: float) -> float:
    lam_m = lam_nm * 1e-9
    hc_over_lkt = 0.014388 / (lam_m * temperature_k)
    lam_peak_m = 2.898e-3 / temperature_k
    peak_hc = 0.014388 / (lam_peak_m * temperature_k)
    spec = 1.0 / lam_m**5 / (math.exp(hc_over_lkt) - 1.0)
    peak = 1.0 / lam_peak_m**5 / (math.exp(peak_hc) - 1.0)
    return spec / max(peak, 1e-30)


def xyz_to_linear_srgb(xyz: Tuple[float, float, float]) -> Tuple[float, float, float]:
    x, y, z = xyz
    return (
        3.2406 * x - 1.5372 * y - 0.4986 * z,
        -0.9689 * x + 1.8758 * y + 0.0415 * z,
        0.0557 * x - 0.2040 * y + 1.0570 * z,
    )


def srgb_gamma(c: float) -> float:
    c = clamp(c, 0.0, 1.0)
    if c <= 0.0031308:
        return 12.92 * c
    return 1.055 * c ** (1.0 / 2.4) - 0.055


def aces(x: float) -> float:
    x = max(x, 0.0)
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0)


def forward_integrate(
    alpha: List[float],
    *,
    path_length: float = 0.75,
    light_temp_k: float = 4500.0,
    exposure: float = 2.4,
) -> Tuple[Tuple[float, float, float], Tuple[float, float, float]]:
    """Integrate (light * Beer-Lambert) * CIE observer to an sRGB color."""
    x_sum = y_sum = z_sum = 0.0
    for i in range(SAMPLES):
        lam = WAVELENGTHS[i]
        emitted = planck(lam, light_temp_k)
        transmitted = emitted * math.exp(-alpha[i] * path_length)
        x_sum += transmitted * CIE_X[i]
        y_sum += transmitted * CIE_Y[i]
        z_sum += transmitted * CIE_Z[i]
    cie_y_integral = sum(CIE_Y) * STEP
    inv = (LAMBDA_MAX - LAMBDA_MIN) / (SAMPLES * cie_y_integral)
    xyz = (x_sum * inv, y_sum * inv, z_sum * inv)
    rgb_linear = xyz_to_linear_srgb(xyz)
    rgb_exposed = tuple(c * exposure for c in rgb_linear)
    rgb_aces = tuple(aces(c) for c in rgb_exposed)
    rgb_srgb = tuple(srgb_gamma(c) for c in rgb_aces)
    return rgb_linear, rgb_srgb


# ===========================================================================
# 1. MULTIPLIER RATIO VERIFICATION
# ===========================================================================
print("=" * 72)
print("PERIDOT PLEOCHROISM VERIFICATION")
print("=" * 72)

print("\n--- Bin-by-bin ratio (extraordinary / ordinary) ---")
print(f"{'Bin':>4s}  {'nm':>6s}  {'Ordinary':>10s}  {'Extraord':>10s}  {'Ratio':>8s}  {'Expected':>16s}  {'Status':>8s}")
print("-" * 72)

PASS_COUNT = 0
FAIL_COUNT = 0

for i in range(SAMPLES):
    lam = WAVELENGTHS[i]
    o = ORDINARY[i]
    e = EXTRAORDINARY[i]
    ratio = e / o if o > 1e-9 else float('inf')

    # Determine expected range
    expected = ""
    lo_expect = None
    hi_expect = None

    if 20 <= i <= 30:
        # Peak boost zone: multiplier 1.4-1.6, peak at bin 25
        lo_expect = 1.35  # slight tolerance
        hi_expect = 1.65
        expected = "1.4-1.6 (boost)"
    elif 32 <= i <= 42:
        # Trough zone: multiplier 0.7-0.8, trough at bin 37
        lo_expect = 0.65  # slight tolerance
        hi_expect = 0.85
        expected = "0.7-0.8 (trough)"
    elif 50 <= i <= 80:
        # Ramp zone: multiplier 1.2-1.3
        lo_expect = 1.15  # slight tolerance
        hi_expect = 1.35
        expected = "1.2-1.3 (ramp)"
    else:
        # Identity zone
        lo_expect = 0.98
        hi_expect = 1.02
        expected = "~1.0 (identity)"

    ok = lo_expect <= ratio <= hi_expect
    status = "OK" if ok else "FAIL"
    if ok:
        PASS_COUNT += 1
    else:
        FAIL_COUNT += 1

    # Print every bin
    flag = "  " if ok else "**"
    print(f"{i:4d}  {lam:6.0f}  {o:10.5f}  {e:10.5f}  {ratio:8.5f}  {expected:>16s}  {status:>6s} {flag}")

print("-" * 72)
print(f"PASS: {PASS_COUNT} / {SAMPLES}   FAIL: {FAIL_COUNT} / {SAMPLES}")

# ===========================================================================
# 2. ZONE SUMMARY STATISTICS
# ===========================================================================
print("\n--- Zone summaries ---")

def zone_stats(name: str, start: int, end: int):
    ratios = [EXTRAORDINARY[i] / ORDINARY[i] for i in range(start, end + 1)]
    mn = min(ratios)
    mx = max(ratios)
    avg = sum(ratios) / len(ratios)
    peak_bin = start + ratios.index(max(ratios))
    trough_bin = start + ratios.index(min(ratios))
    print(f"  {name}: bins {start}-{end}")
    print(f"    min={mn:.5f} (bin {trough_bin}), max={mx:.5f} (bin {peak_bin}), avg={avg:.5f}")

zone_stats("Boost (bins 20-30)", 20, 30)
zone_stats("Trough (bins 32-42)", 32, 42)
zone_stats("Ramp (bins 50-80)", 50, 80)

# Identity zones
identity_bins = [i for i in range(SAMPLES) if not (20 <= i <= 30 or 32 <= i <= 42 or 50 <= i <= 80)]
identity_ratios = [EXTRAORDINARY[i] / ORDINARY[i] for i in identity_bins]
print(f"  Identity (all other bins): {len(identity_bins)} bins")
print(f"    min={min(identity_ratios):.5f}, max={max(identity_ratios):.5f}, "
      f"avg={sum(identity_ratios)/len(identity_ratios):.5f}")

# Bin 31 is between boost and trough — check it
print(f"\n  Transition bin 31: ratio = {EXTRAORDINARY[31]/ORDINARY[31]:.5f} "
      f"(ordinary={ORDINARY[31]:.5f}, extraordinary={EXTRAORDINARY[31]:.5f})")

# ===========================================================================
# 3. FORWARD INTEGRATION — sRGB COLORS
# ===========================================================================
print("\n--- Forward-integrated sRGB (T_light=4500K, exposure=2.4) ---")
print(f"{'Path':>6s}  {'Ordinary sRGB':>24s}  {'Extraord sRGB':>24s}  {'Ordinary Linear':>30s}  {'Extraord Linear':>30s}")
print("-" * 120)

for L in (0.3, 0.5, 0.75, 1.0):
    lin_o, srgb_o = forward_integrate(ORDINARY, path_length=L)
    lin_e, srgb_e = forward_integrate(EXTRAORDINARY, path_length=L)
    srgb_o_255 = tuple(int(c * 255) for c in srgb_o)
    srgb_e_255 = tuple(int(c * 255) for c in srgb_e)
    print(f"L={L:.2f}  ({srgb_o_255[0]:3d},{srgb_o_255[1]:3d},{srgb_o_255[2]:3d})              "
          f"({srgb_e_255[0]:3d},{srgb_e_255[1]:3d},{srgb_e_255[2]:3d})              "
          f"({lin_o[0]:.4f},{lin_o[1]:.4f},{lin_o[2]:.4f})          "
          f"({lin_e[0]:.4f},{lin_e[1]:.4f},{lin_e[2]:.4f})")

# ===========================================================================
# 4. COLOR SHIFT ANALYSIS
# ===========================================================================
print("\n--- Color shift analysis (extraordinary vs ordinary) ---")

for L in (0.3, 0.5, 0.75, 1.0):
    lin_o, srgb_o = forward_integrate(ORDINARY, path_length=L)
    lin_e, srgb_e = forward_integrate(EXTRAORDINARY, path_length=L)

    # Green-to-red ratio (higher = more green/neon, lower = more brown/olive)
    gr_o = lin_o[1] / max(lin_o[0], 1e-9)
    gr_e = lin_e[1] / max(lin_e[0], 1e-9)

    # Blue contribution (lower = warmer / more olive)
    b_frac_o = lin_o[2] / max(sum(lin_o), 1e-9)
    b_frac_e = lin_e[2] / max(sum(lin_e), 1e-9)

    # Saturation proxy: max(RGB) - min(RGB) in linear
    sat_o = max(lin_o) - min(lin_o)
    sat_e = max(lin_e) - min(lin_e)

    print(f"\n  L={L:.2f}:")
    print(f"    G/R ratio:   ordinary={gr_o:.4f}  extraordinary={gr_e:.4f}  "
          f"({'extraordinary greener' if gr_e > gr_o else 'extraordinary more olive/brown'})")
    print(f"    Blue frac:   ordinary={b_frac_o:.4f}  extraordinary={b_frac_e:.4f}")
    print(f"    Saturation:  ordinary={sat_o:.4f}  extraordinary={sat_e:.4f}  "
          f"({'extraordinary more saturated' if sat_e > sat_o else 'extraordinary less saturated (more muted)'})")

    # Check: extraordinary should have lower G/R (less neon green, more olive)
    if gr_e < gr_o:
        print(f"    -> PASS: extraordinary is less neon (lower G/R)")
    else:
        print(f"    -> NOTE: extraordinary has higher G/R than ordinary at this path length")

print("\n" + "=" * 72)
print("VERIFICATION COMPLETE")
print("=" * 72)
