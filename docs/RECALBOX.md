# Version Recalbox

Build Linux du jeu pour Recalbox, construit à chaque push sur `main`, installable depuis `/recalbox/` et mis à jour automatiquement au lancement. Même principe que la version Steam Deck (`docs/STEAMDECK.md`), dont il réutilise l'updater et l'outillage.

## Faisabilité (vérifiée le 2026-10-18 sur les sources de Recalbox, branche `master`)

Recalbox n'a pas de « ports natifs » à la Batocera (dossier de `.sh` lancés tels quels). Ses Ports sont des moteurs compilés dans l'image. Il reste toutefois une voie propre et prévue par EmulationStation :

- **Système utilisateur.** ES lit `share/system/.emulationstation/systemlist.xml` en plus de la liste de Recalbox (`SystemDeserializer::UserConfigurationPath()`). Un système peut y déclarer sa propre `command`, que ES exécute avec `system()` (`GameRunner::Run`) après avoir libéré l'écran. Avec `port="1"`, le système est rangé dans le dossier « Ports ». Il faut déclarer un émulateur et un cœur, même fictifs : sinon ES refuse le lancement (`ViewController::LaunchCheck`).
- **Affichage.** Godot 4 n'a pas de pilote KMS/DRM, il lui faut X11 ou Wayland. Sur PC, ES tourne sous `startx`, donc `DISPLAY` existe. Sur Raspberry Pi 4/5 (images 64 bits), ES dessine directement en KMS, mais l'image embarque `dwl`, un compositeur Wayland avec XWayland. configgen s'en sert déjà pour les émulateurs `videobackend=wayland` (`runner.py` : `dwl -s "<commande>"`). Le lanceur fait de même.
- **OpenGL.** Pi 4/5 : Mesa V3D, OpenGL ES 3.1. Le rendu Compatibility passe par `--rendering-driver opengl3_es`, parce que V3D n'offre qu'OpenGL 3.1 et pas le 3.3. PC : Mesa (Intel, AMD, Nouveau) ou NVIDIA, OpenGL 3.3 et plus.
- **Partition `share`.** Elle est en exFAT, montée avec `fmask=0133` (`recalbox-mount.sh`) : aucun fichier n'y est exécutable, et `chmod` n'y fait rien. Le lanceur copie donc l'exécutable dans `/overlay` (partition ext4 persistante, comme le fait le générateur pico8 de Recalbox), sinon dans `/tmp`.
- **Modèles Godot.** Les modèles officiels 4.7 incluent `linux_release.arm64` et `linux_release.x86_64` (ainsi que `arm32`). Le binaire arm64 est aligné sur 16 Ko (`readelf -l` : segments `LOAD` alignés à `0x4000`), ce qu'exige le noyau du Pi 5 (`BR2_ARM64_PAGE_SIZE_16K`). Il ne dépend que de la glibc 2.28.
- **Exclus.** Le Pi 3 et le Pi Zero 2 n'ont que GLES 2 (VC4), alors que Godot Compatibility exige GLES 3. L'image Pi 4 32 bits n'a ni X11 ni Wayland. Les portables Rockchip ou Odroid n'ont pas de compositeur.

Sources : dépôt `recalbox/recalbox` sur GitLab (`configs/recalbox-*_defconfig`, `package/recalbox-system/Config.in`, `board/recalbox/fsoverlay/etc/init.d/S31emulationstation` et `S11share`, `recalbox/scripts/recalbox-mount.sh`, `projects/configgen/configgen/utils/runner.py`, `generators/pico8/pico8Generator.py`) et `recalbox/recalbox-emulationstation` (`es-app/src/systems/SystemDeserializer.*`, `SystemManager.cpp`, `GameRunner.cpp`, `views/ViewController.cpp`, `games/FolderData.cpp`). Version stable : Recalbox 10.1 (annonce du 2026-09-04 sur recalbox.com).

## Ce qui est en place

