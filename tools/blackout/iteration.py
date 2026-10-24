#!/usr/bin/env python3
"""Itérations pixelforge par animation (Julien, 23/10 ; GDD §8.5) : plus de set complet. Trois jobs, dans
cet ordre, chacun gardé (keep) :
  1. base neutre : profil et portrait HD seuls (preview) ;
  2. base avec expression : la base neutre avec seulement le visage changé (expression + expression_of) ;
  3. animation : un élément animé sur la base de son expression (profile_of), puis réduit (moteur B).
L'expression de chaque élément vient des banques (style_party_hard.json → expressions ; pnj.json →
expression), jamais du prompt.

  iteration.py base louis …                    job 1
  iteration.py expression louis [fier …]       job 2 (sans clé : l'expression de base du perso)
  iteration.py anime louis run [victoire …]    job 3, un par élément (crée le job 2 manquant d'abord)
  iteration.py etat [louis …]                  ids et statuts
  iteration.py integre louis …                 rapatrie dans assets/blackout/<famille>/<id>/ (hd/ et px32/),
                                               élément par élément, sans toucher aux autres
  options : --famille persos|pnj (défaut persos), --prio high|normal|night (défaut normal), --montre
            (affiche les requêtes, n'envoie rien) ; les courses sont neutres (GDD §8.5)
Ids dans tools/blackout/iterations.json. Ne rien déposer sans l'accord de Julien (GDD §14).
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
sys.path.insert(0, HERE)
import gen_anims_pf as pf  # noqa: E402

ETAT = os.path.join(HERE, "iterations.json")
GRAINE = 7
TAG = "miarritze/iteration"
STANDARDS = ["run", "jump_hide", "lift", "interagir", "victoire", "defaite", "etourdi", "renverse", "colle",
             "ralenti", "aveugle", "tracte"]
NEUTRE = "neutre"


# ------------------------------------------------------------------ banques
class Persos:
    famille = "persos"

    def __init__(self) -> None:
        import party_hard_v2 as ph
        self.ph = ph
        self.ex = ph.SPEC["expressions"]

    def prompt(self, pid: str) -> str:
        return self.ph.prompt(pid)

    def base(self, pid: str) -> str:
        return self.ex["base"][pid]

    def expression(self, pid: str, el: str) -> str:
        e = self.ex["exceptions"].get(pid, {}).get(el) or self.ex["par_element"][el]
        return self.base(pid) if e == "base" else e

    def extras(self, pid: str) -> dict:
        il = self.ph.SPEC["idle_long"][pid]
        out = {"idle_long": {"name": "idle_long", "motion": il["clip"], "action": il["geste"], "loop": True,
                             "fps": 10, "object": il.get("objet") or False}}
        for c in self.ph.casts(pid):
            out[c["name"]] = c
        return out

    def requete_anim(self, pid: str, el: str) -> dict:
        return {}


class Pnj:
    famille = "pnj"

    def __init__(self) -> None:
        import pnj_jobs as pj
        self.pj = pj
        self.p = pj.PNJ

    def prompt(self, pid: str) -> str:
        return self.pj.requete(pid, "normal")["prompt"]

    def base(self, pid: str) -> str:
        return self.p["humains"][pid]["expression"]

    def expression(self, pid: str, el: str) -> str:
        e = self.p["set_humain"]["expressions"].get(el) or self.p["activites"].get(el, {}).get("expression", "base")
        return self.base(pid) if e == "base" else e

    def extras(self, pid: str) -> dict:
        return {e["name"]: e for e in self.pj.requete(pid, "normal")["extras"]}

    def requete_anim(self, pid: str, el: str) -> dict:
        r = self.pj.requete(pid, "normal")
        return {"clips": r["clips"], "actions": r["actions"]} if el == "run" else {}


# ------------------------------------------------------------------ pixelforge
def get(tid: str) -> dict:
    try:
        req = urllib.request.Request(f"{pf.PF}/v2/inferences/tasks/{tid}", headers=pf.AUTH)
        return json.loads(urllib.request.urlopen(req, timeout=60).read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return {"status": "introuvable"}
        raise


def keep(tid: str) -> None:
    req = urllib.request.Request(f"{pf.PF}/v2/inferences/tasks/{tid}", data=b'{"keep": true}', method="PATCH",
                                 headers={**pf.AUTH, "Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=60)


AJUSTE = None                         # crochet du watcher : demande -> demande (refus à refaire, GDD §14.2)


PRIORITE = "night"            # Julien 24/10 : tout part en file de nuit chez pixelforge (01:00–08:00 Paris), jamais autrement


def depose(r: dict, montre: bool) -> dict:
    if AJUSTE:
        r = AJUSTE(r)
    r = {**r, "priority": PRIORITE}
    if r.get("then"):
        r["then"] = [{**t, "priority": PRIORITE} for t in r["then"]]
    if montre:
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return {"task_id": "(montre)"}
    rep = pf._post_json(pf.PF + "/v2/inferences", r, timeout=120)
    keep(rep["task_id"])
    return rep


def fichiers(tid: str) -> list:
    return ((get(tid).get("result") or {}).get("pixelforge") or {}).get("files", [])


def telecharge(f: dict, cible: str) -> None:
    u = urllib.parse.urlparse(f["url"])        # pixelforge renvoie parfois 127.0.0.1 : on garde le chemin
    req = urllib.request.Request(pf.PF + u.path + (f"?{u.query}" if u.query else ""), headers=pf.AUTH)
    open(cible, "wb").write(urllib.request.urlopen(req, timeout=120).read())


# ------------------------------------------------------------------ étapes
def etat() -> dict:
    return json.load(open(ETAT)) if os.path.exists(ETAT) else {}


def sauve(e: dict) -> None:
    json.dump(e, open(ETAT, "w"), ensure_ascii=False, indent=1)


def cle(b, pid: str) -> str:
    return f"{b.famille}/{pid}"


def job_base(b, e: dict, pid: str, prio: str, montre: bool, graine: int = GRAINE) -> None:
    r = {"prompt_style": "pf_px__character_set", "prompt": b.prompt(pid), "seed": graine, "priority": prio,
         "tag": f"{TAG}/{b.famille}/base", "preview": True}
    rep = depose(r, montre)
    if not montre:
        e.setdefault(cle(b, pid), {})["base"] = rep["task_id"]
        e[cle(b, pid)]["expressions"] = {}
        print(pid, "base neutre", rep["task_id"])


def job_base_px(b, e: dict, pid: str, prio: str, montre: bool) -> None:
    """Profil et portrait 32 px depuis la HD de base (Julien 24/10 : la chaîne HD → pixel vient du même modèle).
    La base neutre (preview) ne livre que la HD et ne se réduit pas : un job reprend son profil, ne demande que
    l'élément portrait, puis pf_px__reduce ; sa réduction livre profile_sheet et portrait_sheet."""
    s = e.get(cle(b, pid), {})
    r = {"prompt_style": "pf_px__character_set", "prompt": b.prompt(pid), "seed": GRAINE, "priority": prio,
         "tag": f"{TAG}/{b.famille}/base_px", "profile_of": s.get("base", "<base>"), "elements": ["portrait"],
         "then": [{"prompt_style": "pf_px__reduce"}]}
    rep = depose(r, montre)
    if not montre:
        s["base_px"] = {"A": rep["task_id"], "B": (rep.get("then") or [{}])[0].get("task_id"), "socle": s["base"]}
        print(pid, "profil et portrait 32 px", rep["task_id"])


