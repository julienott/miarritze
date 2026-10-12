# STATUS — Miarritze Borroka

Mis à jour à chaque fin de phase. Reprendre ici après une interruption.

## Phase atteinte : 2 ✅ (contenu de gameplay en mannequins)

### Phase 2
- 12 combattants + boss Itsasargi + mannequin Hondar : fiches de coups (4 spéciaux, super, finish), projectiles et pièges, mannequins distincts (14 silhouettes, 4 costumes chacun).
- Écrans provisoires : menu, sélection 6×2 (portraits, costumes, verrous), choix de map, VS, Pyramide du Phare (9 étages : double, reflet, rival, boss), fin TXAPELDUN + 3 cadrages, résultats versus, pause, entraînement (historique, dégâts, mannequin réglable), liste des coups.
- Finishs BUKATU procéduraux par perso (seau, vague, filet, statue, danse, poisson, plumes…).
- IA à compétence 1–100, adaptation après défaites ; équilibrage automatique (`tools/balance_tune.py`) : 43–57 % (n=20, `docs/captures/phase2_balance.png`).
- Pyramides complètes jouées en automatique (`--autotower`) : Louis Facile, Mattin Normal ; Kaio Expert en cours.
- 15 tests headless au vert (fuzz de tout le roster, renvoi de projectile).

### Phase 1 (rappel)

### Phase 1
- `src/fight/sim/` : sim entière (1 px = 256), XRng, InputBuffer (buffer 8 f, double tape, manips), coups normaux, auto-combo P×3, garde haute/basse, chip sans K.O., projection + tech, projectiles (boomerang, chocs, renvoi), spéciaux (vitesses, invuln, armure, téléport, contre, traction, vol de jauge, ralentissement), super, Marée + Retour de vague, rounds, chrono, égalités, BUKATU + finish, `save_state/load_state/checksum` (< 1 Ko).
- `tests/run_tests.gd` : 13 tests au vert (lint, données, save/load, déterminisme 3600 f, rollback 1–8 f, frame data, chip, combo forcé, chrono, Retour de vague, projection/tech, match complet, entrées → coups).
- IA de base (`src/fight/ai/ai_brain.gd`) dans la sim, déterministe.
- Pipeline sprites : rig cut-out RotSprite (`tools/rig/`), mannequins (`tools/mannequin/`), palettes/costumes, boîtes inférées, planches contact (`tools/sprites/`). Louis et Maïa : 37 animations, 215 frames, feuille 2048×1792 indexée.
- Vue : shader de palette, caméra (lissage, shake), HUD (vie + vie perdue, bouée-chrono, txapelas, Marée), annonces, vfx procéduraux, F3 boîtes, ombres.
- Versus local au clavier (titre → combat) testé dans le build web (Playwright).
- QaCapture : `--autofight`, `--frames`, `--inputs` (entrées scriptées), garde-fou 180 s.

### Captures Phase 1
`docs/captures/phase1_autofight.png`, `phase1_uppercut.png/.gif`, `phase1_web_clavier.png`.

## Historique

### Ce qui marche
- Branche `borroka`. L'ancien gameplay a été supprimé (§2.2). Nouvelle arborescence (§8.1).
- `project.godot` : 384×216, viewport/expand/fractional, 60 ticks, autoloads `Profiles, Api, InputHub, AudioManager, SceneRouter, QaCapture, OrientationOverlay`, actions clavier J1/J2 (§4.1).
- Écran titre provisoire ; l'export web tourne en WebKit (émulation iPhone 844×390, tactile) et en Chromium : `crossOriginIsolated`, aucune erreur console.
- `tools/palette.py` : 68 couleurs en rampes, `tools/palette.png`.
- `tools/rd/client.py` (v2) : check_cost, cache versionné, registre, **plafond 50 $**, contrôle croisé du solde, `--status`. Test réel : 1 image `rd_fast` 64×64. Test hors ligne du refus : `tools/rd/test_client.py`.
- *Hegoak* retiré (`gen_audio.py`, `menu.mp3` supprimé avec les anciennes musiques).

### Captures
`tests/out/smoke_webkit.png`, `tests/out/smoke_chromium.png`, `tests/out/title.png` (non versionnées : `node tests/web/smoke.mjs webkit` pour les régénérer).

### Dépense RD
Voir `python3 tools/rd/client.py --status` (Phase 3 en cours : 3,23 $ au 12/10).

### Blocages / notes
- Les photos sources i2i ne sont plus sur le disque. Repli : élargir les décors `bg_*` existants, txt2img pour les nouveaux stages (DECISIONS).
- `tools/rd_i2i.py` / `rd_post.py` gardent des chemins codés en dur : ils seront migrés vers `tools/rd/` en Phase 3.
