#!/usr/bin/env python3
"""Studio : le watcher du board local (Julien, 24/10 ; GDD §14.2, procédure docs/PRODUCER.md).
Tourne seul, sans appel au modèle (aucun token), un tour par minute :

  1. Todo → file pixelforge : un chapeau de perso ou de PNJ mis en Todo y emmène ses cartes du Backlog ;
     chaque carte en Todo (base, expression, animation) est déposée dès que ce dont elle dépend est prêt
     (base neutre → base avec expression → animation, tools/blackout/iteration.py), puis passe en Doing.
     Les persos se finissent l'un après l'autre, dans l'ordre de la colonne.
  2. Doing : suit les tâches pixelforge (statuts écrits sur la carte, champ jobs) ; une tâche échouée ou
     annulée est redéposée (2 essais au plus, puis commentaire sur la carte) ; une tâche finie est intégrée
     en local (assets/blackout/<famille>/<id>/, sans commit).
  3. Build de QA : après une intégration, tests, export web dans .studio/site/jeu (le jeu de QA servi sur
     Tailscale) et index du board ; les cartes intégrées passent alors en QA.
  4. keep : toute tâche d'une carte en Doing, QA, Validé ou En prod est gardée chez pixelforge.
  5. Chapeaux : leur colonne suit celle de leurs enfants.
  6. Validé → En prod : 10 min après le dernier accept, tests, commit et push des seuls fichiers validés,
     déploiement (deploy.yml), puis les cartes passent En prod.

Une carte refusée (↺ à retraiter) en Backlog attend ; remise en Todo (« Refuser et refaire », ou à la main),
elle attend Claude (.studio/a_traiter.json, relevé toutes les 30 min), qui écrit la demande ajustée selon le
commentaire ; le watcher la contrôle et la redépose depuis le profil validé (Studio.refait) ; dès qu'une nouvelle tâche est
intégrée pour elle, elle revient en QA d'elle-même. Les cartes de code (feature, bug, gameplay) ne sont jamais traitées ici.

  studio.py            (boucle ; lancé par launchd, voir tools/producer/studio_installe.sh)
  studio.py --un-tour  (un seul tour, pour essayer)
Journal : .studio/studio.log ; état : .studio/studio_etat.json ; état affiché par le board : studio.json.
"""
from __future__ import annotations

import copy
import json
import re
import shlex
import os
import subprocess
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools", "blackout"))
os.environ.setdefault("PRODUCER_URL", "http://127.0.0.1:8099/producer/")
import cli  # noqa: E402
import iteration as it  # noqa: E402
import refaire  # noqa: E402

STUDIO = os.path.join(ROOT, ".studio")
SITE = os.path.join(STUDIO, "site")
DATA = os.path.join(SITE, "producer", "data")
ETAT = os.path.join(STUDIO, "studio_etat.json")
A_TRAITER = os.path.join(STUDIO, "a_traiter.json")      # refus à refaire, relevés par Claude
REFAIRE = os.path.join(STUDIO, "refaire")                # ses demandes ajustées, <id>.json
LOG = os.path.join(STUDIO, "studio.log")
PY = os.path.join(ROOT, ".venv", "bin", "python")
PAUSE_S = 60
DELAI_PROD_S = 600          # déploiement groupé : 10 min après le dernier accept
ESSAIS_MAX = 2
ORDRE = ["backlog", "todo", "doing", "qa", "valide", "done"]
RANG = {s: i for i, s in enumerate(ORDRE)}
FIN = ("failed", "cancelled", "introuvable")
EN_COURS = ("pending", "running", "queued")
FAMILLES = {"persos": it.Persos, "pnj": it.Pnj}
PRIO = {"haute": "high", "basse": "low"}


def log(*m) -> None:
    os.makedirs(STUDIO, exist_ok=True)
    with open(LOG, "a") as f:
        f.write(time.strftime("%d/%m %H:%M:%S ") + " ".join(str(x) for x in m) + "\n")


def charge(chemin: str, defaut):
    try:
        return json.load(open(chemin))
    except (OSError, ValueError):
        return defaut


def ecrit(chemin: str, data) -> None:
    tmp = chemin + ".tmp"
    json.dump(data, open(tmp, "w"), ensure_ascii=False, indent=1)
    os.replace(tmp, chemin)


def studio_json(cle: str, valeur: dict) -> None:
    """État lu par le board (route studio) : build de QA et déploiement."""
    os.makedirs(DATA, exist_ok=True)
    s = charge(os.path.join(DATA, "studio.json"), {})
    s[cle] = {**valeur, "at": int(time.time())}
    ecrit(os.path.join(DATA, "studio.json"), s)


def sh(*cmd: str, timeout: int = 1800) -> tuple[int, str]:
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr)[-4000:]


# ------------------------------------------------------------------ board
def cartes() -> list:
    r = cli.call("cards")
    return r.get("cards", r) if isinstance(r, dict) else r


def bouge(c: dict, st: str, pourquoi: str = "") -> None:
    if c["status"] == st:
        return
    cli.call("card_move", {"id": c["id"], "status": st})
    if pourquoi:
        cli.call("card_comment", {"id": c["id"], "body": pourquoi})
    log(f"#{c['id']} {c['title']} : {c['status']} → {st}", pourquoi)
    c["status"] = st


