"""Compare Godot Mueller math with Mitsuba; run after export_polarization_checks.gd.

Install tools/reference-requirements.txt in an isolated environment. This optional
check has no dependency on game assets or renderer-generated reference tables.
"""
import json
from pathlib import Path

import mitsuba as mi
import numpy as np

mi.set_variant("scalar_spectral_polarized")
ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "artifacts/reference/polarization-cases.json"
cases = json.loads(path.read_text(encoding="utf-8"))["cases"]
errors = []
for case in cases:
    kind = case["kind"]
    if kind == "dielectric":
        # Godot's kernel convention is ni/nt; Mitsuba takes nt/ni.
        eta = 1 / case["eta"]
        if case["transmission"]:
            reference = mi.mueller.specular_transmission(case["cosine"], eta)
        else:
            reference = mi.mueller.specular_reflection(case["cosine"], mi.Complex2f(eta, 0))
    elif kind == "rotation":
        reference = mi.mueller.rotator(case["angle"])
    elif kind == "retarder":
        reference = mi.mueller.linear_retarder(case["phase"])
    elif kind == "diattenuator":
        reference = mi.mueller.diattenuator(case["tx"], case["ty"])
    elif kind == "change_basis":
        element = mi.mueller.diattenuator(case["tx"], case["ty"]) @ mi.mueller.linear_retarder(case["phase"])
        reference = mi.mueller.rotate_mueller_basis(
            element, mi.Vector3f(case["forward"]), mi.Vector3f(case["current"]), mi.Vector3f(case["target"]),
            mi.Vector3f(case["outgoing"]), mi.Vector3f(case["out_current"]), mi.Vector3f(case["out_target"])
        )
    else:
        reference = mi.mueller.rotate_stokes_basis(
            mi.Vector3f(case["forward"]), mi.Vector3f(case["current"]), mi.Vector3f(case["target"])
        )
    actual = np.asarray(case["matrix"]).reshape(4, 4)
    error = float(np.max(np.abs(actual - np.asarray(reference))))
    exact_index_match = kind == "dielectric" and case["eta"] == 1.0
    if exact_index_match:
        # Equal indices have no boundary. The reference's flux conversion loses
        # precision near grazing (3.9.1: ~5e-4 at cosine .005). Record that
        # discrepancy, but judge this degenerate case by its exact physical law.
        exact = np.eye(4) if case["transmission"] else np.zeros((4, 4))
        checked_error = float(np.max(np.abs(actual - exact)))
    else:
        checked_error = error
    errors.append({"kind": kind, "reference_error": error, "checked_error": checked_error,
                   "comparison": "exact_index_match" if exact_index_match else "mitsuba", "passed": checked_error < 3e-5})
report = {"mitsuba": mi.__version__, "checks": len(cases), "failures": sum(not x["passed"] for x in errors),
          "mitsuba_comparisons": sum(x["comparison"] == "mitsuba" for x in errors),
          "exact_index_checks": sum(x["comparison"] == "exact_index_match" for x in errors),
          "maximum_reference_error": max(x["reference_error"] for x in errors),
          "maximum_checked_error": max(x["checked_error"] for x in errors), "cases": errors}
(path.parent / "polarization-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps({k: v for k, v in report.items() if k != "cases"}))
for case, result in zip(cases, errors):
    if not result["passed"]:
        print({k: v for k, v in case.items() if k != "matrix"}, result)
if not report["failures"]: print("CHECK_COMPLETE: check_polarization_reference")
raise SystemExit(bool(report["failures"]))
