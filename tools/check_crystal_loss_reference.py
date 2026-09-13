"""Validate weak modal absorption against a complex-permittivity eigenproblem.

Use the full complex principal indices n+i*alpha/(2*k0), not the implementation's
Poynting loss formula. Track each lossless eigenvalue as loss increases. Imaginary
normal wavevector gives attenuation along the corresponding energy ray.
"""
import json
from pathlib import Path

import numpy as np

from check_crystal_modes_reference import propagation_matrix

root = Path(__file__).resolve().parents[1] / "artifacts/reference"
cases = json.loads((root / "crystal-loss.json").read_text(encoding="utf-8"))
maximum = {"1.0": 0.0, "0.1": 0.0, "0.01": 0.0}
for case in cases:
    k0 = 2*np.pi / (case["wavelength_nm"] * 1e-6)
    axis = np.asarray(case["axis"])
    projector = np.outer(axis, axis)
    for scale in (1.0, 0.1, 0.01):
        no = case["no"] + 1j * case["alpha_o"] * scale / (2*k0)
        ne = case["ne"] + 1j * case["alpha_e"] * scale / (2*k0)
        epsilon = no*no*np.eye(3) + (ne*ne-no*no)*projector
        roots = np.linalg.eigvals(propagation_matrix(epsilon, case["kx"]))
        q = roots[np.argmin(np.abs(roots - complex(*case["mode"]["q"]))) ]
        rate = 2*k0*q.imag*case["mode"]["ray"][2] / scale
        relative = float(abs(rate / case["rate"] - 1))
        maximum[str(scale)] = max(maximum[str(scale)], relative)
report = {"modes": len(cases), "complex_eigenproblems": len(cases)*3,
          "max_relative_rate_error_by_loss_scale": maximum}
(root / "crystal-loss-comparison.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report))
assert maximum["1.0"] < 2e-6 and maximum["0.1"] < 1e-7 and maximum["0.01"] < 1e-7, report
print("CHECK_COMPLETE: check_crystal_loss_reference")
