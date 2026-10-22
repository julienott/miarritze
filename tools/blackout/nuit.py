#!/usr/bin/env python3
"""Production de nuit de Gordeka chez pixelforge (consigne de Julien, 2026-10-20) :
- un seul perso à la fois (toutes ses animations), intégré dans le jeu sans recette ;
- au plus 10 jobs de décor en file en même temps, intégrés dans le jeu dès réception, sans recette ;
- chaque asset intégré est commité en local, SANS push (Julien poussera demain matin).

  nuit.py [--sans-decor] [--persos louis,txomin,…]

Le décor ne démarre que si le fichier tools/gordeka/.decor_go existe (créé quand pixelforge a confirmé
que pf_2d__prop est corrigé) ; il est relu à chaque tour, on peut donc l'ouvrir en cours de nuit.
Journal : tools/rd/out/nuit.log ; état : tools/rd/out/nuit_etat.json.
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "pf"))
sys.path.insert(0, HERE)
import gen_anims_pf as pf  # noqa: E402
import extras_pf as ex  # noqa: E402
import anime_perso as ap  # noqa: E402
import envoie_decor as ed  # noqa: E402

PY = os.path.join(ROOT, ".venv", "bin", "python")
OUT = os.path.join(ROOT, "tools", "rd", "out")
LOG = os.path.join(OUT, "nuit.log")
ETAT = os.path.join(OUT, "nuit_etat.json")
DECOR_GO = os.path.join(HERE, ".decor_go")
MAX_DECOR = 10
FINI = ("succeeded", "failed", "canceled", "expired")
PERSOS = ["louis", "txomin", "patxi", "maia", "xabi", "mattin", "amaia", "kaio", "karramarro", "ramuntxo",
          "itsaso", "peio"]
# Profil fantôme déjà fait (Patxi, 2026-10-20).
FANTOME_TACHE = {"patxi": "5dd49f252886444b81fa012b16d535c1"}
# Version HD (1024 px) du profil validé, pour la retouche « ailes » : depuis le petit sprite, Qwen ne voit
# plus les détails et redessine un perso générique (Mattin sans barbe, pixelforge 2026-10-20).
PROFIL_HD = {
    "mattin": "mattin/gk2d/pieds/image_00_raw.png",
    "amaia": "amaia/gk2d/profil/image_00_white.png",
    "kaio": "kaio/gk2d/foulard/image_00_raw.png",
    "karramarro": "karramarro/gk2d/foulard_pointe/image_00_raw.png",
    "ramuntxo": "ramuntxo/gk2d/retouche/image_00_raw.png",
    "itsaso": "itsaso/gk2d/profil/image_00_white.png",
    "peio": "peio/gk2d/profil_ballon/image_00_white.png",
}
FANTOME_LOUIS =os.path.join(OUT, "louis", "gk2d", "v4", "ailes_image_00_white.png")
MODELE_LOUIS = os.path.join(OUT, "louis", "gk2d", "v4", "image_02_white.png")


def log(*a):
    ligne = time.strftime("%H:%M:%S ") + " ".join(str(x) for x in a)
    print(ligne, flush=True)
    open(LOG, "a").write(ligne + "\n")


def tache(tid):
    try:
        return json.loads(urllib.request.urlopen(f"{pf.PF}/v2/inferences/tasks/{tid}", timeout=60).read())
    except urllib.error.HTTPError as e:
        if e.code == 404:   # tâche purgée ou perdue chez pixelforge : traitée comme expirée (relance)
            return {"status": "expired", "error": "404 : tâche inconnue de pixelforge"}
        raise


def deposer(payload):
    while True:
        try:
            return pf._post_json(pf.PF + "/v2/inferences", payload, timeout=300)["task_id"]
        except Exception as e:  # file pleine, redémarrage : on réessaie
            log("dépôt refusé, nouvel essai dans 60 s :", str(e)[:200])
            time.sleep(60)


def commit(chemins, message):
    chemins = chemins + [c + ".import" for c in chemins if c.endswith(".png")]   # métadonnées d'import Godot
    chemins = [c for c in chemins if os.path.exists(os.path.join(ROOT, c))]
    if not chemins:
        return
    subprocess.run(["git", "add", "--"] + chemins, cwd=ROOT, check=False)
    # `-- chemins` : ne commite que nos fichiers, même si un autre agent a des fichiers indexés.
    for _ in range(5):
        p = subprocess.run(["git", "commit", "-q", "-m", message + "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n"
                            "Claude-Session: https://claude.ai/code/session_01LXFHAN75rdxEcdsy5wKHqu", "--"] + chemins,
                           cwd=ROOT, capture_output=True, text=True)
        if "index.lock" not in p.stderr:
            return
        time.sleep(3)


def sur_blanc(src, dst):
    im = Image.open(src).convert("RGBA")
    bg = Image.new("RGBA", im.size, "white")
    bg.alpha_composite(im)
    bg.convert("RGB").save(dst)
    return dst


# ------------------------------------------------------------------ persos

class Perso:
    """Un perso : profil fantôme si besoin, puis ses animations, importées une à une."""

    def __init__(self, pid):
        self.pid = pid
        self.dir = os.path.join(OUT, pid, "gk2d")
        os.makedirs(self.dir, exist_ok=True)
        self.taches_p = os.path.join(HERE, f"taches_{pid}.json")
        self.etape = "fantome"
        self.fantome_tid = FANTOME_TACHE.get(pid)
        self.faits_p = os.path.join(self.dir, "_faits_nuit.json")
        self.faits = set(json.load(open(self.faits_p))) if os.path.exists(self.faits_p) else set()
        self.relances = {}

    def modele(self):
        if self.pid == "louis":
            return MODELE_LOUIS
        return sur_blanc(os.path.join(ROOT, "assets", "gordeka", "persos", self.pid, "modele.png"),
                         os.path.join(self.dir, "modele_blanc.png"))

    def fantome_png(self):
        return FANTOME_LOUIS if self.pid == "louis" else os.path.join(self.dir, "fantome", "image_00_white.png")

    def tour(self):
        """Avance d'un pas ; rend True quand le perso est fini."""
        if self.etape == "fantome":
            if os.path.exists(self.fantome_png()):
                self.etape = "depot"
            elif self.fantome_tid is None:
                # Vraie retouche du profil validé (params.edit, pixelforge 2026-10-20) : le prompt ne dit que
                # ce qui change ; l'ancien mode « the same character… » inventait une casquette.
                self.fantome_tid = deposer({
                    "prompt_style": "pf_2d__character",
                    "input_image": ex.b64(Image.open(os.path.join(OUT, PROFIL_HD[self.pid]) if self.pid in PROFIL_HD
                                                     else self.modele()).convert("RGB")),
                    "prompt": "add small white feathered angel wings on the back", "edit": True,
                    "num_images": 1, "seed": 7, "priority": "normal", "tag": f"miarritze/gk2d_{self.pid}"})
                log(self.pid, "profil fantôme déposé", self.fantome_tid)
                return False
            else:
                r = tache(self.fantome_tid)
                if r["status"] not in FINI:
                    return False
                if r["status"] != "succeeded":
                    log(self.pid, "profil fantôme", r["status"], str(r.get("error", ""))[:200], "→ relance")
                    self.fantome_tid = None
                    return False
                d = os.path.join(self.dir, "fantome")
                os.makedirs(d, exist_ok=True)
                for f in r["result"]["pixelforge"]["files"]:
                    open(os.path.join(d, f["name"]), "wb").write(urllib.request.urlopen(f["url"], timeout=120).read())
                json.dump({"style": "pf_2d__character", "task": self.fantome_tid, "seed": 7,
                           "prompt": r.get("request", {}).get("prompt", "")},
                          open(os.path.join(d, "params.json"), "w"), ensure_ascii=False, indent=1)
                if not os.path.exists(self.fantome_png()):
                    sur_blanc(os.path.join(d, "image_00.png"), self.fantome_png())
                log(self.pid, "profil fantôme reçu")
                self.etape = "depot"
        if self.etape == "depot":
            ap.depose(self.pid, self.modele(), self.fantome_png(), [])
            log(self.pid, "animations déposées")
            self.etape = "anims"
            return False
        taches = json.load(open(self.taches_p))
        reste = 0
        for anim, tid in taches.items():
            if anim in self.faits:
                continue
            r = tache(tid)
            if r["status"] not in FINI:
                reste += 1
                continue
            if r["status"] != "succeeded":
                n = self.relances.get(anim, 0)
                log(self.pid, anim, r["status"], str(r.get("error", ""))[:200])
                if n < 2:
                    self.relances[anim] = n + 1
                    del taches[anim]
                    json.dump(taches, open(self.taches_p, "w"), indent=1)
                    ap.depose(self.pid, self.modele(), self.fantome_png(), [anim])
                    log(self.pid, anim, "relancée")
                    reste += 1
                else:
                    self.faits.add(anim)
                continue
            self.importer(anim, tid)
            self.faits.add(anim)
            json.dump(sorted(self.faits), open(self.faits_p, "w"))
        return reste == 0

    def importer(self, anim, tid):
        une = os.path.join(self.dir, "_une.json")
        json.dump({anim: tid}, open(une, "w"))
        subprocess.run([PY, os.path.join(HERE, "import_perso.py"), self.pid, une], cwd=ROOT, check=False)
        base = f"assets/gordeka/persos/{self.pid}/{anim}"
        commit([base + ".png", base + "_tenue.png", base + ".json", f"tools/gordeka/taches_{self.pid}.json"],
               f"Gordeka : {self.pid}, animation {anim} (production de nuit, sans recette)")
        log(self.pid, anim, "intégrée")