def job_expression(b, e: dict, pid: str, k: str, prio: str, montre: bool, graine: int = GRAINE) -> str:
    s = e.get(cle(b, pid), {})
    if k == NEUTRE:
        return s.get("base", "")
    if k in s.get("expressions", {}):
        return s["expressions"][k]
    if not s.get("base") and not montre:
        sys.exit(f"{pid} : pas de base neutre (iteration.py base {pid})")
    r = {"prompt_style": "pf_px__character_set", "prompt": b.prompt(pid), "seed": graine, "priority": prio,
         "tag": f"{TAG}/{b.famille}/expression", "expression": k, "expression_of": s.get("base", "<base>")}
    rep = depose(r, montre)
    if not montre:
        s.setdefault("expressions", {})[k] = rep["task_id"]
        print(pid, "expression", k, rep["task_id"])
    return rep["task_id"]


def job_anim(b, e: dict, pid: str, el: str, prio: str, montre: bool, graine: int = GRAINE) -> None:
    k = b.expression(pid, el)
    socle = job_expression(b, e, pid, k, prio, montre)    # le profil déjà fait (et validé) sert de socle
    extras = b.extras(pid)
    r = {"prompt_style": "pf_px__character_set", "prompt": b.prompt(pid), "seed": graine, "priority": prio,
         "tag": f"{TAG}/{b.famille}/anim", "profile_of": socle, "elements": [],
         "then": [{"prompt_style": "pf_px__reduce", **({"steps": json.loads(os.environ["PF_STEPS"])}
                                                        if os.environ.get("PF_STEPS") else {})}]}
    if el in extras:
        r["extras"] = [extras[el]]
    elif el in STANDARDS or el == "idle":
        # Un job ne fait que ce qu'on demande (pixelforge, 23/10) ; profil (repris) et idle (code) toujours livrés.
        r["elements"] = [] if el == "idle" else [el]
    else:
        sys.exit(f"{pid} : élément inconnu {el}")
    r.update(b.requete_anim(pid, el))
    rep = depose(r, montre)
    if not montre:
        e[cle(b, pid)].setdefault("animations", {})[el] = {
            "A": rep["task_id"], "B": (rep.get("then") or [{}])[0].get("task_id"), "expression": k,
            "socle": socle}
        print(pid, el, f"({k})", rep["task_id"])


