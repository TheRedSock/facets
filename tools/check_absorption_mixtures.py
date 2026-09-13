"""Check GPU slabs against raw measured cross sections and a closed-form series.

Normal incidence perpendicular to c: two independent principal polarizations.
Uniform D65 surrounds the slab; both reflection and transmission reach the camera.
This validates data/transport integration, not the published specimen Lab appendix.
"""
import csv
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/lapidary/measurements/gia_corundum_2020"
metadata = json.loads((SOURCE / "source.json").read_text(encoding="utf-8"))
curves = {}
for name in ("chromium", "iron_titanium"):
    record = metadata["spectra"][name]
    path = SOURCE / record["file"]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == record["sha256"]
    with path.open(encoding="utf-8", newline="") as stream:
        curves[name] = {int(r["wavelength_nm"]): (float(r["ordinary"]), float(r["extraordinary"])) for r in csv.DictReader(stream)}

def table(name):
    with (ROOT / "data/lapidary/standards" / name).open(encoding="utf-8", newline="") as stream:
        return {int(r[0]): tuple(float(v) for v in r[1:]) for r in csv.reader(stream)}

cmf = table("CIE_xyz_1931_2deg.csv")
d65 = table("CIE_std_illum_D65.csv")
ynorm = sum(cmf[w][1] * (0.5 if w in (380, 780) else 1) for w in range(380, 781))
# The fixture explicitly uses unit-luminance D65. Integrate the product of
# piecewise-linear observer/emission functions, rather than fitting a scale.
daylight_y = 0.0
for w in range(380, 780):
    a, b = cmf[w][1], cmf[w+1][1]
    u, v = d65[w][0]/d65[560][0], d65[w+1][0]/d65[560][0]
    daylight_y += (2*a*u+a*v+b*u+2*b*v)/6/ynorm

def interpolate(values, wavelength, channel):
    lower = int(wavelength)
    fraction = wavelength - lower
    return values[lower][channel] * (1-fraction) + values[lower+1][channel] * fraction

def index(b, c, wavelength):
    l2 = (wavelength * .001)**2
    return math.sqrt(1 + sum(bi*l2/(l2-ci) for bi, ci in zip(b, c) if bi))

records = json.loads((ROOT / "artifacts/reference/absorption-mixtures.json").read_text(encoding="utf-8"))
results = []
for case in records:
    expected = [0.0]*3
    for step in range(3200):
        wavelength = 380 + (step+.5)*.125
        radiance = 0.0
        for channel in range(2):
            # One ppma = 1.178e17 active absorbers/cm3; /10 converts cm^-1 to mm^-1.
            alpha = sum(t["ppma"]*interpolate(curves[t["id"]], wavelength, channel) for t in case["terms"])*1.178e16
            n = index(case["be"] if channel else case["b"], case["ce"] if channel else case["c"], wavelength)
            reflection = ((n-1)/(n+1))**2
            transmission = math.exp(-alpha*case["depth_mm"])
            radiance += .5*(reflection+(1-reflection)**2*transmission/(1-reflection*transmission))
        emission = interpolate(d65, wavelength, 0)/d65[560][0]/daylight_y
        for channel in range(3):
            expected[channel] += radiance*emission*interpolate(cmf, wavelength, channel)*.125/ynorm
    error = max(abs(a-b) for a, b in zip(case["xyz"], expected))
    results.append({"id":case["id"], "crystal":case["crystal"], "depth_mm":case["depth_mm"], "expected":expected, "actual":case["xyz"], "max_absolute_xyz_error":error})
report = {"cases":results, "max_absolute_xyz_error":max(r["max_absolute_xyz_error"] for r in results)}
(ROOT / "artifacts/reference/absorption-mixtures-comparison.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
print(json.dumps(report))
assert len(results)==12 and report["max_absolute_xyz_error"]<.001, report
print("CHECK_COMPLETE: check_absorption_mixtures")
