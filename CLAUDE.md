# CLAUDE.md — Miarritze Gordeka

Cache-cache en ligne pour enfants, façon *Among Us*, dans les décors de Biarritz.
**La seule source de vérité est `SPEC-GORDEKA.md`** ; en cas de doute, elle prime. Ce fichier en est
le résumé opérationnel (stack, conventions, commandes).

L'ancien jeu de combat *Miarritze Borroka* a été retiré du dépôt le 2026-10-22 (récupérable par le tag
`avant-suppression-borroka` et la branche `borroka`). N'en restent que le réseau des salons, le client
pixelforge et quelques briques réduites dans `src/gordeka/commun/`, à remplacer.

---

## 0. Règles d'or

1. **GDScript typé uniquement** (le C# ne s'exporte pas en web). Renderer **Compatibility**.
2. **Web-first, paysage, iPhone + clavier/manette.** Projet en **1280×720** lissé,
   `stretch=canvas_items`, `aspect=expand`. Zones sûres iPhone (`SafeArea`).
3. **Enfants (9 ans) :** lisible, généreux, jamais punitif, zéro violence graphique.
   **Zéro donnée personnelle** : pseudo seul, pas de texte libre.
4. **Tout paramètre de gameplay est une donnée** (`data/gordeka/rules.json`, `options_partie.json`,
   constantes nommées), pas un nombre magique. Une option de gameplay validée devient réglable dans
   le menu de création de partie.
5. **Branche de travail = `main`.** Les commits et les push sur `main` sont autorisés. Pas de
   déploiement en prod sans Julien.
6. **Tout rendu est regardé** (captures `--shot`) avant d'être montré ou déployé.
7. Musique et sons : le jeu n'en a pas pour l'instant. Toute musique ajoutée est une composition
   originale ou un air du domaine public.

## 1. Stack

Godot **4.7** (GDScript typé, Compatibility/WebGL 2, export Web threadé) · Backend **PHP + SQLite**
(LAMP, même origine `/api`) · En ligne : **WebRTC P2P** (data channels) + signalisation PHP par polling,
hôte-autorité · Génération d'assets : **pixelforge** (`tools/pf`) · Outils : Python 3 (`.venv/` : Pillow,
numpy), Playwright (`tests/web/`).

## 2. Arborescence

```
src/gordeka/          partie et règles (gk_game, gk_rules), carte (gk_map, gk_map_chunk, gk_decor),
                      acteurs (gk_actor, gk_perso, gk_pantin), IA (gk_ai), entrées (gk_input), HUD,
                      versus, podium ; démarrage gk_boot.tscn
src/gordeka/menus/    gk_qui_joue → gk_accueil → gk_partie_rapide, gk_profil_ecran, gk_reglages ;
                      navigation GkNav, kit 1280×720 GkUi, profil GkProfil
src/gordeka/commun/   briques héritées, réduites, à remplacer : autoloads Settings, Profiles, InputHub,
                      QaCapture ; InputDevice, Prompts, SafeArea, WebTextField
src/gordeka/gk_online.tscn   « En ligne » (écran d'attente, à remplacer par les salons)
src/net/              réseau des salons : Api (autoload, client HTTP), P2PLink (WebRTC), Signaling
data/gordeka/         rules.json, options_partie.json, gros_mots.json…
assets/maps/<carte>/  cartes (map.txt, décor) ; assets/gordeka/ persos, décor, mannequin
backend/              API PHP (routeur unique public/index.php, salons dans src/Rooms.php)
producer/             service /producer (pilotage) ; tools/producer/ pour le construire
tools/gordeka/        cartes, décor, persos, recette (pixelforge) ; tools/pf/ client pixelforge
tests/                gk_tests.gd (headless), decor/, backend/rooms_test.py, web/ (Playwright)
web/                  shell.html (page d'accueil web), .htaccess (COOP/COEP)
```

## 3. Conventions

- `class_name` PascalCase ; fichiers/dossiers snake_case ; constantes UPPER_SNAKE ; membres privés `_x` ;
  signaux au passé.
- Typage statique partout. Composition > héritage.
- Commentaires et code en **français**.
- `.gdignore` dans `.venv`, `tools`, `web`, `backend`, `docs`, `tests/web`, `tests/out`.
- Commits atomiques par étape.
- Prompts de génération sans négation (décrire seulement le résultat voulu) ; chaque génération
  retenue est notée dans SPEC-GORDEKA §16.2.

## 4. Commandes

```bash
godot --headless --path . --import                                              # (ré)import
godot --headless --path . --fixed-fps 60 --script res://tests/gk_tests.gd       # tests Gordeka
godot --path . -- --scene=gk_game [--gk-local-role=hunter|hider] [--gk-rules=phase_hide:2,…]
godot --headless --path . -- --scene=gk_game --gk-bots-only --gk-log --speed=8  # rounds IA contre IA
godot --path . --resolution 1280x720 -- --scene=gk_<écran> --shot=/abs/out.png --delay=3   # capture
godot --headless --path . --export-release "Web" web/build/index.html
node tests/web/smoke.mjs chromium "#scene=gk_game" 20                           # web
python3 tests/backend/rooms_test.py                                             # API des salons
python3 tools/gordeka/make_proto_map.py                                         # carte → assets/maps/
tools/producer/build.sh <dossier>                                               # /producer
```

Écrans pour `--scene=` : `gk_qui_joue`, `gk_accueil`, `gk_partie_rapide`, `gk_profil`, `gk_reglages`,
`gk_en_ligne`, `gk_game` (web : `#scene=gk_game`). Captures de tous les menus :
`tools/producer/captures_ecrans.sh`.

## 5. Contraintes web (rappels)

COOP/COEP obligatoires (`web/.htaccess`), MIME wasm, Cache-Control no-cache. Budget mémoire WASM :
libérer chaque scène, tester une session longue. Zones sûres iPhone
(`DisplayServer.get_display_safe_area()`). Sur iOS, l'index d'un toucher est arbitraire : jamais
supposer 0. Le clic sur JOUER de la page d'accueil (`web/shell.html`) est le geste qui débloque
l'audio et le plein écran.
