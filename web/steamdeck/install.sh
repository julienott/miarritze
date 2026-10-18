#!/usr/bin/env bash
# Miarritze Borroka — installation sur Steam Deck (ou tout Linux x86_64).
#
# - Télécharge la dernière version depuis le site (ou utilise les fichiers
#   à côté de ce script s'il est lancé depuis l'archive décompressée),
# - vérifie son empreinte sha256,
# - installe le jeu dans ~/Games/MiarritzeBorroka,
# - crée un raccourci (menu des applications + Bureau),
# - l'ajoute à Steam quand l'outil de SteamOS est disponible.
# Les sauvegardes (profils, réglages) ne sont jamais touchées : elles vivent
# dans ~/.local/share/godot/app_userdata/Miarritze Borroka/.
#
# Variables (tests) : MIARRITZE_MANIFEST=<url du manifeste>, MIARRITZE_HOME=<dossier personnel>
set -euo pipefail

NAME=MiarritzeBorroka
TITLE="Miarritze Borroka"
MANIFEST_URL=${MIARRITZE_MANIFEST:-https://miarritze.ijulien.com/steamdeck/manifest.json}
USER_HOME=${MIARRITZE_HOME:-$HOME}
INSTALL_DIR=$USER_HOME/Games/$NAME
DESKTOP_ID=miarritze-borroka.desktop
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Messages : dans le terminal, ou en fenêtre si le script a été lancé d'un double-clic.
say() {
  echo "$1"
  if [ ! -t 1 ] && command -v kdialog >/dev/null 2>&1; then
    kdialog --title "$TITLE" --msgbox "$1" >/dev/null 2>&1 || true
  fi
}
fail() {
  say "Oups ! $1"
  exit 1
}

# Lit un champ du manifeste (ex. package.url) avec python3, présent sur SteamOS.
manifest_field() {
  python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d=d[k]
print(d)' "$1" "$2"
}

if [ ! -t 1 ] && command -v kdialog >/dev/null 2>&1; then
  kdialog --title "$TITLE" --passivepopup "Installation en cours… patiente une minute." 15 >/dev/null 2>&1 &
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ -f "$HERE/$NAME.x86_64" ] && [ -f "$HERE/$NAME.pck" ]; then
  # Lancé depuis l'archive décompressée : on installe ces fichiers-là.
  SRC="$HERE"
else
  command -v curl >/dev/null 2>&1 || fail "curl est introuvable."
  command -v python3 >/dev/null 2>&1 || fail "python3 est introuvable."
  echo "Recherche de la dernière version…"
  curl -fsSL "$MANIFEST_URL" -o "$TMP/manifest.json" \
    || fail "Impossible de joindre le site. Vérifie le Wi-Fi et recommence."
  VERSION=$(manifest_field "$TMP/manifest.json" version)
  URL=$(manifest_field "$TMP/manifest.json" package.url)
  SHA=$(manifest_field "$TMP/manifest.json" package.sha256)
  case "$URL" in
    http://*|https://*) ;;
    *) URL="${MANIFEST_URL%/*}/$URL" ;;
  esac
  echo "Téléchargement de la version ${VERSION}…"
  curl -fL --progress-bar "$URL" -o "$TMP/game.tar.gz" \
    || fail "Le téléchargement a échoué. Recommence un peu plus tard."
  echo "$SHA  $TMP/game.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
    || fail "Le fichier téléchargé est abîmé. Recommence."
  tar -xzf "$TMP/game.tar.gz" -C "$TMP"
  SRC="$TMP/$NAME"
fi

echo "Installation dans ${INSTALL_DIR}…"
mkdir -p "$INSTALL_DIR"
# + bibliothèques des extensions (WebRTC natif : jeu en ligne).
for f in "$NAME.x86_64" "$NAME.pck" icon.png VERSION install.sh $(cd "$SRC" && ls *.so 2>/dev/null); do
  if [ -f "$SRC/$f" ]; then
    cp -f "$SRC/$f" "$INSTALL_DIR/$f.new"
    mv -f "$INSTALL_DIR/$f.new" "$INSTALL_DIR/$f"
  fi
done
chmod +x "$INSTALL_DIR/$NAME.x86_64"
[ -f "$INSTALL_DIR/install.sh" ] && chmod +x "$INSTALL_DIR/install.sh"

# Ensuite, le jeu se met à jour tout seul dans ce dossier (src/autoload/updater.gd).
rm -f "$INSTALL_DIR"/.update-*.part

# Raccourci : menu des applications + Bureau.
DESKTOP_FILE="$USER_HOME/.local/share/applications/$DESKTOP_ID"
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$TITLE
Comment=Jeu de combat de Biarritz
Exec="$INSTALL_DIR/$NAME.x86_64"
Path=$INSTALL_DIR
Icon=$INSTALL_DIR/icon.png
Terminal=false
Categories=Game;
EOF
chmod +x "$DESKTOP_FILE"
if [ -d "$USER_HOME/Desktop" ]; then
  cp -f "$DESKTOP_FILE" "$USER_HOME/Desktop/$DESKTOP_ID"
  chmod +x "$USER_HOME/Desktop/$DESKTOP_ID"
fi

# Ajout à Steam : SteamOS fournit steamos-add-to-steam (celui du clic droit
# « Ajouter à Steam »). Steam doit tourner (c'est le cas en mode Bureau).
ADDED=0
if command -v steamos-add-to-steam >/dev/null 2>&1; then
  if steamos-add-to-steam "$INSTALL_DIR/$NAME.x86_64" >/dev/null 2>&1; then
    ADDED=1
  fi
fi

if [ "$ADDED" = 1 ]; then
  say "C'est installé ! Miarritze Borroka est ajouté à Steam. Reviens en mode Jeu : il est dans ta Bibliothèque, onglet « Non-Steam »."
else
  say "C'est installé ! Pour l'ajouter à Steam : ouvre Steam, menu « Jeux » > « Ajouter un jeu non-Steam à ma bibliothèque », coche « $TITLE », puis reviens en mode Jeu."
fi
