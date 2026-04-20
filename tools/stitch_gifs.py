#!/usr/bin/env python3
"""
Stitch rotation GIFs into a tiered composite animated GIF.

Reads individual per-gem rotation GIFs (produced by gif_rotations.py) from a
rotation_gifs/ directory, groups them by tier using data/tiles/*.tres, and
composites them into a single animated GIF with one row per tier.

Filename convention: {gem_name}_{rotation_axis}.gif
  e.g. ruby_yaw.gif, sapphire_pitch.gif

Within each tier row, gems are sorted by merge-ladder priority then
alphabetically, with each gem's axes placed consecutively (yaw before pitch).

Usage:
    python tools/stitch_gifs.py --input assets/debug_review_v5_smooth/rotation_gifs
    python tools/stitch_gifs.py --input path/to/rotation_gifs --size 64
    python tools/stitch_gifs.py --input path/to/rotation_gifs --output sheet.gif
    python tools/stitch_gifs.py --input path/to/rotation_gifs --fps 15 --labels
    python tools/stitch_gifs.py --input path/to/rotation_gifs --padding 4
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

# Tier parsing from .tres files.
TIER_PATTERN = re.compile(r"^tier\s*=\s*(\d+)", re.MULTILINE)

# Canonical merge-ladder order within each tier.
TIER_LADDER_ORDER = [
    "quartz", "amethyst", "peridot", "topaz",
    "sapphire", "emerald", "ruby", "diamond",
]

# Axis sort order (yaw before pitch for consistency).
AXIS_ORDER = {"yaw": 0, "pitch": 1}

# GIF filename pattern: {gem_name}_{axis}.gif
GIF_FILENAME_PATTERN = re.compile(r"^(.+)_(yaw|pitch)\.gif$")


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


def gather_gifs(input_dir: Path) -> dict[str, list[tuple[str, Path]]]:
    """Scan input_dir for rotation GIFs, group by gem name.

    Returns {gem_name: [(axis, path), ...]} sorted by axis order.
    """
    groups: dict[str, list[tuple[str, Path]]] = {}
    for gif_path in sorted(input_dir.glob("*.gif")):
        m = GIF_FILENAME_PATTERN.match(gif_path.name)
        if not m:
            continue
        gem_name = m.group(1)
        axis = m.group(2)
        groups.setdefault(gem_name, []).append((axis, gif_path))

    # Sort each gem's axes by canonical order.
    for gem in groups:
        groups[gem].sort(key=lambda t: AXIS_ORDER.get(t[0], 99))

    return groups


def sort_gem_names(names: list[str], tier_map: dict[str, int]) -> list[str]:
    """Sort gem names by tier (ascending), ladder-first within tier, then alphabetical."""
    ladder_set = set(TIER_LADDER_ORDER)

    def sort_key(name: str) -> tuple[int, int, str]:
        tier = tier_map.get(name, 9999)
        ladder_priority = 0 if name in ladder_set else 1
        return (tier, ladder_priority, name)

    return sorted(names, key=sort_key)


def load_gif_frames(gif_path: Path, frame_size: int | None) -> list[Image.Image]:
    """Load all frames from an animated GIF as RGBA images."""
    frames: list[Image.Image] = []
    try:
        gif = Image.open(gif_path)
    except (OSError, IOError) as e:
        print(f"  Warning: cannot open {gif_path}: {e}", file=sys.stderr)
        return frames

    try:
        while True:
            frame = gif.convert("RGBA")
            if frame_size is not None and frame.size != (frame_size, frame_size):
                frame = frame.resize((frame_size, frame_size), Image.LANCZOS)
            frames.append(frame)
            gif.seek(gif.tell() + 1)
    except EOFError:
        pass

    return frames


def build_tiered_layout(
    groups: dict[str, list[tuple[str, Path]]],
    tier_map: dict[str, int],
) -> list[list[tuple[str, str, Path]]]:
    """Build row layout: list of rows, each row is list of (gem_name, axis, path).

    Rows are ordered by tier ascending. Within a row, gems are sorted by
    ladder priority then alphabetical, with axes in canonical order.
    """
    # Group gems by tier.
    tier_groups: dict[int, list[str]] = {}
    for gem_name in groups:
        tier = tier_map.get(gem_name, 9999)
        tier_groups.setdefault(tier, []).append(gem_name)

    rows: list[list[tuple[str, str, Path]]] = []
    for tier in sorted(tier_groups.keys()):
        gem_names = sort_gem_names(tier_groups[tier], tier_map)
        row: list[tuple[str, str, Path]] = []
        for gem_name in gem_names:
            for axis, path in groups[gem_name]:
                row.append((gem_name, axis, path))
        rows.append(row)

    return rows


def stitch_gifs(
    rows: list[list[tuple[str, str, Path]]],
    tier_map: dict[str, int],
    frame_size: int,
    padding: int,
    labels: bool,
    fps: int,
) -> tuple[Image.Image, list[Image.Image], int] | None:
    """Build composite animated GIF frames from the tiered layout.

    Returns (first_frame, append_frames, duration_ms) or None on failure.
    """
    # Load all GIF frame sequences.
    # cell_frames[row_idx][col_idx] = list of RGBA frames
    cell_frames: list[list[list[Image.Image]]] = []
    max_cols = 0
    max_frame_count = 0

    for row in rows:
        row_frames: list[list[Image.Image]] = []
        for gem_name, axis, path in row:
            frames = load_gif_frames(path, frame_size)
            if not frames:
                print(f"  Warning: no frames loaded from {path.name}, using blank", file=sys.stderr)
                frames = [Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))]
            row_frames.append(frames)
            max_frame_count = max(max_frame_count, len(frames))
        cell_frames.append(row_frames)
        max_cols = max(max_cols, len(row_frames))

    if max_frame_count == 0:
        return None

    num_rows = len(rows)

    # Compute label width.
    label_width = 0
    font = None
    if labels:
        try:
            from PIL import ImageFont
            # Build tier labels like "T5: sapphire"
            tier_labels = _build_tier_labels(rows, tier_map)
            longest = max(len(lbl) for lbl in tier_labels) if tier_labels else 0
            label_width = longest * (frame_size // 10) + padding * 2
            label_width = max(label_width, 60)  # minimum width
            try:
                font = ImageFont.truetype("arial.ttf", max(12, frame_size // 6))
            except OSError:
                font = ImageFont.load_default()
        except ImportError:
            labels = False

    atlas_w = label_width + max_cols * frame_size + max(0, max_cols - 1) * padding
    atlas_h = num_rows * frame_size + max(0, num_rows - 1) * padding
    duration_ms = max(1, round(1000 / fps))

    # Build tier labels if needed.
    tier_labels = _build_tier_labels(rows, tier_map) if labels else []

    # Composite each frame of the output animation.
    composite_frames: list[Image.Image] = []
    for frame_idx in range(max_frame_count):
        canvas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))

        # Draw labels on each frame.
        if labels and font:
            from PIL import ImageDraw
            draw = ImageDraw.Draw(canvas)
            for row_idx, lbl in enumerate(tier_labels):
                y = row_idx * (frame_size + padding) + frame_size // 2
                draw.text((padding, y), lbl, fill=(255, 255, 255, 255), font=font, anchor="lm")

        # Paste gem frames.
        for row_idx, row_data in enumerate(cell_frames):
            y = row_idx * (frame_size + padding)
            for col_idx, frames in enumerate(row_data):
                x = label_width + col_idx * (frame_size + padding)
                # Loop shorter GIFs to match longest.
                actual_idx = frame_idx % len(frames)
                canvas.paste(frames[actual_idx], (x, y), frames[actual_idx])

        composite_frames.append(canvas)

    if not composite_frames:
        return None

    # Quantize frames to palette mode for GIF output.
    key_color = (1, 255, 1)
    gif_frames: list[Image.Image] = []
    for frame in composite_frames:
        alpha = frame.getchannel("A")
        mask = Image.eval(alpha, lambda a: 255 if a < 128 else 0)

        bg = Image.new("RGBA", frame.size, (0, 0, 0, 255))
        bg.paste(frame, mask=frame)
        rgb = bg.convert("RGB")

        key_layer = Image.new("RGB", frame.size, key_color)
        rgb.paste(key_layer, mask=mask)

        quantized = rgb.quantize(colors=256, method=Image.Quantize.MEDIANCUT)

        palette = quantized.getpalette()
        key_index = None
        for i in range(256):
            r, g, b = palette[i * 3], palette[i * 3 + 1], palette[i * 3 + 2]
            if (r, g, b) == key_color:
                key_index = i
                break

        if key_index is None:
            best_dist = float("inf")
            for i in range(256):
                r, g, b = palette[i * 3], palette[i * 3 + 1], palette[i * 3 + 2]
                d = (r - key_color[0]) ** 2 + (g - key_color[1]) ** 2 + (b - key_color[2]) ** 2
                if d < best_dist:
                    best_dist = d
                    key_index = i

        quantized.info["transparency"] = key_index
        gif_frames.append(quantized)

    first = gif_frames[0]
    return first, gif_frames[1:], duration_ms


def _build_tier_labels(
    rows: list[list[tuple[str, str, Path]]],
    tier_map: dict[str, int],
) -> list[str]:
    """Build display labels for each row (tier)."""
    labels: list[str] = []
    for row in rows:
        if not row:
            labels.append("?")
            continue
        # All gems in row share the same tier.
        gem_name = row[0][0]
        tier = tier_map.get(gem_name, 0)
        gem_names = []
        seen = set()
        for g, _, _ in row:
            if g not in seen:
                gem_names.append(g)
                seen.add(g)
        names_str = ", ".join(gem_names)
        labels.append(f"T{tier}: {names_str}")
    return labels


def main():
    parser = argparse.ArgumentParser(
        description="Stitch rotation GIFs into a tiered composite animated GIF."
    )
    parser.add_argument(
        "--input", "-i",
        type=str,
        required=True,
        help="Input directory containing {gem_name}_{axis}.gif files.",
    )
    parser.add_argument(
        "--output", "-o",
        type=str,
        default=None,
        help="Output GIF path (default: <input_dir>/rotation_sheet.gif).",
    )
    parser.add_argument(
        "--size", "-s",
        type=int,
        default=None,
        help="Resize each gem frame to this square size (default: use native GIF size).",
    )
    parser.add_argument(
        "--padding", "-p",
        type=int,
        default=2,
        help="Pixel gap between cells (default: 2).",
    )
    parser.add_argument(
        "--fps", "-f",
        type=int,
        default=15,
        help="Frames per second for output GIF (default: 15).",
    )
    parser.add_argument(
        "--labels", "-l",
        action="store_true",
        help="Draw tier/gem labels on the left of each row.",
    )
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    input_dir = Path(args.input)
    output_path = Path(args.output) if args.output else input_dir / "rotation_sheet.gif"

    if not input_dir.is_dir():
        print(f"Error: Input directory not found: {input_dir}", file=sys.stderr)
        sys.exit(1)

    tier_map = load_tier_map(project_root)
    groups = gather_gifs(input_dir)

    if not groups:
        print(f"No GIFs matching {{gem}}_{{axis}}.gif found in {input_dir}", file=sys.stderr)
        sys.exit(1)

    # Report what was found.
    sorted_names = sort_gem_names(list(groups.keys()), tier_map)
    print(f"Found {len(groups)} gems with rotation GIFs:")
    for gem in sorted_names:
        tier = tier_map.get(gem)
        tier_label = f" (T{tier})" if tier is not None else ""
        axes = [a for a, _ in groups[gem]]
        print(f"  {gem}{tier_label}: {', '.join(axes)}")

    # Determine frame size from first GIF if not specified.
    frame_size = args.size
    if frame_size is None:
        first_path = groups[sorted_names[0]][0][1]
        try:
            with Image.open(first_path) as img:
                frame_size = img.size[0]
        except (OSError, IOError):
            frame_size = 128
        print(f"  Using native frame size: {frame_size}x{frame_size}px")

    # Build layout and stitch.
    rows = build_tiered_layout(groups, tier_map)

    # Report layout.
    print(f"\nLayout ({len(rows)} tiers):")
    for row in rows:
        if not row:
            continue
        gem_name = row[0][0]
        tier = tier_map.get(gem_name, 0)
        entries = [f"{g}:{a}" for g, a, _ in row]
        print(f"  T{tier}: {', '.join(entries)}")

    result = stitch_gifs(rows, tier_map, frame_size, args.padding, args.labels, args.fps)
    if result is None:
        print("Error: failed to build composite GIF.", file=sys.stderr)
        sys.exit(1)

    first_frame, append_frames, duration_ms = result

    # Save output.
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if append_frames:
        first_frame.save(
            str(output_path),
            format="GIF",
            save_all=True,
            append_images=append_frames,
            duration=duration_ms,
            loop=0,
            disposal=2,
        )
    else:
        first_frame.save(
            str(output_path),
            format="GIF",
            duration=duration_ms,
            loop=0,
        )

    # Report.
    total_cells = sum(len(row) for row in rows)
    print(f"\nComposite GIF saved: {output_path}")
    print(f"  Rows: {len(rows)} tiers")
    print(f"  Cells: {total_cells} ({frame_size}x{frame_size}px each)")
    print(f"  FPS: {args.fps}")


if __name__ == "__main__":
    main()
