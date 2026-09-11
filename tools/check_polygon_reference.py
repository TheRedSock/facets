"""Independent rational checks of every encoded cap from test_polygon.gd.

No engine predicates, floating tolerances, or triangulation library are used.
Positive triangle area, exact boundary cancellation and exact area conservation
check the triangulated oriented disk, including collinear boundary subdivisions.
"""
import json
from collections import Counter
from fractions import Fraction as Q
from pathlib import Path


def orient(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def check(case):
    points = [tuple(Q(x) for x in p) for p in case["points"]]
    indices = case["indices"]
    n = len(points)
    assert len(indices) == 3 * (n - 2)
    edges = Counter()
    area = Q(0)
    for i in range(0, len(indices), 3):
        tri = indices[i:i + 3]
        assert len(set(tri)) == 3 and all(0 <= v < n for v in tri)
        determinant = orient(*(points[v] for v in tri))
        assert determinant > 0, (case["label"], "nonpositive exact triangle area")
        area += determinant
        edges.update(zip(tri, tri[1:] + tri[:1]))
    polygon_area = sum(points[i][0] * points[(i + 1) % n][1] -
                       points[i][1] * points[(i + 1) % n][0] for i in range(n))
    assert area == polygon_area > 0, (case["label"], "exact area mismatch")
    for i in range(n):
        edge = (i, (i + 1) % n)
        assert edges[edge] == 1 and edges[edge[::-1]] == 0
        del edges[edge]
    assert all(count == 1 and edges[edge[::-1]] == 1 for edge, count in edges.items())


def main():
    source = Path(__file__).resolve().parents[1] / "artifacts/polygon/corpus.json"
    corpus = json.loads(source.read_text(encoding="utf-8"))
    required = {"translated square 10000.0", "128 retained collinear boundary vertices",
                "almost collinear positive ear", "radial star 512", "concave comb"}
    assert len(corpus) >= 74 and required <= {case["label"] for case in corpus}, "incomplete cap corpus"
    for case in corpus:
        check(case)
    print(f"Rational polygon reference: {len(corpus)} caps PASS")


if __name__ == "__main__":
    main()
