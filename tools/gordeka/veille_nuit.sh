#!/usr/bin/env bash
# Veille de nuit des rendus pixelforge (Julien 2026-10-20 : « il faudra que tu aies un watcher sur les
# rendus pixelforge, ça va tourner cette nuit ! »). Toutes les 5 min :
# - santé de pixelforge (alerte si injoignable 10 min, ou si la file de nuit est ouverte mais n'avance plus) ;
# - persos : la routine tools/gordeka/recette.py tourne-t-elle ? (relancée sinon) ; ses « À VOIR » sont
#   relayés ;
# - décor : tools/producer/decor_matin.py releve (rapatrie et fait les planches) ; ce qui devient prêt
#   pour la recette est relayé.
# Une ligne par événement utile (sortie lue par Claude), rien quand rien ne change.
cd "$(dirname "$0")/../.." || exit 1
PF=https://stellar.tailbeda4d.ts.net
JOURNAL=tools/rd/out/recette/journal.log
# Reprend où la veille précédente s'était arrêtée (une relance ne perd aucune ligne du journal).
LUS=tools/rd/out/recette/.veille_lus
lus=$(cat "$LUS" 2>/dev/null || wc -l < "$JOURNAL" 2>/dev/null || echo 0)
ko=0; dernier_fini=""
while true; do
  q=$(curl -s -m 20 "$PF/v2/queue")
  if [ -z "$q" ]; then
    ko=$((ko + 1)); [ $ko -eq 2 ] && echo "ALERTE pixelforge injoignable depuis 10 min"
  else
    [ $ko -ge 2 ] && echo "pixelforge de nouveau joignable"
    ko=0
    etat=$(printf '%s' "$q" | python3 -c "import json,sys;q=json.load(sys.stdin);n=q.get('night',{});print(n.get('open'),n.get('pending'),len(q.get('running',[])),len(q.get('pending',[])))" 2>/dev/null)
    set -- $etat
    if [ "$1" = "True" ] && [ "$3" = "0" ] && [ "${2:-0}" != "0" ]; then echo "ALERTE file de nuit ouverte mais rien ne tourne ($2 en attente)"; fi
    [ "$etat" != "$dernier_fini" ] && [ "${2:-0}" = "0" ] && [ "$3" = "0" ] && [ "$4" = "0" ] && echo "FILE VIDE : tous les rendus de nuit sont terminés"
    dernier_fini=$etat
  fi
  pgrep -f "recette.py boucle" >/dev/null || { nohup .venv/bin/python tools/gordeka/recette.py boucle >> tools/rd/out/recette/stdout 2>&1 & echo "routine recette relancée"; }
  n=$(wc -l < "$JOURNAL" 2>/dev/null || echo 0)
  if [ "$n" -gt "$lus" ]; then
    tail -n $((n - lus)) "$JOURNAL" | grep -E "À VOIR|POUR QA|ÉCHEC|ALERTE|Traceback" | sed 's/^/PERSO /'
    lus=$n
    echo "$lus" > "$LUS"
  fi
  .venv/bin/python tools/producer/wip.py 2>&1 | sed "s/^/WIP /"

  .venv/bin/python tools/producer/decor_matin.py releve 2>&1 | grep -E "prêt|À VOIR|A_VOIR|reçu|échec|ÉCHEC|Erreur|Traceback" | sed 's/^/DECOR /'
  sleep 300
done
