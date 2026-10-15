#!/usr/bin/env python3
"""Bande-son chiptune de Miarritze Borroka (SPEC-BORROKA §12).

Moteur maison : carré (rapport cyclique variable), triangle, bruit LFSR
15 bits façon NES, « steel pan » additif. Synthèse vectorisée (numpy),
export OGG Vorbis via soundfile/libsndfile (ffmpeg n'est pas requis).

Thèmes de stage : chacun est bâti sur un AIR TRADITIONNEL ANONYME basque,
relevé note à note dans un recueil vérifiable (Azkue, Aita Donostia, Iztueta,
Salaberry, via la base Doinutegia de Bertsozale ou la Wikipédia basque), avec
harmonisation et orchestration originales et des timbres basques évoqués en
synthèse (txistu, trikitixa, alboka, chœur, txalaparta, pandero, atabal).
Les autres morceaux (titre, menus, pyramide, fins, jingles) restent des
compositions originales dans des formes traditionnelles. Aucune œuvre à auteur
protégée, aucun échantillon tiers (voir docs/MUSIC.md). Hegoak est exclu.

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
        if real <= PEAK:
            return
        target *= PEAK / real * 0.995


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


# ================================================================ instruments basques
# Timbres ÉVOQUÉS en synthèse pure (numpy), sans aucun échantillon tiers :
#   txistu   flûte à 3 trous : fondamentale pure, souffle, attaque « par en dessous », vibrato
#   trikitixa accordéon diatonique : deux anches désaccordées (battement = trémolo)
#   alboka   anche double en corne : spectre nasal (harmoniques impairs + formant), bourdon
#   abesbatza chœur : 3 voix « a / o » par formants
#   txalaparta planches frappées : partiels inharmoniques d'une poutre libre
#   pandero  tambourin à cymbalettes ; atabal (caisse claire) ; bombo (grosse caisse)
#   ttun-ttun tambour à cordes souletin (corde pincée tonique/quinte)
#   tronpeta cuivre de fanfare (stade)

_NOTE_CACHE = {}
_NOISE_CACHE = {}


def band_noise(n, lo, hi, seed=0):
    """Bruit blanc filtré passe-bande (FFT) ; banque de 4 s tirée en boucle."""
    key = (lo, hi, seed)
    if key not in _NOISE_CACHE:
        rng = np.random.default_rng(1000 + seed)
        m = 4 * SR
        spec = np.fft.rfft(rng.standard_normal(m))
        f = np.fft.rfftfreq(m, 1 / SR)
        resp = 1.0 / (1 + ((f - (lo + hi) / 2) / max(1.0, (hi - lo) / 2)) ** 4)
        x = np.fft.irfft(spec * resp, m)
        _NOISE_CACHE[key] = x / (np.max(np.abs(x)) + 1e-9)
    bank = _NOISE_CACHE[key]
    return bank[np.arange(n) % len(bank)]


def _gate_env(n, n_gate, attack, release):
    """Enveloppe : montée `attack`, tenue jusqu'à `n_gate`, extinction `release`."""
    env = np.zeros(n)
    a = max(1, min(n_gate, int(attack * SR)))
    env[:a] = np.linspace(0, 1, a)
    env[a:n_gate] = 1.0
    r = n - n_gate
    if r > 0:
        env[n_gate:] = np.linspace(1, 0, r)
    return env


def _additive(f, amps):
    """Somme d'harmoniques k·f d'amplitudes `amps` (coupées sous Nyquist)."""
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = np.zeros(len(f))
    fmax = float(np.max(f))
    for k, a in enumerate(amps, 1):
        if a and k * fmax < SR * 0.45:
            out += a * np.sin(k * phase)
    return out


def _vibrato(t, depth, rate=5.2, delay=0.15):
    return 1 + np.clip((t - delay) / 0.2, 0, 1) * depth * np.sin(2 * np.pi * rate * t)


def inst_txistu(m, dur, soft=False):
    """Txistu : flûte à bec à 3 trous, son pur et aigu, souffle audible."""
    rel = 0.07
    n, ng = int((dur + rel) * SR), max(1, int(dur * SR))
    t = np.arange(n) / SR
    f = freq(m) * (1 - 0.010 * np.exp(-t * 45)) * _vibrato(t, 0.004 if soft else 0.006)
    amps = (1, 0.10, 0.04) if soft else (1, 0.22, 0.10, 0.04, 0.02)
    s = _additive(f, amps)
    chiff = band_noise(n, 2500, 7000, 1) * (0.05 + (0.15 if soft else 0.35) * np.exp(-t * 40))
    return (s + chiff) * _gate_env(n, ng, 0.03 if soft else 0.02, rel)


_REED = tuple(0.9 / k ** 1.1 * (1.0 if k % 2 else 0.75) for k in range(1, 13))


def inst_trikitixa(m, dur):
    """Trikitixa : deux anches légèrement désaccordées → trémolo de battement."""
    rel = 0.05
    n, ng = int((dur + rel) * SR), max(1, int(dur * SR))
    f = np.full(n, freq(m))
    s = _additive(f, _REED) + 0.8 * _additive(f * 1.0042, _REED)
    return s * 0.55 * _gate_env(n, ng, 0.012, rel)


def _nasal_amps(f0, n_h=16, centre=1500.0, width=700.0):
    amps = []
    for k in range(1, n_h + 1):
        base = (1.0 if k % 2 else 0.35) / k
        amps.append(base * (1 + 2.2 * np.exp(-((k * f0 - centre) / width) ** 2)))
    return amps


def inst_alboka(m, dur):
    """Alboka : double chalumeau en corne, timbre nasal et perçant, très lié."""
    rel = 0.04
    n, ng = int((dur + rel) * SR), max(1, int(dur * SR))
    t = np.arange(n) / SR
    f = np.full(n, freq(m)) * _vibrato(t, 0.002, 6.0)
    s = _additive(f, _nasal_amps(freq(m)))
    accent = 1 + 0.35 * np.exp(-t * 25)                 # coup de langue appuyé
    return s * 0.45 * accent * _gate_env(n, ng, 0.015, rel)


