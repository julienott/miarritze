#!/usr/bin/env python3
"""Met en file chez pixelforge les cartes du chapeau « Décor du port » que Julien a passées en Todo
(Julien 2026-10-20 soir : 91 cartes en Todo 🌙). Carte 🌙 → priorité « night » (pixelforge les retient
d'elle-même jusqu'à 1 h, heure de Paris), sinon « normal ». La carte prise passe en Doing avec un
commentaire. Le pendant du matin est tools/producer/decor_matin.py (relève, planches, intégration).

  todo_decor.py [--essai]

Cartes reconnues (titre « <Nom de l'élément> : <quoi> », nom = `nom` de tools/gordeka/prompts_decor.json) :
  « : image »            pf_2d__prop (pf_2d__ground pour les sols et les bords), 2 variantes
  « : refaire de face »  pf_2d__prop (verrou de caméra mis d'office par pixelforge), 2 variantes
  « : version ouverte »  pf_hd__edit de l'image fermée retenue (index du décor), 2 variantes
  « : animation »        pf_2d__loop (warp / particles / video, un job par piste à comparer)
  « : masque v3 »        pf_2d__footprint sur l'image intégrée (comme tools/gordeka/masques_pf.py)
  « Décor · toit en tuiles : version calme »   pf_2d__ground, colors 6 + max_saturation
Une carte qui dépend d'une image pas encore choisie (version ouverte ou animation d'un objet sans image,
masque ou animation d'un objet dont l'image est refaite cette nuit) reste en Todo avec un commentaire :
decor_matin.py la dépose quand l'image est intégrée. Masques déjà en v3 et questions : commentaire seul.

Suivi : tools/gordeka/taches_decor_nuit.json ({carte: {sorte, element, jobs, statut, …}}). Idempotent :
une carte déjà suivie n'est ni redéposée ni recommentée.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
GK = os.path.join(ROOT, "tools", "gordeka")
sys.path.insert(0, HERE)
sys.path.insert(0, GK)
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import cli  # noqa: E402
import gen_anims_pf as pf  # noqa: E402
import envoie_decor as ed  # noqa: E402
import masques_pf as mp  # noqa: E402
import nuit  # noqa: E402   (nuit.ex.b64 : image -> base64)

from PIL import Image  # noqa: E402

CHAPEAU = 228                      # carte « Décor du port »
SUIVI = os.path.join(GK, "taches_decor_nuit.json")
DECOR = os.path.join(ROOT, "assets", "gordeka", "decor")
INDEX = os.path.join(DECOR, "index.json")
OUT_DECOR = os.path.join(ROOT, "tools", "rd", "out", "decor")
NIGHT_MAX = 2000                   # file « night » de pixelforge
SEED_NUIT = 11                     # graine neuve : les essais précédents (seed 1) sont en ligne
TAG = "miarritze/decor_nuit"

SORTES = {"image": "image", "refaire de face": "refaire", "version ouverte": "ouvert",
          "animation": "anim", "masque v3": "masque"}
STYLE_DE = {"image": "pf_2d__prop", "refaire": "pf_2d__prop", "ouvert": "pf_hd__edit",
            "anim": "pf_2d__loop", "masque": "pf_2d__footprint", "toit": "pf_2d__ground"}

# Descriptions réécrites (règle : jamais « no X », FLUX ajoute ce qu'on nomme ; consignes de
# retouches_recette.json remises à l'affirmative).
PROMPTS_NUIT = {
    "barque_mouillage": "Small traditional Basque wooden fishing boat floating on its own, horizontal (bow to the "
                        "right), brightly painted hull (white with a red, green or blue stripe), warm wooden inside "
                        "with a bench, two oars and a small coiled net, the whole hull visible on a plain background.",
    "cachette_malle_pelotes": "Big closed wicker trunk with a leather strap, its rounded lid shut and latched, a few "
                              "white pelota balls and a curved wicker chistera basket resting on top of the lid. "
                              "Clearly a hiding spot, with a warm orange #e08a2e accent.",
    "cachette_tas_filets_cachette": "A big soft messy heap of green and blue fishing nets made of visible criss-cross "
                                    "mesh lines, orange cork floats and a coiled rope tangled in it, like a pile of "
                                    "fabric on the quay. Clearly a hiding spot, with a warm orange #e08a2e accent.",
    "cachette_barque_retournee": "Small wooden rowing boat turned upside down and lying directly on the ground: its "
                                 "rounded painted hull bottom and keel on top, blue and white stripes, a green rim "
                                 "along the ground, seen from the front, horizontal. Clearly a hiding spot, with a "
                                 "warm orange #e08a2e accent.",
    "facade_labourdine": "Front wall of a Labourd Basque house seen straight from the front, a wide horizontal strip: "
                         "whitewashed #f4f1ea wall with red half-timbering beams, two small windows with Basque red "
                         "#9e1b1b shutters, a red wooden door, a flower box with pink hydrangeas.",
}
# Sols et bords : pf_2d__ground (tuile vue d'aplomb, répétable ; la matière seule, le trait est fait par code).
GROUND_NUIT = {
    "bord_quai_eau": {"prompt": "Golden sandstone harbour quay blocks meeting turquoise #2fa7b8 sea water, a band of "
                                "white sea foam and small ripples along the stones, seen straight from above, "
                                "calm flat colors.", "colors": 8},
    "mur_pierre": {"prompt": "Top of a thick old harbour wall seen straight from above: large flat dark grey-blue "
                             "capstones in neat staggered rows with rounded corners, golden sandstone #d9c39a joints, "
                             "calm and low contrast.", "colors": 6, "max_saturation": 0.25},
    "toit_tuiles": {"prompt": "Red clay Basque canal roof tiles seen straight from above: neat even staggered rows of "
                              "overlapping rounded tiles in two close warm terracotta tones, calm, regular and low "
                              "contrast, simple flat shapes.", "colors": 6, "max_saturation": 0.45},
}
# Animations en boucle (pf_2d__loop) : une piste par job, Julien compare sur la planche.
# Eau (Julien 2026-10-20) : « on parle de l'océan, il faudra animer bien plus cette partie » (houle, écume, reflets).
ANIMS = {
    "eau_mer": [
        {"quoi": "houle (warp water fort)", "mode": "warp", "kind": "water", "amplitude_px": 8, "waves": 3,
         "frames": 16, "fps": 8},
        {"quoi": "grande houle lente (warp water ample)", "mode": "warp", "kind": "water", "amplitude_px": 12,
         "waves": 2, "frames": 20, "fps": 8},
        {"quoi": "océan vivant (vidéo)", "mode": "video", "frames": 16, "fps": 8, "source": "hd",
         "prompt": "the ocean swell rolls slowly across the water, white foam crests form and fade on the waves, "
                   "bright sun glints sparkle on the surface, seamless gentle loop"},
    ],
    "bord_quai_eau": [
        {"quoi": "écume (warp water)", "mode": "warp", "kind": "water", "amplitude_px": 5, "waves": 2,
         "frames": 16, "fps": 8},
        {"quoi": "écume qui va et vient (vidéo)", "mode": "video", "frames": 16, "fps": 8,
         "prompt": "white sea foam washes up against the quay stones and draws back, small waves, gentle loop"},
    ],
    "tour_phare": [
        {"quoi": "faisceau qui tourne (vidéo)", "mode": "video", "frames": 16, "fps": 8,
         "prompt": "the lighthouse lantern at the top glows and its warm light beam sweeps slowly around, "
                   "the tower itself stays perfectly still"},
    ],
    "chalutier_quai": [
        {"quoi": "drapeau (warp flag, zone du drapeau)", "mode": "warp", "kind": "flag", "anchor": "right",
         "amplitude_px": 6, "waves": 2, "area": [70, 110, 180, 185], "frames": 12, "fps": 10},
        {"quoi": "drapeau (vidéo)", "mode": "video", "frames": 16, "fps": 8,
         "prompt": "the small green flag at the top of the mast flutters in the wind, the boat and its hull stay "
                   "perfectly still"},
    ],
    "fontaine_place": [
        {"quoi": "jet d'eau et rides (vidéo)", "mode": "video", "frames": 16, "fps": 8,
         "prompt": "a thin stream of water pours from the small spout of the fountain and falls into the basin, "
                   "gentle ripples spread on the turquoise water, the stone stays still"},
        {"quoi": "gouttes du bec (particles drops)", "mode": "particles", "kind": "drops", "count": 10,
         "size_px": 5, "area": [300, 120, 340, 300], "frames": 12, "fps": 10},
    ],
    "lavoir_bassin": [
        {"quoi": "bulles de savon (particles bubbles)", "mode": "particles", "kind": "bubbles", "count": 12,
         "size_px": 7, "frames": 12, "fps": 10},
        {"quoi": "rides et bulles (vidéo)", "mode": "video", "frames": 16, "fps": 8,
         "prompt": "soap bubbles rise slowly from the water of the wash basin and pop, gentle ripples on the water, "
                   "the stone basin stays still"},
    ],
    "piege_generique": [
        {"quoi": "bulles qui éclatent (particles bubbles)", "mode": "particles", "kind": "bubbles", "count": 6,
         "size_px": 8, "frames": 12, "fps": 10},
        {"quoi": "bulles (vidéo)", "mode": "video", "frames": 16, "fps": 8,
         "prompt": "bubbles slowly swell on the sticky golden goo puddle and pop, the puddle stays in place"},
    ],
}


def lire(p, d):
    return json.load(open(p)) if os.path.exists(p) else d


def ecrire(p, v):
    tmp = p + ".tmp"
    json.dump(v, open(tmp, "w"), ensure_ascii=False, indent=1)
    os.replace(tmp, p)


def elements():
    return {e["id"]: e for e in json.load(open(ed.PROMPTS))["elements"]}


def index():
    return lire(INDEX, {"elements": {}})["elements"]


def a_une_image(eid):
    return bool(index().get(eid, {}).get("fichiers"))


# ------------------------------------------------------------------ payloads

def payload_image(eid, sorte):
    """pf_2d__prop (objet, décor au sol, sortie, façade) ou pf_2d__ground (sols, bords, toit)."""
    el = elements()[eid]
    if eid in GROUND_NUIT:
        g = GROUND_NUIT[eid]
        pl = {"prompt_style": "pf_2d__ground", "prompt": g["prompt"], "width": 1024, "height": 1024,
              "num_images": 2, "seed": SEED_NUIT}
        pl.update({k: v for k, v in g.items() if k != "prompt"})
        return pl
    src = dict(el["payloads"][0])
    src.pop("taille_cases", None)
    if src["prompt_style"] == "pf_hd__texture":         # façade : traitée comme un objet de décor
        src["prompt_style"] = "pf_hd__prop"
    pl = ed.en_2d(src)
    # La description seule : pixelforge pose la caméra (verrou de caméra) et le trait des persos.
    pl["prompt"] = PROMPTS_NUIT.get(eid) or pl["prompt"].split(" Camera:")[0]
    pl.update(num_images=2, seed=SEED_NUIT)
    pl.pop("priority", None)
    return pl


def source_fermee(eid):
    """Image fermée retenue (avant recadrage) d'après l'index du décor : <out>/decor/<id>/<job>/<variante>.png."""
    s = (index().get(eid, {}).get("sources") or [{}])[0]
    if s.get("fichier"):
        return s["fichier"]
    return os.path.join(OUT_DECOR, eid, str(s.get("job", 0)), str(s.get("variante", "image_00")) + ".png")


def payload_ouvert(eid):
    el = elements()[eid]
    edit = (el.get("edits") or [{}])[0]
    p = source_fermee(eid)
    if not os.path.exists(p):
        raise RuntimeError(f"image fermée introuvable : {p}")
    im = Image.open(p).convert("RGBA")
    fond = Image.new("RGBA", im.size, "white")
    fond.alpha_composite(im)
    w, h = (min(1024, max(128, v)) for v in im.size)
    prompt = edit.get("prompt") or "same object, same style, but its lid or door slightly open, a dark gap inside"
    return {"prompt_style": "pf_hd__edit", "input_image": nuit.ex.b64(fond.convert("RGB")),
            "prompt": prompt + ", same camera, same size, same colors, same thick dark navy outline",
            "width": w, "height": h, "num_images": 2, "seed": SEED_NUIT}


def image_jeu(eid):
    el = index()[eid]
    return Image.open(os.path.join(DECOR, el["fichiers"][0]))


def payloads_anim(eid):
    pls = []
    # Pistes écrites ici, sinon celles de prompts_decor.json (animation.pistes : éléments ajoutés avec la
    # carte v3, tools/gordeka/make_port_v3.py).
    for a in ANIMS.get(eid) or elements()[eid].get("animation", {}).get("pistes", []):
        pl = {k: v for k, v in a.items() if k not in ("quoi", "source")}
        if a.get("source") == "hd":                    # vidéo : la source HD (1024 px), Wan voit mieux
            s = (index()[eid].get("sources") or [{}])[0]
            im = Image.open(os.path.join(OUT_DECOR, eid, str(s.get("job", 0)), s.get("variante", "image_00") + ".png"))
        else:                                          # l'image intégrée : la boucle s'aligne sur le jeu
            im = image_jeu(eid)
        pl.update(prompt_style="pf_2d__loop", input_image=nuit.ex.b64(im))
        pls.append((a["quoi"], pl))
    return pls


def payload_masque(eid):
    pl = mp.payload(eid, index()[eid])
    pl.pop("priority", None)
    return pl


def payloads(sorte, eid):
    """[(quoi, payload)] d'une carte ; priorité et tag ajoutés au dépôt."""
    if sorte in ("image", "refaire", "toit"):
        pl = payload_image(eid, sorte)
        return [(f"{pl['prompt_style']} ×{pl['num_images']}", pl)]
    if sorte == "ouvert":
        return [("pf_hd__edit ×2 (ouverte)", payload_ouvert(eid))]
    if sorte == "anim":
        return payloads_anim(eid)
    if sorte == "masque":
        return [("pf_2d__footprint", payload_masque(eid))]
    raise ValueError(sorte)


