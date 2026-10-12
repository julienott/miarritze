#!/usr/bin/env python3
"""Police bitmap « euskal letra » (SPEC-BORROKA §10.3).

Lettrage basque traditionnel des frontons et linteaux : pleins de 2 px,
empattements triangulaires (deux rangées en coin), dessiné à la main en
grilles ASCII (méthode de tools/legacy/gen_louis.py).

Cellule 12×16 : 2 rangées en haut pour les accents, 12 rangées de corps
(ligne de base = rangée 14), 2 rangées de jambage (virgule, cédille).
Avance variable = largeur du glyphe + 1.

Sorties (BMFont texte, importées par Godot 4 comme FontFile) :
  assets/fonts/euskal.fnt / euskal.png          blanc sur transparent (à teinter)
  assets/fonts/euskal_outline.fnt / .png        blanc + contour outline 1 px intégré
  tests/out/ui/font_sheet.png                   planche ×4
Usage : python3 tools/gen_font.py
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from palette import PALETTE  # noqa: E402

CELL_H = 16
TOP = 2          # rangées réservées aux accents
BASE = TOP + 12  # ligne de base

G = {}

G["A"] = [
    "....####....",
    "...######...",
    "...##..##...",
    "..##....##..",
    "..##....##..",
    "..##....##..",
    ".##########.",
    ".##......##.",
    ".##......##.",
    ".##......##.",
    ".###....###.",
    "#####..#####",
]
G["B"] = [
    "#########..",
    ".####...##.",
    "..##....##.",
    "..##....##.",
    "..##...##..",
    "..######...",
    "..##...##..",
    "..##....##.",
    "..##....##.",
    "..##....##.",
    ".####...##.",
    "#########..",
]
G["C"] = [
    "...#####..",
    "..##...###",
    ".##.....##",
    "##.......#",
    "##........",
    "##........",
    "##........",
    "##........",
    "##.......#",
    ".##.....##",
    "..##...###",
    "...#####..",
]
G["D"] = [
    "#######....",
    ".####.##...",
    "..##...##..",
    "..##....##.",
    "..##....##.",
    "..##....##.",
    "..##....##.",
    "..##....##.",
    "..##....##.",
    "..##...##..",
    ".####.##...",
    "#######....",
]
G["E"] = [
    "##########",
    ".####...##",
    "..##.....#",
    "..##......",
    "..##..#...",
    "..######..",
    "..##..#...",
    "..##......",
    "..##......",
    "..##.....#",
    ".####...##",
    "##########",
]
G["F"] = [
    "##########",
    ".####...##",
    "..##.....#",
    "..##......",
    "..##..#...",
    "..######..",
    "..##..#...",
    "..##......",
    "..##......",
    "..##......",
    ".####.....",
    "######....",
]
G["G"] = [
    "...#####...",
    "..##...###.",
    ".##.....##.",
    "##.......#.",
    "##.........",
    "##.........",
    "##...######",
    "##.....##..",
    "##.....##..",
    ".##....##..",
    "..##..###..",
    "...####.##.",
]
G["H"] = [
    "#####..#####",
    ".####..####.",
    "..##....##..",
    "..##....##..",
    "..##....##..",
    "..########..",
    "..##....##..",
    "..##....##..",
    "..##....##..",
    "..##....##..",
    ".####..####.",
    "#####..#####",
]
G["I"] = [
    "######",
    ".####.",
    "..##..",
    "..##..",
    "..##..",
    "..##..",
    "..##..",
    "..##..",
    "..##..",
    "..##..",
    ".####.",
    "######",
]
G["J"] = [
    "..#######",
    "....####.",
    ".....##..",
    ".....##..",
    ".....##..",
    ".....##..",
    ".....##..",
    ".....##..",
    "##...##..",
    "##...##..",
    ".##.##...",
    "..###....",
]
G["K"] = [
    "#####..#####",
    ".####...###.",
    "..##...##...",
    "..##..##....",
    "..##.##.....",
    "..####......",
    "..#####.....",
    "..##.###....",
    "..##..###...",
    "..##...###..",
    ".####...###.",
    "#####..#####",
]
G["L"] = [
    "######....",
    ".####.....",
    "..##......",
    "..##......",
    "..##......",
    "..##......",
    "..##......",
    "..##......",
    "..##......",
    "..##.....#",
    ".####...##",
    "##########",
]
G["M"] = [
    "####....####",
    ".###....###.",
    ".####..####.",
    ".##.####.##.",
    ".##..##..##.",
    ".##..##..##.",
    ".##......##.",
    ".##......##.",
    ".##......##.",
    ".##......##.",
    ".###....###.",
    "#####..#####",
]
G["N"] = [
    "####...#####",
    ".###....###.",
    ".####....##.",
    ".##.##...##.",
    ".##..##..##.",
    ".##..##..##.",
    ".##...##.##.",
    ".##...##.##.",
    ".##....####.",
    ".##.....###.",
    ".###.....##.",
    "#####....##.",
]
G["O"] = [
    "...#####...",
    "..##...##..",
    ".##.....##.",
    "##.......##",
    "##.......##",
    "##.......##",
    "##.......##",
    "##.......##",
    "##.......##",
    ".##.....##.",
    "..##...##..",
    "...#####...",
]
G["P"] = [
    "#########.",
    ".####...##",
    "..##....##",
    "..##....##",
    "..##...##.",
    "..######..",
    "..##......",
    "..##......",
    "..##......",
    "..##......",
    ".####.....",
    "######....",
]
G["Q"] = [
    "...#####...",
    "..##...##..",
    ".##.....##.",
    "##.......##",
    "##.......##",
    "##.......##",
    "##.......##",
    "##...#...##",
    "##...##..##",
    ".##...####.",
    "..##...###.",
    "...#####.##",
]
G["R"] = [
    "#########..",
    ".####...##.",
    "..##....##.",
    "..##....##.",
    "..##...##..",
    "..######...",
    "..##.##....",
    "..##..##...",
    "..##...##..",
    "..##....##.",
    ".####...###",
    "#####....##",
]
G["S"] = [
    "..######.#",
    ".##....###",
    "##......##",
    "##........",
    ".###......",
    "..######..",
    "......###.",
    "........##",
    "........##",
    "##......##",
    "###....##.",
    "#.######..",
]
G["T"] = [
    "############",
    "##...##...##",
    "#....##....#",
    ".....##.....",
    ".....##.....",
    ".....##.....",
    ".....##.....",
    ".....##.....",
    ".....##.....",
    ".....##.....",
    "....####....",
    "..########..",
]
G["U"] = [
    "#####..#####",
    ".###....###.",
    ".##......##.",
    ".##......##.",
    ".##......##.",
    ".##......##.",
    ".##......##.",
    ".##......##.",
    ".##......##.",
    "..##....##..",
    "...##..##...",
    "....####....",
]
G["V"] = [
    "#####..#####",
    ".###....###.",
    ".##......##.",
    ".##......##.",
    "..##....##..",
    "..##....##..",
    "..##....##..",
    "...##..##...",
    "...##..##...",
    "....####....",
    "....####....",
    ".....##.....",
]
G["W"] = [
    "####....####",
    ".##......##.",
    ".##......##.",
    ".##......##.",
    ".##..##..##.",
    ".##..##..##.",
    ".##..##..##.",
    ".##.####.##.",
    ".###.##.###.",
    ".####..####.",
    "..##....##..",
    "..#......#..",
]
G["X"] = [
    "#####..#####",
    ".###....###.",
    "..##....##..",
    "...##..##...",
    "....####....",
    ".....##.....",
    "....####....",
    "...##..##...",
    "..##....##..",
    ".##......##.",
    ".###....###.",
    "#####..#####",
]
G["Y"] = [
    "#####..#####",
    ".###....###.",
    "..##....##..",
    "...##..##...",
    "....####....",
    ".....##.....",
    ".....##.....",
    ".....##.....",
    ".....##.....",
    ".....##.....",
    "....####....",
    "..########..",
]
G["Z"] = [
    "##########",
    "##.....##.",
    "#.....##..",
    ".....##...",
    "....##....",
    "....##....",
    "...##.....",
    "..##......",
    ".##.......",
    "##.......#",
    "##......##",
    "##########",
]
G["0"] = [
    "..#####..",
    ".##...##.",
    "##.....##",
    "##....###",
    "##...####",
    "##..##.##",
    "##.##..##",
    "####...##",
    "###....##",
    "##.....##",
    ".##...##.",
    "..#####..",
]
G["1"] = [
    "...##...",
    "..###...",
    ".####...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    "...##...",
    ".######.",
    "########",
]
G["2"] = [
    ".######..",
    "##....##.",
    "#......##",
    ".......##",
    "......##.",
    ".....##..",
    "....##...",
    "...##....",
    "..##.....",
    ".##.....#",
    "##.....##",
    "#########",
]
G["3"] = [
    ".######..",
    "##....##.",
    "#......##",
    ".......##",
    "......##.",
    "...####..",
    "......##.",
    ".......##",
    ".......##",
    "#......##",
    "##....##.",
    ".######..",
]
G["4"] = [
    ".....###..",
    "....####..",
    "...##.##..",
    "..##..##..",
    ".##...##..",
    "##....##..",
    "##########",
    "......##..",
    "......##..",
    "......##..",
    ".....####.",
    "....######",
]
G["5"] = [
    "#########",
    "##.......",
    "##.......",
    "##.......",
    "#######..",
    "......##.",
    ".......##",
    ".......##",
    ".......##",
    "#......##",
    "##....##.",
    ".######..",
]
G["6"] = [
    "..######.",
    ".##....##",
    "##.......",
    "##.......",
    "##.......",
    "#######..",
    "##....##.",
    "##.....##",
    "##.....##",
    "##.....##",
    ".##...##.",
    "..#####..",
]
G["7"] = [
    "#########",
    "##.....##",
    "#.....##.",
    ".....##..",
    "....##...",
    "....##...",
    "...##....",
    "...##....",
    "...##....",
    "...##....",
    "..####...",
    ".######..",
]
G["8"] = [
    "..#####..",
    ".##...##.",
    "##.....##",
    "##.....##",
    ".##...##.",
    "..#####..",
    ".##...##.",
    "##.....##",
    "##.....##",
    "##.....##",
    ".##...##.",
    "..#####..",
]
G["9"] = [
    "..#####..",
    ".##...##.",
    "##.....##",
    "##.....##",
    "##.....##",
    ".##....##",
    "..#######",
    ".......##",
    ".......##",
    ".......##",
    "##....##.",
    ".######..",
]
G["!"] = [
    ".##.",
    "####",
    "####",
    "####",
    ".##.",
    ".##.",
    ".##.",
    ".##.",
    "....",
    ".##.",
    "####",
    ".##.",
]
G["?"] = [
    ".######..",
    "##....##.",
    "#......##",
    ".......##",
    "......##.",
    "....###..",
    "....##...",
    "....##...",
    ".........",
    "....##...",
    "...####..",
    "....##...",
]
G["'"] = ["##", "##", ".#", "#."] + [".."] * 8
G["."] = [".."] * 10 + ["##", "##"]
G[","] = [".."] * 10 + ["##", "##", ".#", "#."]          # 2 rangées de jambage
G[":"] = [".."] * 3 + ["##", "##"] + [".."] * 5 + ["##", "##"]
G["-"] = ["......"] * 5 + ["######", "######"] + ["......"] * 5
G["+"] = [
    "........",
    "........",
    "........",
    "...##...",
    "...##...",
    "########",
    "########",
    "...##...",
    "...##...",
    "........",
    "........",
    "........",
]
G["/"] = [
    "......##",
    "......##",
    ".....##.",
    ".....##.",
    "....##..",
    "....##..",
    "...##...",
    "...##...",
    "..##....",
    "..##....",
    ".##.....",
    ".##.....",
]
G["«"] = [
    ".........",
    ".........",
    ".........",
    "...##..##",
    "..##..##.",
    ".##..##..",
    "##..##...",
    ".##..##..",
    "..##..##.",
    "...##..##",
    ".........",
    ".........",
]
G["»"] = [row[::-1] for row in G["«"]]

# Accents : rangées au-dessus du corps (cellule 0–1), centrées sur le glyphe.
ACUTE = ["..##", ".##."]
GRAVE = ["##..", ".##."]
TILDE = [".##..#", "#..##."]
CEDILLA = ["..##.", "...##", ".###."]   # sous la ligne de base (rangées 14–16)

ACCENTED = {"É": ("E", ACUTE), "È": ("E", GRAVE), "À": ("A", GRAVE), "Ñ": ("N", TILDE)}

SPACE_ADVANCE = 6
OUTLINE = PALETTE["outline"]


def build_cell(ch):
    """Renvoie (largeur, liste de rangées de 16) pour un caractère."""
    if ch in ACCENTED:
        base, mark = ACCENTED[ch]
        rows = G[base]
        w = len(rows[0])
        cell = ["." * w] * CELL_H
        cell = list(cell)
        for i, r in enumerate(rows):
            cell[TOP + i] = r
        off = (w - len(mark[0])) // 2
        for i, r in enumerate(mark):
            cell[i] = "." * off + r + "." * (w - off - len(r))
        return w, cell
    if ch == "Ç":
        rows = G["C"]
        w = len(rows[0])
        cell = ["." * w] * CELL_H
        cell = list(cell)
        for i, r in enumerate(rows):
            cell[TOP + i] = r
        off = (w - len(CEDILLA[0])) // 2 - 1
        for i, r in enumerate(CEDILLA[:2]):
            cell[BASE + i] = "." * off + r + "." * (w - off - len(r))
        return w, cell
    rows = G[ch]
    w = len(rows[0])
    for r in rows:
        assert len(r) == w, f"glyphe {ch!r} : rangées de longueurs inégales"
    cell = ["." * w] * CELL_H
    cell = list(cell)
    for i, r in enumerate(rows[:CELL_H - TOP]):
        cell[TOP + i] = r
    return w, cell


CHARS = [c for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!?'.,:-+/«»"] + ["É", "È", "À", "Ç", "Ñ"]


def render(outline: bool):
    """Atlas + table BMFont. Contour : glyphe agrandi de 1 px de chaque côté."""
    pad = 1 if outline else 0
    cells = [(ch, *build_cell(ch)) for ch in CHARS]
    cols = 12
    cw = 12 + 2 * pad + 1
    ch_ = CELL_H + 2 * pad + 1
    rows_n = (len(cells) + cols - 1) // cols
    W = 1
    while W < cols * cw:
        W *= 2
    H = 1
    while H < rows_n * ch_:
        H *= 2
    atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = atlas.load()
    entries = []
    for k, (c, w, cell) in enumerate(cells):
        ox, oy = (k % cols) * cw, (k // cols) * ch_
        fill = set()
        for y, r in enumerate(cell):
            for x, v in enumerate(r):
                if v == "#":
                    fill.add((x, y))
        if outline:
            ring = set()
            for (x, y) in fill:
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        if (x + dx, y + dy) not in fill:
                            ring.add((x + dx, y + dy))
            for (x, y) in ring:
                px[ox + x + pad, oy + y + pad] = OUTLINE + (255,)
        for (x, y) in fill:
            px[ox + x + pad, oy + y + pad] = (255, 255, 255, 255)
        entries.append((ord(c), ox, oy, w + 2 * pad, CELL_H + 2 * pad, -pad, -pad, w + 1))
    return atlas, entries


def write_fnt(name, atlas, entries):
    fonts = os.path.join(ROOT, "assets", "fonts")
    os.makedirs(fonts, exist_ok=True)
    atlas.save(os.path.join(fonts, f"{name}.png"))
    lines = [
        f'info face="Euskal Letra" size={CELL_H} bold=0 italic=0 charset="" unicode=1 '
        f'stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=1,1 outline=0',
        f"common lineHeight={CELL_H + 2} base={BASE} scaleW={atlas.width} scaleH={atlas.height} "
        f"pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0",
        f'page id=0 file="{name}.png"',
        f"chars count={len(entries) + 1}",
        f"char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance={SPACE_ADVANCE} page=0 chnl=15",
    ]
    for (cid, x, y, w, h, xo, yo, adv) in entries:
        lines.append(f"char id={cid} x={x} y={y} width={w} height={h} xoffset={xo} "
                     f"yoffset={yo} xadvance={adv} page=0 chnl=15")
    with open(os.path.join(fonts, f"{name}.fnt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


# ------------------------------------------------------------------ utilitaires partagés

def glyph_mask(ch):
    """Masque booléen (liste de rangées) d'un caractère, cellule complète 16 px."""
    if ch == " ":
        return SPACE_ADVANCE - 1, [[False] * (SPACE_ADVANCE - 1) for _ in range(CELL_H)]
    w, cell = build_cell(ch)
    return w, [[v == "#" for v in r] for r in cell]


