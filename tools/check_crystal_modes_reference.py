"""Independent NumPy eigenproblem for the actual GDScript uniaxial modes.

Rather than repeat the analytic roots, eliminate Ez/Hz in Maxwell's equations
and diagonalize the 4x4 tangential-field propagation matrix for (Ex,Ey,Hx,Hy).
Lossless permittivity is fully tensorial; this eigenproblem also admits biaxial
tensors. Input fixtures exercise propagating and evanescent uniaxial modes.
"""
import json
from pathlib import Path

import numpy as np


def propagation_matrix(eps, k):
    zz = eps[2, 2]
    return np.array([
        [-k * eps[2, 0] / zz, -k * eps[2, 1] / zz, 0, 1 - k*k / zz],
        [0, 0, -1, 0],
        [-eps[1, 0] + eps[1, 2]*eps[2, 0]/zz,
         k*k - eps[1, 1] + eps[1, 2]*eps[2, 1]/zz, 0, eps[1, 2]*k/zz],
        [eps[0, 0] - eps[0, 2]*eps[2, 0]/zz,
         eps[0, 1] - eps[0, 2]*eps[2, 1]/zz, 0, -eps[0, 2]*k/zz],
    ], dtype=complex)


def main():
    root = Path(__file__).resolve().parents[1]
    cases = json.loads((root / "artifacts/reference/crystal-modes.json").read_text(encoding="utf-8"))
    max_root = max_field = max_ray = 0.0
    count = 0
    for case in cases:
        no, ne, k = case["no"], case["ne"], case["kx"]
        axis = np.asarray(case["axis"], dtype=float)
        eps = no*no * np.eye(3) + (ne*ne - no*no) * np.outer(axis, axis)
        matrix = propagation_matrix(eps, k)
        roots, vectors = np.linalg.eig(matrix)
        for mode in case["modes"]:
            q = complex(*mode["q"])
            error = float(np.min(np.abs(roots - q)))
            max_root = max(max_root, error)
            e = np.asarray(mode["E_real"]) + 1j*np.asarray(mode["E_imag"])
            h = np.asarray(mode["H_real"]) + 1j*np.asarray(mode["H_imag"])
            field = np.array([e[0], e[1], h[0], h[1]])
            max_field = max(max_field, float(np.linalg.norm(matrix @ field - q*field)))
            idx = int(np.argmin(np.abs(roots - q)))
            # At an exact repeated eigenvalue NumPy may choose any basis in its
            # eigenspace. Root and Maxwell residual checks remain meaningful.
            if np.count_nonzero(np.abs(roots - q) < 1e-7) == 1:
                ex, ey, hx, hy = vectors[:, idx]
                ez = (-k*hy - eps[2, 0]*ex - eps[2, 1]*ey) / eps[2, 2]
                ee = np.array([ex, ey, ez])
                hh = np.array([hx, hy, k*ey])
                s = np.cross(ee, np.conj(hh)).real
                if np.linalg.norm(s) > 1e-12:
                    s /= np.linalg.norm(s)
                    max_ray = max(max_ray, float(np.linalg.norm(s - np.asarray(mode["ray"]))))
            count += 1
    result = {"modes": count, "max_q_error": max_root,
              "max_tangential_maxwell_residual": max_field, "max_ray_error": max_ray}
    print(json.dumps(result))
    (root / "artifacts/reference/crystal-modes-comparison.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    assert max_root < 1e-9 and max_field < 1e-9 and max_ray < 1e-8, result


if __name__ == "__main__":
    main()
    print("CHECK_COMPLETE: check_crystal_modes_reference")
