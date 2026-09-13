"""Compare coherent Maxwell field chains to independent Mitsuba Mueller optics.

The GDScript exporter enters glass, undergoes three oriented TIR events and
returns to air. Initial states include elliptical polarization. All four Stokes
components are checked, so discarding relative complex phases cannot pass.
"""
import json
from pathlib import Path

import mitsuba as mi
import numpy as np

mi.set_variant("scalar_spectral_polarized")
root = Path(__file__).resolve().parents[1] / "artifacts/reference"
cases = json.loads((root / "crystal-packet-chains.json").read_text(encoding="utf-8"))
errors = []
field_errors = []
for case in cases:
    state = np.asarray(case["initial"])
    axis = np.asarray(case["initial_axis"])
    flux_conversion = 1.0
    for step in case["steps"]:
        direction, following, normal = (np.asarray(step[k]) for k in ("direction", "next", "normal"))
        natural_in = np.cross(normal, direction)
        natural_out = np.cross(normal, following)
        natural_in /= np.linalg.norm(natural_in)
        natural_out /= np.linalg.norm(natural_out)
        state = np.asarray(mi.mueller.rotate_stokes_basis(mi.Vector3f(direction), mi.Vector3f(axis), mi.Vector3f(natural_in))) @ state
        cosine = float(np.dot(direction, normal))
        eta = step["after"] / step["before"]
        matrix = (mi.mueller.specular_transmission(cosine, eta) if step["transmission"]
                  else mi.mueller.specular_reflection(cosine, mi.Complex2f(eta, 0)))
        state = np.asarray(matrix) @ state
        if step["transmission"]:
            # Mitsuba's Mueller transmission is normal-flux normalized. The
            # Maxwell solver also exports raw E amplitudes, whose squared norm
            # excludes this n*cos(theta) conversion at each interface.
            flux_conversion *= eta * abs(float(np.dot(following, normal))) / abs(cosine)
        axis = natural_out
    state = np.asarray(mi.mueller.rotate_stokes_basis(mi.Vector3f(following), mi.Vector3f(axis), mi.Vector3f(case["final_axis"]))) @ state
    errors.append(float(np.max(np.abs(state - np.asarray(case["flux_stokes"])))))
    field_errors.append(float(np.max(np.abs(state / flux_conversion - np.asarray(case["final"])))))
report = {"mitsuba": mi.__version__, "chains": len(cases), "interfaces_per_chain": 5,
          "max_flux_stokes_error": max(errors), "max_field_stokes_error": max(field_errors),
          "failures": sum(e > 3e-5 for e in errors + field_errors)}
(root / "crystal-packet-comparison.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report))
if not report["failures"]: print("CHECK_COMPLETE: check_crystal_packet_reference")
raise SystemExit(bool(report["failures"]))
