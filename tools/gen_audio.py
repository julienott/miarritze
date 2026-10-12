#!/usr/bin/env python3
"""Bande-son chiptune de Miarritze Borroka (SPEC-BORROKA §12).

Moteur maison : carré (rapport cyclique variable), triangle, bruit LFSR
15 bits façon NES, « steel pan » additif. Synthèse vectorisée (numpy),
export OGG Vorbis via soundfile/libsndfile (ffmpeg n'est pas requis).

Toutes les mélodies sont des COMPOSITIONS ORIGINALES écrites dans des formes
traditionnelles basques du domaine public (fandango, arin-arin, zortziko,
aurresku, kalejira, berceuse) : aucune œuvre à auteur identifié, aucune
partition ni MIDI tiers (voir docs/MUSIC.md). Hegoak est exclu.

Usage : .venv/bin/python tools/gen_audio.py [music|sfx|voice|all] [nom…]
"""
import os
import sys

import numpy as np

try:
    import soundfile as sf
except ImportError:  # pragma: no cover
    sf = None

SR = 32000
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
AUDIO = os.path.join(ROOT, "assets", "audio")
PEAK = 10 ** (-3 / 20)          # normalisation à −3 dBFS crête
MUSIC_QUALITY = 0.55            # niveau de compression libsndfile (≈ 90–100 kbps)
SFX_QUALITY = 0.65

# ================================================================ synthèse

NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    """« G4 », « F#3 », « Bb5 » → numéro MIDI ; « r » → None."""
    if name in ("r", "-", "."):
        return None
    letter = name[0].upper()
    rest = name[1:]
    acc = 0
    while rest and rest[0] in "#b":
        acc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + NOTE_INDEX[letter] + acc


def seq(text):
    """« G4:1 A4:.5 r:1 » → [(midi|None, temps), …] (durée par défaut : 1)."""
    out = []
    for tok in text.replace("|", " ").split():
        if ":" in tok:
            n, d = tok.split(":")
            out.append((midi(n), float(d)))
        else:
            out.append((midi(tok), 1.0))
    return out


def freq(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


_LFSR = None


def lfsr_noise(n, period=1):
    """Bruit LFSR 15 bits (NES) ; `period` = échantillons par pas (grave si grand)."""
    global _LFSR
    if _LFSR is None:
        state, vals = 0x4001, []
        for _ in range(32767):
            bit = (state ^ (state >> 1)) & 1
            state = (state >> 1) | (bit << 14)
            vals.append(1.0 if state & 1 else -1.0)
        _LFSR = np.array(vals, dtype=np.float64)
    idx = (np.arange(n) // max(1, int(period))) % len(_LFSR)
    return _LFSR[idx]


def wave(kind, phase, duty=0.5):
    p = phase % 1.0
    if kind == "square":
        return np.where(p < duty, 0.6, -0.6)
    if kind == "triangle":
        return 4.0 * np.abs(p - 0.5) - 1.0
    if kind == "steel":
        two_pi = 2 * np.pi
        return 0.5 * (np.sin(two_pi * phase) + 0.55 * np.sin(2 * two_pi * phase + 0.3)
                      + 0.22 * np.sin(3.02 * two_pi * phase) + 0.10 * np.sin(4.6 * two_pi * phase))
    if kind == "saw":
        return 2.0 * p - 1.0
    raise ValueError(kind)


def tone(buf, start, dur, m, kind="square", vol=0.3, duty=0.5, vibrato=0.0,
         attack=0.004, release=0.04, decay=0.0, slide=0, vib_rate=5.5, vib_delay=0.12):
    n = int(dur * SR)
    if n <= 0 or start >= len(buf):
        return
    n = min(n, len(buf) - start)
    t = np.arange(n) / SR
    f0, f1 = freq(m), freq(m + slide)
    f = f0 + (f1 - f0) * (t / max(dur, 1e-6))
    if vibrato:
        depth = np.clip((t - vib_delay) / 0.15, 0.0, 1.0) * vibrato
        f = f * (1.0 + depth * np.sin(2 * np.pi * vib_rate * t))
    phase = np.cumsum(f) / SR
    s = wave(kind, phase, duty)
    env = np.ones(n)
    a = min(n, max(1, int(attack * SR)))
    env[:a] = np.linspace(0, 1, a)
    r = min(n, max(1, int(release * SR)))
    env[-r:] *= np.linspace(1, 0, r)
    if decay:
        env *= np.exp(-t * decay)
    if kind == "steel":
        env *= np.exp(-t * 3.2)
    buf[start:start + n] += s * env * vol


def drum(buf, start, kind, vol=0.35):
    if start >= len(buf):
        return
    if kind == "kick":
        n = int(0.11 * SR)
        t = np.arange(n) / SR
        f = 120 * np.exp(-t * 28) + 42
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 22)
    elif kind == "snare":
        n = int(0.12 * SR)
        t = np.arange(n) / SR
        s = (lfsr_noise(n, 1) * 0.7 + np.sin(2 * np.pi * 190 * t) * 0.4) * np.exp(-t * 26)
    elif kind == "hat":
        n = int(0.035 * SR)
        t = np.arange(n) / SR
        s = lfsr_noise(n, 1) * np.exp(-t * 90) * 0.45
    elif kind == "clap":      # palmas du fronton : rafales serrées
        n = int(0.13 * SR)
        t = np.arange(n) / SR
        env = np.exp(-((t * 1000) % 12) / 3.0) * np.exp(-t * 14)
        s = lfsr_noise(n, 1) * env * 0.8
    elif kind == "tom":
        n = int(0.16 * SR)
        t = np.arange(n) / SR
        f = 160 * np.exp(-t * 9) + 70
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 14)
    elif kind == "wood":      # « toc » de bois (txalaparta stylisée)
        n = int(0.06 * SR)
        t = np.arange(n) / SR
        s = (np.sin(2 * np.pi * 880 * t) + 0.5 * np.sin(2 * np.pi * 1320 * t)) * np.exp(-t * 70)
    elif kind == "shaker":
        n = int(0.05 * SR)
        t = np.arange(n) / SR
        s = lfsr_noise(n, 1) * np.sin(np.pi * t / t[-1]) * 0.3
    else:
        raise ValueError(kind)
    n = min(len(s), len(buf) - start)
    buf[start:start + n] += s[:n] * vol


