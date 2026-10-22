# CLAUDE.md — Miarritze Blackout

Cache-cache asymétrique pour enfants, de nuit, en pixel art façon *Party Hard*, dans Biarritz.
**La seule source de vérité est `GDD-BLACKOUT.md`** ; en cas de doute, elle prime. Ce fichier n'en est
que le résumé opérationnel (stack, conventions, commandes) et ne contient aucune décision de conception.
Toute nouvelle décision de Julien s'écrit d'abord dans le GDD (datée), puis on corrige ou archive le jour
même tout document, JSON ou commentaire qui la contredit. On ne crée pas d'autre document de conception.

L'ancien jeu de combat *Miarritze Borroka* a été retiré du dépôt le 2026-10-22 (récupérable par le tag
`avant-suppression-borroka` et la branche `borroka`). N'en restent que le réseau des salons, le client
pixelforge et quelques briques réduites dans `src/blackout/commun/`, à remplacer.

---

## 0. Règles d'or

1. **GDScript typé uniquement** (le C# ne s'exporte pas en web). Renderer **Compatibility**.
2. **Web-first, paysage, iPhone + clavier/manette, Steam Deck.** Cible (GDD §9) : pixel art en
   **640×360** affiché ×2, cases et persos de 32 px, filtre plus proche voisin. *Le projet est encore
   en 1280×720 lissé et en cases de 64 px : bascule prévue au jalon actuel (GDD §15).* Zones sûres
   iPhone (`SafeArea`).
3. **Enfants (9 ans) :** lisible, généreux, jamais punitif, zéro violence graphique.
   **Zéro donnée personnelle** : pseudo seul, pas de texte libre.
4. **Tout paramètre de gameplay est une donnée** (`data/blackout/rules.json`, `options_partie.json`,
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
src/blackout/          partie et règles (bk_game, bk_rules), carte (bk_map, bk_map_chunk, bk_decor),
                      acteurs (bk_actor, bk_perso, bk_pantin), IA (bk_ai), entrées (bk_input), HUD,
                      versus, podium ; démarrage bk_boot.tscn
src/blackout/menus/    bk_qui_joue → bk_accueil → bk_partie_rapide, bk_profil_ecran, bk_reglages ;
                      navigation BkNav, kit BkUi, profil BkProfil
src/blackout/commun/   briques héritées, réduites, à remplacer : autoloads Settings, Profiles, InputHub,
                      QaCapture ; InputDevice, Prompts, SafeArea, WebTextField
src/blackout/bk_online.tscn   « En ligne » (écran d'attente, à remplacer par les salons)
src/net/              réseau des salons : Api (autoload, client HTTP), P2PLink (WebRTC), Signaling
data/blackout/         rules.json, options_partie.json, gros_mots.json…
assets/maps/<carte>/  cartes (map.txt, décor) ; assets/blackout/ persos, décor
backend/              API PHP (routeur unique public/index.php, salons dans src/Rooms.php)
producer/             service /producer (pilotage) ; tools/producer/ pour le construire
tools/blackout/        cartes, décor, persos, recette (pixelforge) ; tools/pf/ client pixelforge
tests/                bk_tests.gd (headless), decor/, backend/rooms_test.py, web/ (Playwright)
web/                  shell.html (page d'accueil web), .htaccess (COOP/COEP)
```

## 3. Conventions

- `class_name` PascalCase ; fichiers/dossiers snake_case ; constantes UPPER_SNAKE ; membres privés `_x` ;
  signaux au passé.
- Typage statique partout. Composition > héritage.
- Commentaires et code en **français**.
- `.gdignore` dans `.venv`, `tools`, `web`, `backend`, `docs`, `tests/web`, `tests/out`.
- Commits atomiques par étape.
- Prompts de génération simples et sans négation (décrire seulement le résultat voulu) ; la
  bibliothèque de prompts est dans GDD-BLACKOUT.md §8.2 (copie machine : `data/blackout/style_party_hard.json`).
- Jobs pixelforge : par la file (API), jamais par message ; rien en file sans accord de Julien.
- Routes et tables du backend gardent leur préfixe historique `gk_` (données en prod).

## 4. Commandes

```bash
godot --headless --path . --import                                              # (ré)import
godot --headless --path . --fixed-fps 60 --script res://tests/bk_tests.gd       # tests Blackout
godot --path . -- --scene=bk_game [--bk-local-role=hunter|hider] [--bk-rules=phase_hide:2,…]
godot --headless --path . -- --scene=bk_game --bk-bots-only --bk-log --speed=8  # rounds IA contre IA
godot --path . --resolution 1280x720 -- --scene=bk_<écran> --shot=/abs/out.png --delay=3   # capture
godot --headless --path . --export-release "Web" web/build/index.html
node tests/web/smoke.mjs chromium "#scene=bk_game" 20                           # web
python3 tests/backend/rooms_test.py                                             # API des salons
python3 tools/blackout/make_proto_map.py                                         # carte → assets/maps/
tools/producer/build.sh <dossier>                                               # /producer
```

Écrans pour `--scene=` : `bk_qui_joue`, `bk_accueil`, `bk_partie_rapide`, `bk_profil`, `bk_reglages`,
`bk_en_ligne`, `bk_game` (web : `#scene=bk_game`). Captures de tous les menus :
`tools/producer/captures_ecrans.sh`.

## 5. Contraintes web (rappels)

COOP/COEP obligatoires (`web/.htaccess`), MIME wasm, Cache-Control no-cache. Budget mémoire WASM :
libérer chaque scène, tester une session longue. Zones sûres iPhone
(`DisplayServer.get_display_safe_area()`). Sur iOS, l'index d'un toucher est arbitraire : jamais
supposer 0. Le clic sur JOUER de la page d'accueil (`web/shell.html`) est le geste qui débloque
l'audio et le plein écran.

## 6. Documents

`GDD-BLACKOUT.md` (fait foi) · procédures : `docs/PRODUCER.md`, `docs/ONLINE.md`, `docs/TEST_DECOR.md`,
`docs/PIXELFORGE_ANIMATIONS.md` · analyses : `docs/STYLE_PARTY_HARD.md`, `docs/PROMPTS_MUSIQUE.md` ·
historique : `archive/`.
