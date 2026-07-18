#!/usr/bin/env python3
"""Audio chiptune Miarritze : musiques par lieu + SFX.

Synthèse 8-bit maison (carré, triangle, bruit), mixage simple, export WAV
puis conversion OGG via ffmpeg. Mélodies : arrangements originaux inspirés
du répertoire traditionnel basque (domaine public) — cf. DESIGN.md §7.
"""
import math, os, random, struct, subprocess, sys, tempfile

SR = 32000

# ---------------------------------------------------------------- synthèse

def square(phase, duty=0.5):
    return 0.6 if (phase % 1.0) < duty else -0.6

def triangle(phase):
    p = phase % 1.0
    return 4.0 * abs(p - 0.5) - 1.0

def noise_sample(state):
    # LFSR 15 bits façon NES
    bit = (state ^ (state >> 1)) & 1
    state = (state >> 1) | (bit << 14)
    return state, (1.0 if state & 1 else -1.0) * 0.4

def midi_freq(note):
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def render_note(buf, start, dur, note, wave="square", duty=0.5, vol=0.5,
                attack=0.004, release=0.05, vibrato=0.0, slide=0):
    """Ajoute une note dans buf (liste de floats)."""
    n = int(dur * SR)
    freq = midi_freq(note)
    freq_end = midi_freq(note + slide) if slide else freq
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = freq + (freq_end - freq) * (i / max(n - 1, 1))
        if vibrato:
            f *= 1.0 + vibrato * math.sin(2 * math.pi * 5.5 * t)
        phase += f / SR
        env = 1.0
        if t < attack:
            env = t / attack
        rem = dur - t
        if rem < release:
            env = max(rem / release, 0.0)
        s = square(phase, duty) if wave == "square" else triangle(phase)
        idx = start + i
        if idx < len(buf):
            buf[idx] += s * vol * env


def render_drum(buf, start, kind, vol=0.5):
    state = 0x4001
    if kind == "kick":
        n = int(0.09 * SR)
        for i in range(n):
            t = i / SR
            f = 110 * (1 - t * 8)
            s = math.sin(2 * math.pi * max(f, 30) * t)
            idx = start + i
            if idx < len(buf):
                buf[idx] += s * vol * (1 - i / n)
    else:  # hat / snare
        n = int((0.03 if kind == "hat" else 0.08) * SR)
        for i in range(n):
            state, s = noise_sample(state)
            idx = start + i
            if idx < len(buf):
                buf[idx] += s * vol * (1 - i / n) * (0.5 if kind == "hat" else 1.0)


def mix_to_wav(path, buf):
    # normalisation douce + clip
    peak = max(1e-6, max(abs(s) for s in buf))
    gain = min(0.85 / peak, 1.0)
    with open(path, "wb") as f:
        data = b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in buf)
        f.write(b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16))
        f.write(b"data" + struct.pack("<I", len(data)) + data)


# ---------------------------------------------------------------- musique

# Notation : listes (note_midi | None, durée_en_temps). None = silence.
# La mélodie est jouée au carré, la basse au triangle, batterie kick/hat.

def song(path, bpm, melody, bass, drums=None, duty=0.5, vibrato=0.006,
         mel_vol=0.30, bass_vol=0.26, swing=0.0):
    beat = 60.0 / bpm
    total_beats = sum(d for _, d in melody)
    n = int(total_beats * beat * SR) + SR // 4
    buf = [0.0] * n

    t = 0.0
    for i, (note, d) in enumerate(melody):
        dur = d * beat
        sw = swing * beat if i % 2 == 1 else 0.0
        if note is not None:
            render_note(buf, int((t + sw) * SR), dur * 0.92, note, "square",
                        duty=duty, vol=mel_vol, vibrato=vibrato)
        t += dur
    t = 0.0
    for note, d in bass:
        dur = d * beat
        if note is not None:
            render_note(buf, int(t * SR), dur * 0.95, note, "triangle", vol=bass_vol)
        t += dur
    if drums:
        pattern, step_beats = drums
        b = 0.0
        while b < total_beats - 0.01:
            for j, kind in enumerate(pattern):
                if kind and b + j * step_beats < total_beats:
                    render_drum(buf, int((b + j * step_beats) * beat * SR), kind, 0.35)
            b += len(pattern) * step_beats
    buf = buf[:int(total_beats * beat * SR)]  # boucle exacte
    mix_to_wav(path, buf)


