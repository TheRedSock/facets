#!/usr/bin/env python3
"""
Stitch gem rotation PNGs/WebPs into a sprite-sheet atlas.

Scans a production bake output directory for files matching the convention
  {gem_name}/{gem_name}@rot_{number}.webp   (or .png)
inside per-gem subdirectories, groups them by gem name, and composites one
row per gem into a single PNG.

Non-gameplay gems (material studies, debug visuals, and gems without a tile
definition) are excluded by default.  Use --include-all to override.

Usage:
    python tools/stitch_rotations.py                        # defaults: 128px, scans generated/traced_bakes/
    python tools/stitch_rotations.py --size 64              # 64x64 per frame
    python tools/stitch_rotations.py --output atlas.png     # custom output path
    python tools/stitch_rotations.py --input path/to/bakes  # custom input directory
    python tools/stitch_rotations.py --labels               # draw gem name labels on the left
    python tools/stitch_rotations.py --padding 4            # 4px gap between frames
    python tools/stitch_rotations.py --include-all          # include study/debug gems
"""

import argparse
import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow is required. Install with: pip install Pillow", file=sys.stderr)
    sys.exit(1)

# Production bake naming: {gem}__rot_{NN}.webp (or .png) inside {gem}/ subdirectory.
# The variant key uses @ internally but sanitize_variant_key() replaces @ with __
# in the on-disk filename.
ROT_PATTERN = re.compile(r"^(.+)__rot_(\d+)\.(webp|png)$")

# Canonical merge-ladder order within each tier for deterministic output.
# Gems sharing a tier are sub-sorted: ladder gem first, then alphabetical.
TIER_LADDER_ORDER = [
    "quartz", "amethyst", "peridot", "topaz",
    "sapphire", "emerald", "ruby", "diamond",
]

TIER_PATTERN = re.compile(r'^tier\s*=\s*(\d+)', re.MULTILINE)

# Non-gameplay gems excluded from the atlas by default.
# These have visual definitions but no tile definitions (no tier in the
# merge ladder).  Includes material study gems, the opaque debug quartz,
# and the standalone red beryl visual.
EXCLUDED_GEMS = frozenset([
    "grandidierite_study",
    "malachite_study",
    "tigers_eye_study",
    "opal_study",
    "quartz_opaque_debug",
    "red_beryl",
])


def gather_rotations(input_dir: Path, include_all: bool = False) -> dict[str, list[Path]]:
    """Walk input_dir recursively and group rotation images by gem name."""
    groups: dict[str, list[Path]] = {}
    for img_path in sorted(input_dir.rglob("*")):
        if img_path.suffix.lower() not in (".webp", ".png"):
            continue
        m = ROT_PATTERN.match(img_path.name)
        if not m:
            continue
        gem_name = m.group(1)
        if not include_all and gem_name in EXCLUDED_GEMS:
            continue
        groups.setdefault(gem_name, []).append(img_path)

    # Sort each group by rotation index
    for gem in groups:
        groups[gem].sort(key=lambda p: int(ROT_PATTERN.match(p.name).group(2)))
    return groups


def load_tier_map(project_root: Path) -> dict[str, int]:
    """Parse tier values from data/tiles/*.tres files."""
    tier_map: dict[str, int] = {}
    tiles_dir = project_root / "data" / "tiles"
    if not tiles_dir.is_dir():
        return tier_map
    for tres in sorted(tiles_dir.glob("*.tres")):
        gem_name = tres.stem
        text = tres.read_text(encoding="utf-8", errors="replace")
        m = TIER_PATTERN.search(text)
        if m:
            tier_map[gem_name] = int(m.group(1))
    return tier_map


def sort_gem_names(names: list[str], tier_map: dict[str, int]) -> list[str]:
    """Sort gem names by tier (ascending), then ladder-first within tier, then alphabetical."""
    ladder_set = set(TIER_LADDER_ORDER)

    def sort_key(name: str) -> tuple[int, int, str]:
        tier = tier_map.get(name, 9999)
        # Within same tier: ladder gems first (0), others second (1)
        ladder_priority = 0 if name in ladder_set else 1
        return (tier, ladder_priority, name)

    return sorted(names, key=sort_key)


