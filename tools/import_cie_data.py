"""Fetch pinned CIE standard data and retain the publisher's licensing metadata.

The tables are build inputs, not test bakes. No network is needed to render.
"""
from hashlib import sha256
from pathlib import Path
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1] / "data/lapidary/standards"
BASE = "https://files.cie.co.at/Publications-datasets/"
DATASETS = (
    ("CIE_xyz_1931_2deg.csv", "fa663e3535a7e0763a745993a1f0a192eb0275ac46ad2d1befd7626841e713c1", "CIE_xyz_1931_2deg.csv_metadata.json"),
    ("CIE_std_illum_D65.csv", "e76f210bffff3d552ef7113025da5f325d5dfec200dd4b878b1a2f3a507032cb", "CIE_std_illum_D65.csv_metadata_v2.json"),
)

def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / ".gdignore").touch()  # Raw scientific CSV, not Godot translations.
    for name, expected, metadata in DATASETS:
        data = urlopen(BASE + name, timeout=30).read()
        if sha256(data).hexdigest() != expected:
            raise RuntimeError(f"Publisher checksum mismatch: {name}")
        details = urlopen(BASE + metadata, timeout=30).read()
        (ROOT / name).write_bytes(data)
        (ROOT / metadata).write_bytes(details)
        print(f"Verified {name}: {len(data)} bytes")

if __name__ == "__main__":
    main()
