#!/usr/bin/env python3
"""Persos façon Party Hard, prompts assemblés UNIQUEMENT depuis data/gordeka/style_party_hard.json
(docs/STYLE_PARTY_HARD.md, docs/style/) : profil (pf_pro__character) puis course (pf_anim__walking).

  party_hard.py <dossier de sortie> louis maia peio kaio [--anim run]

Écrit pour chaque perso : <id>_profil_<n>.png, puis les fichiers de l'animation (spritesheet, gif…) de la
première variante du profil, et prompts.json (les prompts exacts envoyés, pour juger la spec).
"""
import base64
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
import gen_anims_pf as pf  # noqa: E402

SPEC = json.load(open(os.path.join(ROOT, "data", "gordeka", "style_party_hard.json")))
STYLE = SPEC["style_commun"]


def prompt_profil(pid):
    p, g = SPEC["persos"][pid], SPEC["gabarits"]["perso"]
    corps = SPEC["gabarits"]["gabarits_corps"][p["corps"]]
    t = g["prompt"].format(gabarit_corps=corps, description=p["description"], signature=p["signature"])
    return f"{t} {STYLE['base']} {STYLE['par_type']['perso']}"


def prompt_anim(pid, anim):
    a, p = SPEC["animations"][anim], SPEC["persos"][pid]
    t = SPEC["gabarits"]["anim"]["prompt"].format(description=p["description"], action=a["action"], expression=a["expression"])
    return f"{t} {STYLE['base']} {STYLE['par_type']['anim']}"


def get(t):
    return json.loads(urllib.request.urlopen(urllib.request.Request(f"{pf.PF}/v2/inferences/tasks/{t}", headers=pf.AUTH),
                                             timeout=60).read())


def attend(t):
    while True:
        r = get(t)
        if r["status"] in ("succeeded", "failed", "canceled", "expired"):
            return r
        time.sleep(15)


def images(r):
    res = r.get("result") or {}
    out = [(f["name"], urllib.request.urlopen(f["url"], timeout=120).read()) for f in (res.get("pixelforge") or {}).get("files", [])]
    out += [(f"image_{i:02d}.png", base64.b64decode(b)) for i, b in enumerate(res.get("base64_images") or [])]
    return out


def deposer(pl):
    for _ in range(60):
        try:
            return pf._post_json(pf.PF + "/v2/inferences", pl, timeout=300)["task_id"]
        except RuntimeError as e:
            if "provider_busy" not in str(e):
                raise
            time.sleep(30)
    raise RuntimeError("pixelforge indisponible")


def main():
    out = sys.argv[1]
    anim = sys.argv[sys.argv.index("--anim") + 1] if "--anim" in sys.argv else "run"
    pids = [a for a in sys.argv[2:] if not a.startswith("--") and a != anim]
    os.makedirs(out, exist_ok=True)
    g, a = SPEC["gabarits"]["perso"], SPEC["animations"][anim]
    journal, profils = {}, {}
    for pid in pids:
        pr = prompt_profil(pid)
        profils[pid] = deposer({"prompt_style": g["prompt_style"], "prompt": pr, "width": g["width"], "height": g["height"],
                                "colors": g["colors"], "num_images": g["num_images"], "seed": g["seed"],
                                "priority": "high", "tag": "miarritze/partyhard"})
        journal[pid] = {"profil": pr, "profil_task": profils[pid]}
        print("profil", pid, profils[pid], flush=True)
    json.dump(journal, open(os.path.join(out, "prompts.json"), "w"), ensure_ascii=False, indent=1)
    for pid, t in profils.items():
        r = attend(t)
        print(pid, "profil", r["status"], str(r.get("error", ""))[:200], flush=True)
        if r["status"] != "succeeded":
            continue
        pngs = [b for n, b in images(r) if n.endswith(".png")]
        for i, b in enumerate(pngs):
            open(os.path.join(out, f"{pid}_profil_{i}.png"), "wb").write(b)
        pa = prompt_anim(pid, anim)
        ta = deposer({"prompt_style": a["style"], "prompt": pa, "input_image": base64.b64encode(pngs[0]).decode(),
                      "width": a["width"], "height": a["height"], "colors": a["colors"], "priority": "high",
                      "tag": "miarritze/partyhard"})
        journal[pid].update(anim=pa, anim_task=ta)
        json.dump(journal, open(os.path.join(out, "prompts.json"), "w"), ensure_ascii=False, indent=1)
        r = attend(ta)
        print(pid, anim, r["status"], str(r.get("error", ""))[:200], flush=True)
        if r["status"] == "succeeded":
            for n, b in images(r):
                open(os.path.join(out, f"{pid}_{anim}_{n}"), "wb").write(b)
    print("FINI", flush=True)


if __name__ == "__main__":
    main()
