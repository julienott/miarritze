#!/usr/bin/env bash
# Assemble le service /producer dans <dossier> (ex. web/build/producer) :
# code PHP + statiques (dont la police) + aperçus/index générés depuis assets/.
# Ne touche jamais à <dossier>/data ni à <dossier>/config.php.
# Usage : tools/producer/build.sh <dossier> [python]
set -euo pipefail
OUT="${1:?usage : build.sh <dossier> [python]}"
PY="${2:-python3}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

mkdir -p "$OUT"
rm -rf "$OUT/lib" "$OUT/static"
cp "$ROOT/producer/index.php" "$ROOT/producer/.htaccess" "$OUT/"
cp -R "$ROOT/producer/lib" "$ROOT/producer/static" "$OUT/"
"$PY" "$ROOT/tools/producer/build_index.py" "$OUT/files"
printf 'Require all denied\n' > "$OUT/files/.htaccess"
test -f "$OUT/files/index.json"
