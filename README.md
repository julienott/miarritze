# Miarritze Borroka

Jeu de combat 2D en pixel art, esprit Mortal Kombat mais solaire, basque et pour les enfants. Douze combattants de la côte basque et le Gardien du Phare s'affrontent sur dix lieux de Biarritz. *Borroka* = « combat » en basque.

- Spec complète (source de vérité) : `SPEC-BORROKA.md`
- Résumés : `DESIGN.md` (le quoi/pourquoi), `CLAUDE.md` (architecture, conventions, commandes)
- Reprise sur un autre ordinateur : `docs/HANDOFF.md`
- Avancement : `docs/STATUS.md` · décisions : `docs/DECISIONS.md` · revues : `docs/REVIEWS.md`

## Jouer en local

```sh
godot --headless --path . --export-release "Web" web/build/index.html
node tests/web/serve.mjs   # ou tout serveur qui envoie COOP/COEP (voir web/.htaccess)
```

Puis ouvrir `http://localhost:<port>/index.html` (Chrome ou Firefox). Le build web exige un contexte sécurisé : `localhost` ou HTTPS.

Clavier : J1 = WASD + J (poing) K (pied) L (spécial) Espace (garde) ; J2 = flèches + pavé 1/2/3/0. Manette : stick + X/A/B/RB. iPhone : manette virtuelle ou gestes.

## Tests

```sh
godot --headless --path . --script res://tests/run_tests.gd     # sim, netcode, règles
godot --headless --path . res://tests/touch_test.tscn            # manette tactile
python3 tests/backend/api_test.py                                # API PHP
node tests/web/online_two.mjs                                    # combat en ligne à deux pages
```

## Prérequis

Godot 4.7 (éditeur standard, pas .NET) + modèles d'export Web ; PHP 8 avec SQLite pour le backend ; Python 3 (`.venv` : Pillow, numpy, PyYAML, soundfile) pour les outils d'assets ; Node 20 + Playwright pour les tests web.