def text_mask(text, scale=1, spacing=1):
    """Masque d'une ligne de texte (pour le logo, les titres pré-rendus)."""
    parts = [glyph_mask(c) for c in text]
    width = sum(w + spacing for w, _ in parts) - spacing
    out = [[False] * (width * scale) for _ in range(CELL_H * scale)]
    x0 = 0
    for w, m in parts:
        for y in range(CELL_H):
            for x in range(w):
                if m[y][x]:
                    for sy in range(scale):
                        for sx in range(scale):
                            out[y * scale + sy][(x0 + x) * scale + sx] = True
        x0 += w + spacing
    return out


def preview(path, text_lines, scale=4):
    bg = (64, 70, 96, 255)
    rows = [text_mask(t) for t in text_lines]
    w = max(len(r[0]) for r in rows) + 8
    h = len(rows) * (CELL_H + 4) + 4
    img = Image.new("RGBA", (w, h), bg)
    px = img.load()
    y0 = 4
    colors = [PALETTE["red"], PALETTE["gold"], PALETTE["white"], PALETTE["sea_foam"]]
    for i, m in enumerate(rows):
        col = colors[i % len(colors)]
        for y, r in enumerate(m):
            for x, v in enumerate(r):
                if v:
                    px[4 + x, y0 + y] = col + (255,)
                    # contour
        for y, r in enumerate(m):
            for x, v in enumerate(r):
                if not v:
                    near = any(0 <= y + dy < len(m) and 0 <= x + dx < len(r) and m[y + dy][x + dx]
                               for dx in (-1, 0, 1) for dy in (-1, 0, 1))
                    if near:
                        px[4 + x, y0 + y] = OUTLINE + (255,)
        y0 += CELL_H + 4
    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


if __name__ == "__main__":
    for name, ol in (("euskal", False), ("euskal_outline", True)):
        atlas, entries = render(ol)
        write_fnt(name, atlas, entries)
    preview(os.path.join(ROOT, "tests", "out", "ui", "font_sheet.png"), [
        "ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "0123456789 !?'.,:-+/«»", "ÉÈÀÇÑ BORROKA ! TXAPELDUN !",
        "PLOUF ! BUKATU ! ZORIONAK !", "GRANDE PLAGE - CÔTE"[:12] + " 3 COUPS",
    ])
    print("police écrite :", len(CHARS), "glyphes")