N = None
# degrés utiles (MIDI) : C4=60
def notes(seq):
    return [(n, d) for n, d in seq]


SONGS = {}

# HUB — inspiré d'Agur Jaunak (3/4 lent, chaleureux)
SONGS["hub"] = dict(
    bpm=100, duty=0.5, vibrato=0.01,
    melody=notes([
        (67, 1), (67, 1), (69, 1), (71, 2), (69, 1),
        (67, 1), (69, 1), (67, 1), (64, 3),
        (65, 1), (65, 1), (67, 1), (69, 2), (67, 1),
        (65, 1), (64, 1), (62, 1), (60, 3),
        (67, 1), (67, 1), (69, 1), (71, 2), (69, 1),
        (72, 1), (71, 1), (69, 1), (67, 3),
        (65, 1), (69, 1), (67, 1), (64, 2), (62, 1),
        (60, 1), (62, 1), (64, 1), (67, 3),
    ]),
    bass=notes([
        (48, 3), (43, 3), (48, 3), (43, 3),
        (41, 3), (43, 3), (48, 3), (43, 3),
        (48, 3), (43, 3), (45, 3), (48, 3),
        (41, 3), (43, 3), (48, 3), (48, 3),
    ]),
    drums=None,
)

# GRANDE PLAGE — course, 2/4 rapide et joyeux (esprit fandango accéléré)
SONGS["beach_run"] = dict(
    bpm=168, duty=0.25, swing=0.02,
    melody=notes([
        (72, .5), (74, .5), (76, .5), (77, .5), (79, 1), (76, .5), (72, .5),
        (74, .5), (76, .5), (77, .5), (79, .5), (81, 1), (79, 1),
        (77, .5), (79, .5), (81, .5), (82, .5), (84, 1), (81, .5), (77, .5),
        (79, .5), (77, .5), (76, .5), (74, .5), (72, 2),
        (72, .5), (76, .5), (79, .5), (84, .5), (83, 1), (79, .5), (76, .5),
        (77, .5), (81, .5), (84, .5), (86, .5), (84, 1), (81, 1),
        (79, .5), (81, .5), (79, .5), (77, .5), (76, .5), (74, .5), (76, .5), (77, .5),
        (76, .5), (74, .5), (72, .5), (71, .5), (72, 2),
    ]),
    bass=notes([
        (48, 1), (55, 1), (52, 1), (55, 1), (48, 1), (55, 1), (52, 1), (55, 1),
        (53, 1), (57, 1), (53, 1), (57, 1), (48, 1), (55, 1), (48, 1), (55, 1),
        (48, 1), (55, 1), (52, 1), (55, 1), (53, 1), (57, 1), (53, 1), (57, 1),
        (55, 1), (59, 1), (55, 1), (59, 1), (48, 1), (52, 1), (55, 1), (48, 1),
    ]),
    drums=(["kick", "hat", "snare", "hat"], 0.5),
)

# CÔTE DES BASQUES — surf, groove médium ensoleillé
SONGS["surf"] = dict(
    bpm=132, duty=0.125, vibrato=0.012,
    melody=notes([
        (69, 1), (N, .5), (69, .5), (72, 1), (74, 1),
        (76, 1.5), (74, .5), (72, 1), (69, 1),
        (67, 1), (N, .5), (67, .5), (69, 1), (72, 1),
        (74, 2), (N, 1), (72, 1),
        (69, 1), (N, .5), (69, .5), (72, 1), (76, 1),
        (79, 1.5), (76, .5), (74, 1), (72, 1),
        (74, 1), (76, .5), (74, .5), (72, 1), (67, 1),
        (69, 2), (N, 2),
    ]),
    bass=notes([
        (45, 1), (45, 1), (52, 1), (45, 1), (45, 1), (45, 1), (52, 1), (45, 1),
        (43, 1), (43, 1), (50, 1), (43, 1), (38, 1), (38, 1), (45, 1), (38, 1),
        (45, 1), (45, 1), (52, 1), (45, 1), (41, 1), (41, 1), (48, 1), (41, 1),
        (38, 1), (38, 1), (43, 1), (43, 1), (45, 1), (45, 1), (45, 1), (45, 1),
    ]),
    drums=(["kick", "hat", "hat", "snare", "hat", "hat", "kick", "hat"], 0.5),
)

