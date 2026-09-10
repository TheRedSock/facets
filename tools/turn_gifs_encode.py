"""Encode a directory of frame_###.png into a looping GIF (Pillow).

Usage: python turn_gifs_encode.py <frame_dir> <out.gif> [fps]

Frames are straight-alpha sprites; they are composited over a neutral dark
board colour before quantisation so the GIF has no ragged transparency edge.
Called by tools/turn_gifs.gd; usable standalone.
"""
import sys
from pathlib import Path

from PIL import Image

BOARD_BG = (18, 18, 20)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    frame_dir = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    fps = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0

    paths = sorted(frame_dir.glob("frame_*.png"))
    if not paths:
        print(f"no frames in {frame_dir}")
        return 1

    frames = []
    for p in paths:
        rgba = Image.open(p).convert("RGBA")
        bg = Image.new("RGBA", rgba.size, BOARD_BG + (255,))
        rgb = Image.alpha_composite(bg, rgba).convert("RGB")
        frames.append(rgb.quantize(colors=256, method=Image.Quantize.MEDIANCUT,
                                   dither=Image.Dither.FLOYDSTEINBERG))

    # GIF delays are in centiseconds; 30 fps -> 33 ms (rounds to 3 cs).
    duration_ms = max(2, round(1000.0 / fps))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    # Write to a sibling then replace: in-place overwrite keeps the NTFS file
    # id and CreationTime, so Explorer/Photos keep serving the previous GIF.
    tmp_path = out_path.with_name(out_path.stem + ".tmpwrite.gif")
    frames[0].save(
        tmp_path, save_all=True, append_images=frames[1:],
        duration=duration_ms, loop=0, disposal=1, optimize=False,
    )
    if out_path.exists():
        out_path.unlink()
    tmp_path.replace(out_path)
    print(f"wrote {out_path} ({len(frames)} frames, {duration_ms} ms/frame)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
