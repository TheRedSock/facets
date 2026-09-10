"""Float64 full-matrix reference for authored GGX shape fields (NumPy)."""
from pathlib import Path
import json
import hashlib
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/finish-fields"


def unit(v):
    return v / np.linalg.norm(v)


def tangent(direction, n):
    t = direction-n*np.dot(n, direction)
    if np.dot(t, t) < 1e-10:
        t = np.cross(n, [0, 0, 1] if abs(n[2]) < 0.9 else [1, 0, 0])
    return unit(t)


def shape(alpha, direction, normal):
    t = tangent(direction, normal)
    b = np.cross(normal, t)
    return alpha[0]**2*np.outer(t, t)+alpha[1]**2*np.outer(b, b)


def rotation(q):
    x, y, z, w = q
    skew = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    return np.eye(3)+2*w*skew+2*skew@skew


def main():
    # Refuse to report old GPU samples as evidence for a changed shader.
    for path, expected in json.loads((OUT / "sources.json").read_text(encoding="utf-8")).items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected, "stale GPU results: "+path
    def read(name, size):
        return np.fromfile(OUT / (name+".bin"), dtype="<f4").astype(float).reshape(-1, size)
    surfaces, fields, queries, results = read("surfaces", 8), read("fields", 20), read("queries", 8), read("results", 8)
    maximum_matrix = maximum_width = 0.0
    for surface, query, result in zip(surfaces, queries, results, strict=True):
        normal = unit(query[4:7])
        matrix = shape(surface[:2], surface[4:7], normal)
        for field in fields[int(surface[3]):int(surface[3]+surface[7])]:
            local = rotation(field[8:12]).T @ (query[:3]-field[:3]) / field[4:7]
            weight = field[3]*max(0, 1-np.dot(local, local))**3
            matrix = (1-weight)*matrix+weight*shape(field[12:14], field[16:19], normal)
        actual = shape(result[:2], result[4:7], normal)
        error = float(np.abs(actual-matrix).max())
        assert error < 3e-6, ("GGX shape matrix", query[3], error)
        expected_widths = np.sqrt(np.maximum(0, np.linalg.eigvalsh(matrix)[1:]))[::-1]
        relative = np.abs(np.sort(result[:2])[::-1]-expected_widths)/np.maximum(expected_widths, 1e-8)
        assert relative.max() < 0.002, ("principal widths", query[3], relative, result[:2], expected_widths)
        maximum_matrix = max(maximum_matrix, error)
        maximum_width = max(maximum_width, float(relative.max()))
    report = {"cases": len(results), "max_matrix_error": maximum_matrix, "max_width_relative_error": maximum_width}
    (OUT / "reference.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