# PORT DES PÊCHEURS — pêche, valse calme
SONGS["fishing"] = dict(
    bpm=96, duty=0.5, vibrato=0.014,
    melody=notes([
        (64, 1), (67, 1), (71, 1), (69, 2), (67, 1),
        (69, 1), (67, 1), (64, 1), (62, 3),
        (60, 1), (64, 1), (67, 1), (66, 2), (64, 1),
        (67, 2), (64, 1), (64, 3),
        (65, 1), (69, 1), (72, 1), (71, 2), (69, 1),
        (71, 1), (69, 1), (67, 1), (64, 3),
        (62, 1), (64, 1), (65, 1), (67, 2), (62, 1),
        (64, 3), (N, 3),
    ]),
    bass=notes([
        (40, 3), (35, 3), (36, 3), (43, 3),
        (36, 3), (38, 3), (43, 3), (40, 3),
        (41, 3), (43, 3), (40, 3), (36, 3),
        (38, 3), (43, 3), (40, 3), (40, 3),
    ]),
    drums=None,
)

# ROCHER — tension, ostinato mineur
SONGS["rock_crossing"] = dict(
    bpm=140, duty=0.25, vibrato=0.0,
    melody=notes([
        (69, .5), (N, .5), (69, .5), (71, .5), (72, 1), (71, .5), (69, .5),
        (68, 1), (N, .5), (68, .5), (69, 1), (N, 1),
        (69, .5), (N, .5), (69, .5), (71, .5), (72, 1), (74, .5), (72, .5),
        (71, 1), (N, .5), (68, .5), (69, 1), (N, 1),
        (72, .5), (N, .5), (72, .5), (74, .5), (76, 1), (74, .5), (72, .5),
        (71, 1), (N, .5), (71, .5), (72, 1), (N, 1),
        (74, .5), (72, .5), (71, .5), (69, .5), (68, 1), (64, 1),
        (69, 1.5), (N, .5), (69, 1), (N, 1),
    ]),
    bass=notes([
        (33, .5), (45, .5), (33, .5), (45, .5), (33, .5), (45, .5), (33, .5), (45, .5),
        (32, .5), (44, .5), (32, .5), (44, .5), (33, .5), (45, .5), (33, .5), (45, .5),
        (33, .5), (45, .5), (33, .5), (45, .5), (33, .5), (45, .5), (33, .5), (45, .5),
        (31, .5), (43, .5), (31, .5), (43, .5), (33, .5), (45, .5), (33, .5), (45, .5),
        (36, .5), (48, .5), (36, .5), (48, .5), (36, .5), (48, .5), (36, .5), (48, .5),
        (31, .5), (43, .5), (31, .5), (43, .5), (33, .5), (45, .5), (33, .5), (45, .5),
        (29, .5), (41, .5), (29, .5), (41, .5), (32, .5), (44, .5), (32, .5), (44, .5),
        (33, .5), (45, .5), (33, .5), (45, .5), (33, .5), (45, .5), (33, .5), (45, .5),
    ]),
    drums=(["kick", None, "hat", None], 0.5),
)

# PORT VIEUX — espadrille, sautillant
SONGS["espadrille"] = dict(
    bpm=152, duty=0.125, swing=0.06,
    melody=notes([
        (67, .5), (N, .5), (67, .5), (69, .5), (71, .5), (N, .5), (71, .5), (72, .5),
        (74, 1), (71, .5), (67, .5), (69, 1), (N, 1),
        (65, .5), (N, .5), (65, .5), (67, .5), (69, .5), (N, .5), (69, .5), (71, .5),
        (72, 1), (69, .5), (65, .5), (67, 1), (N, 1),
        (67, .5), (71, .5), (74, .5), (79, .5), (78, 1), (74, .5), (71, .5),
        (72, .5), (76, .5), (79, .5), (81, .5), (79, 1), (76, 1),
        (74, .5), (76, .5), (74, .5), (72, .5), (71, .5), (69, .5), (67, .5), (65, .5),
        (67, 1), (62, 1), (67, 2),
    ]),
    bass=notes([
        (43, 1), (50, 1), (43, 1), (50, 1), (43, 1), (50, 1), (45, 1), (45, 1),
        (41, 1), (48, 1), (41, 1), (48, 1), (43, 1), (50, 1), (43, 1), (43, 1),
        (43, 1), (50, 1), (47, 1), (50, 1), (48, 1), (52, 1), (48, 1), (48, 1),
        (50, 1), (50, 1), (45, 1), (41, 1), (43, 1), (38, 1), (43, 1), (43, 1),
    ]),
    drums=(["kick", "hat", "snare", "hat"], 0.5),
)

