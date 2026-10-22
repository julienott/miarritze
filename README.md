# Miarritze Blackout

Cache-cache asymétrique pour enfants, de nuit dans Biarritz, en pixel art façon *Party Hard* : un
chasseur, des chassés qui se cachent dans l'ombre, des coups spéciaux et un boss basque en fin de partie
(ex-*Gordeka*, « cache-cache » en basque).

- Conception (seul document qui fait foi) : `GDD-BLACKOUT.md`
- Conventions, commandes, architecture : `CLAUDE.md`
- En ligne (API des salons) : `docs/ONLINE.md` · pilotage : `docs/PRODUCER.md`

L'ancien jeu de combat *Miarritze Borroka* a été retiré du dépôt le 2026-10-22 (tag
`avant-suppression-borroka`, branche `borroka`).

## Jouer en local

```sh
godot --path .                                             # « Qui joue ? »
godot --path . -- --scene=bk_game                          # une partie contre l'IA tout de suite
godot --headless --path . --export-release "Web" web/build/index.html
node tests/web/smoke.mjs chromium "#scene=bk_game" 20      # build web servi avec COOP/COEP
```

## Tests

```sh
godot --headless --path . --fixed-fps 60 --script res://tests/bk_tests.gd   # règles, IA, cartes, profils
python3 tests/backend/rooms_test.py                                         # API des salons (php -S)
```

## Prérequis

Godot 4.7 (éditeur standard, pas .NET) + modèles d'export Web ; PHP 8 avec SQLite pour le backend ;
Python 3 (`.venv` : Pillow, numpy) pour les outils ; Node 20 + Playwright pour les tests web.
