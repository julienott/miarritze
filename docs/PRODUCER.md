# Producer — assets, commentaires, kanban

Service privé : https://miarritze.ijulien.com/producer/

## Pour Julien

- **Connexion** : mot de passe unique. Après 5 échecs, l'adresse IP est bloquée 15 minutes. La session dure 30 jours.
- **Assets** : les catégories sont à gauche (sur iPhone, en haut). On peut aussi chercher par nom (`maia`, `idle`, `fronton`…).
  - Les catégories sont rangées en trois sections : **Gordeka** (Persos, Décor, Carte, Mannequin, Textures & modèles), **Borroka** (l'ancien jeu de combat, replié : toucher « ▸ Borroka » pour l'ouvrir) et **Audio**.
  - **Persos** (la page d'ouverture) :
    - en haut, le **récapitulatif** perso × animation : ✓ = présente (toucher un ✓ la lit en plein écran), « · » = manquante. La liste attendue est celle de `tools/gordeka/prompts_anims.json` ; les clips sur mesure à venir (`hunter_reveal`, émotes) sont en italique ;
    - puis une section par perso, dans l'ordre du casting : le profil validé à gauche, un bandeau qui liste ses animations manquantes, et toutes ses animations qui tournent. Une animation manquante est une tuile hachurée « manquante » (ou « à venir » pour un clip sur mesure). En dessous : masques de tenue et profils candidats ;
    - « Commenter les animations » ouvre la page de commentaires des animations du perso.
  - **Plein écran** : toucher une animation l'ouvre en plein écran, à la vitesse du `.json` (i/s, boucle ; une animation sans boucle marque une pause sur sa dernière image). Commandes : ◀ ▶ image par image (met en pause), ⏸ / Lire, « ‹ anim » « anim › » ; sur iPhone, **glisser** à gauche/droite change d'animation, glisser vers le haut/bas change de perso, toucher l'image met en pause. Au clavier : ← → animation, ↑ ↓ perso, `,` `.` image par image, espace pause, Échap ferme. « Fond » alterne clair, sombre et damier ; « Masque » pose le masque de tenue (en magenta) ; « Pieds » trace la ligne des pieds (`feet_anchor`) ; ⛶ passe en vrai plein écran quand le navigateur le permet (pas sur iPhone, où le lecteur occupe déjà tout l'écran). Le bouton retour du navigateur ferme le lecteur. Pense à tourner l'iPhone en paysage.
  - **Décor** : tous les objets du décor de `assets/gordeka/decor` sur damier.
    - En haut : « Sans masques » (l'image seule), « Avec masques » (violet = zone qui cache le perso, vert = emprise au sol qui bloque, orange = contact au sol ; masques pixelforge superposés pixel pour pixel), « Contrôle du jeu » (la forme réellement utilisée par le jeu). Chaque objet a aussi sa bascule « Masques : oui/non ».
    - Badges : source des masques (vert « pixelforge », orange « repli local » quand le jeu recalcule la forme lui-même, rouge « sans masque »), confiance de pixelforge, « bloque la vue », nombre d'avertissements (survol ou page de l'objet pour les lire).
    - « Sans masque seulement » ne garde que les objets sans masques pixelforge utilisés (repli ou aucun), encadrés en orange.
    - Les sols sont affichés en tuile répétée 2×2 ; en bas, la liste des éléments du décor qui n'ont pas encore d'image.
    - Toucher un objet ouvre sa page : vues sans/avec masques, contrôle du jeu, aperçu pixelforge et ombre, avec les avertissements, la caméra et les zones, et les commentaires.
  - Les profils candidats viennent de `tools/gordeka/candidats/` (copies réduites versionnées, « variante N » = `image_0(N-1)`, avec le prompt).
  - Carte : aperçu rendu depuis `map.txt` (une couleur par tuile, celles de `gk_map.gd`, zones de `zones.json` encadrées et nommées), sauf si un PNG existe dans le dossier de la carte. Mannequin : pièces du pantin, `rig.json` et chorégraphies (JSON affichés en texte). Textures & modèles : textures du décor et des `.glb`.
  - Combattants de Borroka : une section par perso, et dans chaque section les tuiles rangées par famille — animations, portraits, image de fin, projectiles, effets des spéciaux, palettes, sources. Les persos sont colorisés avec le costume 0 ; la vignette des animations joue l'attente.
  - Sur « animations », toutes les animations du perso tournent en aperçu sous le lecteur ; un clic en ouvre une dans le lecteur, où l'on peut avancer image par image avec ◀ ▶.
  - Le fond se choisit entre clair, sombre et damier ; le zoom est en pixels nets.
  - Musiques, SFX et voix ont un lecteur audio.
