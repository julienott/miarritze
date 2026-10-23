#!/usr/bin/env python3
"""Intègre tels quels les rendus du run persos v2 (tools/blackout/taches_partyhard_v2.json) :
moteur A → assets/blackout/persos/<id>/hd/, moteur B → assets/blackout/persos/<id>/px32/ (remplace l'ancien
contenu). Pas de recette : Julien tranche en QA (GDD §14). Un perso dont la chaîne n'a pas réussi garde ses
anciens fichiers et est signalé.

  integre_persos_v2.py            tous les persos
  integre_persos_v2.py louis …    seulement ceux-là
  TACHES_PERSOS=taches_pnj.json DEST=pnj integre_persos_v2.py      les PNJ (assets/blackout/pnj/)
  TACHES_PERSOS=taches_fantome.json DEST=fantome integre_persos_v2.py   le fantôme commun
  TACHES_PERSOS=taches_boss_essai.json DEST=boss integre_persos_v2.py   les boss (assets/blackout/boss/)
Un placeholder (set.json → "placeholder": true, tools/blackout/placeholders_sets.py) est remplacé en entier,
comme tout ancien contenu de px32/.
"""
import json
import os
import shutil
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import gen_anims_pf as pf  # noqa: E402

TACHES = os.path.join(HERE, os.environ.get("TACHES_PERSOS", "taches_persos_v3.json"))
# Dossier d'arrivée sous assets/blackout/ : persos (défaut), pnj, fantome…
DEST = os.environ.get("DEST", "persos")


def tache(tid: str) -> dict:
    req = urllib.request.Request(f"{pf.PF}/v2/inferences/tasks/{tid}", headers=pf.AUTH)
    try:
        return json.loads(urllib.request.urlopen(req, timeout=60).read())
    except urllib.error.HTTPError as e:
        if e.code == 404:                      # tâche annulée puis purgée chez pixelforge
            return {"status": "introuvable"}
        raise


def rapatrie(r: dict, dossier: str) -> int:
    p = r["result"]["pixelforge"]
    tmp = dossier + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    for f in p.get("files", []):
        u = urllib.parse.urlparse(f["url"])   # pixelforge renvoie parfois 127.0.0.1 : on garde le chemin
        req = urllib.request.Request(pf.PF + u.path + (f"?{u.query}" if u.query else ""), headers=pf.AUTH)
        open(os.path.join(tmp, f["name"]), "wb").write(urllib.request.urlopen(req, timeout=120).read())
    anims = {k: {x: y for x, y in a.items() if x != "frames"} for k, a in (p.get("animations") or {}).items()}
    json.dump(anims, open(os.path.join(tmp, "animations.json"), "w"), ensure_ascii=False, indent=1)
    shutil.rmtree(dossier, ignore_errors=True)
    os.rename(tmp, dossier)
    return len(p.get("files", []))


def complete(r: dict, dossier: str) -> int:
    """Ajoute à `dossier` les fichiers d'une autre tâche (aperçu) qu'il n'a pas déjà."""
    n = 0
    for f in (r.get("result") or {}).get("pixelforge", {}).get("files", []):
        cible = os.path.join(dossier, f["name"])
        if os.path.exists(cible):
            continue
        u = urllib.parse.urlparse(f["url"])
        req = urllib.request.Request(pf.PF + u.path + (f"?{u.query}" if u.query else ""), headers=pf.AUTH)
        open(cible, "wb").write(urllib.request.urlopen(req, timeout=120).read())
        n += 1
    return n


def main() -> None:
    taches = json.load(open(TACHES))
    pids = sys.argv[1:] or list(taches)
    bilan = {}
    for pid in pids:
        t = taches[pid]
        base = os.path.join(ROOT, "assets", "blackout", DEST, pid)
        marque = os.path.join(base, ".tache")          # tâche A déjà intégrée : rien à refaire
        if os.path.exists(marque) and open(marque).read().strip() == t["A"]:
            continue
        a = tache(t["A"])
        b = tache(t["chaine"][0]["task_id"])
        if a["status"] in ("pending", "running"):
            bilan[pid] = f"en cours chez pixelforge ({a['status']})"
            continue
        if a["status"] != "succeeded" or b["status"] != "succeeded":
            bilan[pid] = f"pas intégré : A {a['status']}, B {b['status']} {str(b.get('error') or a.get('error') or '')[:120]}"
            continue
        n = rapatrie(a, os.path.join(base, "hd")) + rapatrie(b, os.path.join(base, "px32"))
        if t.get("apercu"):                    # profil et portrait HD venus de l'aperçu (profile_of)
            n += complete(tache(t["apercu"]), os.path.join(base, "hd"))
        open(marque, "w").write(t["A"] + "\n")
        # Tâche gardée chez pixelforge (keep, avec sa réduction) : retouches et ajouts d'extras restent possibles.
        req = urllib.request.Request(f"{pf.PF}/v2/inferences/tasks/{t['A']}", data=b'{"keep": true}', method="PATCH",
                                     headers={**pf.AUTH, "Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=60)
        bilan[pid] = f"intégré ({n} fichiers, éléments : {', '.join(sorted(b['result']['pixelforge'].get('animations', {})))})"
    for pid, txt in bilan.items():
        print(pid, ":", txt)


if __name__ == "__main__":
    main()
