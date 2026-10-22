#!/usr/bin/env bash
# Captures des écrans de menu de Blackout pour /producer (section Jeu → Écrans, fiche de chaque écran) :
# docs/captures/ecrans/<id>.png, réduites à 640 px de large. Relancer après un changement de menu,
# puis reconstruire /producer (build.sh). Godot doit avoir importé le projet (godot --headless --import).
# Usage : tools/producer/captures_ecrans.sh [id…]     (défaut : tous les écrans de BkNav.ECRANS)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/docs/captures/ecrans"
mkdir -p "$OUT"
IDS=("$@")
if [ ${#IDS[@]} -eq 0 ]; then
  IDS=($(sed -n 's/^\t"\([a-z_]*\)": "res:.*tscn",$/\1/p' "$ROOT/src/blackout/menus/bk_nav.gd"))
fi
for id in "${IDS[@]}"; do
  delay=4
  [ "$id" = game ] && delay=8          # la partie : après le tirage, pendant la cachette
  godot --path "$ROOT" --resolution 1280x720 -- --scene="bk_$id" --shot="$OUT/$id.png" --delay=$delay >/dev/null 2>&1 || true
  if [ -f "$OUT/$id.png" ]; then
    sips -Z 640 "$OUT/$id.png" >/dev/null 2>&1 || true
    echo "capture : $id"
  else
    echo "capture impossible : $id"
  fi
done
