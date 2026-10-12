# Palette Miarritze Borroka : ~64 couleurs en rampes (SPEC-BORROKA §10.2).
# UNIQUE source des couleurs du jeu (sprites, UI, vfx). Les décors i2i
# gardent leur propre palette RD, harmonisée par filtre de cohérence.
#
# Lumière en haut à gauche. Contour universel : `outline` (jamais de noir pur).

from collections import OrderedDict

# Chaque rampe va du plus clair au plus sombre.
RAMPS = OrderedDict([
    # Structure
    ("outline",   [(58, 38, 52)]),
    ("ink",       [(24, 16, 28)]),
    ("linen",     [(247, 241, 227), (236, 225, 204), (214, 198, 170), (176, 160, 140)]),
    # Peaux (plusieurs carnations)
    ("skin_a",    [(255, 222, 186), (242, 201, 160), (214, 160, 110), (170, 116, 78)]),
    ("skin_b",    [(214, 158, 110), (176, 118, 76), (132, 84, 56)]),
    # Cheveux
    ("blond",     [(250, 222, 132), (226, 184, 84), (176, 128, 52)]),
    ("hair",      [(122, 82, 56), (90, 58, 40), (60, 40, 32)]),
    # Tissus basques
    ("red",       [(238, 96, 84), (206, 52, 52), (150, 34, 40), (104, 26, 36)]),
    ("green",     [(96, 170, 96), (52, 128, 72), (34, 88, 52)]),
    ("navy",      [(84, 112, 168), (52, 72, 124), (34, 44, 82)]),
    ("turquoise", [(112, 214, 210), (64, 180, 188), (36, 128, 146)]),
    ("yellow",    [(255, 232, 110), (244, 198, 62), (198, 146, 34)]),
    ("orange",    [(250, 176, 96), (238, 140, 58), (188, 96, 40)]),
    # Métal / laiton / bois
    ("brass",     [(250, 226, 150), (222, 176, 82), (160, 112, 50)]),
    ("steel",     [(200, 208, 214), (140, 150, 162), (92, 100, 116)]),
    ("wood",      [(196, 148, 92), (150, 104, 62), (108, 72, 46), (74, 48, 34)]),
    # Écume / mer / ciel
    ("foam",      [(236, 250, 246), (196, 232, 230)]),
    ("sea",       [(64, 150, 210), (32, 120, 154), (23, 78, 118)]),
    ("sky",       [(150, 214, 236), (255, 200, 140)]),
    # Sable / pierre
    ("sand",      [(238, 202, 128), (214, 168, 96), (178, 130, 74)]),
    ("stone",     [(164, 156, 152), (120, 112, 116), (82, 74, 84)]),
    # Nuit (Phare) / violet / rose
    ("night",     [(108, 132, 156), (44, 60, 110), (28, 34, 66)]),
    ("purple",    [(160, 112, 176), (120, 80, 140)]),
    ("pink",      [(246, 166, 176), (214, 104, 130)]),
])

# Alias historiques (tools/legacy, décors) : nom -> (rampe, index)
ALIASES = {
    "white": ("linen", 0), "cream": ("linen", 1), "cream_shade": ("linen", 2),
    "black": ("ink", 0), "skin": ("skin_a", 1), "skin_shade": ("skin_a", 2),
    "red_dark": ("red", 2), "green_dark": ("green", 2), "gold": ("yellow", 1),
    "gold_dark": ("yellow", 2), "sea_deep": ("sea", 2), "sea_mid": ("sea", 1),
    "sea_turquoise": ("turquoise", 1), "sea_foam": ("foam", 0),
    "sky_high": ("sea", 0), "sky_low": ("sky", 0), "sky_dawn": ("sky", 1),
    "sand_shade": ("sand", 1), "sand_dark": ("sand", 2), "rock": ("stone", 1),
    "rock_light": ("stone", 0), "rock_dark": ("stone", 2), "rope": ("wood", 0),
    "sky_night": ("night", 1), "grey_blue": ("night", 0), "earth": ("wood", 1),
}

PALETTE = OrderedDict()
for _name, _ramp in RAMPS.items():
    if len(_ramp) == 1:
        PALETTE[_name] = _ramp[0]
    for _i, _c in enumerate(_ramp):
        PALETTE[f"{_name}_{_i}"] = _c
for _alias, (_ramp_name, _idx) in ALIASES.items():
    PALETTE.setdefault(_alias, RAMPS[_ramp_name][_idx])
for _name, _ramp in RAMPS.items():
    PALETTE.setdefault(_name, _ramp[min(1, len(_ramp) - 1)])


def colors() -> list:
    """Liste ordonnée et dédupliquée de toutes les couleurs (≈ 64)."""
    out = []
    for ramp in RAMPS.values():
        for c in ramp:
            if c not in out:
                out.append(c)
    return out


def px(name: str) -> tuple:
    return PALETTE[name] + (255,)


def palette_image(path: str) -> None:
    """Écrit la palette en image N×1 (input_palette de Retro Diffusion)."""
    from PIL import Image
    cols = colors()
    img = Image.new("RGB", (len(cols), 1))
    for i, c in enumerate(cols):
        img.putpixel((i, 0), c)
    img.save(path)


if __name__ == "__main__":
    import os
    out = os.path.join(os.path.dirname(__file__), "palette.png")
    palette_image(out)
    print(len(colors()), "couleurs ->", out)
