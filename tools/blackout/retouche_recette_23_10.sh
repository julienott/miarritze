#!/usr/bin/env bash
# Retouches de la recette du 23/10 (Julien) : pour chaque perso, redo des éléments revus, nouveaux clips par défaut de pixelforge
# (commit f471e43 : redo les reprend tout seul) ; seuls les lancements passent leurs clips (§4.6).
# À lancer seulement quand pixelforge a déployé ses corrections (portrait, cadence de run, LiftAir_RM).
#   tools/blackout/retouche_recette_23_10.sh --montre|--depose
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:---montre}"
for pid in $("$ROOT/.venv/bin/python" -c "import json;print(' '.join(k for k in json.load(open('$ROOT/data/blackout/style_party_hard.json'))['casts'] if k!='_doc'))"); do
  J="import json;c=json.load(open('$ROOT/data/blackout/style_party_hard.json'))['casts']['$pid']"
  cc=$("$ROOT/.venv/bin/python" -c "$J;print(c['cast_chasse']['clip'])")
  ccr=$("$ROOT/.venv/bin/python" -c "$J;print(c['cast_chasseur']['clip'])")
  ac=$("$ROOT/.venv/bin/python" -c "$J;print(c['cast_chasse']['action'])")
  acr=$("$ROOT/.venv/bin/python" -c "$J;print(c['cast_chasseur']['action'])")
  "$ROOT/.venv/bin/python" "$ROOT/tools/blackout/retouche.py" "$MODE" "persos/$pid" \
    portrait run jump_hide lift victoire defaite etourdi colle aveugle tracte cast_chasse cast_chasseur \
    --clip "cast_chasse=$cc" --clip "cast_chasseur=$ccr" \
    --action "cast_chasse=$ac" --action "cast_chasseur=$acr" --prio normal
done