def render_track(buf, notes, bpm, kind="square", vol=0.3, duty=0.5, vibrato=0.0,
                 gate=0.92, swing=0.0, offset_beats=0.0, **kw):
    beat = 60.0 / bpm
    t = offset_beats
    for i, (m, d) in enumerate(notes):
        if m is not None:
            sw = swing if i % 2 == 1 else 0.0
            tone(buf, int((t + sw) * beat * SR), d * beat * gate, m, kind, vol, duty, vibrato, **kw)
        t += d
    return t


def render_drums(buf, pattern, step, bpm, total_beats, vol=0.35, offset=0.0):
    """`pattern` : liste de noms (« kick+snare » possible, None = rien)."""
    beat = 60.0 / bpm
    b = offset
    while b < total_beats - 1e-6:
        for j, k in enumerate(pattern):
            at = b + j * step
            if k and at < total_beats - 1e-6:
                for part in k.split("+"):
                    drum(buf, int(at * beat * SR), part, vol)
        b += len(pattern) * step


SHAPES = {"M": (0, 4, 7, 12), "m": (0, 3, 7, 12), "7": (0, 4, 7, 10), "sus": (0, 5, 7, 12)}


def chord_arp(roots, quality, beats_each, step, pattern=(0, 1, 2, 1)):
    """Arpèges : pour chaque fondamentale, notes de l'accord en valeurs `step`."""
    out = []
    for root, q in zip(roots, quality):
        sh = SHAPES[q]
        k = 0
        t = 0.0
        while t < beats_each - 1e-6:
            out.append((root + sh[pattern[k % len(pattern)]], step))
            t += step
            k += 1
    return out


def bass_line(roots, beats_each, style="root", fifth=7):
    out = []
    for r in roots:
        if style == "root":
            out.append((r, beats_each))
        elif style == "alt":          # fondamentale / quinte
            half = beats_each / 2
            out += [(r, half), (r + fifth, half)]
        elif style == "waltz":        # 3/4 : basse + 2 temps légers
            third = beats_each / 3
            out += [(r, third), (r + 12, third), (r + fifth + 12, third)]
        elif style == "octave":
            q = beats_each / 4
            out += [(r, q), (r + 12, q), (r, q), (r + 12, q)]
    return out


def normalize(buf, peak=PEAK):
    m = float(np.max(np.abs(buf))) if len(buf) else 0.0
    if m > 1e-6:
        buf = buf * (peak / m)
    return np.clip(buf, -1.0, 1.0).astype(np.float32)


def write_ogg(path, buf, quality, peak=PEAK):
    """Encode en OGG Vorbis ; vérifie la crête APRÈS décodage (Vorbis peut
    dépasser sur le bruit large bande) et ré-encode plus bas si besoin."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if sf is None:
        raise SystemExit("soundfile manquant : .venv/bin/pip install soundfile")
    target = peak
    for _ in range(6):
        sf.write(path, normalize(buf, target), SR, format="OGG", subtype="VORBIS", compression_level=quality)
        decoded, _sr = sf.read(path)
        real = float(np.max(np.abs(decoded)))
        if real <= PEAK * 1.06:
            return
        target *= PEAK / real


def blank(beats, bpm, tail=0.0):
    return np.zeros(int(beats * 60.0 / bpm * SR + tail * SR), dtype=np.float64)


def loop_fix(buf, beats, bpm):
    """Boucle exacte : coupe à la mesure et replie la queue des notes au
    début, pour une reprise sans clic ni trou."""
    n = int(beats * 60.0 / bpm * SR)
    tail = buf[n:]
    out = buf[:n].copy()
    k = min(len(tail), n)
    out[:k] += tail[:k]
    return out


MAJOR = (0, 2, 4, 5, 7, 9, 11)


def third_below(notes, tonic):
    """Harmonie à la tierce inférieure DIATONIQUE (reste dans la tonalité)."""
    scale = {(tonic + d) % 12 for d in MAJOR}
    out = []
    for m, d in notes:
        if m is None:
            out.append((None, d))
            continue
        h = m - 3 if (m - 3) % 12 in scale else m - 4
        out.append((h, d))
    return out


def lead_beats(lead):
    return sum(d for _, d in lead)

# ================================================================ morceaux
# Phrases de 8 mesures combinées en A B A (B) pour 45–80 s de boucle.


def song_title():
    """Titre : marche d'honneur (forme ezpata-dantza / aurresku), sol majeur."""
    bpm = 104
    a = seq("D4:1 G4:1 G4:.5 A4:.5 B4:1 | A4:1 G4:.5 A4:.5 B4:1 D5:1 | C5:1 B4:.5 A4:.5 B4:1 G4:1 | A4:3 r:1 |"
            "D4:1 G4:1 G4:.5 A4:.5 B4:1 | A4:1 G4:.5 A4:.5 B4:1 D5:1 | E5:1 D5:.5 C5:.5 B4:1 A4:1 | G4:3 r:1")
    b = seq("B4:1 D5:1 D5:.5 E5:.5 D5:1 | C5:1 E5:1 E5:.5 D5:.5 C5:1 | B4:1 D5:1 G5:1 F#5:.5 E5:.5 | D5:3 r:1 |"
            "E5:1 C5:1 C5:.5 B4:.5 A4:1 | D5:1 B4:1 B4:.5 A4:.5 G4:1 | A4:1 B4:.5 C5:.5 B4:1 A4:1 | G4:4")
    ra = [55, 50, 48, 50, 55, 50, 48, 55]
    rb = [55, 48, 55, 50, 48, 55, 50, 55]
    lead = a + b + a
    roots = ra + rb + ra
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.26, duty=0.5, vibrato=0.008)
    render_track(buf, [(m - 12 if m else None, d) for m, d in lead], bpm, "steel", 0.10)
    render_track(buf, bass_line([r - 12 for r in roots], 4, "alt"), bpm, "triangle", 0.30)
    render_track(buf, chord_arp(roots, ["M"] * len(roots), 4, 0.5), bpm, "square", 0.06, duty=0.125, gate=0.5)
    render_drums(buf, ["kick", "hat", "snare", "hat"] * 2, 0.5, bpm, beats, 0.30)
    return loop_fix(buf, beats, bpm)


