"""Generate the original CC0 propeller loop; run from any directory."""
import hashlib
import json
import math
from pathlib import Path
import struct
import wave


def main():
    root = Path(__file__).resolve().parents[1]
    project = root / "GodotDemo" if (root / "GodotDemo").is_dir() else root
    directory = project / "assets/audio"
    rate, seconds = 22050, 2
    samples = []
    for index in range(rate * seconds):
        time = index / rate
        pulse = 0.72 + 0.28 * math.cos(math.tau * 14 * time)
        carrier = (0.27 * math.sin(math.tau * 56 * time)
                   + 0.13 * math.sin(math.tau * 112 * time)
                   + 0.06 * math.sin(math.tau * 168 * time)
                   + 0.02 * math.sin(math.tau * 308 * time))
        samples.append(round(pulse * carrier * 32767))
    output = directory / "airplane_engine.wav"
    with wave.open(str(output), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(rate)
        stream.writeframes(struct.pack("<%dh" % len(samples), *samples))
    values = [sample / 32768 for sample in samples]
    manifest_path = directory / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["assets"] = [asset for asset in manifest["assets"] if asset["file"] != output.name]
    manifest["assets"].append({
        "file": output.name, "generator": "tools/generate_aircraft_audio.py",
        "license": "CC0-1.0", "sample_rate": rate, "channels": 1,
        "sample_width_bytes": 2, "frames": len(values), "duration_seconds": seconds,
        "loop": True, "peak": max(abs(value) for value in values),
        "rms": math.sqrt(sum(value * value for value in values) / len(values)),
        "max_channel_dc": abs(sum(values) / len(values)),
        "seam_delta": abs(values[-1] - values[0]),
        "max_adjacent_step": max(abs(a - b) for a, b in zip(values, values[1:])),
        "size_bytes": output.stat().st_size,
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    })
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
