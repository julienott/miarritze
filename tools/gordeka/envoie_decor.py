#!/usr/bin/env python3
"""Dépose le décor de la carte chez pixelforge (priorité low) et relève les résultats au fil de l'eau.

  envoie_decor.py depose [<id> …]     dépose les payloads de prompts_decor.json (tous par défaut)
  envoie_decor.py suivant             attend le prochain job fini, le rapatrie, rend la main
  envoie_decor.py annule <id> …       annule les jobs encore en attente de ces éléments

Suivi : tools/gordeka/taches_decor.json ({id: [task_id, …]}), sorties dans tools/rd/out/decor/<id>/<n>/.
Les `edits` (états ouverts, images suivantes de l'eau) attendent qu'une image soit validée.
"""
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import gen_anims_pf as pf  # noqa: E402

PROMPTS = os.path.join(HERE, "prompts_decor.json")
SUIVI = os.path.join(HERE, "taches_decor.json")
OUT = os.path.join(ROOT, "tools", "rd", "out", "decor")
FINI = ("succeeded", "failed", "canceled", "expired")
# Les ancres d'abord : le sol le plus étendu, un objet, une cachette (premiers retours à juger).
ANCRES = ["sol_dalles_quai", "caisses_poisson", "cachette_coffre_quai"]


# Décor au trait des persos (pixelforge, 2026-10-20) : pf_2d__prop (Qwen + référence de style = le
# modèle de Louis) et pf_2d__ground (sol mis au trait par code). Les façades (pf_hd__texture) attendent.
STYLE_2D = True
STYLE_TASK = "affc36bd90aa4e25ba350ee139b2fdc5"   # pf_2d__character de Louis (variante 3 retenue)
PRIORITE = os.environ.get("PF_PRIORITE", "low")


def en_2d(pl):
    if pl["prompt_style"] == "pf_hd__prop":
        q = {k: v for k, v in pl.items() if k != "height"}
        q.update(prompt_style="pf_2d__prop",
                 width=max(pl.get("width", 512), pl.get("height", 512)))
        return q
    if pl["prompt_style"] == "pf_hd__ground":
        q = {k: v for k, v in pl.items() if k != "theme"}
        q["prompt_style"] = "pf_2d__ground"
        q["prompt"] = q["prompt"].split(" Camera:")[0]   # la matière seule : le trait est fait par code
        return q
    return None


def charger(chemin, defaut):
    return json.load(open(chemin)) if os.path.exists(chemin) else defaut


def tache(tid):
    return json.loads(urllib.request.urlopen(f"{pf.PF}/v2/inferences/tasks/{tid}", timeout=60).read())


def depose(ids):
    els = {e["id"]: e for e in json.load(open(PROMPTS))["elements"]}
    ordre = [i for i in ANCRES if i in els] + [i for i in els if i not in ANCRES]
    suivi = charger(SUIVI, {})
    for eid in ordre:
        if ids and eid not in ids or eid in suivi:
            continue
        suivi[eid] = []
        for pl in els[eid].get("payloads", []):
            pl = {k: v for k, v in pl.items() if k not in ("taille_cases",)}
            if STYLE_2D:
                pl = en_2d(pl)
                if pl is None:
                    continue
            pl["priority"] = PRIORITE
            if eid in ANCRES:
                pl["num_images"] = 3           # ancres : 3 variantes à faire valider
            pl["tag"] = f"miarritze/decor_{eid}"
            while True:
                try:
                    suivi[eid].append(pf._post_json(pf.PF + "/v2/inferences", pl, timeout=300)["task_id"])
                    break
                except RuntimeError as e:  # file pleine (50 tâches max) : on attend qu'elle se vide
                    if "provider_busy" not in str(e):
                        raise
                    time.sleep(60)
        json.dump(suivi, open(SUIVI, "w"), indent=1)
        print("déposé", eid, suivi[eid], flush=True)


def suivant():
    suivi = charger(SUIVI, {})
    vus = charger(os.path.join(OUT, "_vus.json"), [])
    while True:
        reste = 0
        for eid, tids in suivi.items():
            for n, tid in enumerate(tids):
                if tid in vus:
                    continue
                try:
                    r = tache(tid)
                except Exception as e:  # redémarrage de pixelforge
                    print("relève impossible :", e, flush=True)
                    time.sleep(30)
                    continue
                if r["status"] not in FINI:
                    reste += 1
                    continue
                d = os.path.join(OUT, eid, str(n))
                os.makedirs(d, exist_ok=True)
                for f in r.get("result", {}).get("pixelforge", {}).get("files", []):
                    open(os.path.join(d, f["name"]), "wb").write(
                        urllib.request.urlopen(f["url"], timeout=120).read())
                vus.append(tid)
                json.dump(vus, open(os.path.join(OUT, "_vus.json"), "w"))
                print(eid, n, r["status"], str(r.get("error", ""))[:300], d, flush=True)
                return
        if not reste:
            print("FINI : plus rien en attente", flush=True)
            return
        time.sleep(15)


def annule(ids):
    suivi = charger(SUIVI, {})
    for eid in ids:
        for tid in suivi.get(eid, []):
            if tache(tid)["status"] in ("pending", "queued"):
                req = urllib.request.Request(f"{pf.PF}/v2/inferences/tasks/{tid}", method="DELETE", headers=pf.AUTH)
                urllib.request.urlopen(req, timeout=60)
                print("annulé", eid, tid, flush=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    cmd, args = sys.argv[1], sys.argv[2:]
    {"depose": depose, "suivant": lambda a: suivant(), "annule": annule}[cmd](args)