| Pièce | Fichier |
|---|---|
| Presets « Recalbox » (Linux arm64) et « Recalbox x86_64 », fonctionnalité `recalbox`, `.pck` séparé | `export_presets.cfg` |
| Plein écran (`display/window/size/mode.recalbox=3`) | `project.godot` |
| Quitter à la manette : Select (ou Home) + Start tenus 1 s | `src/input/quit_combo.gd` (autoload `QuitCombo`, actif seulement avec `recalbox`) |
| Mise à jour automatique (Steam Deck + Recalbox) | `src/autoload/updater.gd` |
| Lanceur exécuté par ES | `tools/recalbox/MiarritzeBorroka.sh` |
| Déclaration du système, gamelist, image | `tools/recalbox/systemlist.xml`, `gamelist.xml`, `media/titre.png` |
| Empaquetage (deux `.zip`, un `.pck`, manifeste) | `tools/recalbox/package.py` |
| Outils partagés avec le Deck | `tools/release/` (`manifest.py`, `set_version.py`, `install_godot.sh`) |
| Page d'installation, `install.sh` (SSH), `.htaccess` | `web/recalbox/` → servi dans `/recalbox/` |
| Build et publication | job `recalbox` de `.github/workflows/deploy.yml` |

## Paquets

Il y a un `.zip` par architecture, `MiarritzeBorroka-recalbox-{arm64,x86_64}-<version>.zip`, à décompresser à la racine de `share` :

```
roms/ports/miarritze/MiarritzeBorroka.sh        lanceur (le « jeu » vu par ES)
roms/ports/miarritze/MiarritzeBorroka.<arch>    exécutable Godot
roms/ports/miarritze/MiarritzeBorroka.pck
roms/ports/miarritze/gamelist.xml, media/        nom, description, images
roms/ports/miarritze/VERSION
system/.emulationstation/systemlist.xml         système « miarritze » (uuid 3aad7373-…)
LISEZMOI.txt
```

Le `.pck` est le même pour les deux architectures : `package.py` vérifie que les deux exports sont identiques octet pour octet. `manifest.json` contient `build`, `version`, `godot`, `date`, `pck` (`url`, `sha256`, `size`) et `packages.arm64` / `packages.x86_64`. Le Deck, lui, n'a qu'un seul `package`.

ES ne liste que les `.sh` du dossier, et ignore `media/` et `gamelist.xml`. Il ajoute `-verbose` ou `-nodefaultkeymap` à la commande : le lanceur les ignore.

## Lanceur (`MiarritzeBorroka.sh`)

1. Met en place les fichiers `*.new` laissés par une mise à jour.
2. Copie l'exécutable dans `/overlay/miarritze-borroka` (sinon `/tmp/miarritze-borroka`), seulement s'il a changé (taille et date), et crée à côté un lien vers le `.pck` resté sur `share`. Si le dossier est monté `noexec` (code 126), il passe au suivant.
3. `XDG_DATA_HOME=share/saves/ports/miarritze`. Les sauvegardes Godot vont donc dans `…/godot/app_userdata/Miarritze Borroka/`. Si ce dossier n'est pas inscriptible, il prend `/tmp`, car Godot plante si `user://` ne l'est pas.
4. Sans `DISPLAY` ni `WAYLAND_DISPLAY`, mais avec `dwl` présent (cas du Pi) : il se relance dans `dwl -s`. dwl s'arrête avec lui.
5. Il lance le jeu avec `-- --install-dir=<dossier sur share>`. Le code 75 accompagné d'un fichier `.relance` signifie « mise à jour prête » : il met les fichiers en place et relance avec `--updated-to=N`, trois fois au plus.

Journal : `share/system/logs/miarritze-borroka.log`, tronqué au-delà de 1 Mo. Variables de dépannage : `MIARRITZE_ARGS` (arguments Godot), `MIARRITZE_USER_ARGS` (arguments du jeu), `MIARRITZE_RUN_DIR`, `MIARRITZE_SAVE_DIR`, `MIARRITZE_NO_DWL=1`.

## Mise à jour automatique

C'est le même `Updater` que sur le Deck : manifeste `/recalbox/manifest.json`, délai de 5 s, vérification de la taille et du sha256, garde-fou `--updated-to`. Hors ligne ou en cas d'erreur, le jeu démarre normalement. Deux différences :

- **Rien n'est remplacé pendant que le jeu tourne.** Le nouveau `.pck`, ou le contenu de `roms/ports/miarritze/` du `.zip` (extrait avec `ZIPReader`, sans outil externe, `gamelist.xml` exclu), est écrit en `<fichier>.new`. C'est le lanceur qui renomme une fois le jeu arrêté, ce qui ne dépend pas des subtilités de l'exFAT.
- **La relance passe par le lanceur** : `.relance` contient N et le jeu quitte avec le code 75. `OS.create_process` ne convient pas ici, car ES reprendrait l'écran dès la fin de la commande.

