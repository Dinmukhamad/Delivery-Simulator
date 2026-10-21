"""Create deterministic, original CC0 arcade aircraft shot/impact sounds."""
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave


def main():
    root = Path(__file__).resolve().parents[1]
    project = root / "GodotDemo" if (root / "GodotDemo").is_dir() else root
    directory = project / "assets/audio"
    manifest_path = directory / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    rate = 22050
    for name, seconds, seed in [("aircraft_fire", 0.13, 16001), ("aircraft_hit", 0.36, 16002)]:
        rng = random.Random(seed)
        samples = []
        for index in range(round(seconds * rate)):
            time = index / rate
            fade = min(1.0, time / 0.003) * max(0.0, 1.0 - time / seconds) ** 2
            if name == "aircraft_fire":
                value = 0.26 * math.sin(math.tau * (420 * time - 650 * time * time)) + 0.18 * rng.uniform(-1, 1)
            else:
                value = 0.22 * math.sin(math.tau * (110 * time - 90 * time * time)) + 0.25 * rng.uniform(-1, 1)
            samples.append(round(32767 * fade * value))
        output = directory / (name + ".wav")
        with wave.open(str(output), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(rate)
            stream.writeframes(struct.pack("<%dh" % len(samples), *samples))
        values = [sample / 32768 for sample in samples]
        manifest["assets"] = [asset for asset in manifest["assets"] if asset["file"] != output.name]
        manifest["assets"].append({
            "file": output.name, "generator": "tools/generate_combat_audio.py", "license": "CC0-1.0",
            "sample_rate": rate, "channels": 1, "sample_width_bytes": 2, "frames": len(values),
            "duration_seconds": len(values) / rate, "loop": False,
            "peak": max(abs(value) for value in values),
            "rms": math.sqrt(sum(value * value for value in values) / len(values)),
            "max_channel_dc": abs(sum(values) / len(values)), "seam_delta": abs(values[-1] - values[0]),
            "max_adjacent_step": max(abs(a - b) for a, b in zip(values, values[1:])),
            "size_bytes": output.stat().st_size, "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        })
    manifest["total_wav_bytes"] = sum(asset["size_bytes"] for asset in manifest["assets"])
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