# ------------------------------------------------------------------ intégration
CONNUS = set(STANDARDS) | {"idle", "idle_long", "cast_chasse", "cast_chasseur", "profile", "portrait", "marcher",
                           "sursaut", "a_terre", "relever", "parler", "telephone", "danser", "musique", "journal",
                           "boire", "assis", "attendre", "promener", "jouer"}
PREFIXES = ("hdfull_", "hdmatte_", "hd_", "src64_", "step_")


def element_de(nom: str) -> str:
    """Élément d'un fichier livré (run_00.png, hd_run_03.png, step_run__4_pixel_brut__8f.png…), sinon ""."""
    n = nom
    for p in PREFIXES:
        if n.startswith(p):
            n = n[len(p):]
            break
    best = ""
    for el in CONNUS:
        if (n == el or n.startswith(el + "_") or n.startswith(el + ".")) and len(el) > len(best):
            best = el
    return best


def rapatrie(tid: str, dossier: str, el: str, anims: bool) -> int:
    os.makedirs(dossier, exist_ok=True)
    n = 0
    r = get(tid)
    for f in (r.get("result") or {}).get("pixelforge", {}).get("files", []):
        cible = os.path.join(dossier, f["name"])
        # set.json (canevas, ligne des pieds) : pris une fois, au premier élément rapatrié.
        if element_de(f["name"]) == el or (f["name"] == "set.json" and not os.path.exists(cible)):
            telecharge(f, cible)
            n += 1
    if anims:
        chemin = os.path.join(dossier, "animations.json")
        a = json.load(open(chemin)) if os.path.exists(chemin) else {}
        src = (r.get("result") or {}).get("pixelforge", {}).get("animations") or {}
        if el in src:
            a[el] = {x: y for x, y in src[el].items() if x != "frames"}
            json.dump(a, open(chemin, "w"), ensure_ascii=False, indent=1)
    return n


