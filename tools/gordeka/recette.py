#!/usr/bin/env python3
"""Production de Gordeka chez pixelforge AVEC recette (Julien, 2026-10-20 matin : « fais la recette de
tout ce qui est sorti, si ce n'est pas bon renvoie-le, sinon intègre-le », remplace nuit.py) :
- un perso à la fois (toutes ses animations), au plus 10 jobs de décor en vol ;
- chaque sortie est rapatriée en zone de recette avec sa planche, SANS être intégrée ;
- Claude regarde la planche puis tape `ok` (intégration + commit local) ou `ko` (renvoi, avec une
  consigne en plus dans le prompt) ;
- aucun push.

  recette.py boucle                       la routine (nohup) ; journal tools/rd/out/recette/journal.log
  recette.py liste                        ce qui attend la recette
  recette.py ok <clé> [variante]          ex. ok perso/maia/walk  |  ok decor/fronton/0 image_02
  recette.py ko <clé> "<consigne>"        renvoi ; la consigne s'ajoute au prompt (retouches_recette.json)
  recette.py echec <clé>                  abandon (garde l'état actuel du jeu)

Les commandes passent par une file (commandes.jsonl) lue par la boucle : pas de course sur l'état.
Clés : perso/<id>/<anim>, decor/<id>/<n>.
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
sys.path.insert(0, HERE)
import gen_anims_pf as pf  # noqa: E402
import nuit  # noqa: E402   (dépôt, commit, profil blanc : on réutilise)
import anime_perso as ap  # noqa: E402
import envoie_decor as ed  # noqa: E402
import planche_recette as pr  # noqa: E402
import masques_pf as mp  # noqa: E402

PY = nuit.PY
DIR = os.path.join(ROOT, "tools", "rd", "out", "recette")
ETAT = os.path.join(DIR, "etat.json")
CMD = os.path.join(DIR, "commandes.jsonl")
LOG = os.path.join(DIR, "journal.log")
RETOUCHES = os.path.join(HERE, "retouches_recette.json")
MAX_DECOR = 10
MAX_ESSAIS = 4
FINI = nuit.FINI


def log(*a):
    ligne = time.strftime("%H:%M:%S ") + " ".join(str(x) for x in a)
    print(ligne, flush=True)
    open(LOG, "a").write(ligne + "\n")


def lire(p, d):
    return json.load(open(p)) if os.path.exists(p) else d


def ecrire(p, v):
    tmp = p + ".tmp"
    json.dump(v, open(tmp, "w"), ensure_ascii=False, indent=1)
    os.replace(tmp, p)


def telecharge(r, d):
    os.makedirs(d, exist_ok=True)
    for f in r["result"]["pixelforge"]["files"]:
        open(os.path.join(d, f["name"]), "wb").write(urllib.request.urlopen(f["url"], timeout=120).read())


# ------------------------------------------------------------------ dépôts

def payload_perso(pid, anim):
    pl = ap.payload(pid, anim)
    pl["priority"] = "low"    # Julien 2026-10-20 : masques > décor > animations
    plus = lire(RETOUCHES, {}).get(f"perso/{pid}/{anim}")
    if isinstance(plus, dict):        # {"action": "...", "hold": {...}} : réglages du mannequin en plus
        if plus.get("action"):
            pl["action"] += " " + plus["action"]
        pl.update({k: v for k, v in plus.items() if k != "action"})
    elif plus:
        pl["action"] += " " + plus
    return pl


def depose_perso(pid, anim):
    from PIL import Image
    p = nuit.Perso(pid)
    img = Image.open(p.fantome_png() if anim in ap.FANTOMES else p.modele()).convert("RGB")
    pl = payload_perso(pid, anim)
    pl["input_image"] = nuit.ex.b64(img)
    tid = nuit.deposer(pl)
    taches = lire(p.taches_p, {})
    taches[anim] = tid
    ecrire(p.taches_p, taches)
    return tid


def payloads_decor(eid):
    els = {e["id"]: e for e in json.load(open(ed.PROMPTS))["elements"]}
    plus = lire(RETOUCHES, {})
    pls = []
    for n, pl in enumerate(els[eid].get("payloads", [])):
        pl = ed.en_2d({k: v for k, v in pl.items() if k != "taille_cases"})
        if pl is None:
            continue
        if plus.get(f"decor/{eid}/{n}"):
            pl["prompt"] = pl["prompt"].rstrip() + " " + plus[f"decor/{eid}/{n}"]
        pl.update(priority="normal", tag=f"miarritze/decor_{eid}")
        pls.append(pl)
    return pls


def depose_decor(eid, n):
    tid = nuit.deposer(payloads_decor(eid)[n])
    suivi = lire(ed.SUIVI, {})
    suivi.setdefault(eid, [])
    while len(suivi[eid]) <= n:
        suivi[eid].append(None)
    suivi[eid][n] = tid
    ecrire(ed.SUIVI, suivi)
    return tid


# ------------------------------------------------------------------ routine

class Routine:
    def __init__(self):
        os.makedirs(DIR, exist_ok=True)
        self.e = lire(ETAT, {"items": {}, "persos": [], "courant": None, "cmd_lues": 0})
        self.vide_depuis = None

    def sauve(self):
        ecrire(ETAT, self.e)

    def items(self, statut=None, sorte=None):
        return {k: v for k, v in self.e["items"].items()
                if (statut is None or v["statut"] == statut) and (sorte is None or k.startswith(sorte + "/"))}

    # --- relève
    def releve(self):
        for cle, it in self.items("en_vol").items():
            r = nuit.tache(it["tid"])
            if r["status"] not in FINI:
                continue
            if r["status"] != "succeeded":
                log(cle, r["status"], str(r.get("error", ""))[:200])
                self.relance(cle, None)
                continue
            d = os.path.join(DIR, cle.replace("/", "_") + f"_{it['essais']}")
            telecharge(r, d)
            it["dossier"] = d
            if cle.startswith("perso/"):
                pr.empile([pr.ligne_anim(os.path.join(d, "spritesheet_00.png"), os.path.join(d, "tenue_sheet_00.png"),
                                         12, cle.split("/")[2])], os.path.join(d, "planche.png"))
            else:
                pr.decor(d, os.path.join(d, "planche.png"))
            it["planche"] = os.path.join(d, "planche.png")
            it["statut"] = "a_voir"
            log("À VOIR", cle, it["planche"])

    def relance(self, cle, consigne):
        it = self.e["items"].setdefault(cle, {"essais": 0, "statut": "nouveau"})
        if consigne:
            ret = lire(RETOUCHES, {})
            ret[cle] = consigne
            ecrire(RETOUCHES, ret)
        it["essais"] += 1
        if it["essais"] > MAX_ESSAIS:
            it["statut"] = "echec"
            log("ÉCHEC", cle, f"après {MAX_ESSAIS} essais : à signaler")
            return
        sorte, a, b = cle.split("/")
        it["tid"] = depose_perso(a, b) if sorte == "perso" else depose_decor(a, int(b))
        it["statut"] = "en_vol"
        log("renvoyé" if consigne else "relancé", cle, it["tid"], consigne or "")

    # --- commandes de Claude
    def commandes(self):
        lignes = open(CMD).read().splitlines() if os.path.exists(CMD) else []
        for l in lignes[self.e["cmd_lues"]:]:
            c = json.loads(l)
            cle = c["cle"]
            try:
                if c["cmd"] == "ok":
                    self.integre(cle, c.get("variante"))
                elif c["cmd"] == "ko":
                    self.relance(cle, c.get("consigne"))
                elif c["cmd"] == "echec":
                    self.e["items"].setdefault(cle, {"essais": 0})["statut"] = "echec"
                    log("abandon", cle)
            except Exception as ex:
                log("commande", c, "refusée :", repr(ex)[:300])
            self.e["cmd_lues"] += 1
            self.sauve()

    def integre(self, cle, variante):
        it = self.e["items"][cle]
        sorte, a, b = cle.split("/")
        if sorte == "perso":
            une = os.path.join(DIR, "_une.json")
            json.dump({b: it["tid"]}, open(une, "w"))
            subprocess.run([PY, os.path.join(HERE, "import_perso.py"), a, une], cwd=ROOT, check=True)
            base = f"assets/gordeka/persos/{a}/{b}"
            nuit.commit([base + ".png", base + "_tenue.png", base + ".json", f"tools/gordeka/taches_{a}.json"],
                        f"Gordeka : {a}, animation {b} (recette OK)")
        else:
            src = os.path.join(ed.OUT, a, b)
            os.makedirs(src, exist_ok=True)
            subprocess.run(["rsync", "-a", it["dossier"] + "/", src + "/"], check=True)
            if b == "0":    # la première taille sert dans le jeu ; les autres restent pour plus tard
                p = subprocess.run([PY, os.path.join(HERE, "integre_decor.py"), a, "0", variante or "image_00",
                                    "--sans-capture"], cwd=ROOT, capture_output=True, text=True)
                if p.returncode:
                    raise RuntimeError(p.stdout[-300:] + p.stderr[-300:])
                nuit.commit(["assets/gordeka/decor", "tools/gordeka/taches_decor.json"],
                            f"Gordeka : décor {a} (pf_2d, recette OK)")
                if lire(ed.PROMPTS, {}) and json.load(open(os.path.join(ROOT, "assets/gordeka/decor/index.json")))[
                        "elements"].get(a, {}).get("type") == "objet":
                    if not os.path.exists(os.path.join(HERE, ".decor_pause")):
                        mp.depose([a])           # masques de gameplay (pf_2d__footprint) de la nouvelle image
        it["statut"] = "ok"
        log("INTÉGRÉ", cle, variante or "")

    # --- alimentation
    def alimente(self):
        # perso courant : fini quand plus rien en vol ni à voir
        pid = self.e["courant"]
        if pid and not any(k.startswith(f"perso/{pid}/") and v["statut"] in ("en_vol", "a_voir", "nouveau")
                           for k, v in self.e["items"].items()):
            log("perso fini :", pid)
            self.e["courant"] = pid = None
        if pid is None and self.e["persos"]:
            pid = self.e["courant"] = self.e["persos"].pop(0)
            p = nuit.Perso(pid)
            while p.etape == "fantome":              # profil fantôme (rare : bloquant court)
                p.tour()
                if p.etape == "fantome":
                    time.sleep(20)
            for anim in ap.pretes():
                self.relance(f"perso/{pid}/{anim}", None)
            log("perso :", pid)
        # décor : file glissante (suspendue tant que tools/gordeka/.decor_pause existe, Julien 2026-10-20)
        if os.path.exists(os.path.join(HERE, ".decor_pause")):
            return
        en_vol = len(self.items("en_vol", "decor"))
        suivi = lire(ed.SUIVI, {})
        for el in json.load(open(ed.PROMPTS))["elements"]:
            if en_vol >= MAX_DECOR:
                break
            if el["id"] in suivi:
                continue
            pls = payloads_decor(el["id"])
            if not pls:
                suivi[el["id"]] = []
                ecrire(ed.SUIVI, suivi)
                continue
            for n in range(len(pls)):
                self.relance(f"decor/{el['id']}/{n}", None)
                en_vol += 1
            suivi = lire(ed.SUIVI, {})

    def masques(self):
        """Masques pf_2d__footprint finis : rapatriés, puis À VOIR (aperçu) pour la recette."""
        avant = {k: v["statut"] for k, v in lire(mp.SUIVI, {}).items()}
        mp.releve(une_fois=True)
        for eid, s in lire(mp.SUIVI, {}).items():
            if avant.get(eid) == "en_vol" and s["statut"] != "en_vol":
                log("À VOIR masque", eid, s["statut"], os.path.join(mp.APERCUS, eid + ".png"))

    def surveille(self):
        """File bloquée : du travail en vol mais pixelforge ne fait rien depuis 10 min."""
        if not self.items("en_vol"):
            self.vide_depuis = None
            return
        q = json.loads(urllib.request.urlopen(pf.PF + "/v2/queue", timeout=30).read())
        if q["running"] or q["pending"]:
            self.vide_depuis = None
        elif self.vide_depuis is None:
            self.vide_depuis = time.time()
        elif time.time() - self.vide_depuis > 600:
            log("ALERTE file bloquée :", len(self.items("en_vol")), "jobs en vol, pixelforge inactif depuis 10 min")
            self.vide_depuis = time.time()

    def boucle(self):
        log("recette : début", self.e["courant"], self.e["persos"])
        erreurs = 0
        while True:
            try:
                self.commandes()
                self.releve()
                self.masques()
                self.alimente()
                self.surveille()
                self.sauve()
                erreurs = 0
            except Exception as ex:
                erreurs += 1
                log("erreur :", repr(ex)[:300])
                if erreurs == 10:
                    log("ALERTE erreurs répétées :", repr(ex)[:300])
                time.sleep(40)
            time.sleep(20)


def commande(cmd, cle, **kw):
    os.makedirs(DIR, exist_ok=True)
    open(CMD, "a").write(json.dumps({"cmd": cmd, "cle": cle, **kw}, ensure_ascii=False) + "\n")
    print("noté :", cmd, cle, kw or "")


if __name__ == "__main__":
    c, a = sys.argv[1], sys.argv[2:]
    if c == "boucle":
        Routine().boucle()
    elif c == "liste":
        for k, v in sorted(lire(ETAT, {"items": {}})["items"].items()):
            if v["statut"] in ("a_voir", "echec") or "-a" in a:
                print(v["statut"], k, v.get("planche", ""))
    elif c == "ok":
        commande("ok", a[0], variante=a[1] if len(a) > 1 else None)
    elif c == "ko":
        commande("ko", a[0], consigne=a[1] if len(a) > 1 else None)
    elif c == "echec":
        commande("echec", a[0])