def stitch(
    groups: dict[str, list[Path]],
    frame_size: int,
    padding: int,
    labels: bool,
    tier_map: dict[str, int],
) -> Image.Image:
    """Build the atlas image."""
    if not groups:
        print("No rotation images found.", file=sys.stderr)
        sys.exit(1)

    gem_names = sort_gem_names(list(groups.keys()), tier_map)
    max_cols = max(len(groups[g]) for g in gem_names)
    num_rows = len(gem_names)

    label_width = 0
    font = None
    if labels:
        try:
            from PIL import ImageDraw, ImageFont
            # Approximate label width from longest name
            longest = max(len(n) for n in gem_names)
            label_width = longest * (frame_size // 10) + padding * 2
            try:
                font = ImageFont.truetype("arial.ttf", max(12, frame_size // 6))
            except OSError:
                font = ImageFont.load_default()
        except ImportError:
            labels = False

    atlas_w = label_width + max_cols * frame_size + (max_cols - 1) * padding
    atlas_h = num_rows * frame_size + (num_rows - 1) * padding
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))

    draw = None
    if labels:
        from PIL import ImageDraw
        draw = ImageDraw.Draw(atlas)

    for row, gem in enumerate(gem_names):
        y = row * (frame_size + padding)
        if draw and font:
            text_y = y + frame_size // 2
            draw.text(
                (padding, text_y),
                gem,
                fill=(255, 255, 255, 255),
                font=font,
                anchor="lm",
            )
        for col, path in enumerate(groups[gem]):
            x = label_width + col * (frame_size + padding)
            img = Image.open(path).convert("RGBA")
            if img.size != (frame_size, frame_size):
                img = img.resize((frame_size, frame_size), Image.LANCZOS)
            atlas.paste(img, (x, y), img)

    return atlas


def main():
    parser = argparse.ArgumentParser(description="Stitch gem rotation images into a sprite-sheet atlas.")
    parser.add_argument(
        "--size", "-s",
        type=int,
        default=128,
        help="Frame size in pixels (default: 128). Each rotation image is downscaled to this.",
    )
    parser.add_argument(
        "--input", "-i",
        type=str,
        default=None,
        help="Input directory to scan (default: generated/traced_bakes/).",
    )
    parser.add_argument(
        "--output", "-o",
        type=str,
        default=None,
        help="Output PNG path (default: <input_dir>/rotation_atlas.png).",
    )
    parser.add_argument(
        "--padding", "-p",
        type=int,
        default=2,
        help="Pixel gap between frames (default: 2).",
    )
    parser.add_argument(
        "--labels", "-l",
        action="store_true",
        help="Draw gem name labels on the left side of each row.",
    )
    parser.add_argument(
        "--include-all",
        action="store_true",
        help="Include non-gameplay gems (studies, debug visuals) in the atlas.",
    )
    args = parser.parse_args()

    # Resolve paths relative to project root (parent of tools/)
    project_root = Path(__file__).resolve().parent.parent
    input_dir = Path(args.input) if args.input else project_root / "generated" / "traced_bakes"
    output_path = Path(args.output) if args.output else input_dir / "rotation_atlas.png"

    if not input_dir.is_dir():
        print(f"Error: Input directory not found: {input_dir}", file=sys.stderr)
        sys.exit(1)

    groups = gather_rotations(input_dir, include_all=args.include_all)
    if not groups:
        print(f"No rotation files matching {{gem}}__rot_{{NN}}.webp/png found in {input_dir}", file=sys.stderr)
        sys.exit(1)

    tier_map = load_tier_map(project_root)

    excluded_count = 0
    if not args.include_all:
        # Count how many excluded gems had files present for reporting.
        all_groups = gather_rotations(input_dir, include_all=True)
        excluded_count = len(all_groups) - len(groups)

    print(f"Found {len(groups)} gems with rotation frames:")
    for gem in sort_gem_names(list(groups.keys()), tier_map):
        tier = tier_map.get(gem)
        tier_label = f" (T{tier})" if tier is not None else ""
        print(f"  {gem}{tier_label}: {len(groups[gem])} frames")
    if excluded_count > 0:
        print(f"  ({excluded_count} non-gameplay gem(s) excluded)")

    atlas = stitch(groups, args.size, args.padding, args.labels, tier_map)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(str(output_path), "PNG")
    print(f"\nAtlas saved: {output_path}")
    print(f"  Size: {atlas.width}x{atlas.height}px")
    print(f"  Frame size: {args.size}x{args.size}px")


if __name__ == "__main__":
    main()
