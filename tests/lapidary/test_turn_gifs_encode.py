"""File-level inspection-animation regressions; no renderer required."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("turn_encoder", ROOT / "tools/turn_gifs_encode.py")
ENCODER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ENCODER)


class EncodingTests(unittest.TestCase):
    def test_four_second_loop_and_lossless_companion(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for i in range(120):
                frame = Image.new("RGBA", (8, 8), (i * 2, 100, 200, 255))
                frame.putpixel((i % 8, i // 8 % 8), (255, 255, 255, 255))
                frame.save(root / f"frame_{i:04d}.png")
            # An old tail must not leak into the new request.
            Image.new("RGBA", (8, 8), "red").save(root / "frame_0120.png")
            report = ENCODER.encode(root, root / "test.gif", 30, 120, 8)
            self.assertEqual(report["source_frames"], 120)
            with Image.open(root / "test.gif") as gif:
                self.assertEqual(gif.n_frames, 120)
                delays = []
                for i in range(gif.n_frames):
                    gif.seek(i)
                    delays.append(gif.info["duration"])
                self.assertEqual(sum(delays), 4000)
                self.assertEqual(set(delays), {30, 40})
                self.assertEqual(gif.info["loop"], 0)
            with Image.open(root / "test.webp") as animation:
                self.assertEqual(animation.n_frames, 120)
                for i in (0, 59, 119):
                    animation.seek(i)
                    with Image.open(root / f"frame_{i:04d}.png") as source:
                        self.assertEqual(animation.convert("RGB").tobytes(), source.convert("RGB").tobytes())
            self.assertTrue((root / "index.html").is_file())
            (root / "frame_0003.png").unlink()
            with self.assertRaises(FileNotFoundError):
                ENCODER.encode(root, root / "missing.gif", 30, 120, 8)

    def test_alpha_compositing_is_linear(self):
        result = ENCODER.composite(Image.new("RGBA", (1, 1), (255, 255, 255, 128)))
        # Half linear white over near-black encodes near 188, not encoded midpoint 137.
        self.assertTrue(all(187 <= channel <= 190 for channel in result.getpixel((0, 0))))


if __name__ == "__main__":
    unittest.main()
