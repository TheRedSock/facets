#!/usr/bin/env python3
"""
Stitch gem rotation PNGs into a sprite-sheet atlas.

Scans assets/debug_bakes/ for files matching {gem_name}__rot_{number}.png,
groups them by gem name, and composites one row per gem into a single PNG.

Usage:
    python tools/stitch_rotations.py                        # defaults: 128px, output to assets/debug_bakes/
    python tools/stitch_rotations.py --size 64              # 64x64 per frame
    python tools/stitch_rotations.py --output atlas.png     # custom output path
    python tools/stitch_rotations.py --input path/to/bakes  # custom input directory
    python tools/stitch_rotations.py --labels               # draw gem name labels on the left
    python tools/stitch_rotations.py --padding 4            # 4px gap between frames
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

ROT_PATTERN = re.compile(r"^(.+)__rot_(\d+)\.png$")

# Tier order for sorting rows (matches the merge ladder).
# Gems not in this list are appended alphabetically at the end.
TIER_ORDER = [
    "quartz", "amethyst", "peridot", "topaz",
    "sapphire", "emerald", "ruby", "diamond",
]


def gather_rotations(input_dir: Path) -> dict[str, list[Path]]:
    """Walk input_dir recursively and group rot PNGs by gem name."""
    groups: dict[str, list[Path]] = {}
    for png in sorted(input_dir.rglob("*.png")):
        m = ROT_PATTERN.match(png.name)
        if not m:
            continue
        gem_name = m.group(1)
        groups.setdefault(gem_name, []).append(png)

    # Sort each group by rotation index
    for gem in groups:
        groups[gem].sort(key=lambda p: int(ROT_PATTERN.match(p.name).group(2)))
    return groups


def sort_gem_names(names: list[str]) -> list[str]:
    """Sort gem names: tier-order first, then alphabetical remainder."""
    tier_set = set(TIER_ORDER)
    ordered = [n for n in TIER_ORDER if n in names]
    remainder = sorted(n for n in names if n not in tier_set)
    return ordered + remainder


def stitch(
    groups: dict[str, list[Path]],
    frame_size: int,
    padding: int,
    labels: bool,
) -> Image.Image:
    """Build the atlas image."""
    if not groups:
        print("No rotation images found.", file=sys.stderr)
        sys.exit(1)

    gem_names = sort_gem_names(list(groups.keys()))
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
    parser = argparse.ArgumentParser(description="Stitch gem rotation PNGs into a sprite-sheet atlas.")
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
        help="Input directory to scan (default: assets/debug_bakes/).",
    )
    parser.add_argument(
        "--output", "-o",
        type=str,
        default=None,
        help="Output PNG path (default: assets/debug_bakes/rotation_atlas.png).",
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
    args = parser.parse_args()

    # Resolve paths relative to project root (parent of tools/)
    project_root = Path(__file__).resolve().parent.parent
    input_dir = Path(args.input) if args.input else project_root / "assets" / "debug_bakes"
    output_path = Path(args.output) if args.output else input_dir / "rotation_atlas.png"

    if not input_dir.is_dir():
        print(f"Error: Input directory not found: {input_dir}", file=sys.stderr)
        sys.exit(1)

    groups = gather_rotations(input_dir)
    if not groups:
        print(f"No files matching {{gem_name}}__rot_{{number}}.png found in {input_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(groups)} gems with rotation frames:")
    for gem in sort_gem_names(list(groups.keys())):
        print(f"  {gem}: {len(groups[gem])} frames")

    atlas = stitch(groups, args.size, args.padding, args.labels)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(str(output_path), "PNG")
    print(f"\nAtlas saved: {output_path}")
    print(f"  Size: {atlas.width}x{atlas.height}px")
    print(f"  Frame size: {args.size}x{args.size}px")


if __name__ == "__main__":
    main()