def song_select():
    """Sélection : petit fandango vif (3/4) en ré majeur, sautillant."""
    bpm = 168
    a = seq("A4:.5 B4:.5 C#5:1 A4:1 | D5:1 C#5:.5 B4:.5 A4:1 | B4:.5 C#5:.5 D5:1 B4:1 | A4:2 r:1 |"
            "F#4:.5 G4:.5 A4:1 F#4:1 | B4:1 A4:.5 G4:.5 F#4:1 | G4:.5 F#4:.5 E4:1 C#4:1 | D4:2 r:1")
    b = seq("D5:1 E5:.5 F#5:.5 E5:1 | D5:1 C#5:.5 B4:.5 C#5:1 | B4:1 C#5:.5 D5:.5 C#5:1 | A4:2 r:1 |"
            "G4:1 A4:.5 B4:.5 A4:1 | F#4:1 E4:.5 F#4:.5 G4:1 | E4:1 F#4:.5 G4:.5 E4:1 | D4:2 r:1")
    lead = a + b + a + b + a
    roots = ([50, 50, 43, 45, 50, 47, 45, 50] + [50, 45, 43, 45, 43, 50, 45, 50]) * 2 + [50, 50, 43, 45, 50, 47, 45, 50]
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.24, duty=0.25, vibrato=0.006)
    render_track(buf, bass_line([r - 12 for r in roots], 3, "waltz"), bpm, "triangle", 0.28)
    render_drums(buf, ["kick", "hat", "hat"], 1.0, bpm, beats, 0.26)
    render_drums(buf, [None, "shaker", "shaker"], 1.0, bpm, beats, 0.2)
    return loop_fix(buf, beats, bpm)


def song_tower():
    """Pyramide : marche d'aurresku (danse d'honneur), la mineur → do majeur."""
    bpm = 116
    a = seq("A4:1 E5:1 D5:.5 C5:.5 B4:1 | C5:1 A4:1 B4:.5 G4:.5 A4:1 | E5:1 G5:1 F5:.5 E5:.5 D5:1 | E5:3 r:1 |"
            "A4:1 E5:1 D5:.5 C5:.5 B4:1 | C5:1 E5:1 D5:.5 C5:.5 B4:1 | A4:1 C5:.5 B4:.5 A4:1 G#4:1 | A4:3 r:1")
    b = seq("C5:1 E5:1 G5:1 E5:1 | F5:1 E5:.5 D5:.5 C5:1 A4:1 | D5:1 F5:1 A5:1 F5:1 | G5:3 r:1 |"
            "E5:1 G5:.5 F5:.5 E5:1 C5:1 | D5:1 F5:.5 E5:.5 D5:1 B4:1 | C5:1 B4:.5 A4:.5 B4:1 G#4:1 | A4:4")
    lead = a + b + a
    roots = [45, 45, 52, 52, 45, 45, 50, 45, 48, 41, 50, 43, 48, 43, 52, 45, 45, 45, 52, 52, 45, 45, 50, 45]
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.24, duty=0.5, vibrato=0.01)
    render_track(buf, bass_line([r - 12 for r in roots], 4, "alt"), bpm, "triangle", 0.30)
    render_drums(buf, ["kick+snare", "hat", "snare", "hat", "kick", "hat", "snare", "snare"], 0.5, bpm, beats, 0.28)
    return loop_fix(buf, beats, bpm)


def fight_song(key_root, bpm, lead_a, lead_b, prog_a, prog_b, drums, step,
               duty=0.25, arp_duty=0.125, bass_style="octave", swing=0.0, minor=False):
    """Gabarit des thèmes de stage : A B A B, arpèges + basse + batterie."""
    lead = lead_a + lead_b + lead_a + lead_b
    prog = prog_a + prog_b + prog_a + prog_b
    roots = [key_root + i for i in prog]
    quals = ["m" if minor and i % 12 in (0, 5, 7) else "M" for i in prog]
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.24, duty=duty, vibrato=0.007, swing=swing)
    render_track(buf, bass_line([r - 12 for r in roots], 4, bass_style), bpm, "triangle", 0.30)
    render_track(buf, chord_arp(roots, quals, 4, 0.25 if bpm < 140 else 0.5), bpm, "square", 0.055,
                 duty=arp_duty, gate=0.6)
    render_drums(buf, drums, step, bpm, beats, 0.30)
    return loop_fix(buf, beats, bpm)


def song_grande_plage():
    """Grande Plage : arin-arin (danse vive en 2/4) en do majeur, plein soleil."""
    a = seq("G4:.5 C5:.5 E5:.5 C5:.5 G5:1 E5:1 | F5:.5 E5:.5 D5:.5 C5:.5 D5:1 G4:1 | A4:.5 B4:.5 C5:.5 D5:.5 E5:.5 F5:.5 G5:1 | "
            "E5:.5 D5:.5 C5:1 C5:2 | G4:.5 C5:.5 E5:.5 C5:.5 G5:1 E5:1 | A5:.5 G5:.5 F5:.5 E5:.5 D5:1 B4:1 | "
            "C5:.5 E5:.5 D5:.5 B4:.5 G4:.5 A4:.5 B4:1 | C5:2 r:2")
    b = seq("E5:1 E5:.5 F5:.5 G5:1 G5:1 | A5:.5 G5:.5 F5:.5 E5:.5 F5:2 | D5:1 D5:.5 E5:.5 F5:1 F5:1 | G5:.5 F5:.5 E5:.5 D5:.5 E5:2 |"
            "C5:1 C5:.5 D5:.5 E5:1 C5:1 | F5:.5 E5:.5 D5:.5 C5:.5 A4:2 | B4:.5 C5:.5 D5:.5 E5:.5 F5:.5 E5:.5 D5:1 | G5:2 r:2")
    return fight_song(48, 152, a, b, [0, 7, 9, 0, 0, 5, 7, 0], [0, 5, 2, 0, 0, 5, 7, 7],
                      ["kick", "hat", "snare", "hat", "kick", "kick", "snare", "hat"], 0.5)


