#!/usr/bin/env python3
"""Props pixel art : obstacles, cibles, poissons, plateformes, icônes.
Chaque sprite est une grille ASCII (1 lettre = 1 couleur de palette.py).
Sortie : assets/sprites/<nom>.png (+ contact sheet de contrôle)."""
from PIL import Image
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from palette import PALETTE

INK = {
    ".": None,
    "O": PALETTE["outline"],
    "K": PALETTE["black"],
    "W": PALETTE["white"],
    "C": PALETTE["cream"],
    "V": PALETTE["cream_shade"],
    "R": PALETTE["red"],
    "D": PALETTE["red_dark"],
    "G": PALETTE["green"],
    "H": PALETTE["green_dark"],
    "Y": PALETTE["gold"],
    "y": PALETTE["gold_dark"],
    "S": PALETTE["sand"],
    "s": PALETTE["sand_shade"],
    "u": PALETTE["sand_dark"],
    "E": PALETTE["rope"],
    "B": PALETTE["sea_mid"],
    "b": PALETTE["sea_deep"],
    "T": PALETTE["sea_turquoise"],
    "F": PALETTE["sea_foam"],
    "P": PALETTE["rock"],
    "p": PALETTE["rock_light"],
    "q": PALETTE["rock_dark"],
    "N": PALETTE["brick"],
    "n": PALETTE["brick_dark"],
    "M": PALETTE["wood"],
    "m": PALETTE["wood_dark"],
    "L": PALETTE["leaf"],
    "l": PALETTE["leaf_dark"],
    "A": PALETTE["orange"],
    "g": PALETTE["grey_blue"],
    "X": PALETTE["skin"],
}

SPRITES = {}

SPRITES["crab"] = [
    "..O..........O..",
    ".OROO......OORO.",
    ".ORRO..OO..ORRO.",
    "..OO.ORRRRO.OO..",
    "...ORRRRRRRRO...",
    "..ORKRRRRRKRRO..",
    "..ORRRRRRRRRRO..",
    "...ODRRRRRRDO...",
    "....OO.OO.OO....",
    "...O..O..O..O...",
]

SPRITES["sandcastle"] = [
    "....O..OO..O....",
    "...OROssssORO...",
    "....OssssssO....",
    "..OssOssssOssO..",
    "..OssssssssssO..",
    "..OsusssssussO..",
    ".OssssOssOssssO.",
    ".OsusssssssussO.",
    ".OsssssussssssO.",
    "OssusssssssussSO",
    "OsssssussssssssO",
    "OuusssususssuuuO",
    "OOOOOOOOOOOOOOOO",
]

SPRITES["parasol"] = [
    ".......OO.......",
    ".....OORROO.....",
    "...OORRWWRROO...",
    "..ORRWWRRWWRRO..",
    ".ORRWWRRRRWWRRO.",
    "OWWRRWWRRWWRRWWO",
    "OOOOOOOMOOOOOOOO",
    ".......OMO......",
    ".......OMO......",
    ".......OMO......",
    ".......OMO......",
    ".......OMO......",
    ".......OMO......",
    ".......OO.......",
]

SPRITES["coin"] = [
    "...OOOO...",
    "..OYYYYO..",
    ".OYyYYyYO.",
    ".OYYYYYYO.",
    ".OYYGYYYO.",
    ".OYYGYYYO.",
    ".OYyYYyYO.",
    "..OYYYYO..",
    "...OOOO...",
]

SPRITES["gull_1"] = [
    "OO..........OO",
    ".OWO..OO..OWO.",
    "..OWWOWWOWWO..",
    "...OWWWWWWO...",
    "....OWKWAO....",
    ".....OOOO.....",
]

SPRITES["gull_2"] = [
    "..............",
    "......OO......",
    "..OOOWWWWOOO..",
    ".OWWWWWWWWWWO.",
    "....OWKWAO....",
    ".....OOOO.....",
]

SPRITES["fish_sardine"] = [
    "..OOOO....O.",
    ".OggFgOO.OO.",
    "OgKgggggOgO.",
    ".OggFggOOgO.",
    "..OOOO....O.",
]