_VOWELS = {"a": ((700, 130, 1.0), (1220, 150, 0.5), (2600, 250, 0.18)),
           "o": ((450, 110, 1.0), (800, 130, 0.45), (2830, 250, 0.06))}


def inst_choir(m, dur, vowel="a"):
    """Chœur : trois voix légèrement désaccordées, voyelle par formants."""
    rel = 0.35
    n, ng = int((dur + rel) * SR), max(1, int(dur * SR))
    t = np.arange(n) / SR
    f0 = freq(m)
    out = np.zeros(n)
    n_h = int(4200 // f0)
    amps = []
    for k in range(1, n_h + 1):
        fk = k * f0
        w = sum(a / (1 + ((fk - fc) / bw) ** 2) for fc, bw, a in _VOWELS[vowel])
        amps.append(w / k ** 0.5)
    for cents, rate, ph in ((-7, 4.6, 0.0), (0, 5.3, 1.3), (6, 5.0, 2.1)):
        f = f0 * 2 ** (cents / 1200) * (1 + 0.005 * np.sin(2 * np.pi * rate * t + ph))
        out += _additive(f, amps)
    return out * 0.22 * _gate_env(n, ng, 0.14, rel)


def inst_tronpeta(m, dur):
    """Cuivre de fanfare : dent de scie qui « s'ouvre » à l'attaque."""
    rel = 0.06
    n, ng = int((dur + rel) * SR), max(1, int(dur * SR))
    t = np.arange(n) / SR
    f = np.full(n, freq(m)) * _vibrato(t, 0.004, 5.5, 0.2)
    bright = 1 - np.exp(-t * 30)
    s = _additive(f, [1 / k for k in range(1, 4)]) + bright * _additive(f, [0, 0, 0] + [1 / k for k in range(4, 12)])
    return s * 0.5 * _gate_env(n, ng, 0.02, rel)


def inst_bass(m, dur):
    """Basse ronde (sinus + 2e harmonique), pincée."""
    rel = 0.06
    n, ng = int((dur + rel) * SR), max(1, int(dur * SR))
    t = np.arange(n) / SR
    s = _additive(np.full(n, freq(m)), (1, 0.35, 0.12))
    return s * np.exp(-t * 2.2) * _gate_env(n, ng, 0.008, rel)


def inst_pluck(m, dur):
    """Corde pincée (ttun-ttun, harpe des « bulles ») : harmoniques à extinction rapide."""
    n = int((dur + 0.4) * SR)
    t = np.arange(n) / SR
    f0 = freq(m)
    phase = 2 * np.pi * f0 * t
    s = sum(np.sin(k * phase) / k * np.exp(-t * (3 + 4 * k)) for k in range(1, 9) if k * f0 < SR * 0.45)
    return s * _gate_env(n, n - int(0.02 * SR), 0.002, 0.02)


def inst_bell(m, dur):
    """Cloche du port : partiels inharmoniques, longue résonance."""
    n = int((dur + 1.0) * SR)
    t = np.arange(n) / SR
    f0 = freq(m)
    s = sum(a * np.sin(2 * np.pi * f0 * r * t) * np.exp(-t * d)
            for r, a, d in ((1, 1, 1.2), (2.0, 0.5, 1.8), (2.4, 0.35, 2.4), (3.0, 0.25, 3.0), (4.5, 0.15, 4.5)))
    return s * _gate_env(n, n - int(0.05 * SR), 0.003, 0.05)


INSTRUMENTS = {"txistu": inst_txistu, "txistu_soft": lambda m, d: inst_txistu(m, d, True),
               "trikitixa": inst_trikitixa, "alboka": inst_alboka,
               "choir_a": lambda m, d: inst_choir(m, d, "a"), "choir_o": lambda m, d: inst_choir(m, d, "o"),
               "tronpeta": inst_tronpeta, "bass": inst_bass, "pluck": inst_pluck, "bell": inst_bell}


def note_sound(inst, m, dur):
    key = (inst, m, round(dur, 4))
    if key not in _NOTE_CACHE:
        _NOTE_CACHE[key] = INSTRUMENTS[inst](m, dur)
    return _NOTE_CACHE[key]


def _hit(kind):
    """Percussions basques (sons courts, mis en cache)."""
    if kind in _NOTE_CACHE:
        return _NOTE_CACHE[kind]
    t = np.arange(int(0.5 * SR)) / SR
    if kind.startswith("txala"):          # txalaparta : poutre libre (1 ; 2,76 ; 5,40 ; 8,93)
        base = {"txala_hi": 520.0, "txala_mid": 440.0, "txala_lo": 340.0,
                "txala_soft_hi": 300.0, "txala_soft_lo": 240.0}[kind]
        soft = "soft" in kind
        parts = ((1, 1.0, 22), (2.76, 0.45, 40), (5.40, 0.18, 70)) if not soft else ((1, 1.0, 14), (2.76, 0.2, 30))
        s = sum(a * np.sin(2 * np.pi * base * r * t) * np.exp(-t * d) for r, a, d in parts)
        click = band_noise(len(t), 1500, 5000, 2) * np.exp(-t * (400 if not soft else 900)) * (0.4 if not soft else 0.1)
        s = s + click
    elif kind in ("pandero", "pandero_acc"):
        jingle = band_noise(len(t), 6000, 11000, 3) * np.exp(-t * 28)
        metal = sum(np.sin(2 * np.pi * fr * t) for fr in (5230, 6870, 8120)) * np.exp(-t * 35) * 0.15
        s = (jingle + metal) * (0.55 if kind == "pandero" else 1.0)
        if kind == "pandero_acc":          # peau frappée
            s = s + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.9
    elif kind in ("atabal", "atabal_s"):
        wires = band_noise(len(t), 1800, 7000, 4) * np.exp(-t * 30)
        body = np.sin(2 * np.pi * 210 * t) * np.exp(-t * 35)
        s = (wires * 0.8 + body * 0.7) * (1.0 if kind == "atabal" else 0.45)
    elif kind == "bombo":
        f = 75 * np.exp(-t * 6) + 48
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * 1.2
    elif kind == "pelota":               # « pok » sec + rebond sur le mur du fronton
        pok = (band_noise(len(t), 900, 3500, 5) * np.exp(-t * 120) + np.sin(2 * np.pi * 1150 * t) * np.exp(-t * 90))
        s = pok.copy()
        d = int(0.13 * SR)
        s[d:] += pok[:-d] * 0.4
    elif kind == "claps":                # applaudissements de tribune (plusieurs mains)
        s = np.zeros(len(t))
        for j, off in enumerate((0, 0.007, 0.013, 0.021, 0.028)):
            k = int(off * SR)
            s[k:] += band_noise(len(t) - k, 900, 4000, 6 + j) * np.exp(-t[:len(t) - k] * 45) * 0.35
    elif kind in ("ttun_g", "ttun_d"):   # ttun-ttun : corde grave pincée + peau
        s = inst_pluck(43 if kind == "ttun_g" else 50, 0.1)[:len(t)] * 0.9
        s = s + np.sin(2 * np.pi * 110 * t[:len(s)]) * np.exp(-t[:len(s)] * 25) * 0.3
    else:
        raise ValueError(kind)
    _NOTE_CACHE[kind] = s
    return s


# ---------------------------------------------------------------- écriture

def chord_list(spec, octave=3):
    """« G:2 C:2 D7:1 Em:1 » → [(fondamentale MIDI, qualité, temps), …]."""
    out = []
    for tok in spec.split():
        name, d = tok.split(":")
        i = 1
        acc = 0
        if len(name) > 1 and name[1] in "#b":
            acc = 1 if name[1] == "#" else -1
            i = 2
        q = name[i:] or "M"
        out.append((12 * (octave + 1) + NOTE_INDEX[name[0]] + acc, q, float(d)))
    return out


def events(notes, start=0.0, transpose=0):
    """Séquence (note, durée) → événements (temps, note, durée) à partir de `start`."""
    out, b = [], start
    for m, d in notes:
        if m is not None:
            out.append((b, m + transpose, d))
        b += d
    return out


class Song:
    """Morceau bouclable : tout est placé en temps (noires), la boucle finit
    exactement sur `beats` et la queue est repliée au début (loop_fix)."""

    def __init__(self, bpm, beats, tail=2.5):
        self.bpm = bpm
        self.beats = int(round(beats)) if abs(beats - round(beats)) < 1e-9 else beats
        self.beat = 60.0 / bpm
        self.buf = blank(beats, bpm, tail)

    def put(self, at_beat, sound, vol):
        s = int(at_beat * self.beat * SR)
        if s >= len(self.buf):
            return
        k = min(len(sound), len(self.buf) - s)
        self.buf[s:s + k] += sound[:k] * vol

    def play(self, evs, inst, vol, gate=0.95):
        for b, m, d in evs:
            self.put(b, note_sound(inst, m, d * self.beat * gate), vol)

    def hits(self, pattern, step, vol, start=0.0, end=None):
        """Motif de percussions répété (« a+b » = simultanés, None = silence)."""
        end = self.beats if end is None else end
        b = start
        while b < end - 1e-6:
            for j, k in enumerate(pattern):
                at = b + j * step
                if k and at < end - 1e-6:
                    for part in k.split("+"):
                        self.put(at, _hit(part), vol)
            b += len(pattern) * step

    def swell(self, at_beat, dur_beats, lo, hi, vol, seed=0):
        """Souffle de bruit filtré en cloche (vagues, foule, embruns)."""
        n = int(dur_beats * self.beat * SR)
        x = np.linspace(0, 1, n)
        self.put(at_beat, band_noise(n, lo, hi, seed) * np.sin(np.pi * x) ** 2, vol)

    def done(self):
        return loop_fix(self.buf, self.beats, self.bpm)


def chord_events(chords, start, style):
    """Accompagnement à partir d'une grille d'accords.
    style : « root » (basse tenue), « umpa » (basse sur le temps, accord au contretemps,
    pour la main gauche de la trikitixa), « alt » (basse fondamentale/quinte par temps),
    « pad » (accord tenu), « arp » (arpège en croches)."""
    bass, chord = [], []
    b = start
    for root, q, d in chords:
        sh = SHAPES[q]
        if style == "root":
            bass.append((b, root - 12, d))
        elif style == "alt":
            k = 0
            while k < d - 1e-6:
                bass.append((b + k, root - 12 + (0 if int(k) % 2 == 0 else 7), min(1.0, d - k)))
                k += 1
        elif style == "umpa":
            k = 0
            while k < d - 1e-6:
                bass.append((b + k, root - 12 + (0 if int(k) % 2 == 0 else 7), 0.45))
                for iv in sh[:3]:
                    chord.append((b + k + 0.5, root + iv, 0.35))
                k += 1
        elif style == "pad":
            for iv in sh[:3]:
                chord.append((b, root + iv, d))
        elif style == "arp":
            k, j = 0.0, 0
            pat = (0, 1, 2, 3, 2, 1)
            while k < d - 1e-6:
                chord.append((b + k, root + 12 + sh[pat[j % 6]], 0.5))
                k += 0.5
                j += 1
        b += d
    return bass, chord


MINOR = (0, 2, 3, 5, 7, 8, 10)
DORIAN = (0, 2, 3, 5, 7, 9, 10)


def harmony_below(notes, tonic, scale=MAJOR):
    """Seconde voix à la tierce inférieure, dans le mode donné."""
    pcs = {(tonic + d) % 12 for d in scale}
    out = []
    for m, d in notes:
        if m is None:
            out.append((None, d))
        else:
            out.append((m - 3 if (m - 3) % 12 in pcs else m - 4, d))
    return out


# ================================================================ thèmes de stage
# Chaque décor est construit autour d'un AIR TRADITIONNEL ANONYME, relevé note à
# note dans une source vérifiable (voir docs/MUSIC.md) :
#   BDB = Bertsozale Elkartea, « Doinutegia » (bdb.bertsozale.eus/web/doinutegia),
#         qui publie la partition et le MIDI de la transcription des cancioneros
#         (Azkue 1922, Aita Donostia, Iztueta 1824, Salaberry 1870…).
#   EU  = partition LilyPond de l'article de la Wikipédia en basque.
# L'harmonisation, l'introduction et l'orchestration sont originales (créées pour
# le jeu) ; seules les MÉLODIES viennent de la tradition. Les rares retouches
# (note finale allongée pour fermer la boucle) sont signalées en commentaire.

# « O Pello Pello » — BDB 2169 (Azkue, Cancionero 875 ; relevé à Azkaine, XIXe s.).
PELLO_PELLO = ("G4:1 G4:.5 A4:.5 B4:1 B4:1 A4:.5 B4:.5 C5:.5 A4:.5 G4:1 D4:1 B4:1.5 C5:.5 D5:1 E5:1 "
               "D5:1.5 C5:.5 B4:1 r:1 B4:.5 D5:.5 D5:.5 D5:.5 E5:1 C5:1 C5:.5 E5:.5 E5:.5 E5:.5 D5:1 B4:1 "
               "B4:.5 D5:.5 D5:.5 D5:.5 C5:1 E5:1 D5:.5 D5:.5 D5:.5 C5:.5 B4:2")      # dernière note : 1 → 2
PELLO_PELLO_CH = "G:2 G:2 D:2 G:2 G:2 C:2 G:2 G:2 G:2 C:2 C:2 G:2 G:2 C:2 D:2 G:2"


def song_grande_plage():
    """Grande Plage : « O Pello Pello » en arin-arin ensoleillé (sol majeur, 2/4).
    Txistu + trikitixa (main gauche um-pa) + pandero, comme une fête sur la promenade."""
    mel = seq(PELLO_PELLO)
    span = lead_beats(mel)                                  # 32 temps
    intro = 8
    s = Song(136, intro + 3 * span)
    ch = chord_list(PELLO_PELLO_CH)
    for start, grid in [(0, ch[-4:])] + [(intro + p * span, ch) for p in range(3)]:
        bass, chord = chord_events(grid, start, "umpa")
        s.play(bass, "bass", 0.30)
        s.play(chord, "trikitixa", 0.07)
    s.play(events(mel, intro, 12), "txistu", 0.30)                          # tour 1 : txistu seul
    s.play(events(mel, intro + span, 12), "trikitixa", 0.16)                # tour 2 : trikitixa…
    s.play(events(harmony_below(mel, 7), intro + span, 12), "trikitixa", 0.09)  # …à la tierce
    s.play(events(mel, intro + 2 * span, 12), "txistu", 0.28)               # tour 3 : tutti
    s.play(events(harmony_below(mel, 7), intro + 2 * span, 12), "trikitixa", 0.08)
    s.hits(["pandero_acc", "pandero", "pandero", "pandero"], 0.25, 0.10)
    s.hits(["bombo", None, None, None], 0.5, 0.25, start=0)
    return s.done()


# « Untziak eder du bela » (variante de « Uso xuria errazu ») — BDB 2826
# (Azkue, manuscrits n° 274 ; relevé à Hazparne, XIXe s.). La mer, le bateau et ses voiles.
UNTZIAK = ("A4:1 A4:.5 B4:.5 C#5:1 C#5:1 D5:1 D5:1 C#5:1.5 r:.5 B4:1 C#5:.5 B4:.5 A4:1 A4:1 B4:1 B4:1 A4:1 r:1 "
           "C#5:1 C#5:1 B4:1 B4:1 A4:.5 A4:.5 A4:.5 A4:.5 G#4:1 A4:1 B4:1 C#5:1 D5:.5 C#5:.5 B4:.5 A4:.5 "
           "G#4:1 F#4:1 E4:1 r:1 A4:1 A4:.5 B4:.5 C#5:1 C#5:1 D5:.5 D5:.5 E5:.5 D5:.5 C#5:.5 B4:.5 C#5:1 "
           "B4:1 C#5:.5 B4:.5 A4:1 A4:1 B4:1 B4:1 A4:2")                         # dernière note : 1 → 2
UNTZIAK_CH = ("A:2 A:2 D:2 A:2 E:2 A:2 E:2 A:2 A:2 E:2 D:2 E:2 E:2 D:2 E:2 E:2 "
              "A:2 A:2 D:2 A:2 E:2 A:2 E:2 A:2")


def song_cote_basques():
    """Côte des Basques : « Untziak eder du bela », la majeur, balancé ; ressac
    toutes les deux mesures. Txistu, puis trikitixa, arpèges « écume »."""
    mel = seq(UNTZIAK)
    span = lead_beats(mel)                                  # 48 temps
    intro = 8
    s = Song(118, intro + 2 * span)
    ch = chord_list(UNTZIAK_CH)
    for start, grid in ((0, ch[-4:]), (intro, ch), (intro + span, ch)):
        bass, _ = chord_events(grid, start, "alt")
        _, arp = chord_events(grid, start, "arp")
        s.play(bass, "bass", 0.30)
        s.play(arp, "pluck", 0.07)
    s.play(events(mel, intro, 12), "txistu", 0.28)
    s.play(events(mel, intro + span, 12), "trikitixa", 0.15)
    s.play(events(harmony_below(mel, 9), intro + span, 12), "trikitixa", 0.08)
    s.hits(["bombo", "pandero", "atabal_s", "pandero"], 0.5, 0.12)
    for k in range(0, s.beats, 4):                          # vagues (une toutes les 2 mesures)
        s.swell(k, 4, 120, 900, 0.10, seed=k % 3)
        s.swell(k + 1.5, 2.0, 3000, 8000, 0.03, seed=7)     # écume
    return s.done()


# « Itsasoa laino dago » (Itsasoan lano dago) — BDB 1993 (Azkue, conférence de Bilbao
# 1901 ; Aita Donostia, « Itsasoetan » 33). Chant de marins, 3/4, mi mineur.
ITSASOA = ("B4:1 B4:1 C5:1 B4:3 A4:1 G4:1 A4:1 F#4:3 B4:1 B4:1 C5:1 B4:3 A4:1 F#4:1 G4:1 E4:3 "
           "F#4:1 A4:1 D#4:1 E4:3 G4:1 B4:1 G4:1 F#4:3 B4:.75 B4:.25 B4:1 C5:1 B4:3 "
           "A4:.75 G4:.25 F#4:1 G4:1 E4:3")
ITSASOA_CH = "Em:3 Em:3 Am:3 B:3 Em:3 Em:3 Am:3 Em:3 B:3 Em:3 G:3 D:3 Em:3 Em:3 B:3 Em:3"


def song_port_pecheurs():
    """Port des Pêcheurs : « Itsasoa laino dago », chant de marins calme.
    Tour 1 : chœur d'hommes (voyelle « o ») ; tour 2 : txistu doux, le chœur
    passe en accords tenus. Bourdon d'alboka très discret, cloche du port, clapot."""
    mel = seq(ITSASOA)
    span = lead_beats(mel)                                  # 48 temps
    intro = 6
    s = Song(96, intro + 2 * span, tail=3.5)
    ch = chord_list(ITSASOA_CH)
    for start, grid in ((0, ch[-2:]), (intro, ch), (intro + span, ch)):
        bass, _ = chord_events(grid, start, "root")
        s.play(bass, "bass", 0.32)
    s.play(events(mel, intro, -12), "choir_o", 0.55)
    s.play(events(harmony_below(mel, 4, MINOR), intro, -12), "choir_o", 0.25)
    _, pad = chord_events(ch, intro + span, "pad")
    s.play(pad, "choir_o", 0.20)
    s.play(events(mel, intro + span, 12), "txistu_soft", 0.26)
    s.play([(b, 52, 2.9) for b in np.arange(0, s.beats, 3.0)], "alboka", 0.025)     # bourdon mi
    s.play([(b, 76, 1) for b in range(0, s.beats, 12)], "bell", 0.10)              # cloche du port
    s.hits(["txala_soft_lo", None, None], 1.0, 0.05)                              # coque contre le quai
    for k in range(0, s.beats, 3):                          # clapot continu (fondus croisés)
        s.swell(k, 6, 100, 700, 0.045, seed=k % 2)
    return s.done()


# « Ene mutilik tipiena » (Nere seme ttipiena) — EU, d'après Aita Donostia, « Gure Herrian »
# 1924 p. 231 (chanson de marins du Labourd relevée à Azkaine). Mesures 2/4 avec une 3/4.
ENE_MUTILIK = ("B4:1 D5:.5 D5:.5 B4:.5 A4:.5 G4:.5 A4:.5 B4:1 G4:1 B4:1 D5:.5 D5:.5 A4:.5 C5:.5 B4:.5 A4:.5 "
               "G4:1 r:1 A4:.5 A4:.5 B4:.5 B4:.5 D5:.5 B4:.5 A4:.5 A4:.5 A4:.5 A4:.25 A4:.25 "
               "B4:.5 B4:.5 D5:.5 B4:.5 A4:1 r:1 D5:1 E5:.5 D5:.5 B4:.5 A4:.5 G4:.5 A4:.25 A4:.25 "
               "B4:1 G4:1 D5:1 E5:.5 D5:.5 B4:.5 A4:.5 C5:.5 A4:.5 G4:1 r:1")
ENE_MUTILIK_CH = "G:2 G:2 G:2 G:2 D:2 G:3 G:2 D:2 G:2 D:2 G:2 Em:2 G:2 C:2 D:2 G:2"


def song_rocher_vierge():
    """Rocher de la Vierge : « Ene mutilik tipiena », l'enfant envoyé en haut du
    mât guetter la terre. Alboka nasale sur txalaparta (rythme alterné « ttakun »),
    puis txistu, puis les deux à la tierce ; embruns sur la passerelle."""
    mel = seq(ENE_MUTILIK)
    span = lead_beats(mel)                                  # 33 temps
    intro = 8
    s = Song(116, intro + 3 * span)
    ch = chord_list(ENE_MUTILIK_CH)
    for p in range(3):
        bass, _ = chord_events(ch, intro + p * span, "alt")
        s.play(bass, "bass", 0.30)
    s.play([(0, 43, 4), (4, 50, 4)], "bass", 0.30)
    s.play(events(mel, intro, 12), "alboka", 0.22)
    s.play(events(mel, intro + span, 12), "txistu", 0.27)
    s.play(events(mel, intro + 2 * span, 12), "alboka", 0.17)
    s.play(events(harmony_below(mel, 7), intro + 2 * span, 12), "txistu", 0.17)
    s.play([(b, 55, 1.95) for b in np.arange(0, s.beats - 1, 2.0)], "alboka", 0.04)  # bourdon sol
    # txalaparta : deux joueurs qui se répondent (ta-kun / ta-kun), en doubles croches
    s.hits(["txala_hi", "txala_lo", "txala_mid", None, "txala_hi", "txala_lo", None, "txala_mid"], 0.25, 0.10)
    s.hits(["bombo", None, None, None], 1.0, 0.18)
    for k in range(0, s.beats - 3, 8):
        s.swell(k, 5, 100, 800, 0.10, seed=k % 3)
        s.swell(k + 3, 3, 3500, 9000, 0.05, seed=5)         # embruns
    return s.done()


# « Ama begira zazu » — BDB (Aita Donostia ; « Gure Herria » 1924, 5 ; « Itsasoetan » ;
# dansée). Levée d'une croche ; note finale allongée (1 → 1,5) pour fermer la mesure.
AMA_BEGIRA = ("D4:.5 G4:.5 G4:.5 B4:.5 B4:.5 D5:1 G4:.5 B4:.5 A4:.5 C5:.5 F#4:.5 A4:.5 G4:1 r:.5 "
              "D4:.5 G4:.5 G4:.5 B4:.5 B4:.5 D5:1 G4:.5 B4:.5 A4:.5 C5:.5 F#4:.5 A4:.5 G4:1 r:1 "
              "D5:1 B4:1 G4:1.5 D4:.5 E4:.5 G4:.5 F#4:.5 A4:.5 G4:1.5")
AMA_BEGIRA_CH = "G:.5 G:2 G:2 D:2 G:2 G:2 G:2 D:2 G:2 G:2 G:2 C:1 D:1 G:1.5"


def song_port_vieux():
    """Port-Vieux : « Ama begira zazu » (« Maman, regarde-moi danser sur la place »).
    Petite crique, baignade : xirula/txistu en duo à la tierce sur ttun-ttun
    (tambour à cordes souletin : tonique et quinte pincées en rythme)."""
    mel = seq(AMA_BEGIRA)
    span = lead_beats(mel)                                  # 24 temps
    intro = 8
    s = Song(120, intro + 4 * span)
    ch = chord_list(AMA_BEGIRA_CH)
    for p in range(4):
        bass, _ = chord_events(ch, intro + p * span, "alt")
        s.play(bass, "bass", 0.26)
    s.play([(0, 43, 2), (2, 50, 2), (4, 43, 2), (6, 50, 2)], "bass", 0.26)
    # ttun-ttun : sol et ré pincés (croche, croche-croche)
    s.hits(["ttun_g", "ttun_d", "ttun_d", None], 0.5, 0.14)
    s.play(events(mel, intro, 12), "txistu", 0.27)
    s.play(events(mel, intro + span, 12), "txistu", 0.24)
    s.play(events(harmony_below(mel, 7), intro + span, 12), "txistu", 0.15)
    s.play(events(mel, intro + 2 * span, 24), "txistu_soft", 0.18)          # xirula, une octave au-dessus
    s.play(events(mel, intro + 2 * span, 12), "pluck", 0.10)
    s.play(events(mel, intro + 3 * span, 12), "txistu", 0.25)
    s.play(events(harmony_below(mel, 7), intro + 3 * span, 12), "txistu", 0.15)
    s.hits([None, "pandero", None, "pandero"], 0.5, 0.08, start=intro + span)
    for k in range(0, s.beats, 8):
        s.swell(k, 8, 150, 900, 0.05, seed=k % 2)
    return s.done()


# « Maritxu nora zoaz » — BDB 501 (Aita Donostia ; Santesteban « Aires vascongados » 64 ;
# relevé à Gartzain, Baztan) et EU (même relevé). Zortziko txiki 2/4.
MARITXU = ("D4:.5 G4:.5 G4:1 F#4:.5 G4:.5 A4:.5 B4:.5 G4:.5 A4:.5 B4:.5 C5:.5 B4:1 A4:1 "
           "D4:.5 G4:.5 G4:1 F#4:.5 G4:.5 A4:.5 B4:.5 C5:.5 D5:.5 B4:.5 C5:.5 A4:1 G4:1 "
           "B4:.5 C5:.5 D5:1 E5:.5 D5:.5 C5:.5 B4:.5 G4:.5 A4:.5 B4:.5 C5:.5 B4:1 A4:1 "
           "D4:.5 G4:.5 G4:1 F#4:.5 G4:.5 A4:.5 B4:.5 C5:.5 D5:.5 B4:.5 C5:.5 A4:1 G4:1")  # fin : 0,5 → 1
MARITXU_CH = "G:2 G:2 G:2 D:2 G:2 G:2 C:2 D:1 G:1 G:2 C:2 G:2 D:2 G:2 G:2 C:2 D:1 G:1"


def song_halles():
    """Les Halles : « Maritxu nora zoaz » en trikitixa et pandero, au tempo
    d'arin-arin : l'ambiance d'un marché couvert un jour de fête."""
    mel = seq(MARITXU)
    span = lead_beats(mel)                                  # 32 temps
    intro = 8
    s = Song(144, intro + 4 * span)
    ch = chord_list(MARITXU_CH)
    for start, grid in [(0, chord_list("G:2 C:2 D:2 G:2"))] + [(intro + p * span, ch) for p in range(4)]:
        bass, chord = chord_events(grid, start, "umpa")
        s.play(bass, "trikitixa", 0.14)
        s.play(chord, "trikitixa", 0.06)
    for p, (tr, harm) in enumerate(((12, False), (12, True), (24, False), (12, True))):
        st = intro + p * span
        s.play(events(mel, st, tr), "trikitixa", 0.17 if tr == 12 else 0.11)
        if harm:
            s.play(events(harmony_below(mel, 7), st, tr), "trikitixa", 0.10)
    s.play(events(mel, intro + 2 * span, 12), "txistu_soft", 0.12)
    s.hits(["pandero_acc", "pandero", "pandero", "pandero", "pandero_acc", "pandero", "pandero_acc", "pandero"],
           0.25, 0.13)
    s.hits(["bombo", None, None, None], 0.5, 0.16, start=intro)
    return s.done()


# « Alpargatak urratuta » / Azeri-dantza — BDB 2088 (Iztueta, « Gipuzkoako dantzak » 49,
# « Esku-aldatzeko soinua », XVIIIe s.). Air de txistu ; les silences de danse sont
# remplis par l'atabal et la pelote. Dernière note allongée (1 → 1 + 3 temps de pause).
AZERI = ("G4:1.5 A4:.5 G4:1 F4:1 E4:1.5 F4:.5 G4:1 A4:1 G4:1.5 A4:.5 G4:1 A4:1 G4:1 r:3 "
         "G4:1.5 A4:.5 G4:1 F4:1 E4:1.5 F4:.5 G4:1 C5:1 G4:1.5 F4:.5 E4:1 D4:1 C4:1 r:2 C4:1 "
         "E4:1.5 D4:.5 E4:1 F4:1 E4:1 r:2 C4:1 E4:1.5 D4:.5 E4:1 F4:1 G4:1 r:3 "
         "G4:1.5 A4:.5 B4:1 G4:1 A4:1.5 B4:.5 C5:1 A4:1 B4:1.5 C5:.5 D5:1 B4:1 C5:1 r:3")
AZERI_CH = "C:4 C:4 C:4 G7:4 C:4 C:4 G:2 G7:2 C:4 C:4 C:4 C:4 G7:4 G:4 Am:4 G:4 C:4"


def song_fronton():
    """Fronton : Azeri-dantza d'Iztueta, txistu et atabal (tamboril) comme sur
    une place de village ; claquements de pelote contre le mur (avec rebond)."""
    mel = seq(AZERI)
    span = lead_beats(mel)                                  # 64 temps
    intro = 8
    s = Song(168, intro + 2 * span)
    ch = chord_list(AZERI_CH)
    s.play([(0, 36, 4), (4, 43, 4)], "bass", 0.30)
    for p in range(2):
        bass, _ = chord_events(ch, intro + p * span, "alt")
        s.play(bass, "bass", 0.28)
    s.play(events(mel, intro, 12), "txistu", 0.30)
    s.play(events(mel, intro + span, 12), "txistu", 0.27)
    s.play(events(mel, intro + span, 24), "txistu_soft", 0.07)              # silbote : doublure aiguë
    s.hits(["atabal", None, "atabal_s", "atabal_s"], 0.25, 0.16)
    s.hits(["bombo", None, None, None, "bombo", None, None, None], 0.5, 0.14)
    # la pelote claque dans les silences de la danse (fin des phrases)
    for at in (13.5, 14.5, 29.5, 37.5, 45, 46, 47.5, 61, 62.5):
        for p in range(2):
            s.put(intro + p * span + at, _hit("pelota"), 0.30)
    s.put(1, _hit("pelota"), 0.30)
    s.put(5, _hit("pelota"), 0.30)
    return s.done()


# « Pello Josepe tabernan dela » — BDB 1551 (Aita Donostia ; Santesteban « Aires
# vascongados » 61 ; relevé à Sare, XIXe s.). Une mesure de silence ajoutée en fin de tour.
PELLO_JOSEPE = ("r:.5 D4:.5 E4:.5 F#4:.5 G4:1 G4:1 r:.5 G4:.5 B4:.5 G4:.5 E4:1 E4:1 r:.5 C5:.5 C5:.5 A4:.5 "
                "F#4:1 D4:1 E4:.5 F#4:.5 G4:1 r:.5 D4:.5 E4:.5 F#4:.5 G4:1 G4:1 r:.5 G4:.5 B4:.5 G4:.5 "
                "E4:1 E4:1 r:.5 C5:.5 C5:.5 A4:.5 F#4:1 D4:1 E4:.5 F#4:.5 G4:1 r:.5 G4:.5 F#4:.5 G4:.5 "
                "A4:1 A4:1 r:.5 F#4:.5 G4:.5 A4:.5 B4:1 B4:1 r:.5 G4:.5 A4:.5 B4:.5 C5:1 C5:1 B4:.5 B4:.5 A4:1 "
                "r:.5 D5:.5 D5:.5 B4:.5 G4:1 G4:1 r:.5 G4:.5 A4:.5 B4:.5 C5:1 E4:1 r:.5 G4:.5 F#4:.5 E4:.5 "
                "D4:1 G4:1 F#4:1 A4:1 G4:2 r:2")
PELLO_JOSEPE_CH = ("D:2 G:2 G:2 C:2 D:2 D:2 G:2 D:2 G:2 G:2 C:2 D:2 D:2 G:2 G:2 D:2 D:2 G:2 G:2 C:2 "
                   "G:1 D:1 G:2 G:2 G:2 C:2 C:2 G:2 D:2 G:2 G:2")


def song_stade():
    """Stade : « Pello Josepe » en fanfare de tribune (peña) : cuivres à la tierce,
    grosse caisse, tambours, applaudissements et clameur de la foule."""
    mel = seq(PELLO_JOSEPE)
    span = lead_beats(mel)                                  # 60 temps
    intro = 8
    s = Song(144, intro + 2 * span)
    ch = chord_list(PELLO_JOSEPE_CH)
    for p in range(2):
        bass, chord = chord_events(ch, intro + p * span, "umpa")
        s.play(bass, "tronpeta", 0.10)
        s.play(chord, "tronpeta", 0.035)
    s.play([(0, 43, 1), (2, 43, 1), (4, 50, 1), (6, 43, 1)], "tronpeta", 0.12)
    for p in range(2):                                      # mesure de pause : coups de fanfare
        end = intro + (p + 1) * span
        s.play([(end - 2, m, 0.5) for m in (67, 71, 74)] + [(end - 1, m, 0.5) for m in (67, 71, 74)],
               "tronpeta", 0.07)
    s.play(events(mel, intro, 12), "tronpeta", 0.20)
    s.play(events(harmony_below(mel, 7), intro, 12), "tronpeta", 0.11)
    s.play(events(mel, intro + span, 12), "tronpeta", 0.18)
    s.play(events(harmony_below(mel, 7), intro + span, 12), "tronpeta", 0.11)
    s.play(events(mel, intro + span, 24), "txistu", 0.12)                   # le txistu de la peña
    s.hits(["bombo+atabal", "atabal_s", "atabal", "atabal_s"], 0.5, 0.15)
    s.hits([None, "claps"], 1.0, 0.18, start=intro)
    for k in range(0, s.beats, 4):                          # clameur continue (fondus croisés)
        s.swell(k, 8, 300, 2500, 0.06, seed=k % 4)
    s.swell(0, 8, 400, 3500, 0.09, seed=9)
    s.swell(intro + span - 4, 8, 400, 3500, 0.09, seed=9)
    return s.done()


# « Haurtxo txikia negarrez dago » I — BDB 1468 (Manuel Lekuona ; « Mariya » 35 ;
# « Donostiko kantu zaharrak » 111). Berceuse, sol mineur (2/4).
HAURTXO = ("r:1 D4:.5 D4:.5 D4:1 E4:.5 F#4:.5 G4:1 G4:.5 F#4:.5 A4:1 G4:1 r:1 F#4:.5 G4:.5 A4:1 C5:.5 Bb4:.5 "
           "A4:1 G4:1 F#4:2 r:1 A4:.5 A4:.5 Bb4:1 A4:.5 G4:.5 G4:1 F#4:.5 G4:.5 A4:1 D4:1 r:1 F4:.5 F4:.5 "
           "G4:1 A4:.5 G4:.5 F4:1 Eb4:1 D4:2 r:1 D4:.5 D4:.5 D5:1 D5:.5 D5:.5 D5:1 C5:.5 Bb4:.5 D5:1 C5:1 "
           "r:1 A4:.5 Bb4:.5 C5:1 C5:.5 C5:.5 C5:1 A4:1 Bb4:2 r:1 G4:.5 A4:.5 Bb4:1 Bb4:.5 Bb4:.5 "
           "Bb4:1 A4:.5 G4:.5 Bb4:1 A4:1 r:1 F#4:.5 G4:.5 A4:1 A4:.5 A4:.5 G4:1 F#4:1 G4:2")
HAURTXO_CH = ("Gm:2 D:2 Gm:2 D:2 D:2 D:2 D:2 D:2 D:2 Gm:2 Gm:2 D:2 F:2 F:2 Cm:2 D:2 "
              "Gm:2 Bb:2 Bb:2 F:2 F:2 F:2 F:2 Bb:2 Gm:2 Gm:2 Gm:2 D:2 D:2 D:2 D:2 Gm:2")


def song_aquarium():
    """Aquarium : la berceuse « Haurtxo txikia », très douce et un peu
    mystérieuse : flûte feutrée, chœur « o » lointain, txalaparta en sourdine,
    arpèges de harpe et bulles. Deuxième moitié à l'octave, plus lumineuse."""
    mel = seq(HAURTXO)
    span = lead_beats(mel)                                  # 64 temps
    intro = 8
    s = Song(84, intro + span, tail=3.5)
    ch = chord_list(HAURTXO_CH)
    for start, grid in ((0, ch[-4:]), (intro, ch)):
        bass, _ = chord_events(grid, start, "root")
        _, arp = chord_events(grid, start, "arp")
        _, pad = chord_events(grid, start, "pad")
        s.play(bass, "bass", 0.30)
        s.play(arp, "pluck", 0.06)
        s.play(pad, "choir_o", 0.07)
    half = 32
    first = [e for e in events(mel, intro, 12) if e[0] < intro + half]
    second = [e for e in events(mel, intro, 12) if e[0] >= intro + half]
    s.play(first, "txistu_soft", 0.28)
    s.play(second, "txistu_soft", 0.22)
    s.play([(b, m + 12, d) for b, m, d in second], "bell", 0.025)          # reflets sur la vitre
    s.hits(["txala_soft_lo", None, "txala_soft_hi", "txala_soft_lo"], 0.5, 0.06)
    rng = np.random.default_rng(42)
    beat = 60.0 / s.bpm
    for k in range(int(s.beats * 0.75)):                    # bulles qui montent
        at = float(rng.uniform(0, s.beats - 1))
        n = int(0.07 * SR)
        t = np.arange(n) / SR
        f = float(rng.uniform(500, 900)) * (1 + 6 * t)
        s.put(at, np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]), 0.03)
    return s.done()


