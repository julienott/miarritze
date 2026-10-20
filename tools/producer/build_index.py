#!/usr/bin/env python3
"""Génère les aperçus et l'index des assets pour le service /producer.

Usage : build_index.py <dossier_sortie>   (ex. web/build/producer/files)

- Lit assets/ en lecture seule.
- Sheets de combattants (PNG « L » indexé) : une planche par animation,
  colorisée avec palettes.png (costume 0), recadrée sur l'union des frames.
- Portraits indexés : colorisés de la même façon.
- Autres images : copiées telles quelles ; les effets d'un perso (assets/vfx/<id>)
  sont rangés dans son groupe de la catégorie Combattants.
- Gordeka (assets/gordeka, assets/maps) : animations des persos (planches d'une
  rangée de cases, recadrées sur l'union des frames) et leurs masques de tenue,
  profil validé (modele.png), profils candidats (tools/rd/out/<id>/gk2d/profil,
  réduits, seulement s'ils sont présents : dossier non versionné), pièces du
  mannequin, chorégraphies et données JSON, textures, aperçu de la carte rendu
  depuis map.txt.
- Décor de Gordeka (assets/gordeka/decor/index.json) : un asset par objet, avec un calque
  coloré tiré des masques pixelforge (masques/<id>/footprint.png en vert, occluder.png en
  violet, ground_contact.png en orange, alignés pixel pour pixel sur objets/<id>.png), la
  source des masques (pixelforge ou repli, tools/gordeka/masques/jeu/_sources.json), le
  contrôle du jeu (masques/jeu/<id>.png) et l'aperçu pixelforge ; un asset par sol.
- Animations attendues (tools/gordeka/prompts_anims.json, clé « animations ») et ordre des
  persos (clé « persos ») : dans index.json, clé « gordeka », pour les manquantes.
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
CAT_GK_PERSOS = "Persos"
CAT_GK_MAP = "Carte"
CAT_GK_MANNEQUIN = "Mannequin"
CAT_GK_DECOR = "Textures & modèles"
CAT_GK_OBJETS = "Décor"
# Sections de la barre latérale ; la page s'ouvre sur la première catégorie.
SECTIONS = [
    {"name": "Gordeka", "categories": [CAT_GK_PERSOS, CAT_GK_OBJETS, CAT_GK_MAP, CAT_GK_MANNEQUIN, CAT_GK_DECOR]},
    # Ancien jeu de combat : replié dans la barre latérale.
    {"name": "Borroka", "categories": [CAT_FIGHTERS, CAT_VFX, CAT_STAGES, CAT_SPRITES, CAT_UI], "collapsed": True},
    {"name": "Audio", "categories": [CAT_MUSIC, CAT_SFX, CAT_VOICE]},
]
CATEGORIES = [c for s in SECTIONS for c in s["categories"]]

GK = ASSETS / "gordeka"
GK_CANDIDATS = ROOT / "tools" / "gordeka" / "candidats"   # copies réduites versionnées (sync_candidats.py)
GK_MASQUES = ROOT / "tools" / "gordeka" / "masques"       # contrôles des formes du décor (masques_decor.py)
GK_PROMPTS = ROOT / "tools" / "gordeka" / "prompts_anims.json"   # animations attendues, ordre des persos
# Calques des masques du décor (RGBA) : emprise au sol, zone qui cache le perso, contact au sol.
GK_MASK_COLORS = (("occluder.png", (155, 89, 230, 115)), ("footprint.png", (40, 200, 80, 160)),
                  ("ground_contact.png", (255, 120, 0, 235)))
# Ordre des animations (tools/gordeka/anime_perso.py), les autres ensuite par nom.
GK_ANIM_ORDER = ["idle", "walk", "run_scared", "hide_in", "hide_out", "found", "trap", "trapped",
                 "search", "detect", "extract", "victory", "sad", "ghost", "ghost_move"]
GK_CANDIDAT_MAX = 512            # côté max des profils candidats (1024 à la source)
# Carte : couleurs de src/gordeka/gk_map.gd (COLORS, TILE_FLOORS, FLOOR_TINTS[0]) ;
# sortie, départ et inconnu choisis pour se voir.
MAP_TILE = 10
MAP_FONT = ASSETS / "fonts" / "press_start_2p.ttf"     # accents (Criée, Hangar à filets)
MAP_COLORS = {"#": "3b4253", "c": "a0703e", "B": "e8eef2", "H": "e08a2e", "t": "c9a873", "~": "2f7fb8",
              "R": "8c6446", "r": "9a7a5c", "v": "5f8a4a", ":": "e6cf98", "=": "b8b2a6", ".": "d9d2c3",
              "E": "3fae5a", "S": "8e5cc8"}
MAP_UNKNOWN = "ff00ff"

# Fichiers de combattants ignorés (obsolètes, remplacés par les sheets RD).
SKIP_FIGHTER_FILES = {"sheet_mannequin.png", "sheet.orig.png"}   # + sauvegarde avant nettoyage


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
        self.gk: dict = {"persos": [], "anims": [], "decor_a_venir": []}

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

    @staticmethod
    def rel_src(path: Path) -> str:
        """Id d'un asset : chemin relatif à assets/, ou au dépôt s'il est ailleurs."""
        try:
            return path.relative_to(ASSETS).as_posix()
        except ValueError:
            return path.relative_to(ROOT).as_posix()

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
            # Image fixe des vignettes : la case du milieu, plus parlante que la première.
            poster = self.save_png(self.colorize(frames[len(frames) // 2][y0:y1, x0:x1], pal),
                                   f"fighters/{fid}/sheet/_poster/{name}.png")
            anims.append({"name": name, "frames": len(frames), "fps": int(a.get("fps", 10)),
                          "loop": bool(a.get("loop", False)), "w": w, "h": h, "file": f, "poster": poster})
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

    # ==================================================================== Gordeka
    def gordeka(self) -> None:
        dirs = {p.name for p in (GK / "persos").iterdir() if p.is_dir()} if (GK / "persos").is_dir() else set()
        cands = {p.parents[1].name for p in GK_CANDIDATS.glob("*/*/image_*.png")}
        # Persos animés d'abord, puis ceux qui ont un profil validé, puis les candidats seuls.
        prompts = json.loads(GK_PROMPTS.read_text(encoding="utf-8")) if GK_PROMPTS.exists() else {}
        ordre = list(prompts.get("persos", {}))
        # Ordre du casting (prompts_anims.json), les autres ensuite par nom.
        def rank(pid: str) -> tuple:
            return (ordre.index(pid) if pid in ordre else len(ordre), pid)
        persos = sorted(dirs | cands | set(ordre), key=rank)
        for pid in persos:
            if pid in dirs:
                self.gk_perso(pid, GK / "persos" / pid)
            self.gk_candidats(pid)
        # Animations attendues pour chaque perso (y compris celles « à venir » : clips sur mesure).
        attendues = [{"name": n, "loop": bool(a.get("boucle", False)),
                      "a_venir": bool((a.get("mouvement") or {}).get("a_venir"))}
                     for n, a in prompts.get("animations", {}).items()]
        self.gk = {"persos": persos, "anims": attendues, "decor_a_venir": []}
        self.gk_objets()
        self.gk_map()
        self.gk_mannequin()
        self.gk_decor()

    def gk_perso(self, pid: str, pdir: Path) -> None:
        anims: list[dict] = []
        masks: list[dict] = []
        used: set[str] = set()
        srcs: list[Path] = []
        mask_srcs: list[Path] = []
        preview = ""
        jsons = [j for j in pdir.glob("*.json") if (pdir / f"{j.stem}.png").exists()]
        order = {n: i for i, n in enumerate(GK_ANIM_ORDER)}
        jsons.sort(key=lambda j: (order.get(j.stem, len(order)), j.stem))
        for j in jsons:
            name = j.stem
            meta = json.loads(j.read_text())
            cell = meta.get("cell", 256)
            cw, ch = (int(cell[0]), int(cell[1])) if isinstance(cell, list) else (int(cell), int(cell))
            png, tenue = pdir / f"{name}.png", pdir / f"{name}_tenue.png"
            used |= {png.name, tenue.name}
            strip = np.array(Image.open(png).convert("RGBA"))
            n = min(int(meta.get("frames", strip.shape[1] // cw)), strip.shape[1] // cw)
            if n <= 0:
                continue
            frames = [strip[:ch, i * cw:(i + 1) * cw] for i in range(n)]
            # Recadrage sur l'union des pixels visibles (les frames restent alignées).
            ys, xs = np.nonzero(np.any(np.stack(frames)[..., 3] > 0, axis=0))
            if len(ys) == 0:
                y0, y1, x0, x1 = 0, ch, 0, cw
            else:
                y0, y1 = max(ys.min() - 4, 0), min(ys.max() + 5, ch)
                x0, x1 = max(xs.min() - 4, 0), min(xs.max() + 5, cw)
            w, h = int(x1 - x0), int(y1 - y0)
            fps = float(meta.get("fps", 24))
            info = {"frames": n, "fps": int(fps) if fps.is_integer() else fps,
                    "loop": bool(meta.get("loop", False)), "w": w, "h": h}
            # Raccord du jeu (gk_perso.gd) : recalage par image, décalage et échelle de la planche,
            # pour que le lecteur plein écran montre ce que voit le joueur.
            offs = meta.get("frame_offsets") or []
            if any(abs(float(o[0])) + abs(float(o[1])) > 0.01 for o in offs[:n]):
                info["offs"] = [[round(float(o[0]), 1), round(float(o[1]), 1)] for o in offs[:n]]
            dec = meta.get("decalage")
            if isinstance(dec, list) and len(dec) == 2 and (dec[0] or dec[1]):
                info["dec"] = [float(dec[0]), float(dec[1])]
            if float(meta.get("echelle", 1.0)) != 1.0:
                info["echelle"] = float(meta["echelle"])
            feet = meta.get("feet_anchor")
            if isinstance(feet, list) and len(feet) == 2:
                info["feet"] = [int(feet[0]) - int(x0), int(feet[1]) - int(y0)]   # repère des pieds, recadré
            cut = Image.fromarray(np.concatenate([fr[y0:y1, x0:x1] for fr in frames], axis=1), "RGBA")
            f = self.save_png(cut, f"gordeka/persos/{pid}/anims/{name}.png")
            # Image fixe des vignettes (case du milieu) : la planche n'est chargée qu'au survol.
            poster = self.save_png(Image.fromarray(frames[n // 2][y0:y1, x0:x1], "RGBA"),
                                   f"gordeka/persos/{pid}/anims/_poster/{name}.png")
            anims.append({"name": name, **info, "file": f, "poster": poster})
            srcs += [png, j]
            if name == "idle" or not preview:
                preview = self.save_png(Image.fromarray(frames[0][y0:y1, x0:x1], "RGBA"),
                                        f"gordeka/persos/{pid}/anims/_preview.png")
            if tenue.exists():
                m = np.array(Image.open(tenue).convert("RGBA"))
                mcut = np.concatenate([m[:ch, i * cw + x0:i * cw + x1][y0:y1] for i in range(n)], axis=1)
                mf = self.save_png(Image.fromarray(mcut, "RGBA"), f"gordeka/persos/{pid}/masques/{name}.png")
                mp = self.save_png(Image.fromarray(mcut[:, (n // 2) * w:(n // 2 + 1) * w], "RGBA"),
                                   f"gordeka/persos/{pid}/masques/_poster/{name}.png")
                masks.append({"name": name, **info, "file": mf, "poster": mp})
                mask_srcs.append(tenue)
        if anims:
            tenue_desc = ""
            try:
                tenue_desc = json.loads(jsons[0].read_text()).get("tenue", "")
            except (OSError, ValueError):
                pass
            self.add(id=f"gordeka/persos/{pid}/animations", cat=CAT_GK_PERSOS, group=pid, kind="anim",
                     name=f"{pid} · animations", type="sprite", smooth=True, version=short_hash(*srcs),
                     w=anims[0]["w"], h=anims[0]["h"], file=preview, preview=preview, anims=anims,
                     note=f"{len(anims)} animations, cases de 256 px recadrées sur l'union des frames")
            if masks:
                mprev = self.save_png(Image.open(self.out / masks[0]["file"]).crop(
                    (0, 0, masks[0]["w"], masks[0]["h"])), f"gordeka/persos/{pid}/masques/_preview.png")
                self.add(id=f"gordeka/persos/{pid}/masques", cat=CAT_GK_PERSOS, group=pid, kind="masque",
                         name=f"{pid} · masques de tenue", type="sprite", smooth=True,
                         version=short_hash(*mask_srcs), w=masks[0]["w"], h=masks[0]["h"], file=mprev,
                         preview=mprev, anims=masks,
                         note="<anim>_tenue.png, même recadrage que les animations"
                              + (f" · tenue : {tenue_desc}" if tenue_desc else ""))
        for png in sorted(pdir.glob("*.png")):
            if png.name in used:
                continue
            img = Image.open(png).convert("RGBA")
            rel = self.rel_src(png)
            f = self.save_png(img, rel)
            modele = png.name == "modele.png"
            self.add(id=rel, cat=CAT_GK_PERSOS, group=pid, kind="modele" if modele else "src",
                     name=f"{pid} · {'profil validé' if modele else png.stem}", type="image", smooth=True,
                     version=short_hash(png), w=img.width, h=img.height, file=f, preview=f, note="")

    def gk_candidats(self, pid: str) -> None:
        """Un lot par génération (profil, retouche…), le plus récent en premier."""
        lots = sorted((d for d in (GK_CANDIDATS / pid).glob("*") if d.is_dir()),
                      key=lambda d: d.stat().st_mtime, reverse=True)
        for pdir in lots:
            prompt = ""
            if (pdir / "params.json").exists():
                try:
                    prompt = json.loads((pdir / "params.json").read_text()).get("prompt", "")
                except ValueError:
                    pass
            for png in sorted(pdir.glob("image_*.png")):
                num = png.stem.split("_")[1]
                img = Image.open(png).convert("RGB")
                img.thumbnail((GK_CANDIDAT_MAX, GK_CANDIDAT_MAX), Image.LANCZOS)
                f = self.save_png(img, f"gordeka/candidats/{pid}/{pdir.name}/image_{num}.png")
                self.add(id=self.rel_src(png), cat=CAT_GK_PERSOS, group=pid, kind="candidat",
                         name=f"{pid} · {pdir.name} · variante {int(num) + 1}", type="image", smooth=True,
                         version=short_hash(png), w=img.width, h=img.height, file=f, preview=f,
                         note="candidat, réduit" + (f" · prompt : {prompt}" if prompt else ""))

    def gk_map(self) -> None:
        from PIL import ImageDraw, ImageFont
        for mdir in sorted(p for p in (ASSETS / "maps").glob("*") if p.is_dir()):
            mid = mdir.name
            pngs = sorted(mdir.glob("*.png"))
            for png in pngs:
                rel = self.rel_src(png)
                img = Image.open(png)
                f = self.copy(png, rel)
                self.add(id=rel, cat=CAT_GK_MAP, group=mid, kind="carte", name=f"{mid} · {png.stem}",
                         type="image", version=short_hash(png), w=img.width, h=img.height,
                         file=f, preview=f, note="")
            txt = mdir / "map.txt"
            if not pngs and txt.exists():
                rows = [r for r in txt.read_text(encoding="utf-8").splitlines() if r]
                gw, gh = max(len(r) for r in rows), len(rows)
                t = MAP_TILE
                img = Image.new("RGB", (gw * t, gh * t), "#" + MAP_COLORS["#"])
                draw = ImageDraw.Draw(img)
                for y, row in enumerate(rows):
                    for x, ch in enumerate(row):
                        draw.rectangle((x * t, y * t, x * t + t - 1, y * t + t - 1),
                                       fill="#" + MAP_COLORS.get(ch, MAP_UNKNOWN))
                zones_path = mdir / "zones.json"
                srcs = [txt]
                if zones_path.exists():
                    srcs.append(zones_path)
                    font = ImageFont.truetype(str(MAP_FONT), 8)
                    for z in json.loads(zones_path.read_text(encoding="utf-8")).get("zones", []):
                        zx, zy, zw, zh = z["rect"]
                        draw.rectangle((zx * t, zy * t, (zx + zw) * t - 1, (zy + zh) * t - 1),
                                       outline="#ffffff")
                        draw.text((zx * t + 4, zy * t + 4), z["name"], fill="#111111", font=font,
                                  stroke_width=2, stroke_fill="#ffffff")
                rel = f"maps/{mid}/map.txt"
                f = self.save_png(img, f"maps/{mid}/apercu.png")
                self.add(id=rel, cat=CAT_GK_MAP, group=mid, kind="carte", name=f"{mid} · aperçu",
                         type="image", version=short_hash(*srcs), w=img.width, h=img.height, file=f, preview=f,
                         note=f"rendu depuis map.txt ({gw}×{gh} cases, {t} px par case) et zones.json · "
                              "mur gris, sol beige, eau bleue, bateau blanc, caisse brune, objet bas sable, "
                              "cachette orange, sortie verte, départ violet")
            for js in sorted(mdir.glob("*.json")):
                self.data(js, CAT_GK_MAP, mid)

    def data(self, js: Path, cat: str, group: str, kind: str = "data") -> None:
        rel = self.rel_src(js)
        f = self.copy(js, rel)
        self.add(id=rel, cat=cat, group=group, kind=kind, name=f"{group} · {js.stem}", type="data",
                 version=short_hash(js), file=f, preview="", note="JSON")

    def gk_mannequin(self) -> None:
        for mdir in sorted(p for p in (GK / "mannequin").glob("*") if p.is_dir()):
            for png in sorted(mdir.glob("*.png")):
                rel = self.rel_src(png)
                img = Image.open(png)
                f = self.copy(png, rel)
                self.add(id=rel, cat=CAT_GK_MANNEQUIN, group=mdir.name, kind="piece",
                         name=f"{mdir.name} · {png.stem}", type="image", smooth=True, version=short_hash(png),
                         w=img.width, h=img.height, file=f, preview=f, note="pièce du pantin")
            for js in sorted(mdir.glob("*.json")):
                self.data(js, CAT_GK_MANNEQUIN, mdir.name)
        for js in sorted((GK / "choreo").glob("*.json")):
            self.data(js, CAT_GK_MANNEQUIN, "chorégraphies", "choreo")

    def gk_objets(self) -> None:
        """Décor en images (assets/gordeka/decor/index.json) : objets avec leurs masques, sols.

        Le calque des masques est une image transparente de la taille de l'objet, à poser
        dessus : violet = zone qui cache le perso (occluder), vert = emprise au sol qui bloque
        (footprint), orange = contact au sol. « sans masque » : pas de masks.json pixelforge,
        ou le jeu utilise le calcul local de repli (_sources.json)."""
        ddir = GK / "decor"
        idx_path = ddir / "index.json"
        if not idx_path.exists():
            return
        elements = json.loads(idx_path.read_text(encoding="utf-8")).get("elements", {})
        src_path = GK_MASQUES / "jeu" / "_sources.json"
        sources = json.loads(src_path.read_text(encoding="utf-8")) if src_path.exists() else {}
        for eid, e in elements.items():
            fichiers = [ddir / f for f in e.get("fichiers") or [] if (ddir / f).exists()]
            base = {"nom": e.get("nom", eid), "categorie": e.get("categorie", ""), "type": e.get("type", ""),
                    "zones": e.get("zones", []), "cases": e.get("taille_cases")}
            if not fichiers:
                self.gk["decor_a_venir"].append({"id": eid, **base})
                continue
            png = fichiers[0]
            rel = self.rel_src(png)
            img = Image.open(png)
            f = self.copy(png, rel)
            if e.get("type", "").startswith("tuile"):
                self.add(id=rel, cat=CAT_GK_OBJETS, group="sols", kind="sol", name=base["nom"], type="image",
                         smooth=True, version=short_hash(png), w=img.width, h=img.height, file=f, preview=f,
                         decor=base, note=f"tuile de {'×'.join(map(str, e.get('taille_cases') or []))} cases, "
                                         "affichée répétée 2×2")
                continue
            srcs = [png]
            mdir = ddir / "masques" / eid
            mj = mdir / "masks.json"
            masks = json.loads(mj.read_text(encoding="utf-8")) if mj.exists() else None
            jeu = sources.get(eid, {})
            source = jeu.get("source") or ("pixelforge" if masks else "aucun")
            info = {**base, "source": source, "refus": jeu.get("refus_pixelforge", ""),
                    "confidence": (masks or {}).get("confidence"), "warnings": (masks or {}).get("warnings", []),
                    "blocks_view": (masks or {}).get("blocks_view", jeu.get("bloque_vue")),
                    "camera": (masks or {}).get("camera", ""), "shapes": (masks or {}).get("shapes", []),
                    "sans_masque": source != "pixelforge"}
            # Calque coloré, aligné pixel pour pixel (même taille que l'objet).
            calque = np.zeros((img.height, img.width, 4), dtype=np.uint8)
            poses = []
            for name, color in GK_MASK_COLORS:
                mp = mdir / name
                if not mp.exists():
                    continue
                m = Image.open(mp)
                if m.size != img.size:
                    info["warnings"] = info["warnings"] + [f"{name} {m.size[0]}×{m.size[1]} ≠ objet {img.width}×{img.height}"]
                    continue
                a = np.array(m.convert("RGBA"))[..., 3] > 0
                calque[a] = color
                poses.append(name)
                srcs.append(mp)
            if poses:
                info["calque"] = self.save_png(Image.fromarray(calque, "RGBA"), f"gordeka/decor/calques/{eid}.png")
            info["masques"] = poses
            if mj.exists():
                srcs.append(mj)
            for key, path in (("controle", GK_MASQUES / "jeu" / f"{eid}.png"), ("apercu_pf", GK_MASQUES / f"{eid}.png"),
                              ("ombre", ddir / e["ombre"] if e.get("ombre") else None)):
                if path is not None and path.exists():
                    im = Image.open(path)
                    info[key] = {"file": self.copy(path, self.rel_src(path)), "w": im.width, "h": im.height}
            self.add(id=rel, cat=CAT_GK_OBJETS, group="objets", kind="objet", name=base["nom"], type="image",
                     smooth=True, version=short_hash(*srcs), w=img.width, h=img.height, file=f, preview=f,
                     decor=info, note=f"{eid} · {base['categorie']}")

    def gk_decor(self) -> None:
        for sub, group in (("textures", "textures"), ("models", "modèles")):
            for png in sorted((GK / sub).glob("*.png")):
                rel = self.rel_src(png)
                img = Image.open(png)
                f = self.copy(png, rel)
                self.add(id=rel, cat=CAT_GK_DECOR, group=group, kind=sub, name=f"{group} · {png.stem}",
                         type="image", smooth=True, version=short_hash(png), w=img.width, h=img.height,
                         file=f, preview=f, note="texture de modèle 3D (.glb non affichable)" if sub == "models" else "")

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
        self.gordeka()
        self.fighters()
        self.images("vfx", CAT_VFX, True)
        self.images("stages", CAT_STAGES, True)
        self.images("sprites", CAT_SPRITES, False)
        self.images("ui", CAT_UI, False)
        self.audio("music", CAT_MUSIC)
        self.audio("sfx", CAT_SFX)
        self.audio("voice", CAT_VOICE)
        cat_rank = {c: i for i, c in enumerate(CATEGORIES)}
        gordeka = set(SECTIONS[0]["categories"])
        def rank(a):
            if a["cat"] in gordeka:
                return (cat_rank[a["cat"]], "", 0, "")     # tri stable : ordre de construction
            if a["cat"] != CAT_FIGHTERS:
                return (cat_rank[a["cat"]], "", 0, a["id"])
            n = a["id"].rsplit("/", 1)[-1]
            k = 0 if a["type"] == "sprite" else 1 if n.startswith("portrait") else 2 if n.startswith("ending") \
                else 4 if a["id"].startswith("vfx/") else 3
            return (cat_rank[a["cat"]], a["group"], k, a["id"])
        self.assets.sort(key=rank)
        index = {
            "commit": git_commit(),
            "generated_at": int(time.time()),
            "categories": CATEGORIES,
            "sections": SECTIONS,
            "gordeka": self.gk,
            "assets": self.assets,
            "files": sorted(set(self.files)),
            # Empreinte du contenu de chaque fichier servi : le client l'ajoute à l'URL (&v=…),
            # une planche réécrite sous le même nom change donc d'URL (pas de vieux cache).
            "versions": {f: hashlib.sha1((self.out / f).read_bytes()).hexdigest()[:10]
                         for f in sorted(set(self.files)) if (self.out / f).is_file()},
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
