# Producer — pilotage du projet (bord, kanban, catalogue, jeu, roadmap, API)

Service privé : https://miarritze.ijulien.com/producer/

## Pour Julien

- **Connexion** : mot de passe unique. Après 5 échecs, l'adresse IP est bloquée 15 minutes. La session dure 30 jours.
- **Sections** (barre du haut ; sur iPhone, une rangée d'icônes) : **Bord**, **Kanban**, **Catalogue**, **Jeu**, **Roadmap**, **Avis**, **Aide**. Les pastilles jaunes comptent les cartes à valider (Kanban) et les avis d'asset ouverts (Avis). La page s'ouvre sur le Bord.
- **Bord** : tuiles chiffrées (à valider, refusées à retraiter, Doing, Todo et night shift, file pixelforge, avis ouverts, animations manquantes, décor sans image) qui mènent à la bonne colonne du kanban ou au bon filtre du catalogue ; les cartes en QA avec leur miniature et ✓ / ✗ ; les refus à retraiter avec leur texte ; les cartes en Doing qui ne bougent plus depuis 3 jours ; la file pixelforge du décor (au moment du build) ; l'avancement des jalons ; l'activité des 48 dernières heures.
- **Catalogue** (`#/assets`) : tous les éléments du jeu, un par un : chaque animation de chaque perso (présente, manquante ou « à venir »), profils, masques de tenue, décor des trois cartes (objets, cachettes, sorties, sols, animations du décor ; un élément repris du port par une autre carte compte pour les deux), plans des cartes, règles, options de partie, écrans de menu, données, mannequin.
  - **Grouper par** type, carte de jeu, perso, statut kanban ou zone de la carte ; filtres « Pas encore fait », « À retraiter », « En QA », « Déjà refusé », « Sans masque », « Provisoire », « Sans carte kanban », « Avis ouverts » ; recherche par mots (`louis marche`, `fronton`, `gâteaux`) ; type et carte de jeu en listes. Les choix sont retenus. « Masques visibles » pose les masques sur tout le décor (sinon au survol) ; « Récap animations » affiche le tableau perso × animation.
  - **Statut** de chaque élément, tiré du kanban : cartes liées par l'asset (et le détail d'animation, ou un titre « Louis · marche »), par les tâches du build (backlogs Plage et Parc Mazon, décor de nuit, options) ou par leur titre (« Banc vert : masque v3 »). Ordre : ↺ à retraiter, QA, en cours, Todo, Backlog, fait, sans carte. Le liseré du haut de la tuile a la couleur du statut.
  - **Fiche** d'un élément : la visionneuse (animation et plein écran, décor avec ou sans masques, contrôle du jeu, règle ou écran), et à côté (dessous sur iPhone, juste après la visionneuse) : les cartes liées (✓ / ✗ si en QA), le dernier refus, le formulaire « Amélioration / Validé » qui reporte le commentaire sur la carte choisie, ou crée une carte en Backlog sous le bon chapeau (« + Nouvelle carte en Backlog ») ; les infos (cartes de jeu, zones, taille, provisoire, masques, animation prévue, version) ; le prompt utilisé (action, expression, perso, consigne commune, retouche de recette ; pour le décor, la partie propre à l'élément et le style de la carte) ; les tâches pixelforge ; les versions vues dans les commentaires ; le fil des cartes liées.
  - **Plein écran** : toucher une animation l'ouvre en plein écran, à la vitesse du `.json` (i/s, boucle ; une animation sans boucle marque une pause sur sa dernière image). Commandes : ◀ ▶ image par image (met en pause), ⏸ / Lire, « ‹ anim » « anim › » ; sur iPhone, **glisser** à gauche/droite change d'animation, glisser vers le haut/bas change de perso, toucher l'image met en pause. Au clavier : ← → animation, ↑ ↓ perso, `,` `.` image par image, espace pause, Échap ferme. « Fond » alterne clair, sombre et damier ; « Masque » pose le masque de tenue (en magenta) ; « Pieds » trace la ligne des pieds (`feet_anchor`) ; « Comme en jeu » (activé par défaut, retenu) applique le raccord du jeu (`frame_offsets` par image, `decalage`, `echelle`, comme `gk_perso.gd`) pour montrer ce que voit le joueur, désactivé il montre la planche brute ; ⛶ passe en vrai plein écran quand le navigateur le permet (pas sur iPhone, où le lecteur occupe déjà tout l'écran). Le bouton retour du navigateur ferme le lecteur. Pense à tourner l'iPhone en paysage.
  - **Vignettes animées au survol** : au repos, chaque animation montre une image fixe (la case du milieu), chargée seulement quand elle arrive à l'écran. Elle ne s'anime qu'au survol de la souris, et s'arrête (mémoire libérée) quand la souris sort. Sur iPhone, un premier toucher anime la vignette, un second ouvre le plein écran ; une seule vignette tourne à la fois. Le lecteur plein écran, lui, joue tout seul.
