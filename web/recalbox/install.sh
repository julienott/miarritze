#!/bin/bash
# Miarritze Borroka — installation sur Recalbox (Raspberry Pi 4/5 ou PC), par SSH.
#
#   ssh root@recalbox          (mot de passe par défaut : recalboxroot)
#   curl -fsSL https://miarritze.ijulien.com/recalbox/install.sh | bash
#
# - télécharge le paquet de la machine (arm64 ou x86_64), vérifie son sha256,
# - installe le jeu dans share/roms/ports/miarritze (gamelist.xml existant gardé),
# - déclare le système « miarritze » dans share/system/.emulationstation/systemlist.xml
#   (ajouté au fichier s'il existe déjà),
# - redémarre EmulationStation : le jeu apparaît dans « Ports ».
# Ensuite le jeu se met à jour tout seul au lancement (src/autoload/updater.gd).
# Les sauvegardes (share/saves/ports/miarritze) ne sont jamais touchées.
#
# Variables (tests) : MIARRITZE_MANIFEST=<url>, MIARRITZE_SHARE=<dossier share>,
# MIARRITZE_NO_RESTART=1 (ne pas redémarrer EmulationStation).
set -euo pipefail

MANIFEST_URL=${MIARRITZE_MANIFEST:-https://miarritze.ijulien.com/recalbox/manifest.json}
SHARE=${MIARRITZE_SHARE:-/recalbox/share}
GAME=$SHARE/roms/ports/miarritze
SYSTEMLIST=$SHARE/system/.emulationstation/systemlist.xml
SYSTEM_UUID=3aad7373-5176-4fcb-942e-6584ba8b44c4

fail() {
  echo "Oups ! $1" >&2
  exit 1
}

case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  x86_64|amd64) ARCH=x86_64 ;;
  *) fail "cette machine ($(uname -m)) n'est pas prise en charge : il faut un Raspberry Pi 4 ou 5 (Recalbox 64 bits) ou un PC." ;;
esac
[ -d "$SHARE" ] || fail "dossier $SHARE introuvable : est-ce bien une Recalbox ?"
PY=$(command -v python3 || command -v python) || fail "python est introuvable."

download() { # download <url> <fichier>
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar "$1" -o "$2"
  else
    wget -q -O "$2" "$1"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Recherche de la dernière version…"
download "$MANIFEST_URL" "$TMP/manifest.json" 2>/dev/null \
  || fail "impossible de joindre le site. Vérifie la connexion de la Recalbox et recommence."
read -r VERSION URL SHA < <("$PY" - "$TMP/manifest.json" "$ARCH" "$MANIFEST_URL" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
p = m["packages"][sys.argv[2]]
url = p["url"]
if not url.startswith(("http://", "https://")):
    url = sys.argv[3].rsplit("/", 1)[0] + "/" + url
print(m["version"], url, p["sha256"])
EOF
) || fail "le manifeste du site est illisible."

echo "Téléchargement de la version $VERSION ($ARCH)…"
download "$URL" "$TMP/jeu.zip" || fail "le téléchargement a échoué. Recommence un peu plus tard."
echo "$SHA  $TMP/jeu.zip" | sha256sum -c - >/dev/null 2>&1 || fail "le fichier téléchargé est abîmé. Recommence."

echo "Installation dans $GAME…"
"$PY" - "$TMP/jeu.zip" "$TMP/x" <<'EOF'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
EOF
mkdir -p "$GAME/media"
# La gamelist existante est gardée (EmulationStation y note les parties jouées).
[ -f "$GAME/gamelist.xml" ] && rm -f "$TMP/x/roms/ports/miarritze/gamelist.xml"
cp -rf "$TMP/x/roms/ports/miarritze/." "$GAME/"
rm -f "$GAME"/*.new "$GAME/.relance" "$GAME"/.update-*

# Déclaration du système (fichier utilisateur d'EmulationStation).
mkdir -p "$(dirname "$SYSTEMLIST")"
if [ ! -f "$SYSTEMLIST" ]; then
  cp "$TMP/x/system/.emulationstation/systemlist.xml" "$SYSTEMLIST"
  echo "Système « miarritze » déclaré."
elif grep -q "$SYSTEM_UUID" "$SYSTEMLIST"; then
  echo "Système « miarritze » déjà déclaré."
else
  cp "$SYSTEMLIST" "$SYSTEMLIST.avant-miarritze"
  "$PY" - "$TMP/x/system/.emulationstation/systemlist.xml" "$SYSTEMLIST" <<'EOF'
import re, sys
ours = open(sys.argv[1]).read()
block = re.search(r"\s*<system .*?</system>", ours, re.S).group(0)
path = sys.argv[2]
text = open(path).read()
if "</systemList>" not in text:
    sys.exit("balise </systemList> introuvable dans " + path)
open(path, "w").write(text.replace("</systemList>", block.rstrip() + "\n</systemList>", 1))
EOF
  echo "Système « miarritze » ajouté à $SYSTEMLIST (copie de l'ancien : systemlist.xml.avant-miarritze)."
fi

if [ -z "${MIARRITZE_NO_RESTART:-}" ] && [ -x /etc/init.d/S31emulationstation ]; then
  echo "Redémarrage d'EmulationStation…"
  /etc/init.d/S31emulationstation restart >/dev/null 2>&1 || true
  echo "C'est installé ! Miarritze Borroka est dans « Ports »."
else
  echo "C'est installé ! Redémarre la Recalbox : Miarritze Borroka sera dans « Ports »."
fi
echo "Pour quitter le jeu : maintiens Select (ou Hotkey) + Start une seconde."
