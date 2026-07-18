#!/usr/bin/env python3
"""Génère le spritesheet de Louis (16x24 par frame) en pixel art.

Chaque frame est une grille ASCII : une lettre = une couleur de la palette.
Sortie : assets/sprites/louis.png (grille de frames, 1 rangée par animation)
+ louis_preview.png (zoom x8 pour contrôle visuel).
"""
from PIL import Image
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from palette import PALETTE

W, H = 16, 24

INK = {
    ".": None,
    "O": PALETTE["outline"],
    "B": PALETTE["red"],          # béret + ceinture
    "D": PALETTE["red_dark"],     # ombre du béret
    "S": PALETTE["skin"],
    "T": PALETTE["skin_shade"],
    "H": (236, 200, 116),   # blond doré
    "W": PALETTE["white"],        # chemise
    "V": PALETTE["cream_shade"],  # ombre chemise
    "C": PALETTE["cream"],        # pantalon
    "U": PALETTE["sand_dark"],    # ombre pantalon
    "E": PALETTE["rope"],         # espadrilles
    "K": PALETTE["black"],
}

# --- Tête commune (rangées 0..10), béret basque penché ---
HEAD = [
    "......OOOOO.....",
    "....OOBBBBBO....",
    "...OBBBBBBBBO...",
    "..OBBBBBBBBBBO..",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO...",
    "...OSSSSSSSSO...",
    "...OTSSSSSSTO...",
    "....OSSTTSSO....",
]

def frame(rows):
    assert len(rows) == H, f"{len(rows)} rangées"
    for r in rows:
        assert len(r) == W, f"'{r}' fait {len(r)}"
    return rows

IDLE_1 = frame(HEAD + [
    "....OOWWWWO.....",
    "...OWWWWWWWO....",
    "...OWSWWWWSO....",
    "...OWWWWWWWO....",
    "...OBBBBBBBO....",
    "...OCCCCCCCO....",
    "....OCCOCCO.....",
    "....OCCOCCO.....",
    "....OCCOCCO.....",
    "....OUCOUCO.....",
    "....OEEOEEO.....",
    "....OOOOOOO.....",
    "................",
])

IDLE_2 = frame(HEAD + [
    "....OOWWWWO.....",
    "...OWWWWWWWO....",
    "...OWSWWWWSO....",
    "...OWWWWWWWO....",
    "...OBBBBBBBO....",
    "...OCCCCCCCO....",
    "....OCCOCCO.....",
    "....OCCOCCO.....",
    "....OUCOUCO.....",
    "....OEEOEEO.....",
    "....OOOOOOO.....",
    "................",
    "................",
])

# --- Course : 6 frames, jambes en ciseaux, bras balancés ---
RUN_1 = frame(HEAD + [
    "....OWWWWWO.....",
    "..OSOWWWWWOSO...",
    "..OOOWWWWWOOO...",
    "....OWWWWWO.....",
    "....OBBBBBO.....",
    "....OCCCCCO.....",
    "...OCCO.OCCO....",
    "..OCCO...OCCO...",
    "..OUCO....OCU...",
    "..OEEO....OEEO..",
    "..OOO......OOO..",
    "................",
    "................",
])

RUN_2 = frame(HEAD + [
    "....OWWWWWO.....",
    "...OSWWWWWSO....",
    "...OOWWWWWOO....",
    "....OWWWWWO.....",
    "....OBBBBBO.....",
    "....OCCCCCO.....",
    "....OCCOCCO.....",
    "...OCCO.OCCO....",
    "...OUCO.OCUO....",
    "...OEEO.OEEO....",
    "...OOO...OOO....",
    "................",
    "................",
])

RUN_3 = frame(HEAD + [
    "....OWWWWWO.....",
    "....OWWWWWO.....",
    "...OSWWWWWSO....",
    "....OWWWWWO.....",
    "....OBBBBBO.....",
    "....OCCCCCO.....",
    "....OCCCCCO.....",
    "....OCCOCCO.....",
    "....OUCOUCO.....",
    "....OEEOEEO.....",
    "....OOO.OOO.....",
    "................",
    "................",
])

RUN_4 = frame(HEAD + [
    "....OWWWWWO.....",
    "..OSOWWWWWOSO...",
    "..OOOWWWWWOOO...",
    "....OWWWWWO.....",
    "....OBBBBBO.....",
    "....OCCCCCO.....",
    "...OCCO.OCCO....",
    "..OCCO...OCCO...",
    "..OCUO....OCUO..",
    "..OEEO....OEEO..",
    "...OOO....OOO...",
    "................",
    "................",
])