- **Jeu** (`#/jeu`) : **Règles** de `rules.json` en groupes lisibles (libellé, valeur, unité, clé), avec les notes du fichier ; **Options de partie** validées (`options_partie.json`) ; **Écrans** de menu dans l'ordre du parcours, avec leur rôle (commentaire en tête du script) et leur capture (`docs/captures/ecrans`, refaites par `tools/producer/captures_ecrans.sh`) ; **Cartes de jeu** : plan, taille, zones (sombres en violet), sorties, cachettes, réglages propres, « chasseur gagne » facile / normal / malin de la version retenue, chiffres du décor (cliquables vers le catalogue), chapeau du kanban et son avancement, bilan d'équilibrage ; **Équilibrage** : les bilans de `docs/GORDEKA_EQUILIBRAGE.md`. Chaque bloc a « Kanban · commenter » (cartes liées, commentaire reporté sur une carte) ; « Cartes qui en parlent » propose les cartes dont le titre nomme l'élément, « Lier » les rattache (champ asset).
- **Roadmap** : « Par jalon » : chaque jalon avec son échéance (rouge si dépassée), sa description, une barre empilée (fait, QA, Doing, Todo, Backlog) sur toutes les cartes sans enfant du jalon (un chapeau rattaché y emmène sa famille), ce qui bloque, ses chapeaux avec leur propre barre, et « + Rattacher un chapeau ». « Modifier » édite le jalon (clos, suppression : ses cartes restent). Sans jalon, « Créer ces jalons » reprend ceux de la spec (§14). « Par chapeau » : l'arbre des chapeaux, les moins avancés d'abord. En haut, « Ce qui bloque » : refus à retraiter, Doing immobiles depuis 3 jours, échéances dépassées.
- **Aide** : ce guide en court, et toutes les routes de l'API (générées par le serveur).
- **Avis** (commentaires d'asset) : depuis la fiche d'un élément, choisis « Amélioration » ou « Validé », puis écris un texte (obligatoire pour une amélioration). Le commentaire est enregistré sur l'asset (avec sa version) et reporté sur la carte choisie (« → carte #N » dans la liste).
  - Le commentaire garde la version de l'asset et le commit du build. Si l'asset a changé depuis, il porte le badge « version précédente ».
  - L'agent répond dans le commentaire et le marque « Traité ». Tu peux le rouvrir.
  - L'onglet « Avis » liste tout, par défaut les commentaires ouverts seulement.
- **Kanban** : cinq colonnes, **Backlog → Todo → Doing → QA → Done**.
  - **Backlog** : tout ce qui est identifié (assets, gameplay…), par Claude ou par toi. En haut de la colonne, la **création rapide** : un titre suffit, le chapeau est optionnel.
  - **Todo** : ce que Claude doit passer en file. C'est toi qui priorises et qui mets une carte en Todo : Claude le voit à son prochain tour (toutes les 5 minutes environ).
  - **Doing** : en cours ou en file d'attente, pixelforge compris. **QA** : en ligne sur le site, à tester. **Done** : réglé.
  - Pour déplacer une carte, glisse-la (ordinateur, l'ordre dans la colonne compte) ou utilise ◀ ▶ (iPhone).
  - Chaque carte a un **type** en petit badge (Feature, Bug, Perso, Animation, Asset, Gameplay, Pixelforge), une priorité (haute, normale, basse) et, discrètement en haut à droite, qui l'a créée (Julien ou Claude).
  - **Chapeaux** : une carte peut avoir une carte parent, par exemple « Amaia » (type Perso) avec en enfants son image de référence et chacune de ses animations. Le chapeau montre une barre d'avancement (enfants en QA ou Done / total) et « ▸ N enfants » pour les déplier ; un enfant affiche « ↑ nom du chapeau », qui ouvre le chapeau. Les enfants se déplacent librement, chacun dans sa colonne. Trois niveaux au plus.
  - En haut du board : filtre **Chapeau** (un chapeau et toute sa famille) et **Chapeaux seulement** (les enfants sont masqués, on les voit en dépliant), et son inverse **Masquer les chapeaux** (seules les cartes sans enfant, chacune dans sa colonne, compteurs compris ; cocher l'une décoche l'autre, le choix est retenu).
  - Touche une carte pour la modifier (type, priorité, titre, description, chapeau, asset lié), voir ses enfants (« + Carte enfant » en crée un), et lire son **historique** : création, déplacements, changements, et les **commentaires** de Julien et de Claude mêlés dans l'ordre. « Commenter » envoie tout de suite.
  - **Asset lié** : sur ordinateur, la tuile montre l'asset en haut, sur toute sa largeur (proportions gardées, hauteur bornée, fond clair ou damier pour le décor) ; sur iPhone, une petite miniature. Pour une animation, elle joue au survol de la tuile (premier toucher sur la miniature en tactile, le toucher suivant ouvre la carte), une seule à la fois, arrêtée et libérée quand la souris sort ; pour un objet du décor qui a des masques, les masques se superposent au survol (toucher la miniature les bascule) : la QA se fait sans ouvrir la carte. Dans le détail de la carte, l'asset est affiché en haut, en pleine largeur (animation qui joue au survol, cliquer ouvre le plein écran ; objet du décor avec ou sans masques ; image), avec le formulaire « Amélioration / Validé » de l'asset et ses commentaires : on commente l'asset sans quitter la carte. Pour une carte d'animation, le champ **Détail** donne le nom de l'animation (`walk`) : c'est elle qui s'affiche.
  - **QA** : une carte en QA porte deux gros boutons. **✓ Accepter** la passe en Done (sur un chapeau, ses enfants encore en QA sont acceptés aussi, après confirmation). **✗ Refuser** demande un commentaire obligatoire : la carte repart en Doing avec le badge **↺ à retraiter**, qui disparaît quand Claude la remet en QA.
  - **Sur iPhone** (portrait, ou paysage) : une colonne à la fois, avec des onglets collés en haut (Backlog · Todo · Doing · QA · Done, avec leurs compteurs). On change de colonne en touchant un onglet ou en balayant l'écran à gauche ou à droite. L'onglet choisi est retenu ; à défaut, QA s'ouvre s'il y a des cartes à tester, sinon Todo. Les tuiles sont compactes (titre, badges, miniature) : une dizaine par écran en portrait. En QA, ✓ et ✗ sont sur la tuile ; ailleurs, le menu ⇄ déplace la carte vers une autre colonne. ☰ déplie les filtres et « + Nouvelle carte ». Le détail s'ouvre en plein écran, avec l'asset en haut et Accepter / Refuser collés en bas ; « ← Retour » ou un balayage vers la droite le ferme. La vue ordinateur ne change pas.
  - **Recherche et filtres** : recherche (titre, description, `#id`), type, perso (son nom dans le titre, son asset ou son chapeau), carte de jeu (asset du décor de la carte, chapeau de la carte, titre), jalon (« sans jalon » compris), chapeau ; les choix sont retenus, « Effacer les filtres » les remet à zéro.
  - **☑ Sélection** : coche des cartes (ou « Tout ce qui est affiché »), puis « Déplacer vers… », « 🌙 Night shift… », « Priorité… » ou « Jalon… » s'appliquent à toutes d'un coup (une seule requête, historisée carte par carte).
  - **Jalon et échéance** : dans le détail d'une carte (enregistrés aussitôt) ; la tuile porte ⏱ (rouge si dépassée) et ⚑ le jalon.
  - **Enregistrement** : dans le détail d'une carte, la case 🌙 Night shift, le type, la priorité et le chapeau s'enregistrent dès qu'on les change (« ✓ enregistré » s'affiche ; si l'envoi échoue, le champ revient en arrière). Le titre, la description, l'asset et le détail s'enregistrent avec « Enregistrer » : tant que ce n'est pas fait, « ● Modifications non enregistrées » s'affiche et fermer demande confirmation.
  - **🌙 Night shift** : coche « Night shift » dans le détail d'une carte (ou 🌙 à la création rapide) quand elle doit être traitée la nuit. Une carte en **Todo** avec night shift part en file la nuit (1 h – 8 h, heure de Paris), par Claude ou dans la file priorisée de pixelforge, au lieu de tout de suite. La tuile porte un badge 🌙 ; le filtre « 🌙 Night shift seulement » est dans la barre des filtres (☰ sur iPhone). Sur un chapeau, « 🌙 Appliquer le night shift aux enfants » donne à tous ses enfants l'état coché. Les cartes créées avant cette option sont sans night shift.
  - **En direct** : toutes les 10 s, le board vérifie si une nouvelle version des assets a été publiée ; si oui, les tuiles, le détail ouvert et le plein écran rechargent l'asset (signe « ↻ nouvelle version » quelques secondes). Les cartes sont relues toutes les 30 s, et toutes les 10 s quand le détail d'une carte est ouvert : un commentaire, un changement de colonne ou d'asset (`set N --asset … --detail …`) y apparaissent sans recharger, sans écraser ce que tu es en train d'écrire.
  - **⚠ glisse de N px dans la planche** : affiché sur une animation dont le perso se déplace dans la planche elle-même (tête et pieds mesurés au build, raccord du jeu compris en mode « Comme en jeu »). Le lecteur montre chaque case telle quelle : ce glissement vient de la planche ou de ses `frame_offsets`, pas de /producer.
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
tools/producer/cli.py cards [--status backlog|todo|doing|qa|done] [--parent N] [--night] [--full] [--json]   # [NIGHT] = night shift
tools/producer/cli.py show 4 [--json]            # détail, enfants, historique et commentaires
tools/producer/cli.py add-card --title "…" [--type feature|bug|perso|animation|asset|gameplay|pixelforge] \
    [--parent N] [--status backlog] [--desc …] [--priority haute] [--asset gordeka/persos/amaia/animations] [--detail walk]
tools/producer/cli.py move 4 doing               # colonnes : backlog todo doing qa done
tools/producer/cli.py comment 4 "Commencé : palette refaite"
tools/producer/cli.py qa 4 "pieds recalés sur feet_anchor"   # carte refusée et retraitée -> QA, commentaire « retraité : … (asset … version abc123) »
tools/producer/cli.py set 4 [--priority haute|normale|basse|aucune] [--parent N|0] [--title …] [--desc …] [--type …] [--asset …] [--detail walk] [--night on|off] [--milestone N|0] [--due AAAA-MM-JJ|aucune]
tools/producer/cli.py cards [--type animation] [--milestone N|none] [--asset ID] [--search texte]
tools/producer/cli.py stats [--stale-days 3] [--json]   # tableau de bord : QA, refus, Doing immobiles, échéances, jalons
tools/producer/cli.py bulk 4 5 6 [--status todo] [--night on|off] [--priority haute|aucune] [--milestone N|0]
tools/producer/cli.py milestones [--json]       # jalons et avancement
tools/producer/cli.py add-milestone --title "Contenu v1" [--due 2026-12-01] [--desc …]
tools/producer/cli.py set-milestone 2 [--title …] [--due …|aucune] [--closed on|off] [--position N]
tools/producer/cli.py asset-comment <asset> "texte" [--detail walk] [--card N] [--title …] [--parent N] [--valide]
tools/producer/cli.py routes [--json]           # toutes les routes de l'API
```

Les alias de l'ancien CLI marchent encore : `afaire` → todo, `encours` → doing, `averifier` et `review` → qa, `fait` → done ; `note` = `comment`. Toute action faite avec le jeton est signée **claude** (origine des cartes, historique, commentaires) ; celles de la session web sont signées **julien**.

Routine conseillée (boucle toutes les 5 minutes) :

1. `events --since <now du tour précédent>` : `events` écrit sur stderr la valeur `now` du serveur à repasser au tour suivant (`--json` la donne dans `now`). Regarder surtout les cartes que Julien a mises en **Todo** (sauf celles marquées `[NIGHT]` : elles attendent la nuit, 1 h – 8 h heure de Paris, de même que la file pixelforge correspondante), les événements `night` (affichés NIGHT ON / NIGHT OFF), ses **commentaires**, et les événements `refuse` (texte du refus dans `new` ; la carte est repartie en Doing « à retraiter » : la retraiter puis `qa N "ce qui a été corrigé"`) et `accepte` (carte passée en Done par Julien).
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
| GET | `cards` (`&status=`, `&parent=`, `&night=1`, `&type=`, `&milestone=<id>\|none`, `&asset=`, `&q=`) | cartes, avec `notes` (commentaires), `children`, `children_done` (QA + Done, descendants compris), `status_at` (entrée dans la colonne), `milestone_id`, `due` |
| GET | `card&id=N` | `{card, children, events}` : détail et historique (commentaires compris) |
| GET | `events&since=<epoch>` (`&card=`) | événements du board depuis `since` inclus (1000 au plus), avec `card_title`, `card_status`, et `now` |
| POST | `card` `{title, type?, description?, priority?, asset?, detail?, night?, status? (défaut backlog), parent?, milestone?, due?}` | crée une carte |
| POST | `card_update` `{id, type?, title?, description?, priority?, asset?, detail?, night?, parent? (0 = aucun), milestone? (0 = aucun), due? ("" = aucune)}` | modifie une carte (seuls les vrais changements sont historisés) |
| POST | `card_move` `{id, status, index?}` | déplace une carte (`review` accepté pour `qa`) |
| POST | `card_comment` `{id, body}` | commente une carte (alias : `card_note`) |
| POST | `card_delete` `{id}` | supprime une carte (ses enfants sont détachés) |
| POST | `card_accept` `{id}` | QA -> Done (+ descendants encore en QA) ; événements `accepte` ; renvoie `accepted` |
| POST | `card_refuse` `{id, body}` | QA -> Doing, `rework` = vrai, commentaire `kind: refus` ; événement `refuse` (`new` = texte) |
| POST | `cards_bulk` `{ids, status?, night?, priority?, milestone?}` | même changement sur 500 cartes au plus (transaction, historisé) |
| POST | `asset_comment` `{asset?, detail?, body, kind?, card?, title?, type?, parent?, context?}` | commentaire d'asset reporté sur une carte : `card` = id, `"new"` = nouvelle carte ; sans `card`, la carte non terminée liée à l'asset (même détail, ou titre « … · <libellé> »), sinon nouvelle carte en Backlog sous le chapeau le plus fréquent des cartes de l'asset ; renvoie `{comment, card, created}` |
| GET | `milestones` | jalons |
| POST | `milestone` `{title, description?, due?}` · `milestone_update` `{id, title?, description?, due?, closed?, position?}` · `milestone_delete` `{id}` | jalons (supprimer un jalon détache ses cartes) |
| GET | `stats` (`&stale_days=3`) | tableau de bord : colonnes, feuilles, à retraiter, Doing immobiles, échéances dépassées, avancement des jalons, avis ouverts, événements 24 h |
| GET | `routes` | description de toutes les routes (page Aide) |
| GET | `index` | index des assets (et, clé `gordeka` : persos, animations attendues, cartes de jeu, règles, options, écrans, liens, tâches et file pixelforge) |
| GET | `file&p=<chemin>` | sert un fichier listé par l'index (liste blanche) |

## Architecture

- `producer/index.php` est le point d'entrée unique. La logique est dans `lib/app.php`, le schéma SQLite dans `lib/schema.sql`, la coquille HTML dans `lib/page.html`, l'interface dans `static/`. Pas de dépendance, tout est same-origin (compatible COOP/COEP).
- Chaque animation a une image fixe `anim.poster` (case du milieu, `…/_poster/<anim>.png`) générée par `build_index.py` : les vignettes l'affichent en `loading="lazy"` et ne chargent la planche qu'au survol. Mesure sur la page Persos (Chromium, 1440×900, 260 animations) : avant, 139 planches chargées d'emblée (37 Mo), 139 canvas redessinés à chaque image (60 rAF/s), environ 980 Mo de mémoire pour le navigateur et la page bloquée plus de 60 s ; après, aucune planche ni canvas ni minuteur au repos, 9,5 Mo de tas JS, environ 510 Mo pour le navigateur une fois toute la page parcourue ; au survol, 1 canvas et un seul minuteur.
- Lecture case par case : chaque image dessinée est une case entière de la planche (largeur de la planche / nombre d'images). Si l'index ne correspond plus à une planche (rebuild pendant que la page est ouverte), la planche fait foi et l'index est rechargé. Chaque fichier est servi avec l'empreinte de son contenu dans l'URL (`&v=`, `versions` de `index.json`) : une planche réécrite sous le même nom change d'URL ; l'URL à jour est mise en cache (`immutable`), une empreinte périmée est toujours revalidée.
- `index_version` (GET) renvoie une version légère de `index.json` (date + taille), sondée par le board ; la page sert `static/app.js` et `app.css` avec `?v=<date>`.
- `tools/producer/build.sh <dossier>` assemble le service. Il lance `build_index.py`, qui génère `files/` : les planches d'animation colorisées, les portraits colorisés, des copies des images et de l'audio, des `.mp3` si ffmpeg est présent, et `index.json`.
- Les données vivent dans `producer/data/` sur le serveur (`producer.sqlite` et les sessions). Ce dossier n'est jamais dans le build, il est exclu du rsync et de git.
- Schéma versionné par `PRAGMA user_version` (5 actuellement). Une base de version 1 est migrée automatiquement à la première requête, dans une transaction (`BEGIN IMMEDIATE`) : colonnes `todo`, `doing`, `done` gardées, `review` → `qa` ; notes conservées (auteur `agent` → `claude`) ; nouvelles colonnes `parent_id` et `origin` (`julien` pour les cartes migrées, faute de mieux) ; historique `card_events` amorcé avec la création de chaque carte et ses commentaires existants ; les ids de cartes ne sont pas réutilisés.
- Version 3 : colonnes `cards.detail` (nom d'animation de l'asset), `cards.rework` (refusée, à retraiter, effacé quand la carte revient en QA) et `card_notes.kind` (`refus`), ajoutées automatiquement à une base v2.
- Version 4 : colonne `cards.night` (night shift, booléen), à faux pour les cartes existantes ; son changement donne un événement `night` (`old`/`new` = `off`/`on`).
- Version 5 (pilotage) : table `milestones` (titre, description, échéance, position, clos), colonnes `cards.milestone_id` (jalon, mis à NULL si le jalon est supprimé), `cards.due` (échéance `AAAA-MM-JJ` ou vide) et `comments.card_id` (carte où un commentaire d'asset a été reporté), ajoutées sans rien réécrire ; événements `jalon` (`old`/`new` = id du jalon) et `echeance`.
- Interface en plusieurs fichiers sans bundler (`static/app.js` puis `pilotage.js`, `catalogue.js`, `jeu.js`, `roadmap.js`, `bord.js`, mêmes globales) ; la page les sert tous avec `?v=<date>`. Les routes sont décrites dans `lib/routes.php` (GET `routes`).
- `build_index.py` ajoute à `index.json` le décor des trois cartes, les animations du décor, les liens et tâches pixelforge lus dans `tools/gordeka/taches_*.json`, et le gameplay de `tools/producer/jeu_index.py` (règles, options, écrans, cartes de jeu, équilibrage, jalons de la spec). Les captures des écrans viennent de `docs/captures/ecrans/<id>.png` (`tools/producer/captures_ecrans.sh`, Godot avec fenêtre).
- Historique : `card_events (card_id, at, author julien|claude, type, old, new)` avec les types `creation`, `deplacement`, `titre`, `description`, `priorite`, `type`, `asset`, `detail`, `parent`, `night`, `commentaire`, `accepte`, `refuse`, `suppression`. Pas de clé étrangère, pour que la suppression d'une carte reste dans le fil.
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
PRODUCER_TEST_PASSWORD=test-local node tests/web/producer_gordeka.mjs # catalogue : animations par perso, manquantes, plein écran, décor (ordi + iPhone)
PRODUCER_TEST_PASSWORD=test-local node tests/web/producer_pilotage.mjs # bord, catalogue, fiche, Jeu, roadmap, kanban filtré et sélection, aide (ordi + iPhone ; PRODUCER_THEME=dark)
PRODUCER_URL=http://127.0.0.1:8099/producer/ PRODUCER_TEST_PASSWORD=test-local \
  PRODUCER_TOKEN=tok_local_0123456789abcdefghij node tests/web/producer_kanban.mjs   # kanban (ordi + iPhone portrait/paysage)
```

`producer_kanban.mjs` (108 vérifications, dont la mise à jour en direct ; `PRODUCER_FILES_DIR=<build>/files` pour tester aussi la republication d'un asset) : chapeaux, historique, asset lié, Accepter/Refuser, CLI, vue mobile iPhone portrait et paysage, balayage) tourne sur une base quelconque (titres uniques). Pour tester la migration, partir d'une base de version 1 : créer `data/producer.sqlite` avec `git show f0c4e41:producer/lib/schema.sql | sqlite3 …`, y insérer les cartes « Ancienne carte à faire » (todo), « Ancien bug en cours » (doing), « Ancienne carte à vérifier » (review, avec une note `agent` puis une note `julien`) et « Ancienne carte faite » (done), puis lancer le test avec `PRODUCER_EXPECT_MIGRATION=1`. Avec plusieurs requêtes en parallèle (images), lancer `php -S` avec `PHP_CLI_SERVER_WORKERS=6`.

Le test (Chromium, 36 vérifications) couvre :

- la connexion, refusée puis acceptée ;
- un perso colorisé, un décor et une musique (y compris la requête Range) ;
- les commentaires et le XSS échappé ;
- le kanban (bouton et glisser-déposer) ;
- `cli.py` ;
- le mobile ;
- le CSRF, le jeton, la traversée de répertoire, la limitation des tentatives et la déconnexion.

Les captures vont dans `tests/out/producer/`. `php -S` ignore les `.htaccess` : les refus d'accès direct se vérifient sous Apache.
