#!/usr/bin/env python3
"""Gera faixas de radio adicionais em assets/audio/music/ usando Python puro."""
import math
import struct
import wave
import os

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "music")
SR = 44100

def note_freq(name):
    notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    nt = name[:-1]
    octave = int(name[-1])
    idx = notes.index(nt)
    midi = 12 * (octave + 1) + idx
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))

def make_track(filename, bpm, bar_count, chords, bass_pattern, lead_pattern):
    beat_dur = 60.0 / bpm
    bar_dur = beat_dur * 4.0
    total_dur = bar_dur * bar_count
    total_samples = int(total_dur * SR)
    buf = [0.0] * total_samples

    # Mix drums
    for bar in range(bar_count):
        bar_start = bar * bar_dur
        for beat in range(4):
            t_beat = bar_start + beat * beat_dur
            idx_beat = int(t_beat * SR)

            # Kick on beats 0 and 2
            if beat in (0, 2):
                kick_samples = int(0.12 * SR)
                for i in range(kick_samples):
                    if idx_beat + i < total_samples:
                        t = i / SR
                        f = 140.0 * math.exp(-35.0 * t) + 45.0
                        amp = math.exp(-22.0 * t)
                        buf[idx_beat + i] += math.sin(2.0 * math.pi * f * t) * amp * 0.55

            # Snare on beats 1 and 3
            if beat in (1, 3):
                snare_samples = int(0.15 * SR)
                for i in range(snare_samples):
                    if idx_beat + i < total_samples:
                        t = i / SR
                        noise = (((i * 1103515245 + 12345) & 0x7FFFFFFF) / 0x7FFFFFFF) * 2.0 - 1.0
                        amp = math.exp(-24.0 * t)
                        body = math.sin(2.0 * math.pi * 180.0 * t) * math.exp(-30.0 * t)
                        buf[idx_beat + i] += (noise * 0.4 + body * 0.3) * amp * 0.4

            # Hi-hat on every 8th note
            for sub in (0, 0.5):
                t_hat = t_beat + sub * beat_dur
                idx_hat = int(t_hat * SR)
                hat_samples = int(0.04 * SR)
                for i in range(hat_samples):
                    if idx_hat + i < total_samples:
                        noise = (((i * 1664525 + 1013904223) & 0x7FFFFFFF) / 0x7FFFFFFF) * 2.0 - 1.0
                        buf[idx_hat + i] += noise * math.exp(-80.0 * (i / SR)) * 0.15

    # Mix Bass and Leads
    for bar in range(bar_count):
        bar_start = bar * bar_dur
        root_chord = chords[bar % len(chords)]

        # Bassline
        for sub_step, note_offset in bass_pattern:
            t_note = bar_start + (sub_step / 16.0) * bar_dur
            idx_note = int(t_note * SR)
            freq = note_freq(root_chord + str(note_offset[1])) * (2.0 ** (note_offset[0] / 12.0))
            note_dur = (1.0 / 16.0) * bar_dur * 0.95
            dur_samples = int(note_dur * SR)
            for i in range(dur_samples):
                if idx_note + i < total_samples:
                    t = i / SR
                    # Sawtooth approximation with first 3 harmonics
                    saw = (math.sin(2 * math.pi * freq * t) +
                           0.5 * math.sin(4 * math.pi * freq * t) +
                           0.25 * math.sin(6 * math.pi * freq * t))
                    amp = math.exp(-12.0 * t)
                    buf[idx_note + i] += saw * amp * 0.28

        # Lead / Arp
        for sub_step, (semi, oct_offset) in lead_pattern:
            t_note = bar_start + (sub_step / 16.0) * bar_dur
            idx_note = int(t_note * SR)
            freq = note_freq(root_chord + str(oct_offset)) * (2.0 ** (semi / 12.0))
            note_dur = (1.0 / 16.0) * bar_dur * 1.5
            dur_samples = int(note_dur * SR)
            for i in range(dur_samples):
                if idx_note + i < total_samples:
                    t = i / SR
                    sq = 1.0 if (math.sin(2 * math.pi * freq * t) > 0) else -1.0
                    amp = math.exp(-10.0 * t)
                    buf[idx_note + i] += sq * amp * 0.14

    # Normalize and write 16-bit PCM WAV
    peak = max(abs(x) for x in buf) or 1.0
    scale = 28000.0 / peak
    raw_data = bytearray()
    for x in buf:
        val = int(max(min(x * scale, 32767), -32768))
        raw_data.extend(struct.pack('<h', val))

    out_path = os.path.join(OUT_DIR, filename)
    with wave.open(out_path, 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(raw_data)
    print(f"Generated {out_path} ({len(raw_data)} bytes)")

# Cyber Rush: 136 BPM, 8 bars, driving Dm / Bb / F / C
make_track(
    "race_cyber.wav",
    bpm=136,
    bar_count=8,
    chords=["D", "A#", "F", "C", "D", "A#", "G", "A"],
    bass_pattern=[(i * 2, (0, 2)) for i in range(8)],
    lead_pattern=[
        (0, (0, 4)), (2, (3, 4)), (4, (7, 4)), (6, (12, 4)),
        (8, (7, 4)), (10, (10, 4)), (12, (12, 4)), (14, (15, 4))
    ]
)

# Chill Drive: 110 BPM, 8 bars, mellow Em / C / G / D
make_track(
    "race_chill.wav",
    bpm=110,
    bar_count=8,
    chords=["E", "C", "G", "D", "E", "C", "B", "A"],
    bass_pattern=[(0, (0, 2)), (4, (0, 2)), (8, (7, 2)), (12, (5, 2))],
    lead_pattern=[
        (0, (0, 4)), (3, (7, 4)), (6, (11, 4)), (9, (12, 4)),
        (12, (14, 4)), (14, (11, 4))
    ]
)
