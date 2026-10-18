#!/bin/bash
# Miarritze Borroka — lanceur Recalbox (Raspberry Pi 4/5 en 64 bits, PC x86_64).
#
# EmulationStation l'exécute avec « bash <ce fichier> » (système « miarritze »
# déclaré dans share/system/.emulationstation/systemlist.xml, rangé dans
# « Ports »). Il ignore les arguments qu'ES ajoute (-verbose, -nodefaultkeymap).
#
# 1. La partition share est en exFAT, sans droit d'exécution : l'exécutable
#    est copié dans un dossier où il peut tourner (/overlay, sinon /tmp), à
#    côté d'un lien vers le .pck resté dans ce dossier-ci.
# 2. Sur Raspberry Pi, EmulationStation dessine directement à l'écran (KMS) :
#    le jeu, lui, a besoin d'un serveur d'affichage. On le lance dans dwl, le
#    compositeur Wayland que Recalbox utilise déjà pour certains émulateurs.
#    Sur PC, ES tourne sous X11 (DISPLAY est déjà là).
# 3. Mise à jour (src/autoload/updater.gd) : le jeu dépose les nouveaux
#    fichiers ici en « .new », écrit le build attendu dans .relance et quitte
#    avec le code 75. On met les fichiers en place, puis on relance.
#
# Journal : /recalbox/share/system/logs/miarritze-borroka.log
# Variables (tests, dépannage) : MIARRITZE_ARGS (arguments Godot en plus),
# MIARRITZE_USER_ARGS (arguments du jeu, ex. --update-manifest=<url>),
# MIARRITZE_RUN_DIR (dossier d'exécution), MIARRITZE_SAVE_DIR (sauvegardes),
# MIARRITZE_NO_DWL=1 (ne pas lancer de compositeur).

NAME=MiarritzeBorroka
RELAUNCH_EXIT_CODE=75
MAX_RUNS=3
NOEXEC_DIRS=""
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_DIR=/recalbox/share/system/logs
[ -d "$LOG_DIR" ] || LOG_DIR=$DIR
LOG=$LOG_DIR/miarritze-borroka.log
# share en lecture seule : le journal va dans /tmp (sinon le jeu ne démarrerait pas).
{ : >> "$LOG"; } 2>/dev/null || LOG=/tmp/miarritze-borroka.log
# Sauvegardes (profils, réglages) avec celles des autres jeux, sur share.
SAVE_DIR=${MIARRITZE_SAVE_DIR:-/recalbox/share/saves/ports/miarritze}

log() {
  echo "[$(date '+%F %T')] $*" >> "$LOG"
}

case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  x86_64|amd64) ARCH=x86_64 ;;
  *)
    log "machine $(uname -m) non prise en charge (il faut un Raspberry Pi 4/5 en 64 bits ou un PC)"
    exit 1
    ;;
esac
BIN=$NAME.$ARCH