def song_cote_basques():
    """Côte des Basques : fandango « surf » en la mixolydien, 6/8 balancé, ressac."""
    bpm = 132
    a = seq("E5:1.5 D5:.5 C#5:.5 B4:.5 | A4:1.5 E4:1.5 | F#4:.5 G4:.5 A4:.5 B4:1 C#5:.5 | D5:3 |"
            "E5:1.5 D5:.5 C#5:.5 B4:.5 | A4:1.5 C#5:1.5 | B4:.5 A4:.5 G4:.5 F#4:1 G4:.5 | A4:3")
    b = seq("A5:1 G5:.5 F#5:1 E5:.5 | D5:1.5 B4:1.5 | G5:1 F#5:.5 E5:1 D5:.5 | C#5:3 |"
            "D5:1 E5:.5 F#5:1 G5:.5 | A5:1.5 E5:1.5 | F#5:.5 E5:.5 D5:.5 C#5:1 B4:.5 | A4:3")
    lead = a + b + a + b
    roots = [57, 57, 55, 50, 57, 57, 55, 57, 50, 55, 55, 57, 50, 57, 52, 57] * 2
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.24, duty=0.125, vibrato=0.012)
    render_track(buf, [(r - 24, 1.5) for r in roots for _ in range(2)], bpm, "triangle", 0.30)
    render_track(buf, chord_arp(roots, ["M"] * len(roots), 3, 0.5, (0, 1, 2, 3, 2, 1)), bpm, "square", 0.05,
                 duty=0.25, gate=0.5)
    render_drums(buf, ["kick", "hat", "hat", "snare", "hat", "shaker"], 0.5, bpm, beats, 0.28)
    beat = 60.0 / bpm
    for k in range(int(beats // 6)):          # vagues : souffle grave toutes les 2 mesures
        start = int(k * 6 * beat * SR)
        n = int(2.5 * beat * SR)
        t = np.arange(n) / n
        if start + n < len(buf):
            buf[start:start + n] += lfsr_noise(n, 6) * np.sin(np.pi * t) * 0.05
    return loop_fix(buf, beats, bpm)


def song_port_pecheurs():
    """Port des Pêcheurs : chant de rameurs (forme arraun-kanta), valse calme
    en mi mineur, cloche du port."""
    bpm = 92
    a = seq("E4:1 G4:1 B4:1 | A4:2 G4:1 | F#4:1 A4:1 B4:1 | G4:2 E4:1 | D4:1 F#4:1 A4:1 | G4:1.5 F#4:.5 E4:1 | "
            "F#4:1 G4:1 A4:1 | B4:3")
    b = seq("B4:1 C5:1 D5:1 | E5:2 D5:1 | C5:1 B4:1 A4:1 | B4:2 G4:1 | A4:1 B4:1 C5:1 | B4:1.5 A4:.5 G4:1 | "
            "F#4:1 E4:1 D#4:1 | E4:3")
    lead = a + b + a + b
    roots = [40, 45, 47, 40, 38, 40, 42, 47, 43, 40, 45, 43, 45, 40, 47, 40] * 2
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.5)
    render_track(buf, lead, bpm, "triangle", 0.30, vibrato=0.012, release=0.2)
    render_track(buf, lead, bpm, "square", 0.07, duty=0.5, vibrato=0.012)
    render_track(buf, bass_line([r - 12 for r in roots], 3, "waltz"), bpm, "triangle", 0.22)
    render_track(buf, [(r + 24, 12) for r in roots[::4]], bpm, "steel", 0.12)   # cloche du port
    return loop_fix(buf, beats, bpm)


def song_rocher_vierge():
    """Rocher de la Vierge : zortziko (5/8, 2+3), ré mineur, embruns tendus.
    Unité de temps = la croche (bpm en croches)."""
    bpm = 300
    a = seq("D5:2 F5:1 E5:1 D5:1 | C5:2 A4:3 | Bb4:2 C5:1 D5:1 E5:1 | F5:2 E5:3 |"
            "D5:2 F5:1 E5:1 D5:1 | C5:2 E5:1 F5:1 G5:1 | A5:2 G5:1 F5:1 E5:1 | D5:5")
    b = seq("A5:2 G5:1 F5:1 E5:1 | F5:2 D5:3 | G5:2 F5:1 E5:1 D5:1 | E5:2 C#5:3 |"
            "D5:2 E5:1 F5:1 G5:1 | A5:2 F5:3 | E5:2 D5:1 C#5:1 E5:1 | D5:5")
    lead = (a + b) * 3
    roots = [50, 45, 46, 45, 50, 48, 45, 50, 45, 50, 43, 45, 50, 41, 45, 50] * 3
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.24, duty=0.25, vibrato=0.006)
    bass = []
    for r in roots:
        bass += [(r - 24, 2), (r - 17, 1), (r - 24, 1), (r - 12, 1)]
    render_track(buf, bass, bpm, "triangle", 0.30)
    render_drums(buf, ["kick", "hat", "snare", "hat", "hat"], 1.0, bpm, beats, 0.30)
    return loop_fix(buf, beats, bpm)