def commente(c: dict, txt: str) -> None:
    cli.call("card_comment", {"id": c["id"], "body": txt})
    log(f"#{c['id']} {c['title']} :", txt)


_BANQUES: dict = {}


def banque(f: str):
    if f not in _BANQUES:
        _BANQUES[f] = FAMILLES[f]()
    return _BANQUES[f]


def cible(c: dict):
    """(famille, pid, détail) d'une carte liée à un set itéré, sinon None. Détail : base, expr:<clé> ou
    un élément (run, victoire…) ; "" pour le chapeau. Une carte portrait:<usage> (Julien 24/10) vise la
    tâche qui le fait : la base neutre, ou la base avec l'expression de l'usage (GDD §8.5)."""
    a = c.get("asset") or ""
    p = a.split("/")
    if len(p) == 4 and p[0] == "blackout" and p[1] in FAMILLES and p[3] == "animations":
        d = c.get("detail") or ""
        if d.startswith("portrait:"):
            b = banque(p[1])
            v = b.ex["portraits"].get(d[9:], "base") if p[1] == "persos" else "base"
            k = b.base(p[2]) if v == "base" else v
            d = "base" if k == it.NEUTRE else f"expr:{k}"
        return p[1], p[2], d
    return None


# ------------------------------------------------------------------ pixelforge
class Taches:
    """Statuts pixelforge, mis en cache quand ils ne bougent plus."""

    def __init__(self, cache: dict) -> None:
        self.cache = cache
        self.vus: dict = {}

    def statut(self, tid: str) -> str:
        if not tid:
            return "absente"
        if tid in self.cache:
            return self.cache[tid]
        if tid not in self.vus:
            st = it.get(tid).get("status", "?")
            self.vus[tid] = st
            if st == "succeeded" or st in FIN:
                self.cache[tid] = st
        return self.vus[tid]


def taches_de(s: dict, b, pid: str, d: str) -> list:
    """Tâches d'une carte : [(rôle, libellé, id)]."""
    if d == "base":
        return [("base", "profil et portrait neutres", s.get("base", ""))]
    if d.startswith("expr:"):
        return [("expression", d[5:], s.get("expressions", {}).get(d[5:], ""))]
    a = s.get("animations", {}).get(d)
    if not a:
        return []
    return [("A", f"{d} HD ({a.get('expression')})", a["A"]), ("B", f"{d} pixel", a.get("B") or "")]


