# Version Steam Deck

Build Linux x86_64 du jeu, construit à chaque push sur `main`, installable depuis le site et mis à jour automatiquement au lancement.

## Ce qui est en place

| Pièce | Fichier |
|---|---|
| Preset d'export « SteamDeck » (Linux x86_64, binaire + `.pck` séparé, fonctionnalité `steamdeck`) | `export_presets.cfg` |
| Plein écran sur le Deck (`display/window/size/mode.steamdeck=3`) | `project.godot` |
| Mise à jour automatique | `src/autoload/updater.gd` (autoload `Updater`), attendue par `src/ui/boot/boot.gd` |
| Empaquetage : archive, `.pck`, `manifest.json` | `tools/steamdeck/package.sh` |
| Page d'installation, script `install.sh`, `.htaccess` | `web/steamdeck/` → servi dans `/steamdeck/` |
| Build et publication | job `steamdeck` de `.github/workflows/deploy.yml` |

L'écran du Deck fait 1280×800 (16:10). Le jeu garde sa résolution logique de 384×216 (`stretch=viewport`, `aspect=expand`), donc il s'affiche en 384×240, agrandi ×3,33. Captures vérifiées sur le titre, la sélection et un combat. Sur le Deck, Steam présente les commandes comme une manette standard : `src/input/gamepad_source.gd` s'en charge, sans changement. Le pad tactile ne s'affiche pas, car il est réservé au web mobile.

## Build automatique (CI)

À chaque push sur `main` (ou en lancement manuel), le job `steamdeck` de `deploy.yml`, indépendant du job web :

1. installe Godot `GODOT_VERSION` avec le seul modèle `linux_release.x86_64`, mis en cache ;
2. calcule la version `<run_number>-<sha7>` (ex. `57-a1b2c3d`) et l'injecte dans `project.godot` (`application/config/build` et `application/config/version`), dans la copie de travail de la CI uniquement ;
3. exporte avec `--export-release "SteamDeck"` ;
4. lance `tools/steamdeck/package.sh`, qui produit :
   - `MiarritzeBorroka-<version>.tar.gz` : le jeu complet (binaire, `.pck`, `icon.png`, `install.sh`, `VERSION`) ;
   - `MiarritzeBorroka-<version>.pck` : la mise à jour légère, environ 14 Mo ;
   - `manifest.json` : `build`, `version`, `godot`, `date`, et pour `package` et `pck` les champs `url`, `sha256` et `size` ;
5. dépose l'archive comme artefact GitHub (14 jours), pratique pour tester sans le site ;
6. envoie tout dans `/steamdeck/` avec rsync, avec les mêmes secrets que le web (`FTP_HOST`, `FTP_USER`, `FTP_PASSWORD`, `FTP_PATH`). Les fichiers partent d'abord, le manifeste en dernier. `--delete` ne nettoie que `steamdeck/` et retire les anciennes versions.

**Archive `.tar.gz` plutôt qu'AppImage.** L'auto-update doit réécrire le jeu sur place, ce qu'une AppImage, en lecture seule, ne permet pas. Une AppImage demande aussi `appimagetool` et FUSE. Avec l'archive, `install.sh` fait le reste.

**Le numéro de build est le `run_number` de `deploy.yml`.** C'est lui que le jeu compare, il doit donc rester croissant. Si le workflow est renommé ou recréé, le compteur repart à 1 et les Deck installés ne verront plus de mise à jour. Dans ce cas, il faut décaler `BUILD` dans le step « Version du build », par exemple `BUILD=$(( run_number + 1000 ))`.

## Installation (page `/steamdeck/`)

La page explique, pour un enfant et ses parents : passer en mode Bureau, télécharger `installer-miarritze.sh`, le rendre exécutable puis l'exécuter, ajouter le jeu à Steam, revenir en mode Jeu. Une commande Konsole est aussi proposée : `curl -fsSL https://miarritze.ijulien.com/steamdeck/install.sh | bash`.

`install.sh` :