def song_port_vieux():
    """Port Vieux : kalejira (défilé festif de rue) en fa majeur, balancé."""
    a = seq("C5:.5 F5:.5 A5:.5 F5:.5 C5:1 A4:1 | Bb4:.5 D5:.5 F5:.5 D5:.5 C5:2 | A4:.5 C5:.5 F5:.5 E5:.5 D5:.5 C5:.5 Bb4:1 | "
            "A4:1 G4:1 F4:2 | C5:.5 F5:.5 A5:.5 F5:.5 C6:1 A5:1 | Bb5:.5 A5:.5 G5:.5 F5:.5 G5:2 | "
            "A5:.5 G5:.5 F5:.5 E5:.5 D5:.5 E5:.5 F5:.5 G5:.5 | F5:2 r:2")
    b = seq("D5:1 D5:.5 E5:.5 F5:1 D5:1 | C5:1 C5:.5 D5:.5 E5:1 C5:1 | Bb4:1 Bb4:.5 C5:.5 D5:1 Bb4:1 | A4:2 C5:2 |"
            "D5:1 E5:.5 F5:.5 G5:1 E5:1 | F5:1 G5:.5 A5:.5 Bb5:1 G5:1 | A5:.5 Bb5:.5 A5:.5 G5:.5 F5:1 E5:1 | F5:4")
    return fight_song(53, 144, a, b, [0, 5, 0, 7, 0, 5, 7, 0], [2, 0, 5, 0, 2, 5, 7, 0],
                      ["kick", "hat", "snare", "hat"], 0.5, duty=0.5, swing=0.04)


def song_halles():
    """Les Halles : arin-arin de marché, sol majeur, accordéon simulé (deux carrés en tierce)."""
    bpm = 160
    a = seq("D5:.5 B4:.5 D5:.5 G5:.5 F#5:.5 E5:.5 D5:1 | C5:.5 A4:.5 C5:.5 E5:.5 D5:.5 C5:.5 B4:1 | "
            "A4:.5 B4:.5 C5:.5 D5:.5 E5:.5 F#5:.5 G5:.5 E5:.5 | D5:2 r:2 |"
            "D5:.5 B4:.5 D5:.5 G5:.5 F#5:.5 E5:.5 D5:1 | E5:.5 C5:.5 E5:.5 A5:.5 G5:.5 F#5:.5 E5:1 | "
            "D5:.5 C5:.5 B4:.5 A4:.5 B4:.5 C5:.5 A4:1 | G4:2 r:2")
    b = seq("B4:1 G4:1 B4:1 D5:1 | C5:1 A4:1 C5:1 E5:1 | D5:1 B4:1 G5:1 F#5:1 | E5:2 D5:2 |"
            "B4:1 G4:1 B4:1 D5:1 | C5:1 E5:1 G5:1 E5:1 | D5:1 F#4:1 A4:1 C5:1 | B4:2 G4:2")
    lead = a + b + a + b
    roots = [55, 48, 50, 55, 55, 48, 50, 55, 55, 48, 55, 48, 55, 48, 50, 55] * 2
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.20, duty=0.25, vibrato=0.01)
    render_track(buf, third_below(lead, 7), bpm, "square", 0.09, duty=0.5, vibrato=0.01)
    render_track(buf, bass_line([r - 12 for r in roots], 4, "alt"), bpm, "triangle", 0.30)
    render_drums(buf, ["kick", "hat", "snare", "hat", "kick", "hat", "snare", "wood"], 0.5, bpm, beats, 0.28)
    return loop_fix(buf, beats, bpm)


def song_fronton():
    """Fronton : fandango à palmas, mi mineur, claquements de pelote."""
    bpm = 150
    a = seq("E5:1 B4:.5 E5:.5 G5:1 | F#5:.5 E5:.5 D#5:1 B4:1 | C5:1 A4:.5 C5:.5 E5:1 | D#5:2 B4:1 |"
            "E5:1 B4:.5 E5:.5 G5:1 | A5:.5 G5:.5 F#5:1 E5:1 | F#5:.5 E5:.5 D#5:.5 C#5:.5 D#5:1 | E5:3")
    b = seq("G5:1 F#5:.5 E5:.5 D5:1 | E5:1 D5:.5 C5:.5 B4:1 | C5:1 B4:.5 A4:.5 G4:1 | F#4:2 B4:1 |"
            "E5:1 F#5:.5 G5:.5 A5:1 | B5:1 A5:.5 G5:.5 F#5:1 | G5:.5 F#5:.5 E5:.5 D#5:.5 F#5:1 | E5:3")
    lead = (a + b) * 2 + a
    roots = [52, 47, 45, 47, 52, 45, 47, 52, 55, 52, 48, 47, 52, 47, 47, 52] * 2 + [52, 47, 45, 47, 52, 45, 47, 52]
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.24, duty=0.25, vibrato=0.008)
    render_track(buf, bass_line([r - 12 for r in roots], 3, "waltz"), bpm, "triangle", 0.28)
    render_drums(buf, ["kick", "clap", "clap"], 1.0, bpm, beats, 0.28)
    render_drums(buf, [None, "wood", None, None, "wood", None], 0.5, bpm, beats, 0.22)
    return loop_fix(buf, beats, bpm)


