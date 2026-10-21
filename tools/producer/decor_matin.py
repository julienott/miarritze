#!/usr/bin/env python3
"""Le matin, après la nuit de pixelforge : relève les jobs déposés par todo_decor.py, rapatrie, fait une
planche de recette par carte et liste ce qui attend la recette de JULIEN. Rien n'est intégré sans lui.

  decor_matin.py releve                  rapatrie les jobs finis, planches (tools/rd/out/decor_nuit/<carte>/)
  decor_matin.py liste [--tout]          ce qui est prêt pour la recette (planche, variantes), échecs, attentes
  decor_matin.py integre <carte> [<variante>] [--sans-capture] [--nuit]
        image / refaire : <variante> = image_00 | image_01        (integre_decor.py, commit local)
        version ouverte : <variante> = image_00 | image_01        (integre_decor.py --etat ouvert)
        animation       : <variante> = numéro de la piste : 0, 1… (planche + json dans assets/gordeka/decor/anims/)
        masque          : sans variante                           (masques dans assets/gordeka/decor/masques/<id>/)
      puis dépose ce qui attendait cette image (masque v3, version ouverte, animation ; masque d'office pour
      un nouvel objet sans carte de masque), en priorité « normal » (« night » avec --nuit), et passe ces
      cartes en Doing. La carte intégrée est notée « prête pour la QA » (commentaire sur le kanban) : elle
      passera en QA après le déploiement, que fait Julien.
  decor_matin.py relance <carte> ["consigne"]   redépose (priorité normal), consigne ajoutée au prompt

<carte> = numéro de la carte kanban (ou « m-<id> » pour un masque déposé d'office).
Suivi : tools/gordeka/taches_decor_nuit.json. Commits locaux à chemins explicites, jamais de push.
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import todo_decor as td  # noqa: E402   (payloads, dépôt, suivi, kanban)
from todo_decor import ROOT, GK, DECOR, INDEX, OUT_DECOR, lire, ecrire  # noqa: E402

import nuit  # noqa: E402
import masques_pf as mp  # noqa: E402
import planche_recette as pr  # noqa: E402

from PIL import Image, ImageDraw  # noqa: E402

STAGE = os.path.join(ROOT, "tools", "rd", "out", "decor_nuit")
PY = os.path.join(ROOT, ".venv", "bin", "python")
SUIVI_DECOR = os.path.join(GK, "taches_decor.json")
ANIMS = os.path.join(DECOR, "anims")


def suivi():
    return lire(td.SUIVI, {})


def telecharge(r, d):
    os.makedirs(d, exist_ok=True)
    for f in r["result"]["pixelforge"]["files"]:
        open(os.path.join(d, f["name"]), "wb").write(urllib.request.urlopen(f["url"], timeout=120).read())


# ------------------------------------------------------------------ relève

def planche_loop(d, out, titre):
    """6 images de la boucle côte à côte sur gris (+ le GIF à ouvrir à côté)."""
    frames = sorted(f for f in os.listdir(d) if f.startswith("frame_") and f.endswith(".png"))
    if not frames:
        return None
    pick = [frames[round(i * (len(frames) - 1) / 5)] for i in range(6)] if len(frames) >= 6 else frames
    vues = []
    for f in pick:
        im = Image.open(os.path.join(d, f)).convert("RGBA")
        im.thumbnail((300, 300))
        fond = Image.new("RGBA", (310, 330), (150, 160, 150, 255))
        fond.alpha_composite(im, ((310 - im.width) // 2, (310 - im.height) // 2))
        ImageDraw.Draw(fond).text((6, 314), f, fill="black")
        vues.append(fond)
    pl = Image.new("RGB", (316 * len(vues), 350), "white")
    ImageDraw.Draw(pl).text((6, 334), titre[:120], fill="black")
    for i, v in enumerate(vues):
        pl.paste(v.convert("RGB"), (i * 316, 0))
    pl.save(out)
    return out


def releve_masque(cle, ent, job, d):
    """Masque : rapatrié par masques_pf (marge retirée, coordonnées recalées) mais dans la zone de recette."""
    eid = ent["element"]
    tmp = os.path.join(d, "_suivi.json")
    json.dump({eid: {"tid": job["tid"], "statut": "en_vol"}}, open(tmp, "w"))
    mp.SUIVI, mp.DECOR, mp.APERCUS = tmp, d, os.path.join(d, "apercu")
    mp.releve(une_fois=True)
    ap = os.path.join(d, "apercu", eid + ".png")
    return ap if os.path.exists(ap) else None


def releve():
    s = suivi()
    for cle, ent in s.items():
        if ent.get("statut") != "en_file":
            continue
        etats = [nuit.tache(j["tid"]) for j in ent["jobs"]]
        if any(r["status"] not in nuit.FINI for r in etats):
            continue
        ent["planches"] = []
        for k, (j, r) in enumerate(zip(ent["jobs"], etats)):
            j["statut"] = r["status"]
            if r["status"] != "succeeded":
                j["erreur"] = str(r.get("error", ""))[:300]
                continue
            d = os.path.join(STAGE, f"{cle}_{ent['element']}", str(k))
            if ent["sorte"] == "masque":
                os.makedirs(d, exist_ok=True)
                p = releve_masque(cle, ent, j, d)
            else:
                telecharge(r, d)
                p = os.path.join(d, "planche.png")
                if ent["sorte"] == "anim":
                    p = planche_loop(d, p, f"#{cle} piste {k} : {j['quoi']}")
                else:
                    pr.decor(d, p)
            j["dossier"] = d
            if p and os.path.exists(p):
                j["planche"] = p
                ent["planches"].append(p)
        ent["statut"] = "a_voir" if any(j.get("statut") == "succeeded" for j in ent["jobs"]) else "echec"
        ecrire(td.SUIVI, s)
        print(ent["statut"].upper(), f"#{cle}", ent["titre"], *ent["planches"], flush=True)
    restants = sum(1 for e in s.values() if e.get("statut") == "en_file")
    print(f"en file encore : {restants}")


def liste(tout=False):
    s = suivi()
    groupes = {}
    for cle, ent in s.items():
        groupes.setdefault(ent.get("statut"), []).append((cle, ent))
    for statut, titre in (("a_voir", "PRÊT POUR TA RECETTE"), ("echec", "ÉCHECS (relance <carte>)"),
                          ("en_file", "ENCORE EN FILE"), ("attend", "EN ATTENTE D'UNE IMAGE"),
                          ("integre", "INTÉGRÉ (prêt pour la QA après déploiement)")):
        if statut not in groupes or (not tout and statut in ("integre",)):
            continue
        print(f"\n== {titre} ({len(groupes[statut])})")
        for cle, ent in sorted(groupes[statut], key=lambda x: (x[1]["sorte"] or "", x[0])):
            print(f"#{cle:>4} [{ent['sorte']}] {ent['titre']}")
            if statut == "a_voir":
                for k, j in enumerate(ent["jobs"]):
                    if j.get("planche"):
                        print(f"        piste {k} ({j['quoi']}) : {j['planche']}")
                    elif j.get("erreur"):
                        print(f"        piste {k} ({j['quoi']}) : échec {j['erreur'][:100]}")
                print(f"        → decor_matin.py integre {cle} " + {
                    "anim": "<piste>", "masque": ""}.get(ent["sorte"], "<image_00|image_01>"))
            elif statut == "attend":
                print(f"        attend la carte #{ent.get('depend')}")
            elif statut == "echec":
                print("        ", "; ".join(j.get("erreur", "")[:100] for j in ent["jobs"]))


# ------------------------------------------------------------------ intégration

def commit(chemins, message):
    chemins = [os.path.relpath(c, ROOT) if os.path.isabs(c) else c for c in chemins]
    nuit.commit(chemins + ["tools/gordeka/taches_decor_nuit.json"], message)


def godot_import():
    subprocess.run(["godot", "--headless", "--path", ROOT, "--import"], capture_output=True, timeout=600)


def run(*args):
    p = subprocess.run([PY, *args], cwd=ROOT, capture_output=True, text=True)
    print(p.stdout[-1500:], p.stderr[-800:])
    if p.returncode:
        sys.exit("échec : " + " ".join(args[:3]))
    return p.stdout


def job_libre(eid):
    """Numéro de job neuf dans tools/rd/out/decor/<id>/ (et taches_decor.json, lu par integre_decor.py)."""
    d = os.path.join(OUT_DECOR, eid)
    pris = [int(x) for x in os.listdir(d) if x.isdigit()] if os.path.isdir(d) else []
    return max(pris + [len(lire(SUIVI_DECOR, {}).get(eid, [])) - 1]) + 1


def integre_image(cle, ent, variante, sans_capture):
    eid, j = ent["element"], ent["jobs"][0]
    el = td.elements()[eid]
    n = job_libre(eid)
    dest = os.path.join(OUT_DECOR, eid, str(n))
    shutil.copytree(j["dossier"], dest, dirs_exist_ok=True)
    sd = lire(SUIVI_DECOR, {})
    sd.setdefault(eid, [])
    while len(sd[eid]) <= n:
        sd[eid].append(None)
    sd[eid][n] = j["tid"]
    ecrire(SUIVI_DECOR, sd)
    if el["type"] in ("tuile_bord", "bande_facade"):
        ent["retenu"] = {"job": n, "variante": variante, "dossier": dest}
        print(f"{eid} : type {el['type']} pas encore affiché par le jeu (gk_decor.gd) : image retenue "
              f"({dest}/{variante}.png), intégration au jeu à faire")
        commit(["tools/gordeka/taches_decor.json"], f"Gordeka : décor {eid}, image retenue {variante} (recette Julien)")
        return []
    args = [os.path.join(GK, "integre_decor.py"), eid, str(n), variante]
    if sans_capture:
        args.append("--sans-capture")
    run(*args)
    if el["type"] == "tuile_sol":
        fichiers = [os.path.join(DECOR, f) for f in td.index()[eid]["fichiers"]]
    else:
        fichiers = [os.path.join(DECOR, "objets", f"{eid}.png"), os.path.join(DECOR, "objets", f"{eid}_ombre.png")]
    commit(fichiers + [INDEX, "tools/gordeka/taches_decor.json"],
           f"Gordeka : décor {eid} {'refait de face' if ent['sorte'] == 'refaire' else 'nouvelle image'} "
           f"(pf_2d, {variante}, recette Julien)")
    return [os.path.join(DECOR, "objets", f"{eid}.png")]


def integre_ouvert(cle, ent, variante, sans_capture):
    eid, j = ent["element"], ent["jobs"][0]
    args = [os.path.join(GK, "integre_decor.py"), eid, "--etat", "ouvert",
            "--fichier", os.path.join(j["dossier"], variante + ".png")]
    if sans_capture:
        args.append("--sans-capture")
    run(*args)
    commit([os.path.join(DECOR, "objets", f"{eid}_ouvert.png"), INDEX],
           f"Gordeka : décor {eid}, état ouvert (pf_hd__edit, {variante}, recette Julien)")


def integre_anim(cle, ent, piste):
    eid, j = ent["element"], ent["jobs"][int(piste)]
    os.makedirs(ANIMS, exist_ok=True)
    png, js = os.path.join(ANIMS, f"{eid}.png"), os.path.join(ANIMS, f"{eid}.json")
    shutil.copy(os.path.join(j["dossier"], "spritesheet_00.png"), png)
    meta = lire(os.path.join(j["dossier"], "animation_00.json"), {})
    meta.update(source_task=j["tid"], piste=j["quoi"])
    json.dump(meta, open(js, "w"), ensure_ascii=False, indent=1)
    # L'animation est notée dans prompts_decor.json (integre_decor.py recopie `animation` de là dans l'index)
    # et dans l'index. Le jeu (gk_decor.gd) ne lit pas encore les planches : c'est une tâche à part.
    pd = json.load(open(td.ed.PROMPTS))
    for e in pd["elements"]:
        if e["id"] == eid:
            e.setdefault("animation", {}).update(planche=f"anims/{eid}.png", planche_json=f"anims/{eid}.json")
            anim = e["animation"]
    json.dump(pd, open(td.ed.PROMPTS, "w"), ensure_ascii=False, indent=1)
    ix = json.load(open(INDEX))
    ix["elements"].setdefault(eid, {})["animation"] = anim
    json.dump(ix, open(INDEX, "w"), ensure_ascii=False, indent=1)
    godot_import()
    commit([png, js, INDEX, td.ed.PROMPTS], f"Gordeka : décor {eid}, animation en boucle ({j['quoi']}, recette Julien)")


def integre_masque(cle, ent):
    eid, j = ent["element"], ent["jobs"][0]
    src = os.path.join(j["dossier"], "masques", eid)
    dst = os.path.join(DECOR, "masques", eid)
    os.makedirs(dst, exist_ok=True)
    fichiers = []
    for f in os.listdir(src):
        shutil.copy(os.path.join(src, f), os.path.join(dst, f))
        fichiers.append(os.path.join(dst, f))
    ap = os.path.join(j["dossier"], "apercu", eid + ".png")
    if os.path.exists(ap):
        shutil.copy(ap, os.path.join(mp.APERCUS_JEU, eid + ".png"))
        fichiers.append(os.path.join(mp.APERCUS_JEU, eid + ".png"))
    godot_import()
    commit(fichiers, f"Gordeka : masques v3 de {eid} (pf_2d__footprint, recette Julien)")


def depose_suites(cle, ent, prio):
    """Ce qui attendait l'image de cette carte : déposé maintenant, cartes passées en Doing."""
    s = suivi()
    eid = ent["element"]
    a_deposer = [(k, e) for k, e in s.items() if e.get("statut") == "attend" and e.get("element") == eid]
    est_objet = td.elements()[eid]["type"] == "objet"
    if est_objet and not any(e.get("sorte") == "masque" and e.get("element") == eid for e in s.values()
                             if e.get("statut") in ("attend", "en_file", "a_voir")):
        k = f"m-{eid}"
        s[k] = {"titre": f"{td.elements()[eid]['nom']} : masque (d'office, nouvelle image)", "sorte": "masque",
                "element": eid, "priorite": prio}
        a_deposer.append((k, s[k]))
    for k, e in a_deposer:
        n = td.depose_entree(k, e, prio)
        e.pop("depend", None)
        ecrire(td.SUIVI, s)
        if k.isdigit():
            td.prise(k, e)
        print(f"déposé #{k} {e['titre']} : {n} job(s) {prio}")


