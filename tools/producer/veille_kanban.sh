#!/usr/bin/env bash
# Veille du kanban /producer toutes les 5 min (Julien 2026-10-20) : affiche une ligne par événement
# fait par Julien (carte passée en Todo, commentaire, nouvelle carte…), pour que Claude réagisse.
# Les événements de Claude lui-même sont ignorés. Usage : tools/producer/veille_kanban.sh [--since EPOCH]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLI="$ROOT/.venv/bin/python $ROOT/tools/producer/cli.py"
SINCE="${2:-$(date +%s)}"
while true; do
  OUT="$($CLI events --since "$SINCE" 2>&1)" || { echo "veille : erreur producer : ${OUT:0:200}"; sleep 300; continue; }
  NEXT="$(printf '%s\n' "$OUT" | sed -n 's/.*repasser --since \([0-9]*\).*/\1/p' | head -1)"
  printf "%s\n" "$OUT" | grep -v "repasser --since" | grep -v " claude #" | grep -v "Rien de neuf" | grep -v "^$" | sed "s/^/KANBAN /"
  [ -n "$NEXT" ] && SINCE="$NEXT"
  sleep 300
done
