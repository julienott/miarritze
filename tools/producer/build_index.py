#!/usr/bin/env python3
"""Génère les aperçus et l'index des assets pour le service /producer.

Usage : build_index.py <dossier_sortie>   (ex. web/build/producer/files)

- Lit assets/ en lecture seule.
- Character sets pixelforge (format du 23/10) des persos, du fantôme commun, des PNJ, des animaux et
  des boss (assets/blackout/<famille>/<id>/px32 et hd) : un asset « animations » par set, avec ses
  éléments dans l'ordre (libellé, ce qu'on doit voir, action, objet, clip Quaternius, images, i/s,
  boucle, planche 32 px et planche HD si le dossier local hd/ est là), les avertissements de
  set.json → controls.warnings et le drapeau « placeholder » (clé `set`, et `blackout.sets`).
- Blackout, ancien format (assets/blackout, assets/maps) : animations des persos (planches d'une
  rangée de cases, recadrées sur l'union des frames) et leurs masques de tenue,
  profil validé (modele.png), profils candidats (tools/rd/out/<id>/gk2d/profil,
  réduits, seulement s'ils sont présents : dossier non versionné), pièces du
  mannequin, chorégraphies et données JSON, textures, aperçu de la carte rendu
  depuis map.txt.
- Décor de Blackout (assets/blackout/decor/index.json) : un asset par objet, avec un calque
  coloré tiré des masques pixelforge (masques/<id>/footprint.png en vert, occluder.png en
  violet, ground_contact.png en orange, alignés pixel pour pixel sur objets/<id>.png), la
  source des masques (pixelforge ou repli, tools/blackout/masques/jeu/_sources.json), le
  contrôle du jeu (masques/jeu/<id>.png) et l'aperçu pixelforge ; un asset par sol.
- Animations attendues (tools/blackout/prompts_anims.json, clé « animations ») et ordre des
  persos (clé « persos ») : dans index.json, clé « blackout », pour les manquantes.
- Décor des autres cartes (assets/maps/<carte>/decor/index.json : Parc Mazon, Plage) : mêmes
  assets ; un élément repris du port (fichier res://assets/blackout/decor/…) n'est pas recopié,
  la carte s'ajoute à `decor.cartes` de l'asset du port. Animations du décor
  (assets/blackout/decor/anims/<id>.png + .json) : une planche par élément, cases réduites.
- Pilotage (clé « blackout » de index.json) : libellés des animations et noms des persos, prompts
  (prompts_anims.json, prompts_decor.json), retouches de recette, liens assets ↔ cartes du kanban
  (`liens`, depuis tools/blackout/taches_plage.json, taches_parc_mazon.json, taches_decor_nuit.json
  et les options de partie), tâches pixelforge par asset (`pixelforge`, depuis les taches_*.json),
  file pixelforge en attente (`file_pixelforge`), et le gameplay de jeu_index.py (règles, options,
  écrans, cartes de jeu, équilibrage, jalons de la spec).
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import jeu_index  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"

CAT_BK_PERSOS = "Persos"
CAT_BK_MAP = "Carte"
CAT_BK_MANNEQUIN = "Mannequin"
CAT_BK_DECOR = "Textures & modèles"
CAT_BK_OBJETS = "Décor"
CAT_BK_JEU = "Jeu"                 # règles, options de partie, écrans (jeu_index.py)
CAT_A_VENIR = "À venir"            # assets sans fichier encore (coups, décor des cartes) : cartes du kanban seules
# Sections de la barre latérale ; la page s'ouvre sur la première catégorie.
SECTIONS = [
    {"name": "Blackout", "categories": [CAT_BK_PERSOS, CAT_BK_OBJETS, CAT_BK_MAP, CAT_BK_JEU, CAT_BK_MANNEQUIN, CAT_BK_DECOR, CAT_A_VENIR]},
]
CATEGORIES = [c for s in SECTIONS for c in s["categories"]]

BK = ASSETS / "blackout"
BK_CANDIDATS = ROOT / "tools" / "blackout" / "candidats"   # copies réduites versionnées (sync_candidats.py)
BK_MASQUES = ROOT / "tools" / "blackout" / "masques"       # contrôles des formes du décor (masques_decor.py)
BK_PROMPTS = ROOT / "tools" / "blackout" / "prompts_anims.json"   # animations attendues, ordre des persos
# Calques des masques du décor (RGBA) : emprise au sol, zone qui cache le perso, contact au sol.
BK_MASK_COLORS = (("occluder.png", (155, 89, 230, 115)), ("footprint.png", (40, 200, 80, 160)),
                  ("ground_contact.png", (255, 120, 0, 235)))
# Ordre des animations (tools/blackout/anime_perso.py), les autres ensuite par nom.
BK_ANIM_ORDER = ["idle", "walk", "run_scared", "hide_in", "hide_out", "found", "trap", "trapped",
                 "search", "detect", "extract", "victory", "sad", "ghost", "ghost_move"]
BK_CANDIDAT_MAX = 512            # côté max des profils candidats (1024 à la source)
# Carte : couleurs de src/blackout/bk_map.gd (COLORS, TILE_FLOORS, FLOOR_TINTS[0]) ;
# sortie, départ et inconnu choisis pour se voir.
MAP_TILE = 10
MAP_FONT = ROOT / "producer" / "static" / "press_start_2p.ttf"     # accents (Criée, Hangar à filets)
MAP_COLORS = {"#": "3b4253", "c": "a0703e", "B": "e8eef2", "H": "e08a2e", "t": "c9a873", "~": "2f7fb8",
              "R": "8c6446", "r": "9a7a5c", "v": "5f8a4a", ":": "e6cf98", "=": "b8b2a6", ".": "d9d2c3",
              "E": "3fae5a", "S": "8e5cc8"}
MAP_UNKNOWN = "ff00ff"
BK_TACHES = ROOT / "tools" / "blackout"                    # taches_*.json : tâches pixelforge, cartes du kanban
BK_RULES = ROOT / "data" / "blackout" / "rules.json"
BK_DECOR_CARTES = [("port_pecheurs", BK / "decor"), ("parc_mazon", ASSETS / "maps" / "parc_mazon" / "decor"),
                   ("plage", ASSETS / "maps" / "plage" / "decor")]
BK_DECOR_ANIM_MAX = 320          # côté max d'une case d'animation du décor dans /producer
# Libellés des animations (titres des cartes « <Perso> · <libellé> » de remplit_kanban.py).
BK_ANIM_LABELS = {"idle": "repos", "walk": "marche", "run_scared": "fuite apeurée", "hide_in": "se cacher",
                  "hide_out": "sortir de cachette", "found": "trouvé", "trap": "poser un piège",
                  "trapped": "pris au piège", "search": "fouiller", "detect": "détecter", "extract": "sortir un chassé",
                  "victory": "victoire", "sad": "tristesse", "hunter_reveal": "apparition du chasseur",
                  "ghost": "fantôme", "ghost_move": "fantôme en vol"}
# Character sets pixelforge (format du 23/10) : <famille>/<id>/px32/ (planches <élément>_sheet.png,
# animations.json, set.json) et <famille>/<id>/hd/ (même chose en HD, local, non versionné).
BK_SET_FAMILLES = [("persos", "Perso"), ("fantome", "Fantôme"), ("pnj", "PNJ"), ("animaux", "Animal"), ("boss", "Boss")]
BK_STYLE = ROOT / "data" / "blackout" / "style_party_hard.json"   # idle_long et casts par perso
BK_PNJ = ROOT / "data" / "blackout" / "pnj.json"                  # extras communs et activités des PNJ
BK_COUPS = ROOT / "data" / "blackout" / "coups.json"              # nom des coups spéciaux par perso
# Éléments d'un character set : libellé, ce qu'on doit voir, clip Quaternius par défaut.
# Source : GDD-BLACKOUT.md §8.1 (éléments fixes), §4.5 (effets subis), §8.3 (boss), §8.4 (PNJ) ;
# aucun JSON ne les porte. Le clip réellement utilisé vient de set.json (clips, extras, optional)
# quand il y est, les éléments propres au perso ou au PNJ de style_party_hard.json et pnj.json.
BK_ELEMENTS = {
    "profile": ("profil", "Sprite de référence, debout de profil tourné vers la droite : toutes les "
                "animations lui restent fidèles.", "Idle_Loop (pose debout, 1re image)"),
    "portrait": ("portrait", "Buste de trois-quarts face pour les menus, le versus et le podium, fait depuis "
                 "le profil seul, sans détail inventé.", ""),
    "idle": ("repos", "Immobile, petite respiration (faite par pixelforge, par code).", "code (respiration)"),
    "idle_long": ("pose d'inactivité", "Pose propre au perso quand il attend longtemps (§8.2).", ""),
    "run": ("course", "Course : 4 poses à pas égal (contact, passage, contact, passage), tête stable, "
            "pieds sur la ligne.", "Sprint_Loop"),
    "jump_hide": ("saut vers la cachette", "Saut vers la cachette ; la sortie de cachette est la même "
                  "animation jouée à l'envers.", "Jump_Start"),
    "lift": ("envol", "Envol avant de devenir fantôme, couleurs normales (le jeu fait clignoter le perso).",
             "LiftAir_Idle_Loop"),
    "ghost": ("fantôme", "Fantôme commun à tous les persos (assets/blackout/fantome/).", "code"),
    "interagir": ("interagir", "Fouille une cachette ou actionne un disjoncteur (1 s).", "Interact"),
    "cast_chasse": ("lancement du coup de chassé", "Lancement de son coup spécial de chassé (§4.6).", ""),
    "cast_chasseur": ("lancement du coup de chasseur", "Lancement de son coup spécial de chasseur (§4.6).", ""),
    "victoire": ("victoire", "Podium du gagnant : il danse de joie.", "Dance_Loop"),
    "defaite": ("défaite", "Podium du perdant : déçu, il fait non.", "Idle_No_Loop"),
    "etourdi": ("étourdi", "Effets Figé et Commandes inversées : coup sur la tête, puis il tangue.", "Hit_Head"),
    "renverse": ("renversé", "Effet Renversé : il tombe, puis se relève.", "Hit_Knockback puis LayToIdle"),
    "colle": ("collé", "Effet Collé : il tire sur ses pieds collés dans la résine.", "Push_Loop"),
    "ralenti": ("ralenti", "Effet Ralenti : marche lourde.", "Zombie_Walk_Fwd_Loop"),
    "aveugle": ("aveuglé", "Effet Aveuglé / masqué : il se frotte les yeux.", "Idle_No_Loop"),
    "tracte": ("tracté", "Effet Tracté : il glisse en se laissant tirer.", "Slide_Loop"),
    # Fantôme commun (§8.1) : drap dessiné une fois, mouvements par code (style pf_px__ghost).
    "float": ("flotte", "Le petit drap blanc flotte sur place, monte et descend doucement.", "code (pf_px__ghost)"),
    "advance": ("avance", "Le fantôme avance en flottant.", "code (pf_px__ghost)"),
    "appear": ("apparition", "Le fantôme apparaît, au moment où le perso devient fantôme.", "code (pf_px__ghost)"),
    # PNJ (§8.4) : la course est la fuite ; marcher et sursaut sont communs à tous.
    "marcher": ("marcher", "Marche calme, son déplacement normal dans la foule.", "Walk_Loop"),
    "sursaut": ("sursaut", "Il sursaute, surpris, puis s'enfuit (fuite).", "Surprise"),
    "a_terre": ("à terre", "Renversé (boss qui fonce) : il s'effondre et reste allongé.", "IdleToLay"),
    "relever": ("se relever", "Il se relève quand le danger est passé.", "LayToIdle"),
    "fuir": ("fuir", "Il s'enfuit.", ""),
    # Boss (§8.3, §5.2).
    "cri": ("cri", "Il repère un joueur et pousse un cri.", ""),
    "pouvoir_1": ("pouvoir 1", "Premier pouvoir du boss (§5.2).", ""),
    "pouvoir_2": ("pouvoir 2", "Second pouvoir du boss (§5.2).", ""),
}
# Ordre d'affichage des éléments d'un perso (GDD §8.1), les autres ensuite dans l'ordre de set.json.
BK_ELEMENTS_PERSO = ["profile", "portrait", "idle", "idle_long", "run", "jump_hide", "lift", "interagir",
                     "cast_chasse", "cast_chasseur", "victoire", "defaite", "etourdi", "renverse", "colle",
                     "ralenti", "aveugle", "tracte"]
# Statuts de taches_decor_nuit.json qui sont encore dans la file pixelforge (ou en attente d'elle).
BK_FILE_STATUTS = {"en_file": "en file", "attend": "attend une autre tâche", "a_voir": "à voir", "question": "question"}

# Fichiers de combattants ignorés (obsolètes, remplacés par les sheets RD).


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
        self.bk: dict = {"persos": [], "anims": [], "decor_a_venir": []}
        self.by_id: dict[str, dict] = {}
        self.liens: dict[str, list[int]] = {}          # asset -> ids de cartes du kanban
        self.liens_chapeaux: dict[str, int] = {}       # carte de jeu -> carte chapeau du kanban
        self.pixelforge: dict[str, list[dict]] = {}    # asset[#anim] -> tâches pixelforge
        self.decor_ids: dict[tuple[str, str], str] = {}   # (carte, élément) -> id d'asset

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

    def add(self, **entry) -> None:
        self.assets.append(entry)
        self.by_id[entry["id"]] = entry

    def lien(self, asset: str, card) -> None:
        if asset and isinstance(card, int) and card not in self.liens.setdefault(asset, []):
            self.liens[asset].append(card)

    def tache(self, key: str, **t) -> None:
        if key and t.get("tid"):
            lst = self.pixelforge.setdefault(key, [])
            if not any(x["tid"] == t["tid"] for x in lst):
                lst.append({k: v for k, v in t.items() if v not in (None, "")})

    @staticmethod
    def rel_src(path: Path) -> str:
        """Id d'un asset : chemin relatif à assets/, ou au dépôt s'il est ailleurs."""
        try:
            return path.relative_to(ASSETS).as_posix()
        except ValueError:
            return path.relative_to(ROOT).as_posix()

    def bk_a_venir(self) -> None:
        """Assets sans fichier encore, pour y rattacher leurs cartes (Julien 24/10) : un par coup spécial
        (objet, effet, icône ; data/blackout/coups.json) et un « décor » par carte de jeu (assets/maps)."""
        coups = json.loads((ROOT / "data" / "blackout" / "coups.json").read_text(encoding="utf-8"))["persos"]
        for pid, d in coups.items():
            for role, cp in d.items() if isinstance(d, dict) else ():
                if isinstance(cp, dict) and cp.get("id"):
                    self.add(id=f"blackout/coups/{cp['id']}", cat=CAT_A_VENIR, group=pid, kind="coup",
                             name=f"{pid} · {cp.get('nom', cp['id'])}", type="jeu", version="0", file="", preview="",
                             note="GDD §4.4–4.6 : objet, effet et icône du coup (à faire)",
                             jeu={"sorte": "a_venir", "coup": cp["id"], "role": role, "famille": cp.get("famille")})
        for m in sorted(p for p in (ASSETS / "maps").iterdir() if (p / "map.txt").exists()):
            self.add(id=f"maps/{m.name}/decor", cat=CAT_A_VENIR, group=m.name, kind="decor",
                     name=f"{m.name} · décor", type="jeu", version="0", file="", preview="",
                     note="assets du décor de la carte (à faire, GDD §10)", jeu={"sorte": "a_venir", "carte": m.name})

    # ==================================================================== Blackout
    def blackout(self) -> None:
        dirs = {p.name for p in (BK / "persos").iterdir() if p.is_dir()} if (BK / "persos").is_dir() else set()
        cands = {p.parents[1].name for p in BK_CANDIDATS.glob("*/*/image_*.png")}
        # Persos animés d'abord, puis ceux qui ont un profil validé, puis les candidats seuls.
        prompts = json.loads(BK_PROMPTS.read_text(encoding="utf-8")) if BK_PROMPTS.exists() else {}
        rules = json.loads(BK_RULES.read_text(encoding="utf-8")) if BK_RULES.exists() else {}
        noms = dict(zip(rules.get("characters", []), rules.get("bot_names", [])))
        ordre = list(prompts.get("persos", {})) or list(rules.get("characters", []))
        # Ordre du casting (prompts_anims.json, sinon rules.json), les autres ensuite par nom.
        def rank(pid: str) -> tuple:
            return (ordre.index(pid) if pid in ordre else len(ordre), pid)
        persos = sorted(dirs | cands | set(ordre), key=rank)
        self.sets: dict[str, dict] = {}      # clé (pid, ou famille/id hors persos) -> fiche du set
        self.libelles: dict[str, str] = {}   # élément -> libellé (tous les sets)
        for pid in persos:
            pdir = BK / "persos" / pid
            if (pdir / "px32" / "set.json").exists():
                self.bk_set("persos", pid, pdir, noms.get(pid, pid.capitalize()))
            elif pid in dirs:
                self.bk_perso(pid, pdir)
            self.bk_candidats(pid)
        # Fantôme commun, PNJ, animaux, boss : mêmes character sets, hors liste des persos.
        autres = []
        for fam, label in BK_SET_FAMILLES[1:]:
            for sj in sorted((BK / fam).glob("*/px32/set.json")):
                sid = sj.parents[1].name
                key = f"{fam}/{sid}"
                nom = label if fam == "fantome" and sid == "fantome" else f"{label} · {sid.replace('_', ' ').capitalize()}"
                self.bk_set(fam, sid, sj.parents[1], nom)
                autres.append(key)
        # Animations attendues pour chaque perso : prompts_anims.json (ancien format), sinon les
        # éléments du character set (GDD §8.1).
        attendues = [{"name": n, "loop": bool(a.get("boucle", False)),
                      "a_venir": bool((a.get("mouvement") or {}).get("a_venir")),
                      "libelle": BK_ANIM_LABELS.get(n, n.replace("_", " "))}
                     for n, a in prompts.get("animations", {}).items()]
        if not attendues and any(s["famille"] == "persos" for s in self.sets.values()):
            attendues = [{"name": n, "loop": False, "a_venir": False, "libelle": BK_ELEMENTS[n][0]}
                         for n in BK_ELEMENTS_PERSO]
        retouches = {}
        if (BK_TACHES / "retouches_recette.json").exists():
            for k, v in json.loads((BK_TACHES / "retouches_recette.json").read_text(encoding="utf-8")).items():
                retouches[k] = v if isinstance(v, str) else (v.get("action") or "")
        self.bk = {
            "persos": persos, "anims": attendues,
            "noms": {**{p: noms.get(p, p.capitalize()) for p in persos}, **{k: self.sets[k]["nom"] for k in autres}},
            # Character sets hors persos (fantôme, PNJ, animaux, boss), clé famille/id.
            "autres": autres, "sets": self.sets, "libelles": self.libelles,
            "decor_a_venir": [],
            # Prompts des animations : consigne commune, action et expression par animation, description du perso.
            "prompts_anims": {
                "regles_communes": prompts.get("regles_communes", ""),
                "animations": {n: {"action": a.get("action", ""), "expression": a.get("expression", "")}
                               for n, a in prompts.get("animations", {}).items()},
                "persos": {p: v.get("description", "") for p, v in prompts.get("persos", {}).items()},
            },
            "retouches": {k: v for k, v in retouches.items() if v},
        }
        self.decor_prompts = self.prompts_decor()
        self.bk["prompts_decor_style"] = {c: v for (k, c), v in self.decor_prompts.items() if k == "_style" and v}
        for carte, ddir in BK_DECOR_CARTES:
            self.bk_objets(carte, ddir)
        self.bk_decor_anims()
        self.bk_map()
        self.bk_mannequin()
        self.bk_decor()
        self.bk_taches()
        self.bk.update(jeu_index.construit(self.add, self.capture_ecran, self.liens, self.liens_chapeaux))
        self.bk_a_venir()
        self.bk["liens"] = self.liens
        self.bk["pixelforge"] = self.pixelforge

    def capture_ecran(self, png: Path) -> dict:
        """Capture d'un écran de menu (docs/captures/ecrans), réduite à 640 px de large."""
        img = Image.open(png).convert("RGB")
        img.thumbnail((640, 640), Image.LANCZOS)
        f = self.save_png(img, f"jeu/ecrans/{png.name}")
        return {"file": f, "w": img.width, "h": img.height}

    @staticmethod
    def prompts_decor() -> dict:
        """Prompt de chaque élément de décor, par (carte, élément) (tools/blackout/prompts_decor.json)."""
        path = BK_TACHES / "prompts_decor.json"
        if not path.exists():
            return {}
        d = json.loads(path.read_text(encoding="utf-8"))
        # Partie propre à l'élément seulement ; le style commun de chaque carte va une fois dans l'index.
        out = {("_style", d.get("carte", "port_pecheurs")): d.get("preambule_style", "")}
        for e in d.get("elements", []):
            out[(d.get("carte", "port_pecheurs"), e["id"])] = e.get("prompt_specifique") or e.get("prompt", "")
        for carte, c in (d.get("cartes") or {}).items():
            out[("_style", carte)] = c.get("style_commun", "")
            for e in c.get("elements", []):
                out[(carte, e["id"])] = e.get("prompt_specifique") or e.get("prompt", "")
        return out

    def bk_taches(self) -> None:
        """Liens assets ↔ cartes du kanban et tâches pixelforge, lus dans tools/blackout/taches_*.json."""
        def charge(nom: str):
            p = BK_TACHES / nom
            try:
                return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
            except ValueError:
                return {}
        # Animations des persos : taches_<perso>.json = {anim: tid}.
        for pid in self.bk["persos"]:
            for nom in (f"taches_{pid}.json",):
                for anim, v in charge(nom).items():
                    tid = v if isinstance(v, str) else (v or {}).get("tid") or (v or {}).get("character_task")
                    if isinstance(tid, str):
                        self.tache(f"blackout/persos/{pid}/animations#{anim}", tid=tid, quoi="animation", style="pf_2d__animate")
        port = lambda eid: self.decor_ids.get(("port_pecheurs", eid), "")   # noqa: E731
        for nom, quoi in (("taches_decor.json", "image"), ("taches_decor_hd.json", "image HD")):
            for eid, tids in charge(nom).items():
                for tid in tids if isinstance(tids, list) else [tids]:
                    self.tache(port(eid), tid=tid, quoi=quoi)
        for eid, v in charge("taches_masques.json").items():
            if isinstance(v, dict):
                self.tache(port(eid), tid=v.get("tid"), quoi="masque", statut=v.get("statut"), essai=v.get("essai"))
        # File de nuit du décor : clé = id de la carte du kanban.
        file = []
        for cid, t in charge("taches_decor_nuit.json").items():
            if not isinstance(t, dict):
                continue
            aid = port(t.get("element", ""))
            card = int(cid) if str(cid).isdigit() else None
            self.lien(aid, card)
            for j in t.get("jobs") or []:
                self.tache(aid, tid=j.get("tid"), quoi=j.get("quoi") or t.get("sorte"), style=j.get("style"),
                           statut=j.get("statut") or t.get("statut"), date=t.get("depose"), carte=card)
            if t.get("statut") in BK_FILE_STATUTS:
                file.append({"carte": card, "titre": t.get("titre", ""), "sorte": t.get("sorte", ""),
                             "element": t.get("element", ""), "asset": aid, "statut": t.get("statut"),
                             "statut_libelle": BK_FILE_STATUTS[t["statut"]], "depose": t.get("depose", ""),
                             "depend": t.get("depend", ""), "jobs": len(t.get("jobs") or [])})
        self.bk["file_pixelforge"] = file
        # Backlogs des cartes Plage et Parc Mazon : {élément[:anim|:ouvert]: carte, chapeau: carte}.
        for carte, nom in (("plage", "taches_plage.json"), ("parc_mazon", "taches_parc_mazon.json")):
            for k, card in charge(nom).items():
                if k == "chapeau":
                    self.liens_chapeaux[carte] = card
                    self.lien(f"maps/{carte}/map.txt", card)
                    continue
                eid = k.split(":")[0]
                self.lien(self.decor_ids.get((carte, eid)) or port(eid), card)
        # Sources pixelforge notées dans les index de décor (job, variante, task).
        for a in self.assets:
            for s in (a.get("decor") or {}).get("sources") or []:
                self.tache(a["id"], tid=s.get("task"), quoi=f"image ({s.get('variante', '')})", date=s.get("date"))

    @staticmethod
    def _json(path: Path) -> dict:
        try:
            return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
        except ValueError:
            return {}

    def _sources_desc(self) -> tuple[dict, dict, dict]:
        """style_party_hard.json, pnj.json et coups.json (lus une fois)."""
        if not hasattr(self, "_desc"):
            self._desc = (self._json(BK_STYLE), self._json(BK_PNJ), self._json(BK_COUPS))
        return self._desc

    def bk_element_desc(self, fam: str, sid: str, name: str, sets: list[dict]) -> dict:
        """Libellé, ce qu'on doit voir, action (prompt), objet et clip d'un élément d'un character set.

        Clip : celui de set.json (extras, optional, clips ; px32 puis HD) s'il y est, sinon celui des
        données (style_party_hard.json pour idle_long et les casts, pnj.json pour les PNJ), sinon le
        clip par défaut de BK_ELEMENTS (GDD §8.1, §4.5)."""
        style, pnj, coups = self._sources_desc()
        libelle, desc, clip = BK_ELEMENTS.get(name, (name.replace("_", " "), "", ""))
        action, objet = "", ""
        if fam == "fantome" and name == "profile":
            desc = ("Fantôme commun à tous les persos (§8.1) : petit drap blanc aux grands yeux ronds et petit "
                    "béret rouge ; le pseudo au-dessus dit à qui il est.")
            clip = "dessiné une fois (pf_px__ghost)"
        elif fam == "persos" and name == "idle_long":
            s = (style.get("idle_long") or {}).get(sid) or {}
            action, clip, objet = s.get("geste", ""), s.get("clip") or clip, s.get("objet") or ""
        elif fam == "persos" and name in ("cast_chasse", "cast_chasseur"):
            s = ((style.get("casts") or {}).get(sid) or {}).get(name) or {}
            action, clip, objet = s.get("action", ""), s.get("clip") or clip, s.get("objet") or ""
            coup = ((coups.get("persos") or {}).get(sid) or {}).get(name.split("_", 1)[1]) or {}
            if coup.get("nom"):
                role = "chassé" if name == "cast_chasse" else "chasseur"
                desc = (f"Lancement de son coup spécial de {role}, « {coup['nom']} » (§4.6"
                        + (f", famille {coup['famille']}" if coup.get("famille") else "") + ").")
        elif fam == "pnj":
            humain = (pnj.get("humains") or {}).get(sid) or {}
            sh = pnj.get("set_humain") or {}
            if name == "run":
                libelle, desc = "fuite", "Course de fuite : il s'enfuit, paniqué (après le sursaut)."
                action, clip = (sh.get("run") or {}).get("action", ""), (sh.get("run") or {}).get("clip") or clip
            for e in sh.get("extras_communs") or []:
                if e.get("name") == name:
                    action, clip = e.get("action", ""), e.get("motion") or clip
            act = (pnj.get("activites") or {}).get(name)
            if act:
                libelle = f"activité : {name}"
                desc = "Une de ses deux activités dans la foule (§8.4)."
                action, clip = act.get("action", ""), act.get("clip") or clip
                objet = act.get("objet") or (f"son objet ({humain.get('signature', '')})" if act.get("objet_du_pnj") else "")
        elif fam == "animaux" and name not in BK_ELEMENTS:
            act = ((pnj.get("animaux") or {}).get(sid) or {}).get("activite", "")
            libelle, desc = f"activité : {name.replace('_', ' ')}", "Son activité (§8.4)" + (f" : {act}." if act else ".")
        # Ce que pixelforge a réellement utilisé (set.json), prioritaire.
        for s in sets:
            for e in (s.get("extras") or []):
                if isinstance(e, dict) and e.get("name") == name:
                    clip = e.get("motion") or clip
                    action = e.get("action") or action
                    objet = e.get("object") or objet
            opt = (s.get("optional") or {}).get(name)
            if isinstance(opt, dict):
                clip = opt.get("motion") or clip
                action = opt.get("action") or action
            if (s.get("clips") or {}).get(name):
                clip = s["clips"][name]
        return {"libelle": libelle, "description": desc, "action": action or "", "objet": objet or "",
                "clip": clip or ""}

    def bk_set(self, fam: str, sid: str, sdir: Path, nom: str) -> None:
        """Character set pixelforge : un asset « animations » avec la liste ordonnée des éléments.

        px32/ (versionné) : <élément>_sheet.png (une rangée de cases), animations.json (fps, loop,
        count), set.json (canevas, feet_y, éléments, contrôles). hd/ (local, peut manquer) : idem
        en HD ; ajouté à chaque élément (`hd`) s'il est là. Les cases ne sont pas recadrées : même
        échelle pour toutes les animations du set."""
        px, hd = sdir / "px32", sdir / "hd"
        sp = self._json(px / "set.json")
        sh = self._json(hd / "set.json") if (hd / "set.json").exists() else {}
        ap, ah = self._json(px / "animations.json"), self._json(hd / "animations.json")
        key = sid if fam == "persos" else f"{fam}/{sid}"
        aid = f"blackout/{fam}/{sid}/animations"
        # set.json ne liste que les éléments de la dernière tâche intégrée (iteration.py, un job par élément) :
        # animations.json tient le set complet.
        noms_el = list((sp.get("elements") or {}).keys())
        noms_el += [n for n in ap if n not in noms_el]
        if fam == "persos":
            noms_el = [n for n in BK_ELEMENTS_PERSO if n in noms_el] + [n for n in noms_el if n not in BK_ELEMENTS_PERSO]
        elif "profile" in noms_el or "portrait" in noms_el:
            noms_el = [n for n in ("profile", "portrait") if n in noms_el] + [n for n in noms_el if n not in ("profile", "portrait")]
        anims: list[dict] = []
        srcs = [p for p in (px / "set.json", px / "animations.json") if p.exists()]

        def planche(d: Path, s: dict, a: dict, name: str, sub: str) -> dict | None:
            png = d / f"{name}_sheet.png"
            if not png.exists():
                return None
            meta = {**((s.get("elements") or {}).get(name) or {}), **(a.get(name) or {})}
            canvas = meta.get("size") or s.get("canvas") or [64, 64]
            cw, ch = int(canvas[0]), int(canvas[1])
            img = Image.open(png).convert("RGBA")
            ch = min(ch, img.height)
            n = max(1, min(int(meta.get("count") or meta.get("frames") or img.width // cw), img.width // cw))
            rel = f"blackout/{fam}/{sid}/{sub}/{name}.png"
            if img.width == cw * n and img.height == ch:
                self.copy(png, rel)
            else:
                self.save_png(img.crop((0, 0, cw * n, ch)), rel)
            poster = self.save_png(img.crop(((n // 2) * cw, 0, (n // 2 + 1) * cw, ch)),
                                   f"blackout/{fam}/{sid}/{sub}/_poster/{name}.png")
            fps = float(meta.get("fps") or 8)
            return {"frames": n, "fps": int(fps) if fps.is_integer() else fps, "loop": bool(meta.get("loop", False)),
                    "w": cw, "h": ch, "file": rel, "poster": poster, "png": png,
                    "feet": [cw // 2, int(s.get("feet_y") or ch)]}

        for name in noms_el:
            p = planche(px, sp, ap, name, "px32")
            if p is None:
                continue
            srcs.append(p.pop("png"))
            entry = {"name": name, **p, **self.bk_element_desc(fam, sid, name, [sp, sh])}
            h = planche(hd, sh, ah, name, "hd") if sh else None
            if h is not None:
                h.pop("png")
                entry["hd"] = {k: h[k] for k in ("frames", "fps", "loop", "w", "h", "file", "poster", "feet")}
            anims.append(entry)
            self.libelles.setdefault(name, entry["libelle"])
        if not anims:
            return

        def controles(s: dict) -> dict:
            c = s.get("controls") or {}
            out = {k: v for k, v in c.items() if isinstance(v, (int, float, str, bool)) and not isinstance(v, dict)}
            out["warnings"] = [str(w) for w in c.get("warnings") or []]
            return out

        style, pnj, _ = self._sources_desc()
        fiche = ((style.get("persos") or {}).get(sid) if fam == "persos"
                 else (pnj.get("humains") or {}).get(sid) if fam == "pnj"
                 else (pnj.get("animaux") or {}).get(sid) if fam == "animaux" else None) or {}
        placeholder = bool(sp.get("placeholder") or sh.get("placeholder"))
        warnings = controles(sp)["warnings"] + ([f"HD : {w}" for w in controles(sh)["warnings"]] if sh else [])
        info = {"famille": fam, "id": sid, "nom": nom, "asset": aid, "placeholder": placeholder,
                "description": fiche.get("description", ""), "signature": fiche.get("signature", ""),
                "type": fiche.get("type", ""), "hd": bool(sh), "taille": sp.get("size", ""),
                "case": sp.get("canvas") or [anims[0]["w"], anims[0]["h"]], "feet_y": sp.get("feet_y"),
                "controles": {"px32": controles(sp), **({"hd": controles(sh)} if sh else {})},
                "warnings": warnings, "elements": [a["name"] for a in anims]}
        # Profils de référence (Julien 24/10 : ils portent toutes les variations) : le neutre, puis un par
        # expression (hd/profile_<clé>_hd.png, portrait_<clé>_hd.png, rapatriés par iteration.py integre).
        profils = []
        for f in sorted(hd.glob("profile*_hd.png")) if hd.is_dir() else []:
            k = f.name[len("profile"):-len("_hd.png")].strip("_") or "neutre"
            pr = hd / f.name.replace("profile", "portrait", 1)
            profils.append({"expression": k, "profile": self.copy(f, f"blackout/{fam}/{sid}/profils/{f.name}"),
                            **({"portrait": self.copy(pr, f"blackout/{fam}/{sid}/profils/{pr.name}")} if pr.exists() else {})})
            srcs.append(f)
        profils.sort(key=lambda x: (x["expression"] != "neutre", x["expression"]))
        info["profils"] = profils
        self.sets[key] = info
        prev = next((a for a in anims if a["name"] == "profile"), anims[0])
        self.add(id=aid, cat=CAT_BK_PERSOS, group=key, kind="anim", name=f"{nom} · animations", type="sprite",
                 smooth=False, version=short_hash(*srcs), w=prev["w"], h=prev["h"], file=prev["poster"],
                 preview=prev["poster"], anims=anims, set=info,
                 note=f"{len(anims)} éléments, cases de {prev['w']} px" + (" + HD" if sh else "")
                      + (" · PLACEHOLDER" if placeholder else "")
                      + (f" · ⚠ {len(warnings)} avertissement(s)" if warnings else ""))

    def bk_perso(self, pid: str, pdir: Path) -> None:
        anims: list[dict] = []
        masks: list[dict] = []
        used: set[str] = set()
        srcs: list[Path] = []
        mask_srcs: list[Path] = []
        preview = ""
        jsons = [j for j in pdir.glob("*.json") if (pdir / f"{j.stem}.png").exists()]
        order = {n: i for i, n in enumerate(BK_ANIM_ORDER)}
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
            # Raccord du jeu (bk_perso.gd) : recalage par image, décalage et échelle de la planche,
            # pour que le lecteur plein écran montre ce que voit le joueur.
            offs = meta.get("frame_offsets") or []
            if any(abs(float(o[0])) + abs(float(o[1])) > 0.01 for o in offs[:n]):
                info["offs"] = [[round(float(o[0]), 1), round(float(o[1]), 1)] for o in offs[:n]]
            dec = meta.get("decalage")
            if isinstance(dec, list) and len(dec) == 2 and (dec[0] or dec[1]):
                info["dec"] = [float(dec[0]), float(dec[1])]
            if float(meta.get("echelle", 1.0)) != 1.0:
                info["echelle"] = float(meta["echelle"])
            # Glissement du perso DANS la planche (tête : haut de la silhouette), brut et après le
            # raccord du jeu : un perso qui « défile » vient de la planche, pas du lecteur.
            # Tout le corps glisse si la tête (haut de la silhouette) ET les pieds (bas) se déplacent :
            # on retient le plus petit des deux écarts (un geste de bras ou un pas n'y suffit pas).
            hauts, bas = [], []
            for fr in frames:
                ys_, xs_ = np.nonzero(fr[..., 3] > 128)
                if len(ys_) == 0:
                    hauts.append(None)
                    bas.append(None)
                    continue
                h_ = (ys_.max() - ys_.min()) * 0.2
                hauts.append(float(xs_[ys_ <= ys_.min() + h_].mean()))
                bas.append(float(xs_[ys_ >= ys_.max() - min(h_, 10)].mean()))
            idx_ = [i for i, t in enumerate(hauts) if t is not None]
            if idx_:
                dx = float(dec[0]) if isinstance(dec, list) and len(dec) == 2 else 0.0
                def ecart(vals, jeu_):
                    v = [vals[i] + ((float(offs[i][0]) if i < len(offs) else 0.0) + dx if jeu_ else 0.0) for i in idx_]
                    return max(v) - min(v)
                brut = min(ecart(hauts, False), ecart(bas, False))
                jeu = min(ecart(hauts, True), ecart(bas, True))
                if max(brut, jeu) >= 8:
                    info["glisse"] = [round(brut), round(jeu)]
            feet = meta.get("feet_anchor")
            if isinstance(feet, list) and len(feet) == 2:
                info["feet"] = [int(feet[0]) - int(x0), int(feet[1]) - int(y0)]   # repère des pieds, recadré
            cut = Image.fromarray(np.concatenate([fr[y0:y1, x0:x1] for fr in frames], axis=1), "RGBA")
            f = self.save_png(cut, f"blackout/persos/{pid}/anims/{name}.png")
            # Image fixe des vignettes (case du milieu) : la planche n'est chargée qu'au survol.
            poster = self.save_png(Image.fromarray(frames[n // 2][y0:y1, x0:x1], "RGBA"),
                                   f"blackout/persos/{pid}/anims/_poster/{name}.png")
            anims.append({"name": name, **info, "file": f, "poster": poster})
            srcs += [png, j]
            if name == "idle" or not preview:
                preview = self.save_png(Image.fromarray(frames[0][y0:y1, x0:x1], "RGBA"),
                                        f"blackout/persos/{pid}/anims/_preview.png")
            if tenue.exists():
                m = np.array(Image.open(tenue).convert("RGBA"))
                mcut = np.concatenate([m[:ch, i * cw + x0:i * cw + x1][y0:y1] for i in range(n)], axis=1)
                mf = self.save_png(Image.fromarray(mcut, "RGBA"), f"blackout/persos/{pid}/masques/{name}.png")
                mp = self.save_png(Image.fromarray(mcut[:, (n // 2) * w:(n // 2 + 1) * w], "RGBA"),
                                   f"blackout/persos/{pid}/masques/_poster/{name}.png")
                masks.append({"name": name, **info, "file": mf, "poster": mp})
                mask_srcs.append(tenue)
        if anims:
            tenue_desc = ""
            try:
                tenue_desc = json.loads(jsons[0].read_text()).get("tenue", "")
            except (OSError, ValueError):
                pass
            self.add(id=f"blackout/persos/{pid}/animations", cat=CAT_BK_PERSOS, group=pid, kind="anim",
                     name=f"{pid} · animations", type="sprite", smooth=True, version=short_hash(*srcs),
                     w=anims[0]["w"], h=anims[0]["h"], file=preview, preview=preview, anims=anims,
                     note=f"{len(anims)} animations, cases de 256 px recadrées sur l'union des frames")
            if masks:
                mprev = self.save_png(Image.open(self.out / masks[0]["file"]).crop(
                    (0, 0, masks[0]["w"], masks[0]["h"])), f"blackout/persos/{pid}/masques/_preview.png")
                self.add(id=f"blackout/persos/{pid}/masques", cat=CAT_BK_PERSOS, group=pid, kind="masque",
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
            self.add(id=rel, cat=CAT_BK_PERSOS, group=pid, kind="modele" if modele else "src",
                     name=f"{pid} · {'profil validé' if modele else png.stem}", type="image", smooth=True,
                     version=short_hash(png), w=img.width, h=img.height, file=f, preview=f, note="")

    def bk_candidats(self, pid: str) -> None:
        """Un lot par génération (profil, retouche…), le plus récent en premier."""
        lots = sorted((d for d in (BK_CANDIDATS / pid).glob("*") if d.is_dir()),
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
                img.thumbnail((BK_CANDIDAT_MAX, BK_CANDIDAT_MAX), Image.LANCZOS)
                f = self.save_png(img, f"blackout/candidats/{pid}/{pdir.name}/image_{num}.png")
                self.add(id=self.rel_src(png), cat=CAT_BK_PERSOS, group=pid, kind="candidat",
                         name=f"{pid} · {pdir.name} · variante {int(num) + 1}", type="image", smooth=True,
                         version=short_hash(png), w=img.width, h=img.height, file=f, preview=f,
                         note="candidat, réduit" + (f" · prompt : {prompt}" if prompt else ""))

    def bk_map(self) -> None:
        from PIL import ImageDraw, ImageFont
        for mdir in sorted(p for p in (ASSETS / "maps").glob("*") if p.is_dir()):
            mid = mdir.name
            pngs = sorted(mdir.glob("*.png"))
            for png in pngs:
                rel = self.rel_src(png)
                img = Image.open(png)
                f = self.copy(png, rel)
                self.add(id=rel, cat=CAT_BK_MAP, group=mid, kind="carte", name=f"{mid} · {png.stem}",
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
                self.add(id=rel, cat=CAT_BK_MAP, group=mid, kind="carte", name=f"{mid} · aperçu",
                         type="image", version=short_hash(*srcs), w=img.width, h=img.height, file=f, preview=f,
                         note=f"rendu depuis map.txt ({gw}×{gh} cases, {t} px par case) et zones.json · "
                              "mur gris, sol beige, eau bleue, bateau blanc, caisse brune, objet bas sable, "
                              "cachette orange, sortie verte, départ violet")
            for js in sorted(mdir.glob("*.json")):
                self.data(js, CAT_BK_MAP, mid)

    def data(self, js: Path, cat: str, group: str, kind: str = "data") -> None:
        rel = self.rel_src(js)
        f = self.copy(js, rel)
        self.add(id=rel, cat=cat, group=group, kind=kind, name=f"{group} · {js.stem}", type="data",
                 version=short_hash(js), file=f, preview="", note="JSON")

    def bk_mannequin(self) -> None:
        for mdir in sorted(p for p in (BK / "mannequin").glob("*") if p.is_dir()):
            for png in sorted(mdir.glob("*.png")):
                rel = self.rel_src(png)
                img = Image.open(png)
                f = self.copy(png, rel)
                self.add(id=rel, cat=CAT_BK_MANNEQUIN, group=mdir.name, kind="piece",
                         name=f"{mdir.name} · {png.stem}", type="image", smooth=True, version=short_hash(png),
                         w=img.width, h=img.height, file=f, preview=f, note="pièce du pantin")
            for js in sorted(mdir.glob("*.json")):
                self.data(js, CAT_BK_MANNEQUIN, mdir.name)
        for js in sorted((BK / "choreo").glob("*.json")):
            self.data(js, CAT_BK_MANNEQUIN, "chorégraphies", "choreo")

    def bk_objets(self, carte: str, ddir: Path) -> None:
        """Décor en images d'une carte (<ddir>/index.json) : objets avec leurs masques, sols.

        Le calque des masques est une image transparente de la taille de l'objet, à poser
        dessus : violet = zone qui cache le perso (occluder), vert = emprise au sol qui bloque
        (footprint), orange = contact au sol. « sans masque » : pas de masks.json pixelforge,
        ou le jeu utilise le calcul local de repli (_sources.json, port seulement).
        Un élément dont l'image est celle d'une autre carte (res://…) n'est pas recopié : on note
        la reprise sur l'asset existant (`decor.cartes`, `decor.reprises`)."""
        idx_path = ddir / "index.json"
        if not idx_path.exists():
            return
        elements = json.loads(idx_path.read_text(encoding="utf-8")).get("elements", {})
        port = carte == "port_pecheurs"
        src_path = BK_MASQUES / "jeu" / "_sources.json"
        sources = json.loads(src_path.read_text(encoding="utf-8")) if port and src_path.exists() else {}
        for eid, e in elements.items():
            fichiers = []
            for f in e.get("fichiers") or []:
                p = ROOT / f[len("res://"):] if f.startswith("res://") else ddir / f
                if p.exists():
                    fichiers.append(p)
            zones = e.get("zones") or e.get("zones_des_poses") or []
            anim = (e.get("animation") or {}).get("description", "")
            base = {"nom": e.get("nom", eid), "categorie": e.get("categorie", ""), "type": e.get("type", ""),
                    "zones": zones, "cases": e.get("taille_cases"), "carte": carte, "cartes": [carte], "element": eid,
                    "provisoire": bool(e.get("provisoire") or e.get("provisoire_png") or e.get("placeholder")),
                    "prompt": self.decor_prompts.get((carte, eid), ""), "anim": anim}
            if not fichiers:
                self.bk["decor_a_venir"].append({"id": eid, **base})
                continue
            png = fichiers[0]
            rel = self.rel_src(png)
            if rel in self.by_id:            # image reprise d'une autre carte
                d = self.by_id[rel].setdefault("decor", {})
                if carte not in d.setdefault("cartes", []):
                    d["cartes"].append(carte)
                d.setdefault("reprises", []).append({"carte": carte, "element": eid, "nom": base["nom"], "zones": zones})
                self.decor_ids[(carte, eid)] = rel
                continue
            self.decor_ids[(carte, eid)] = rel
            img = Image.open(png)
            f = self.copy(png, rel)
            if e.get("type", "").startswith("tuile"):
                self.add(id=rel, cat=CAT_BK_OBJETS, group="sols", kind="sol", name=base["nom"], type="image",
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
                    "blocks_view": (masks or {}).get("blocks_view", jeu.get("bloque_vue", e.get("bloque_vue"))),
                    "camera": (masks or {}).get("camera", ""), "shapes": (masks or {}).get("shapes", []),
                    "sans_masque": source != "pixelforge", "sources": e.get("sources") or []}
            # Calque coloré, aligné pixel pour pixel (même taille que l'objet).
            calque = np.zeros((img.height, img.width, 4), dtype=np.uint8)
            poses = []
            for name, color in BK_MASK_COLORS:
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
                sub = "" if port else f"{carte}/"
                info["calque"] = self.save_png(Image.fromarray(calque, "RGBA"), f"blackout/decor/calques/{sub}{eid}.png")
            info["masques"] = poses
            if mj.exists():
                srcs.append(mj)
            vues = [("ombre", ddir / e["ombre"] if e.get("ombre") else None),
                    ("ouvert", ddir / e["ouvert"] if isinstance(e.get("ouvert"), str) else None)]
            if port:
                vues += [("controle", BK_MASQUES / "jeu" / f"{eid}.png"), ("apercu_pf", BK_MASQUES / f"{eid}.png")]
            for key, path in vues:
                if path is not None and path.exists():
                    im = Image.open(path)
                    info[key] = {"file": self.copy(path, self.rel_src(path)), "w": im.width, "h": im.height}
            self.add(id=rel, cat=CAT_BK_OBJETS, group="objets", kind="objet", name=base["nom"], type="image",
                     smooth=True, version=short_hash(*srcs), w=img.width, h=img.height, file=f, preview=f,
                     decor=info, note=f"{eid} · {base['categorie']}")

    def bk_decor_anims(self) -> None:
        """Animations du décor (assets/blackout/decor/anims/<id>.png + .json, une rangée de cases) :
        une planche par élément, cases réduites à BK_DECOR_ANIM_MAX px de côté au plus."""
        adir = BK / "decor" / "anims"
        for j in sorted(adir.glob("*.json")):
            png = adir / f"{j.stem}.png"
            if not png.exists():
                continue
            meta = json.loads(j.read_text(encoding="utf-8"))
            cell = meta.get("cell", [256, 256])
            cw, ch = (int(cell[0]), int(cell[1])) if isinstance(cell, list) else (int(cell), int(cell))
            img = Image.open(png).convert("RGBA")
            n = min(int(meta.get("frames", img.width // cw)), img.width // cw)
            if n <= 0:
                continue
            k = min(1.0, BK_DECOR_ANIM_MAX / max(cw, ch))
            w, h = max(1, round(cw * k)), max(1, round(ch * k))
            strip = img.crop((0, 0, cw * n, ch)).resize((w * n, h), Image.LANCZOS) if k < 1 else img.crop((0, 0, cw * n, ch))
            eid = j.stem
            f = self.save_png(strip, f"blackout/decor/anims/{eid}.png")
            poster = self.save_png(strip.crop(((n // 2) * w, 0, (n // 2 + 1) * w, h)), f"blackout/decor/anims/_poster/{eid}.png")
            fps = float(meta.get("fps", 10))
            anim = {"name": eid, "frames": n, "fps": int(fps) if fps.is_integer() else fps, "loop": bool(meta.get("loop", True)),
                    "w": w, "h": h, "file": f, "poster": poster}
            objet = self.decor_ids.get(("port_pecheurs", eid), "")
            nom = (self.by_id.get(objet) or {}).get("name", eid)
            self.add(id=self.rel_src(png), cat=CAT_BK_OBJETS, group="animations", kind="decor_anim",
                     name=f"{nom} · animation", type="sprite", smooth=True, version=short_hash(png, j),
                     w=w, h=h, file=poster, preview=poster, anims=[anim],
                     decor={"nom": nom, "carte": "port_pecheurs", "cartes": ["port_pecheurs"], "element": eid,
                            "categorie": "animation", "objet": objet, "methode": f"{meta.get('mode', '')} {meta.get('kind', '')}".strip(),
                            "piste": meta.get("piste", ""), "zones": (self.by_id.get(objet) or {}).get("decor", {}).get("zones", [])},
                     note=f"{n} images à {anim['fps']} i/s · {meta.get('piste', '')}")
            self.tache(self.rel_src(png), tid=meta.get("source_task"), quoi="animation", style="pf_2d__loop")

    def bk_decor(self) -> None:
        for sub, group in (("textures", "textures"), ("models", "modèles")):
            for png in sorted((BK / sub).glob("*.png")):
                rel = self.rel_src(png)
                img = Image.open(png)
                f = self.copy(png, rel)
                self.add(id=rel, cat=CAT_BK_DECOR, group=group, kind=sub, name=f"{group} · {png.stem}",
                         type="image", smooth=True, version=short_hash(png), w=img.width, h=img.height,
                         file=f, preview=f, note="texture de modèle 3D (.glb non affichable)" if sub == "models" else "")

    def run(self) -> None:
        if self.out.exists():
            shutil.rmtree(self.out)
        self.out.mkdir(parents=True)
        self.blackout()
        cat_rank = {c: i for i, c in enumerate(CATEGORIES)}
        self.assets.sort(key=lambda a: cat_rank[a["cat"]])     # tri stable : ordre de construction
        index = {
            "commit": git_commit(),
            "generated_at": int(time.time()),
            "categories": CATEGORIES,
            "sections": SECTIONS,
            "blackout": self.bk,
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