def integre(cle, variante, sans_capture, prio, plus_tard=False):
    s = suivi()
    ent = s.get(cle)
    if not ent or ent.get("statut") not in ("a_voir", "integre"):
        sys.exit(f"#{cle} n'est pas prête pour l'intégration ({(ent or {}).get('statut')})")
    sorte = ent["sorte"]
    if sorte in ("image", "refaire", "toit"):
        integre_image(cle, ent, variante or "image_00", sans_capture)
    elif sorte == "ouvert":
        integre_ouvert(cle, ent, variante or "image_00", sans_capture)
    elif sorte == "anim":
        integre_anim(cle, ent, variante or "0")
    elif sorte == "masque":
        integre_masque(cle, ent)
    ent.update(statut="integre", variante=variante)
    s[cle] = ent
    ecrire(td.SUIVI, s)
    if cle.isdigit():
        td.commente(cle, f"Intégré en local ({variante or 'masques'}, commit local, sans push) : prêt à passer "
                         "en QA après le prochain déploiement.")
    print(f"#{cle} intégré : prêt pour la QA après déploiement")
    if sorte in ("image", "refaire"):
        if td.a_une_image(ent["element"]) and plus_tard:
            # File pixelforge pleine : les suites (masque, animation) partiront avec « suites » (veille).
            s = suivi()
            s[cle]["suites_a_deposer"] = prio
            ecrire(td.SUIVI, s)
            print("suites différées : décor_matin.py suites les déposera quand la file aura de la place")
        elif td.a_une_image(ent["element"]):
            depose_suites(cle, ent, prio)
        else:
            print("suites non déposées : l'élément n'a pas d'image dans le jeu (type pas encore géré)")


