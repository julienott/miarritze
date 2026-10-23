#!/usr/bin/env python3
"""Cartes chapeau de recette créées toutes seules pour chaque set pixelforge publié (Julien 23/10 : « ça doit
être automatique l'ajout de cartes sans ton intervention, pour tout ce qui est poussé en prod »).

Lancé à la fin de tools/producer/publie.sh. Pour chaque set réel (pas placeholder) de
assets/blackout/{persos,fantome,pnj,animaux,boss}/<id>/px32/ :
- pas encore de carte → carte type « perso » créée en QA (asset blackout/<famille>/<id>/animations) ;
- carte existante et set changé depuis le dernier passage → commentaire « nouvelle version » (éléments
  changés) et retour en QA ;
- sinon rien. L'empreinte de chaque set est notée dans cartes_auto_etat.json (versionné).

  cartes_auto.py [--essai]     --essai : affiche ce qui serait fait, sans rien envoyer
"""
import hashlib
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import cli  # noqa: E402

ETAT = HERE / "cartes_auto_etat.json"
FAMILLES = {"persos": "Perso", "fantome": "Fantôme", "pnj": "PNJ", "animaux": "Animal", "boss": "Boss"}
JALONS = {"persos": 2, "fantome": 2, "boss": 3}          # Persos v2, Boss (roadmap)
NOMS = {"maia": "Maïa", "fantome": "commun", "intxixu_1": "Intxixu 1", "intxixu_2": "Intxixu 2",
        "intxixu_3": "Intxixu 3"}


def empreintes(px32: Path) -> dict:
    """Empreinte par élément (planche), pour dire ce qui a changé."""
    return {p.name[:-len("_sheet.png")]: hashlib.sha1(p.read_bytes()).hexdigest()[:12]
            for p in sorted(px32.glob("*_sheet.png"))}


def main() -> None:
    essai = "--essai" in sys.argv
    etat = json.loads(ETAT.read_text()) if ETAT.exists() else {}
    for fam, libelle in FAMILLES.items():
        for px32 in sorted((ROOT / "assets" / "blackout" / fam).glob("*/px32")):
            sj = px32 / "set.json"
            if not sj.exists() or json.loads(sj.read_text()).get("placeholder"):
                continue
            pid = px32.parent.name
            asset = f"blackout/{fam}/{pid}/animations"
            emp = empreintes(px32)
            avant = etat.get(asset, {})
            if avant.get("empreintes") == emp:
                continue
            cartes = [c for c in cli.call("cards", query={"asset": asset})["cards"] if c["type"] == "perso"]
            if not cartes:
                titre = f"{libelle} : {NOMS.get(pid, pid.replace('_', ' ').title())}"
                print("nouvelle carte :", titre)
                if not essai:
                    body = {"type": "perso", "title": titre, "asset": asset, "status": "qa",
                            "description": f"Recette du set pixelforge ({len(emp)} éléments) : toutes les animations "
                                           "sont dans cette carte. Commenter élément par élément ; ✗ Refuser pour "
                                           "renvoyer en file (seuls les éléments commentés repartent, GDD §14.1)."}
                    if fam in JALONS:
                        body["milestone"] = JALONS[fam]
                    cid = cli.call("card", body=body)["id"]
                    etat[asset] = {"carte": cid, "empreintes": emp}
            else:
                c = cartes[0]
                change = sorted(k for k in emp if avant.get("empreintes", {}).get(k) != emp[k])
                print(f"carte #{c['id']} : nouvelle version ({', '.join(change)})")
                if not essai:
                    cli.call("card_comment", body={"id": c["id"], "body": "Nouvelle version publiée : "
                                                   + ", ".join(change) + "."})
                    if c["status"] != "qa":
                        cli.call("card_move", body={"id": c["id"], "status": "qa"})
                    etat[asset] = {"carte": c["id"], "empreintes": emp}
    if not essai:
        ETAT.write_text(json.dumps(etat, ensure_ascii=False, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