# ------------------------------------------------------------------ dépôt

def file_night():
    q = json.loads(urllib.request.urlopen(urllib.request.Request(pf.PF + "/v2/queue", headers=pf.AUTH),
                                          timeout=60).read())
    return q.get("night", {}).get("pending", 0)


def deposer(pl, essais=20):
    """Dépôt d'un job ; 502/503/file pleine/réseau : on réessaie (60 s), le reste remonte."""
    for i in range(essais):
        try:
            return pf._post_json(pf.PF + "/v2/inferences", pl, timeout=300)["task_id"]
        except RuntimeError as e:
            m = str(e)
            if not any(k in m for k in ("HTTP 503", "HTTP 502", "HTTP 504", "provider_busy", "queue_full")):
                raise
            print("  pixelforge occupé, nouvel essai dans 60 s :", m[:120], flush=True)
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            print("  réseau, nouvel essai dans 60 s :", str(e)[:120], flush=True)
        time.sleep(60)
    raise RuntimeError("pixelforge indisponible")


def depose_entree(cle, ent, priorite):
    """Dépose les jobs d'une entrée du suivi (carte ou masque sans carte) ; renvoie le nombre de jobs."""
    ent["jobs"], refus = [], []
    for quoi, pl in payloads(ent["sorte"], ent["element"]):
        pl.update(priority=priorite, tag=f"{TAG}_{ent['element']}")
        try:
            ent["jobs"].append({"tid": deposer(pl), "quoi": quoi, "style": pl["prompt_style"]})
        except RuntimeError as e:                    # paramètre refusé (422…) : on garde les autres pistes
            print(f"  refusé ({quoi}) :", str(e)[:300], flush=True)
            refus.append({"quoi": quoi, "erreur": str(e)[:300]})
    if refus:
        ent["refus"] = refus
    if not ent["jobs"]:
        raise RuntimeError("aucun job accepté : " + refus[0]["erreur"][:200])
    ent.update(statut="en_file", priorite=priorite, depose=time.strftime("%Y-%m-%d %H:%M"))
    return len(ent["jobs"])


