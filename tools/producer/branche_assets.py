#!/usr/bin/env python3
"""Versionne tous les assets sur la branche « assets-integres » (Julien, 24/10 ; GDD §14.2).

main ne reçoit que ce que Julien a validé (le watcher le committe à l'acceptation, puis la prod se
déploie). La branche « assets-integres » reçoit tout le reste : chaque intégration locale, 32 px et HD (la HD en
Git LFS, .gitattributes). Elle part de main (HEAD) et ajoute assets/ tel qu'il est sur le disque, sans
toucher à la copie de travail ni à l'index de main (index temporaire dans .studio/).

  branche_assets.py [--sans-push]
Imprime le commit créé, ou « rien de neuf ».
"""
import os
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
INDEX = os.path.join(ROOT, ".studio", "assets.index")
BRANCHE = "assets-integres"


def git(*args, env=None, check=True) -> str:
    p = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, env=env)
    if check and p.returncode != 0:
        sys.exit(f"git {' '.join(args[:3])} : {p.stderr.strip()[-400:]}")
    return p.stdout.strip()


def main() -> None:
    env = {**os.environ, "GIT_INDEX_FILE": INDEX}
    os.makedirs(os.path.dirname(INDEX), exist_ok=True)
    git("read-tree", "HEAD", env=env)
    git("add", "--all", "--", "assets", env=env)     # filtre LFS appliqué à la HD
    arbre = git("write-tree", env=env)
    avant = git("rev-parse", "--verify", "-q", f"refs/heads/{BRANCHE}", check=False)
    if avant and git("rev-parse", f"{avant}^{{tree}}") == arbre:
        print("rien de neuf")
        return
    parents = ["-p", avant] if avant else []
    tete = git("rev-parse", "HEAD")
    if not avant or tete not in git("rev-list", "--parents", "-n", "1", avant).split():
        parents += ["-p", tete]                        # rattache la branche au main du moment
    msg = "Assets intégrés en local (non validés compris), 32 px et HD\n\nPar tools/producer/branche_assets.py."
    commit = git("commit-tree", arbre, *parents, "-m", msg)
    git("update-ref", f"refs/heads/{BRANCHE}", commit)
    print(commit[:10])
    if "--sans-push" not in sys.argv:
        p = subprocess.run(["git", "push", "-q", "origin", f"{BRANCHE}:{BRANCHE}"], cwd=ROOT,
                           capture_output=True, text=True, timeout=3600)
        if p.returncode != 0:
            sys.exit("push : " + p.stderr.strip()[-400:])
        print("poussé sur origin/" + BRANCHE)


if __name__ == "__main__":
    main()
