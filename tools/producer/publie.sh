#!/usr/bin/env bash
# Prépare /producer EN LOCAL (pages statiques + aperçus, ~1 min) puis le pousse pour publication
# (Julien 2026-10-20 : « préparer les pages statiques sur /producer en local puis pousser le tout pour
# publication / rsync »). Le build va sur la branche orpheline `producer-build`, en UN SEUL commit
# remplacé à chaque fois (push forcé) : main ne grossit pas, le dépôt garde une seule copie des
# aperçus. Le workflow producer.yml (lancé à la fin) ne fait plus que copier (rsync).
# Avantage du local : les candidats de tools/rd/out (non versionnés) sont aussi publiés.
# Usage : tools/producer/publie.sh            (depuis la racine du dépôt, après le push de main)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PY="${PY:-$ROOT/.venv/bin/python}"
BRANCHE=producer-build
TMP="$(mktemp -d)"
trap 'git -C "$ROOT" worktree remove --force "$TMP/wt" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

# (reboot 21/10 : plus de candidats flat cartoon publiés)
"$ROOT/tools/producer/build.sh" "$TMP/producer" "$PY"
rm -f "$TMP/producer/config.php"          # jamais de config (hachages) dans le dépôt
rm -rf "$TMP/producer/data"

git -C "$ROOT" branch -D "$BRANCHE" >/dev/null 2>&1 || true   # copie locale de l'envoi précédent
git -C "$ROOT" worktree add --detach "$TMP/wt" >/dev/null
cd "$TMP/wt"
git checkout -q --orphan "$BRANCHE"
git rm -rq --cached . >/dev/null
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$TMP/producer/." .
printf '%s\n' "$(git -C "$ROOT" rev-parse HEAD)" > SOURCE_COMMIT
git add -A
git commit -q -m "Producer construit en local depuis main $(git -C "$ROOT" rev-parse --short HEAD)"
git push -q -f origin "HEAD:$BRANCHE"
# La branche orpheline n'a pas de workflow : on lance celui de main, qui copie producer-build.
gh workflow run producer.yml --ref main -R "$(git -C "$ROOT" remote get-url origin)"
echo "producer poussé sur $BRANCHE ($(du -sh . | cut -f1)) : publication lancée (producer.yml)"