def commente(carte, texte):
    if carte and str(carte).isdigit():
        cli.call("card_comment", {"id": int(carte), "body": texte})


def prise(carte, ent):
    quand = "en priorité de nuit (calcul entre 1 h et 8 h)" if ent["priorite"] == "night" else "tout de suite"
    jobs = ", ".join(j["quoi"] for j in ent["jobs"])
    cli.call("card_move", {"id": int(carte), "status": "doing"})
    commente(carte, f"Pris : déposé chez pixelforge {quand} — {jobs}. Au matin : planche de recette "
                    "(decor_matin.py), Julien choisit la variante, puis intégration et commit local.")


# ------------------------------------------------------------------ cartes

def classe(c, noms):
    """(sorte, élément) d'une carte, ou (None, raison)."""
    t = c["title"]
    if t.startswith("Décor · toit en tuiles"):
        return "toit", "toit_tuiles"
    if t.startswith("Décor · dalles du quai"):
        return "question", "sol_dalles_quai"
    if " : " not in t:
        return None, "titre non reconnu"
    nom, quoi = t.rsplit(" : ", 1)
    if quoi not in SORTES or nom not in noms:
        return None, "titre non reconnu"
    return SORTES[quoi], noms[nom]


def descendants(cartes, racine):
    par = {c["id"]: c for c in cartes}
    out = set()
    for c in cartes:
        p, vus = c, set()
        while p and p.get("parent_id") and p["id"] not in vus:
            vus.add(p["id"])
            if p["parent_id"] == racine:
                out.add(c["id"])
                break
            p = par.get(p["parent_id"])
    return out


