#!/usr/bin/env python3
"""
Generate animated GIF(s) from showroom axis rotation bakes.

Reads the gameplay_manifest.json from a bake output directory, filters for
showroom axis rotation entries (pitch and/or yaw), validates size and step
consistency per gem, and assembles frames into looping animated GIFs.

Only entries recorded in the manifest are used.  If a bake directory contains
images from multiple bake runs at different resolutions or step counts, the
manifest validation catches the inconsistency and skips the gem (or uses only
the entries matching the most recent consistent set).

Usage:
    python tools/gif_rotations.py                                # all gems, pitch axis, from generated/traced_bakes/
    python tools/gif_rotations.py --axis yaw                     # yaw rotation
    python tools/gif_rotations.py --axis pitch yaw               # both axes (separate GIFs)
    python tools/gif_rotations.py --gems quartz amethyst         # specific gems only
    python tools/gif_rotations.py --input path/to/bakes          # custom input directory
    python tools/gif_rotations.py --output path/to/output        # custom output directory
    python tools/gif_rotations.py --size 256                     # resize frames to 256x256
    python tools/gif_rotations.py --fps 24                       # 24 frames per second
    python tools/gif_rotations.py --include-all                  # include non-gameplay gems
"""

import argparse
import json
import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow is required.  Install with: pip install Pillow", file=sys.stderr)
    sys.exit(1)

# Manifest filename written by the bake pipeline.
MANIFEST_NAME = "gameplay_manifest.json"

# Canonical merge-ladder order within each tier for deterministic output.
TIER_LADDER_ORDER = [
    "quartz", "amethyst", "peridot", "topaz",
    "sapphire", "emerald", "ruby", "diamond",
]

TIER_PATTERN = re.compile(r"^tier\s*=\s*(\d+)", re.MULTILINE)

# Non-gameplay gems excluded by default (same set as stitch_rotations.py).
EXCLUDED_GEMS = frozenset([
    "grandidierite_study",
    "malachite_study",
    "tigers_eye_study",
    "opal_study",
    "quartz_opaque_debug",
    "red_beryl",
])

# Valid showroom axis frame types.
VALID_AXES = frozenset(["pitch", "yaw"])

# Matches Godot's Vector2i JSON serialization: "(x, y)" or "(x,y)".
GODOT_VECTOR2I_PATTERN = re.compile(r"^\((\d+),\s*(\d+)\)$")


def parse_godot_size(value) -> tuple[int, int] | None:
    """Parse a size value that may be a list, dict, or Godot Vector2i string.

    Godot's JSON.stringify serializes Vector2i as "(x, y)" strings.
    Returns (w, h) or None if unparseable.
    """
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        return (int(value[0]), int(value[1]))
    if isinstance(value, dict):
        return (int(value.get("x", 0)), int(value.get("y", 0)))
    if isinstance(value, str):
        m = GODOT_VECTOR2I_PATTERN.match(value.strip())
        if m:
            return (int(m.group(1)), int(m.group(2)))
    return None


