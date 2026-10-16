"""
Gera todas as músicas e efeitos sonoros do ZERO-IMPACT (sintetizados, sem
samples externos) em assets/audio/. Precisa de Python 3 + numpy.

    python tools/gerar_sons.py
"""
import os
import wave
import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- básicos

def save(rel, x, level=0.9, fade=True):
    x = np.asarray(x, dtype=np.float64).copy()
    if fade:  # rampa curtinha nas pontas para não estalar
        f = min(220, len(x) // 4)
        x[:f] *= np.linspace(0, 1, f)
        x[-f:] *= np.linspace(1, 0, f)
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x / peak * level
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    print("ok", rel, f"{len(x) / SR:.2f}s")


def n_of(d):
    return int(SR * d)


def tt(d):
    return np.arange(n_of(d)) / SR


def midi(note):
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    n = names[note[0]]
    rest = note[1:]
    if rest.startswith("#"):
        n += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        n -= 1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + n


def hz(note):
    return 440.0 * 2 ** ((midi(note) - 69) / 12)


def osc(freq, d, kind="sine", duty=0.5):
    n = n_of(d)
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    ph = np.cumsum(f) / SR
    ph = ph - np.floor(ph)
    if kind == "sine":
        return np.sin(2 * np.pi * ph)
    if kind == "square":
        return np.where(ph < duty, 1.0, -1.0)
    if kind == "saw":
        return 2 * ph - 1
    if kind == "tri":
        return 2 * np.abs(2 * ph - 1) - 1
    raise ValueError(kind)


def noise(d):
    return rng.uniform(-1, 1, n_of(d))


def lp(x, cutoff):
    """Passa-baixa de um polo (cutoff pode ser escalar ou array)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def hp(x, cutoff):
    return x - lp(x, cutoff)


def adsr(n, a=0.005, d=0.05, s=0.7, r=0.05):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(n - a_n - d_n - r_n, 0)
    e = np.concatenate([
        np.linspace(0, 1, a_n, endpoint=False),
        np.linspace(1, s, d_n, endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, r_n),
    ])
    return np.pad(e, (0, max(n - len(e), 0)))[:n]


def expdec(d, tau):
    return np.exp(-tt(d) / tau)


def mix_at(buf, x, start):
    s = int(start * SR)
    end = min(s + len(x), len(buf))
    if s < len(buf):
        buf[s:end] += x[: end - s]


# ---------------------------------------------------------------- instrumentos

def kick():
    d = 0.35
    f = 45 + 110 * np.exp(-tt(d) / 0.03)
    x = osc(f, d) * expdec(d, 0.12)
    x[:200] += np.linspace(0.6, 0, 200) * noise(200 / SR)
    return x


def snare():
    d = 0.22
    body = osc(185, d, "tri") * expdec(d, 0.05)
    sn = hp(noise(d), 1500) * expdec(d, 0.07)
    return 0.6 * body + 0.9 * sn


def hat(open_=False):
    d = 0.18 if open_ else 0.05
    return hp(noise(d), 7000) * expdec(d, 0.06 if open_ else 0.012)


def bass(note, d):
    f = hz(note)
    x = osc(f, d, "saw") + 0.6 * osc(f * 0.5, d, "square")
    cut = 300 + 1400 * np.exp(-tt(d) / 0.06)
    return lp(x, cut) * adsr(n_of(d), 0.003, 0.08, 0.6, 0.03)


def pluck(note, d, bright=3500):
    f = hz(note)
    x = osc(f, d, "square", 0.25) + 0.5 * osc(f * 1.005, d, "saw")
    return lp(x, bright * np.exp(-tt(d) / 0.15) + 400) * expdec(d, 0.11)


def pad(notes, d):
    x = np.zeros(n_of(d))
    for nt in notes:
        f = hz(nt)
        for det in (0.995, 1.0, 1.006):
            x += osc(f * det, d, "saw")
    return lp(x, 1300) * adsr(n_of(d), 0.35, 0.3, 0.75, 0.4)


def lead(note, d):
    f = hz(note)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * tt(d)) * np.clip(tt(d) / 0.25, 0, 1)
    x = osc(f * vib, d, "saw") + 0.7 * osc(f * vib * 1.008, d, "square", 0.4)
    return lp(x, 2600) * adsr(n_of(d), 0.01, 0.1, 0.75, 0.08)


def bell(note, d):
    f = hz(note)
    x = osc(f, d) + 0.4 * osc(f * 2.76, d) * expdec(d, 0.15) + 0.2 * osc(f * 5.4, d) * expdec(d, 0.05)
    return x * expdec(d, 0.5)


def delay_wrap(x, beat, amount=0.3, taps=3):
    """Eco que dá a volta no fim (para o loop não ter emenda)."""
    y = x.copy()
    shift = int(beat * 0.75 * SR)
    for k in range(1, taps + 1):
        y += np.roll(x, shift * k) * (amount ** k)
    return y


# ---------------------------------------------------------------- músicas

CHORDS = {
    "Am": ["A3", "C4", "E4"], "F": ["F3", "A3", "C4"], "C": ["C4", "E4", "G4"],
    "G": ["G3", "B3", "D4"], "E": ["E3", "G#3", "B3"], "Em": ["E3", "G3", "B3"],
    "Dm": ["D3", "F3", "A3"],
}
ROOTS = {"Am": "A1", "F": "F1", "C": "C2", "G": "G1", "E": "E1", "Em": "E1", "Dm": "D2"}


def up_oct(note, k=1):
    i = 1 if len(note) > 1 and note[1] in "#b" else 0
    return note[: i + 1] + str(int(note[i + 1:]) + k)


def render_song(bpm, prog, passes, melody=None, style="race"):
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * len(prog) * passes
    L = n_of(total)
    drums = np.zeros(L)
    bassb = np.zeros(L)
    arp = np.zeros(L)
    pads = np.zeros(L)
    mel = np.zeros(L)

    K, S, H, HO = kick(), snare(), hat(), hat(True)
    for p in range(passes):
        for bi, ch in enumerate(prog):
            t0 = (p * len(prog) + bi) * bar
            notes = CHORDS[ch]
            root = ROOTS[ch]
            pads_d = bar
            mix_at(pads, pad(notes, pads_d + 0.3), t0)
            for b in range(4):
                tb = t0 + b * beat
                if style == "race":
                    mix_at(drums, K, tb)
                    if b in (1, 3):
                        mix_at(drums, S, tb)
                    for e in range(2):
                        mix_at(drums, HO if e == 1 and b == 3 else H, tb + e * beat / 2)
                else:
                    if b in (0, 2):
                        mix_at(drums, K * 0.8, tb)
                    if b == 3 and p % 2 == 1:
                        mix_at(drums, S * 0.4, tb)
                    mix_at(drums, H * 0.6, tb + beat / 2)
                # baixo
                if style == "race":
                    for e in range(2):
                        nt = root if e == 0 else up_oct(root)
                        mix_at(bassb, bass(nt, beat / 2 * 0.9), tb + e * beat / 2)
                else:
                    if b in (0, 2):
                        mix_at(bassb, bass(root, beat * 1.8), tb)
            # arpejo
            seq = [notes[0], notes[1], notes[2], up_oct(notes[0]), notes[2], notes[1]] * 3
            step = beat / 4 if style == "race" else beat / 2
            count = 16 if style == "race" else 8
            for k in range(count):
                mix_at(arp, pluck(up_oct(seq[k % len(seq)]), step * 1.6, 4000 if style == "race" else 2000), t0 + k * step)

            # melodia (só em algumas passadas)
            if melody and (style == "race" and p % 2 == 1 or style == "menu" and p >= 1):
                tokens = melody[bi].split()
                step8 = beat / 2
                k = 0
                while k < len(tokens):
                    tok = tokens[k]
                    if tok in ("-", "."):
                        k += 1
                        continue
                    ln = 1
                    while k + ln < len(tokens) and tokens[k + ln] == "-":
                        ln += 1
                    inst = lead if style == "race" else bell
                    mix_at(mel, inst(tok, step8 * ln * 0.95 + (0.0 if style == "race" else 0.8)), t0 + k * step8)
                    k += ln

    # "pump" do sidechain no ritmo do bumbo
    phase = (np.arange(L) / SR) % beat
    pump = 1 - 0.55 * np.exp(-phase / 0.12) if style == "race" else 1 - 0.25 * np.exp(-phase / 0.2)

    arp = delay_wrap(arp, beat, 0.35)
    mel = delay_wrap(mel, beat, 0.3)
    pads = delay_wrap(pads, beat, 0.2, 2)
    if style == "race":
        out = 0.9 * drums + 0.55 * bassb * pump + 0.16 * arp * pump + 0.13 * pads * pump + 0.2 * mel
    else:
        out = 0.5 * drums + 0.45 * bassb * pump + 0.14 * arp + 0.2 * pads * pump + 0.35 * mel
    # fade curtinho nas pontas para o loop não estalar
    f = 256
    out[:f] *= np.linspace(0, 1, f)
    out[-f:] *= np.linspace(1, 0, f)
    return out


RACE_MELODY = [
    "E5 - A5 - C6 - B5 A5",
    "A5 - C6 - A5 - G5 F5",
    "E5 - G5 - C6 - B5 G5",
    "D5 - G5 - B5 - A5 G5",
    "E5 A5 C6 E6 D6 C6 B5 A5",
    "C6 - A5 - F5 - A5 C6",
    "G5 - E5 - G5 - C6 -",
    "B5 - G#5 - E5 - - -",
]

MENU_MELODY = [
    "E5 - - - C5 - D5 -",
    "C5 - - - A4 - - -",
    "G5 - - - E5 - D5 -",
    "D5 - - - B4 - - -",
    "E5 - - - G5 - A5 -",
    "C6 - - - A5 - - -",
    "G5 - E5 - D5 - C5 -",
    "B4 - - - - - - -",
]


def music():
    race = render_song(128, ["Am", "F", "C", "G", "Am", "F", "C", "E"], 2, RACE_MELODY, "race")
    save("music/race.wav", race, 0.8, fade=False)
    menu = render_song(96, ["Am", "F", "C", "G", "Am", "F", "C", "Em"], 2, MENU_MELODY, "menu")
    save("music/menu.wav", menu, 0.75, fade=False)

    # jingle de game over
    d = 2.6
    x = np.zeros(n_of(d))
    for i, nt in enumerate(["E5", "C5", "A4", "F4"]):
        mix_at(x, lead(nt, 0.32) * 0.8, i * 0.24)
    mix_at(x, pad(["A3", "C4", "E4"], 1.6), 0.96)
    mix_at(x, bell("A4", 1.6), 0.96)
    x = delay_wrap(np.pad(x, (0, n_of(0.6))), 0.4, 0.25)
    save("music/gameover.wav", x, 0.75)


# ---------------------------------------------------------------- efeitos

def sfx():
    # moeda: duas notinhas quadradas
    a = osc(hz("B5"), 0.06, "square", 0.5) * 0.6
    b = osc(hz("E6"), 0.16, "square", 0.5) * expdec(0.16, 0.06)
    save("sfx/coin.wav", lp(np.concatenate([a, b]), 6000), 0.5)

    # escudo: subida brilhante
    d = 0.6
    f = np.linspace(300, 1200, n_of(d))
    x = osc(f, d) + 0.5 * osc(f * 1.5, d, "tri") + 0.3 * osc(f * 2.01, d)
    x *= adsr(n_of(d), 0.01, 0.1, 0.7, 0.3)
    save("sfx/power_shield.wav", delay_wrap(np.pad(x, (0, n_of(0.3))), 0.15, 0.3), 0.6)

    # câmera lenta: descida com vibrato
    d = 0.8
    f = np.linspace(900, 150, n_of(d)) * (1 + 0.05 * np.sin(2 * np.pi * 9 * tt(d)))
    x = lp(osc(f, d, "saw") + osc(f * 0.5, d, "square"), 1800) * adsr(n_of(d), 0.01, 0.2, 0.6, 0.3)
    save("sfx/power_slow.wav", x, 0.55)

    # estrela de pontos: arpejo para cima
    x = np.zeros(n_of(0.6))
    for i, nt in enumerate(["C6", "E6", "G6", "C7"]):
        mix_at(x, osc(hz(nt), 0.2, "square", 0.25) * expdec(0.2, 0.07), i * 0.06)
    save("sfx/power_points.wav", lp(delay_wrap(x, 0.12, 0.3), 7000), 0.5)

    # batida/explosão
    d = 1.2
    cut = 200 + 4000 * np.exp(-tt(d) / 0.1)
    boom = lp(noise(d), cut) * expdec(d, 0.3)
    thump = osc(40 + 80 * np.exp(-tt(d) / 0.05), d) * expdec(d, 0.18)
    crunch = hp(noise(d), 2500) * expdec(d, 0.04)
    save("sfx/crash.wav", 1.0 * boom + 0.9 * thump + 0.4 * crunch, 0.95)

    # escudo bloqueando: "ping" metálico
    d = 0.5
    x = (osc(1800, d) + 0.6 * osc(2700, d) + 0.4 * osc(4100, d)) * expdec(d, 0.12)
    x += 0.6 * lp(noise(d), 3000) * expdec(d, 0.04)
    save("sfx/shield_block.wav", x, 0.6)

    # perdeu uma vida
    x = np.concatenate([
        lp(osc(330, 0.15, "square"), 2500) * adsr(n_of(0.15), 0.005, 0.02, 0.8, 0.03),
        lp(osc(220, 0.3, "square"), 2000) * adsr(n_of(0.3), 0.005, 0.05, 0.7, 0.15),
    ])
    save("sfx/life_lost.wav", x, 0.55)

    # escudo acabando
    d = 0.35
    x = osc(np.linspace(1100, 400, n_of(d)), d, "tri") * expdec(d, 0.12)
    save("sfx/shield_end.wav", x, 0.45)

    # troca de faixa: "whoosh" curto
    d = 0.22
    e = np.sin(np.pi * np.clip(tt(d) / d, 0, 1)) ** 2
    x = lp(noise(d), np.linspace(800, 3000, n_of(d))) * e
    save("sfx/whoosh.wav", x, 0.35)

    # novo cenário: whoosh longo + sininho
    d = 1.2
    e = np.sin(np.pi * np.clip(tt(d) / 0.8, 0, 1)) ** 2
    x = lp(noise(d), np.linspace(400, 2500, n_of(d))) * e * 0.5
    mix_at(x, bell("E6", 0.8) * 0.5, 0.3)
    mix_at(x, bell("B6", 0.6) * 0.4, 0.45)
    save("sfx/biome.wav", x, 0.45)

    # interface
    save("sfx/ui_move.wav", osc(1400, 0.04, "square", 0.3) * expdec(0.04, 0.012), 0.25)
    x = np.concatenate([osc(900, 0.04, "square", 0.3), osc(1350, 0.08, "square", 0.3) * expdec(0.08, 0.03)])
    save("sfx/ui_click.wav", lp(x, 5000), 0.35)
    x = np.zeros(n_of(0.7))
    for i, nt in enumerate(["E6", "G#6", "B6", "E7"]):
        mix_at(x, bell(nt, 0.4), i * 0.07)
    mix_at(x, hp(noise(0.3), 5000) * expdec(0.3, 0.05) * 0.5, 0.0)
    save("sfx/ui_buy.wav", x, 0.5)
    x = lp(osc(110, 0.25, "square") + osc(116, 0.25, "square"), 1500) * adsr(n_of(0.25), 0.005, 0.02, 0.8, 0.05)
    save("sfx/ui_error.wav", x, 0.45)

    # buzina (carros que trocam de faixa perto do jogador)
    d = 0.35
    x = lp(osc(370, d, "square") + osc(466, d, "square"), 1800) * adsr(n_of(d), 0.01, 0.05, 0.9, 0.05)
    save("sfx/horn.wav", x, 0.35)

    # motor em loop (1 s, ciclos inteiros para emendar sem estalo)
    # renderiza 2 s e guarda só o segundo (filtro já estabilizado)
    d = 2.0
    wob = 1 + 0.02 * np.sin(2 * np.pi * 6 * tt(d))
    x = osc(60 * wob, d, "saw") + 0.7 * osc(120 * wob, d, "square", 0.3) + 0.3 * osc(30, d, "saw")
    x = lp(x, 700)[n_of(1.0):]
    save("sfx/engine.wav", x, 0.5, fade=False)


if __name__ == "__main__":
    sfx()
    music()