def plan(todo, noms):
    """Décide, carte par carte : déposer, attendre une image, ou commenter seulement."""
    sortes = {}
    for c in todo:
        s, eid = classe(c, noms)
        if s:
            sortes[c["id"]] = (s, eid)
    refaites = {eid: cid for cid, (s, eid) in sortes.items() if s == "refaire"}
    images = {eid: cid for cid, (s, eid) in sortes.items() if s == "image"}
    els = elements()
    decisions = []
    for c in todo:
        cid = c["id"]
        if cid not in sortes:
            decisions.append((c, "ignore", None, None))
            continue
        s, eid = sortes[cid]
        if s == "question":
            decisions.append((c, "question", eid, None))
        elif s == "masque" and os.path.exists(os.path.join(DECOR, "masques", eid, "ground_y.png")) \
                and "footprint_override" in json.dumps(lire(os.path.join(DECOR, "masques", eid, "masks.json"), {})):
            decisions.append((c, "deja_fait", eid, None))
        elif s in ("masque", "anim", "ouvert") and eid in refaites:
            decisions.append((c, "attend", eid, refaites[eid]))
        elif s in ("anim", "ouvert", "masque") and not a_une_image(eid):
            decisions.append((c, "attend", eid, images.get(eid)))
        elif s == "anim" and eid not in ANIMS:
            decisions.append((c, "ignore", eid, None))
        elif s == "masque" and els[eid]["type"] != "objet":
            decisions.append((c, "ignore", eid, None))
        else:
            decisions.append((c, "depose", eid, None))
    return sortes, decisions