Moteur identique : seul le `.pck` est téléchargé (~14 Mo). Moteur différent : le `.zip` de l'architecture (~40 Mo).

## Build automatique (CI)

Le job `recalbox` de `deploy.yml` est indépendant des jobs `deploy` (web) et `steamdeck`, et s'exécute en concurrence `recalbox-deploy` :

1. installe Godot et les modèles `linux_release.arm64` et `.x86_64`, mis en cache sous la clé `godot-<ver>-linux-recalbox` ;
2. définit la version `<run_number>-<sha7>`, injectée par `tools/release/set_version.py`. C'est le même compteur que pour le Deck, et il doit rester croissant (voir `docs/STEAMDECK.md`) ;
3. exporte les deux presets, puis lance `tools/recalbox/package.py` ;
4. dépose les `.zip` comme artefact GitHub (14 jours) ;
5. publie dans `/recalbox/` par rsync, avec les secrets `FTP_*` : les fichiers d'abord, le manifeste en dernier, et `--delete` limité à `recalbox/`.

## Installation (page `/recalbox/`)

- **À la main** : télécharger le `.zip`, l'extraire dans `share` par le réseau (`\\RECALBOX\share`, `smb://recalbox`) ou depuis la carte SD, puis redémarrer. Si un `systemlist.xml` utilisateur existe déjà, il faut fusionner à la main ou passer par le SSH.
- **Par SSH** : `curl -fsSL https://miarritze.ijulien.com/recalbox/install.sh | bash`. Le script choisit l'architecture, vérifie le sha256, garde la gamelist, ajoute le bloc `<system>` à un `systemlist.xml` existant (avec une copie `.avant-miarritze`), puis redémarre ES.

## Tester (sans Recalbox)

```bash
python3 tools/release/set_version.py 5 5-test        # (sur une copie, puis restaurer project.godot)
godot --headless --path . --export-release "Recalbox" exports/recalbox/arm64/MiarritzeBorroka.arm64
godot --headless --path . --export-release "Recalbox x86_64" exports/recalbox/x86_64/MiarritzeBorroka.x86_64
tools/recalbox/package.py exports/recalbox /tmp/srv 5 5-test 4.7.1
```

Validé le 2026-10-18 dans des conteneurs Debian privilégiés, arm64 natif et x86_64 émulé. La partition `share` y était une vraie image exFAT montée comme sur Recalbox (`mount.exfat` FUSE, `fmask=0133`), et les commandes de base étaient celles de busybox. Le jeu tournait en `--headless`. 26 vérifications réussies par architecture :

- binaire non exécutable sur `share` ;
- mise à jour du `.pck` puis relance par le lanceur ;
- déjà à jour, sans nouvelle copie ;
- moteur différent avec le `.zip` complet, `gamelist.xml` conservé ;
- sha256 faux ;
- hors ligne ;
- anti-boucle ;
- dossier `noexec`, avec repli sur le dossier suivant ;
- `share` en lecture seule.

`install.sh` a été testé de trois façons : installation neuve, réinstallation, fusion avec un `systemlist.xml` existant. Non-régression Steam Deck : mise à jour `.pck` et `.tar.gz` toujours OK.

**Pas testé, faute de vraie Recalbox :** ES qui affiche et lance le système, l'affichage sous `dwl` et GLES sur un vrai Pi, le son, les manettes, Select+Start pour quitter.

## À faire sur une vraie Recalbox (Pi 4/5 et/ou PC)

- [ ] Installer par le `.zip` et par SSH. Vérifier que « Miarritze Borroka » apparaît dans Ports, avec le nom et l'image.
- [ ] Lancer : plein écran, rendu (Pi : GLES 3 sous dwl), son, deux manettes, menus, combat.
- [ ] Select (ou Hotkey) + Start une seconde : retour à ES, qui reprend bien l'écran et le son.
- [ ] Pousser un commit sur `main`, relancer le jeu, voir l'écran de mise à jour et le redémarrage.
- [ ] En cas de souci, lire `share/system/logs/miarritze-borroka.log` et `es_launch_stderr.log`.
