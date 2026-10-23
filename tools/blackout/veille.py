#!/usr/bin/env python3
"""Veille de nuit de la recette pixelforge (Julien, 23/10), sans surveillance ni appel au modèle :
  - à chaque tour, dépose ce qui est prêt (enchaine.tour : base, expressions, animations, persos un par un) ;
  - quand la file de pixelforge est vide :
      1. intègre en local ce qui est fini (iteration.integre, dans assets/blackout/persos/) SANS commit ni push :
         rien ne part dans le jeu en ligne ;
      2. remet en file un élément manquant (expression ou animation échouée ou annulée) d'un perso en cours,
      3. sinon ajoute le perso suivant de ORDRE, avec tout son set.
S'arrête quand les 13 persos sont déposés, finis et intégrés. Journal : tools/blackout/veille.log.

  veille.py [--prio normal] [--prio-de louis=high]
"""
import json
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import enchaine as en  # noqa: E402
import iteration as it  # noqa: E402

ORDRE = ["louis", "txomin", "maia", "patxi", "xabi", "mattin", "amaia", "kaio", "karramarro", "ramuntxo",
         "itsaso", "peio", "itsasargi"]
LOG = os.path.join(HERE, "veille.log")
PAUSE_S = 60
ESSAIS_MAX = 2          # un élément qui échoue deux fois n'est plus redéposé (signalé dans le journal)


def log(*m) -> None:
    with open(LOG, "a") as f:
        f.write(time.strftime("%d/%m %H:%M ") + " ".join(str(x) for x in m) + "\n")


def file_vide() -> bool:
    q = json.loads(urllib.request.urlopen(urllib.request.Request(it.pf.PF + "/v2/queue", headers=it.pf.AUTH),
                                          timeout=60).read())
    return not q.get("running") and not q.get("pending") and not q.get("draining")


def manquant(b, e: dict, actifs: list) -> bool:
    """Retire de l'état une expression ou une animation échouée/annulée : le tour suivant la redépose."""
    for pid in actifs:
        s = e.get(it.cle(b, pid), {})
        ech = s.setdefault("echouees", {})
        essais = lambda p: sum(1 for c in ech if c.startswith(p))  # noqa: E731
        if s.get("base") and it.get(s["base"])["status"] in en.FIN and essais("base_") < ESSAIS_MAX:
            ech[f"base_{s['base'][:8]}"] = s.pop("base")
            log(pid, "base neutre à refaire")
            return True
        for k, t in list(s.get("expressions", {}).items()):
            if it.get(t)["status"] in en.FIN and essais(f"expression_{k}_") < ESSAIS_MAX:
                ech[f"expression_{k}_{t[:8]}"] = t
                del s["expressions"][k]
                log(pid, "expression", k, "à refaire")
                return True
        for n, a in list(s.get("animations", {}).items()):
            if any(it.get(t)["status"] in en.FIN for t in (a["A"], a.get("B")) if t) \
                    and essais(f"anim_{n}_") < ESSAIS_MAX:
                ech[f"anim_{n}_{a['A'][:8]}"] = a
                del s["animations"][n]
                log(pid, "animation", n, "à refaire")
                return True
    return False


def tout_integre(b, e: dict, pid: str) -> bool:
    s = e.get(it.cle(b, pid), {})
    els, _ = en.utiles(b, pid)
    return all(s.get("integre", {}).get(x) == s.get("animations", {}).get(x, {}).get("A") for x in els)


def main() -> None:
    args = sys.argv[1:]
    prio_de = {"*": "normal"}
    for i, a in enumerate(args):
        if a == "--prio":
            prio_de["*"] = args[i + 1]
        if a == "--prio-de":
            k, v = args[i + 1].split("=")
            prio_de[k] = v
    b = it.Persos()
    signale: set = set()
    log("veille démarrée")
    while True:
        try:
            e = it.etat()
            actifs = [p for p in ORDRE if it.cle(b, p) in e]
            en.tour(b, actifs, prio_de, signale, True)
            if file_vide():
                e = it.etat()
                for pid in actifs:
                    it.integre(b, e, pid)
                it.sauve(e)
                log("intégré en local :", ", ".join(actifs))
                if manquant(b, e, actifs):
                    it.sauve(e)
                    signale.clear()
                else:
                    suivant = [p for p in ORDRE if p not in actifs]
                    if suivant:
                        it.job_base(b, e, suivant[0], prio_de.get(suivant[0], prio_de["*"]), False)
                        it.sauve(e)
                        log("nouveau perso :", suivant[0])
                    elif all(tout_integre(b, e, p) for p in actifs):
                        log("les 13 persos sont finis et intégrés en local")
                        break
        except Exception as x:              # serveur qui redémarre : on réessaie au tour suivant
            log("pixelforge indisponible :", str(x)[:80])
        time.sleep(PAUSE_S)


if __name__ == "__main__":
    main()
