"""Indices de palette communs au roster (docs/PIPELINE_CONTRACT.md §1)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from palette import RAMPS  # noqa: E402

TRANSPARENT = 0
OUTLINE = 1
EYE = 2

ROLES = {
    "skin": (3, 4),
    "hair": (7, 3),
    "outfit_a": (10, 4),
    "outfit_b": (14, 4),
    "hat": (18, 4),
    "acc_b": (22, 4),
    "acc_c": (26, 3),
    "extra": (29, 3),
}

OUTLINE_RGB = RAMPS["outline"][0]
EYE_RGB = RAMPS["linen"][0]


def palette_roles() -> dict:
    return {role: list(range(start, start + n)) for role, (start, n) in ROLES.items()}


def base(role: str, back: bool = False) -> int:
    """Index de remplissage d'une pièce : 2e ton de la rampe (3e pour l'arrière)."""
    start, n = ROLES[role]
    return start + min(2 if back else 1, n - 1)


def shade_ramps() -> dict:
    """index -> (plus clair, plus sombre) au sein de sa rampe."""
    out = {}
    for start, n in ROLES.values():
        for i in range(start, start + n):
            out[i] = (i - 1 if i > start else None, i + 1 if i < start + n - 1 else None)
    return out


def resample(ramp: list, n: int) -> list:
    if len(ramp) == n:
        return list(ramp)
    if n == 1:
        return [ramp[len(ramp) // 2]]
    if n > len(ramp):
        # on prolonge par le ton le plus sombre : les membres arrière
        # (2e ton plus sombre) restent distincts des membres avant
        return list(ramp) + [ramp[-1]] * (n - len(ramp))
    return [ramp[round(i * (len(ramp) - 1) / (n - 1))] for i in range(n)]


def build_row(role_ramps: dict) -> list:
    """32 couleurs RGBA d'un costume à partir de {rôle: liste RGB}."""
    row = [(0, 0, 0, 0)] * 32
    row[OUTLINE] = OUTLINE_RGB + (255,)
    row[EYE] = EYE_RGB + (255,)
    for role, (start, n) in ROLES.items():
        cols = resample(role_ramps[role], n)
        for i, c in enumerate(cols):
            row[start + i] = tuple(c) + (255,)
    return row