# « Haltzak ez du bihotzik » (Berterretxen kantoria, ballade du XVe s.) — BDB 1843
# (Salaberry, « Chants populaires du Pays Basque » 1870, p. 211 ; Azkue 417 ;
# Aita Donostia). Mode de mi dorien (do#). Le « r:0.125 » du relevé est fondu dans la note.
BERTERRETXE = ("E4:.5 G4:.25 F#4:.25 E4:.5 D4:.5 G4:.5 A4:.5 B4:1 E5:1 E5:.5 E5:.5 D5:.5 B4:.25 C#5:.25 D5:.5 C#5:.5 B4:2 "
               "E4:.5 G4:.25 F#4:.25 E4:.5 D4:.5 G4:.5 A4:.5 B4:1 E5:1 E5:.5 E5:.5 D5:.5 B4:.25 C#5:.25 D5:.5 C#5:.5 B4:2 "
               "B4:.5 B4:.25 C5:.25 D5:.5 B4:.5 A4:.25 G4:.25 A4:.25 B4:.25 G4:.5 E4:.5 A4:1 B4:.75 A4:.25 "
               "G4:.5 E4:.5 A4:.5 G4:.5 F#4:2 B4:.5 B4:.25 C5:.25 D5:.5 B4:.5 A4:.25 G4:.25 A4:.25 B4:.25 G4:.5 E4:.5 "
               "A4:1 B4:.75 A4:.25 G4:.5 A4:.5 G4:.5 F#4:.5 E4:2")