def song_stade():
    """Stade : marche festive de tribune, si bémol majeur, tambours, énergique."""
    a = seq("F4:.5 Bb4:.5 D5:.5 F5:.5 F5:1 D5:1 | Eb5:.5 D5:.5 C5:.5 Bb4:.5 C5:2 | G4:.5 C5:.5 Eb5:.5 G5:.5 G5:1 Eb5:1 | "
            "F5:.5 Eb5:.5 D5:.5 C5:.5 D5:2 | F4:.5 Bb4:.5 D5:.5 F5:.5 Bb5:1 F5:1 | G5:.5 F5:.5 Eb5:.5 D5:.5 Eb5:1 C5:1 | "
            "D5:.5 C5:.5 Bb4:.5 A4:.5 C5:1 A4:1 | Bb4:2 r:2")
    b = seq("D5:1 D5:1 D5:.5 Eb5:.5 F5:1 | Eb5:1 Eb5:1 Eb5:.5 F5:.5 G5:1 | F5:1 F5:1 F5:.5 G5:.5 A5:1 | Bb5:2 F5:2 |"
            "G5:1 Eb5:1 C5:1 Eb5:1 | F5:1 D5:1 Bb4:1 D5:1 | Eb5:.5 D5:.5 C5:.5 Bb4:.5 A4:1 C5:1 | Bb4:4")
    return fight_song(46, 156, a, b, [0, 5, 2, 7, 0, 5, 7, 0], [0, 5, 7, 0, 5, 0, 7, 0],
                      ["kick+snare", "hat", "kick", "hat", "kick+snare", "tom", "tom", "snare"], 0.5, duty=0.5)


def song_aquarium():
    """Aquarium : nappe aquatique, ré majeur 6/8, steel pan et bulles."""
    bpm = 108
    a = seq("A4:1.5 F#5:1.5 | E5:1 D5:.5 C#5:1.5 | B4:1.5 G5:1.5 | F#5:3 | A4:1.5 F#5:1.5 | G5:1 F#5:.5 E5:1.5 | "
            "D5:1 E5:.5 F#5:1 C#5:.5 | D5:3")
    b = seq("B5:1.5 A5:1.5 | G5:1 F#5:.5 E5:1.5 | A5:1.5 G5:1.5 | F#5:1 E5:.5 D5:1.5 | G5:1.5 F#5:1.5 | "
            "E5:1 D5:.5 C#5:1.5 | B4:1 C#5:.5 D5:1 E5:.5 | D5:3")
    lead = a + b + a + b
    roots = [50, 45, 43, 50, 50, 43, 45, 50, 47, 43, 45, 50, 43, 45, 43, 50] * 2
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.5)
    render_track(buf, lead, bpm, "steel", 0.32)
    render_track(buf, lead, bpm, "triangle", 0.10, vibrato=0.015)
    render_track(buf, chord_arp(roots, ["M"] * len(roots), 3, 0.25, (0, 1, 2, 3, 2, 1)), bpm, "square",
                 0.045, duty=0.125, gate=0.4)
    render_track(buf, [(r - 12, 3) for r in roots], bpm, "triangle", 0.26)
    render_drums(buf, ["kick", None, "shaker", None, "shaker", None], 0.5, bpm, beats, 0.22)
    return loop_fix(buf, beats, bpm)


def song_phare_sommet():
    """Sommet du Phare (boss) : aurresku nocturne, ré mineur harmonique, martial."""
    bpm = 126
    a = seq("D4:1 A4:1 F4:.5 A4:.5 D5:1 | C#5:1 A4:1 E5:2 | D5:1 F5:1 E5:.5 D5:.5 C#5:1 | D5:3 r:1 |"
            "Bb4:1 D5:1 A4:.5 D5:.5 F5:1 | E5:1 C#5:1 A4:2 | G4:1 Bb4:1 A4:.5 G4:.5 F4:1 | E4:3 r:1")
    b = seq("A5:1 G5:.5 F5:.5 E5:1 D5:1 | C#5:1 E5:1 A4:2 | Bb5:1 A5:.5 G5:.5 F5:1 E5:1 | F5:2 E5:2 |"
            "D5:1 F5:1 A5:1 F5:1 | G5:1 E5:1 C#5:1 A4:1 | D5:1 C#5:.5 B4:.5 C#5:1 A4:1 | D5:4")
    lead = a + b + a
    roots = [38, 45, 38, 38, 46, 45, 43, 45, 41, 45, 46, 45, 38, 45, 45, 38, 38, 45, 38, 38, 46, 45, 43, 45]
    quals = ["m" if (r % 12) in (2, 7, 5) else "M" for r in roots]
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.24, duty=0.5, vibrato=0.012)
    render_track(buf, [(m - 12 if m else None, d) for m, d in lead], bpm, "saw", 0.05)
    render_track(buf, bass_line([r - 12 for r in roots], 4, "octave"), bpm, "triangle", 0.32)
    render_track(buf, chord_arp(roots, quals, 4, 0.25, (3, 2, 1, 0)), bpm, "square", 0.05, duty=0.125, gate=0.5)
    render_drums(buf, ["kick+snare", "hat", "hat", "snare", "kick", "hat", "tom", "tom"], 0.5, bpm, beats, 0.30)
    return loop_fix(buf, beats, bpm)


def song_victory():
    """Victoire : jingle court (non bouclé), arpège montant + accord tenu."""
    bpm = 150
    buf = blank(6, bpm, 1.0)
    render_track(buf, seq("C5:.5 E5:.5 G5:.5 C6:.5 B5:.5 C6:.5 D6:.5 E6:2.5"), bpm, "square", 0.28, duty=0.25, gate=0.95)
    render_track(buf, seq("C3:1 G2:1 C3:4"), bpm, "triangle", 0.30)
    render_track(buf, seq("r:3.5 E5:2.5"), bpm, "square", 0.12, duty=0.5, vibrato=0.01)
    render_track(buf, seq("r:3.5 G5:2.5"), bpm, "steel", 0.15)
    render_drums(buf, ["kick", "hat", "snare", "hat", "kick+snare"], 0.5, bpm, 2.5, 0.3)
    return fade_out(buf, 0.05)


def song_txapeldun():
    """TXAPELDUN ! : fanfare de remise de la txapela (non bouclée), sol majeur."""
    bpm = 120
    lead = seq("D5:.5 D5:.5 D5:.5 G5:1.5 r:.5 | B4:.5 B4:.5 B4:.5 E5:1.5 r:.5 | "
               "C5:.5 D5:.5 E5:.5 F#5:.5 G5:.5 A5:.5 | B5:4 r:1")
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 1.0)
    render_track(buf, lead, bpm, "square", 0.28, duty=0.5, vibrato=0.01)
    render_track(buf, third_below(lead, 7), bpm, "square", 0.12, duty=0.25)
    render_track(buf, seq("G2:3.5 E2:3.5 C2:1.5 D2:1.5 G2:5"), bpm, "triangle", 0.32)
    render_drums(buf, ["snare", "snare", "snare", "kick+snare", None, None, None], 0.5, bpm, 7, 0.3)
    render_drums(buf, ["kick+snare", "snare", "kick+snare", "snare"], 0.5, bpm, beats - 1, 0.28, offset=7)
    return fade_out(buf, 0.05)


