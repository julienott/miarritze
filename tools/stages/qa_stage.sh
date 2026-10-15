#!/bin/zsh
# Recette des marges d'un ou plusieurs décors : 5 formats d'écran (16:9,
# iPhone, ultra-large, 4:3, carré), perso collé au mur gauche puis au mur
# droit, puis planche à regarder.
# Usage : tools/stages/qa_stage.sh [décor …]   (sans argument : les 10)
set -e
cd "$(dirname "$0")/../.."
OUT=$PWD/tests/out/qa_stage
mkdir -p $OUT
STAGES=(${@:-grande_plage cote_basques port_pecheurs rocher_vierge port_vieux halles fronton stade aquarium phare_sommet})
for st in $STAGES; do
  for res in 1152x648 1688x780 1512x648 1024x768 1000x1000; do
    /opt/homebrew/bin/godot --fixed-fps 60 --resolution $res --path . -- --shot=$OUT/${st}_${res}.png \
      --autofight=louis,hondar,$st,1,0 --inputs="L*260,_*10,R*700" --frames=250,960 --timeout=200 >/dev/null 2>&1
  done
done
.venv/bin/python - $OUT $STAGES <<'EOF'
import sys
from PIL import Image
out, stages = sys.argv[1], sys.argv[2:]
for half, fr in (('gauche', '00250'), ('droite', '00960')):
    W = Image.new('RGB', (1700, 210 * len(stages)), (24, 16, 28))
    for i, st in enumerate(stages):
        x = 0
        for res in ('1152x648', '1688x780', '1512x648', '1024x768', '1000x1000'):
            im = Image.open(f'{out}/{st}_{res}_{fr}.png').convert('RGB')
            im = im.resize((im.width * 200 // im.height, 200))
            W.paste(im, (x, i * 210)); x += im.width + 8
    W.save(f'{out}/_planche_{half}.png')
    print(f'{out}/_planche_{half}.png')
EOF
