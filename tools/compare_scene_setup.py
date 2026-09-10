"""Compare ignored scene-setup benchmark timings and linear float32 films."""
import argparse
import json
import math
from pathlib import Path
import statistics
import struct


def compare(before: Path, after: Path) -> dict:
    old = json.loads((before / "report.json").read_text(encoding="utf-8"))
    new = json.loads((after / "report.json").read_text(encoding="utf-8"))
    if old["triangles"] != new["triangles"] or len(old["frames"]) != len(new["frames"]):
        raise ValueError("Benchmark geometry/frame counts disagree")
    rows = []
    for index, (a, b) in enumerate(zip(old["frames"], new["frames"])):
        raw_a = (before / f"frame{index}.bin").read_bytes()
        raw_b = (after / f"frame{index}.bin").read_bytes()
        if len(raw_a) != len(raw_b) or not raw_a or len(raw_a) % 16:
            raise ValueError("Invalid or mismatched XYZA film")
        values_a = struct.unpack(f"<{len(raw_a) // 4}f", raw_a)
        values_b = struct.unpack(f"<{len(raw_b) // 4}f", raw_b)
        if not all(math.isfinite(x) for x in values_a + values_b):
            raise ValueError("Nonfinite film")
        differences = [abs(x - y) for x, y in zip(values_a, values_b)]
        rows.append({"frame": index, "before_ms": a["configure_ms"],
                     "after_ms": b["configure_ms"], "max_xyza_error": max(differences),
                     "rms_xyza_error": math.sqrt(statistics.mean(x*x for x in differences))})
    return {"triangles": old["triangles"], "frames": rows,
            "warm_setup_speedup": statistics.median(row["before_ms"] for row in rows[1:]) /
                                  statistics.median(row["after_ms"] for row in rows[1:]),
            "max_xyza_error": max(row["max_xyza_error"] for row in rows)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    report = compare(args.before, args.after)
    print(json.dumps(report, indent=2))
    # Different adaptive submission grouping permits float32 rounding differences.
    if report["max_xyza_error"] > 2e-6:
        raise SystemExit("FAIL: cached geometry changed linear radiance")
