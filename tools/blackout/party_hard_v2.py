#!/usr/bin/env python3
"""Rejeu de la bibliothèque de prompts persos v2 (GDD-BLACKOUT.md §8.2, copie machine
data/blackout/style_party_hard.json) : une chaîne moteur A (pf_px__character_set) → moteur B
(pf_px__reduce) par perso, déposée dans la FILE de pixelforge.

  party_hard_v2.py --montre [louis …]            affiche les requêtes, n'envoie rien
  party_hard_v2.py --apercu [louis …]            dépose l'aperçu (profil et portrait HD seuls, gardé : keep)
  party_hard_v2.py --depose [louis …] [--prio high|normal|night]

Flux de pixelforge (23/10) : d'abord l'aperçu de chaque perso, jugé par Julien ; --depose anime ensuite ce
profil sans le redessiner (profile_of), sans refaire le portrait. Sans aperçu : set complet comme avant.
Aperçus dans tools/blackout/taches_apercus.json.

Sans liste de persos : les 13. Écrit les ids des tâches dans tools/blackout/taches_partyhard_v2.json.
Ne rien déposer sans l'accord de Julien (GDD §14).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))

SPEC = json.load(open(os.path.join(ROOT, "data", "blackout", "style_party_hard.json"), encoding="utf-8"))
SORTIE = os.path.join(HERE, "taches_persos_v3.json")
APERCUS = os.path.join(HERE, "taches_apercus.json")
TAG = "miarritze/persos_v3"
GRAINE = 7
ELEMENTS = ["profile", "idle", "run", "jump_hide", "lift", "portrait", "interagir", "victoire", "defaite", "etourdi",
            "renverse", "colle", "ralenti", "aveugle", "tracte"]


def prompt(pid: str) -> str:
    p = SPEC["persos"][pid]
    # Détail clé « clearly visible » déjà dans la description (règles de pixelforge, GDD §8.2), sinon ajouté.
    if "clearly visible" in p["description"]:
        return p["description"] + "."
    return f"{p['description']}, with {p['signature']} clearly visible."


def casts(pid: str) -> list:
    """Lancements des deux coups spéciaux (GDD §4.6), extras cast_chasse et cast_chasseur."""
    c = SPEC.get("casts", {}).get(pid, {})
    return [{"name": n, "motion": c[n]["clip"], "action": c[n]["action"], "object": c[n]["objet"] or False,
             "loop": False, "fps": 12} for n in ("cast_chasse", "cast_chasseur") if n in c]


def reduction() -> dict:
    """Moteur B (pixelforge, API du 23/10) : A ne fait plus que le HD ; B le réduit à la taille finale
    (« pixel brut »). Ses traitements ne s'appliquent que demandés : PF_STEPS='{"couleurs": true, …}'."""
    steps = json.loads(os.environ.get("PF_STEPS", "{}"))
    return {"prompt_style": "pf_px__reduce", **({"steps": steps} if steps else {})}


def apercus() -> dict:
    return json.load(open(APERCUS)) if os.path.exists(APERCUS) else {}


def requete_apercu(pid: str, prio: str) -> dict:
    return {"prompt_style": "pf_px__character_set", "prompt": prompt(pid), "seed": GRAINE, "priority": prio,
            "tag": TAG + "/apercu", "preview": True}


def requete(pid: str, prio: str) -> dict:
    il = SPEC["idle_long"][pid]
    ap = apercus().get(pid)
    r = {
        "prompt_style": "pf_px__character_set", "prompt": prompt(pid), "seed": GRAINE,
        "priority": prio, "tag": TAG,
        # Éléments voulus (liste blanche, pixelforge df70eab) ; pas de ghost : fantôme commun (pf_px__ghost, GDD §8.1).
        "elements": ELEMENTS,
        "extras": [{"name": "idle_long", "motion": il["clip"], "action": il["geste"], "loop": True, "fps": 10,
                    "object": il.get("objet") or False}] + casts(pid),
        # B lit la ligne des pieds dans le set.json de A (60 en 32 px, case 64) : pas de feet_y.
        "then": [reduction()],
    }
    if ap:      # profil de l'aperçu repris tel quel, portrait déjà fait (intégré depuis l'aperçu)
        r["profile_of"] = ap
        r["elements"] = [e for e in ELEMENTS if e != "portrait"]
    return r


def main() -> None:
    args = sys.argv[1:]
    prio = args[args.index("--prio") + 1] if "--prio" in args else "high"
    pids = [a for a in args if not a.startswith("--") and a != prio] or \
        [k for k in SPEC["persos"] if not k.startswith("_")]
    if "--apercu" in args:
        import gen_anims_pf as pf  # noqa: E402
        import urllib.request
        aps = apercus()
        for pid in pids:
            rep = pf._post_json(pf.PF + "/v2/inferences", requete_apercu(pid, prio), timeout=120)
            aps[pid] = rep["task_id"]
            req = urllib.request.Request(f"{pf.PF}/v2/inferences/tasks/{rep['task_id']}", data=b'{"keep": true}',
                                         method="PATCH", headers={**pf.AUTH, "Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=60)
            print(pid, "aperçu", rep["task_id"], flush=True)
        json.dump(aps, open(APERCUS, "w"), ensure_ascii=False, indent=1)
        return
    reqs = {pid: requete(pid, prio) for pid in pids}
    if "--depose" not in args:
        print(json.dumps(reqs, ensure_ascii=False, indent=1))
        return
    import gen_anims_pf as pf  # noqa: E402
    taches = json.load(open(SORTIE)) if os.path.exists(SORTIE) else {}
    for pid, r in reqs.items():
        rep = pf._post_json(pf.PF + "/v2/inferences", r, timeout=120)
        taches[pid] = {"A": rep["task_id"], "chaine": rep.get("then") or rep.get("chain"), "prompt": r["prompt"],
                       "idle_long": r["extras"][0], **({"apercu": r["profile_of"]} if "profile_of" in r else {})}
        print(pid, rep["task_id"], flush=True)
    json.dump(taches, open(SORTIE, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
