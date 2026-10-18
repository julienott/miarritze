#!/usr/bin/env python3
"""File pixelforge pour la refonte des persos (from_mannequin.py) : toutes les
animations de plusieurs persos sont déposées d'avance dans la file asynchrone
du serveur (POST /v2/inferences, 50 places), relevées au fil de l'eau
(GET /v2/inferences/tasks/{id}) et enregistrées ; plus de temps mort entre deux
appels ni de session à surveiller.

  file_pf.py <id> [<id> …] [--refaire] [--max 40] [--anims a,b,c]
État reprenable par perso : tools/rd/out/<id>/file_pf.json ({anim: tâche}) ; journal
tools/rd/out/file_pf.log. Plusieurs files (persos différents) peuvent tourner ensemble.
Tâches marquées tag « miarritze/<id> » : annuler le lot d'un perso (modèle refusé) =
DELETE /v2/inferences/tasks?tag=miarritze/<id> ; le passer devant = PATCH … {"priority": "high"}.
Une tâche en échec est redéposée une fois (graine +1000) ; une animation déjà
« OK » n'est pas redéposée sans --refaire. Pause pour un déploiement pixelforge :
--pause arrête de déposer (les tâches déjà en file sont relevées).
"""
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import from_mannequin as fm  # noqa: E402
import pieces  # noqa: E402

PF = fm.pf.PF
POLL = 20


def get(url):
    return json.loads(urllib.request.urlopen(url, timeout=60).read().decode())


def submit(payload):
    r = fm.pf._post_json(PF + "/v2/inferences", payload, timeout=300)
    return r["task_id"]


def save(state, fids):
    for f in fids:
        sub = {k.split("/", 1)[1]: v for k, v in state.items() if k.split("/", 1)[0] == f}
        json.dump(sub, open(os.path.join(fm.out_dir(f), "file_pf.json"), "w"), indent=1)


def log(msg):
    line = time.strftime("%H:%M:%S ") + msg
    print(line, flush=True)
    with open(os.path.join(ROOT, "tools", "rd", "out", "file_pf.log"), "a") as fh:
        fh.write(line + "\n")


def main():
    only = set(sys.argv[sys.argv.index("--anims") + 1].split(",")) if "--anims" in sys.argv else None
    skip = {sys.argv[sys.argv.index(k) + 1] for k in ("--anims", "--max") if k in sys.argv}
    fids = [a for a in sys.argv[1:] if not a.startswith("--") and not a.isdigit() and a not in skip]
    limit = int(sys.argv[sys.argv.index("--max") + 1]) if "--max" in sys.argv else 40
    state = {}
    for f in fids:
        sp = os.path.join(fm.out_dir(f), "file_pf.json")
        if os.path.exists(sp):
            state.update({f"{f}/{k}": v for k, v in json.load(open(sp)).items()})
    jobs = {f: fm.Perso(f) for f in fids}
    todo = []
    for f in fids:
        done, verdicts = jobs[f].state()
        for name in fm.animate.ANIM_ORDER:
            if only is not None and name not in only:
                continue
            key = f"{f}/{name}"
            if key in state and state[key]["status"] in ("pending", "running") and only is None:
                continue                        # déjà en file (reprise) ; --anims : on redépose
            if verdicts.get(name) == "OK" and name in done and "--refaire" not in sys.argv:
                continue
            todo.append((f, name, 0))
    log(f"{len(todo)} animations à déposer ({', '.join(fids)}), {sum(1 for v in state.values() if v['status'] in ('pending', 'running'))} déjà en file")
    controls_cache = {}
    while todo or any(v["status"] in ("pending", "running") for v in state.values()):
        # 1. déposer tant qu'il y a de la place
        try:
            q = get(PF + "/v2/queue")
            waiting = len(q.get("pending", [])) + len(q.get("running", []))
        except Exception as e:
            log(f"serveur injoignable ({e}), on attend")
            time.sleep(60)
            continue
        while todo and waiting < limit and "--pause" not in sys.argv:
            f, name, shift = todo.pop(0)
            job = jobs[f]
            job.shift = shift
            payload, seed, controls = job.prepare(name)
            payload["priority"] = "low"         # lot de fond : les requêtes courtes passent devant
            payload["tag"] = f"miarritze/{f}"   # annulable / reprioritisable d'un coup (DELETE|PATCH ?tag=)
            try:
                tid = submit(payload)
            except Exception as e:
                log(f"{f}/{name}: dépôt refusé ({e})")
                continue
            state[f"{f}/{name}"] = {"task_id": tid, "seed": seed, "shift": shift, "status": "pending",
                                    "t": time.time()}
            controls_cache[f"{f}/{name}"] = controls
            waiting += 1
            save(state, fids)
        # 2. relever
        for key, t in list(state.items()):
            if t["status"] not in ("pending", "running"):
                continue
            try:
                r = get(f"{PF}/v2/inferences/tasks/{t['task_id']}")
            except Exception:
                continue
            st = r.get("status")
            f, name = key.split("/")
            if st in ("succeeded", "failed", "canceled", "cancelled", "expired"):
                job = jobs[f]
                controls = controls_cache.get(key)
                if controls is None:            # reprise : contrôles recalculés (déterministes)
                    job.shift = t["shift"]
                    controls = job.prepare(name)[2]
                fr, gqa = [], {}
                if st == "succeeded":
                    fr, gqa = pieces.guided_parse(r["result"], controls[0].size, len(controls))
                errs = job.store(name, t["seed"], controls, fr, gqa, time.time() - t["t"])
                t["status"] = st
                t["errs"] = errs
                log(f"{key}: {st} {'OK' if not errs else ' ; '.join(errs)}")
                if st == "failed" and t["shift"] == 0:     # annulée exprès (DELETE) : pas redéposée
                    todo.append((f, name, 1000))
            else:
                t["status"] = "running" if st == "running" else "pending"
        save(state, fids)
        time.sleep(POLL)
    for f in fids:
        jobs[f].report()
    log("FIN")


if __name__ == "__main__":
    main()