class Studio:
    def __init__(self) -> None:
        self.etat = charge(ETAT, {})
        for k in ("statuts", "gardees", "integre", "a_construire", "rework_a", "signale", "suit", "propage"):
            self.etat.setdefault(k, {} if k not in ("a_construire",) else [])
        self.t = Taches(self.etat["statuts"])
        self.bq = {f: banque(f) for f in FAMILLES}

    def sauve(self) -> None:
        ecrit(ETAT, self.etat)

    # ---------------------------------------------------------- tour
    def tour(self) -> None:
        self.t.vus = {}
        cs = cartes()
        par_id = {c["id"]: c for c in cs}
        enfants: dict = {}
        for c in cs:
            if c.get("parent_id"):
                enfants.setdefault(c["parent_id"], []).append(c)
        self.todo_des_chapeaux(cs, enfants)
        self.commandes(cs)
        e = it.etat()                                   # relu après les commandes, qui peuvent l'écrire
        voulues = [c for c in cs if cible(c) and cible(c)[2] and c["status"] in ("todo", "doing")
                   and not commandes_de(c)[0]]
        for c in cs:                                    # boss, animaux, fantôme : pas encore en itérations
            if c["status"] == "todo" and not cible(c) and (c.get("asset") or "").startswith("blackout/") \
                    and not enfants.get(c["id"]) and str(c["id"]) not in self.etat["signale"]:
                commente(c, "studio : ce set n'est pas encore automatisé (iteration.py : persos et PNJ) ; "
                            "l'agent le lance à la main")
                self.etat["signale"][str(c["id"])] = "manuel"
        attente = self.propage(e, cs, par_id) + self.refait(e, voulues)
        it.sauve(e)
        voulues = [c for c in voulues if c["id"] not in attente]
        self.depose(e, voulues, par_id)
        it.sauve(e)
        self.echecs(e, voulues)
        it.sauve(e)
        self.synchronise(e, cs)
        if self.integre(e, voulues):
            it.sauve(e)
        self.build_qa(par_id)
        self.chapeaux(cs, enfants)
        self.prod(cartes())
        self.sauve()

    def todo_des_chapeaux(self, cs: list, enfants: dict) -> None:
        # Les objets, effets et icônes des coups et le décor (pas encore automatisés, faits après les 13 persos)
        # restent en Backlog : Julien les met en Todo lui-même.
        tire = lambda k: k["status"] == "backlog" and not (k.get("asset") or "").startswith(("blackout/coups/", "maps/"))  # noqa: E731
        for c in cs:
            if c["status"] == "todo" and enfants.get(c["id"]):
                for k in enfants[c["id"]]:
                    if tire(k):
                        bouge(k, "todo")
                        k["status"] = "todo"
                for k in enfants[c["id"]]:          # sous-chapeaux (portraits, coups)
                    if enfants.get(k["id"]) and k["status"] == "todo":
                        for kk in enfants[k["id"]]:
                            if tire(kk):
                                bouge(kk, "todo")

    # ---------------------------------------------------------- 0. cartes à commande
    def commandes(self, cs: list) -> None:
        """Carte dont la description donne sa commande (« $ … », Julien 24/10) : en Todo, le watcher la lance
        et passe la carte en Doing ; les tâches pixelforge citées par la commande sont suivies ; quand elles
        sont finies, les commandes « $ apres: … » tournent (intégration), puis build de QA et QA."""
        cmds = self.etat.setdefault("commandes", {})
        par_id = {c["id"]: c for c in cs}
        for c in cs:
            avant, apres = commandes_de(c)
            if not avant:
                continue
            k = str(c["id"])
            attente = [int(n) for n in re.findall(r"^\s*\$ attend:\s*#(\d+)", c.get("description") or "", re.M)]
            if c["status"] == "todo" and any(RANG.get(par_id.get(n, {}).get("status"), 9) < RANG["qa"] for n in attente):
                continue                                # « $ attend: #N » : pas avant que la carte N soit en QA
            if c["status"] == "todo" and k not in cmds:
                taches, sorties = [], []
                for argv in avant:
                    ok, out = lance(argv)
                    sorties.append(f"$ {' '.join(argv)} → {'ok' if ok else 'ÉCHEC'}\n{out[-600:]}")
                    taches += [t for t in re.findall(r"\b[0-9a-f]{32}\b", out) if t not in taches]
                    if not ok:
                        break
                cmds[k] = {"taches": taches, "apres": False, "ok": ok}
                commente(c, "studio : commande lancée\n" + "\n".join(sorties)[-3000:])
                if ok:
                    bouge(c, "doing")
                continue
            d = cmds.get(k)
            if not d or c["status"] != "doing" or d.get("apres") or not d.get("ok"):
                continue
            sts = [self.t.statut(t) for t in d["taches"]]
            jobs = [{"id": t, "role": "tâche", "label": "commande", "status": s,
                     "keep": bool(self.etat["gardees"].get(t))} for t, s in zip(d["taches"], sts)]
            for t in d["taches"]:
                if not self.etat["gardees"].get(t):
                    try:
                        it.keep(t)
                        self.etat["gardees"][t] = 1
                    except Exception:
                        pass
            txt = json.dumps(jobs, ensure_ascii=False)
            if jobs and txt != (c.get("jobs") or ""):
                cli.call("card_update", {"id": c["id"], "jobs": txt})
            if any(s in FIN for s in sts):
                if not d.get("signale"):
                    commente(c, "studio : une tâche de la commande a échoué : à voir par l'agent")
                    d["signale"] = True
                continue
            if all(s == "succeeded" for s in sts):
                sorties = []
                for argv in apres:
                    ok, out = lance(argv)
                    sorties.append(f"$ {' '.join(argv)} → {'ok' if ok else 'ÉCHEC'}\n{out[-600:]}")
                d["apres"] = True
                if sorties:
                    commente(c, "studio : tâches finies\n" + "\n".join(sorties)[-3000:])
                if c["id"] not in self.etat["a_construire"]:
                    self.etat["a_construire"].append(c["id"])

    # ---------------------------------------------------------- 1. dépôts
    def propage(self, e: dict, cs: list, par_id: dict) -> list:
        """Profil de référence refusé (Julien 24/10) : une base ou une expression refusée en QA emmène dans sa
        colonne (Backlog ou Todo, selon le refus) tout ce qui en est fait et qui était en QA, Validé ou En prod :
        les expressions et portraits d'une base, les animations et portraits faits sur ce profil. Ces cartes
        attendent que le profil soit refait (sa carte n'est plus « à retraiter ») ; en Todo, elles sont alors
        redemandées depuis le nouveau profil (anciennes tâches dans « refaites »). Rend les cartes qui attendent."""
        suit, fait = self.etat["suit"], self.etat["propage"]
        for c in cs:
            if not c.get("rework") or c["status"] not in ("backlog", "todo") or not cible(c):
                continue
            f, pid, d = cible(c)
            if d != "base" and not d.startswith("expr:"):
                continue
            b = self.bq[f]
            s = e.get(it.cle(b, pid), {})
            tid = s.get("base") if d == "base" else s.get("expressions", {}).get(d[5:])
            if not tid or fait.get(str(c["id"])) == tid:
                continue
            fait[str(c["id"])] = tid
            for k in cs:
                ck = cible(k) if k["id"] != c["id"] else None
                if not ck or ck[:2] != (f, pid) or k["status"] not in ("qa", "valide", "done"):
                    continue
                d2 = ck[2]
                a = s.get("animations", {}).get(d2) or {}
                # Une base porte tout le perso (expressions, puis animations faites sur elles) ; une expression,
                # ses portraits et les animations faites sur elle.
                if d == "base" or d2 == d or a.get("socle") == tid:
                    bouge(k, c["status"], f"studio : suit son profil de référence #{c['id']} ({d}), refusé en QA "
                                          "(Julien 24/10) ; sera refait depuis le nouveau profil")
                    suit[str(k["id"])] = c["id"]
        attente = []
        for kid, sid in list(suit.items()):
            k, sc = par_id.get(int(kid)), par_id.get(sid)
            if not k or not sc:
                suit.pop(kid, None)
                continue
            if sc.get("rework"):
                attente.append(k["id"])                 # le profil n'est pas encore refait
                continue
            if k["status"] != "todo":
                continue                                # en Backlog : attend que Julien la mette en Todo
            f, pid, d2 = cible(k)
            s = e.get(it.cle(self.bq[f], pid), {})
            rf = s.setdefault("refaites", {})
            if d2.startswith("expr:") and d2 != cible(sc)[2] and d2[5:] in s.get("expressions", {}):
                ancien = s["expressions"].pop(d2[5:])
                rf[f"{d2}_profil_{ancien[:8]}"] = ancien
            elif d2 in s.get("animations", {}):
                ancien = s["animations"].pop(d2)["A"]
                rf[f"{d2}_profil_{ancien[:8]}"] = ancien
                s.get("integre", {}).pop(d2, None)
            self.etat["integre"].pop(kid, None)
            suit.pop(kid)
            log(pid, d2, "redemandée depuis le nouveau profil", f"(#{sid})")
        return attente

    def refait(self, e: dict, voulues: list) -> list:
        """« Refuser et refaire » (Julien 24/10) : une carte refusée remise en Todo attend Claude, qui relève
        .studio/a_traiter.json toutes les 30 min, applique le commentaire du refus à la demande et écrit
        .studio/refaire/<id>.json : {"modifs": {prompt, extras, elements, expression}, "explication": "…"}.
        Le watcher contrôle les modifs (refaire.controle) puis redépose avec une autre graine. Un sous-élément
        repart du profil déjà validé : une animation garde la base ou l'expression qui lui sert de socle, une
        expression garde la base ; seul l'élément refusé est refait (l'ancienne tâche va dans « refaites »).
        Rend les ids des cartes en attente (le reste du tour les laisse de côté)."""
        attente, liste = [], {}
        for c in voulues:
            if c["status"] != "todo" or not c.get("rework"):
                continue
            f, pid, d = cible(c)
            b = self.bq[f]
            s = e.get(it.cle(b, pid), {})
            ts = taches_de(s, b, pid, d)
            cle = ",".join(tid for _r, _l, tid in ts)
            if not ts or not all(tid for _r, _l, tid in ts):
                continue                                # jamais déposée : depose s'en charge
            refusee = self.etat["integre"].get(str(c["id"])) or self.etat["rework_a"].setdefault(str(c["id"]), cle)
            if cle != refusee:
                continue                                # déjà refaite, on attend la nouvelle tâche
            fichier = os.path.join(REFAIRE, f"{c['id']}.json")
            if os.path.exists(fichier):
                try:
                    self.redepose(e, c, b, s, pid, d, cle, charge(fichier, {}))
                    os.remove(fichier)
                    continue
                except Exception as err:            # noqa: BLE001
                    os.rename(fichier, fichier + ".refuse")
                    commente(c, f"studio : demande ajustée refusée ({err}) ; à reprendre par Claude")
            attente.append(c["id"])
            refus = [n for n in c.get("notes", []) if n.get("kind") == "refus"]
            requete = self._apercu(e, b, pid, d)
            liste[str(c["id"])] = {"titre": c["title"], "famille": f, "perso": pid, "element": d,
                                   "commentaire": refus[-1]["body"] if refus else "", "requete": requete}
            if str(c["id"]) not in self.etat["signale"]:
                self.etat["signale"][str(c["id"])] = "refaire"
                commente(c, "studio : à refaire, en attente de Claude (relève toutes les 30 min) "
                            "pour appliquer le commentaire du refus")
        if liste or os.path.exists(A_TRAITER):
            ecrit(A_TRAITER, liste)
        return attente

    def job(self, e: dict, b, pid: str, d: str, prio: str, montre: bool, graine: int) -> None:
        if d == "base":
            it.job_base(b, e, pid, prio, montre, graine)
        elif d.startswith("expr:"):
            it.job_expression(b, e, pid, d[5:], prio, montre, graine)
        else:
            it.job_anim(b, e, pid, d, prio, montre, graine)

    def redepose(self, e: dict, c: dict, b, s: dict, pid: str, d: str, cle: str, dem: dict) -> None:
        modifs, expl = dem.get("modifs") or {}, str(dem.get("explication", "")).strip()
        def ajuste(r: dict) -> dict:
            r2 = {**r, **modifs}
            refaire.controle(r, r2)
            return r2
        ajuste(self._apercu(e, b, pid, d))          # contrôle avant tout changement d'état
        it.AJUSTE = ajuste
        rf = s.setdefault("refaites", {})
        n = 1 + sum(1 for k in rf if k.startswith(f"{d}_refus_"))
        graine = it.GRAINE + n
        prio = self.prio([c])
        garde = dict(s.get("expressions", {}))
        anciennes = (dict(s.get("expressions", {})), dict(s.get("animations", {})))
        try:
            if d.startswith("expr:"):
                s["expressions"].pop(d[5:], None)
            elif d != "base":
                s["animations"].pop(d, None)
            self.job(e, b, pid, d, prio, False, graine)
        except BaseException:
            s["expressions"], s["animations"] = anciennes
            raise
        finally:
            it.AJUSTE = None
        if d == "base":
            s["expressions"] = garde                    # les expressions faites restent
            socle = "nouvelle base"
        elif d.startswith("expr:"):
            socle = f"base {s['base'][:8]}"
        else:
            socle = f"socle {s['animations'][d]['socle'][:8]} ({s['animations'][d]['expression']})"
        rf[f"{d}_refus_{n}"] = cle
        s.get("integre", {}).pop(d, None)
        self.etat["rework_a"][str(c["id"])] = cle
        self.etat["signale"].pop(str(c["id"]), None)
        it.sauve(e)
        log(pid, d, "refaite après refus, graine", graine, "depuis", socle)
        commente(c, f"studio : refaite chez pixelforge depuis le profil validé ({socle}), graine {graine}"
                    + (f". Claude : {expl}" if expl else ""))

    def _apercu(self, e: dict, b, pid: str, d: str) -> dict:
        """La demande telle qu'elle serait redéposée (rien n'est déposé ni écrit)."""
        r: dict = {}
        e2 = copy.deepcopy(e)
        s2 = e2.get(it.cle(b, pid), {})
        if d.startswith("expr:"):
            s2.get("expressions", {}).pop(d[5:], None)
        ancien = it.AJUSTE
        it.AJUSTE = lambda x: r.update(x) or x
        try:
            with open(os.devnull, "w") as nul:
                sortie, sys.stdout = sys.stdout, nul
                try:
                    self.job(e2, b, pid, d, "normal", True, it.GRAINE)
                finally:
                    sys.stdout = sortie
        finally:
            it.AJUSTE = ancien
        return r

    def depose(self, e: dict, voulues: list, par_id: dict) -> None:
        def rang_perso(c):
            h = par_id.get(c.get("parent_id") or 0, c)
            return (RANG.get(h["status"], 9) * -1, h.get("position", 0), h["id"])
        groupes: dict = {}
        for c in sorted(voulues, key=rang_perso):
            f, pid, d = cible(c)
            groupes.setdefault((f, pid), []).append(c)
        precedent_fini = True
        for (f, pid), cartes_p in groupes.items():
            b = self.bq[f]
            prio = self.prio(cartes_p)
            s = e.setdefault(it.cle(b, pid), {})
            if not s.get("base"):
                it.job_base(b, e, pid, prio, False)
                log(pid, "base neutre déposée", s["base"])
            st_base = self.t.statut(s["base"])
            for c in cartes_p:
                if c["status"] == "todo" and cible(c)[2] == "base":
                    bouge(c, "doing", f"en file chez pixelforge (base {s['base'][:8]})")
            if st_base != "succeeded" or not precedent_fini:
                precedent_fini = False                  # un perso à la fois : le suivant attend
                continue
            tout = True
            for c in cartes_p:
                d = cible(c)[2]
                if d == "base":
                    continue
                k = d[5:] if d.startswith("expr:") else b.expression(pid, d)
                if k != it.NEUTRE and k not in s.get("expressions", {}):
                    it.job_expression(b, e, pid, k, prio, False)
                    log(pid, "expression", k, "déposée")
                if d.startswith("expr:"):
                    if c["status"] == "todo":
                        bouge(c, "doing", f"en file chez pixelforge (expression {k})")
                    continue
                if d in s.get("animations", {}):
                    if c["status"] == "todo":
                        bouge(c, "doing", "en file chez pixelforge")
                    continue
                socle = s["base"] if k == it.NEUTRE else s["expressions"][k]
                if self.t.statut(socle) == "succeeded":
                    it.job_anim(b, e, pid, d, prio, False)
                    log(pid, d, "animation déposée", s["animations"][d]["A"])
                    bouge(c, "doing", f"en file chez pixelforge ({k})")
                else:
                    tout = False
            precedent_fini = tout

    @staticmethod
    def prio(cs: list) -> str:
        if any(c.get("night") for c in cs):
            return "night"
        for p in ("haute", "normale", "basse"):
            if any(c.get("priority") == p for c in cs):
                return PRIO.get(p, "normal")
        return "normal"

    # ---------------------------------------------------------- 2. échecs
    def echecs(self, e: dict, voulues: list) -> None:
        for c in voulues:
            f, pid, d = cible(c)
            b = self.bq[f]
            s = e.get(it.cle(b, pid), {})
            ech = s.setdefault("echouees", {})
            essais = sum(1 for x in ech if x.startswith(f"{d}_"))
            rates = [(r, tid) for r, _l, tid in taches_de(s, b, pid, d) if tid and self.t.statut(tid) in FIN]
            if not rates:
                continue
            role, tid = rates[0]
            st = self.t.statut(tid)
            if essais >= ESSAIS_MAX:
                if self.etat["signale"].get(str(c["id"])) != tid:
                    commente(c, f"pixelforge : tâche {role} {tid[:8]} {st}, après {essais} essais : à voir par l'agent")
                    self.etat["signale"][str(c["id"])] = tid
                continue
            ech[f"{d}_{tid[:8]}"] = tid
            if d == "base":
                s.pop("base", None)
            elif d.startswith("expr:"):
                s.get("expressions", {}).pop(d[5:], None)
            else:
                s.get("animations", {}).pop(d, None)
            commente(c, f"pixelforge : tâche {role} {tid[:8]} {st} ; redéposée (essai {essais + 2})")

    # ---------------------------------------------------------- 3. jobs et keep
    def synchronise(self, e: dict, cs: list) -> None:
        for c in cs:
            ci = cible(c)
            if not ci or not ci[2]:
                continue
            f, pid, d = ci
            b = self.bq[f]
            s = e.get(it.cle(b, pid), {})
            jobs = []
            for role, lib, tid in taches_de(s, b, pid, d):
                if not tid:
                    continue
                st = self.t.statut(tid) if c["status"] != "backlog" else self.etat["statuts"].get(tid, "?")
                garde = False
                if RANG.get(c["status"], 0) >= RANG["doing"]:
                    if not self.etat["gardees"].get(tid):
                        try:
                            it.keep(tid)
                            self.etat["gardees"][tid] = 1
                        except Exception as x:   # tâche purgée : rien à garder
                            log("keep impossible", tid[:8], str(x)[:60])
                    garde = bool(self.etat["gardees"].get(tid))
                jobs.append({"id": tid, "role": role, "label": lib, "status": st, "keep": garde})
            txt = json.dumps(jobs, ensure_ascii=False)
            if jobs and txt != (c.get("jobs") or ""):
                cli.call("card_update", {"id": c["id"], "jobs": txt})

    # ---------------------------------------------------------- 4. intégration locale
    def integre(self, e: dict, voulues: list) -> bool:
        neuves: dict = {}
        for c in voulues:
            f, pid, d = cible(c)
            b = self.bq[f]
            s = e.get(it.cle(b, pid), {})
            ts = taches_de(s, b, pid, d)
            if not ts or not all(tid and self.t.statut(tid) == "succeeded" for _r, _l, tid in ts):
                continue
            cle = ",".join(tid for _r, _l, tid in ts)   # une réduction refaite (même A, nouveau B) se réintègre
            if self.etat["integre"].get(str(c["id"])) == cle:
                continue
            if c.get("rework") and self.etat["rework_a"].get(str(c["id"])) == cle:
                continue                                # refusée : on attend une nouvelle tâche
            neuves.setdefault((f, pid), []).append((c, cle))
        for (f, pid), lst in neuves.items():
            b = self.bq[f]
            it.integre(b, e, pid)
            for c, cle in lst:
                self.etat["integre"][str(c["id"])] = cle
                if c["id"] not in self.etat["a_construire"]:
                    self.etat["a_construire"].append(c["id"])
            log(pid, "intégré en local :", ", ".join(cible(c)[2] for c, _ in lst))
        for c in voulues:                               # mémorise la tâche refusée
            if c.get("rework") and str(c["id"]) not in self.etat["rework_a"]:
                self.etat["rework_a"][str(c["id"])] = self.etat["integre"].get(str(c["id"]), "")
        return bool(neuves)

    # ---------------------------------------------------------- 5. build de QA
    def build_qa(self, par_id: dict) -> None:
        if not self.etat["a_construire"]:
            return
        log("build de QA :", len(self.etat["a_construire"]), "cartes")
        ok, msg = construit_qa()
        commit = sh("git", "rev-parse", "--short", "HEAD")[1].strip()
        studio_json("qa_build", {"ok": ok, "commit": commit, "message": msg[-300:]})
        if not ok:
            log("build de QA en échec :", msg[-300:])
            return
        self.versionne()
        for cid in self.etat["a_construire"]:
            c = par_id.get(cid)
            if c and c["status"] in ("todo", "doing"):
                bouge(c, "qa", "livrée par pixelforge, intégrée telle quelle : à tester dans le jeu de QA (/jeu/)")
            if c:
                self.etat["rework_a"].pop(str(cid), None)
        self.etat["a_construire"] = []

    def versionne(self) -> None:
        """Tous les assets intégrés (32 px et HD en LFS) sur la branche assets-integres (Julien 24/10),
        en arrière-plan : un envoi LFS peut durer, le tour n'attend pas. Un seul à la fois."""
        en_cours = getattr(self, "_versionne", None)
        if en_cours and en_cours.poll() is None:
            return
        out = open(os.path.join(STUDIO, "branche_assets.log"), "a")
        self._versionne = subprocess.Popen([PY, os.path.join(HERE, "branche_assets.py")], cwd=ROOT,
                                           stdout=out, stderr=subprocess.STDOUT)

    # ---------------------------------------------------------- 6. chapeaux
    def chapeaux(self, cs: list, enfants: dict) -> None:
        cs = cartes()
        par_id = {c["id"]: c for c in cs}
        enf = {}
        for c in cs:
            if c.get("parent_id"):
                enf.setdefault(c["parent_id"], []).append(c)
        # Du plus profond au plus haut : un sous-chapeau se règle avant son chapeau.
        def prof(c):
            n, p = 0, c
            while p.get("parent_id") and p["parent_id"] in par_id and n < 5:
                p, n = par_id[p["parent_id"]], n + 1
            return -n
        for h in sorted((c for c in cs if enf.get(c["id"])), key=prof):
            rangs = [RANG.get(k["status"], 0) for k in enf[h["id"]]]
            bas = min(rangs)
            if bas >= RANG["doing"]:
                st = ORDRE[bas]
            elif RANG["doing"] in rangs:
                st = "doing"                            # un enfant en cours
            elif RANG.get(h["status"], 0) >= RANG["qa"] and max(rangs) <= RANG["todo"]:
                st = ORDRE[max(rangs)]                  # en QA ou après sans rien de livré dessous (Julien 24/10)
            else:
                continue                                # rien en cours : la colonne du chapeau ne bouge pas
            if st != h["status"] and not (h["status"] == "valide" and st == "qa"):
                bouge(h, st)

    # ---------------------------------------------------------- 7. mise en prod
    def prod(self, cs: list) -> None:
        d = self.etat.get("deploiement")
        if d:                                           # déploiement lancé : on suit le run
            rc, out = sh("gh", "run", "view", str(d["run"]), "--json", "status,conclusion")
            if rc != 0:
                return
            r = json.loads(out[out.index("{"):])
            if r["status"] != "completed":
                return
            if r["conclusion"] == "success":
                par_id = {c["id"]: c for c in cs}
                for cid in d["cartes"]:
                    if par_id.get(cid, {}).get("status") == "valide":
                        bouge(par_id[cid], "done")
                studio_json("deploy", {"state": "idle", "cards": d["cartes"], "message": f"en prod ({d['commit']})"})
                log("en prod :", d["cartes"])
            else:
                studio_json("deploy", {"state": "echec", "cards": d["cartes"],
                                       "message": f"deploy.yml {r['conclusion']} (run {d['run']})"})
                log("déploiement en échec", d["run"])
                self.etat["dernier_echec"] = d["dernier_accept"]
            self.etat.pop("deploiement")
            return
        val = [c for c in cs if c["status"] == "valide"]
        if not val:
            return
        dernier = max(int(c.get("status_at") or 0) for c in val)
        if self.etat.get("dernier_echec") == dernier:
            return                                      # échec déjà vu : on attend un nouvel accept
        if time.time() - dernier < DELAI_PROD_S:
            studio_json("deploy", {"state": "en_attente", "cards": [c["id"] for c in val],
                                   "message": f"déploiement vers {time.strftime('%H:%M', time.localtime(dernier + DELAI_PROD_S))}"})
            return
        self.deploie(val, dernier)

    def deploie(self, val: list, dernier: int) -> None:
        ids = [c["id"] for c in val]
        if sh("git", "diff", "--cached", "--quiet")[0] != 0:
            studio_json("deploy", {"state": "echec", "cards": ids, "message": "index git non vide : déploiement suspendu"})
            log("index git non vide : déploiement suspendu")
            self.etat["dernier_echec"] = dernier
            return
        studio_json("deploy", {"state": "en_cours", "cards": ids, "message": "tests"})
        ok, msg = tests()
        if not ok:
            studio_json("deploy", {"state": "echec", "cards": ids, "message": "tests en échec : " + msg[-200:]})
            self.etat["dernier_echec"] = dernier
            return
        n = 0
        for c in val:
            n += prepare_commit(c)
        if n:
            titres = ", ".join(f"#{c['id']}" for c in val)[:300]
            rc, out = sh("git", "commit", "-q", "-m", f"Mise en prod des cartes validées : {titres}\n\n"
                         "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n"
                         "Claude-Session: https://claude.ai/code/session_01LXFHAN75rdxEcdsy5wKHqu")
            if rc != 0:
                studio_json("deploy", {"state": "echec", "cards": ids, "message": "commit : " + out[-200:]})
                self.etat["dernier_echec"] = dernier
                return
        rc, out = sh("git", "push", "-q", "origin", "main")
        if rc != 0:
            studio_json("deploy", {"state": "echec", "cards": ids, "message": "push : " + out[-200:]})
            self.etat["dernier_echec"] = dernier
            return
        avant = sh("gh", "run", "list", "--workflow", "deploy.yml", "--limit", "1", "--json", "databaseId")[1]
        rc, out = sh("gh", "workflow", "run", "deploy.yml", "--ref", "main")
        if rc != 0:
            studio_json("deploy", {"state": "echec", "cards": ids, "message": "gh workflow run : " + out[-200:]})
            self.etat["dernier_echec"] = dernier
            return
        run = None
        for _ in range(12):
            time.sleep(5)
            o = sh("gh", "run", "list", "--workflow", "deploy.yml", "--limit", "1", "--json", "databaseId")[1]
            if o != avant and "databaseId" in o:
                run = json.loads(o[o.index("["):])[0]["databaseId"]
                break
        commit = sh("git", "rev-parse", "--short", "HEAD")[1].strip()
        if not run:
            studio_json("deploy", {"state": "echec", "cards": ids, "message": "run deploy.yml introuvable"})
            self.etat["dernier_echec"] = dernier
            return
        self.etat["deploiement"] = {"run": run, "cartes": ids, "commit": commit, "dernier_accept": dernier}
        studio_json("deploy", {"state": "en_cours", "cards": ids, "message": f"deploy.yml en cours ({commit})"})
        log("déploiement lancé", run, ids)


