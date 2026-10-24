#!/usr/bin/env python3
"""Gera sons adicionais (sirene e jump do Roadster) em assets/audio/sfx/."""
import math
import struct
import wave
import os

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
SR = 44100

def save_wav(filename, samples):
    peak = max(abs(x) for x in samples) or 1.0
    scale = 28000.0 / peak
    raw = bytearray()
    for s in samples:
        v = int(max(min(s * scale, 32767), -32768))
        raw.extend(struct.pack('<h', v))
    path = os.path.join(OUT_DIR, filename)
    with wave.open(path, 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(raw)
    print(f"Generated {path}")

# 1. Sirene (polícia / emergência): som característico de giroflex
dur_siren = 1.2
samples_siren = []
total_s = int(dur_siren * SR)
phase = 0.0
for i in range(total_s):
    t = i / SR
    # Frequência modula entre 650Hz e 1150Hz
    mod = math.sin(2.0 * math.pi * 2.5 * t)
    f = 900.0 + 250.0 * mod
    phase += 2.0 * math.pi * f / SR
    # Onda mista senóide + leve harmônico
    s = math.sin(phase) * 0.7 + math.sin(phase * 2.0) * 0.2
    # Envelope com entrada e saída suave
    env = min(t / 0.05, 1.0) * min((dur_siren - t) / 0.05, 1.0)
    samples_siren.append(s * env)

save_wav("siren.wav", samples_siren)

# 2. Jump (Roadster SpaceX Thruster): sopro de ar comprimido com subida e queda
dur_jump = 0.8
samples_jump = []
total_j = int(dur_jump * SR)
p_jump = 0.0
for i in range(total_j):
    t = i / SR
    # Jato de ar comprimido / foguete
    f = 120.0 + 280.0 * math.exp(-3.5 * t)
    p_jump += 2.0 * math.pi * f / SR
    noise = (((i * 1103515245 + 12345) & 0x7FFFFFFF) / 0x7FFFFFFF) * 2.0 - 1.0
    # Mistura ar pressurizado (ruído filtrado) com tom propulsor
    jet = noise * math.exp(-4.0 * t) * 0.6 + math.sin(p_jump) * math.exp(-3.0 * t) * 0.4
    samples_jump.append(jet)

save_wav("jump.wav", samples_jump)
