"""Build original deterministic 48 kHz mono PCM candidates; never publish assets."""
import argparse
import hashlib
import json
import math
import platform
import random
import struct
import wave
from pathlib import Path

RATE = 48000


def synth(recipe):
    count = round(recipe["seconds"] * RATE)
    rng = random.Random(recipe["seed"])
    samples = []
    low = edge = grain = 0.0
    grit = 1.0
    low_rate = math.exp(-math.tau * recipe["body_hz"] / RATE)
    edge_rate = math.exp(-math.tau * recipe["edge_hz"] / RATE)
    body_scale = math.sqrt((1 + low_rate) / (1 - low_rate)) * .55
    for index in range(count):
        t = index / RATE
        # Aperiodic friction and impacts, without tuned oscillators or notes.
        white = rng.uniform(-1, 1)
        low = low_rate * low + (1 - low_rate) * white
        edge = edge_rate * edge + (1 - edge_rate) * white
        if index % 48 == 0:
            grit = rng.uniform(.25, 1)
        if rng.random() < recipe.get("grains_per_second", 0) / RATE:
            grain = rng.uniform(.3, 1)
        grain *= .987
        envelope = 0.0
        for onset, strength in recipe["impacts"]:
            age = t - onset
            if age >= 0:
                envelope += strength * min(1.0, age / .0015) * math.exp(-age * recipe["decay"])
        envelope *= min(1.0, (count - index) / (RATE * .010))
        texture = low * body_scale + (white - edge) * recipe["sharpness"] * (grit + grain)
        value = recipe["gain"] * envelope * texture
        samples.append(round(max(-.5, min(.5, value)) * 32767))
    return struct.pack("<" + "h" * len(samples), *samples)


def write_wave(path, frames):
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(frames)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipes", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    recipes = json.loads(args.recipes.read_text(encoding="utf-8"))
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {"generator": "facets-prototype-sfx-v2-material", "python": platform.python_version(),
                "authorship": "Original mathematical recipes authored for Facets",
                "acceptance": "candidate; listening required", "cues": {}}
    sampler = bytearray()
    for name, recipe in recipes.items():
        frames = synth(recipe)
        target = args.output / (name + ".wav")
        write_wave(target, frames)
        sampler.extend(frames)
        sampler.extend(bytes(RATE))  # half-second mono silence between cues
        manifest["cues"][name] = {"recipe": recipe, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                                  "bytes": target.stat().st_size, "frames": len(frames) // 2}
    write_wave(args.output / "audition.wav", sampler)
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("SFX_CANDIDATES_COMPLETE:", args.output)


if __name__ == "__main__":
    main()