# ------------------------------------------------------------------ commandes des cartes
OUTILS = ("tools/blackout/", "tools/pf/", "tools/producer/")


def commandes_de(c: dict) -> tuple[list, list]:
    """Lignes « $ … » (à lancer en Todo) et « $ apres: … » (quand les tâches sont finies) de la description."""
    avant, apres = [], []
    for ligne in (c.get("description") or "").splitlines():
        ligne = ligne.strip().strip("`").strip()
        if not ligne.startswith("$ "):
            continue
        ligne = ligne[2:].strip()
        if ligne.startswith("attend:"):
            continue
        cible_ = apres if ligne.startswith("apres:") else avant
        try:
            argv = shlex.split(ligne.split(":", 1)[1] if cible_ is apres else ligne)
        except ValueError:
            continue
        if argv:
            cible_.append(argv)
    return avant, apres


def lance(argv: list) -> tuple[bool, str]:
    """Lance un outil du dépôt (tools/blackout, tools/pf, tools/producer : .py ou .sh), sans shell."""
    chemin = os.path.realpath(os.path.join(ROOT, argv[0]))
    rel = os.path.relpath(chemin, ROOT)
    if not rel.startswith(OUTILS) or not rel.endswith((".py", ".sh")) or not os.path.isfile(chemin):
        return False, f"refusé : {argv[0]} n'est pas un outil du dépôt (tools/blackout, tools/pf, tools/producer)"
    if rel.endswith("studio.py"):
        return False, "refusé : le watcher ne se relance pas lui-même"
    try:
        rc, out = sh(PY if rel.endswith(".py") else "bash", chemin, *argv[1:], timeout=900)
    except subprocess.TimeoutExpired:
        return False, "trop long (15 min)"
    return rc == 0, out