# ------------------------------------------------------------------ décor

class Decor:
    """File glissante de jobs de décor (au plus MAX_DECOR en vol), intégrés à réception."""

    def __init__(self):
        self.suivi_p = ed.SUIVI
        self.integres_p = os.path.join(OUT, "decor", "_integres.json")
        os.makedirs(os.path.join(OUT, "decor"), exist_ok=True)
        self.integres = set(json.load(open(self.integres_p))) if os.path.exists(self.integres_p) else set()
        self.els = json.load(open(ed.PROMPTS))["elements"]
        self.vol = {}       # tid -> (eid, n)

    def charger_suivi(self):
        return json.load(open(self.suivi_p)) if os.path.exists(self.suivi_p) else {}

    def tour(self):
        suivi = self.charger_suivi()
        # Relève des jobs en vol (y compris ceux déposés avant la nuit).
        for eid, tids in suivi.items():
            for n, tid in enumerate(tids):
                cle = f"{eid}/{n}"
                if cle in self.integres:
                    continue
                r = tache(tid)
                if r["status"] not in FINI:
                    self.vol[tid] = (eid, n)
                    continue
                self.vol.pop(tid, None)
                self.integres.add(cle)
                json.dump(sorted(self.integres), open(self.integres_p, "w"))
                if r["status"] != "succeeded":
                    log("décor", eid, n, r["status"], str(r.get("error", ""))[:200])
                    continue
                d = os.path.join(OUT, "decor", eid, str(n))
                os.makedirs(d, exist_ok=True)
                for f in r["result"]["pixelforge"]["files"]:
                    open(os.path.join(d, f["name"]), "wb").write(urllib.request.urlopen(f["url"], timeout=120).read())
                if n == 0:    # la première taille sert dans le jeu ; les autres restent pour la recette
                    p = subprocess.run([PY, os.path.join(HERE, "integre_decor.py"), eid, "0", "image_00", "--sans-capture"],
                                       cwd=ROOT, capture_output=True, text=True)
                    log("décor", eid, "intégré" if p.returncode == 0 else "intégration refusée : " + p.stdout[-200:] + p.stderr[-200:])
                    commit(["assets/gordeka/decor", "tools/gordeka/taches_decor.json"],
                           f"Gordeka : décor {eid} (pf_2d, production de nuit, sans recette)")
                else:
                    log("décor", eid, n, "reçu (taille secondaire)")
        if not os.path.exists(DECOR_GO):
            return
        # Dépôts tant qu'il y a de la place.
        for e in self.els:
            if len(self.vol) >= MAX_DECOR:
                break
            if e["id"] in suivi:
                continue
            pls = [ed.en_2d({k: v for k, v in pl.items() if k != "taille_cases"}) for pl in e.get("payloads", [])]
            pls = [pl for pl in pls if pl is not None]
            if not pls or len(self.vol) + len(pls) > MAX_DECOR:
                if not pls:
                    suivi[e["id"]] = []
                    json.dump(suivi, open(self.suivi_p, "w"), indent=1)
                continue
            suivi[e["id"]] = []
            for pl in pls:
                pl.update(priority="low", tag=f"miarritze/decor_{e['id']}")
                tid = deposer(pl)
                suivi[e["id"]].append(tid)
                self.vol[tid] = (e["id"], len(suivi[e["id"]]) - 1)
            json.dump(suivi, open(self.suivi_p, "w"), indent=1)
            log("décor", e["id"], "déposé", len(pls), "job(s)")