SPRITES["fish_dorade"] = [
    "...OOOOO.....O..",
    "..OTTTTTOO..OO..",
    ".OTKTTTTTTOOTO..",
    ".OTTTTFFTTTTTO..",
    "..OTTTTTTOOTO...",
    "...OOOOO....O...",
]

SPRITES["fish_thon"] = [
    "....OOOOOO......O...",
    "..OObbbbbbOO...OO...",
    ".ObKbbggbbbbOObbO...",
    ".Obbbbbbggbbbbbbb...",
    ".ObbFbbbbbbbOObbO...",
    "..OObbbbbbOO...OO...",
    "....OOOOOO......O...",
]

SPRITES["fish_dore"] = [
    "...OOOOO.....O..",
    "..OYYYYYOO..OO..",
    ".OYKYyYYYYOOYO..",
    ".OYYYYFFYyYYYO..",
    "..OYYYYYYOOYO...",
    "...OOOOO....O...",
]

SPRITES["buoy"] = [
    "....OO....",
    "...OWWO...",
    "..ORRRRO..",
    ".ORRRRRRO.",
    ".ORWWWWRO.",
    ".ORRRRRRO.",
    "..ORRRRO..",
    "...OOOO...",
]

SPRITES["can"] = [
    "..OOOO..",
    ".OppppO.",
    ".OPKKPO.",
    ".OPPPPO.",
    ".OpNNpO.",
    ".OPNNPO.",
    ".OPPPPO.",
    ".OqqqqO.",
    "..OOOO..",
]

SPRITES["espadrille_shoe"] = [
    "....OOOOOO..",
    "..OOWWWWWWO.",
    ".ORWWWWWWWO.",
    "OEEEEEEEEEO.",
    ".OOOOOOOOO..",
]

SPRITES["boat"] = [
    "........O.......",
    "........OO......",
    "....OOOOWWO.....",
    "....OWWWWWO.....",
    "........OO......",
    "OOOOOOOOOOOOOOOO",
    ".ORRRRRRRRRRRO..",
    "..OWWWWWWWWWO...",
    "...OOOOOOOOO....",
]

SPRITES["rock_platform"] = [
    "....OOOOOOOOOOOOOOOO....",
    "..OOppppppPPPPppppppOO..",
    ".OpppppPPPPPPPPPPpppppO.",
    "OpppPPPPPPqqPPPPPPPPppO.",
    "OppPPPqqPPPPPPqqPPPPppO.",
    ".OPPPPPPPPqqPPPPPPPPPO..",
    "..OqqPPPPPPPPPPPqqqOO...",
    "....OOOqqqqqqqqOOO......",
    ".......OOOOOOOO.........",
]

SPRITES["ledge"] = [
    "OOOOOOOOOOOOOOOOOOOOOOOOOOOO",
    "OWWWWWWWWWWWWWWWWWWWWWWWWWWO",
    "OCCCCCCCCCCCCCCCCCCCCCCCCCCO",
    "OKKKKKKKKKKKKKKKKKKKKKKKKKKO",
    ".OOOOOOOOOOOOOOOOOOOOOOOOOO.",
]

SPRITES["surfboard"] = [
    "..OOOOOOOOOOOOOOOOOOOO....",
    ".OWWWWWWRRWWWWWWWWWWWWOO..",
    "OWWWWWWWRRWWWWWWWWWWWWWWO.",
    ".OVVVVVVVVVVVVVVVVVVVVOO..",
    "..OOOOOOOOOOOOOOOOOOOO....",
]

SPRITES["statue"] = [
    "......OO......",
    ".....OWWO.....",
    ".....OWWO.....",
    "....OWWWWO....",
    "...OWWWWWWO...",
    "...OWWWWWWO...",
    "..OWWOWWOWWO..",
    "..OWWWWWWWWO..",
    "...OWWWWWWO...",
    "...OWWWWWWO...",
    "...OWWWWWWO...",
    "..OWWWWWWWWO..",
    "..OWWWWWWWWO..",
    ".OWWWWWWWWWWO.",
    ".OppppppppppO.",
    "OppppppppppppO",
    "OOOOOOOOOOOOOO",
]

