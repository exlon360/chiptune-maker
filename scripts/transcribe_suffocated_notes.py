#!/usr/bin/env python3
"""Generate a ChipTune Creator note map from a permitted Suffocated by Hatred audio file."""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf


NOTE_NAMES = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
CHANNELS = [
    {"id": "pulse1", "title": "Pulse 1", "waveform": "pulse50", "volume": 0.46},
    {"id": "pulse2", "title": "Pulse 2", "waveform": "pulse25", "volume": 0.38},
    {"id": "triangle", "title": "Triangle", "waveform": "triangle", "volume": 0.42},
    {"id": "saw", "title": "Saw Lead", "waveform": "saw", "volume": 0.32},
    {"id": "noise", "title": "Noise", "waveform": "noise", "volume": 0.24},
    {"id": "kick", "title": "Kick", "waveform": "kick", "volume": 0.62},
    {"id": "snare", "title": "Snare", "waveform": "snare", "volume": 0.42},
    {"id": "hat", "title": "Hat", "waveform": "hat", "volume": 0.28},
]


def midi_frequency(midi: int) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def midi_name(midi: int) -> str:
    octave = midi // 12 - 1
    return f"{NOTE_NAMES[midi % 12]}{octave}"


def note_sort_key(note: str) -> int:
    base = note[:-1]
    octave = int(note[-1])
    return (octave + 1) * 12 + NOTE_NAMES.index(base)