def song_ending():
    """Fins illustrées : berceuse (forme lo-lo, bercement 6/8), fa majeur,
    txistu simulé (triangle + vibrato), très doux."""
    bpm = 84
    a = seq("C5:1.5 A4:1.5 | Bb4:1 A4:.5 G4:1.5 | A4:1 Bb4:.5 C5:1 D5:.5 | C5:3 | F5:1.5 E5:1 D5:.5 | "
            "C5:1 Bb4:.5 A4:1.5 | G4:1 A4:.5 Bb4:1 G4:.5 | F4:3")
    b = seq("A4:1 C5:.5 F5:1.5 | E5:1 D5:.5 C5:1.5 | D5:1 C5:.5 Bb4:1.5 | A4:3 | Bb4:1 D5:.5 G5:1.5 | "
            "F5:1 E5:.5 D5:1.5 | C5:1 A4:.5 Bb4:1 G4:.5 | F4:3")
    lead = a + b + a
    roots = [41, 46, 41, 48, 46, 41, 36, 41, 41, 48, 46, 41, 43, 46, 48, 41, 41, 46, 41, 48, 46, 41, 36, 41]
    beats = lead_beats(lead)
    buf = blank(beats, bpm, 2.0)
    render_track(buf, lead, bpm, "triangle", 0.34, vibrato=0.018, vib_rate=5.0, release=0.15, attack=0.03)
    render_track(buf, [(r - 12, 1.5) for r in roots for _ in range(2)], bpm, "triangle", 0.16, release=0.3)
    render_track(buf, chord_arp(roots, ["M"] * len(roots), 3, 0.5, (0, 1, 2)), bpm, "steel", 0.08)
    return loop_fix(buf, beats, bpm)


MUSIC = {
    "title": song_title, "select": song_select, "tower": song_tower,
    "grande_plage": song_grande_plage, "cote_basques": song_cote_basques,
    "port_pecheurs": song_port_pecheurs, "rocher_vierge": song_rocher_vierge,
    "port_vieux": song_port_vieux, "halles": song_halles, "fronton": song_fronton,
    "stade": song_stade, "aquarium": song_aquarium, "phare_sommet": song_phare_sommet,
    "victory": song_victory, "txapeldun": song_txapeldun, "ending": song_ending,
}

# ================================================================ SFX


def env_exp(n, k):
    return np.exp(-np.arange(n) / SR * k)


def sweep(f0, f1, dur, kind="square", vol=0.6, duty=0.5, curve=1.0):
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    f = f0 + (f1 - f0) * t ** curve
    return wave(kind, np.cumsum(f) / SR, duty) * (1 - t) * vol


def noise_burst(dur, period=1, decay=20.0, vol=0.6):
    n = int(dur * SR)
    return lfsr_noise(n, period) * env_exp(n, decay) * vol


def arp(freqs, step=0.06, kind="square", vol=0.5, duty=0.5):
    out = []
    for f in freqs:
        n = int(step * SR)
        t = np.arange(n) / SR
        out.append(wave(kind, f * t, duty) * (1 - 0.6 * t / step) * vol)
    return np.concatenate(out)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def hz(semi, base=440.0):
    return base * 2 ** (semi / 12)


def fade_out(buf, dur=0.01, fade_in=0.002):
    """Fondu de sortie (et d'entrée de 2 ms) : aucun clic au début ni à la fin."""
    buf = buf.copy()
    n = min(len(buf), int(dur * SR))
    buf[-n:] *= np.linspace(1, 0, n)
    m = min(len(buf), int(fade_in * SR))
    buf[:m] *= np.linspace(0, 1, m)
    return buf