def load_manifest(input_dir: Path) -> dict | None:
    """Load and return the gameplay manifest from input_dir, or None."""
    manifest_path = input_dir / MANIFEST_NAME
    if not manifest_path.is_file():
        return None
    try:
        return json.loads(manifest_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        print(f"Error reading manifest: {e}", file=sys.stderr)
        return None


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
    """Sort gem names by tier (ascending), ladder-first within tier, then alphabetical."""
    ladder_set = set(TIER_LADDER_ORDER)

    def sort_key(name: str) -> tuple[int, int, str]:
        tier = tier_map.get(name, 9999)
        ladder_priority = 0 if name in ladder_set else 1
        return (tier, ladder_priority, name)

    return sorted(names, key=sort_key)


def resolve_texture_path(entry_texture_path: str, input_dir: Path, output_root: str = "") -> Path | None:
    """Resolve a manifest texture_path to an on-disk Path.

    Manifest paths use Godot resource prefixes (res://, user://) which must be
    mapped to the actual filesystem location.  The input_dir is assumed to be
    the directory that corresponds to the manifest's output_root.

    The output_root from the manifest (e.g. "user://gem_designer_analysis") is
    stripped from the front of texture_path to yield a relative path that is
    then resolved against input_dir.
    """
    p = entry_texture_path.replace("\\", "/")

    # Strip the manifest output_root prefix (with or without trailing slash).
    if output_root:
        root = output_root.replace("\\", "/").rstrip("/") + "/"
        if p.startswith(root):
            p = p[len(root):]

    # If that didn't strip anything, try common Godot resource prefixes.
    if p == entry_texture_path.replace("\\", "/"):
        for scheme in ("res://", "user://"):
            if p.startswith(scheme):
                # Strip scheme + first path segment(s) up to the point where
                # the remaining path is relative within the input_dir.
                remainder = p[len(scheme):]
                # Walk segments: try progressively shorter prefixes until we
                # find a file that exists under input_dir.
                segments = remainder.split("/")
                for start in range(len(segments)):
                    candidate = input_dir / "/".join(segments[start:])
                    if candidate.is_file():
                        return candidate
                break

    candidate = input_dir / p
    if candidate.is_file():
        return candidate

    # Fallback: use only the last two path components (gem_dir/filename).
    parts = p.split("/")
    if len(parts) >= 2:
        candidate = input_dir / "/".join(parts[-2:])
        if candidate.is_file():
            return candidate

    return None


def collect_axis_entries(
    manifest: dict,
    axis: str,
    gem_filter: set[str] | None,
    include_all: bool,
) -> dict[str, list[dict]]:
    """Collect showroom axis entries from manifest, grouped by tile_id.

    Returns {tile_id: [entries sorted by frame index]}.
    Only entries with matching showroom_frame_type and consistent size/step
    count are included.
    """
    entries = manifest.get("entries", [])
    groups: dict[str, list[dict]] = {}

    for entry in entries:
        # Must be a showroom variant with matching frame type.
        if entry.get("variant_type") != "showroom":
            continue
        if entry.get("showroom_frame_type") != axis:
            continue

        tile_id = entry.get("tile_id", "")
        if not tile_id:
            continue

        # Filter by gem name if requested.
        if gem_filter is not None and tile_id not in gem_filter:
            continue

        # Exclude non-gameplay gems unless --include-all.
        if not include_all and tile_id in EXCLUDED_GEMS:
            continue

        groups.setdefault(tile_id, []).append(entry)

    return groups


def _parse_frame_index_from_variant_key(variant_key: str, axis: str) -> int | None:
    """Extract the 3-digit frame index from a showroom axis variant key.

    Expected format: {tile_id}@showroom_{axis}_{NNN}
    """
    pattern = f"@showroom_{axis}_"
    idx = variant_key.find(pattern)
    if idx < 0:
        return None
    suffix = variant_key[idx + len(pattern):]
    # Take leading digits.
    digits = ""
    for ch in suffix:
        if ch.isdigit():
            digits += ch
        else:
            break
    if not digits:
        return None
    return int(digits)


def validate_and_sort_group(
    tile_id: str,
    entries: list[dict],
    axis: str,
) -> tuple[list[dict], str | None]:
    """Validate a group of entries for size/step consistency.

    Returns (sorted_entries, error_message).
    If error_message is not None, the group should be skipped.
    """
    if not entries:
        return [], "no entries"

    # Check draw_size consistency.
    draw_sizes = set()
    for e in entries:
        ds = parse_godot_size(e.get("draw_size"))
        if ds is not None:
            draw_sizes.add(ds)
    if len(draw_sizes) > 1:
        return [], (
            f"mixed draw_size values {draw_sizes} — likely baked at different "
            f"resolutions.  Re-bake at a single resolution or clean the manifest."
        )

    # Check showroom_direction_count consistency (= total steps for this axis).
    direction_counts = set()
    for e in entries:
        dc = e.get("showroom_direction_count")
        if dc is not None:
            direction_counts.add(int(dc))
    if len(direction_counts) > 1:
        return [], (
            f"mixed showroom_direction_count values {direction_counts} — entries "
            f"from different bake runs with different step counts."
        )

    # Parse frame indices and sort.
    indexed: list[tuple[int, dict]] = []
    for e in entries:
        vk = str(e.get("variant_key", ""))
        frame_idx = _parse_frame_index_from_variant_key(vk, axis)
        if frame_idx is None:
            continue
        indexed.append((frame_idx, e))

    indexed.sort(key=lambda t: t[0])

    # Verify frame count matches direction_count if available.
    if direction_counts:
        expected = direction_counts.pop()
        if len(indexed) != expected:
            return [], (
                f"expected {expected} frames (showroom_direction_count) but "
                f"found {len(indexed)} matching entries in manifest."
            )

    if not indexed:
        return [], "no valid frame entries after parsing"

    # Check for duplicate frame indices.
    seen_indices = set()
    for idx, _ in indexed:
        if idx in seen_indices:
            return [], f"duplicate frame index {idx}"
        seen_indices.add(idx)

    return [e for _, e in indexed], None


def build_gif(
    tile_id: str,
    entries: list[dict],
    input_dir: Path,
    output_root: str,
    frame_size: int | None,
    fps: int,
    bounce: bool,
) -> Image.Image | None:
    """Load frames and assemble into an animated GIF Image.

    Returns the first frame with appended frames info, or None on failure.
    """
    frames: list[Image.Image] = []
    for entry in entries:
        texture_path = entry.get("texture_path", "")
        file_path = resolve_texture_path(texture_path, input_dir, output_root)
        if file_path is None:
            print(f"  Warning: file not found for {texture_path}, skipping frame", file=sys.stderr)
            continue

        img = Image.open(file_path).convert("RGBA")

        if frame_size is not None and img.size != (frame_size, frame_size):
            img = img.resize((frame_size, frame_size), Image.LANCZOS)

        frames.append(img)

    if not frames:
        print(f"  Error: no loadable frames for {tile_id}", file=sys.stderr)
        return None

    if bounce and len(frames) > 2:
        # Append reversed frames (excluding first and last to avoid stutter).
        frames = frames + frames[-2:0:-1]

    # Convert RGBA frames to palette mode for GIF.
    # GIF supports only 1-bit transparency via a single transparent palette
    # index.  Strategy: paint transparent regions with a unique key color
    # before quantization so that color gets its own palette slot, then mark
    # that slot as transparent.  This avoids the pitfall where palette index 0
    # collides with actual gem pixels.
    duration_ms = max(1, round(1000 / fps))

    # Pick a key color unlikely to appear in a gem render.  Scan the first
    # frame to confirm, and nudge if needed.
    key_color = (1, 255, 1)  # near-green, unlikely in traced gem renders

    gif_frames: list[Image.Image] = []
    for frame in frames:
        alpha = frame.getchannel("A")
        # Build transparency mask: pixels with alpha < 128 are transparent.
        mask = Image.eval(alpha, lambda a: 255 if a < 128 else 0)

        # Composite opaque/semi-transparent pixels onto black background.
        bg = Image.new("RGBA", frame.size, (0, 0, 0, 255))
        bg.paste(frame, mask=frame)
        rgb = bg.convert("RGB")

        # Paint the key color into transparent regions.
        key_layer = Image.new("RGB", frame.size, key_color)
        rgb.paste(key_layer, mask=mask)

        # Quantize to 255 colors + 1 reserved for the key.
        quantized = rgb.quantize(colors=256, method=Image.Quantize.MEDIANCUT)

        # Find which palette index the key color mapped to.
        palette = quantized.getpalette()
        key_index = None
        for i in range(256):
            r, g, b = palette[i * 3], palette[i * 3 + 1], palette[i * 3 + 2]
            if (r, g, b) == key_color:
                key_index = i
                break

        if key_index is None:
            # Key color was dithered away — find nearest match.
            best_dist = float("inf")
            for i in range(256):
                r, g, b = palette[i * 3], palette[i * 3 + 1], palette[i * 3 + 2]
                d = (r - key_color[0]) ** 2 + (g - key_color[1]) ** 2 + (b - key_color[2]) ** 2
                if d < best_dist:
                    best_dist = d
                    key_index = i

        quantized.info["transparency"] = key_index
        gif_frames.append(quantized)

    if not gif_frames:
        return None

    first = gif_frames[0]
    first.info["duration"] = duration_ms
    first.info["loop"] = 0  # infinite loop
    first._gif_frames = gif_frames[1:]  # stash for save
    first._gif_duration = duration_ms
    return first


def save_gif(
    first_frame: Image.Image,
    output_path: Path,
    fps: int,
) -> None:
    """Save assembled GIF frames to disk."""
    duration_ms = max(1, round(1000 / fps))
    append_frames = getattr(first_frame, "_gif_frames", [])

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


def main():
    parser = argparse.ArgumentParser(
        description="Generate animated GIFs from showroom axis rotation bakes."
    )
    parser.add_argument(
        "--axis", "-a",
        nargs="+",
        choices=["pitch", "yaw"],
        default=["pitch"],
        help="Rotation axis/axes to generate GIFs for (default: pitch).",
    )
    parser.add_argument(
        "--gems", "-g",
        nargs="+",
        default=None,
        help="Specific gem tile_ids to process (default: all).",
    )
    parser.add_argument(
        "--input", "-i",
        type=str,
        default=None,
        help="Input bake directory containing gameplay_manifest.json (default: generated/traced_bakes/).",
    )
    parser.add_argument(
        "--output", "-o",
        type=str,
        default=None,
        help="Output directory for GIF files (default: <input_dir>/rotation_gifs/).",
    )
    parser.add_argument(
        "--size", "-s",
        type=int,
        default=None,
        help="Resize frames to this square size in pixels (default: use baked size).",
    )
    parser.add_argument(
        "--fps", "-f",
        type=int,
        default=15,
        help="Frames per second for the GIF animation (default: 15).",
    )
    parser.add_argument(
        "--bounce",
        action="store_true",
        help="Ping-pong animation (forward then reverse) instead of looping.",
    )
    parser.add_argument(
        "--include-all",
        action="store_true",
        help="Include non-gameplay gems (studies, debug visuals).",
    )
    args = parser.parse_args()

    # Resolve paths relative to project root (parent of tools/).
    project_root = Path(__file__).resolve().parent.parent
    input_dir = Path(args.input) if args.input else project_root / "generated" / "traced_bakes"
    output_dir = Path(args.output) if args.output else input_dir / "rotation_gifs"

    if not input_dir.is_dir():
        print(f"Error: Input directory not found: {input_dir}", file=sys.stderr)
        sys.exit(1)

    # Load manifest — required for size/step validation.
    manifest = load_manifest(input_dir)
    if manifest is None:
        print(
            f"Error: No {MANIFEST_NAME} found in {input_dir}.\n"
            f"Run a showroom bake first (gem designer Analysis tab, or CLI with "
            f"--showroom_axis_steps).",
            file=sys.stderr,
        )
        sys.exit(1)

    tier_map = load_tier_map(project_root)
    gem_filter = set(args.gems) if args.gems else None
    output_root = str(manifest.get("output_root", ""))

    total_gifs = 0
    total_skipped = 0

    for axis in args.axis:
        print(f"\n=== {axis.upper()} axis ===")

        groups = collect_axis_entries(manifest, axis, gem_filter, args.include_all)
        if not groups:
            print(f"  No showroom {axis} entries found in manifest.")
            if gem_filter:
                print(f"  (filtered to: {', '.join(sorted(gem_filter))})")
            continue

        gem_names = sort_gem_names(list(groups.keys()), tier_map)

        for tile_id in gem_names:
            entries = groups[tile_id]
            sorted_entries, error = validate_and_sort_group(tile_id, entries, axis)

            if error:
                tier = tier_map.get(tile_id)
                tier_label = f" (T{tier})" if tier is not None else ""
                print(f"  SKIP {tile_id}{tier_label}: {error}")
                total_skipped += 1
                continue

            # Report frame info.
            tier = tier_map.get(tile_id)
            tier_label = f" (T{tier})" if tier is not None else ""
            ds = parse_godot_size(sorted_entries[0].get("draw_size"))
            ds_str = f"{ds[0]}x{ds[1]}" if ds else "unknown"
            frame_count = len(sorted_entries)
            step_deg = 360.0 / frame_count if frame_count > 0 else 0
            print(
                f"  {tile_id}{tier_label}: {frame_count} frames "
                f"({step_deg:.1f} deg/step), {ds_str}px baked"
            )

            gif_image = build_gif(
                tile_id, sorted_entries, input_dir, output_root, args.size, args.fps, args.bounce,
            )
            if gif_image is None:
                total_skipped += 1
                continue

            gif_name = f"{tile_id}_{axis}.gif"
            gif_path = output_dir / gif_name
            save_gif(gif_image, gif_path, args.fps)

            effective_size = args.size if args.size else ds
            if isinstance(effective_size, tuple):
                size_str = f"{effective_size[0]}x{effective_size[1]}"
            elif isinstance(effective_size, int):
                size_str = f"{effective_size}x{effective_size}"
            else:
                size_str = str(effective_size)
            print(f"    -> {gif_path} ({size_str}px, {args.fps}fps)")
            total_gifs += 1

    # Summary.
    print(f"\nDone: {total_gifs} GIF(s) created", end="")
    if total_skipped > 0:
        print(f", {total_skipped} skipped")
    else:
        print()

    if total_gifs > 0:
        print(f"Output directory: {output_dir}")


if __name__ == "__main__":
    main()