# ------------------------------------------------------------------ build, tests, commit
def tests() -> tuple[bool, str]:
    sh("godot", "--headless", "--path", ".", "--import")
    rc, out = sh("godot", "--headless", "--path", ".", "--fixed-fps", "60", "--script", "res://tests/bk_tests.gd")
    return " 0 échecs" in out, out


def construit_qa() -> tuple[bool, str]:
    ok, out = tests()
    if not ok:
        return False, "tests : " + out
    jeu = os.path.join(SITE, "jeu.neuf")
    sh("rm", "-rf", jeu)
    os.makedirs(jeu)
    rc, out = sh("godot", "--headless", "--path", ".", "--export-release", "Web", os.path.join(jeu, "index.html"))
    if rc != 0 or not os.path.exists(os.path.join(jeu, "index.wasm")):
        return False, "export : " + out
    sh("rm", "-rf", os.path.join(SITE, "jeu.ancien"))
    if os.path.exists(os.path.join(SITE, "jeu")):
        os.replace(os.path.join(SITE, "jeu"), os.path.join(SITE, "jeu.ancien"))
    os.replace(jeu, os.path.join(SITE, "jeu"))
    rc, out2 = sh("bash", "tools/producer/build.sh", os.path.join(SITE, "producer"), PY)
    return rc == 0, "board : " + out2 if rc else "ok"


