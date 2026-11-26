"""Placeholder parry tones"""

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 16_000
AUDIO_DIR = Path(__file__).resolve().parents[1] / "assets" / "audio"


def write_tone(path: Path, start_hz: float, end_hz: float, duration: float) -> None:
    sample_count = round(SAMPLE_RATE * duration)
    phase = 0.0
    samples = []

    for index in range(sample_count):
        progress = index / sample_count
        frequency = start_hz + (end_hz - start_hz) * progress
        phase += 2 * math.pi * frequency / SAMPLE_RATE
        attack = min(1.0, 12 * progress)
        decay = 1.0 - progress
        samples.append(round(math.sin(phase) * attack * decay * 10_000))

    try:
        with wave.open(str(path), "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(SAMPLE_RATE)
            audio.writeframes(struct.pack(f"<{sample_count}h", *samples))
            print(f"Wrote tone to \"{path}\"")
    except Exception as ex:
        print(f"Failed to write tone to \"{path}\": \"{ex}\"")


def main() -> None:
    write_tone(AUDIO_DIR / "parry-success.wav", 660, 1180, 0.14)
    write_tone(AUDIO_DIR / "parry-failure.wav", 220, 95, 0.22)


if __name__ == "__main__":
    main()
