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
  - **Vignettes animées au survol** : au repos, chaque animation montre une image fixe (la case du milieu), chargée seulement quand elle arrive à l'écran. Elle ne s'anime qu'au survol de la souris, et s'arrête (mémoire libérée) quand la souris sort. Sur iPhone, un premier toucher anime la vignette, un second ouvre le plein écran ; une seule vignette tourne à la fois. Le lecteur plein écran, lui, joue tout seul.
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
- **Kanban** : cinq colonnes, **Backlog → Todo → Doing → QA → Done**.
  - **Backlog** : tout ce qui est identifié (assets, gameplay…), par Claude ou par toi. En haut de la colonne, la **création rapide** : un titre suffit, le chapeau est optionnel.
  - **Todo** : ce que Claude doit passer en file. C'est toi qui priorises et qui mets une carte en Todo : Claude le voit à son prochain tour (toutes les 5 minutes environ).
  - **Doing** : en cours ou en file d'attente, pixelforge compris. **QA** : en ligne sur le site, à tester. **Done** : réglé.
  - Pour déplacer une carte, glisse-la (ordinateur, l'ordre dans la colonne compte) ou utilise ◀ ▶ (iPhone).
  - Chaque carte a un **type** en petit badge (Feature, Bug, Perso, Animation, Asset, Gameplay, Pixelforge), une priorité (haute, normale, basse) et, discrètement en haut à droite, qui l'a créée (Julien ou Claude).
  - **Chapeaux** : une carte peut avoir une carte parent, par exemple « Amaia » (type Perso) avec en enfants son image de référence et chacune de ses animations. Le chapeau montre une barre d'avancement (enfants en QA ou Done / total) et « ▸ N enfants » pour les déplier ; un enfant affiche « ↑ nom du chapeau », qui ouvre le chapeau. Les enfants se déplacent librement, chacun dans sa colonne. Trois niveaux au plus.
  - En haut du board : filtre **Chapeau** (un chapeau et toute sa famille) et **Chapeaux seulement** (les enfants sont masqués, on les voit en dépliant).
  - Touche une carte pour la modifier (type, priorité, titre, description, chapeau, asset lié), voir ses enfants (« + Carte enfant » en crée un), et lire son **historique** : création, déplacements, changements, et les **commentaires** de Julien et de Claude mêlés dans l'ordre. « Commenter » envoie tout de suite.
  - **Asset lié** : la tuile montre une petite miniature de l'asset. Dans le détail de la carte, l'asset est affiché en dessous (animation qui joue au survol, cliquer ouvre le plein écran ; objet du décor avec ou sans masques ; image), avec le formulaire « Amélioration / Validé » de l'asset et ses commentaires : on commente l'asset sans quitter la carte. Pour une carte d'animation, le champ **Détail** donne le nom de l'animation (`walk`) : c'est elle qui s'affiche.
  - **QA** : une carte en QA porte deux gros boutons. **✓ Accepter** la passe en Done (sur un chapeau, ses enfants encore en QA sont acceptés aussi, après confirmation). **✗ Refuser** demande un commentaire obligatoire : la carte repart en Doing avec le badge **↺ à retraiter**, qui disparaît quand Claude la remet en QA.
  - Le board se met à jour tout seul toutes les 30 secondes.
  - Sur un asset, « + Carte liée » crée une carte dans le Backlog avec l'asset préréglé.
- Le bouton ◐ bascule entre le thème clair et le thème sombre.

## Pour l'agent (terminal)

`tools/producer/cli.py` n'utilise que la bibliothèque standard de Python. Configuration :

- `PRODUCER_TOKEN` : le jeton. Sinon, il est lu dans `.producer_token` à la racine du dépôt (fichier gitignoré, le jeton seul sur la première ligne).
- `PRODUCER_URL` : l'adresse du service, par défaut `https://miarritze.ijulien.com/producer/`.

```bash
tools/producer/cli.py comments --open            # retours sur les assets (--asset <id>, --json)
tools/producer/cli.py reply 12 "Bras raccourcis de 2 px (commit abc1234)" --done
tools/producer/cli.py close 12 [--reopen]

tools/producer/cli.py events --since 5m          # TOUT ce qui a bougé sur le board (epoch, 15m, 2h, 1d, "2026-10-20 14:00") [--card N] [--json]
tools/producer/cli.py cards [--status backlog|todo|doing|qa|done] [--parent N] [--full] [--json]
tools/producer/cli.py show 4 [--json]            # détail, enfants, historique et commentaires
tools/producer/cli.py add-card --title "…" [--type feature|bug|perso|animation|asset|gameplay|pixelforge] \
    [--parent N] [--status backlog] [--desc …] [--priority haute] [--asset gordeka/persos/amaia/animations] [--detail walk]
tools/producer/cli.py move 4 doing               # colonnes : backlog todo doing qa done
tools/producer/cli.py comment 4 "Commencé : palette refaite"
tools/producer/cli.py qa 4 "pieds recalés sur feet_anchor"   # carte refusée et retraitée -> QA, commentaire « retraité : … »
tools/producer/cli.py set 4 [--priority haute|normale|basse|aucune] [--parent N|0] [--title …] [--desc …] [--type …] [--asset …] [--detail walk]
```

Les alias de l'ancien CLI marchent encore : `afaire` → todo, `encours` → doing, `averifier` et `review` → qa, `fait` → done ; `note` = `comment`. Toute action faite avec le jeton est signée **claude** (origine des cartes, historique, commentaires) ; celles de la session web sont signées **julien**.

Routine conseillée (boucle toutes les 5 minutes) :

1. `events --since <now du tour précédent>` : `events` écrit sur stderr la valeur `now` du serveur à repasser au tour suivant (`--json` la donne dans `now`). Regarder surtout les cartes que Julien a mises en **Todo**, ses **commentaires**, et les événements `refuse` (texte du refus dans `new` ; la carte est repartie en Doing « à retraiter » : la retraiter puis `qa N "ce qui a été corrigé"`) et `accepte` (carte passée en Done par Julien).
2. Lire `comments --open` (retours sur les assets).
3. Passer une carte en `doing` quand le travail commence ou part en file (pixelforge compris), avec un `comment` si utile.
4. Quand c'est en ligne, la passer en `qa` avec un commentaire qui dit quoi tester : c'est à Julien de la mettre en Done.
5. Ce qui est repéré en route va dans le Backlog (`add-card`, `--parent` pour l'accrocher à son chapeau, par exemple le perso).

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
| GET | `cards` (`&status=`, `&parent=`) | cartes, avec `notes` (commentaires), `children`, `children_done` (QA + Done, descendants compris) |
| GET | `card&id=N` | `{card, children, events}` : détail et historique (commentaires compris) |
| GET | `events&since=<epoch>` (`&card=`) | événements du board depuis `since` inclus (1000 au plus), avec `card_title`, `card_status`, et `now` |
| POST | `card` `{title, type?, description?, priority?, asset?, detail?, status? (défaut backlog), parent?}` | crée une carte |
| POST | `card_update` `{id, type?, title?, description?, priority?, asset?, detail?, parent? (0 = aucun)}` | modifie une carte (seuls les vrais changements sont historisés) |
| POST | `card_move` `{id, status, index?}` | déplace une carte (`review` accepté pour `qa`) |
| POST | `card_comment` `{id, body}` | commente une carte (alias : `card_note`) |
| POST | `card_delete` `{id}` | supprime une carte (ses enfants sont détachés) |
| POST | `card_accept` `{id}` | QA -> Done (+ descendants encore en QA) ; événements `accepte` ; renvoie `accepted` |
| POST | `card_refuse` `{id, body}` | QA -> Doing, `rework` = vrai, commentaire `kind: refus` ; événement `refuse` (`new` = texte) |
| GET | `index` | index des assets |
| GET | `file&p=<chemin>` | sert un fichier listé par l'index (liste blanche) |

## Architecture

- `producer/index.php` est le point d'entrée unique. La logique est dans `lib/app.php`, le schéma SQLite dans `lib/schema.sql`, la coquille HTML dans `lib/page.html`, l'interface dans `static/`. Pas de dépendance, tout est same-origin (compatible COOP/COEP).
- Chaque animation a une image fixe `anim.poster` (case du milieu, `…/_poster/<anim>.png`) générée par `build_index.py` : les vignettes l'affichent en `loading="lazy"` et ne chargent la planche qu'au survol. Mesure sur la page Persos (Chromium, 1440×900, 260 animations) : avant, 139 planches chargées d'emblée (37 Mo), 139 canvas redessinés à chaque image (60 rAF/s), environ 980 Mo de mémoire pour le navigateur et la page bloquée plus de 60 s ; après, aucune planche ni canvas ni minuteur au repos, 9,5 Mo de tas JS, environ 510 Mo pour le navigateur une fois toute la page parcourue ; au survol, 1 canvas et un seul minuteur.
- `tools/producer/build.sh <dossier>` assemble le service. Il lance `build_index.py`, qui génère `files/` : les planches d'animation colorisées, les portraits colorisés, des copies des images et de l'audio, des `.mp3` si ffmpeg est présent, et `index.json`.
- Les données vivent dans `producer/data/` sur le serveur (`producer.sqlite` et les sessions). Ce dossier n'est jamais dans le build, il est exclu du rsync et de git.
- Schéma versionné par `PRAGMA user_version` (2 actuellement). Une base de version 1 est migrée automatiquement à la première requête, dans une transaction (`BEGIN IMMEDIATE`) : colonnes `todo`, `doing`, `done` gardées, `review` → `qa` ; notes conservées (auteur `agent` → `claude`) ; nouvelles colonnes `parent_id` et `origin` (`julien` pour les cartes migrées, faute de mieux) ; historique `card_events` amorcé avec la création de chaque carte et ses commentaires existants ; les ids de cartes ne sont pas réutilisés.
- Version 3 : colonnes `cards.detail` (nom d'animation de l'asset), `cards.rework` (refusée, à retraiter, effacé quand la carte revient en QA) et `card_notes.kind` (`refus`), ajoutées automatiquement à une base v2.
- Historique : `card_events (card_id, at, author julien|claude, type, old, new)` avec les types `creation`, `deplacement`, `titre`, `description`, `priorite`, `type`, `asset`, `detail`, `parent`, `commentaire`, `accepte`, `refuse`, `suppression`. Pas de clé étrangère, pour que la suppression d'une carte reste dans le fil.
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
PRODUCER_URL=http://127.0.0.1:8099/producer/ PRODUCER_TEST_PASSWORD=test-local \
  PRODUCER_TOKEN=tok_local_0123456789abcdefghij node tests/web/producer_kanban.mjs   # kanban (ordi + iPhone portrait/paysage)
```

`producer_kanban.mjs` (46 vérifications : chapeaux, historique, asset lié, Accepter/Refuser, CLI, iPhone) tourne sur une base quelconque (titres uniques). Pour tester la migration, partir d'une base de version 1 : créer `data/producer.sqlite` avec `git show f0c4e41:producer/lib/schema.sql | sqlite3 …`, y insérer les cartes « Ancienne carte à faire » (todo), « Ancien bug en cours » (doing), « Ancienne carte à vérifier » (review, avec une note `agent` puis une note `julien`) et « Ancienne carte faite » (done), puis lancer le test avec `PRODUCER_EXPECT_MIGRATION=1`. Avec plusieurs requêtes en parallèle (images), lancer `php -S` avec `PHP_CLI_SERVER_WORKERS=6`.

Le test (Chromium, 36 vérifications) couvre :

- la connexion, refusée puis acceptée ;
- un perso colorisé, un décor et une musique (y compris la requête Range) ;
- les commentaires et le XSS échappé ;
- le kanban (bouton et glisser-déposer) ;
- `cli.py` ;
- le mobile ;
- le CSRF, le jeton, la traversée de répertoire, la limitation des tentatives et la déconnexion.

Les captures vont dans `tests/out/producer/`. `php -S` ignore les `.htaccess` : les refus d'accès direct se vérifient sous Apache.
