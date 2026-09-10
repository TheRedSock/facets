"""Independent exact-rational oracle for the binary32 geometry predicates."""
from fractions import Fraction as F
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
report = json.loads((ROOT / "artifacts/geometry/predicates.json").read_text(encoding="utf-8"))
source = ROOT / "core/lapidary/geometry/exact_predicates.gd"
assert report["source"] == hashlib.sha256(source.read_bytes()).hexdigest(), "Stale predicate export"
checked = 0
for i, case in enumerate(report["cases"]):
    a, b, c, d = [[F(float(v)) for v in p] for p in case["points"]]
    u, v, w = [[p[j] - d[j] for j in range(3)] for p in (a, b, c)]
    determinants = [sum(u[j] * (v[(j+1)%3] * w[(j+2)%3] - v[(j+2)%3] * w[(j+1)%3]) for j in range(3))]
    determinants += [(a[x]-c[x])*(b[y]-c[y])-(a[y]-c[y])*(b[x]-c[x]) for x,y in ((0,1),(1,2),(2,0))]
    expected = [(d > 0) - (d < 0) for d in determinants]
    assert expected == case["signs"], (i, expected, case["signs"])
    checked += len(expected)
print(f"Exact Fraction predicate reference: {checked} signs PASS")

# Construct exact rational intersection points independently of the production
# orientation-only overlap tests; then compare the intersection with the indexed
# shared simplex. This also tests coplanar, shared-edge, and shared-vertex cases.
def sub(a, b): return tuple(x-y for x,y in zip(a,b))
def dot(a, b): return sum(x*y for x,y in zip(a,b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def normal(t): return cross(sub(t[1],t[0]),sub(t[2],t[0]))
def inside(p, t):
    n = normal(t)
    return all(dot(cross(sub(t[(k+1)%3],t[k]),sub(p,t[k])),n) >= 0 for k in range(3))
def intersections(a,b):
    found = set()
    for t,u in ((a,b),(b,a)):
        n = normal(u)
        for k in range(3):
            p,q = t[k],t[(k+1)%3]
            dp,dq = dot(sub(p,u[0]),n),dot(sub(q,u[0]),n)
            if dp == 0 and inside(p,u): found.add(p)
            if dp*dq < 0:
                x = tuple(p[j]+dp/(dp-dq)*(q[j]-p[j]) for j in range(3))
                if inside(x,u): found.add(x)
    if all(dot(sub(p,a[0]),normal(a)) == 0 for p in b):
        # Coplanar edges: exact 2D line intersections, including crossing edges
        # where no original vertex lies inside the other triangle.
        omitted = max(range(3),key=lambda j:abs(normal(a)[j]))
        x,y = [j for j in range(3) if j != omitted]
        for k in range(3):
            p,q = a[k],a[(k+1)%3]
            r = sub(q,p)
            for l in range(3):
                c,d = b[l],b[(l+1)%3]
                v,w = sub(d,c),sub(c,p)
                den = r[x]*v[y]-r[y]*v[x]
                if den:
                    u = (w[x]*v[y]-w[y]*v[x])/den
                    t = (w[x]*r[y]-w[y]*r[x])/den
                    if 0 <= u <= 1 and 0 <= t <= 1:
                        found.add(tuple(p[j]+u*r[j] for j in range(3)))
    return found

def on_shared(p, shared):
    if not shared: return False
    if len(shared) == 1: return p == shared[0]
    u,v = sub(p,shared[0]),sub(shared[1],shared[0])
    return cross(u,v) == (0,0,0) and 0 <= dot(u,v) <= dot(v,v)

assert report["intersection_source"] == hashlib.sha256((ROOT/"core/lapidary/geometry/mesh_intersections.gd").read_bytes()).hexdigest(), "Stale intersections export"
for i,case in enumerate(report["pairs"]):
    points = [tuple(F(float(v)) for v in p) for p in case["points"]]
    ai,bi = case["indices"][:3],case["indices"][3:]
    shared = [points[j] for j in ai if j in bi]
    expected = len(shared) == 3 or any(not on_shared(p,shared) for p in intersections([points[j] for j in ai],[points[j] for j in bi]))
    assert expected == case["invalid"], (i,case,expected)
print(f"Exact rational triangle intersection reference: {len(report['pairs'])} pairs PASS")