# PHARE — ascension triomphante
SONGS["lighthouse"] = dict(
    bpm=120, duty=0.5, vibrato=0.008,
    melody=notes([
        (60, 1), (64, 1), (67, 1), (72, 1),
        (71, 1.5), (67, .5), (69, 1), (67, 1),
        (65, 1), (69, 1), (72, 1), (77, 1),
        (76, 1.5), (72, .5), (74, 1), (72, 1),
        (67, 1), (71, 1), (74, 1), (79, 1),
        (77, 1.5), (74, .5), (76, 1), (77, 1),
        (79, 1), (77, 1), (76, 1), (74, 1),
        (72, 2), (67, 1), (72, 1),
    ]),
    bass=notes([
        (48, 2), (52, 2), (43, 2), (48, 2),
        (41, 2), (48, 2), (43, 2), (48, 2),
        (43, 2), (47, 2), (50, 2), (43, 2),
        (48, 2), (43, 2), (48, 2), (48, 2),
    ]),
    drums=(["kick", "hat", "hat", "hat"], 0.5),
)


# MENU — Hegoak (Txoria txori), musique de Mikel Laboa, d'après
# l'arrangement de Jo Maris (partition EKE). Usage privé/familial :
# l'œuvre n'est PAS dans le domaine public (cf. DESIGN.md §7).
# Mélodie extraite du MIDI de la collection Maris (3/4, mi mineur).
HEGOAK_MELODY = [
    (64, 4), (71, 1), (69, 1), (71, 4), (69, 1), (67, 1),
    (69, 4), (71, 1), (69, 1), (71, 6),
    (64, 4), (71, 1), (69, 1), (71, 4), (69, 1), (67, 1),
    (69, 4), (71, 1), (69, 1), (64, 4),
    (N, 1), (59, 1), (64, 1), (64, 1), (64, 1), (66, 1),
    (64, 1), (66, 1), (67, 2), (71, 1), (74, 4),
    (N, 1), (71, 1), (69, 1), (69, 1), (69, 2), (71, 1), (69, 1), (71, 4),
    (N, 1), (71, 1), (69, 1), (69, 1), (69, 2), (71, 1), (69, 1), (71, 4),
    (N, 1), (59, 1), (64, 1), (64, 1), (64, 1), (66, 1),
    (64, 1), (66, 1), (67, 2), (71, 1), (74, 4),
    (N, 1), (71, 1), (69, 1), (69, 1), (69, 2), (71, 1), (69, 1), (71, 4),
    (N, 1), (71, 1), (69, 1), (69, 1), (69, 2), (71, 1), (69, 1), (71, 4),
    (N, 2),
]


def hegoak_bass(melody):
    """Basse auto-harmonisée : par mesure (3 temps), la fondamentale la plus
    consonante avec les notes de la mesure (mi min : E, D, G, B, A)."""
    roots = [40, 38, 43, 47, 45]
    beats = []
    for note, d in melody:
        for _ in range(int(d * 2)):
            beats.append(note)
    bass = []
    i = 0
    while i < len(beats):
        bar = [b for b in beats[i:i + 6] if b]
        best, best_score = 40, -1
        for r in roots:
            score = sum(1 for b in bar if (b - r) % 12 in (0, 3, 4, 7))
            if score > best_score:
                best, best_score = r, score
        bass.append((best, 2))
        bass.append((best + 7, 1))
        i += 6
    return bass


SONGS["menu"] = dict(
    bpm=104, duty=0.5, vibrato=0.012, mel_vol=0.32, bass_vol=0.22,
    melody=notes(HEGOAK_MELODY),
    bass=notes(hegoak_bass(HEGOAK_MELODY)),
    drums=None,
)

# ---------------------------------------------------------------- SFX

