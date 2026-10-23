#!/usr/bin/env bash
# Retouches de la recette du 23/10 (Julien) : pour chaque perso, redo des éléments revus, clips du GDD §8.1/§4.5/§4.6.
# À lancer seulement quand pixelforge a déployé ses corrections (portrait, cadence de run, LiftAir_RM).
#   tools/blackout/retouche_recette_23_10.sh --montre|--depose
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:---montre}"
for pid in $("$ROOT/.venv/bin/python" -c "import json;print(' '.join(k for k in json.load(open('$ROOT/data/blackout/style_party_hard.json'))['casts'] if k!='_doc'))"); do
  read -r cc ccr < <("$ROOT/.venv/bin/python" -c "import json;c=json.load(open('$ROOT/data/blackout/style_party_hard.json'))['casts']['$pid'];print(c['cast_chasse']['clip'],c['cast_chasseur']['clip'])")
  "$ROOT/.venv/bin/python" "$ROOT/tools/blackout/retouche.py" "$MODE" "persos/$pid" \
    portrait run jump_hide lift victoire defaite etourdi colle aveugle tracte cast_chasse cast_chasseur \
    --clip jump_hide=NinjaJump_Start+NinjaJump_Idle+NinjaJump_Land --clip lift=LiftAir_RM \
    --clip victoire=Celebration --clip defaite=Crying --clip etourdi=Hit_Shoulder_L+Hit_Shoulder_R \
    --clip colle=Crouch_Fwd --clip aveugle=Spell_Double_Shoot --clip tracte=Slide \
    --clip "cast_chasse=$cc" --clip "cast_chasseur=$ccr" --prio normal
done