def main():
    essai = "--essai" in sys.argv
    cartes = cli.call("cards")["cards"]
    famille = descendants(cartes, CHAPEAU)
    todo = [c for c in cartes if c["status"] == "todo" and c["id"] in famille and not c.get("children")]
    noms = {e["nom"]: eid for eid, e in elements().items()}
    suivi = lire(SUIVI, {})
    sortes, decisions = plan(todo, noms)
    n_dep = sum(1 for d in decisions if d[1] == "depose" and str(d[0]["id"]) not in suivi)
    if not essai and n_dep:
        libre = NIGHT_MAX - file_night()
        if libre < 3 * n_dep:
            sys.exit(f"file night presque pleine ({libre} places) : rien déposé")
    compte = {}
    for c, action, eid, dep in decisions:
        cle = str(c["id"])
        prio = "night" if c.get("night") else "normal"
        if cle in suivi:
            continue                                  # déjà traitée (idempotent)
        s = sortes.get(c["id"], (None, None))[0]
        ent = {"titre": c["title"], "sorte": s, "element": eid, "priorite": prio}
        if action == "ignore":
            print(f"#{cle} {c['title']} : non reconnue, laissée en Todo")
            continue
        if action == "question":
            ent["statut"] = "question"
            texte = ("Question pour Julien : passer la tuile des dalles du quai à 4×4 cases (motif moins chargé, "
                     "à générer en 2048 px puis réduire) ou garder 2×2 ? Rien n'est déposé tant que tu n'as pas "
                     "tranché ; réponds ici et je lance.")
        elif action == "deja_fait":
            ent["statut"] = "deja_fait"
            texte = ("Déjà en v3 avec l'emprise tracée à la main (footprint_override, commit 00be280, en local) : "
                     "rien redéposé, une relance sans l'emprise manuelle la perdrait. À passer en QA après le "
                     "prochain déploiement.")
        elif action == "attend":
            ent.update(statut="attend", depend=str(dep) if dep else None)
            texte = (f"En attente : dépend de l'image de « {elements()[eid]['nom']} »"
                     + (f" (carte #{dep}, déposée cette nuit)" if dep else "")
                     + ". Déposé au matin par decor_matin.py dès que Julien a choisi la variante et qu'elle est "
                       "intégrée (sinon le résultat porterait sur une image obsolète).")
        else:
            if essai:
                print(f"#{cle} {c['title']} → {s} {eid} ({prio}) : {[q for q, _ in payloads(s, eid)]}")
                compte[s] = compte.get(s, 0) + len(payloads(s, eid))
                continue
            try:
                n = depose_entree(cle, ent, prio)
            except RuntimeError as e:
                print(f"#{cle} {c['title']} : ÉCHEC du dépôt, laissée en Todo :", str(e)[:200], flush=True)
                continue
            compte[s] = compte.get(s, 0) + n
            suivi[cle] = ent
            ecrire(SUIVI, suivi)
            prise(cle, ent)
            print(f"#{cle} {c['title']} → {n} job(s) {prio}", flush=True)
            continue
        print(f"#{cle} {c['title']} : {ent['statut']}" + (f" (← #{ent.get('depend')})" if ent.get("depend") else ""))
        if not essai:
            suivi[cle] = ent
            ecrire(SUIVI, suivi)
            commente(cle, texte)
    print("jobs par sorte :", compte, "total", sum(compte.values()))


if __name__ == "__main__":
    main()