def main():
    persos = PERSOS
    if "--persos" in sys.argv:
        persos = sys.argv[sys.argv.index("--persos") + 1].split(",")
    decor = None if "--sans-decor" in sys.argv else Decor()
    file_persos = list(persos)
    courant = None
    log("nuit : début", file_persos)
    while True:
        try:
            if courant is None and file_persos:
                courant = Perso(file_persos.pop(0))
                if os.path.exists(courant.taches_p):
                    courant.etape = "anims"               # reprise : animations déjà déposées
                log("perso :", courant.pid)
            if courant is not None and courant.tour():
                log("perso fini :", courant.pid)
                courant = None
            if decor is not None:
                decor.tour()
            json.dump({"perso": courant.pid if courant else None, "persos_restants": file_persos,
                       "decor_en_vol": len(decor.vol) if decor else 0,
                       "decor_integres": len(decor.integres) if decor else 0},
                      open(ETAT, "w"), ensure_ascii=False, indent=1)
            if courant is None and not file_persos and (decor is None or (not decor.vol and os.path.exists(DECOR_GO)
                                                                            and all(e["id"] in decor.charger_suivi() for e in decor.els))):
                log("nuit : tout est fait")
                return
        except Exception as e:  # pixelforge injoignable, etc. : on attend et on reprend
            log("erreur :", repr(e)[:300])
            time.sleep(60)
        time.sleep(20)


if __name__ == "__main__":
    main()
