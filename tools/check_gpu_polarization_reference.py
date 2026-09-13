"""Independent check of the actual GPU's five-interface Mueller products.

Run tools/polarization_gpu_check.gd first. Chains enter a dielectric, undergo
three differently oriented TIR events, then exit. Full I/Q/U/V is compared,
including circular polarization and radiance unit conversion.
"""
import json
from pathlib import Path

import mitsuba as mi
import numpy as np

mi.set_variant("scalar_spectral_polarized")
root = Path(__file__).resolve().parents[1] / "artifacts/reference"
cases = json.loads((root / "polarized-interface-chains.json").read_text(encoding="utf-8"))
cases += json.loads((root / "polarized-dichroic-chains.json").read_text(encoding="utf-8"))
errors = []
for case in cases:
    weight = np.array([1.0, 0, 0, 0])
    direction = np.array(case["steps"][0][:3])
    axis = mi.mueller.stokes_basis(mi.Vector3f(-direction))
    for step_index, values in enumerate(case["steps"]):
        previous, before = np.array(values[:3]), values[3]
        following, after = np.array(values[4:7]), values[7]
        normal, transmitted = np.array(values[8:11]), bool(values[11])
        outgoing, incident = -previous, -following
        out_axis, in_axis = np.cross(normal, outgoing), np.cross(normal, incident)
        out_axis /= np.linalg.norm(out_axis)
        in_axis /= np.linalg.norm(in_axis)
        next_axis = mi.mueller.stokes_basis(mi.Vector3f(incident))
        if transmitted:
            matrix = mi.mueller.specular_transmission(abs(float(np.dot(incident, normal))), before / after)
        else:
            matrix = mi.mueller.specular_reflection(abs(float(np.dot(outgoing, normal))), mi.Complex2f(after / before, 0))
        matrix = mi.mueller.rotate_mueller_basis(matrix,
            mi.Vector3f(incident), mi.Vector3f(in_axis), next_axis,
            mi.Vector3f(outgoing), mi.Vector3f(out_axis), axis)
        weight = weight @ np.asarray(matrix)
        if transmitted:
            weight *= (before / after) ** 2
        axis = next_axis
        if case.get("absorption"):
            entry = case["absorption"][step_index]
            natural = np.cross(np.asarray(entry["axis"]), incident)
            natural /= np.linalg.norm(natural)
            absorption = mi.mueller.diattenuator(entry["ordinary"], entry["extraordinary"])
            absorption = mi.mueller.rotate_mueller_basis(absorption,
                mi.Vector3f(incident), mi.Vector3f(natural), next_axis,
                mi.Vector3f(incident), mi.Vector3f(natural), next_axis)
            weight = weight @ np.asarray(absorption)
    # Compare in the natural final frame exported by the GPU, not Mitsuba's
    # arbitrary implicit transverse basis.
    rotation = mi.mueller.rotate_stokes_basis(mi.Vector3f(incident), mi.Vector3f(case["axis"]), axis)
    weight = weight @ np.asarray(rotation)
    errors.append(float(np.max(np.abs(weight - np.array(case["weight"])))))
report = {"mitsuba": mi.__version__, "interface_chains": len(cases), "interfaces_per_chain": 5,
          "maximum_absolute_error": max(errors), "failures": sum(x >= 3e-5 for x in errors), "errors": errors}
(root / "gpu-polarization-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps({k: v for k, v in report.items() if k != "errors"}))
if not report["failures"]: print("CHECK_COMPLETE: check_gpu_polarization_reference")
raise SystemExit(bool(report["failures"]))