def suites():
    """Dépose les suites différées (--suites-plus-tard), une entrée à la fois, sans attendre : arrêt dès que
    pixelforge est plein (on reprendra au passage suivant de la veille)."""
    for cle, ent in list(suivi().items()):
        prio = ent.get("suites_a_deposer")
        if not prio:
            continue
        essais = td.deposer.__defaults__
        td.deposer.__defaults__ = (1,)
        try:
            depose_suites(cle, ent, prio)
        except (RuntimeError, SystemExit) as e:
            print("suites : pixelforge plein, reprise plus tard", str(e)[:100])
            return
        finally:
            td.deposer.__defaults__ = essais
        s = suivi()
        s[cle].pop("suites_a_deposer", None)
        ecrire(td.SUIVI, s)


def relance(cle, consigne):
    s = suivi()
    ent = s[cle]
    if consigne:
        ent["consigne"] = consigne
    orig = td.payloads

    def avec_consigne(sorte, eid):
        pls = orig(sorte, eid)
        for _, pl in pls:
            if consigne and "prompt" in pl:
                pl["prompt"] = pl["prompt"].rstrip() + " " + consigne
            if "seed" in pl:
                pl["seed"] += 100
        return pls
    td.payloads = avec_consigne
    n = td.depose_entree(cle, ent, "normal")
    ecrire(td.SUIVI, s)
    td.commente(cle, f"Relancé ({n} job(s), priorité normale)" + (f" avec la consigne : {consigne}" if consigne else ""))
    print(f"#{cle} relancé : {n} job(s)")


if __name__ == "__main__":
    mp.APERCUS_JEU = mp.APERCUS                      # aperçus lus par /producer (tools/gordeka/masques/)
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "releve":
        releve()
    elif a[0] == "liste":
        liste("--tout" in a)
    elif a[0] == "integre":
        pos = [x for x in a[1:] if not x.startswith("--")]
        integre(pos[0], pos[1] if len(pos) > 1 else None, "--sans-capture" in a, "night" if "--nuit" in a else "normal",
                "--suites-plus-tard" in a)
    elif a[0] == "suites":
        suites()
    elif a[0] == "relance":
        relance(a[1], a[2] if len(a) > 2 else None)
    else:
        sys.exit(__doc__)
