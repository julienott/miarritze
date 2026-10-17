# Producer — assets, commentaires, kanban

Service privé : https://miarritze.ijulien.com/producer/

## Pour Julien

- **Connexion** : mot de passe unique. Après 5 échecs, l'adresse IP est bloquée 15 minutes. La session dure 30 jours.
- **Assets** : les catégories sont à gauche (sur iPhone, en haut). On peut aussi chercher par nom (`maia`, `idle`, `fronton`…).
  - La page s'ouvre sur les combattants : une section par perso (cliquer son nom n'affiche que lui), et dans chaque section les tuiles rangées par famille — animations, portraits, image de fin, projectiles, effets des spéciaux, palettes, sources. Les persos sont colorisés avec le costume 0 ; la vignette des animations joue l'attente.
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

Pour une sheet, ces sources sont `sheet.png`, `palettes.png` et `anims.json`. Un commentaire dont la version diffère de la version actuelle porte sur une version précédente.

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
