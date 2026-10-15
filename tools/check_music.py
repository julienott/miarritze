#!/usr/bin/env python3
"""Contrôle des musiques bouclées (après décodage OGG) : durée, crête, débit,
raccord de boucle fin → début, niveau RMS et centroïde spectral.

Raccord : on compare le saut entre le dernier et le premier échantillon au
saut typique entre deux échantillons voisins du morceau (percentile 99,9) ;
un rapport ≤ 1 veut dire « aucun clic » à la reprise. On vérifie aussi que
les 250 ms de fin et de début ne sont pas un trou (RMS > RMS global − 12 dB).

Usage : .venv/bin/python tools/check_music.py [nom…]   (défaut : les 10 décors)
"""
import os
import sys

import numpy as np
import soundfile as sf

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MUSIC = os.path.join(ROOT, "assets", "audio", "music")
STAGES = ["grande_plage", "cote_basques", "port_pecheurs", "rocher_vierge", "port_vieux",
          "halles", "fronton", "stade", "aquarium", "phare_sommet"]


def check(name):
    path = os.path.join(MUSIC, name + ".ogg")
    x, sr = sf.read(path)
    if x.ndim > 1:
        x = x.mean(axis=1)
    dur = len(x) / sr
    peak_db = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    kbps = os.path.getsize(path) * 8 / dur / 1000
    d = np.abs(np.diff(x))
    jump = abs(x[0] - x[-1]) / (np.percentile(d, 99.9) + 1e-12)
    w = int(0.25 * sr)
    rms = lambda a: float(np.sqrt(np.mean(a ** 2)) + 1e-12)
    rms_db = 20 * np.log10(rms(x))
    end_db = 20 * np.log10(rms(x[-w:])) - rms_db       # pas de trou en fin de boucle…
    start_db = 20 * np.log10(rms(x[:w])) - rms_db      # …ni au début
    seam_db = min(end_db, start_db)
    spec = np.abs(np.fft.rfft(x[: sr * 20]))
    f = np.fft.rfftfreq(min(len(x), sr * 20), 1 / sr)
    centroid = float(np.sum(f * spec) / np.sum(spec))
    ok = 45 <= dur <= 70 and peak_db <= -2.99 and jump <= 1.0 and seam_db > -12 and os.path.getsize(path) <= 700_000
    print(f"{name:14s} {dur:5.1f} s  crête {peak_db:5.2f} dBFS  RMS {rms_db:6.1f} dB  {kbps:4.0f} kbps  "
          f"{os.path.getsize(path) / 1024:4.0f} Ko  saut boucle {jump:4.2f}  RMS fin/début {end_db:+5.1f}/{start_db:+5.1f} dB  "
          f"centroïde {centroid:5.0f} Hz  {'OK' if ok else '<<< À VOIR'}")
    return ok


if __name__ == "__main__":
    names = sys.argv[1:] or STAGES
    results = [check(n) for n in names]
    sys.exit(0 if all(results) else 1)
