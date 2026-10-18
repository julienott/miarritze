#!/usr/bin/env bash
# Empaquette l'export Steam Deck pour le site :
#   <sortie>/MiarritzeBorroka-<version>.tar.gz  (jeu complet : binaire + .pck + icône + install.sh)
#   <sortie>/MiarritzeBorroka-<version>.pck     (mise à jour légère, lue par src/autoload/updater.gd)
#   <sortie>/manifest.json                      (version, build, url, sha256, taille, date)
#
# Usage : tools/steamdeck/package.sh <dossier_export> <dossier_sortie> <build> <version> <version_godot> [url_de_base]
#   build         : entier croissant (numéro de run CI) — c'est lui que le jeu compare
#   version_godot : version du moteur qui a exporté (ex. 4.7.2) ; si elle change,
#                   le jeu télécharge le paquet complet au lieu du seul .pck
#   url_de_base   : ex. https://miarritze.ijulien.com/steamdeck (sinon URLs relatives au manifeste)
set -euo pipefail

EXPORT_DIR=$1
OUT=$2
BUILD=$3
VERSION=$4
GODOT=$5
BASE_URL=${6:-}
NAME=MiarritzeBorroka
ROOT=$(cd "$(dirname "$0")/../.." && pwd)

test -f "$EXPORT_DIR/$NAME.x86_64"
test -f "$EXPORT_DIR/$NAME.pck"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME" "$OUT"
cp "$EXPORT_DIR/$NAME.x86_64" "$EXPORT_DIR/$NAME.pck" "$STAGE/$NAME/"
# Bibliothèques des extensions (WebRTC natif pour le jeu en ligne), posées par l'export.
for so in "$EXPORT_DIR"/*.so; do
  [ -f "$so" ] && cp "$so" "$STAGE/$NAME/"
done
ls "$STAGE/$NAME"/libwebrtc_native*.so >/dev/null
chmod +x "$STAGE/$NAME/$NAME.x86_64"
cp "$ROOT/assets/ui/app_icon.png" "$STAGE/$NAME/icon.png"
cp "$ROOT/web/steamdeck/install.sh" "$STAGE/$NAME/install.sh"
chmod +x "$STAGE/$NAME/install.sh"
echo "$VERSION" > "$STAGE/$NAME/VERSION"

TAR="$NAME-$VERSION.tar.gz"
PCK="$NAME-$VERSION.pck"
# COPYFILE_DISABLE : pas de fichiers « ._* » quand on empaquette depuis macOS.
COPYFILE_DISABLE=1 tar -czf "$OUT/$TAR" -C "$STAGE" "$NAME"
cp "$EXPORT_DIR/$NAME.pck" "$OUT/$PCK"

python3 "$ROOT/tools/release/manifest.py" "$OUT" --platform "linux-x86_64 (Steam Deck)" \
  --build "$BUILD" --version "$VERSION" --godot "$GODOT" --base-url "$BASE_URL" \
  --package "$TAR" --pck "$PCK"