def make_sfx():
    s = {}
    s["hit_light"] = mix(noise_burst(0.09, 1, 40, 0.6), sweep(900, 300, 0.06, "square", 0.3, 0.25))
    s["hit_heavy"] = mix(noise_burst(0.16, 2, 22, 0.7), sweep(400, 90, 0.14, "square", 0.4, 0.5))
    s["hit_uppercut"] = mix(noise_burst(0.25, 2, 14, 0.7), sweep(260, 1400, 0.22, "square", 0.35, 0.25, 0.7),
                            sweep(160, 50, 0.25, "triangle", 0.6))
    s["hit_super"] = mix(noise_burst(0.4, 3, 8, 0.7), sweep(220, 40, 0.4, "square", 0.45),
                         arp([hz(12), hz(16), hz(19)], 0.05, vol=0.25))
    n = int(0.07 * SR)
    t = np.arange(n) / SR
    s["block"] = (np.sin(2 * np.pi * 700 * t) + 0.6 * np.sin(2 * np.pi * 1050 * t)) * np.exp(-t * 60) * 0.7
    nwh = int(0.12 * SR)
    s["whiff"] = noise_burst(0.12, 1, 18, 0.25) * np.linspace(0.2, 1, nwh) ** 2
    s["jump"] = sweep(hz(-5), hz(7), 0.13, "square", 0.4, 0.25)
    s["land"] = mix(noise_burst(0.06, 4, 40, 0.4), sweep(200, 80, 0.06, "triangle", 0.5))
    s["throw"] = mix(sweep(hz(-12), hz(5), 0.18, "square", 0.35, 0.125), noise_burst(0.18, 3, 10, 0.3))
    s["tech"] = arp([hz(7), hz(14)], 0.05, vol=0.4, duty=0.25)
    s["plouf"] = mix(sweep(600, 120, 0.3, "triangle", 0.6, curve=0.5), noise_burst(0.6, 2, 6, 0.45))
    nw = int(1.0 * SR)
    s["wave"] = lfsr_noise(nw, 5) * np.sin(np.pi * np.linspace(0, 1, nw)) * 0.6
    s["super"] = mix(sweep(hz(-12), hz(24), 0.5, "square", 0.35, 0.5, 0.6),
                     arp([hz(0), hz(4), hz(7), hz(12), hz(16), hz(19)], 0.06, vol=0.25))
    s["special"] = sweep(hz(0), hz(12), 0.16, "square", 0.4, 0.125)
    s["projectile"] = mix(sweep(hz(5), hz(-7), 0.2, "square", 0.3, 0.25), noise_burst(0.2, 1, 10, 0.12))
    s["ko"] = mix(sweep(hz(0), hz(-24), 0.6, "square", 0.45, 0.5), noise_burst(0.6, 6, 5, 0.3))
    s["perfect"] = arp([hz(12), hz(16), hz(19), hz(24), hz(19), hz(24)], 0.07, vol=0.4, duty=0.25)
    s["round"] = mix(arp([hz(0), hz(7)], 0.12, vol=0.4), sweep(hz(-12), hz(-12), 0.24, "triangle", 0.4))
    n = int(0.03 * SR)
    s["timer_tick"] = np.sin(2 * np.pi * 1600 * np.arange(n) / SR) * np.exp(-np.arange(n) / SR * 120) * 0.5
    s["ui_ok"] = arp([hz(7), hz(12)], 0.05, vol=0.4, duty=0.25)
    s["ui_move"] = arp([hz(12)], 0.03, vol=0.25, duty=0.125)
    s["ui_no"] = arp([hz(-2), hz(-6)], 0.07, vol=0.35, duty=0.5)
    nw = int(0.5 * SR)
    tw = np.arange(nw) / SR
    trill = 2900 + 300 * np.sign(np.sin(2 * np.pi * 28 * tw))
    s["whistle"] = wave("square", np.cumsum(trill) / SR, 0.5) * np.minimum(1, (0.5 - tw) * 8) * 0.35
    s["pelota"] = mix(noise_burst(0.05, 1, 80, 0.7), sweep(1200, 600, 0.04, "triangle", 0.6))
    ng = int(0.45 * SR)
    tg = np.linspace(0, 1, ng)
    fg = 1300 + 500 * np.sin(np.pi * tg) - 600 * tg
    s["gull"] = wave("square", np.cumsum(fg) / SR, 0.25) * np.sin(np.pi * tg) * 0.3
    s["pinch"] = mix(noise_burst(0.03, 1, 100, 0.6), arp([hz(19), hz(24)], 0.03, vol=0.3, duty=0.125))
    nf = int(0.5 * SR)
    s["fire"] = lfsr_noise(nf, 3) * np.sin(np.pi * np.linspace(0, 1, nf)) * 0.5
    nc = int(1.5 * SR)
    crowd = np.zeros(nc)
    rng = np.random.default_rng(7)
    for _ in range(40):
        st = int(rng.uniform(0, 1.2) * SR)
        crowd[st:st + int(0.06 * SR)] += lfsr_noise(int(0.06 * SR), 1) * rng.uniform(0.1, 0.3)
    s["crowd"] = crowd * np.sin(np.pi * np.linspace(0, 1, nc)) + lfsr_noise(nc, 8) * 0.08 * np.sin(np.pi * np.linspace(0, 1, nc))
    s["splash"] = mix(noise_burst(0.35, 1, 9, 0.5), sweep(900, 300, 0.15, "triangle", 0.3))
    s["bucket"] = mix(sweep(hz(5), hz(-12), 0.15, "square", 0.3, 0.5), noise_burst(0.5, 2, 6, 0.4))
    s["fight"] = mix(sweep(hz(-12), hz(12), 0.2, "square", 0.4, 0.5), noise_burst(0.3, 2, 8, 0.35))
    return {k: fade_out(v) for k, v in s.items()}


def make_voice():
    """Jingles d'annonce (pas de voix enregistrée : annonces textuelles + jingles)."""
    v = {}
    v["borroka"] = mix(arp([hz(-5), hz(0), hz(7)], 0.09, vol=0.4, duty=0.5), sweep(110, 110, 0.27, "triangle", 0.5))
    v["bukatu"] = arp([hz(7), hz(3), hz(0), hz(-5)], 0.12, vol=0.4, duty=0.25)
    v["txapeldun"] = arp([hz(0), hz(4), hz(7), hz(12), hz(16)], 0.1, vol=0.4, duty=0.5)
    v["plouf"] = mix(sweep(900, 140, 0.35, "triangle", 0.6, curve=0.5), noise_burst(0.5, 2, 6, 0.4))
    return {k: fade_out(b) for k, b in v.items()}


# ================================================================ main


def main(argv):
    what = argv[0] if argv else "all"
    only = set(argv[1:])
    if what in ("music", "all"):
        for name, fn in MUSIC.items():
            if only and name not in only:
                continue
            buf = fn()
            write_ogg(os.path.join(AUDIO, "music", f"{name}.ogg"), buf, MUSIC_QUALITY)
            print(f"musique {name:14s} {len(buf) / SR:5.1f} s")
    if what in ("sfx", "all"):
        sfx = make_sfx()
        for name, buf in sfx.items():
            if only and name not in only:
                continue
            write_ogg(os.path.join(AUDIO, "sfx", f"{name}.ogg"), buf, SFX_QUALITY)
        print("sfx :", len(sfx))
    if what in ("voice", "all"):
        voice = make_voice()
        for name, buf in voice.items():
            write_ogg(os.path.join(AUDIO, "voice", f"{name}.ogg"), buf, SFX_QUALITY)
        print("jingles :", len(voice))


if __name__ == "__main__":
    main(sys.argv[1:])