# saut : bras en l'air, jambes repliées
JUMP = frame([
    "......OOOOO.....",
    "..O.OOBBBBBO.O..",
    ".OSOBBBBBBBBOSO.",
    ".OOOBBBBBBBBOOO.",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO...",
    "...OSSSSSSSSO...",
    "...OTSSSSSSTO...",
    "....OSSTTSSO....",
    "....OWWWWWO.....",
    "...OWWWWWWWO....",
    "...OWWWWWWWO....",
    "....OBBBBBO.....",
    "....OCCCCCO.....",
    "...OCCCOCCCO....",
    "...OCCO.OCCO....",
    "...OEEO.OEEO....",
    "...OOO...OOO....",
    "................",
    "................",
    "................",
    "................",
])

# chute : bras écartés, jambes tendues
FALL = frame(HEAD + [
    "....OWWWWWO.....",
    ".OSOWWWWWWWOSO..",
    ".OOOWWWWWWWOOO..",
    "....OWWWWWO.....",
    "....OBBBBBO.....",
    "....OCCCCCO.....",
    "....OCCOCCO.....",
    "....OCCOCCO.....",
    "....OUCOUCO.....",
    "....OEEOEEO.....",
    "....OOO.OOO.....",
    "................",
    "................",
])

# touché : étoiles, assis
HIT = frame([
    "................",
    "......OOOOO.....",
    "....OOBBBBBO....",
    "...OBBBBBBBBO...",
    "..OBBBBBBBBBBO..",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO...",
    "...OSTTSSTTSO...",
    "...OTSSSSSSTO...",
    "....OSSTTSSO....",
    "...OWWWWWWWO....",
    "..OSWWWWWWWSO...",
    "..OOWWWWWWWOO...",
    "...OBBBBBBBO....",
    "..OCCCCCCCCCO...",
    "..OCCCOOOCCCO...",
    "..OECO...OCEO...",
    "..OOO.....OOO...",
    "................",
    "................",
    "................",
    "................",
])

# surf : accroupi de profil sur planche (la planche est dans la scène)
SURF = frame([
    "................",
    "................",
    "......OOOOO.....",
    "....OOBBBBBO....",
    "...OBBBBBBBBO...",
    "..OBBBBBBBBBBO..",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO...",
    "...OSSSSSSSSO...",
    "....OSSTTSSO....",
    "..OSOWWWWWO.....",
    "..OOWWWWWWWO....",
    "....OWWWWWWOSO..",
    "....OBBBBBOOO...",
    "....OCCCCCCO....",
    "...OCCCOOCCCO...",
    "...OCCO..OCCO...",
    "...OEEO..OEEO...",
    "...OOO....OOO...",
    "................",
    "................",
    "................",
])


# pêche : assis de profil, canne (2 frames : canne haute / basse)
FISH_1 = frame([
    "................",
    "......OOOOO.....",
    "....OOBBBBBO....",
    "...OBBBBBBBBO...",
    "..OBBBBBBBBBBO..",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO.O.",
    "...OSSSSSSSSOEO.",
    "...OTSSSSSSTOEO.",
    "....OSSTTSSOEO..",
    "....OWWWWWWOEO..",
    "...OWWWWWWWSEO..",
    "...OWWWWWWOOO...",
    "...OBBBBBBBO....",
    "..OCCCCCCCCCO...",
    "..OCCCCCCCCCO...",
    "..OCCOOOOOCCO...",
    "..OECO...OCEO...",
    "..OOO.....OOO...",
    "................",
    "................",
    "................",
])

FISH_2 = frame([
    "................",
    "......OOOOO.....",
    "....OOBBBBBO....",
    "...OBBBBBBBBO...",
    "..OBBBBBBBBBBO..",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO...",
    "...OSSSSSSSSO...",
    "...OTSSSSSSTO.O.",
    "....OSSTTSSO.EO.",
    "....OWWWWWWOEO..",
    "...OWWWWWWWSEO..",
    "...OWWWWWWOOO...",
    "...OBBBBBBBO....",
    "..OCCCCCCCCCO...",
    "..OCCCCCCCCCO...",
    "..OCCOOOOOCCO...",
    "..OECO...OCEO...",
    "..OOO.....OOO...",
    "................",
    "................",
    "................",
])