def fichiers_carte(f: str, pid: str, d: str) -> list:
    """Fichiers de travail d'une carte de set itéré (chemins relatifs au dépôt)."""
    base = os.path.join("assets", "blackout", f, pid)
    out = []
    for sous in ("hd", "px32"):
        dossier = os.path.join(ROOT, base, sous)
        if not os.path.isdir(dossier):
            continue
        for n in sorted(os.listdir(dossier)):
            if d == "base":
                ok = n in ("profile_hd.png", "portrait_hd.png")
            elif d.startswith("expr:"):
                ok = n.endswith(f"_{d[5:]}_hd.png")
            else:
                ok = it.element_de(n) == d
            if ok or n == "set.json":
                out.append(os.path.join(base, sous, n))
    return out


def prepare_commit(c: dict) -> int:
    """Met dans l'index git les seuls fichiers de la carte validée ; animations.json : la version déjà en
    prod, plus la seule entrée de cette animation. Renvoie le nombre de fichiers ajoutés."""
    ci = cible(c)
    if not ci:
        a = c.get("asset") or ""
        chemin = os.path.join("assets", a)
        if a and os.path.exists(os.path.join(ROOT, chemin)):
            sh("git", "add", "--", chemin)
            return 1
        return 0
    f, pid, d = ci
    if not d:
        return 0                                        # chapeau : ses enfants portent les fichiers
    fs = fichiers_carte(f, pid, d)
    if fs:
        sh("git", "add", "--", *fs)
    if d not in ("base",) and not d.startswith("expr:"):
        rel = os.path.join("assets", "blackout", f, pid, "px32", "animations.json")
        travail = charge(os.path.join(ROOT, rel), {})
        if d in travail:
            index = sh("git", "show", f":{rel}")
            prod = json.loads(index[1]) if index[0] == 0 else {}
            prod[d] = travail[d]
            data = json.dumps(prod, ensure_ascii=False, indent=1).encode()
            p = subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=ROOT, input=data, capture_output=True)
            sha = p.stdout.decode().strip()
            sh("git", "update-index", "--add", "--cacheinfo", f"100644,{sha},{rel}")
            fs.append(rel)
    return len(fs)


def main() -> None:
    un = "--un-tour" in sys.argv
    log("studio démarré")
    s = Studio()
    while True:
        try:
            s.tour()
        except (Exception, SystemExit) as x:   # pixelforge ou board indisponible (cli sort par SystemExit) : tour suivant
            log("tour interrompu :", str(x)[:200])
            log(traceback.format_exc()[-800:])
            s.sauve()
        if un:
            break
        time.sleep(PAUSE_S)


if __name__ == "__main__":
    main()