BERTERRETXE_CH = ("Em:2 G:2 Em:2 A:2 Bm:2 Em:2 G:2 Em:2 A:2 B:2 G:2 Am:2 D:2 C:2 B:2 G:2 Am:2 D:2 C:1 B:1 Em:2")


def song_phare_sommet():
    """Sommet du Phare (boss) : la vieille ballade souletine de Berterretxe,
    sombre et épique au crépuscule. Tour 1 : chœur d'hommes et alboka sur
    tambours de guerre ; tour 2 : tutti, txistu à l'octave, txalaparta lancée."""
    mel = seq(BERTERRETXE)
    span = lead_beats(mel)                                  # 40 temps
    intro = 8
    s = Song(104, intro + 2 * span)
    ch = chord_list(BERTERRETXE_CH)
    s.play([(0, 28, 4), (4, 28, 4)], "bass", 0.34)
    for p in range(2):
        bass, _ = chord_events(ch, intro + p * span, "alt")
        _, pad = chord_events(ch, intro + p * span, "pad")
        s.play(bass, "bass", 0.32)
        s.play(pad, "choir_a", 0.10)
    s.play(events(mel, intro, -12), "choir_a", 0.42)
    s.play(events(mel, intro, 12), "alboka", 0.15)
    s.play(events(mel, intro + span, 0), "choir_a", 0.40)
    s.play(events(harmony_below(mel, 4, DORIAN), intro + span, 0), "choir_a", 0.18)
    s.play(events(mel, intro + span, 12), "txistu", 0.22)
    s.play([(b, 40, 1.95) for b in np.arange(0, s.beats - 1, 2.0)], "alboka", 0.035)   # bourdon mi
    s.hits(["bombo", None, "atabal_s", "atabal_s", "bombo", "atabal_s", "atabal", "atabal_s"], 0.25, 0.16)
    s.hits(["txala_lo", "txala_hi", "txala_mid", "txala_hi"], 0.25, 0.08, start=intro + span)
    s.hits(["txala_lo", None, None, "txala_hi"], 0.25, 0.06, start=0, end=intro + span)
    return s.done()


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