- **Commentaires** : sur chaque asset, choisis « Amélioration » ou « Validé », puis écris un texte (obligatoire pour une amélioration).
  - Le commentaire garde la version de l'asset et le commit du build. Si l'asset a changé depuis, il porte le badge « version précédente ».
  - L'agent répond dans le commentaire et le marque « Traité ». Tu peux le rouvrir.
  - L'onglet « Commentaires » liste tout, par défaut les commentaires ouverts seulement.
- **Kanban** : quatre colonnes, À faire → En cours → À vérifier → Fait.
  - « + Nouvelle carte » crée une feature ou un bug, avec priorité et asset lié en option. Sur un asset, « + Carte liée » préremplit l'asset.
  - Pour déplacer une carte, glisse-la (ordinateur) ou utilise les boutons ◀ ▶ (iPhone).
  - Touche une carte pour la modifier, lire les notes de l'agent ou ajouter une note.
- Le bouton ◐ bascule entre le thème clair et le thème sombre.

## Pour l'agent (terminal)

`tools/producer/cli.py` n'utilise que la bibliothèque standard de Python. Configuration :

- `PRODUCER_TOKEN` : le jeton. Sinon, il est lu dans `.producer_token` à la racine du dépôt (fichier gitignoré, le jeton seul sur la première ligne).
- `PRODUCER_URL` : l'adresse du service, par défaut `https://miarritze.ijulien.com/producer/`.

```bash
tools/producer/cli.py comments --open            # retours à traiter (--asset <id>, --json)
tools/producer/cli.py reply 12 "Bras raccourcis de 2 px (commit abc1234)" --done
tools/producer/cli.py close 12 [--reopen]
tools/producer/cli.py cards [--status todo|doing|review|done] [--full] [--json]
tools/producer/cli.py show 4                     # description + notes
tools/producer/cli.py move 4 doing               # alias : afaire, encours, averifier, fait
tools/producer/cli.py note 4 "Commencé : palette refaite"
tools/producer/cli.py add-card --type bug --title "…" [--desc …] [--priority haute] [--asset fighters/maia/sheet.png]
```

Routine conseillée :

1. Lire `comments --open` et `cards --status todo`.
2. Passer une carte en `doing` quand le travail commence.
3. Quand c'est fini, la passer en `review` avec une note : c'est à Julien de la mettre en « Fait ».
4. Répondre aux commentaires avec `reply … --done`.

Les ids d'asset sont les chemins relatifs à `assets/`, par exemple `fighters/maia/sheet.png`, qui regroupe les animations de Maia. La version d'un asset est un hash court de ses sources.

