#!/usr/bin/env bash
# Installe (ou réinstalle) le board local sur ce Mac (Julien, 24/10 ; GDD §14.2, docs/PRODUCER.md) :
#   1. assemble le board dans .studio/site/producer (build.sh) et sa config (Tailscale, jeton de l'agent) ;
#   2. deux agents launchd, relancés seuls : le serveur (php -S 127.0.0.1:8099, studio_router.php)
#      et le watcher (studio.py) ;
#   3. tailscale serve : https://<ce Mac>.<tailnet>.ts.net:10000/ → 127.0.0.1:8099 (board /producer/, jeu de QA /jeu/).
# Rien n'est exposé hors du tailnet. Ne lit le jeton que pour en écrire le hachage.
#   tools/producer/studio_installe.sh [--sans-watcher]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SITE="$ROOT/.studio/site"
PY="$ROOT/.venv/bin/python"
PORT=8099
AGENTS="$HOME/Library/LaunchAgents"
PATH_LD="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$SITE/producer" "$ROOT/.studio"
bash "$ROOT/tools/producer/build.sh" "$SITE/producer" "$PY" >/dev/null
if [ ! -f "$SITE/producer/config.php" ]; then
  PRODUCER_TAILSCALE=1 PRODUCER_TOKEN="$(head -1 "$ROOT/.producer_token")" \
    php "$ROOT/tools/producer/make_config.php" "$SITE/producer/config.php"
fi

plist() {   # nom, commande…
  local nom="$1"; shift
  local args=""
  for a in "$@"; do args="$args<string>$a</string>"; done
  cat > "$AGENTS/com.miarritze.$nom.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.miarritze.$nom</string>
  <key>ProgramArguments</key><array>$args</array>
  <key>WorkingDirectory</key><string>$ROOT</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$PATH_LD</string>
    <key>PHP_CLI_SERVER_WORKERS</key><string>6</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$ROOT/.studio/$nom.out</string>
  <key>StandardErrorPath</key><string>$ROOT/.studio/$nom.out</string>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)/com.miarritze.$nom" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENTS/com.miarritze.$nom.plist"
}

mkdir -p "$AGENTS"
plist studio-web "$(command -v php)" -S "127.0.0.1:$PORT" -t "$SITE" "$ROOT/tools/producer/studio_router.php"
if [ "${1:-}" != "--sans-watcher" ]; then
  plist studio "$PY" "$ROOT/tools/producer/studio.py"
fi
tailscale serve --bg --https=10000 "http://127.0.0.1:$PORT" >/dev/null
echo "board : https://$(tailscale status --self --json | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))'):10000/producer/"
