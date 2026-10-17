#!/usr/bin/env python3
"""Génère les aperçus et l'index des assets pour le service /producer.

Usage : build_index.py <dossier_sortie>   (ex. web/build/producer/files)

- Lit assets/ en lecture seule.
- Sheets de combattants (PNG « L » indexé) : une planche par animation,
  colorisée avec palettes.png (costume 0), recadrée sur l'union des frames.
- Portraits indexés : colorisés de la même façon.
- Autres images : copiées telles quelles ; les effets d'un perso (assets/vfx/<id>)
  sont rangés dans son groupe de la catégorie Combattants.
- Audio : .ogg copié ; si ffmpeg est présent, un .mp3 est ajouté (Safari iOS
  ne lit pas toujours le Vorbis).
- index.json : liste des assets (id = chemin relatif à assets/), version =
  hash court des sources, commit git du build, et liste blanche des fichiers
  servis (le PHP ne sert rien d'autre).
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"

CAT_FIGHTERS = "Combattants"
CAT_VFX = "VFX"
CAT_STAGES = "Décors"
CAT_SPRITES = "Fonds & sprites"
CAT_UI = "UI"
CAT_MUSIC = "Musique"
CAT_SFX = "SFX"
CAT_VOICE = "Voix"
CATEGORIES = [CAT_FIGHTERS, CAT_VFX, CAT_STAGES, CAT_SPRITES, CAT_UI,
              CAT_MUSIC, CAT_SFX, CAT_VOICE]

# Fichiers de combattants ignorés (obsolètes, remplacés par les sheets RD).
SKIP_FIGHTER_FILES = {"sheet_mannequin.png"}


def short_hash(*paths: Path) -> str:
    h = hashlib.sha256()
    for p in paths:
        h.update(p.read_bytes())
    return h.hexdigest()[:10]


def git_commit() -> str:
    env_sha = os.environ.get("GITHUB_SHA", "")
    if env_sha:
        return env_sha[:7]
    try:
        out = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                             capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "inconnu"


class Builder:
    def __init__(self, out: Path) -> None:
        self.out = out
        self.assets: list[dict] = []
        self.files: list[str] = []
        self.has_ffmpeg = shutil.which("ffmpeg") is not None

    # -------------------------------------------------------------- utilitaires
    def _dest(self, rel: str) -> Path:
        dest = self.out / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        self.files.append(rel)
        return dest

    def save_png(self, img: Image.Image, rel: str) -> str:
        img.save(self._dest(rel), optimize=True)
        return rel

    def copy(self, src: Path, rel: str) -> str:
        shutil.copyfile(src, self._dest(rel))
        return rel

    @staticmethod
    def palette(path: Path) -> np.ndarray:
        """Ligne 0 (costume 0) de palettes.png, 32 couleurs RGBA ; index 0 transparent."""
        pal = np.array(Image.open(path).convert("RGBA"))[0].copy()
        pal[0] = (0, 0, 0, 0)
        full = np.zeros((256, 4), dtype=np.uint8)
        full[: len(pal)] = pal
        return full

    @staticmethod
    def colorize(idx: np.ndarray, pal: np.ndarray) -> Image.Image:
        return Image.fromarray(pal[idx], "RGBA")

    def add(self, **entry) -> None:
        self.assets.append(entry)

    # ---------------------------------------------------------------- combattants
    def fighters(self) -> None:
        for fdir in sorted(p for p in (ASSETS / "fighters").iterdir() if p.is_dir()):
            fid = fdir.name
            pal_path = fdir / "palettes.png"
            pal = self.palette(pal_path) if pal_path.exists() else None
            if pal is not None and (fdir / "sheet.png").exists() and (fdir / "anims.json").exists():
                self.sheet(fid, fdir, pal)
            for png in sorted(fdir.glob("*.png")):
                if png.name in SKIP_FIGHTER_FILES or png.name == "sheet.png":
                    continue
                rel_src = f"fighters/{fid}/{png.name}"
                if png.name == "palettes.png":
                    self.palette_asset(fid, png)
                    continue
                img = Image.open(png)
                version_srcs = [png]
                note = ""
                if img.mode == "L" and pal is not None:
                    out_img = self.colorize(np.array(img), pal)
                    version_srcs.append(pal_path)
                    note = "colorisé avec palettes.png (costume 0)"
                else:
                    out_img = img.convert("RGBA")
                f = self.save_png(out_img, rel_src)
                self.add(id=rel_src, cat=CAT_FIGHTERS, group=fid, name=f"{fid} · {png.stem}",
                         type="image", version=short_hash(*version_srcs),
                         w=out_img.width, h=out_img.height, file=f, preview=f, note=note)

    def sheet(self, fid: str, fdir: Path, pal: np.ndarray) -> None:
        meta = json.loads((fdir / "anims.json").read_text())
        cell = int(meta["cell"])
        cols = int(meta["cols"])
        idx = np.array(Image.open(fdir / "sheet.png"))
        rows_avail = idx.shape[0] // cell
        anims = []
        preview = ""
        for name, a in meta["anims"].items():
            first, count = int(a["first"]), int(a["frames"])
            frames = []
            for i in range(first, first + count):
                r, c = divmod(i, cols)
                if r >= rows_avail:
                    break
                frames.append(idx[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell])
            if not frames:
                continue
            # Recadrage sur l'union des pixels non vides (les frames restent alignées).
            mask = np.any(np.stack(frames) > 0, axis=0)
            ys, xs = np.nonzero(mask)
            if len(ys) == 0:
                y0, y1, x0, x1 = 0, cell, 0, cell
            else:
                y0, y1 = max(ys.min() - 2, 0), min(ys.max() + 3, cell)
                x0, x1 = max(xs.min() - 2, 0), min(xs.max() + 3, cell)
            w, h = int(x1 - x0), int(y1 - y0)
            strip = np.concatenate([fr[y0:y1, x0:x1] for fr in frames], axis=1)
            f = self.save_png(self.colorize(strip, pal), f"fighters/{fid}/sheet/{name}.png")
            anims.append({"name": name, "frames": len(frames), "fps": int(a.get("fps", 10)),
                          "loop": bool(a.get("loop", False)), "w": w, "h": h, "file": f})
            if name == "idle" or not preview:
                preview_img = self.colorize(frames[0][y0:y1, x0:x1], pal)
                preview = self.save_png(preview_img, f"fighters/{fid}/sheet/_preview.png")
        rel = f"fighters/{fid}/sheet.png"
        self.add(id=rel, cat=CAT_FIGHTERS, group=fid, name=f"{fid} · animations",
                 type="sprite", version=short_hash(fdir / "sheet.png", fdir / "palettes.png",
                                                   fdir / "anims.json"),
                 w=cell, h=cell, file=preview, preview=preview, anims=anims,
                 note=f"sheet {idx.shape[1]}×{idx.shape[0]}, cellule {cell}, colorisée costume 0")

    def palette_asset(self, fid: str, png: Path) -> None:
        img = Image.open(png).convert("RGBA")
        # Agrandie ×8 pour la lisibilité (32 index × 4 costumes).
        big = img.resize((img.width * 8, img.height * 8), Image.NEAREST)
        rel = f"fighters/{fid}/palettes.png"
        f = self.save_png(big, rel)
        self.add(id=rel, cat=CAT_FIGHTERS, group=fid, name=f"{fid} · palettes",
                 type="image", version=short_hash(png), w=big.width, h=big.height,
                 file=f, preview=f, note="32 index × 4 costumes (agrandi ×8)")

    # -------------------------------------------------------------- images simples
    def images(self, sub: str, cat: str, group_from_dir: bool) -> None:
        base = ASSETS / sub
        if not base.exists():
            return
        for png in sorted(base.rglob("*.png")):
            rel = png.relative_to(ASSETS).as_posix()
            img = Image.open(png)
            f = self.copy(png, rel)
            group = png.parent.name if group_from_dir else sub
            c = cat
            if sub == "vfx" and (ASSETS / "fighters" / group).is_dir():
                c = CAT_FIGHTERS     # effets d'un perso : sur sa page, avec ses animations
            self.add(id=rel, cat=c, group=group, name=f"{group} · {'effet · ' if c != cat else ''}{png.stem}" if group_from_dir else png.stem,
                     type="image", version=short_hash(png), w=img.width, h=img.height,
                     file=f, preview=f, note="")

    # ----------------------------------------------------------------------- audio
    @staticmethod
    def _md_parts(cell: str) -> list:
        """Cellule markdown → [{t}, {t, url}] (liens https seulement, gras retiré)."""
        import re
        cell = cell.replace("**", "").replace("*", "").replace("`", "").strip()
        parts, pos = [], 0
        for m in re.finditer(r"\[([^\]]+)\]\((https://[^)\s]+)\)", cell):
            if m.start() > pos:
                parts.append({"t": cell[pos:m.start()]})
            parts.append({"t": m.group(1), "url": m.group(2)})
            pos = m.end()
        if pos < len(cell):
            parts.append({"t": cell[pos:]})
        return parts

    def music_credits(self) -> dict:
        """Attribution par morceau, lue dans les tableaux de docs/MUSIC.md."""
        doc = ROOT / "docs" / "MUSIC.md"
        out: dict = {}
        if not doc.exists():
            return out
        header = None
        for line in doc.read_text(encoding="utf-8").splitlines():
            if not line.startswith("|"):
                header = None
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if header is None:
                header = cells
                continue
            if set(line) <= set("|-: "):
                continue
            key = cells[0].strip("`").removeprefix("music/").removesuffix(".ogg")
            if not key or " " in key:
                continue
            out[key] = [{"label": h.replace("`", ""), "parts": self._md_parts(c)}
                        for h, c in zip(header[1:], cells[1:]) if c]
        out.setdefault("hegoak", [
            {"label": "Air", "parts": [{"t": "Hegoak (Txoria txori), musique de Mikel Laboa"}]},
            {"label": "Droits", "parts": [{"t": "Œuvre protégée : arrangement de l'ancien jeu, rétabli sur l'accueil à la demande de Julien (2026-10-13)"}]},
        ])
        return out

    def audio(self, sub: str, cat: str) -> None:
        credits = self.music_credits() if sub == "music" else {}
        original = [{"label": "Origine", "parts": [{"t": "Composition et synthèse originales (tools/gen_audio.py)"}]}]
        base = ASSETS / "audio" / sub
        if not base.exists():
            return
        for src in sorted(list(base.glob("*.ogg")) + list(base.glob("*.mp3")) + list(base.glob("*.wav"))):
            rel = src.relative_to(ASSETS).as_posix()
            sources = [self.copy(src, rel)]
            if self.has_ffmpeg and src.suffix == ".ogg":
                mp3_rel = rel[:-4] + ".mp3"
                dest = self._dest(mp3_rel)
                res = subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(src),
                                      "-codec:a", "libmp3lame", "-q:a", "5", str(dest)])
                if res.returncode == 0:
                    sources.append(mp3_rel)
                else:
                    self.files.remove(mp3_rel)
            self.add(id=rel, cat=cat, group=sub, name=src.stem, type="audio",
                     version=short_hash(src), file=sources[0], sources=sources,
                     preview="", note="", credits=credits.get(src.stem, original))

    def run(self) -> None:
        if self.out.exists():
            shutil.rmtree(self.out)
        self.out.mkdir(parents=True)
        self.fighters()
        self.images("vfx", CAT_VFX, True)
        self.images("stages", CAT_STAGES, True)
        self.images("sprites", CAT_SPRITES, False)
        self.images("ui", CAT_UI, False)
        self.audio("music", CAT_MUSIC)
        self.audio("sfx", CAT_SFX)
        self.audio("voice", CAT_VOICE)
        def rank(a):
            if a["cat"] != CAT_FIGHTERS:
                return (1, "", 0, a["id"])
            n = a["id"].rsplit("/", 1)[-1]
            k = 0 if a["type"] == "sprite" else 1 if n.startswith("portrait") else 2 if n.startswith("ending") \
                else 4 if a["id"].startswith("vfx/") else 3
            return (0, a["group"], k, a["id"])
        self.assets.sort(key=rank)
        index = {
            "commit": git_commit(),
            "generated_at": int(time.time()),
            "categories": CATEGORIES,
            "assets": self.assets,
            "files": sorted(set(self.files)),
        }
        (self.out / "index.json").write_text(json.dumps(index, ensure_ascii=False, separators=(",", ":")))
        print(f"producer : {len(self.assets)} assets, {len(index['files'])} fichiers -> {self.out}")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    Builder(Path(sys.argv[1]).resolve()).run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
