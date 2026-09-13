"""Independent float64 Smith walk using numerical inverse slope CDFs.

Heitz et al. 2016, DOI 10.1145/2897824.2925943 (height sampling and
dielectric phase function). GPU uses cap normals/log-CDF free paths; this
reference instead numerically inverts the projected GGX slope density and
uses a uniform physical height in [-1,1]. No production module is translated
or imported. Requires NumPy; run microsurface_gpu_check.gd first.
"""
from pathlib import Path
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/microsurface"


def unit(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def visible_normals(wi, alpha, rng):
    v = unit(wi * np.array([*alpha, 1.0]))
    c = v[:, 2]
    s = np.linalg.norm(v[:, :2], axis=1)
    u = rng.random(len(v))
    # Marginal visible slope x: (c-s*x)/(2*A*(1+x*x)^1.5), x<c/s.
    # Substitute t=x/sqrt(1+x*x), then numerically invert its exact CDF.
    low = np.full(len(v), -1.0)
    high = c.copy()
    for _ in range(48):
        t = (low + high) * 0.5
        f = (c * (t + 1.0) + s * np.sqrt(np.maximum(0, 1-t*t))) / (1+c)
        low, high = np.where(f < u, t, low), np.where(f >= u, t, high)
    t = (low + high) * 0.5
    sx = t / np.sqrt(np.maximum(1e-30, 1-t*t))
    # Conditional slope y uses p(y) proportional to (1+y*y)^-2.
    u = rng.random(len(v))
    low.fill(-np.pi / 2)
    high.fill(np.pi / 2)
    for _ in range(42):
        angle = (low + high) * 0.5
        f = 0.5 + (angle + 0.5*np.sin(2*angle)) / np.pi
        low, high = np.where(f < u, angle, low), np.where(f >= u, angle, high)
    sy = np.tan((low+high)*0.5) * np.sqrt(1+sx*sx)
    azimuth = np.arctan2(v[:, 1], v[:, 0])
    x = np.cos(azimuth)*sx - np.sin(azimuth)*sy
    y = np.sin(azimuth)*sx + np.cos(azimuth)*sy
    return unit(np.column_stack([-alpha[0]*x, -alpha[1]*y, np.ones(len(x))]))


def reference(case, count, seed):
    rng = np.random.default_rng(seed)
    angle = np.radians(case["angle"])
    alpha = np.array(case["alpha"])
    # Match float32 case inputs, while doing all reference arithmetic in float64.
    initial = np.array([np.sin(angle), 0, -np.cos(angle)], dtype=np.float32).astype(float)
    ray = np.tile(initial, (count, 1))
    if case["angle"] < 0:
        r2, phi = rng.random(count), 2*np.pi*rng.random(count)
        ray = np.column_stack([np.sqrt(r2)*np.cos(phi), np.sqrt(r2)*np.sin(phi), -np.sqrt(1-r2)])
    eta = float(np.float32(case["eta"]))
    height = np.ones(count)
    outside = np.ones(count, dtype=bool)
    order = np.zeros(count, dtype=int)
    pending = np.arange(count)
    for _ in range(1024):
        side = np.where(outside[pending], 1.0, -1.0)
        local = ray[pending] * side[:, None]
        h = height[pending] * side
        cosine = local[:, 2]
        slope = np.linalg.norm(local[:, :2]*alpha, axis=1)
        # Signed Lambda, Eq.28. Use physical height and power-law inversion.
        with np.errstate(divide="ignore", invalid="ignore", over="ignore"):
            lam = (np.sqrt(1+(slope/cosine)**2)*np.sign(cosine)-1)*0.5
            cdf = np.clip((h+1)*0.5, 0, 1)
            escape = np.where(cosine > 0, cdf**lam, 0.0)
            u = rng.random(len(pending))
            hit = u < 1-escape
            next_cdf = cdf[hit] * (1-u[hit]) ** (-1/lam[hit])
        pending = pending[hit]
        if not len(pending):
            break
        side = side[hit]
        height[pending] = side * (2*np.clip(next_cdf, 0, 1)-1)
        m = side[:, None] * visible_normals(-ray[pending]*side[:, None], alpha, rng)
        ratio = np.where(outside[pending], eta, 1/eta)
        cosine = np.clip(-np.sum(ray[pending]*m, axis=1), 0, 1)
        sine2 = ratio**2 * (1-cosine**2)
        ct = np.sqrt(np.maximum(0, 1-sine2))
        rs = (ratio*cosine-ct) / (ratio*cosine+ct)
        rp = (cosine-ratio*ct) / (cosine+ratio*ct)
        reflectance = np.where(sine2 >= 1, 1, (rs*rs+rp*rp)*0.5)
        reflect = rng.random(len(pending)) < reflectance
        reflected = ray[pending]+2*cosine[:, None]*m
        transmitted = ratio[:, None]*ray[pending]+(ratio*cosine-ct)[:, None]*m
        ray[pending] = unit(np.where(reflect[:, None], reflected, transmitted))
        outside[pending] ^= ~reflect
        order[pending] += 1
    assert not len(pending), "reference walk did not converge"
    assert np.all(np.isfinite(ray)) and np.all((ray[:, 2] > 0) == outside)
    return ray, order


def features(ray, order):
    reflected = ray[:, 2] > 0
    return np.column_stack([reflected, ray, ray**2,
                            ray*reflected[:, None],
                            order == 1, order == 2, order >= 3])


def main():
    manifest = json.loads((OUT / "cases.json").read_text(encoding="utf-8"))
    source = ROOT / "core/lapidary/microsurface/smith_walk.glsl"
    assert hashlib.sha256(source.read_bytes()).hexdigest() == manifest["source_sha256"], "stale GPU results"
    results = []
    reciprocity = {}
    for i, case in enumerate(manifest["cases"]):
        data = np.fromfile(OUT / f"case_{i:02d}.bin", dtype="<f4").reshape(-1, 8)
        assert len(data) == manifest["samples"] and case["invalid"] == 0
        assert np.isfinite(data).all() and np.all(data[:, 3] >= 1)
        ray, order = reference(case, len(data), 4096+i)
        gpu = features(data[:, :3].astype(float), data[:, 3])
        ref = features(ray, order)
        delta = np.abs(gpu.mean(0)-ref.mean(0))
        se = np.sqrt((gpu.var(0, ddof=1)+ref.var(0, ddof=1))/len(data))
        tolerance = 6*se + 0.0001
        assert np.all(delta < tolerance), (i, delta, tolerance)
        # Joint azimuth/elevation distribution, retaining both output sides.
        def histogram(d):
            return np.histogram2d(d[:, 2], np.arctan2(d[:, 1], d[:, 0]),
                                  bins=[np.linspace(-1, 1, 33), np.linspace(-np.pi, np.pi, 25)])[0].ravel()
        hg, hr = histogram(data[:, :3]), histogram(ray)
        good = hg+hr >= 50
        chi2 = float(np.sum((hg[good]-hr[good])**2/(hg[good]+hr[good])))
        df = int(good.sum())-1
        assert chi2 < df+8*np.sqrt(2*df)+16, ("angular histogram", i, chi2, df)
        # Below-horizon VNDF: independently inverted slope density moments.
        a = np.radians(case["angle"])
        wi = unit(np.array([[-np.sin(a), 0.17, -np.cos(a)]]))
        normals = visible_normals(np.tile(wi, (len(data), 1)), case["alpha"], np.random.default_rng(8192+i))
        gpu_normals = data[:, 4:7].astype(float)
        gn = np.column_stack([gpu_normals, gpu_normals**2])
        rn = np.column_stack([normals, normals**2])
        nd = np.abs(gn.mean(0)-rn.mean(0))
        ns = np.sqrt((gn.var(0, ddof=1)+rn.var(0, ddof=1))/len(data))
        assert np.all(nd < 6*ns+0.0001), ("VNDF", i, nd, ns)
        result = {"case": i, "max_standard_errors": float(np.max(delta/np.maximum(se, 1e-12))),
                  "angular_chi2": chi2, "angular_df": df,
                  "gpu_reflection": float(gpu[:, 0].mean()), "reference_reflection": float(ref[:, 0].mean()),
                  "multiple_fraction": float(np.mean(data[:, 3] > 1)), "mean_order": float(data[:, 3].mean()),
                  "max_vndf_absolute_error": float(nd.max()),
                  "max_vndf_standard_errors": float(np.max(nd/np.maximum(ns, 1e-12)))}
        results.append(result)
        if case["angle"] < 0:
            reciprocity[(*case["alpha"], round(case["eta"], 6))] = (1-result["gpu_reflection"], len(data))
        print(json.dumps(result), flush=True)
    for (au, av, eta), (t, n) in reciprocity.items():
        if eta > 1:
            continue
        reverse = next(value for (ru, rv, re), value in reciprocity.items()
                       if ru == au and rv == av and abs(re*eta-1) < 1e-5)
        tr, nr = reverse
        error = abs(eta*eta*t-tr)
        se = np.sqrt(eta**4*t*(1-t)/n+tr*(1-tr)/nr)
        assert error < 6*se+0.0001, ("hemispherical reciprocity", au, av, eta, error, se)
        print(f"Reciprocity alpha={au,av} eta={eta}: absolute error {error:.6g}, SE {se:.6g}")
    (OUT / "reference.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(f"PASS: {len(results)} independent directional distributions and below-horizon VNDFs")


if __name__ == "__main__":
    main()
    print("CHECK_COMPLETE: check_microsurface_reference")
