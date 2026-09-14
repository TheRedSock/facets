"""Validate candidate PCM headers, bounds and provenance; does not certify sound quality."""
import argparse
import hashlib
import json
import struct
import wave
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    manifest = json.loads((args.directory / "manifest.json").read_text(encoding="utf-8"))
    failures = []
    total = 0
    for name, entry in manifest["cues"].items():
        path = args.directory / (name + ".wav")
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            failures.append(name + "/hash")
        with wave.open(str(path), "rb") as audio:
            if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype()) != (1, 2, 48000, "NONE"):
                failures.append(name + "/format")
            if audio.getnframes() != entry["frames"] or not 0 < audio.getnframes() <= 48000:
                failures.append(name + "/duration")
            frames = audio.readframes(audio.getnframes())
            total += len(frames)
            values = struct.unpack("<" + "h" * (len(frames) // 2), frames)
            if max(abs(value) for value in values) > 16384:
                failures.append(name + "/peak")
            if abs(values[0]) > 100 or abs(values[-1]) > 100:
                failures.append(name + "/endpoint")
    if total > 2 * 1024 * 1024:
        failures.append("decoded_budget")
    print(json.dumps({"status": "failed" if failures else "passed", "failures": failures,
                      "candidate_count": len(manifest["cues"]), "decoded_bytes": total,
                      "listening_acceptance": "not established"}, indent=2))
    print("CHECK_COMPLETE: check_prototype_sfx")
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
