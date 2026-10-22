"""Gameplay de Blackout pour /producer (importé par build_index.py) : règles lisibles, options de
partie validées, écrans de menu, cartes de jeu (zones, sorties, cachettes, chiffres d'équilibrage),
jalons de la spec.

Chaque règle (groupe), option et écran devient un « asset » de type « jeu » (id `jeu/…`) : on peut
lier une carte du kanban à lui (champ asset) et le commenter comme une image, avec sa version
(empreinte de ses valeurs). Les cartes de jeu gardent l'id de leur aperçu (`maps/<id>/map.txt`).
Lecture seule du dépôt.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RULES = ROOT / "data" / "blackout" / "rules.json"
OPTIONS = ROOT / "data" / "blackout" / "options_partie.json"
NAV = ROOT / "src" / "blackout" / "menus" / "bk_nav.gd"
PARTIE_RAPIDE = ROOT / "src" / "blackout" / "menus" / "bk_partie_rapide.gd"
SPEC = ROOT / "SPEC-GORDEKA.md"
EQUILIBRAGE = ROOT / "docs" / "GORDEKA_EQUILIBRAGE.md"
CAPTURES = ROOT / "docs" / "captures" / "ecrans"       # <id>.png, faites par tools/producer/captures_ecrans.sh
MAPS = ROOT / "assets" / "maps"

# Groupes de règles, dans l'ordre d'affichage : (id, titre, clé _doc_* qui le décrit, clés ou préfixes).
GROUPES = [
    ("partie", "Partie et phases", "_doc_versus",
     ["tile_px", "phase_draw", "phase_versus", "rounds_", "joueurs_", "phase_hide", "phase_hunt", "phase_end"]),
    ("sorties", "Sorties", "", ["exits_open_at", "extract_hold", "exits_per_round", "exits_min_gap"]),
    ("vision", "Vision et capture", "", ["capture_", "cone_", "near_radius", "use_range", "scared_range"]),
    ("deplacements", "Déplacements", "", ["body_radius", "speed_", "turn_speed_deg"]),
    ("pouvoirs", "Pouvoirs : pièges et détection", "", ["trap_", "detect_"]),
    ("cachettes", "Cachettes", "_doc_cachette", ["hide_", "search_time", "cachette_"]),
    ("decor", "Décor, masques et vue", "_doc_decor", ["decor_", "masque_"]),
    ("idees", "Idées validées : fantômes, gâteaux, mouettes", "_doc_idees",
     ["idee_chatouille", "chatouille_", "idee_delivrance", "delivrance_", "idee_grince", "grince_", "idee_bredouille",
      "bredouille_", "idee_gateaux", "gateaux_nombre", "gateau_", "idee_mouettes", "mouettes_"]),
    ("tension", "Tension et mouvement", "_doc_tension",
     ["idee_detection", "detection_", "idee_frisson", "frisson_", "idee_mouvement", "gateaux_reapparition",
      "mouvement_", "idee_ronde", "ronde_"]),
    ("poursuite", "Poursuite (essai)", "_doc_poursuite", ["idee_poursuite", "poursuite_"]),
    ("grottes", "Grottes sombres (essai)", "_doc_grottes", ["idee_grottes", "grotte_"]),
    ("emotes", "Emotes", "", ["emote_"]),
    ("score", "Score", "", ["score"]),
    ("animations", "Raccord des animations", "_doc_anims", ["anim_", "anims"]),
    ("ia", "IA (Facile, Normal, Malin)", "", ["ai"]),
    ("persos", "Persos et couleurs", "", ["characters", "bot_names", "colors", "color_names"]),
]

# Libellés (et unité) des règles ; une clé absente s'affiche telle quelle.
LIBELLES = {
    "tile_px": ("Taille d'une case", "px"), "phase_draw": ("Tirage du chasseur", "s"),
    "phase_versus": ("Écran Versus", "s"), "rounds_defaut": ("Rounds par partie (0 = un par joueur)", ""),
    "rounds_min": ("Rounds au minimum", ""), "rounds_max": ("Rounds au maximum", ""),
    "joueurs_min": ("Joueurs au minimum", ""), "joueurs_max": ("Joueurs au maximum", ""),
    "joueurs_defaut": ("Joueurs par défaut", ""), "phase_hide": ("Temps pour se cacher", "s"),
    "phase_hunt": ("Durée de la chasse", "s"), "phase_end": ("Fin de round (scores)", "s"),
    "exits_open_at": ("Ouverture des sorties après", "s"), "extract_hold": ("Temps pour sortir par une sortie", "s"),
    "exits_per_round": ("Sorties ouvertes par round", ""), "exits_min_gap": ("Écart minimal entre deux sorties", "cases"),
    "capture_time": ("Temps de capture (vu en plein)", "s"), "capture_decay": ("Jauge de capture : baisse", "/s"),
    "cone_deg": ("Ouverture du cône de vision", "°"), "cone_range": ("Portée du cône de vision", "cases"),
    "near_radius": ("Vu de tout près (rayon)", "cases"), "use_range": ("Portée pour utiliser (cachette, sortie)", "cases"),
    "scared_range": ("Peur du chasseur (fuite) à", "cases"),
    "decor_formes": ("Formes du décor (collision et vue par forme)", "on/off"),
    "decor_masques_pf": ("Masques pixelforge prioritaires", "on/off"),
    "decor_masques_pf_confiance_min": ("Confiance minimale des masques pixelforge", ""),
    "decor_masques_pf_part_max": ("Emprise pixelforge maximale (part de la silhouette)", ""),
    "decor_profondeur_min": ("Profondeur minimale d'une emprise", "cases"),
    "decor_finesse_px": ("Parties fines ignorées (mât, pieds) sous", "px"),
    "masque_vue_portee": ("Le chasseur voit derrière un objet à", "cases"),
    "masque_fondu": ("Opacité de l'objet vu par les coéquipiers", ""),
    "body_radius": ("Rayon du corps", "cases"), "speed_hider": ("Vitesse d'un chassé", "cases/s"),
    "speed_hunter": ("Vitesse du chasseur", "cases/s"), "speed_ghost": ("Vitesse d'un fantôme", "cases/s"),
    "turn_speed_deg": ("Vitesse de rotation", "°/s"),
    "trap_cooldown": ("Piège : recharge", "s"), "trap_max": ("Pièges posés au plus", ""),
    "trap_slow": ("Piège : vitesse du chasseur pris", "×"), "trap_duration": ("Piège : durée", "s"),
    "trap_seen_range": ("Piège visible par le chasseur à", "cases"),
    "detect_cooldown": ("Détection : recharge", "s"), "detect_radius": ("Détection : rayon", "cases"),
    "detect_duration": ("Détection : durée", "s"), "detect_hint_duration": ("Détection : indice affiché", "s"),
    "hide_max": ("Temps maximal dans une cachette", "s"), "hide_lock": ("Cachette fermée aux autres pendant", "s"),
    "search_time": ("Temps pour fouiller une cachette", "s"),
    "cachette_open_s": ("Ouverture d'une cachette", "s"), "cachette_close_s": ("Fermeture d'une cachette", "s"),
    "cachette_dive_min": ("Plongée dans la cachette (min.)", "s"), "cachette_dive_max": ("Plongée dans la cachette (max.)", "s"),
    "cachette_out_s": ("Sortie de cachette", "s"), "cachette_squash": ("Écrasement (squash)", ""),
    "cachette_squash_s": ("Durée de l'écrasement", "s"), "cachette_shake_in": ("Tremblement à l'entrée", ""),
    "cachette_shake_out": ("Tremblement à la sortie", ""), "cachette_shake_search": ("Tremblement à la fouille", ""),
    "cachette_shake_found": ("Tremblement quand trouvé", ""), "cachette_shiver_gap": ("Frémissement : toutes les", "s"),
    "cachette_shiver_s": ("Frémissement : durée", "s"),
    "anim_raccord": ("Raccord des planches (échelle, calage)", "on/off"), "anim_entrees": ("Entrée des boucles au plus proche", "on/off"),
    "anim_fondu_s": ("Fondu enchaîné au plus", "s"), "anim_fondu_ecart_min": ("Fondu : écart minimal des silhouettes", ""),
    "anim_fondu_ecart_plein": ("Fondu : écart pour un fondu entier", ""), "anim_pouf_s": ("Pouf (squash & stretch) : durée", "s"),
    "anim_pouf_k": ("Pouf : amplitude", ""), "anim_piege_marche": ("Chasseur piégé qui marche", "on/off"),
    "anim_reveal_avance": ("Lampe du chasseur allumée en avance", "on/off"), "anim_durees": ("Durées des gestes appliquées", "on/off"),
    "anims": ("Réglages par animation", ""),
    "idee_chatouille": ("Chatouille", "on/off"), "chatouille_portee": ("Chatouille : portée", "cases"),
    "chatouille_cooldown": ("Chatouille : recharge", "s"), "chatouille_duree": ("Chatouille : durée du fou rire", "s"),
    "chatouille_lent": ("Chatouille : vitesse du chasseur", "×"), "chatouille_repit": ("Chatouille : répit", "s"),
    "idee_delivrance": ("Délivrance", "on/off"), "delivrance_portee": ("Délivrance : portée", "cases"),
    "delivrance_temps": ("Délivrance : temps", "s"), "delivrance_max": ("Délivrances par manche", ""),
    "idee_grince": ("Cachette qui grince", "on/off"), "grince_apres": ("Grince après", "s"),
    "grince_ecart": ("Grince : écart", "s"), "grince_ouie": ("Grince : entendu à", "cases"),
    "idee_bredouille": ("Chasseur bredouille plus rapide", "on/off"), "bredouille_apres": ("Bredouille après", "s"),
    "bredouille_vitesse": ("Bredouille : vitesse", "×"),
    "idee_gateaux": ("Gâteaux basques", "on/off"), "gateaux_nombre": ("Nombre de gâteaux", ""),
    "gateau_portee": ("Gâteau : portée", "cases"), "gateau_sprint": ("Gâteau : sprint", "×"),
    "gateau_duree": ("Gâteau : durée du sprint", "s"),
    "idee_mouettes": ("Mouettes", "on/off"), "mouettes_nombre": ("Groupes de mouettes", ""),
    "mouettes_portee": ("Mouettes : s'envolent à", "cases"), "mouettes_ouie": ("Mouettes : entendues à", "cases"),
    "mouettes_retour": ("Mouettes : reviennent après", "s"),
    "idee_detection": ("Détection progressive", "on/off"), "detection_temps_pres": ("Repéré de près en", "s"),
    "detection_temps_loin": ("Repéré de loin en", "s"), "detection_partiel": ("Corps en partie visible", "×"),
    "detection_decroissance": ("Jauge : baisse hors de vue", "/s"), "detection_doute": ("« ? » affiché dès", ""),
    "idee_frisson": ("Frisson du chassé", "on/off"), "frisson_portee": ("Frisson : distance", "cases"),
    "frisson_fouille_portee": ("« Il fouille à côté ! » à", "cases"),
    "idee_mouvement": ("Pousser à bouger", "on/off"), "gateaux_reapparition": ("Gâteaux : réapparition", "s"),
    "mouvement_fenetre_portee": ("IA : profite des fouilles à", "cases"), "mouvement_contourne": ("IA : contourne le chasseur", "proba."),
    "mouvement_relocate": ("IA : change de planque", "×"),
    "idee_ronde": ("Ronde du chasseur IA dans les recoins", "on/off"), "ronde_recoins": ("Rondes vers les recoins", "part"),
    "idee_poursuite": ("Poursuite", "on/off"), "poursuite_mult": ("Poursuite : vitesse", "×"),
    "poursuite_mult_chasseur": ("Poursuite : vitesse du chasseur (0 = commune)", "×"),
    "poursuite_mult_chasse": ("Poursuite : vitesse du chassé (0 = commune)", "×"),
    "poursuite_duree_s": ("Poursuite : durée", "s"), "poursuite_seuil": ("Poursuite : seuil de la jauge", ""),
    "poursuite_tant_que_vu": ("Poursuite : rechargée tant que vu", "on/off"),
    "poursuite_tous_vus": ("Poursuite : tous les chassés vus", "on/off"),
    "idee_grottes": ("Grottes sombres", "on/off"), "grotte_portee": ("Vue dans les grottes", "cases"),
    "emote_duration": ("Emote : durée", "s"), "emote_gap": ("Emote : écart", "s"), "emote_ai_rate": ("Emotes des IA", "/s"),
    "score": ("Points", ""), "characters": ("Persos", ""), "bot_names": ("Noms des IA", ""),
    "colors": ("Couleurs des joueurs", ""), "color_names": ("Noms des couleurs", ""), "ai": ("Niveaux d'IA", ""),
}
SCORE = {"hider_per_10s": "Chassé : toutes les 10 s caché", "hider_survive": "Chassé : survit au round",
         "hider_trap_hit": "Chassé : chasseur pris au piège", "hider_extract": "Chassé : sort par une sortie",
         "hunter_find": "Chasseur : trouve un chassé", "hunter_all": "Chasseur : les trouve tous",
         "ghost_tickle": "Fantôme : chatouille", "hider_rescue": "Chassé : délivre un fantôme",
         "hider_cake": "Chassé : mange un gâteau"}

# Écrans hors de BkNav.ECRANS (scripts sans scène propre), à la suite du parcours.
ECRANS_EN_PLUS = [("versus", "Versus", "src/blackout/bk_versus.gd"), ("podium", "Podium", "src/blackout/bk_podium.gd")]
NOMS_ECRANS = {"qui_joue": "Qui joue ?", "accueil": "Accueil", "profil": "Mon profil", "reglages": "Réglages",
               "partie_rapide": "Partie rapide", "en_ligne": "En ligne", "game": "Partie (jeu et HUD)",
               "versus": "Versus", "podium": "Podium"}
ORDRE_ECRANS = ["qui_joue", "accueil", "profil", "reglages", "partie_rapide", "en_ligne", "versus", "game", "podium"]
# Mots qui rattachent une section de GORDEKA_EQUILIBRAGE.md à une carte.
CARTES_MOTS = {"plage": ["Plage", "Côte des Basques"], "parc_mazon": ["Parc Mazon"], "port_pecheurs": ["Port des Pêcheurs"]}


def empreinte(data) -> str:
    return hashlib.sha256(json.dumps(data, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:10]


def unite(cle: str) -> str:
    if cle in LIBELLES:
        return LIBELLES[cle][1]
    return ""


def doc_gd(path: Path) -> str:
    """Commentaire de doc (lignes `##`) en tête d'un script GDScript, jusqu'au premier code."""
    if not path.exists():
        return ""
    lignes = []
    for ln in path.read_text(encoding="utf-8").splitlines():
        s = ln.strip()
        if s.startswith("##"):
            lignes.append(s[2:].strip())
        elif lignes and (s == "" or not s.startswith(("class_name", "extends", "#"))):
            break
    return " ".join(lignes)


def regles(add) -> list[dict]:
    """Un asset par groupe de règles ; renvoie la liste des groupes (pour l'index)."""
    data = json.loads(RULES.read_text(encoding="utf-8"))
    pris: set[str] = set()
    out = []
    for gid, titre, doc_key, cles in GROUPES:
        items = []
        for k, v in data.items():
            if k.startswith("_") or k in pris:
                continue
            if any(k == c or (c.endswith("_") and k.startswith(c)) for c in cles):
                pris.add(k)
                lib, u = LIBELLES.get(k, (k, ""))
                item = {"cle": k, "libelle": lib, "unite": u, "valeur": v}
                if k == "score":
                    item["details"] = {s: SCORE.get(s, s) for s in v}
                items.append(item)
        if not items:
            continue
        doc = data.get(doc_key, "") if doc_key else ""
        add(id=f"jeu/regles/{gid}", cat="Jeu", group="regles", kind="regles", name=f"Règles · {titre}", type="jeu",
            version=empreinte(items), file="", preview="", note="data/blackout/rules.json",
            jeu={"sorte": "regles", "titre": titre, "doc": doc, "items": items})
        out.append({"id": gid, "titre": titre, "asset": f"jeu/regles/{gid}"})
    reste = [k for k in data if not k.startswith("_") and k not in pris]
    if reste:
        items = [{"cle": k, "libelle": LIBELLES.get(k, (k, ""))[0], "unite": unite(k), "valeur": data[k]} for k in reste]
        add(id="jeu/regles/autres", cat="Jeu", group="regles", kind="regles", name="Règles · Autres", type="jeu",
            version=empreinte(items), file="", preview="", note="data/blackout/rules.json",
            jeu={"sorte": "regles", "titre": "Autres", "doc": "", "items": items})
        out.append({"id": "autres", "titre": "Autres", "asset": "jeu/regles/autres"})
    return out, data.get("_doc", "")


def options(add, liens: dict) -> list[str]:
    data = json.loads(OPTIONS.read_text(encoding="utf-8"))
    ids = []
    for o in data.get("options", []):
        aid = f"jeu/options/{o['id']}"
        add(id=aid, cat="Jeu", group="options", kind="option", name=f"Option · {o.get('libelle', o['id'])}", type="jeu",
            version=empreinte(o), file="", preview="", note="data/blackout/options_partie.json",
            jeu={"sorte": "option", **o})
        if o.get("carte_kanban"):
            liens.setdefault(aid, []).append(int(o["carte_kanban"]))
        ids.append(aid)
    return ids, data.get("_doc", "")


def ecrans(add, copy_capture) -> list[str]:
    src = NAV.read_text(encoding="utf-8") if NAV.exists() else ""
    trouves = dict(re.findall(r'"(\w+)":\s*"res://([^"]+\.tscn)"', src))
    liste = [(i, NOMS_ECRANS.get(i, i), p.replace(".tscn", ".gd")) for i, p in trouves.items()]
    liste += [e for e in ECRANS_EN_PLUS if e[0] not in trouves]
    liste.sort(key=lambda e: (ORDRE_ECRANS.index(e[0]) if e[0] in ORDRE_ECRANS else 99, e[0]))
    ids = []
    for i, nom, script in liste:
        role = doc_gd(ROOT / script)
        cap = CAPTURES / f"{i}.png"
        capture = copy_capture(cap) if cap.exists() else None
        info = {"sorte": "ecran", "ecran": i, "nom": nom, "script": script, "role": role,
                "scene": f"--scene=bk_{i}" if i in trouves else ""}
        if capture:
            info["capture"] = capture
        aid = f"jeu/ecrans/{i}"
        add(id=aid, cat="Jeu", group="ecrans", kind="ecran", name=f"Écran · {nom}", type="jeu",
            version=empreinte([info, cap.stat().st_mtime if cap.exists() else 0]), file=capture["file"] if capture else "",
            preview=capture["file"] if capture else "", note=script, jeu=info)
        ids.append(aid)
    return ids


def _cellules(ligne: str) -> list[str]:
    return [c.strip() for c in ligne.strip().strip("|").split("|")]


def chasseur_gagne(texte: str) -> str:
    """« F / N / M » du chasseur sur la version retenue d'une section d'équilibrage."""
    # (priorité, valeur) : « **retenue** » / « **final** » en gras l'emporte, puis « retenue » ; à égalité, la dernière.
    trouve = (0, "")
    tableau: list[list[str]] = []
    for ln in texte.splitlines() + [""]:
        if ln.startswith("|"):
            tableau.append(_cellules(ln))
            continue
        if tableau:
            tete, lignes = tableau[0], [r for r in tableau[1:] if not set("".join(r)) <= set("-: ")]
            col = next((i for i, h in enumerate(tete) if h.lower().startswith("chasseur gagne")), -1)
            if col >= 0:
                for r in lignes:
                    ligne = " ".join(r)
                    prio = 2 if re.search(r"\*\*[^*]*(retenue|final)[^*]*\*\*", ligne, re.I) else \
                        1 if re.search(r"retenue", ligne, re.I) else 0
                    if len(r) > col and prio and prio >= trouve[0]:
                        trouve = (prio, r[col])
            for r in lignes:
                if r and r[0].lower().startswith("chasseur gagne"):
                    gras = [c for c in r[1:] if c.startswith("**")]
                    trouve = (3, (gras or r[-1:])[-1])
            tableau = []
    return re.sub(r"\([^)]*\)", "", trouve[1]).replace("*", "").strip()


def equilibrage() -> list[dict]:
    """Sections « ## » de GORDEKA_EQUILIBRAGE.md (texte markdown), rattachées à une carte si possible."""
    if not EQUILIBRAGE.exists():
        return []
    sections, cur = [], None
    for ln in EQUILIBRAGE.read_text(encoding="utf-8").splitlines():
        if ln.startswith("## "):
            cur = {"titre": ln[3:].strip(), "texte": []}
            sections.append(cur)
        elif cur is not None:
            cur["texte"].append(ln)
    out = []
    for s in sections:
        texte = "\n".join(s["texte"]).strip()
        carte = next((c for c, mots in CARTES_MOTS.items() if any(m in s["titre"] for m in mots)), "")
        out.append({"titre": s["titre"], "carte": carte, "texte": texte,
                    "chasseur_gagne": chasseur_gagne(texte) if carte else ""})
    return out


def cartes(liens_chapeaux: dict) -> list[dict]:
    """Cartes de jeu : nom, version, taille, zones, sorties, cachettes, réglages propres, jouable."""
    src = PARTIE_RAPIDE.read_text(encoding="utf-8") if PARTIE_RAPIDE.exists() else ""
    m = re.search(r"const CARTES[^=]*=\s*\[(.*?)\]\s*\n\n", src, re.S)
    jouables = re.findall(r'\["(\w+)",\s*"([^"]+)"\]', m.group(1) if m else "")
    nom_menu = dict(jouables)
    sections = equilibrage()
    out = []
    for mdir in sorted(p for p in MAPS.glob("*") if p.is_dir()):
        mid = mdir.name
        z = json.loads((mdir / "zones.json").read_text(encoding="utf-8")) if (mdir / "zones.json").exists() else {}
        rows = [r for r in (mdir / "map.txt").read_text(encoding="utf-8").splitlines() if r] if (mdir / "map.txt").exists() else []
        txt = "".join(rows)
        eq = [s for s in sections if s["carte"] == mid]
        out.append({
            "id": mid, "nom": z.get("name", mid), "nom_menu": nom_menu.get(mid, ""), "version": z.get("version"),
            "jouable": mid in nom_menu, "asset": f"maps/{mid}/map.txt",
            "taille": [max((len(r) for r in rows), default=0), len(rows)],
            "sol": sum(txt.count(c) for c in ".:=tr"), "cachettes": txt.count("H"), "sorties_cases": txt.count("E"),
            "zones": [{"name": zz.get("name", ""), "rect": zz.get("rect"), "sombre": bool(zz.get("sombre"))}
                      for zz in z.get("zones", [])],
            "sorties": [e.get("zone", "") for e in z.get("exits", [])],
            "objets": len(z.get("objets", [])) or None, "regles": z.get("regles", {}), "passes": z.get("passes", []),
            "decor": z.get("decor", ""), "chapeau": liens_chapeaux.get(mid),
            "equilibrage": [{"titre": s["titre"], "texte": s["texte"], "chasseur_gagne": s["chasseur_gagne"]} for s in eq],
            "chasseur_gagne": next((s["chasseur_gagne"] for s in reversed(eq) if s["chasseur_gagne"]), ""),
        })
    out.sort(key=lambda c: (not c["jouable"], [j[0] for j in jouables].index(c["id"]) if c["jouable"] else 0, c["id"]))
    return out


def jalons_spec() -> list[dict]:
    """Jalons de SPEC-GORDEKA §14 (liste numérotée, sous-points), pour amorcer la roadmap."""
    if not SPEC.exists():
        return []
    dans, out = False, []
    for ln in SPEC.read_text(encoding="utf-8").splitlines():
        if ln.startswith("## "):
            dans = ln.startswith("## 14.")
            continue
        if not dans:
            continue
        m = re.match(r"^\d+\.\s+\*\*(.+?)\*\*\s*:?\s*(.*)$", ln)
        if m:
            out.append({"titre": m.group(1).strip(), "description": m.group(2).strip()})
        elif out and ln.strip().startswith("- "):
            out[-1]["description"] = (out[-1]["description"] + "\n" + ln.strip()).strip()
        elif out and ln.startswith("   ") and ln.strip():          # suite d'une ligne coupée
            out[-1]["description"] += " " + ln.strip()
    return out


def construit(add, copy_capture, liens: dict, liens_chapeaux: dict) -> dict:
    groupes, doc_regles = regles(add)
    opts, doc_options = options(add, liens)
    ecr = ecrans(add, copy_capture)
    return {"regles": groupes, "doc_regles": doc_regles, "options": opts, "doc_options": doc_options, "ecrans": ecr,
            "cartes": cartes(liens_chapeaux), "equilibrage": [{"titre": s["titre"], "carte": s["carte"]} for s in equilibrage()],
            "equilibrage_general": [s for s in equilibrage() if not s["carte"]],
            "jalons_spec": jalons_spec()}