SPRITES["bush"] = [
    "....OOOO..OOO....",
    "..OOLLLLOOLLLOO..",
    ".OLLLLlLLLLlLLLO.",
    "OLLlLLLLLlLLLLLlO",
    "OLlLLLlLLLLLlLLLO",
    ".OLLLLLLlLLLLLLO.",
    "..OOlLLLLLlLOO...",
    "....OOOOOOOO.....",
]

SPRITES["cloud"] = [
    "......OOOOOO..........",
    "...OOOWWWWWWOOO.......",
    ".OOWWWWWWWWWWWWOOOOO..",
    "OWWWWWWWWWWWWWWWWWWWO.",
    ".OOOOWWWWWWWWWWWOOOO..",
    ".....OOOOOOOOOOO......",
]

SPRITES["bobber"] = [
    "..OO..",
    ".ORRO.",
    ".OWWO.",
    "..OO..",
]

SPRITES["ikurrina"] = [   # drapeau basque
    "OOOOOOOOOOOOOOOO",
    "OGRRRRRGGRRRRRGO",
    "ORGRRRGWWGRRRGRO",
    "ORRGRGWWWWGRGRRO",
    "ORRRGGWWWWGGRRRO",
    "ORRGRGWWWWGRGRRO",
    "ORGRRRGWWGRRRGRO",
    "OGRRRRRGGRRRRRGO",
    "OOOOOOOOOOOOOOOO",
]

SPRITES["coin_2"] = [
    "...OOOO...",
    "..OyYYyO..",
    ".OYYYYYYO.",
    ".OYYGYYYO.",
    ".OYYGYYYO.",
    ".OYYGYYYO.",
    ".OYYYYYYO.",
    "..OyYYyO..",
    "...OOOO...",
]

SPRITES["coin_3"] = [
    "....OO....",
    "...OYYO...",
    "...OYYO...",
    "...OyYO...",
    "...OyYO...",
    "...OyYO...",
    "...OYYO...",
    "...OYYO...",
    "....OO....",
]

SPRITES["crab_2"] = [
    "..O..........O..",
    ".OROO......OORO.",
    ".ORRO..OO..ORRO.",
    "..OO.ORRRRO.OO..",
    "...ORRRRRRRRO...",
    "..ORKRRRRRKRRO..",
    "..ORRRRRRRRRRO..",
    "...ODRRRRRRDO...",
    "...OO..OO..OO...",
    "..O...O..O...O..",
]


def render(name, rows):
    w = max(len(r) for r in rows)
    img = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            c = INK[ch]
            if c is not None:
                img.putpixel((x, y), c + (255,))
    return img


def main():
    out = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
    os.makedirs(out, exist_ok=True)
    images = {}
    for name, rows in SPRITES.items():
        img = render(name, rows)
        img.save(os.path.join(out, f"{name}.png"))
        images[name] = img

    # Contact sheet de contrôle
    pad = 6
    cols = 6
    cell_w = max(i.width for i in images.values()) + pad
    cell_h = max(i.height for i in images.values()) + pad + 2
    rows_n = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell_w, rows_n * cell_h), PALETTE["sky_low"] + (255,))
    for i, (name, img) in enumerate(images.items()):
        x = (i % cols) * cell_w + pad // 2
        y = (i // cols) * cell_h + pad // 2
        sheet.alpha_composite(img, (x, y))
    sheet = sheet.resize((sheet.width * 5, sheet.height * 5), Image.NEAREST)
    sheet.save("/private/tmp/claude-501/-Users-julien-Dev-miarritze/67304e46-0e41-4582-88cc-ff9cd5e3783a/scratchpad/props_preview.png")
    print("props:", ", ".join(images), f"({len(images)} sprites)")


if __name__ == "__main__":
    main()
