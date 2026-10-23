#!/usr/bin/env python3
"""Retouche d'éléments d'un set pixelforge déjà livré, sans refaire le reste (GDD §14.1, mode `redo`).

  retouche.py --montre persos/louis run portrait [--clip run=Sprint_Loop] [--action idle_long="…"] [--seed 12]
  retouche.py --depose persos/louis run portrait [...] [--prio normal|high|night|low]
  retouche.py --integre        fusionne dans les sets les retouches terminées (lancé par livraison.sh)

Rien ne part sans la décision de Julien (il refuse la carte en QA ; GDD §14.1). La tâche d'origine (A et
sa réduction B) est cherchée dans tools/blackout/taches_*.json. Les retouches sont notées dans
taches_retouches.json ; à l'intégration, seuls les fichiers des éléments refaits sont remplacés (hd/ et px32/),
animations.json est fusionné, set.json est gardé.
"""
import glob
import json
import os
import re
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import gen_anims_pf as pf  # noqa: E402

SORTIE = os.path.join(HERE, "taches_retouches.json")
FIXES = {"profile", "idle", "ghost"}          # ne se refont pas seuls : tout le set repart


def tache(tid: str) -> dict:
    req = urllib.request.Request(f"{pf.PF}/v2/inferences/tasks/{tid}", headers=pf.AUTH)
    return json.loads(urllib.request.urlopen(req, timeout=60).read())


def origine(famille: str, pid: str) -> tuple[str, str]:
    """Tâches A et B intégrées pour ce set (la marque .tache dit laquelle)."""
    marque = os.path.join(ROOT, "assets", "blackout", famille, pid, ".tache")
    a = open(marque).read().strip() if os.path.exists(marque) else None
    for f in sorted(glob.glob(os.path.join(HERE, "taches_*.json"))):
        if f == SORTIE:
            continue
        t = json.load(open(f)).get(pid)
        if isinstance(t, dict) and t.get("A") and (a is None or t["A"] == a):
            return t["A"], t["chaine"][0]["task_id"]
    sys.exit(f"tâche d'origine introuvable pour {famille}/{pid}")


def options(args: list[str], cle: str) -> dict:
    return dict(args[i + 1].split("=", 1) for i, x in enumerate(args) if x == cle)


def requete(args: list[str]) -> tuple[dict, dict]:
    vals = {args[i + 1] for i, x in enumerate(args) if x.startswith("--") and x != "--montre" and x != "--depose"}
    pos = [x for x in args if not x.startswith("--") and x not in vals]
    famille, pid = pos[0].split("/")
    elements = pos[1:]
    if not elements or FIXES & set(elements):
        sys.exit(f"éléments à refaire requis ; {', '.join(sorted(FIXES))} ne se refont pas seuls (tout le set repart)")
    a, b = origine(famille, pid)
    prio = args[args.index("--prio") + 1] if "--prio" in args else "normal"
    r = {"prompt_style": "pf_px__character_set", "base_task": a, "redo": elements, "priority": prio,
         "tag": f"miarritze/retouche/{famille}", "then": [{"prompt_style": "pf_px__reduce", "factor": 4,
                                                           "colors": 10, "base_task": b}]}
    if "--seed" in args:
        r["seed"] = int(args[args.index("--seed") + 1])
    for cle, champ in (("--clip", "clips"), ("--action", "actions")):
        if options(args, cle):
            r[champ] = options(args, cle)
    if "--run-frames" in args:
        r["run_frames"] = int(args[args.index("--run-frames") + 1])
    return r, {"famille": famille, "pid": pid, "elements": elements}


def fusionne(r: dict, dossier: str, elements: list[str]) -> int:
    """Remplace les seuls fichiers des éléments refaits ; fusionne animations.json."""
    p = r["result"]["pixelforge"]
    os.makedirs(dossier, exist_ok=True)
    n = 0
    for f in p.get("files", []):
        if not any(re.fullmatch(re.escape(e) + r"(_\d+|_sheet)?\.(png|gif)", f["name"]) for e in elements):
            continue
        u = urllib.parse.urlparse(f["url"])   # pixelforge renvoie parfois 127.0.0.1 : on garde le chemin
        req = urllib.request.Request(pf.PF + u.path + (f"?{u.query}" if u.query else ""), headers=pf.AUTH)
        open(os.path.join(dossier, f["name"]), "wb").write(urllib.request.urlopen(req, timeout=120).read())
        n += 1
    chemin = os.path.join(dossier, "animations.json")
    anims = json.load(open(chemin)) if os.path.exists(chemin) else {}
    for k, a in (p.get("animations") or {}).items():
        anims[k] = {x: y for x, y in a.items() if x != "frames"}
    json.dump(anims, open(chemin, "w"), ensure_ascii=False, indent=1)
    return n


def integre() -> None:
    lot = json.load(open(SORTIE)) if os.path.exists(SORTIE) else []
    for r in lot:
        if r.get("integre"):
            continue
        a, b = tache(r["A"]), tache(r["B"])
        if a["status"] != "succeeded" or b["status"] != "succeeded":
            if "failed" in (a["status"], b["status"]) or "cancelled" in (a["status"], b["status"]):
                print(f"retouche {r['famille']}/{r['pid']} : échec ({str(a.get('error') or b.get('error'))[:120]})")
                r["integre"] = "echec"
            continue
        base = os.path.join(ROOT, "assets", "blackout", r["famille"], r["pid"])
        n = fusionne(a, os.path.join(base, "hd"), r["elements"]) + fusionne(b, os.path.join(base, "px32"), r["elements"])
        r["integre"] = True
        print(f"retouche {r['famille']}/{r['pid']} intégrée : {', '.join(r['elements'])} ({n} fichiers)")
    json.dump(lot, open(SORTIE, "w"), ensure_ascii=False, indent=1)


def main() -> None:
    args = sys.argv[1:]
    if "--integre" in args:
        integre()
        return
    req, info = requete(args)
    if "--depose" not in args:
        print(json.dumps(req, ensure_ascii=False, indent=1))
        return
    rep = pf._post_json(pf.PF + "/v2/inferences", req, timeout=120)
    lot = json.load(open(SORTIE)) if os.path.exists(SORTIE) else []
    lot.append({**info, "A": rep["task_id"], "B": (rep.get("then") or rep.get("chain"))[0]["task_id"],
                "requete": req, "integre": False})
    json.dump(lot, open(SORTIE, "w"), ensure_ascii=False, indent=1)
    print(info["pid"], rep["task_id"])


if __name__ == "__main__":
    main()