def sfx_sweep(path, f0, f1, dur, wave="square", vol=0.5, duty=0.5):
    n = int(dur * SR)
    buf = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        phase += f / SR
        s = square(phase, duty) if wave == "square" else triangle(phase)
        buf[i] = s * vol * (1 - t)
    mix_to_wav(path, buf)


def sfx_arp(path, freqs, step=0.06, vol=0.5, wave="square"):
    n = int(step * len(freqs) * SR)
    buf = [0.0] * n
    phase = 0.0
    for i in range(n):
        f = freqs[min(int(i / (step * SR)), len(freqs) - 1)]
        phase += f / SR
        s = square(phase, 0.5) if wave == "square" else triangle(phase)
        env = 1 - (i % int(step * SR)) / (step * SR) * 0.6
        buf[i] = s * vol * env
    mix_to_wav(path, buf)


def sfx_noise(path, dur, f_mod=1.0, vol=0.5, fall=True):
    n = int(dur * SR)
    buf = [0.0] * n
    state = 0x4001
    val = 0.0
    for i in range(n):
        if i % max(int(1 / f_mod), 1) == 0:
            state, val = noise_sample(state)
        env = (1 - i / n) if fall else min(i / (n * 0.1), 1) * (1 - i / n)
        buf[i] = val * vol * env
    mix_to_wav(path, buf)


def main():
    root = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
    music_dir = os.path.join(root, "music")
    sfx_dir = os.path.join(root, "sfx")
    os.makedirs(music_dir, exist_ok=True)
    os.makedirs(sfx_dir, exist_ok=True)
    tmp = tempfile.mkdtemp()

    for name, cfg in SONGS.items():
        wav = os.path.join(tmp, f"{name}.wav")
        song(wav, **cfg)
        mp3 = os.path.join(music_dir, f"{name}.mp3")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                        "-c:a", "libmp3lame", "-q:a", "4", mp3], check=True)
        print("musique :", name)

    A = 440.0
    def hz(semi):
        return A * 2 ** (semi / 12)

    sfx_defs = {}
    sfx_defs["jump"] = lambda p: sfx_sweep(p, hz(0), hz(12), 0.14, vol=0.4, duty=0.25)
    sfx_defs["coin"] = lambda p: sfx_arp(p, [hz(16), hz(21)], 0.06, 0.4)
    sfx_defs["hit"] = lambda p: sfx_noise(p, 0.22, 0.5, 0.5)
    sfx_defs["splash"] = lambda p: sfx_noise(p, 0.35, 0.25, 0.4)
    sfx_defs["bite"] = lambda p: sfx_arp(p, [hz(7), hz(7)], 0.07, 0.45)
    sfx_defs["snap"] = lambda p: sfx_sweep(p, hz(7), hz(-17), 0.3, vol=0.5)
    sfx_defs["landed"] = lambda p: sfx_arp(p, [hz(0), hz(4), hz(7), hz(12)], 0.07, 0.4)
    sfx_defs["trick"] = lambda p: sfx_arp(p, [hz(7), hz(12), hz(16)], 0.045, 0.4)
    sfx_defs["land"] = lambda p: sfx_sweep(p, hz(-5), hz(-10), 0.1, "triangle", 0.5)
    sfx_defs["step"] = lambda p: sfx_sweep(p, hz(5), hz(9), 0.06, vol=0.3, duty=0.25)
    sfx_defs["throw"] = lambda p: sfx_sweep(p, hz(-5), hz(14), 0.18, vol=0.35, duty=0.125)
    sfx_defs["impact"] = lambda p: sfx_noise(p, 0.12, 1.0, 0.5)
    sfx_defs["crossed"] = lambda p: sfx_arp(p, [hz(0), hz(7), hz(12)], 0.06, 0.45)
    sfx_defs["victory"] = lambda p: sfx_arp(p, [hz(0), hz(4), hz(7), hz(12), hz(16), hz(19), hz(24)], 0.09, 0.45)

    for name, fn in sfx_defs.items():
        wav = os.path.join(tmp, f"sfx_{name}.wav")
        fn(wav)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                        "-c:a", "libmp3lame", "-q:a", "4",
                        os.path.join(sfx_dir, f"{name}.mp3")], check=True)
    print("sfx :", ", ".join(sfx_defs))


if __name__ == "__main__":
    main()