def download_audio(url: str, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    template = str(output_dir / "suffocated.%(ext)s")
    subprocess.run(
        ["yt-dlp", "--no-playlist", "-x", "--audio-format", "wav", "--audio-quality", "0", "-o", template, url],
        check=True,
    )
    return output_dir / "suffocated.wav"


def load_mono(path: Path) -> tuple[np.ndarray, int]:
    samples, sample_rate = sf.read(str(path), always_2d=True)
    mono = samples.mean(axis=1).astype(np.float32)
    peak = float(np.max(np.abs(mono))) or 1.0
    return mono / peak, int(sample_rate)


def spectral_scores(
    mono: np.ndarray,
    sample_rate: int,
    tempo: float,
    steps: int,
    midi_min: int,
    midi_max: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    n_fft = 8192
    half = n_fft // 2
    window = np.hanning(n_fft).astype(np.float32)
    freqs = np.fft.rfftfreq(n_fft, d=1.0 / sample_rate)
    midi_values = np.arange(midi_min, midi_max + 1)
    step_samples = sample_rate * (60.0 / tempo / 4.0)

    pitch_scores = np.zeros((steps, len(midi_values)), dtype=np.float32)
    low_energy = np.zeros(steps, dtype=np.float32)
    mid_energy = np.zeros(steps, dtype=np.float32)
    high_energy = np.zeros(steps, dtype=np.float32)

    low_mask = (freqs >= 45) & (freqs <= 180)
    mid_mask = (freqs >= 650) & (freqs <= 3200)
    high_mask = (freqs >= 5200) & (freqs <= 13000)

    for step in range(steps):
        center = int(round((step + 0.5) * step_samples))
        start = center - half
        end = start + n_fft
        frame = np.zeros(n_fft, dtype=np.float32)
        src_start = max(0, start)
        src_end = min(len(mono), end)
        if src_end > src_start:
            dst_start = src_start - start
            frame[dst_start : dst_start + (src_end - src_start)] = mono[src_start:src_end]

        spectrum = np.abs(np.fft.rfft(frame * window)).astype(np.float32)
        low_energy[step] = float(np.mean(spectrum[low_mask]))
        mid_energy[step] = float(np.mean(spectrum[mid_mask]))
        high_energy[step] = float(np.mean(spectrum[high_mask]))

        for index, midi in enumerate(midi_values):
            base_freq = midi_frequency(int(midi))
            score = 0.0
            for harmonic in range(1, 9):
                target = base_freq * harmonic
                if target >= freqs[-2]:
                    break
                bin_index = int(np.searchsorted(freqs, target))
                lo = max(1, bin_index - 1)
                hi = min(len(spectrum) - 1, bin_index + 2)
                weight = 1.45 if harmonic == 1 else 1.0 / (harmonic ** 0.72)
                score += float(np.max(spectrum[lo:hi])) * weight
            pitch_scores[step, index] = score

    return midi_values, pitch_scores, low_energy, mid_energy, high_energy


def pick_range_events(
    midi_values: np.ndarray,
    pitch_scores: np.ndarray,
    midi_low: int,
    midi_high: int,
    floor_ratio: float,
    min_length: int = 1,
) -> list[dict[str, float | int | str]]:
    mask = (midi_values >= midi_low) & (midi_values <= midi_high)
    scoped_midi = midi_values[mask]
    scoped_scores = pitch_scores[:, mask]
    best_indexes = scoped_scores.argmax(axis=1)
    best_scores = scoped_scores[np.arange(scoped_scores.shape[0]), best_indexes]
    max_score = float(best_scores.max()) or 1.0
    floor = max(float(np.percentile(best_scores, 42)) * 0.72, max_score * floor_ratio)
    velocities = np.clip((best_scores / max_score) ** 0.45, 0.05, 1.0)

    raw: list[tuple[str | None, float]] = []
    for index, score in enumerate(best_scores):
        if score < floor:
            raw.append((None, 0.0))
        else:
            raw.append((midi_name(int(scoped_midi[int(best_indexes[index])])), float(velocities[index])))

    events: list[dict[str, float | int | str]] = []
    active_note: str | None = None
    active_start = 0
    active_velocity = 0.0
    active_count = 0

    def flush(end_step: int) -> None:
        nonlocal active_note, active_start, active_velocity, active_count
        if active_note is not None and end_step - active_start >= min_length:
            events.append(
                {
                    "note": active_note,
                    "startStep": active_start,
                    "length": end_step - active_start,
                    "velocity": round(max(0.05, min(1.0, active_velocity / max(active_count, 1))), 2),
                }
            )
        active_note = None
        active_velocity = 0.0
        active_count = 0

    for step, (note, velocity) in enumerate(raw):
        if note != active_note:
            flush(step)
            if note is not None:
                active_note = note
                active_start = step
                active_velocity = velocity
                active_count = 1
        elif note is not None:
            active_velocity += velocity
            active_count += 1

    flush(len(raw))
    return events


def pick_accent_events(
    midi_values: np.ndarray,
    pitch_scores: np.ndarray,
    used_notes: list[set[str]],
    midi_low: int,
    midi_high: int,
) -> list[dict[str, float | int | str]]:
    mask = (midi_values >= midi_low) & (midi_values <= midi_high)
    scoped_midi = midi_values[mask]
    scoped_scores = pitch_scores[:, mask]
    max_scores = scoped_scores.max(axis=1)
    threshold = max(float(np.percentile(max_scores, 73)), float(max_scores.max()) * 0.16)
    events: list[dict[str, float | int | str]] = []

    for step in range(scoped_scores.shape[0]):
        if max_scores[step] < threshold:
            continue

        ranked = np.argsort(scoped_scores[step])[-5:][::-1]
        chosen: str | None = None
        for index in ranked:
            candidate = midi_name(int(scoped_midi[int(index)]))
            if candidate not in used_notes[step]:
                chosen = candidate
                break

        if chosen is None:
            continue

        if events and events[-1]["note"] == chosen and events[-1]["startStep"] + events[-1]["length"] == step:
            events[-1]["length"] = int(events[-1]["length"]) + 1
            events[-1]["velocity"] = round(min(1.0, (float(events[-1]["velocity"]) + 0.74) / 2.0), 2)
        else:
            velocity = round(max(0.24, min(0.86, float(max_scores[step] / (max_scores.max() or 1.0)) ** 0.5)), 2)
            events.append({"note": chosen, "startStep": step, "length": 1, "velocity": velocity})

    return events


def pick_hits(energy: np.ndarray, note: str, ratio: float, min_gap: int) -> list[dict[str, float | int | str]]:
    baseline = float(np.percentile(energy, 55))
    peak = float(energy.max()) or 1.0
    threshold = max(float(np.percentile(energy, 78)), peak * ratio, baseline * 1.25)
    events: list[dict[str, float | int | str]] = []
    last_step = -min_gap
    for step, value in enumerate(energy):
        if value < threshold or step - last_step < min_gap:
            continue
        prev_value = energy[step - 1] if step > 0 else 0
        next_value = energy[step + 1] if step + 1 < len(energy) else 0
        if value < prev_value or value < next_value * 0.78:
            continue
        velocity = round(max(0.18, min(1.0, math.sqrt(float(value / peak)))), 2)
        events.append({"note": note, "startStep": step, "length": 1, "velocity": velocity})
        last_step = step
    return events


def build_config(audio_path: Path, tempo: float, steps: int) -> dict:
    mono, sample_rate = load_mono(audio_path)
    midi_values, pitch_scores, low_energy, mid_energy, high_energy = spectral_scores(
        mono=mono,
        sample_rate=sample_rate,
        tempo=tempo,
        steps=steps,
        midi_min=48,
        midi_max=84,
    )

    patterns: dict[str, list[dict[str, float | int | str]]] = {
        "triangle": pick_range_events(midi_values, pitch_scores, 48, 59, 0.018),
        "pulse2": pick_range_events(midi_values, pitch_scores, 60, 72, 0.024),
        "pulse1": pick_range_events(midi_values, pitch_scores, 72, 84, 0.024),
    }

    used_by_step = [set() for _ in range(steps)]
    for channel in ("triangle", "pulse2", "pulse1"):
        for event in patterns[channel]:
            for step in range(int(event["startStep"]), min(steps, int(event["startStep"]) + int(event["length"]))):
                used_by_step[step].add(str(event["note"]))

    patterns["saw"] = pick_accent_events(midi_values, pitch_scores, used_by_step, 60, 84)
    patterns["kick"] = pick_hits(low_energy, "C-4", ratio=0.46, min_gap=2)
    patterns["snare"] = pick_hits(mid_energy, "C-5", ratio=0.52, min_gap=3)
    patterns["hat"] = pick_hits(high_energy, "G-5", ratio=0.38, min_gap=1)
    patterns["noise"] = pick_hits(high_energy + (mid_energy * 0.42), "G-5", ratio=0.32, min_gap=2)

    note_names = {
        str(event["note"])
        for channel_events in patterns.values()
        for event in channel_events
    }
    notes = sorted(note_names, key=note_sort_key, reverse=True)

    return {
        "tempo": tempo,
        "steps": steps,
        "notes": notes,
        "channels": CHANNELS,
        "patterns": patterns,
        "metadata": {
            "source": "Suffocated by Hatred audio transcription",
            "stepResolution": "1/16",
            "analysis": "FFT harmonic pitch scoring per sequencer step plus energy-band percussion hits",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, help="Input WAV/AIFF/FLAC audio path")
    parser.add_argument("--youtube-url", help="Download this URL with yt-dlp before transcription")
    parser.add_argument("--output", type=Path, required=True, help="Output ChipTune Creator JSON config")
    parser.add_argument("--tempo", type=float, default=156.0)
    parser.add_argument("--steps", type=int, default=1936)
    args = parser.parse_args()

    audio_path = args.input
    if args.youtube_url:
        temp_dir = Path(tempfile.gettempdir()) / "chiptune-suffocated-transcribe"
        audio_path = download_audio(args.youtube_url, temp_dir)
    if audio_path is None:
        raise SystemExit("Pass --input or --youtube-url")

    config = build_config(audio_path, args.tempo, args.steps)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")

    totals = {channel: len(events) for channel, events in config["patterns"].items()}
    print(json.dumps({"steps": config["steps"], "notes": len(config["notes"]), "events": totals}, indent=2))


if __name__ == "__main__":
    main()
