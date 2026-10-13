# HANDOFF — reprendre Miarritze Borroka sur un autre ordinateur

Dernière mise à jour : 2026-10-13. Branche de travail : `borroka`. Elle est identique à `main`, à part ce fichier, qui n'est que sur `borroka`.
Prod : https://miarritze.ijulien.com. Un push sur `main` déclenche `.github/workflows/deploy.yml` (build Godot 4.7.2 + rsync).

## 1. À lire d'abord
1. `CLAUDE.md` : règles d'or, conventions, commandes.
2. `docs/STATUS.md` : état exact. La section « Après la mise en prod » liste ce qui reste à faire.
3. `SPEC-BORROKA.md` : source de vérité. `docs/DECISIONS.md` : écarts tranchés, y compris ceux décidés par Julien après la spec (*Hegoak* rétabli, versus contre l'ordi sur le tactile…).

## 2. Installer la machine (macOS)
```sh
git clone <dépôt> miarritze && cd miarritze && git checkout borroka
brew install godot            # 4.7.2, éditeur standard (pas .NET)
# Modèles d'export Web 4.7.2 : Godot > Editor > Manage Export Templates, ou télécharger
# Godot_v4.7.2-stable_export_templates.tpz dans ~/Library/Application Support/Godot/export_templates/4.7.2.stable/
python3 -m venv .venv && .venv/bin/pip install pillow numpy pyyaml soundfile
(cd tests/web && npm install && npx playwright install chromium webkit)
brew install php              # PHP 8 + SQLite, pour le backend local des tests
godot --headless --path . --import
```

**Secrets absents du dépôt :** à recopier depuis l'ancien Mac, ou à redemander à Julien.
- `.rd_api_key` à la racine : clé Retro Diffusion. Sans elle, les outils RD refusent de tourner ; le cache `tools/rd/cache/` suffit pour tout reconstruire sans appel payant.
- `tools/rd/out/` (gitignoré) : sorties brutes RD (finals.json, picks.json). Utile seulement pour régénérer des sprites de combattants. Recopier si possible, sinon le cache suffit.
- `backend/config.php` : seulement en prod, sur le serveur. En local, l'API tourne sans.
- Secrets GitHub du déploiement (`FTP_HOST`, `FTP_USER`, `FTP_PASSWORD`, `FTP_PATH`) : déjà configurés dans le dépôt GitHub, rien à faire.

**Budget RD :** plafond dur de 50 $, appliqué par `tools/rd/client.py`. Le registre `tools/rd/ledger.jsonl` est versionné : 13,67 $ dépensés, 36,33 $ restants. Ne jamais appeler RD hors de ce client. `.venv/bin/python tools/rd/client.py --status` donne l'état.

## 3. Vérifier que tout marche
```sh
godot --headless --path . --script res://tests/run_tests.gd     # 19 tests sim/netcode
godot --headless --path . res://tests/touch_test.tscn            # manette tactile
python3 tests/backend/api_test.py                                # API PHP
godot --headless --path . --export-release "Web" web/build/index.html
node tests/web/online_two.mjs                                    # combat en ligne à 2 pages
```

## 4. Prochaine tâche (interrompue)
Relancer la tournée iPhone sur le build actuel et regarder **chaque** capture :
```sh
node tests/web/iphone_tour.mjs all iphone13
node tests/web/iphone_tour.mjs screens,tower,settings,portrait iphone_se
# captures : tests/out/iphone_tour/<appareil>/<section>/ (+ sheet.png par section)
```
Points à vérifier en priorité, tous corrigés juste avant la pause mais pas encore revus en capture :
- sélection : un tap choisit, un second valide, toucher le grand perso change le costume ;
- liste des coups (« Fermer » en haut) ;
- bouton « Mannequin » ;
- grille des maps sur SE ;
- défilement des réglages au doigt ;
- message portrait ;
- écran de fin (`#scene=ending:louis`, bouton « Menu » déplacé en bas à droite) ;
- boutons tactiles estompés au-dessus d'un combattant.

Ensuite, des améliorations cosmétiques connues : les étoiles de stats chevauchent la tête de l'aperçu à la sélection ; le pseudo de la carte de profil est recouvert par le sprite ; « 3 COUPS ! » reste visible pendant la pause.

## 5. Outils utiles
- **Tests iPhone :** `tests/web/iphone_lib.mjs` touche les boutons par libellé (`tapText`), glisse et fait du multi-touch via CDP. Il faut `?qa=1` dans l'URL : le jeu publie alors `window.__qa` (scène + boutons). `#scene=<id>` démarre sur un écran (voir `src/ui/boot/boot.gd`).
- **Décors :** `godot --path . res://tests/stage_sheet.tscn [-- --only=<id>]` produit des planches en 16:9, 19,5:9 et 4:3, caméra à gauche, au centre et à droite. Pour refaire un décor sans raccord : `.venv/bin/python tools/stages/regen_wide.py pano <id> <seed>…`, puis `pick <id> <candidat>`, puis `tools/stages/build_stage.py <id>`. RD refuse toute largeur au-delà de 384 px : on génère du 384×160, agrandi ×4/3.
- **Revue d'assets :** toujours sur planche contact ×4 avant intégration (règle d'or).

## 6. Reste à faire côté Julien
- Checklist sur un vrai iPhone (`docs/TEST_IPHONE.md`), dont le clavier du pseudo et la zone de l'encoche.
- Un match en ligne en 4G. Si les connexions échouent, ajouter des serveurs TURN dans `backend/config.php` côté serveur.
- Question ouverte : un mode « deux joueurs sur un iPad » (une manette par côté) ? Il n'est pas fait ; la spec le laisse à trancher en playtest.

## 7. Règles de travail
- Commits atomiques sur `borroka`. Déployer = pousser sur `main` (`git push origin borroka:main`), seulement avec l'accord de Julien. Il l'a donné pour la v1 et les correctifs iPhone.
- Sim 100 % déterministe (lint en test). GDScript typé, commentaires en français.
- Consigner les décisions dans `docs/DECISIONS.md`, les revues dans `docs/REVIEWS.md` et l'avancement dans `docs/STATUS.md`.
