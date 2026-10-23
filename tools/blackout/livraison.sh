#!/usr/bin/env bash
# Livraison des rendus pixelforge en une commande, sans intervention (Julien 23/10) :
# intègre tels quels les sets terminés (persos, fantôme, PNJ, boss), réimporte, teste, committe, pousse,
# publie producer (qui crée ou remet en QA les cartes chapeau de recette : cartes_auto.py).
# Ne met RIEN en file chez pixelforge. Sortie courte : une ligne par set intégré, puis le bilan.
#   tools/blackout/livraison.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PY="$ROOT/.venv/bin/python"
cd "$ROOT/tools/blackout"
for f in "taches_persos_v3.json persos" "taches_fantome.json fantome" "taches_pnj.json pnj" "taches_boss_essai.json boss"; do
  set -- $f
  TACHES_PERSOS=$1 DEST=$2 "$PY" integre_persos_v2.py | grep -v "en cours chez pixelforge"
done
"$PY" retouche.py --integre
cd "$ROOT"
if [ -n "$(git status --porcelain assets/blackout)" ]; then
  godot --headless --path . --import >/dev/null 2>&1
  if ! godot --headless --path . --fixed-fps 60 --script res://tests/bk_tests.gd 2>&1 | tail -3 | grep " 0 échecs" >/dev/null; then
    echo "TESTS EN ÉCHEC : rien n'est committé ni publié"; exit 1
  fi
  git add assets/blackout
  git commit -q -m "Livraison pixelforge intégrée telle quelle ($(date +%d/%m\ %H:%M))

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LXFHAN75rdxEcdsy5wKHqu" -- assets/blackout && git push -q
  tools/producer/publie.sh 2>&1 | grep -v "Updating files" | tail -30
  # Le jeu aussi, à la racine du site : tout élément livré est jouable, même en QA (Julien 23/10).
  gh workflow run deploy.yml --ref main && echo "jeu : déploiement lancé (deploy.yml)"
else
  echo "Rien de nouveau chez pixelforge."
fi
