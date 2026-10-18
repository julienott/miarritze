#!/usr/bin/env bash
# Installe Godot (éditeur headless Linux x86_64) et seulement les modèles
# d'export demandés, pour les jobs CI des versions natives (deploy.yml).
#
# Usage : tools/release/install_godot.sh <version> <modèle>...
#   ex.   tools/release/install_godot.sh 4.7.2 linux_release.x86_64 linux_release.arm64
#
# Résultat : ~/godot-bin/godot et ~/.local/share/godot/export_templates/<version>.stable/
# (dossiers mis en cache par actions/cache). Le .tpz complet fait ~1 Go : on
# n'en extrait que les modèles utiles.
set -euo pipefail

VERSION=$1
shift
URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p ~/godot-bin
curl -fsSL -o "$TMP/godot.zip" "$URL/Godot_v${VERSION}-stable_linux.x86_64.zip"
unzip -q "$TMP/godot.zip" -d "$TMP"
mv "$TMP/Godot_v${VERSION}-stable_linux.x86_64" ~/godot-bin/godot
chmod +x ~/godot-bin/godot

TPL_DIR="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
mkdir -p "$TPL_DIR"
curl -fsSL -o "$TMP/templates.tpz" "$URL/Godot_v${VERSION}-stable_export_templates.tpz"
PATTERNS=("templates/version.txt")
for tpl in "$@"; do
  PATTERNS+=("templates/$tpl")
done
unzip -q "$TMP/templates.tpz" "${PATTERNS[@]}" -d "$TMP/tpz"
mv "$TMP"/tpz/templates/* "$TPL_DIR/"
ls -la "$TPL_DIR"