# Met en place les fichiers déposés par la mise à jour (le jeu est arrêté).
apply_updates() {
  local f
  for f in "$DIR"/*.new; do
    [ -f "$f" ] || continue
    mv -f "$f" "${f%.new}" && log "mise à jour : $(basename "${f%.new}")"
  done
}

# Copie l'exécutable dans un dossier où il peut tourner ; la copie est
# refaite seulement si l'exécutable a changé (taille ou date).
prepare_run_dir() {
  local candidate stamp
  stamp=$(stat -c '%s %Y' "$DIR/$BIN")
  for candidate in ${MIARRITZE_RUN_DIR:-} /overlay/miarritze-borroka /tmp/miarritze-borroka; do
    case " $NOEXEC_DIRS " in *" $candidate "*) continue ;; esac
    mkdir -p "$candidate" 2>/dev/null || continue
    if [ ! -x "$candidate/$BIN" ] || [ "$(cat "$candidate/.stamp" 2>/dev/null)" != "$stamp" ]; then
      rm -f "$candidate/$BIN"
      if ! { cp "$DIR/$BIN" "$candidate/$BIN.tmp" 2>/dev/null \
          && chmod 755 "$candidate/$BIN.tmp" \
          && mv -f "$candidate/$BIN.tmp" "$candidate/$BIN" \
          && echo "$stamp" > "$candidate/.stamp"; }; then
        rm -f "$candidate/$BIN.tmp"
        continue
      fi
    fi
    # Godot cherche <exécutable>.pck à côté de lui : un lien vers celui d'ici.
    ln -sfn "$DIR/$NAME.pck" "$candidate/$NAME.pck" || continue
    RUN_DIR=$candidate
    return 0
  done
  log "aucun dossier où copier le jeu"
  return 1
}

run_game() {
  local args=()
  # Raspberry Pi : le pilote Mesa V3D offre OpenGL ES 3.1 mais seulement
  # OpenGL 3.1 ; le rendu Compatibility de Godot passe donc par GLES 3.
  [ "$ARCH" = arm64 ] && args+=(--rendering-driver opengl3_es)
  # shellcheck disable=SC2206 # découpage voulu : liste d'arguments
  args+=(${MIARRITZE_ARGS:-})
  args+=(-- "--install-dir=$DIR" "$@")
  # shellcheck disable=SC2206
  args+=(${MIARRITZE_USER_ARGS:-})
  log "lancement : $RUN_DIR/$BIN ${args[*]}"
  "$RUN_DIR/$BIN" "${args[@]}" >> "$LOG" 2>&1
}

# Boucle de jeu : relance après une mise à jour, au plus MAX_RUNS fois.
play() {
  local extra=() code=1 run
  # Seulement s'il est inscriptible : Godot plante si user:// ne l'est pas.
  if mkdir -p "$SAVE_DIR" 2>/dev/null && { : > "$SAVE_DIR/.ecriture"; } 2>/dev/null; then
    rm -f "$SAVE_DIR/.ecriture"
    export XDG_DATA_HOME=$SAVE_DIR
  else
    log "sauvegardes impossibles dans $SAVE_DIR : dossier temporaire"
    export XDG_DATA_HOME=/tmp/miarritze-donnees
  fi
  for ((run = 1; run <= MAX_RUNS; run++)); do
    apply_updates
    if [ ! -f "$DIR/$BIN" ] || [ ! -f "$DIR/$NAME.pck" ]; then
      log "fichiers manquants dans $DIR ($BIN, $NAME.pck)"
      return 1
    fi
    prepare_run_dir || return 1
    run_game "${extra[@]}"
    code=$?
    log "fin du jeu (code $code)"
    if [ "$code" -eq 126 ]; then
      # Dossier monté sans droit d'exécution : on essaie le suivant.
      NOEXEC_DIRS="$NOEXEC_DIRS $RUN_DIR"
      continue
    fi
    if [ "$code" -ne "$RELAUNCH_EXIT_CODE" ] || [ ! -f "$DIR/.relance" ]; then
      break
    fi
    extra=("--updated-to=$(cat "$DIR/.relance")")
    rm -f "$DIR/.relance"
  done
  return "$code"
}

# Troncature du journal : on garde la fin.
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  tail -c 262144 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"
fi

if [ "${1:-}" = "--dans-dwl" ]; then
  play
  exit $?
fi

log "=== Miarritze Borroka ($(cat "$DIR/VERSION" 2>/dev/null || echo '?'), $ARCH) ==="
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${MIARRITZE_NO_DWL:-}" ] \
    && command -v dwl >/dev/null 2>&1; then
  if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR=/tmp/miarritze-runtime
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
  fi
  log "affichage : dwl (Wayland)"
  # dwl s'arrête quand la commande de démarrage se termine.
  dwl -s "bash '$DIR/$(basename "${BASH_SOURCE[0]}")' --dans-dwl" >> "$LOG" 2>&1
  exit $?
fi
play