- lit le manifeste, télécharge l'archive, vérifie son sha256 ;
- installe dans `~/Games/MiarritzeBorroka`, sans `sudo` ;
- crée `~/.local/share/applications/miarritze-borroka.desktop` et une copie sur le Bureau ;
- appelle `steamos-add-to-steam` (l'outil de SteamOS derrière « Ajouter à Steam »), sinon affiche la marche à suivre manuelle ;
- affiche ses messages avec `kdialog` quand il est lancé d'un double-clic.

S'il est lancé depuis une archive décompressée, il installe les fichiers posés à côté de lui, sans rien télécharger.

Les sauvegardes restent dans `~/.local/share/godot/app_userdata/Miarritze Borroka/` et ne sont jamais touchées. Pour désinstaller, supprimer `~/Games/MiarritzeBorroka`, le `.desktop` et le raccourci Steam.

## Mise à jour automatique (`Updater`)

L'updater n'est actif que dans un export avec les fonctionnalités `steamdeck`, `template` et `linux`. Il ne tourne jamais en web ni dans l'éditeur. `--no-update` le coupe.

1. Au démarrage, le boot attend `Updater.finished`. Le manifeste a un délai de 5 s ; hors ligne, la réponse est immédiate.
2. Si `manifest.build` est supérieur au build qui tourne :
   - **même moteur** (`manifest.godot` identique au moteur) : téléchargement du `.pck` dans `~/Games/MiarritzeBorroka/.update-N.pck.part`, vérification de la taille et du sha256, puis renommage atomique sur `MiarritzeBorroka.pck` ;
   - **moteur différent** (montée de version de Godot) : téléchargement de l'archive complète, vérification, puis `tar -xzf --strip-components=1` dans le dossier du jeu.

   Sous Linux, on peut remplacer un exécutable ou un fichier ouvert sans risque.
3. Le jeu se relance (`OS.create_process`) avec `--updated-to=N`. Si la version relancée n'est pas N, l'updater n'insiste pas, ce qui évite une boucle.
4. Pendant ce temps, un écran affiche « Nouvelle version du jeu ! Téléchargement… 42 % », puis « C'est prêt ! Le jeu redémarre… ».

Si quoi que ce soit échoue (réseau, sha256, dossier en lecture seule, `tar`), le jeu démarre normalement avec la version présente.

**Pourquoi le `.pck` va à côté de l'exécutable et pas dans `user://`.** Les modèles d'export officiels de Godot 4.7 refusent `--main-pack`. Le message est « compiled without support for path overrides », constaté dans un conteneur Linux. Un `ProjectSettings.load_resource_pack()` à chaud, lui, ne recharge ni les autoloads, ni `project.binary`, ni le cache des `class_name`.

**Limites :**

- Pas de retour arrière automatique. Si un build publié plante avant que l'autoload `Updater` ne démarre, le joueur doit réinstaller depuis le site. Un build qui plante plus tard dans le jeu se corrige en publiant un build suivant.
- Le jeu n'a pas de bouton « Quitter ». Sur le Deck, on quitte avec le bouton STEAM, puis « Quitter le jeu ».
- Le binaire Linux pèse environ 73 Mo et l'archive environ 40 Mo. Une montée de moteur télécharge donc l'archive entière.

## Tester

```bash
# Export local (modèles 4.7.1 installés sur le Mac de Julien)
godot --headless --path . --export-release "SteamDeck" exports/steamdeck/MiarritzeBorroka.x86_64

# Rendu 1280×800 (captures QA)
godot --path . --resolution 1280x800 -- --shot=/abs/deck.png --delay=3

# Paquet + manifeste locaux
tools/steamdeck/package.sh exports/steamdeck /tmp/srv 5 5-test 4.7.1
```

Auto-update de bout en bout, sans Deck : servir `/tmp/srv` avec `python3 -m http.server 8765`, puis lancer le binaire exporté dans un conteneur `docker run --platform linux/amd64 python:3.12-slim`. Le binaire prend `--headless --quit-after 600 -- --update-manifest=http://127.0.0.1:8765/manifest.json`.

Scénarios validés le 2026-10-18 :

- `.pck` plus récent installé, puis relance ;
- déjà à jour ;
- moteur différent, avec l'archive décompressée par-dessus le binaire en cours d'exécution ;
- garde-fou anti-boucle ;
- sha256 faux ;
- hors ligne ;
- dossier en lecture seule.

Install : `MIARRITZE_HOME=/tmp/fakehome MIARRITZE_MANIFEST=http://127.0.0.1:8765/manifest.json bash web/steamdeck/install.sh`.

## À faire sur un vrai Deck

- [ ] Installer depuis `/steamdeck/` en mode Bureau. Vérifier le double-clic sur le `.sh`, la fenêtre « C'est installé ! » et l'ajout à Steam par `steamos-add-to-steam`.
- [ ] Mode Jeu : plein écran 1280×800, manette (menus, combat, pause), son.
- [ ] Pousser un commit sur `main`, relancer le jeu sur le Deck, voir l'écran de mise à jour et le redémarrage.
