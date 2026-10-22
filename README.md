# Miarritze Gordeka

Cache-cache en ligne pour enfants, façon *Among Us*, dans les décors de Biarritz : un chasseur, des
chassés qui se cachent, des rounds courts. *Gordeka* = « cache-cache » en basque.

- Spec (seule source de vérité) : `SPEC-GORDEKA.md`
- Conventions, commandes, architecture : `CLAUDE.md`
- En ligne (API des salons) : `docs/ONLINE_GORDEKA.md` · pilotage : `docs/PRODUCER.md`

L'ancien jeu de combat *Miarritze Borroka* a été retiré du dépôt le 2026-10-22 (tag
`avant-suppression-borroka`, branche `borroka`).

## Jouer en local

```sh
godot --path .                                             # « Qui joue ? »
godot --path . -- --scene=gk_game                          # une partie contre l'IA tout de suite
godot --headless --path . --export-release "Web" web/build/index.html
node tests/web/smoke.mjs chromium "#scene=gk_game" 20      # build web servi avec COOP/COEP
```

## Tests

```sh
godot --headless --path . --fixed-fps 60 --script res://tests/gk_tests.gd   # règles, IA, cartes, profils
python3 tests/backend/rooms_test.py                                         # API des salons (php -S)
```

## Prérequis

Godot 4.7 (éditeur standard, pas .NET) + modèles d'export Web ; PHP 8 avec SQLite pour le backend ;
Python 3 (`.venv` : Pillow, numpy) pour les outils ; Node 20 + Playwright pour les tests web.
