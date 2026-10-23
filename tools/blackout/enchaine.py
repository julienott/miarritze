#!/usr/bin/env python3
"""Enchaîne les itérations pixelforge (iteration.py, GDD §8.5) sans surveillance : pour chaque perso, la base
neutre, puis dès qu'elle est prête les bases avec expression utiles (expressions des animations et des
portraits), puis chaque animation dès que la base de son expression est prête. Relit iterations.json à
chaque tour ; un seul enchaînement à la fois. Les erreurs passagères du serveur (502…) sont réessayées.
Ne contrôle aucun rendu (Julien s'en charge) et ne met en file que ce que Julien a demandé.

  enchaine.py louis txomin … [--prio normal] [--prio-de louis=high] [--un-par-un]
--un-par-un : un perso ne reçoit ses expressions qu'une fois toutes les animations du précédent déposées,
pour finir les persos l'un après l'autre (bases neutres déposées tout de suite).
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import iteration as it  # noqa: E402

FIN = ("failed", "cancelled", "introuvable")
PAUSE_S = 30


def utiles(b, pid: str) -> list:
    """Éléments à animer et expressions nécessaires (sans neutre), dans l'ordre des éléments."""
    els = it.STANDARDS + list(b.extras(pid))
    ks = []
    for x in els:
        k = b.expression(pid, x)
        if k != it.NEUTRE and k not in ks:
            ks.append(k)
    for v in b.ex["portraits"].values():
        k = b.base(pid) if v == "base" else v
        if k != it.NEUTRE and k not in ks:
            ks.append(k)
    return els, ks


def tour(b, pids: list, prio_de: dict, signale: set, un_par_un: bool = False) -> bool:
    e = it.etat()
    fini = True
    precedent_depose = True
    for pid in pids:
        prio = prio_de.get(pid, prio_de["*"])
        s = e.get(it.cle(b, pid), {})
        if not s.get("base"):
            it.job_base(b, e, pid, prio, False)
            it.sauve(e)
            fini = False
            continue
        st = it.get(s["base"])["status"]
        if st != "succeeded":
            if st in FIN and pid not in signale:
                print(pid, ": base neutre", st, flush=True)
                signale.add(pid)
            fini = fini and st in FIN
            precedent_depose = False
            continue
        els, ks = utiles(b, pid)
        if un_par_un and not precedent_depose:
            fini = False
            continue
        for k in ks:
            if k not in s.get("expressions", {}):
                it.job_expression(b, e, pid, k, prio, False)
                it.sauve(e)
        anims = s.setdefault("animations", {})
        for x in els:
            if x in anims or (pid, x) in signale:
                continue
            k = b.expression(pid, x)
            tid = s["base"] if k == it.NEUTRE else s["expressions"].get(k)
            st = it.get(tid)["status"] if tid else "absente"
            if st == "succeeded":
                it.job_anim(b, e, pid, x, prio, False)
                it.sauve(e)
            elif st in FIN:
                print(pid, x, ": base", k, st, flush=True)
                signale.add((pid, x))
            else:
                fini = False
        precedent_depose = all(x in anims or (pid, x) in signale for x in els)
    return fini


def main() -> None:
    args = sys.argv[1:]
    prio_de = {"*": "normal"}
    pids = []
    i = 0
    while i < len(args):
        if args[i] == "--prio":
            prio_de["*"] = args[i + 1]
            i += 1
        elif args[i] == "--prio-de":
            k, v = args[i + 1].split("=")
            prio_de[k] = v
            i += 1
        elif args[i] == "--un-par-un":
            prio_de["un_par_un"] = True
        else:
            pids.append(args[i])
        i += 1
    b = it.Persos()
    signale: set = set()
    un = bool(prio_de.pop("un_par_un", False))
    while True:
        try:
            if tour(b, pids, prio_de, signale, un):
                break
        except Exception as x:          # serveur qui redémarre : on réessaie au tour suivant
            print("pixelforge indisponible :", str(x)[:80], flush=True)
        time.sleep(PAUSE_S)
    print("tout est déposé", flush=True)


if __name__ == "__main__":
    main()