Pour une sheet, ces sources sont `sheet.png`, `palettes.png` et `anims.json`. Pour Gordeka, les animations d'un perso ont l'id `gordeka/persos/<id>/animations` (sources : les `<anim>.png` et `<anim>.json`), ses masques `gordeka/persos/<id>/masques` (les `<anim>_tenue.png`), un objet ou un sol du décor son chemin (`gordeka/decor/objets/fronton.png`, sources : l'image, ses masques et `masks.json`), la carte `maps/<carte>/map.txt` et un profil candidat son chemin dans le dépôt (`tools/gordeka/candidats/<id>/<lot>/image_00.png`). Un commentaire dont la version diffère de la version actuelle porte sur une version précédente.

### API (HTTP)

Toutes les routes passent par `index.php?r=<route>` et répondent en JSON. Authentification : `Authorization: Bearer <jeton>`, ou `X-Producer-Token: <jeton>` si Apache supprime l'en-tête Authorization.

| Méthode | Route | Effet |
|---|---|---|
| GET | `comments` (`&status=open\|done`, `&asset=`) | liste, avec `outdated` et `current_version` |
| POST | `comment` `{asset, kind: amelioration\|valide, body, context}` | ajoute un commentaire |
| POST | `comment_update` `{id, status?, reply?}` | modifie un commentaire |
| POST | `comment_delete` `{id}` | supprime un commentaire |
| GET | `cards` (`&status=`) | cartes, avec leurs `notes` |
| POST | `card` `{type, title, description?, priority?, asset?, status?}` | crée une carte |
| POST | `card_update` `{id, …}` | modifie une carte |
| POST | `card_move` `{id, status, index?}` | déplace une carte |
| POST | `card_note` `{id, body}` | ajoute une note |
| POST | `card_delete` `{id}` | supprime une carte |
| GET | `index` | index des assets |
| GET | `file&p=<chemin>` | sert un fichier listé par l'index (liste blanche) |

## Architecture

- `producer/index.php` est le point d'entrée unique. La logique est dans `lib/app.php`, le schéma SQLite dans `lib/schema.sql`, la coquille HTML dans `lib/page.html`, l'interface dans `static/`. Pas de dépendance, tout est same-origin (compatible COOP/COEP).
- `tools/producer/build.sh <dossier>` assemble le service. Il lance `build_index.py`, qui génère `files/` : les planches d'animation colorisées, les portraits colorisés, des copies des images et de l'audio, des `.mp3` si ffmpeg est présent, et `index.json`.
- Les données vivent dans `producer/data/` sur le serveur (`producer.sqlite` et les sessions). Ce dossier n'est jamais dans le build, il est exclu du rsync et de git.
- Sécurité :
  - session PHP avec cookie HttpOnly, Secure et SameSite=Strict ;
  - jeton CSRF (en-tête `X-CSRF-Token`) exigé sur toute écriture faite avec la session ;
  - limitation des échecs d'authentification (mot de passe ou jeton) à 5 par IP et par 15 minutes ;
  - requêtes SQL préparées ; aucun `innerHTML` côté client ; CSP stricte (`script-src 'self'`) ;
  - fichiers servis seulement s'ils sont listés par l'index, avec contrôle `realpath` ;
  - `.htaccess` qui refuse `data/`, `lib/`, `files/` et `config.php`.

## Mise en place (une seule fois)

Les secrets ne vont jamais dans le dépôt, qui est public. Le déploiement écrit `producer/config.php` avec `tools/producer/make_config.php`. Ce fichier ne contient que le `password_hash` du mot de passe et le sha256 du jeton.

```bash
gh secret set PRODUCER_PASSWORD                 # saisir le mot de passe à l'invite (rien dans l'historique du shell)
openssl rand -hex 32 > .producer_token          # jeton de l'agent, gardé en local (gitignoré)
gh secret set PRODUCER_TOKEN < .producer_token
```

Ensuite, n'importe quel push sur `main` (ou un lancement manuel du workflow) déploie `/producer`. Pour changer le mot de passe ou le jeton, il suffit de mettre à jour le secret et de redéployer.

Si les secrets sont absents, le workflow émet un avertissement et n'envoie pas de config ; sans config, toute connexion est refusée.

## Tester en local

```bash
OUT=/tmp/producer-site/producer
tools/producer/build.sh "$OUT" .venv/bin/python
PRODUCER_PASSWORD=test-local PRODUCER_TOKEN=tok_local_0123456789abcdefghij PRODUCER_INSECURE_COOKIE=1 \
  php tools/producer/make_config.php "$OUT/config.php"
php -S 127.0.0.1:8099 -t /tmp/producer-site &
PRODUCER_URL=http://127.0.0.1:8099/producer/ PRODUCER_TEST_PASSWORD=test-local \
  PRODUCER_TOKEN=tok_local_0123456789abcdefghij node tests/web/producer.mjs   # base vide requise
PRODUCER_TEST_PASSWORD=test-local node tests/web/producer_anims.mjs   # page d'un perso + galerie animée
PRODUCER_TEST_PASSWORD=test-local node tests/web/producer_gordeka.mjs # persos, manquantes, plein écran, décor (ordi + iPhone)
```

Le test (Chromium, 36 vérifications) couvre :

- la connexion, refusée puis acceptée ;
- un perso colorisé, un décor et une musique (y compris la requête Range) ;
- les commentaires et le XSS échappé ;
- le kanban (bouton et glisser-déposer) ;
- `cli.py` ;
- le mobile ;
- le CSRF, le jeton, la traversée de répertoire, la limitation des tentatives et la déconnexion.

Les captures vont dans `tests/out/producer/`. `php -S` ignore les `.htaccess` : les refus d'accès direct se vérifient sous Apache.