def integre(b, e: dict, pid: str) -> None:
    s = e.get(cle(b, pid), {})
    base = os.path.join(ROOT, "assets", "blackout", b.famille, pid)
    hd = os.path.join(base, "hd")
    os.makedirs(hd, exist_ok=True)
    # Profil et portrait HD : neutre (profile_hd.png, portrait_hd.png), puis un par expression (_<clé>).
    # hd/retouches.json : fichiers retouchés à la main (Julien 24/10), jamais écrasés par une intégration.
    fr = os.path.join(hd, "retouches.json")
    gardes = set(json.load(open(fr))) if os.path.exists(fr) else set()
    for k, tid in [(NEUTRE, s.get("base"))] + sorted(s.get("expressions", {}).items()):
        if not tid or get(tid).get("status") != "succeeded":
            continue
        for f in fichiers(tid):
            if f["name"] in ("profile_hd.png", "portrait_hd.png"):
                nom = f["name"] if k == NEUTRE else f["name"].replace("_hd.png", f"_{k}_hd.png")
                if nom not in gardes:
                    telecharge(f, os.path.join(hd, nom))
    faits = s.setdefault("integre", {})
    bp = s.get("base_px") or {}
    if bp.get("B") and faits.get("base_px") != bp["B"] and get(bp["B"]).get("status") == "succeeded":
        px = os.path.join(base, "px32")
        n = 0
        for f in fichiers(bp["B"]):
            if element_de(f["name"]) in ("profile", "portrait") and not f["name"].startswith(("step_", "src64_")):
                dest = os.path.join(hd if f["name"] == "portrait_hd.png" else px, f["name"])
                if os.path.basename(dest) not in gardes:
                    telecharge(f, dest)
                    n += 1
        chemin = os.path.join(px, "animations.json")
        an = json.load(open(chemin)) if os.path.exists(chemin) else {}
        src = (get(bp["B"]).get("result") or {}).get("pixelforge", {}).get("animations") or {}
        for el in ("profile", "portrait"):
            if el in src:
                an[el] = {x: y for x, y in src[el].items() if x != "frames"}
        json.dump(an, open(chemin, "w"), ensure_ascii=False, indent=1)
        faits["base_px"] = bp["B"]
        print(pid, "profil et portrait 32 px intégrés depuis la base :", n, "fichiers")
    for nom, a in s.get("animations", {}).items():
        if faits.get(nom) == a["A"]:
            continue
        sa, sb = get(a["A"])["status"], get(a["B"])["status"] if a.get("B") else "?"
        if sa != "succeeded" or sb != "succeeded":
            print(pid, nom, ": pas prêt (A", sa, ", B", sb, ")")
            continue
        el = nom
        px = os.path.join(base, "px32")
        if not faits.get("_set"):              # 1re animation de la nouvelle chaîne : son set.json remplace l'ancien
            if os.path.exists(os.path.join(px, "set.json")):
                os.remove(os.path.join(px, "set.json"))
            faits["_set"] = a["B"]
        n = rapatrie(a["A"], hd, el, False) + rapatrie(a["B"], px, el, True)
        faits[nom] = a["A"]
        print(pid, nom, f"({a['expression']}) intégré : {n} fichiers")


def main() -> None:
    args = sys.argv[1:]
    opt = lambda o, d: args[args.index(o) + 1] if o in args else d  # noqa: E731
    prio, fam = opt("--prio", "normal"), opt("--famille", "persos")
    montre = "--montre" in args
    libres = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] not in
                                                                             ("--prio", "--famille"))]
    if not libres:
        sys.exit(__doc__)
    cmd, reste = libres[0], libres[1:]
    b = Persos() if fam == "persos" else Pnj()
    e = etat()
    if cmd == "base":
        for pid in reste:
            job_base(b, e, pid, prio, montre)
    elif cmd == "expression":
        pid, cles = reste[0], reste[1:] or None
        for k in cles or [b.base(pid)]:
            job_expression(b, e, pid, k, prio, montre)
    elif cmd == "anime":
        pid = reste[0]
        for el in reste[1:]:
            job_anim(b, e, pid, el, prio, montre)
    elif cmd == "etat":
        for c, s in e.items():
            if reste and c.split("/")[1] not in reste:
                continue
            print(c, "base", s.get("base"), get(s["base"])["status"] if s.get("base") else "")
            for k, t in s.get("expressions", {}).items():
                print("  expression", k, t, get(t)["status"])
            for n, a in s.get("animations", {}).items():
                print("  anim", n, f"({a['expression']})", a["A"], get(a["A"])["status"])
        return
    elif cmd == "integre":
        for pid in reste:
            integre(b, e, pid)
    else:
        sys.exit(__doc__)
    if not montre:
        sauve(e)


if __name__ == "__main__":
    main()
