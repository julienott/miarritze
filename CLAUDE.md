# CLAUDE.md — Miarritze Gordeka (ex-Borroka)

> **Pivot du 2026-10-19** : le jeu devient **Miarritze Gordeka**, un cache-cache façon Among Us.
> **La source de vérité est désormais `SPEC-GORDEKA.md`.** Ce qui suit décrit le jeu de combat
> (`SPEC-BORROKA.md`, archivé) : la stack, les conventions, le backend, le réseau et les plateformes
> restent valables. En revanche, la sim de combat déterministe, le pixel art 384×216 et le pipeline
> de sprites de combat ne s'appliquent plus au nouveau jeu (style HD lisse, hôte-autorité). État de la
> refonte des combattants arrêtée : `docs/APRES_PAUSE.md`.
>
> **Gordeka (jalon 1, prototype gris)** : code dans `src/gordeka/` (gk_game = partie et règles,
> gk_map, gk_actor, gk_ai, gk_input, gk_hud, gk_menu), règles dans `data/gordeka/rules.json`, carte
> générée par `tools/gordeka/make_proto_map.py` → `assets/maps/port_pecheurs/`. Projet en 1280×720
> lissé, démarrage `src/gordeka/gk_boot.tscn`.
> ```bash
> godot --path . -- --scene=gk_game [--gk-local-role=hunter|hider] [--gk-rules=phase_hide:2,…]
> godot --headless --path . -- --scene=gk_game --gk-bots-only --gk-log --speed=8   # rounds IA contre IA
> node tests/web/smoke.mjs chromium "#scene=gk_game" 28                          # web
> ```

Résumé opérationnel pour Claude Code. **La source de vérité est `SPEC-BORROKA.md`** ; en cas de doute, elle prime. Le *quoi/pourquoi* est résumé dans `DESIGN.md`. État d'avancement : `docs/STATUS.md`. Choix tranchés : `docs/DECISIONS.md`. Revues visuelles : `docs/REVIEWS.md`.

---

## 0. Règles d'or

1. **Sim de combat 100 % déterministe** (`src/fight/sim/`) : entiers seulement (1 px = 256 sous-pixels), `XRng` maison, aucun Node/signal, ordre d'itération fixe, `save_state/load_state/checksum`. Un lint en test refuse `float`, `randf`, `randi`, `Time.`, `OS.`, `Engine.` dans `sim/`.
2. **GDScript typé uniquement** (le C# ne s'exporte pas en web). Renderer **Compatibility**.
3. **Web-first, paysage, iPhone + clavier/manette.** Résolution logique **384×216**, `stretch=viewport`, `aspect=expand`, `scale_mode=fractional`, filtre nearest.
4. **Aucun code de jeu ne lit d'`InputEvent` brut** sauf les sources (`src/input/`). La sim ne voit qu'un `InputFrame` 8 bits par joueur et par tick. Sur iOS, **l'index d'un toucher est arbitraire** : jamais supposer 0.
5. **Retro Diffusion : plafond DUR de 50 $** appliqué par `tools/rd/client.py` (registre `tools/rd/ledger.jsonl`, refus automatique, cache). Jamais d'appel RD hors de ce client. Plafond atteint → mannequins + procédural.
6. **Tout asset est regardé** sur planche contact ×4 (nearest) avant intégration.
7. **Enfants (9 ans) :** lisible, généreux, jamais punitif, zéro violence graphique. **Zéro donnée personnelle** : pseudo + code de groupe, pas de texte libre.
8. **Tout paramètre de gameplay est une donnée** (JSON combattant, `stage.json`, constantes nommées), pas un nombre magique.
9. **Branche de travail = `main`.** Les commits et les push sur `main` sont autorisés. Pas de déploiement en prod sans Julien.
10. Musique : compositions originales ou airs du domaine public (`docs/MUSIC.md`). Exception décidée par Julien : *Hegoak* (`hegoak.mp3`) sur l'accueil et les menus.

## 1. Stack

Godot **4.7** (GDScript typé, Compatibility/WebGL 2, export Web threadé) · Backend **PHP + SQLite** (LAMP, même origine `/api`) · Réseau en ligne : **WebRTC P2P** (data channels) + signalisation PHP par polling · Outils : Python 3 (`.venv/` : Pillow, numpy, PyYAML), Playwright (`tests/web/`).

## 2. Arborescence

```
src/autoload/      profiles, api, input_hub, audio_manager, scene_router, qa_capture, orientation_overlay
src/fight/sim/     simulation déterministe (RefCounted, entiers)
src/fight/data/    fighter_db.gd (JSON -> structures)
src/fight/view/    scène de combat, vues, caméra, HUD, vfx (floats autorisés, lecture seule de la sim)
src/fight/ai/      ai_brain.gd (produit des InputFrame, dans la sim)
src/fight/modes/   tower / versus / online / training
src/input/         sources : clavier, manette, pad virtuel, gestes, IA, réseau
src/net/           signalisation, lien P2P, session rollback
src/ui/<écran>/    un dossier par écran (.tscn + .gd de même nom) ; widgets/ partagés
assets/fighters/<id>/  sheet.png indexée, palettes.png, portraits, data.json
assets/stages/<id>/    far.png, floor.png, stage.json…
backend/           API PHP (routeur unique public/index.php)
tools/rd/          client RD (plafond), prompts, cache versionné
tools/sprites/ tools/rig/ tools/mannequin/   pipeline sprites
tests/             run_tests.gd (headless), web/ (Playwright), out/ (gitignoré)
```

## 3. Conventions

- `class_name` PascalCase ; fichiers/dossiers snake_case ; constantes UPPER_SNAKE ; membres privés `_x` ; signaux au passé.
- Typage statique partout. Composition > héritage.
- Commentaires et code en **français**.
- `.gdignore` dans `.venv`, `tools`, `web`, `backend`, `docs`, `tests/web`, `tests/out`.
- Commits atomiques par étape/phase, sur `borroka`.

## 4. Commandes

```bash
godot --headless --path . --import                         # (ré)import
godot --headless --path . --script res://tests/run_tests.gd   # tests sim
godot --path . -- --shot=/abs/out.png --delay=2 [--scene=<id|res://…>] [--autofight=p1,p2,stage,seed] [--frames=…]
godot --headless --path . --export-release "Web" web/build/index.html
node tests/web/smoke.mjs webkit|chromium ["#scene=…"] [secondes]
.venv/bin/python tools/rd/client.py --status [--real]
```

## 5. Contraintes web (rappels)

COOP/COEP obligatoires (`web/.htaccess`), MIME wasm, Cache-Control no-cache. Budget mémoire WASM : SceneRouter libère chaque scène ; tester une session longue. Audio débloqué au premier geste. Zones sûres iPhone (`DisplayServer.get_display_safe_area()`).