# lancer : bras arrière avec espadrille, puis bras avant
THROW_1 = frame([
    "......OOOOO.....",
    "....OOBBBBBO....",
    "...OBBBBBBBBO...",
    "..OBBBBBBBBBBO..",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO...",
    "...OSSSSSSSSO...",
    "...OTSSSSSSTO...",
    "....OSSTTSSO....",
    "OEEOOWWWWWO.....",
    "OEEOSWWWWWWO....",
    ".OOOOWWWWWWO....",
    "....OWWWWWWOSO..",
    "....OBBBBBOOO...",
    "....OCCCCCO.....",
    "...OCCCOCCCO....",
    "...OCCO.OCCO....",
    "...OUCO.OCUO....",
    "...OEEO.OEEO....",
    "...OOO...OOO....",
    "................",
    "................",
])

THROW_2 = frame([
    "......OOOOO.....",
    "....OOBBBBBO....",
    "...OBBBBBBBBO...",
    "..OBBBBBBBBBBO..",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO...",
    "...OSSSSSSSSO...",
    "...OTSSSSSSTO...",
    "....OSSTTSSO....",
    "....OWWWWWOOSOO.",
    "...OWWWWWWWOOO..",
    "...OWWWWWWWO....",
    "...OWWWWWWO.....",
    "....OBBBBBO.....",
    "....OCCCCCO.....",
    "...OCCCOCCCO....",
    "..OCCO...OCCO...",
    "..OUCO...OCUO...",
    "..OEEO...OEEO...",
    "..OOO.....OOO...",
    "................",
    "................",
])

# escalade : bras alternés vers le haut
CLIMB_1 = frame([
    "..OSO.OOOOO.....",
    "..OOOOBBBBBO....",
    "...OBBBBBBBBO...",
    "..OBBBBBBBBBBO..",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO...",
    "...OSSSSSSSSO...",
    "...OTSSSSSSTO...",
    "....OSSTTSSO....",
    "....OWWWWWO.....",
    "...OWWWWWWWOSO..",
    "...OWWWWWWWOOO..",
    "....OWWWWWO.....",
    "....OBBBBBO.....",
    "....OCCCCCO.....",
    "...OCCCOCCO.....",
    "...OCCO.OCCO....",
    "...OUCO..OCUO...",
    "...OEEO..OEEO...",
    "...OOO....OOO...",
    "................",
    "................",
])

CLIMB_2 = frame([
    ".....OOOOO.OSO..",
    "....OBBBBBOOOO..",
    "...OBBBBBBBBO...",
    "..OBBBBBBBBBBO..",
    "..ODDBBBBBBDDO..",
    "...OOHHHHHOO....",
    "...OHSSSSSSHO...",
    "...OSSKSSKSSO...",
    "...OSSSSSSSSO...",
    "...OTSSSSSSTO...",
    "....OSSTTSSO....",
    "....OWWWWWO.....",
    ".OSOWWWWWWWO....",
    ".OOOWWWWWWWO....",
    "....OWWWWWO.....",
    "....OBBBBBO.....",
    "....OCCCCCO.....",
    ".....OCCOCCCO...",
    "....OCCO.OCCO...",
    "...OCUO...OCU...",
    "...OEEO...OEEO..",
    "....OOO...OOO...",
    "................",
    "................",
])

ANIMS = [
    ("idle", [IDLE_1, IDLE_2]),
    ("run", [RUN_1, RUN_2, RUN_3, RUN_2, RUN_4, RUN_3]),
    ("jump", [JUMP]),
    ("fall", [FALL]),
    ("hit", [HIT]),
    ("surf", [SURF]),
    ("fish", [FISH_1, FISH_2]),
    ("throw", [THROW_1, THROW_2]),
    ("climb", [CLIMB_1, CLIMB_2]),
]


def draw_frame(img, ox, oy, rows):
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            color = INK[ch]
            if color is not None:
                img.putpixel((ox + x, oy + y), color + (255,))


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
    os.makedirs(out_dir, exist_ok=True)
    max_frames = max(len(frames) for _, frames in ANIMS)
    sheet = Image.new("RGBA", (W * max_frames, H * len(ANIMS)), (0, 0, 0, 0))
    for row, (name, frames) in enumerate(ANIMS):
        for col, fr in enumerate(frames):
            draw_frame(sheet, col * W, row * H, fr)
    sheet.save(os.path.join(out_dir, "louis.png"))

    preview = sheet.resize((sheet.width * 8, sheet.height * 8), Image.NEAREST)
    bg = Image.new("RGBA", preview.size, PALETTE["sand"] + (255,))
    bg.alpha_composite(preview)
    bg.save("/private/tmp/claude-501/-Users-julien-Dev-miarritze/67304e46-0e41-4582-88cc-ff9cd5e3783a/scratchpad/louis_preview.png")
    print("louis.png:", sheet.size, "| animations:", [(n, len(f)) for n, f in ANIMS])


if __name__ == "__main__":
    main()
