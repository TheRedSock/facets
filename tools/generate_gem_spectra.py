"""Generate physically-plausible absorption spectra for five gems.

Outputs 81-value PackedFloat32Array strings ready to paste into .tres files,
plus a forward-integration sanity check against a neutral warm light to confirm
the resulting xyY sits close to the authored display_color.

IMPORTANT: absorption values here are in per-unit-path (alpha), where "unit"
is one world-space unit in the renderer. Typical internal chord lengths in
faceted gems are 0.3-1.2 world units, so peak alphas need to be ~10-20 to
fully suppress the CIE Y response in the 530-580nm band. Values like 3-8 at
peak are too low: even 1% green transmission at 555nm dominates a 50% red
transmission at 680nm, because CIE Y peaks at 555nm.

Run-time: ~40 ms. No external dependencies.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable, List, Tuple

LAMBDA_MIN = 380.0
LAMBDA_MAX = 780.0
STEP = 5.0
SAMPLES = 81
WAVELENGTHS = [LAMBDA_MIN + i * STEP for i in range(SAMPLES)]


def gauss(lam: float, center: float, width: float) -> float:
    delta = (lam - center) / max(width, 1e-6)
    return math.exp(-0.5 * delta * delta)


def clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))


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
    # C++ clamps negatives to zero *before* the rational, because the
    # rational produces spurious high values for out-of-gamut (negative)
    # inputs.  We mirror that here so Python sanity checks stay in sync
    # with the on-device tracer.
    x = max(x, 0.0)
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0)


def forward_integrate(
    alpha: List[float],
    *,
    path_length: float = 0.75,
    light_temp_k: float = 4500.0,
    exposure: float = 2.4,
) -> Tuple[Tuple[float, float, float], Tuple[float, float, float]]:
    """Integrate (light * Beer-Lambert) * CIE observer to an sRGB color.

    Default path_length=0.75 approximates an average internal chord across
    a faceted gem of radius ~0.5 with 2-3 internal bounces.
    """
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


# ---------------------------------------------------------------------------
# Per-gem absorption curves (sums of physically-meaningful bands).
# Peak alphas are sized so that at path length ~0.75 the integrated sRGB sits
# close to the authored display_color. Alpha=15-20 in the 540-580nm band is
# required to kill the CIE Y response (which peaks at 555nm).
# ---------------------------------------------------------------------------

@dataclass
class Spectrum:
    name: str
    alpha: Callable[[float], float]
    display_color: Tuple[float, float, float]
    notes: str = ""
    pleochroism: Callable[[float], float] | None = None


def ruby_alpha(lam: float) -> float:
    """Cr3+ in corundum.

    Bands:
      - Y (violet) ~420 nm, broad enough that the 450-490 nm blue window
        closes and we don't bleed cyan.
      - U (yellow-green) ~550 nm, very strong (peak alpha >=18) so the gem
        kills CIE Y completely at realistic path lengths.
      - Narrow red-orange transmission begins ~610 nm and extends past 720 nm
        with baseline alpha ~0.3.
      - alpha(694 nm) stays below ~0.5 so the Cr3+ R-line fluorescence escapes.
    """
    a_y = 10.0 * gauss(lam, 420.0, 45.0)
    a_u = 19.0 * gauss(lam, 550.0, 38.0)
    a_uv = 4.5 * math.exp(-(lam - 380.0) / 18.0) if lam < 420.0 else 0.0
    a_nir = 0.5 * math.exp((lam - 780.0) / 40.0) if lam > 720.0 else 0.0
    baseline = 0.30
    return a_y + a_u + a_uv + a_nir + baseline


def rhodolite_alpha(lam: float) -> float:
    """Pyrope-almandine (raspberry/magenta tone).

    Compared to ruby the red window is slightly narrower (starts later near
    620nm), and the blue-violet window near 460nm is *wider* — that is what
    gives rhodolite its magenta/raspberry tone rather than pure red.
    """
    a_violet = 4.0 * gauss(lam, 420.0, 35.0)
    a_main = 14.0 * gauss(lam, 540.0, 40.0)
    a_uv = 3.5 * math.exp(-(lam - 380.0) / 22.0) if lam < 430.0 else 0.0
    a_nir = 0.5 * math.exp((lam - 780.0) / 45.0) if lam > 700.0 else 0.0
    baseline = 0.45
    return a_violet + a_main + a_uv + a_nir + baseline


def painite_ordinary_alpha(lam: float) -> float:
    """Painite ordinary ray (dark reddish-brown, Fe-Ti charge transfer).

    Natural painite is a muted brownish / orange-red, not a saturated red.
    Target behaviour (after path integration): R noticeably > G > B with
    non-zero G so the result desaturates into an orange-brown rather than
    saturating to pure red.  We keep the charge-transfer band narrow and
    centred on cyan-green so yellow / orange (570-620 nm) leaks through.
    """
    a_main = 4.8 * gauss(lam, 510.0, 60.0)
    a_blue_shoulder = 1.5 * gauss(lam, 430.0, 35.0)
    a_uv = 3.5 * math.exp(-(lam - 380.0) / 18.0) if lam < 420.0 else 0.0
    red_ramp = 1.2 * max(0.0, (lam - 620.0) / 80.0) if lam > 620.0 else 0.0
    baseline = 1.4
    return a_main + a_blue_shoulder + a_uv + red_ramp + baseline


def painite_extraordinary_alpha(lam: float) -> float:
    """Extraordinary ray — similar profile, 15-20% stronger body band."""
    a_main = 5.5 * gauss(lam, 515.0, 60.0)
    a_blue_shoulder = 1.8 * gauss(lam, 430.0, 35.0)
    a_uv = 3.8 * math.exp(-(lam - 380.0) / 18.0) if lam < 420.0 else 0.0
    red_ramp = 1.4 * max(0.0, (lam - 620.0) / 80.0) if lam > 620.0 else 0.0
    baseline = 1.5
    return a_main + a_blue_shoulder + a_uv + red_ramp + baseline


def smoky_quartz_alpha(lam: float) -> float:
    """Al-O- color center tail — monotonically descending from UV to NIR.

    Classic smoky-brown: strong UV-blue absorption, moderate-to-high green,
    noticeable red.  A flatter tail (long decay length) with a high baseline
    keeps the red channel from running away and gives a warm-neutral brown
    at typical path lengths, rather than a saturated yellow-orange.
    """
    # Flatter exponential tail — primary body absorption.  Slower decay
    # means red is absorbed almost as much as green, yielding a brown.
    a_tail = 5.5 * math.exp(-(lam - 380.0) / 140.0)
    # Extra UV boost to kill the deep violet completely.
    a_uv = 3.0 * math.exp(-(lam - 380.0) / 25.0) if lam < 450.0 else 0.0
    # High baseline absorbs uniformly so even red transmits only a little —
    # this is what turns a yellow gem into a brown one at typical chords.
    baseline = 1.40
    return a_tail + a_uv + baseline


def tourmaline_rubellite_alpha(lam: float) -> float:
    """Mn3+ bearing rubellite (pink body).

    With correctly calibrated CIE observers, we no longer need the
    ultra-aggressive alpha=14 peak to overcome a green bias: alpha~9 at
    540 nm gives a bright hot-pink body at typical 0.4-0.6 chord lengths.
    - Mn2+ shoulder ~430 nm closes the blue window enough for a clean pink
      (not magenta) at thin edges.
    - Mn3+ main band ~540 nm absorbs yellow-green.
    - Open red transmission above 620 nm.
    """
    a_mn2 = 4.5 * gauss(lam, 430.0, 32.0)
    a_mn3 = 9.0 * gauss(lam, 540.0, 40.0)
    a_uv = 3.0 * math.exp(-(lam - 380.0) / 22.0) if lam < 420.0 else 0.0
    a_nir = 0.4 * math.exp((lam - 780.0) / 50.0) if lam > 700.0 else 0.0
    baseline = 0.30
    return a_mn2 + a_mn3 + a_uv + a_nir + baseline


def tourmaline_verdelite_alpha(lam: float) -> float:
    """Fe2+ bearing verdelite (green rim for watermelon zoning).

    The color balance on this curve is fiddly because y-bar peaks at 555 nm
    right next to the green transmission window, so even a little leakage
    above 540 nm turns the result chartreuse.  We therefore place the
    yellow absorption band at 575 nm (well clear of 520 nm) with a modest
    width, and couple it with a stronger 605 nm orange band.
    """
    a_red_band = 10.0 * gauss(lam, 680.0, 60.0)
    a_orange = 8.0 * gauss(lam, 605.0, 22.0)
    a_yellow = 7.0 * gauss(lam, 575.0, 18.0)
    a_violet = 9.0 * gauss(lam, 420.0, 38.0)
    a_uv = 4.5 * math.exp(-(lam - 380.0) / 20.0) if lam < 420.0 else 0.0
    baseline = 0.35
    return a_red_band + a_orange + a_yellow + a_violet + a_uv + baseline


# ---------------------------------------------------------------------------
# Atlas-tuning recipes (2026-04 review pass).
# Each recipe below targets a specific regression noted in the rotation atlas
# reference build. Integration probes should land near the listed target color
# at L ≈ 0.5–0.75 (typical faceted chord).
# ---------------------------------------------------------------------------


def amethyst_deep_alpha(lam: float) -> float:
    """Amethyst (Fe4+ colour centre) — deeper purple.

    Purple = transmit violet + red, absorb green. The previous curve peaked
    at ~4 α over a wide green band (leaking too much Y*) and let enough red
    through that the stone read as lavender/pink. Pull both wings open and
    bolt a tall, narrower Mn-Fe band over the green window:

      - 420-440 nm: near-zero α (violet window wide open).
      - 540-560 nm: peak α ≈ 12 (kills CIE Y, defining the purple hue).
      - 660-700 nm: α ≈ 0.4 (red transmission for the raspberry edge).
    """
    a_main = 12.0 * gauss(lam, 545.0, 40.0)
    a_wing = 2.5 * gauss(lam, 625.0, 42.0)
    a_uv = 2.0 * math.exp(-(lam - 380.0) / 24.0) if lam < 420.0 else 0.0
    a_nir = 0.3 * math.exp((lam - 780.0) / 70.0) if lam > 700.0 else 0.0
    baseline = 0.45
    return a_main + a_wing + a_uv + a_nir + baseline


def smoky_quartz_neutral_alpha(lam: float) -> float:
    """Smoky quartz (Al-O- colour centre) — flat, neutral brown.

    The 2025 curve was a pure exponential decay from UV, which — even with a
    raised baseline — still let much more red through than green/blue, so the
    gem read orange. Classic smoky should be a cool-neutral brown: roughly
    the same transmission across the entire visible range, with a mild UV
    shoulder for warmth.

      - Flat baseline α ≈ 3.0 across the full band (neutral grey-brown body).
      - Gentle UV lift so 380-430 nm absorbs a touch more than red (warm cast).
      - NO monotonic tail — red transmission is kept in line with green.
    """
    baseline = 3.0
    a_uv_shoulder = 1.8 * math.exp(-(lam - 380.0) / 70.0)
    a_uv_peak = 1.2 * math.exp(-(lam - 380.0) / 22.0) if lam < 430.0 else 0.0
    # Slight red pullback so we don't drift into yellow at long chords.
    a_red_tip = 0.5 * max(0.0, (lam - 640.0) / 120.0) if lam > 640.0 else 0.0
    return baseline + a_uv_shoulder + a_uv_peak + a_red_tip


def tourmaline_rubellite_soft_alpha(lam: float) -> float:
    """Tourmaline rubellite — softer body (halve the 2025 peak).

    The trillion-cut tourmaline was rendering near black. Drop the Mn3+ peak
    from ~9 to ~4.5 so 0.4-0.6 chords read bright pink instead of plum.
    """
    a_mn2 = 2.0 * gauss(lam, 430.0, 32.0)
    a_mn3 = 4.5 * gauss(lam, 540.0, 42.0)
    a_uv = 1.6 * math.exp(-(lam - 380.0) / 24.0) if lam < 420.0 else 0.0
    a_nir = 0.25 * math.exp((lam - 780.0) / 50.0) if lam > 700.0 else 0.0
    baseline = 0.20
    return a_mn2 + a_mn3 + a_uv + a_nir + baseline


def tourmaline_verdelite_soft_alpha(lam: float) -> float:
    """Tourmaline verdelite — softer green zone (halve 2025 peak).

    The zone curve peaked at ~15 which combined with the body spectrum
    produced charcoal edges in watermelon zoning. Cap all bands near α ≈ 5.
    """
    a_red_band = 5.0 * gauss(lam, 680.0, 60.0)
    a_orange = 4.0 * gauss(lam, 605.0, 22.0)
    a_yellow = 3.5 * gauss(lam, 575.0, 18.0)
    a_violet = 4.5 * gauss(lam, 420.0, 38.0)
    a_uv = 2.2 * math.exp(-(lam - 380.0) / 22.0) if lam < 420.0 else 0.0
    baseline = 0.25
    return a_red_band + a_orange + a_yellow + a_violet + a_uv + baseline


def rhodolite_magenta_alpha(lam: float) -> float:
    """Rhodolite garnet — open the violet-blue window for true magenta.

    Old curve put α ≈ 3.5 around 380-430 nm (from the UV exponential AND the
    violet Gaussian), which killed the blue contribution and left the stone
    reading as dark red. Real rhodolite shows a clean magenta because the
    violet window stays partially open. We drop the violet Gaussian peak
    from 4 to 2 and lower its UV tail.
    """
    a_violet = 2.0 * gauss(lam, 420.0, 35.0)
    a_main = 14.0 * gauss(lam, 540.0, 40.0)
    a_uv = 1.6 * math.exp(-(lam - 380.0) / 22.0) if lam < 430.0 else 0.0
    a_nir = 0.4 * math.exp((lam - 780.0) / 45.0) if lam > 700.0 else 0.0
    baseline = 0.35
    return a_violet + a_main + a_uv + a_nir + baseline


def aquamarine_clear_alpha(lam: float) -> float:
    """Aquamarine (Fe2+) — lighter, cleaner transmission.

    The 2025 curve peaked at α ≈ 2.2 near 620 nm. Combined with the kite cut's
    pavilion that's enough internal path to read as "light blue sapphire".
    We lower everything by ~40% and keep the 380-450 nm violet window wide
    open so the stone reads as a pale, crystalline blue.
    """
    # Fe2+ absorption peaks around ~620-640 nm (yellow-red removal).
    a_main = 1.35 * gauss(lam, 625.0, 85.0)
    # Long red tail kept intentionally low — aquamarine's red transmission is
    # low but present.
    a_red = 0.75 * gauss(lam, 720.0, 80.0)
    # Mild UV shoulder for authenticity; keep 380-430 nm transmissive.
    a_uv = 0.15 * math.exp(-(lam - 380.0) / 40.0) if lam < 430.0 else 0.0
    baseline = 0.05
    return a_main + a_red + a_uv + baseline


def alexandrite_turquoise_alpha(lam: float) -> float:
    """Alexandrite daylight body — turquoise (green-leaning blue).

    Multiple internal bounces in faceted geometry accumulate long path
    lengths (≈1.0-1.5 world units), so we keep peak α modest and narrow.
    Target sRGB at L=0.75 chord: approximately (15,140,170) — clear teal.

    Turquoise = transmit 475-530 nm (green-blue), absorb yellow + red.
      - Narrow yellow-orange block at 590 nm (Cr3+ U band, peak α ≈ 5.0).
      - Deep-red block at 680 nm to avoid pink spill.
      - Mild violet shoulder at 445 nm to steer hue toward green-blue.
      - Low baseline (α ≈ 0.2) so the stone stays bright.
    """
    a_main = 5.0 * gauss(lam, 590.0, 38.0)
    a_red = 2.6 * gauss(lam, 680.0, 42.0)
    a_blue_block = 2.6 * gauss(lam, 460.0, 40.0)
    a_uv = 1.8 * math.exp(-(lam - 380.0) / 22.0) if lam < 430.0 else 0.0
    a_green_lift = -0.4 * gauss(lam, 510.0, 24.0)
    baseline = 0.20
    return max(0.0, a_main + a_red + a_blue_block + a_uv + a_green_lift + baseline)


def alexandrite_incandescent_alpha(lam: float) -> float:
    """Alexandrite incandescent (phenomenon zone) — deep violet/magenta.

    Phenomenon curve used when the viewing geometry aligns with the
    extraordinary axis. Transmit violet + red, absorb green-blue.
      - Strong cyan-green block at 490-560 nm.
      - Blue window shifted deep into violet (420-450 nm).
      - Red wing open from 620 nm onward.
    """
    a_cyan = 9.0 * gauss(lam, 515.0, 38.0)
    a_green = 5.0 * gauss(lam, 560.0, 30.0)
    a_uv = 1.2 * math.exp(-(lam - 380.0) / 32.0) if lam < 420.0 else 0.0
    # Keep a mild 480 nm pullback so the violet is deep, not electric blue.
    a_blue_trim = 2.0 * gauss(lam, 475.0, 22.0)
    baseline = 0.35
    return a_cyan + a_green + a_uv + a_blue_trim + baseline


def ruby_tight_alpha(lam: float) -> float:
    """Ruby (Cr3+) — tightened blue window to eliminate yellow edge spill.

    Previous override left α ≈ 10-11 near 420 nm but dropped to ~8 around
    460-480 nm. That narrow sag let a sliver of blue-through-green escape
    at thin edges which, combined with the hot key card, produced a
    yellow/orange fringe in the marquise cut. We flatten the 420-500 nm
    band to a consistent high plateau so only the deep-red window really
    transmits.
    """
    a_y = 11.5 * gauss(lam, 425.0, 55.0)     # wider violet lobe
    a_u = 19.0 * gauss(lam, 550.0, 38.0)     # unchanged yellow-green band
    a_blue_fill = 4.0 * gauss(lam, 475.0, 30.0)  # NEW: close the 460-490 sag
    a_uv = 4.5 * math.exp(-(lam - 380.0) / 18.0) if lam < 420.0 else 0.0
    a_nir = 0.5 * math.exp((lam - 780.0) / 40.0) if lam > 720.0 else 0.0
    baseline = 0.35
    return a_y + a_u + a_blue_fill + a_uv + a_nir + baseline


def painite_strong_alpha(lam: float) -> float:
    """Painite — stronger dark brown-red with a deeper umber floor.

    The prior build relied on the mineral template plus strength scale 0.78,
    so the navette read as a bright coral. Real painite is very dark — close
    to garnet-red-brown at typical chords. We slightly widen the main band,
    push UV further shut, and lift the baseline to ~2.0.
    """
    a_main = 6.2 * gauss(lam, 510.0, 65.0)
    a_blue_shoulder = 3.2 * gauss(lam, 435.0, 38.0)
    a_uv = 4.5 * math.exp(-(lam - 380.0) / 16.0) if lam < 430.0 else 0.0
    red_ramp = 1.8 * max(0.0, (lam - 620.0) / 80.0) if lam > 620.0 else 0.0
    baseline = 2.0
    return a_main + a_blue_shoulder + a_uv + red_ramp + baseline


def blue_garnet_body_alpha(lam: float) -> float:
    """Blue garnet body — near-black ground with a wide teal window.

    Target: stone reads very dark overall, with a clear teal-blue flash at
    ~480 nm in specular bounces and a subtle maroon glow at ~680 nm in the
    thickest chords. Compared with the 2025 first pass we:
      - *Widen* the teal window (σ 28 nm) and dig it deeper (α ≈ 0.2 at min)
        so enough cool light escapes to read blue under 4500-6500K lighting.
      - *Narrow* the maroon window (σ 22 nm, lifted centre to 670 nm) and
        cap its min at α ≈ 0.8 so the red channel stays subordinate.
      - Keep a firm α ≈ 4.5 baseline elsewhere so the body still reads ~black.
    """
    baseline = 4.5
    teal_window = -4.3 * gauss(lam, 480.0, 28.0)
    maroon_window = -2.0 * gauss(lam, 670.0, 22.0)
    a_uv = 4.0 * math.exp(-(lam - 380.0) / 18.0) if lam < 420.0 else 0.0
    return max(0.20, baseline + teal_window + maroon_window + a_uv)


def ruby_epsilon_alpha(lam: float) -> float:
    """Ruby extraordinary ray (∥c, corundum).

    Compared to the ordinary ⊥c view (ruby_tight_alpha):
      - Violet lobe moves redward (405 → 415 nm) and weakens slightly, so the
        blue shoulder transmits a touch more — pulls hue toward orange-red.
      - U-band centre shifts from 550 → 545 nm (a few nm, typical for Cr3+).
      - Wider 460-500 nm plateau stays near 7-8 α so the stone still kills
        cyan leakage (the same shoulder fix as ruby_tight).
    Net effect: an orange-red cast with reduced deep-magenta. Real Cr3+/Al2O3
    pleochroism is documented to shift ε toward orange-red vs ω's purplish red.
    """
    a_y = 9.5 * gauss(lam, 415.0, 55.0)
    a_u = 18.0 * gauss(lam, 545.0, 44.0)
    a_blue_fill = 3.2 * gauss(lam, 475.0, 28.0)
    a_uv = 4.0 * math.exp(-(lam - 380.0) / 18.0) if lam < 420.0 else 0.0
    a_nir = 0.4 * math.exp((lam - 780.0) / 40.0) if lam > 720.0 else 0.0
    baseline = 0.40
    return a_y + a_u + a_blue_fill + a_uv + a_nir + baseline


def sapphire_omega_alpha(lam: float) -> float:
    """Blue sapphire ordinary ray (⊥c, corundum).

    Rebuilt from the hand-tuned override currently shipping in sapphire.tres:
    Fe-Ti IVCT band centred around 585-600 nm; broad violet/UV edge; a deep
    blue window open near 450 nm. This is the cooler, more saturated
    'royal blue' tone.
    """
    a_ivct = 6.2 * gauss(lam, 585.0, 70.0)
    a_violet_edge = 2.3 * gauss(lam, 405.0, 30.0)
    a_red = 3.5 * gauss(lam, 720.0, 95.0)
    a_uv = 1.8 * math.exp(-(lam - 380.0) / 30.0) if lam < 430.0 else 0.0
    baseline = 0.50
    return a_ivct + a_violet_edge + a_red + a_uv + baseline


def sapphire_epsilon_alpha(lam: float) -> float:
    """Blue sapphire extraordinary ray (∥c): greener / teal-shifted.

    Fe-Ti IVCT centre moves blueward to ~555 nm and widens slightly; the
    405 nm violet edge deepens. The net effect is a green-blue / teal
    compared to the ω-ray's royal blue. Real sapphires display this
    famously in the 'inky' vs 'open' pleochroism trade distinction.
    """
    a_ivct = 5.8 * gauss(lam, 555.0, 80.0)
    a_violet_edge = 3.5 * gauss(lam, 400.0, 32.0)
    a_red = 4.2 * gauss(lam, 700.0, 80.0)
    a_uv = 2.6 * math.exp(-(lam - 380.0) / 24.0) if lam < 430.0 else 0.0
    baseline = 0.55
    return a_ivct + a_violet_edge + a_red + a_uv + baseline


def emerald_omega_alpha(lam: float) -> float:
    """Emerald ordinary ray (⊥c): classic blue-green.

    Keeps the existing hand-tuned curve shape — Cr3+/V3+ bands blocking
    blue-violet and yellow-red, leaving a wide green-blue transmission
    window centred on 490-510 nm.
    """
    a_violet = 5.2 * gauss(lam, 430.0, 55.0)
    a_yellow = 4.5 * gauss(lam, 590.0, 42.0)
    a_red = 6.8 * gauss(lam, 680.0, 55.0)
    a_uv = 2.4 * math.exp(-(lam - 380.0) / 24.0) if lam < 420.0 else 0.0
    baseline = 0.45
    return a_violet + a_yellow + a_red + a_uv + baseline


def emerald_epsilon_alpha(lam: float) -> float:
    """Emerald extraordinary ray (∥c): yellow-green (warmer, desaturated).

    Cr3+ bands drift such that the transmission window re-centres on
    520-540 nm (pure green / slightly yellow-green) and the 680 nm red
    absorption weakens. This is why emeralds can look 'yellowy' when
    viewed down the c-axis and is part of what makes the best stones
    drop the cut's table perpendicular to c so the cool green face-up
    dominates.
    """
    a_violet = 6.5 * gauss(lam, 420.0, 60.0)
    a_blue = 3.2 * gauss(lam, 460.0, 32.0)
    a_yellow = 3.6 * gauss(lam, 600.0, 48.0)
    a_red = 4.8 * gauss(lam, 690.0, 60.0)
    a_uv = 2.0 * math.exp(-(lam - 380.0) / 24.0) if lam < 420.0 else 0.0
    baseline = 0.40
    return a_violet + a_blue + a_yellow + a_red + a_uv + baseline


def aquamarine_epsilon_alpha(lam: float) -> float:
    """Aquamarine extraordinary ray (∥c): the saturated 'main' blue.

    Real aquamarine shows its most intense blue when viewed down the c-axis.
    We therefore author this as a *stronger* Fe2+ curve than the ω-ray, so
    crown views (aligned with `optic_axis = Vector3(0, 1, 0)`) pick up the
    saturated blue while thin edges with off-axis paths look paler.
    """
    a_main = 2.1 * gauss(lam, 625.0, 85.0)
    a_red = 1.3 * gauss(lam, 720.0, 80.0)
    a_uv = 0.2 * math.exp(-(lam - 380.0) / 40.0) if lam < 430.0 else 0.0
    baseline = 0.10
    return a_main + a_red + a_uv + baseline


def alexandrite_epsilon_alpha(lam: float) -> float:
    """Alexandrite extraordinary ray (∥c): soft red-violet / rose accent.

    Replaces the phenomenon_zone_spectrum hack previously used to fake
    color-change. The Cr3+ absorption in chrysoberyl has its Y-band
    (orange) notably weaker along c than across c, so red transmits
    more freely and the stone drifts to red-violet/magenta.

    Real alexandrite's ε axis is nowhere near as dark as the previous
    α≈10 spectrum implied — we tone down to a rose-violet that pairs
    well with the turquoise ω body. At typical chords this produces
    magenta flashes, not black-magenta dead zones.

      - Modest cyan-green block (~515 nm, α ≈ 4.5).
      - Mild 560-580 nm block keeps yellow out.
      - Deep red window open above 620 nm.
      - Gentle 475 nm pullback so violet stays slightly deep.
    """
    a_cyan = 2.4 * gauss(lam, 515.0, 44.0)
    a_green = 1.3 * gauss(lam, 560.0, 32.0)
    a_uv = 0.6 * math.exp(-(lam - 380.0) / 32.0) if lam < 420.0 else 0.0
    a_blue_trim = 0.5 * gauss(lam, 475.0, 24.0)
    baseline = 0.25
    return a_cyan + a_green + a_uv + a_blue_trim + baseline


def blue_garnet_phenomenon_alpha(lam: float) -> float:
    """Blue garnet phenomenon zone — shifted maroon/burgundy response.

    Under glare / off-axis the stone should bloom into burgundy rather than
    teal. Block the teal window, keep the deep-red window open, add a hint
    of magenta in the NIR-red.
    """
    baseline = 4.5
    teal_block = 2.5 * gauss(lam, 480.0, 28.0)
    maroon_window = -3.5 * gauss(lam, 660.0, 28.0)
    magenta_window = -1.8 * gauss(lam, 720.0, 45.0)
    a_uv = 4.0 * math.exp(-(lam - 380.0) / 18.0) if lam < 420.0 else 0.0
    return max(0.20, baseline + teal_block + maroon_window + magenta_window + a_uv)


# ---------------------------------------------------------------------------
# Emit PackedFloat32Array strings, plus sanity-check color readout.
# ---------------------------------------------------------------------------

def sample_curve(fn: Callable[[float], float]) -> List[float]:
    return [max(0.0, fn(w)) for w in WAVELENGTHS]


def format_packed(values: List[float]) -> str:
    parts = [f"{v:.5f}" for v in values]
    return "PackedFloat32Array(" + ", ".join(parts) + ")"


def report(spectrum: Spectrum) -> None:
    alpha = sample_curve(spectrum.alpha)
    print(f"\n### {spectrum.name}")
    if spectrum.notes:
        print(f"# {spectrum.notes}")
    key_wavelengths = [380, 400, 420, 460, 500, 540, 580, 620, 640, 660,
                       680, 694, 700, 720, 740, 780]
    probes = []
    for kw in key_wavelengths:
        idx = int(round((kw - LAMBDA_MIN) / STEP))
        probes.append(f"{kw}:{alpha[idx]:.1f}")
    print("#", " ".join(probes))
    print("# integrated sRGB at typical path lengths (T_light=4500K, exp=2.4):")
    for L in (0.3, 0.5, 0.75, 1.0, 1.5):
        _, srgb = forward_integrate(alpha, path_length=L)
        print(f"#   L={L:.2f} -> "
              f"({int(srgb[0]*255):3d},{int(srgb[1]*255):3d},{int(srgb[2]*255):3d})")
    tr = spectrum.display_color
    print(f"# target display_color = ({int(tr[0]*255):3d},{int(tr[1]*255):3d},{int(tr[2]*255):3d})")
    print(format_packed(alpha))

    if spectrum.pleochroism is not None:
        pleo = sample_curve(spectrum.pleochroism)
        print(f"# {spectrum.name} pleochroism (extraordinary)")
        print(format_packed(pleo))


def main() -> None:
    spectra = [
        Spectrum("ruby", ruby_alpha, (0.73, 0.08, 0.14),
                 "deep-red window, blue window near 475nm, low alpha at 694nm"),
        Spectrum("ruby_tight", ruby_tight_alpha, (0.70, 0.06, 0.12),
                 "2026-04 retune: close 460-490nm sag, wider violet lobe",
                 ruby_epsilon_alpha),
        Spectrum("rhodolite", rhodolite_alpha, (0.60, 0.06, 0.38),
                 "magenta/raspberry: 540nm main + 460nm blue window, deep red tail"),
        Spectrum("rhodolite_magenta", rhodolite_magenta_alpha, (0.62, 0.08, 0.42),
                 "2026-04 retune: open violet window for true magenta"),
        Spectrum("painite", painite_ordinary_alpha, (0.58, 0.22, 0.12),
                 "Fe-Ti charge transfer, broad 400-580nm, deeper red transmission",
                 painite_extraordinary_alpha),
        Spectrum("painite_strong", painite_strong_alpha, (0.38, 0.12, 0.05),
                 "2026-04 retune: deeper brown-red, UV fully shut"),
        Spectrum("smoky_quartz", smoky_quartz_alpha, (0.52, 0.40, 0.26),
                 "UV-tail color center, warm brown"),
        Spectrum("smoky_quartz_neutral", smoky_quartz_neutral_alpha, (0.44, 0.36, 0.28),
                 "2026-04 retune: flat neutral brown-grey, kill orange bias"),
        Spectrum("amethyst_deep", amethyst_deep_alpha, (0.42, 0.10, 0.58),
                 "2026-04 retune: tall green band for true deep purple"),
        Spectrum("tourmaline_rubellite", tourmaline_rubellite_alpha, (0.88, 0.28, 0.46),
                 "Mn2+/Mn3+ bands, pink transmission"),
        Spectrum("tourmaline_rubellite_soft", tourmaline_rubellite_soft_alpha, (0.90, 0.40, 0.58),
                 "2026-04 retune: halved body for bright pink trillion"),
        Spectrum("tourmaline_verdelite", tourmaline_verdelite_alpha, (0.06, 0.82, 0.36),
                 "Fe2+ band absorbs red, transmits green (watermelon rim)"),
        Spectrum("tourmaline_verdelite_soft", tourmaline_verdelite_soft_alpha, (0.20, 0.80, 0.42),
                 "2026-04 retune: halved zone for brighter watermelon rim"),
        Spectrum("aquamarine_clear", aquamarine_clear_alpha, (0.58, 0.82, 0.94),
                 "2026-04 retune: lighter translucent pale blue",
                 aquamarine_epsilon_alpha),
        Spectrum("alexandrite_turquoise", alexandrite_turquoise_alpha, (0.10, 0.52, 0.48),
                 "2026-04 retune: turquoise green-blue daylight body",
                 alexandrite_epsilon_alpha),
        Spectrum("alexandrite_incandescent", alexandrite_incandescent_alpha, (0.46, 0.08, 0.52),
                 "2026-04 retune: deep violet phenomenon zone"),
        Spectrum("sapphire_omega", sapphire_omega_alpha, (0.05, 0.12, 0.70),
                 "2026-04 pleochroism pair: ⊥c royal blue (ordinary ω)",
                 sapphire_epsilon_alpha),
        Spectrum("emerald_omega", emerald_omega_alpha, (0.04, 0.46, 0.26),
                 "2026-04 pleochroism pair: ⊥c blue-green (ordinary ω)",
                 emerald_epsilon_alpha),
        Spectrum("blue_garnet_body", blue_garnet_body_alpha, (0.04, 0.10, 0.22),
                 "2026-04 retune: near-black body with teal + maroon windows"),
        Spectrum("blue_garnet_phenomenon", blue_garnet_phenomenon_alpha, (0.22, 0.04, 0.12),
                 "2026-04 retune: burgundy phenomenon zone"),
    ]
    for s in spectra:
        report(s)


if __name__ == "__main__":
    main()
