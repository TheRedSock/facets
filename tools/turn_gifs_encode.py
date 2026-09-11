"""Encode engine PNGs into a timed GIF and lossless full-color WebP for inspection.

python tools/turn_gifs_encode.py FRAME_DIR OUTPUT.gif 30 --frames 120 --size 256
Requires Pillow and NumPy. GIF timing uses cumulative 10 ms rounding.
One shared palette avoids palette pumping; PNG/WebP remain color references.
"""
import argparse
import html
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, features

BOARD_BG = (18, 18, 20)


def durations(count: int, fps: float, quantum: int) -> list[int]:
    if not math.isfinite(fps) or not 0 < fps <= 50 or count < 1:
        raise ValueError("Expected nonempty animation and 0 < fps <= 50")
    edges = [math.floor(i * 1000 / fps / quantum + 0.5) for i in range(count + 1)]
    return [(edges[i + 1] - edges[i]) * quantum for i in range(count)]


def composite(rgba: Image.Image) -> Image.Image:
    """Composite the engine's straight sRGB print in linear light."""
    pixels = np.asarray(rgba.convert("RGBA"), dtype=np.float32) / 255
    rgb, alpha = pixels[..., :3], pixels[..., 3:4]
    bg = np.asarray(BOARD_BG, dtype=np.float32) / 255
    linear = lambda v: np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)
    value = linear(rgb) * alpha + linear(bg) * (1 - alpha)
    encoded = np.where(value <= 0.0031308, 12.92 * value, 1.055 * value ** (1 / 2.4) - 0.055)
    return Image.fromarray(np.rint(np.clip(encoded, 0, 1) * 255).astype(np.uint8))


def gallery(directory: Path) -> None:
    cards = []
    for path in sorted(directory.glob("*.gif")):
        name = html.escape(path.stem)
        cards.append(f'<article><h2>{name.replace("_", " ")}</h2><img width="256" height="256" src="{name}.gif" alt="{name} rotation"><p><a href="{name}.gif">GIF</a> · <a href="{name}.webp">Lossless WebP</a> · <a href="{name}/frame_0000.png">First RGBA frame</a></p></article>')
    document = r'''<!doctype html><meta charset="utf-8"><title>Gem rotation inspection</title>
<style>body{background:#121214;color:#ddd;font:16px system-ui;margin:24px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:20px}article{padding:12px;border:1px solid #444}h2{font-size:18px;text-transform:capitalize}a{color:#9bcfff}img{display:block}button{padding:10px;margin-bottom:20px}</style>
<h1>Gem rotation inspection</h1><p>Physical catalog specimens · gameplay studio lighting · house print · no game stylizer. Timing and encoding metrics are in each .encoding.json sidecar.</p>
<button onclick="document.querySelectorAll('img').forEach(i=>i.src=i.src.replace(/\.(gif|webp)$/,this.dataset.next));this.dataset.next=this.dataset.next==='.webp'?'.gif':'.webp'" data-next=".webp">Toggle GIF / lossless WebP</button><main>'''
    (directory / "index.html").write_text(document + "\n".join(cards) + "</main>", encoding="utf-8")


def encode(frame_dir: Path, out_path: Path, fps: float, count: int | None, size: int | None) -> dict:
    # Explicit indices exclude stale frames left by a prior longer animation.
    paths = ([frame_dir / f"frame_{i:04d}.png" for i in range(count)] if count is not None
             else sorted(frame_dir.glob("frame_*.png")))
    if not paths:
        raise ValueError(f"No frames in {frame_dir}")
    frames = []
    for path in paths:
        with Image.open(path) as source:
            if size is not None and source.size != (size, size):
                raise ValueError(f"Wrong dimensions: {path}: {source.size}")
            frames.append(composite(source))
    if any(frame.size != frames[0].size for frame in frames):
        raise ValueError("Frames have inconsistent sizes")
    gif_delays = durations(len(frames), fps, 10)
    webp_delays = durations(len(frames), fps, 1)
    tile_size = (min(128, frames[0].width), min(128, frames[0].height))
    training = Image.new("RGB", (tile_size[0] * 8, tile_size[1] * math.ceil(len(frames) / 8)), BOARD_BG)
    for i, frame in enumerate(frames):
        training.paste(frame.resize(tile_size, Image.Resampling.BOX), ((i % 8) * tile_size[0], (i // 8) * tile_size[1]))
    palette = training.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    quantized = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    squared = sum(float(np.square(np.asarray(a, dtype=np.float32) - np.asarray(b.convert("RGB"), dtype=np.float32)).sum()) for a, b in zip(frames, quantized))
    rmse = math.sqrt(squared / (len(frames) * frames[0].width * frames[0].height * 3))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = out_path.with_suffix(".tmp.gif")
    quantized[0].save(temporary, save_all=True, append_images=quantized[1:], duration=gif_delays, loop=0, disposal=1, optimize=False)
    with Image.open(temporary) as check:
        saved_count = check.n_frames
        saved_duration = 0
        for i in range(saved_count):
            check.seek(i)
            saved_duration += check.info["duration"]
        if saved_duration != sum(gif_delays) or check.size != frames[0].size or check.info.get("loop") != 0:
            raise ValueError("GIF roundtrip timing/size/loop mismatch")
    temporary.replace(out_path)
    webp = out_path.with_suffix(".webp")
    temporary_webp = out_path.with_suffix(".tmp.webp")
    frames[0].save(temporary_webp, save_all=True, append_images=frames[1:], duration=webp_delays, loop=0, lossless=True, method=4)
    temporary_webp.replace(webp)
    report = {"source_frames": len(frames), "gif_frames": saved_count, "size": frames[0].size,
              "fps_requested": fps, "duration_ms": saved_duration, "gif_delays_ms": gif_delays,
              "webp_delays_ms": webp_delays, "gif_bytes": out_path.stat().st_size, "webp_bytes": webp.stat().st_size,
              "palette": "shared 256, no dithering", "gif_rgb_rmse_lsb": rmse,
              "background_srgb": BOARD_BG, "compositing": "linear light", "game_style": "none",
              "timing_note": "GIF centisecond timing approximates cadence; cumulative rounding preserves loop duration. Identical frames may be coalesced by Pillow."}
    out_path.with_suffix(".encoding.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    gallery(out_path.parent)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frame_dir", nargs="?", type=Path)
    parser.add_argument("out_path", nargs="?", type=Path)
    parser.add_argument("fps", nargs="?", type=float, default=30)
    parser.add_argument("--frames", type=int)
    parser.add_argument("--size", type=int)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if not features.check("webp"):
        parser.error("Pillow needs WebP support")
    if args.check:
        print("Pillow/NumPy/WebP available")
        return 0
    if args.frame_dir is None or args.out_path is None:
        parser.error("frame_dir and out_path required")
    print(json.dumps(encode(args.frame_dir, args.out_path, args.fps, args.frames, args.size)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
