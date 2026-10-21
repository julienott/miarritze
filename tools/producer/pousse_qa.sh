#!/usr/bin/env bash
# Mise en ligne puis passage en QA des cartes données (règle de Julien : carte retraitée → en ligne → QA).
# Usage : pousse_qa.sh "<message>" <carte> [<carte>…]
cd /Users/julien/Dev/miarritze
# Une seule mise en ligne à la fois (wip.py et Claude peuvent pousser en même temps).
VERROU=tools/rd/out/recette/.pousse_qa.lock
for i in $(seq 1 180); do mkdir "$VERROU" 2>/dev/null && break; sleep 10; done
trap 'rmdir "$VERROU" 2>/dev/null' EXIT
MSG="$1"; shift
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . --script res://tests/run_tests.gd 2>&1 | tail -1 | grep -q " 0 échecs" || { echo "TESTS EN ÉCHEC"; exit 1; }
git add $(git ls-files --others --exclude-standard assets) assets tools/gordeka/masques tools/gordeka/taches_*.json tools/gordeka/retouches_recette.json 2>/dev/null
git commit -q -m "Gordeka : $MSG

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01LXFHAN75rdxEcdsy5wKHqu" -- assets tools/gordeka/masques tools/gordeka/taches_*.json tools/gordeka/retouches_recette.json 2>/dev/null
git push -q origin main || { echo "PUSH ÉCHOUÉ"; exit 1; }
gh workflow run deploy.yml --ref main; sleep 8
id=$(gh run list --workflow deploy.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$id" --exit-status >/dev/null 2>&1; r=$(gh run view "$id" --json conclusion -q .conclusion)
[ "$r" = success ] || { echo "DÉPLOIEMENT $r"; exit 1; }
# /producer reconstruit en local : sinon les cartes montrent les anciennes illustrations
tools/producer/publie.sh >/dev/null 2>&1; sleep 8
pid=$(gh run list --workflow producer.yml --limit 1 --json databaseId -q ".[0].databaseId"); gh run watch "$pid" --exit-status >/dev/null 2>&1
for c in "$@"; do .venv/bin/python tools/producer/cli.py qa "$c" "En ligne : nouvelle version à tester (recharger sans le cache si besoin)." >/dev/null && echo -n "$c "; done; echo "→ QA"
