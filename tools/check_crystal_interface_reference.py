"""Compare exported complex interface solves to NumPy LAPACK, independently
of GDScript's elimination. Mode physics is checked by the separate eigenproblem.
"""
import json
from pathlib import Path
import numpy as np


def main():
    root = Path(__file__).resolve().parents[1]
    cases = json.loads((root / "artifacts/reference/crystal-interfaces.json").read_text(encoding="utf-8"))
    largest = 0.0
    for case in cases:
        matrix = np.asarray(case["matrix"]).reshape(4, 4, 2)
        matrix = matrix[:, :, 0] + 1j * matrix[:, :, 1]
        rhs = np.asarray(case["rhs"]).reshape(4, 2)
        rhs = rhs[:, 0] + 1j * rhs[:, 1]
        expected = np.linalg.solve(matrix, rhs)
        actual = np.asarray(case["amplitudes"]).reshape(4, 2)
        actual = actual[:, 0] + 1j * actual[:, 1]
        largest = max(largest, float(np.max(np.abs(expected - actual))))
    report = {"interfaces": len(cases), "max_complex_amplitude_error": largest}
    print(json.dumps(report))
    (root / "artifacts/reference/crystal-interface-comparison.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    assert largest < 1e-10, report


if __name__ == "__main__":
    main()
