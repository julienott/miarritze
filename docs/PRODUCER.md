# Producer — le board de production (local, Tailscale)

Référencé par GDD-BLACKOUT.md §14.2 (décision) et §15 (roadmap). Depuis le 24/10, le board tourne sur le
Mac de Julien et n'existe plus en ligne :

- **Board** : https://squid.tailbeda4d.ts.net:10000/producer/ ; **jeu de QA** : https://squid.tailbeda4d.ts.net:10000/jeu/
  (joignables seulement des appareils du tailnet de Julien ; pas de mot de passe, Tailscale fait foi).
- **Prod** : https://miarritze.ijulien.com/ (le jeu seul).
- Le Mac doit être allumé et éveillé pour que le board, le jeu de QA et les watchers tournent.

## Les colonnes et leurs règles de passage

| Colonne | Ce que ça veut dire | Qui y met une carte | Ce qui se passe ensuite |
|---|---|---|---|
| **Backlog** | identifié, pas décidé | Julien ou l'agent | rien |
| **Todo** | accord de Julien pour lancer le travail | **Julien seul** (ou l'agent sur son ordre explicite) | le watcher la prend (voir plus bas) |
| **Doing** | en cours : en file chez pixelforge, ou travail de l'agent | le watcher (pixelforge) ou l'agent (code) | suivi automatique |
| **QA** | livré, intégré **dans le jeu de QA local** (/jeu/), à tester | le watcher, après le build de QA ; l'agent pour le code | Julien : ✓ ou ✗ |
| **Validé** | accepté par Julien, part au prochain déploiement | ✓ Accepter (Julien) | mise en prod groupée |
| **En prod** | en ligne sur miarritze.ijulien.com | le watcher, après le déploiement réussi | fini |

- Le dialogue de refus a deux boutons, avec un commentaire obligatoire (ce qui ne va pas, ce qu'il faut améliorer) :
  - **✗ Refuser** renvoie la carte en haut du Backlog avec ↺ « à retraiter » : c'est un travail pour l'agent
    (nouveau prompt, retouche), relancé quand la carte repasse en Todo ;
  - **↻ Refuser et refaire** (Julien, 24/10) la met en haut du Todo, ↺ « à retraiter ». Le watcher la redemande à
    pixelforge avec une autre graine, depuis le profil déjà validé : une animation garde la base ou l'expression
    qui lui sert de socle, une expression garde la base ; seul l'élément refusé est refait (l'ancienne tâche est
    notée dans `refaites` d'iterations.json). Une carte refusée remise en Todo à la main fait de même.
  Dès qu'une nouvelle tâche pixelforge est intégrée pour elle, la carte revient seule en QA.
- **Carte à commande** (Julien, 24/10) : si sa description contient des lignes `$ <outil> …`, le watcher les
  lance quand la carte est en Todo (outils du dépôt seulement : `tools/blackout`, `tools/pf`, `tools/producer`,
  `.py` ou `.sh`, sans shell), écrit la sortie en commentaire et passe la carte en Doing. Il suit les tâches
  pixelforge dont la sortie donne l'id ; quand elles sont finies, il lance les lignes `$ apres: <outil> …`
  (intégration), puis le build de QA, puis la carte passe en QA. `$ attend: #N` retient la carte en Todo tant
  que la carte N n'est pas en QA. Exemple :
  ```
  $ attend: #1180
  $ tools/blackout/rereduit.py louis run --prio high
  $ apres: tools/blackout/iteration.py integre louis
  ```
- **Chapeaux** : leur colonne suit leurs enfants (la plus basse ; Doing dès qu'un enfant est commencé). Mettre
  un chapeau en Todo y emmène tous ses enfants du Backlog. ✓ sur un chapeau valide aussi ses enfants en QA.
- **Une carte par élément** : chaque perso, PNJ, animal ou boss a son chapeau (asset
  `blackout/<famille>/<id>/animations`) ; dessous, une carte par base (`detail` = `base`), par expression
  (`expr:<clé>`) et par animation (`run`, `victoire`…). Les chapeaux de famille (Persos, PNJ et animaux, Boss)
  les regroupent.
- **Roadmap** : les jalons du board sont ceux de GDD §15 (`R0`…`R8`, titre « R2 · … »), dans le même ordre.
  On change la roadmap dans le GDD, puis `tools/producer/reorganise_board.py` met le board à jour (idempotent :
  rien n'est dupliqué, aucune colonne ne recule).
- **keep** : toute tâche pixelforge d'une carte en Doing, QA, Validé ou En prod est marquée `keep` (jamais purgée).
  Les tâches figurent sur la carte (« Tâches pixelforge », 📌 = gardée).

## Les automatismes (sans agent, sans token)

Le watcher `tools/producer/studio.py` fait un tour par minute (journal `.studio/studio.log`) :

1. **Todo → Doing** : une carte de base, d'expression ou d'animation d'un perso ou d'un PNJ part en file
   chez pixelforge dès que ce dont elle dépend est prêt : base neutre → base avec l'expression de l'animation
   (§8.5) → animation, puis réduction pixel (`tools/blackout/iteration.py`). Priorité : haute si la carte
   est en priorité haute, nuit si 🌙, sinon normale. Les persos se finissent l'un après l'autre, dans
   l'ordre de la colonne.
2. **Doing** : statuts des tâches recopiés sur la carte ; une tâche échouée ou annulée est redéposée (2 essais,
   puis un commentaire demande l'agent) ; une tâche finie est **intégrée en local** dans
   `assets/blackout/<famille>/<id>/` (sans commit).
3. **Build de QA** : après une intégration, tests (`bk_tests.gd`), export web dans `.studio/site/jeu` et index
   du board ; les cartes intégrées passent **en QA**. En échec, rien ne bouge et le Bord affiche l'erreur.
4. **Mise en prod** : 10 min après le dernier ✓ (pour grouper), tests, puis commit et push des **seuls fichiers
   des cartes validées** (pour une animation : ses planches, le `set.json` et son entrée dans
   `animations.json`, le reste du fichier restant celui de la prod), lancement de `deploy.yml`, suivi du run ;
   réussi, les cartes passent **En prod**. En échec, elles restent en Validé et le Bord l'affiche ; un nouvel
   ✓ relance la tentative.
5. Boss, animaux et fantôme ne sont pas encore en itérations : mis en Todo, ils reçoivent un commentaire et
   l'agent les lance à la main.

Les cartes de code (feature, gameplay, bug) ne sont pas traitées par le watcher : l'agent les passe en Doing,
puis en QA une fois le code commité et le jeu de QA reconstruit (`studio.py --un-tour` ou le prochain tour).

## Installation et exploitation

- Config du board local (`.studio/site/producer/config.php`, écrite par `make_config.php` avec
  `PRODUCER_TAILSCALE=1`) : `tailscale_auth` vrai, pas de mot de passe, sha256 du jeton de l'agent. Une requête
  venue de 127.0.0.1 avec l'en-tête `Tailscale-User-Login` (posé par `tailscale serve`) est connectée comme
  Julien ; sans l'en-tête, 401. Le serveur n'écoute que sur 127.0.0.1.
- Schéma v6 : colonne `valide`, colonne `jobs` (tâches pixelforge d'une carte, écrites par le watcher :
  `[{"id","role","label","status","keep"}]`) ; route `GET studio` (`data/studio.json` : `qa_build`, `deploy`),
  affichée sur le Bord.

```bash
tools/producer/studio_installe.sh        # board + config + launchd (serveur, watcher) + tailscale serve
launchctl kickstart -k gui/$(id -u)/com.miarritze.studio   # relancer le watcher
tail -f .studio/studio.log               # ce que fait le watcher
tools/producer/reorganise_board.py       # roadmap du GDD → jalons et cartes du board
```

- `.studio/` (gitignoré) : `site/producer` (board, base `data/producer.sqlite`, `data/studio.json`),
  `site/jeu` (jeu de QA), `studio_etat.json`, journaux, `sauvegardes/` (export du board en ligne du 24/10).
- `cli.py` vise le board local (`PRODUCER_URL` par défaut `http://127.0.0.1:8099/producer/`), même jeton.
- Migration (faite le 24/10) : `exporte_prod.py` (sauvegarde par l'API) puis `importe_local.py` (ids conservés).

---

*La suite décrit l'interface et l'API du board (inchangées, sauf les colonnes Validé et En prod et
l'accès Tailscale).*

## Pour Julien

- **Connexion** : mot de passe unique. Après 5 échecs, l'adresse IP est bloquée 15 minutes. La session dure 30 jours.
- **Sections** (barre du haut ; sur iPhone, une rangée d'icônes) : **Bord**, **Kanban**, **Catalogue**, **Jeu**, **Roadmap**, **Avis**, **Aide**. Les pastilles jaunes comptent les cartes à valider (Kanban) et les avis d'asset ouverts (Avis). La page s'ouvre sur le Bord.
- **Bord** : tuiles chiffrées (à valider, refusées à retraiter, Doing, Todo et night shift, file pixelforge, avis ouverts, animations manquantes, décor sans image) qui mènent à la bonne colonne du kanban ou au bon filtre du catalogue ; les cartes en QA avec leur miniature et ✓ / ✗ ; les refus à retraiter avec leur texte ; les cartes en Doing qui ne bougent plus depuis 3 jours ; la file pixelforge du décor (au moment du build) ; l'avancement des jalons ; l'activité des 48 dernières heures.
- **Catalogue** (`#/assets`) : tous les éléments du jeu, un par un : chaque animation de chaque perso (présente, manquante ou « à venir »), profils, masques de tenue, décor des trois cartes (objets, cachettes, sorties, sols, animations du décor ; un élément repris du port par une autre carte compte pour les deux), plans des cartes, règles, options de partie, écrans de menu, données, mannequin.
  - **Grouper par** type, carte de jeu, perso, statut kanban ou zone de la carte ; filtres « Pas encore fait », « À retraiter », « En QA », « Déjà refusé », « Sans masque », « Provisoire », « Sans carte kanban », « Avis ouverts » ; recherche par mots (`louis marche`, `fronton`, `gâteaux`) ; type et carte de jeu en listes. Les choix sont retenus. « Masques visibles » pose les masques sur tout le décor (sinon au survol) ; « Récap animations » affiche le tableau perso × animation.
  - **Statut** de chaque élément, tiré du kanban : cartes liées par l'asset (et le détail d'animation, ou un titre « Louis · marche »), par les tâches du build (backlogs Plage et Parc Mazon, décor de nuit, options) ou par leur titre (« Banc vert : masque v3 »). Ordre : ↺ à retraiter, QA, en cours, Todo, Backlog, fait, sans carte. Le liseré du haut de la tuile a la couleur du statut.
  - **Fiche** d'un élément : la visionneuse (animation et plein écran, décor avec ou sans masques, contrôle du jeu, règle ou écran), et à côté (dessous sur iPhone, juste après la visionneuse) : les cartes liées (✓ / ✗ si en QA), le dernier refus, le formulaire « Amélioration / Validé » qui reporte le commentaire sur la carte choisie, ou crée une carte en Backlog sous le bon chapeau (« + Nouvelle carte en Backlog ») ; les infos (cartes de jeu, zones, taille, provisoire, masques, animation prévue, version) ; le prompt utilisé (action, expression, perso, consigne commune, retouche de recette ; pour le décor, la partie propre à l'élément et le style de la carte) ; les tâches pixelforge ; les versions vues dans les commentaires ; le fil des cartes liées.
  - **Plein écran** : toucher une animation l'ouvre en plein écran, à la vitesse du `.json` (i/s, boucle ; une animation sans boucle marque une pause sur sa dernière image). Commandes : ◀ ▶ image par image (met en pause), ⏸ / Lire, « ‹ anim » « anim › » ; sur iPhone, **glisser** à gauche/droite change d'animation, glisser vers le haut/bas change de perso, toucher l'image met en pause. Au clavier : ← → animation, ↑ ↓ perso, `,` `.` image par image, espace pause, Échap ferme. « Fond » alterne clair, sombre et damier ; « Masque » pose le masque de tenue (en magenta) ; « Pieds » trace la ligne des pieds (`feet_anchor`) ; « Comme en jeu » (activé par défaut, retenu) applique le raccord du jeu (`frame_offsets` par image, `decalage`, `echelle`, comme `bk_perso.gd`) pour montrer ce que voit le joueur, désactivé il montre la planche brute ; ⛶ passe en vrai plein écran quand le navigateur le permet (pas sur iPhone, où le lecteur occupe déjà tout l'écran). Le bouton retour du navigateur ferme le lecteur. Pense à tourner l'iPhone en paysage.
  - **Vignettes animées au survol** : au repos, chaque animation montre une image fixe (la case du milieu), chargée seulement quand elle arrive à l'écran. Elle ne s'anime qu'au survol de la souris, et s'arrête (mémoire libérée) quand la souris sort. Sur iPhone, un premier toucher anime la vignette, un second ouvre le plein écran ; une seule vignette tourne à la fois. Le lecteur plein écran, lui, joue tout seul.
- **Jeu** (`#/jeu`) : **Règles** de `rules.json` en groupes lisibles (libellé, valeur, unité, clé), avec les notes du fichier ; **Options de partie** validées (`options_partie.json`) ; **Écrans** de menu dans l'ordre du parcours, avec leur rôle (commentaire en tête du script) et leur capture (`docs/captures/ecrans`, refaites par `tools/producer/captures_ecrans.sh`) ; **Cartes de jeu** : plan, taille, zones (sombres en violet), sorties, cachettes, réglages propres, « chasseur gagne » facile / normal / malin de la version retenue, chiffres du décor (cliquables vers le catalogue), chapeau du kanban et son avancement, bilan d'équilibrage ; **Équilibrage** : les bilans de `archive/2026-10-22-docs-gordeka/GORDEKA_EQUILIBRAGE.md`. Chaque bloc a « Kanban · commenter » (cartes liées, commentaire reporté sur une carte) ; « Cartes qui en parlent » propose les cartes dont le titre nomme l'élément, « Lier » les rattache (champ asset).
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
  - **QA** : une carte en QA porte deux gros boutons. **✓ Accepter** la passe en Done (sur un chapeau, ses enfants encore en QA sont acceptés aussi, après confirmation). **✗ Refuser** ou **↻ Refuser et refaire** demandent un commentaire obligatoire : la carte repart en Backlog (ou en Todo, redemandée à pixelforge) avec le badge **↺ à retraiter**, qui disparaît quand elle revient en QA.
  - **Sur iPhone** (portrait, ou paysage) : une colonne à la fois, avec des onglets collés en haut (Backlog · Todo · Doing · QA · Done, avec leurs compteurs). On change de colonne en touchant un onglet ou en balayant l'écran à gauche ou à droite. L'onglet choisi est retenu ; à défaut, QA s'ouvre s'il y a des cartes à tester, sinon Todo. Les tuiles sont compactes (titre, badges, miniature) : une dizaine par écran en portrait. En QA, ✓ et ✗ sont sur la tuile ; ailleurs, le menu ⇄ déplace la carte vers une autre colonne. ☰ déplie les filtres et « + Nouvelle carte ». Le détail s'ouvre en plein écran, avec l'asset en haut et Accepter / Refuser collés en bas ; « ← Retour » ou un balayage vers la droite le ferme. La vue ordinateur ne change pas.
  - **Recherche et filtres** : recherche (titre, description, `#id`), type, perso (son nom dans le titre, son asset ou son chapeau), carte de jeu (asset du décor de la carte, chapeau de la carte, titre), jalon (« sans jalon » compris), chapeau ; les choix sont retenus, « Effacer les filtres » les remet à zéro.
  - **☑ Sélection** : coche des cartes (ou « Tout ce qui est affiché »), puis « Déplacer vers… », « 🌙 Night shift… », « Priorité… » ou « Jalon… » s'appliquent à toutes d'un coup (une seule requête, historisée carte par carte).
  - **Jalon et échéance** : dans le détail d'une carte (enregistrés aussitôt) ; la tuile porte ⏱ (rouge si dépassée) et ⚑ le jalon.
  - **Enregistrement** : dans le détail d'une carte, la case 🌙 Night shift, le type, la priorité et le chapeau s'enregistrent dès qu'on les change (« ✓ enregistré » s'affiche ; si l'envoi échoue, le champ revient en arrière). Le titre, la description, l'asset et le détail s'enregistrent avec « Enregistrer » : tant que ce n'est pas fait, « ● Modifications non enregistrées » s'affiche et fermer demande confirmation.
  - **🌙 Night shift** : coche « Night shift » dans le détail d'une carte (ou 🌙 à la création rapide) quand elle doit être traitée la nuit. Une carte en **Todo** avec night shift part en file la nuit (1 h – 8 h, heure de Paris), par Claude ou dans la file priorisée de pixelforge, au lieu de tout de suite. La tuile porte un badge 🌙 ; le filtre « 🌙 Night shift seulement » est dans la barre des filtres (☰ sur iPhone). Sur un chapeau, « 🌙 Appliquer le night shift aux enfants » donne à tous ses enfants l'état coché. Les cartes créées avant cette option sont sans night shift.
  - **En direct** : toutes les 10 s, le board vérifie si une nouvelle version des assets a été publiée ; si oui, les tuiles, le détail ouvert et le plein écran rechargent l'asset (signe « ↻ nouvelle version » quelques secondes). Les cartes sont relues toutes les 30 s, et toutes les 10 s quand le détail d'une carte est ouvert : un commentaire, un changement de colonne ou d'asset (`set N --asset … --detail …`) y apparaissent sans recharger, sans écraser ce que tu es en train d'écrire.
  - **⚠ glisse de N px dans la planche** : affiché sur une animation dont le perso se déplace dans la planche elle-même (tête et pieds mesurés au build, raccord du jeu compris en mode « Comme en jeu »). Le lecteur montre chaque case telle quelle : ce glissement vient de la planche ou de ses `frame_offsets`, pas de /producer.
  - Sur un asset, « + Carte liée » crée une carte dans le Backlog avec l'asset préréglé.
- **Recette d'un perso (carte chapeau)** : ouvre la carte chapeau du perso (type **Perso**, asset `blackout/persos/<id>/animations` sans détail ; une carte Perso sans asset retrouve son set par l'id dans le titre, « Perso : Louis »). Le détail montre toute la recette, sans ouvrir de carte d'animation :
  - en tête : nom du set, badge **PLACEHOLDER** (rose) si `set.json` porte `"placeholder": true`, nombre d'éléments, « HD disponible » ou « 32 px seulement », le prompt (description et signature) et les **avertissements** de `set.json → controls.warnings` (32 px, puis HD) ;
  - le **profil** et le **portrait**, puis une fiche par **animation**, chacune animée en 32 px agrandi net (×3 sur ordinateur, ×2 sur iPhone) et en HD à côté si le build a la HD (dossier local `hd/`) ; dessous : libellé, nom de l'élément, ce qu'on doit voir, l'action demandée au prompt, l'objet, le clip Quaternius, images, i/s, boucle ou une fois ;
  - **💬 Commenter** sous chaque animation : « Amélioration / Validé » + texte ; le commentaire est enregistré sur l'asset avec `detail` = l'élément (contexte `anim : <élément>`) et **reporté sur la carte chapeau** ouverte. Les commentaires déjà posés sur l'élément s'affichent sous lui ; ceux sur l'ensemble du set, en bas. Contrairement aux autres cartes, une amélioration **ne sort pas** la carte Perso de QA (Julien 23/10) : il commente élément par élément et décide seul du renvoi avec **✗ Refuser** ; Claude ne renvoie alors en file pixelforge que les éléments commentés (GDD §14.1) ;
  - ⛶ ouvre le lecteur plein écran sur l'élément (image par image, ligne des pieds) ; « Pause », « Fond » (clair, sombre, damier) et « HD : oui/non » valent pour toute la galerie. Les animations ne tournent que quand elles sont à l'écran et s'arrêtent à la fermeture.
  - Même chose pour le fantôme commun (`blackout/fantome/fantome/animations`), les PNJ (`blackout/pnj/<id>/animations`), les animaux (`blackout/animaux/<id>/…`) et les boss (`blackout/boss/<id>/…`, cases de 128).
  - **Cartes automatiques** : depuis le 24/10, c'est le watcher `studio.py` qui crée et déplace les cartes (voir plus haut) ; `reorganise_board.py` crée le chapeau et les cartes de chaque set.
- Le bouton ◐ bascule entre le thème clair et le thème sombre.

## Pour l'agent (terminal)

`tools/producer/cli.py` n'utilise que la bibliothèque standard de Python. Configuration :

- `PRODUCER_TOKEN` : le jeton. Sinon, il est lu dans `.producer_token` à la racine du dépôt (fichier gitignoré, le jeton seul sur la première ligne).
- `PRODUCER_URL` : l'adresse du service, par défaut `http://127.0.0.1:8099/producer/` (board local).

```bash
tools/producer/cli.py comments --open            # retours sur les assets (--asset <id>, --json)
tools/producer/cli.py reply 12 "Bras raccourcis de 2 px (commit abc1234)" --done
tools/producer/cli.py close 12 [--reopen]

tools/producer/cli.py events --since 5m          # TOUT ce qui a bougé sur le board (epoch, 15m, 2h, 1d, "2026-10-20 14:00") [--card N] [--json]
tools/producer/cli.py cards [--status backlog|todo|doing|qa|done] [--parent N] [--night] [--full] [--json]   # [NIGHT] = night shift
tools/producer/cli.py show 4 [--json]            # détail, enfants, historique et commentaires
tools/producer/cli.py add-card --title "…" [--type feature|bug|perso|animation|asset|gameplay|pixelforge] \
    [--parent N] [--status backlog] [--desc …] [--priority haute] [--asset blackout/persos/amaia/animations] [--detail walk]
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

Pour une sheet, ces sources sont `sheet.png`, `palettes.png` et `anims.json`. Pour Blackout, les animations d'un perso ont l'id `blackout/persos/<id>/animations` (character set pixelforge du 23/10 : sources `px32/set.json`, `px32/animations.json` et les `px32/<élément>_sheet.png` ; la HD locale `hd/` est affichée mais n'entre pas dans la version ; ancien format : les `<anim>.png` et `<anim>.json`) ; de même `blackout/fantome/fantome/animations`, `blackout/pnj/<id>/animations`, `blackout/animaux/<id>/animations`, `blackout/boss/<id>/animations`. Chaque élément de l'index porte `libelle`, `description` (ce qu'on doit voir, GDD §8.1, §4.5, §8.3, §8.4), `action`, `objet` (style_party_hard.json pour `idle_long` et les casts, pnj.json pour les PNJ), `clip` (celui de `set.json` s'il y est), `frames`, `fps`, `loop`, la planche 32 px et `hd` ; l'asset porte `set` (famille, nom, placeholder, avertissements de `controls.warnings`). Ses masques (ancien format) : `blackout/persos/<id>/masques` (les `<anim>_tenue.png`) ; un objet ou un sol du décor son chemin (`blackout/decor/objets/fronton.png`, sources : l'image, ses masques et `masks.json`), la carte `maps/<carte>/map.txt` et un profil candidat son chemin dans le dépôt (`tools/blackout/candidats/<id>/<lot>/image_00.png`). Un commentaire dont la version diffère de la version actuelle porte sur une version précédente.

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
| POST | `card_refuse` `{id, body, refaire?}` | QA -> sommet du Backlog (avec `refaire` : du Todo), `rework` = vrai, commentaire `kind: refus` ; événement `refuse` (`new` = texte, `old` = `qa` ou `qa>todo`) |
| POST | `cards_bulk` `{ids, status?, night?, priority?, milestone?}` | même changement sur 500 cartes au plus (transaction, historisé) |
| POST | `asset_comment` `{asset?, detail?, body, kind?, card?, title?, type?, parent?, context?}` | commentaire d'asset reporté sur une carte : `card` = id, `"new"` = nouvelle carte ; sans `card`, la carte non terminée liée à l'asset (même détail, ou titre « … · <libellé> »), sinon nouvelle carte en Backlog sous le chapeau le plus fréquent des cartes de l'asset ; renvoie `{comment, card, created}` |
| GET | `milestones` | jalons |
| POST | `milestone` `{title, description?, due?}` · `milestone_update` `{id, title?, description?, due?, closed?, position?}` · `milestone_delete` `{id}` | jalons (supprimer un jalon détache ses cartes) |
| GET | `stats` (`&stale_days=3`) | tableau de bord : colonnes, feuilles, à retraiter, Doing immobiles, échéances dépassées, avancement des jalons, avis ouverts, événements 24 h |
| GET | `routes` | description de toutes les routes (page Aide) |
| GET | `index` | index des assets (et, clé `blackout` : persos, animations attendues, cartes de jeu, règles, options, écrans, liens, tâches et file pixelforge) |
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
- `build_index.py` ajoute à `index.json` le décor des trois cartes, les animations du décor, les liens et tâches pixelforge lus dans `tools/blackout/taches_*.json`, et le gameplay de `tools/producer/jeu_index.py` (règles, options, écrans, cartes de jeu, équilibrage, jalons de la spec). Les captures des écrans viennent de `docs/captures/ecrans/<id>.png` (`tools/producer/captures_ecrans.sh`, Godot avec fenêtre).
- Historique : `card_events (card_id, at, author julien|claude, type, old, new)` avec les types `creation`, `deplacement`, `titre`, `description`, `priorite`, `type`, `asset`, `detail`, `parent`, `night`, `commentaire`, `accepte`, `refuse`, `suppression`. Pas de clé étrangère, pour que la suppression d'une carte reste dans le fil.
- Sécurité :
  - session PHP avec cookie HttpOnly, Secure et SameSite=Strict ;
  - jeton CSRF (en-tête `X-CSRF-Token`) exigé sur toute écriture faite avec la session ;
  - limitation des échecs d'authentification (mot de passe ou jeton) à 5 par IP et par 15 minutes ;
  - requêtes SQL préparées ; aucun `innerHTML` côté client ; CSP stricte (`script-src 'self'`) ;
  - fichiers servis seulement s'ils sont listés par l'index, avec contrôle `realpath` ;
  - `.htaccess` qui refuse `data/`, `lib/`, `files/` et `config.php`.

## Mise en place (une seule fois)

Le jeton de l'agent est dans `.producer_token` (gitignoré ; `openssl rand -hex 32 > .producer_token` pour en
créer un). `tools/producer/studio_installe.sh` en écrit le hachage dans la config du board local. Plus de
secrets GitHub ni de déploiement de /producer (supprimé du serveur le 24/10).

## Tester en local

```bash
OUT=/tmp/producer-site/producer
tools/producer/build.sh "$OUT" .venv/bin/python
PRODUCER_PASSWORD=test-local PRODUCER_TOKEN=tok_local_0123456789abcdefghij PRODUCER_INSECURE_COOKIE=1 \
  php tools/producer/make_config.php "$OUT/config.php"
php -S 127.0.0.1:8099 -t /tmp/producer-site &
PRODUCER_URL=http://127.0.0.1:8099/producer/ PRODUCER_TEST_PASSWORD=test-local \
  PRODUCER_TOKEN=tok_local_0123456789abcdefghij node tests/web/producer.mjs   # base vide requise
PRODUCER_TEST_PASSWORD=test-local node tests/web/producer_blackout.mjs # character sets (persos, fantôme, PNJ, animaux, boss), plein écran, recette de Louis en carte chapeau, placeholder (ordi + iPhone ; crée une carte et un commentaire : base locale seulement)
PRODUCER_TEST_PASSWORD=test-local node tests/web/producer_pilotage.mjs # bord, catalogue, fiche, Jeu, roadmap, kanban filtré et sélection, aide (ordi + iPhone ; PRODUCER_THEME=dark)
PRODUCER_URL=http://127.0.0.1:8099/producer/ PRODUCER_TEST_PASSWORD=test-local \
  PRODUCER_TOKEN=tok_local_0123456789abcdefghij node tests/web/producer_kanban.mjs   # kanban (ordi + iPhone portrait/paysage)
```

`producer_kanban.mjs` (136 vérifications ; `PRODUCER_TAILSCALE_URL` = une 2e instance avec `tailscale_auth` pour tester l'accès Tailscale, dont la mise à jour en direct ; `PRODUCER_FILES_DIR=<build>/files` pour tester aussi la republication d'un asset) : chapeaux, historique, asset lié, Accepter/Refuser, CLI, vue mobile iPhone portrait et paysage, balayage) tourne sur une base quelconque (titres uniques). Pour tester la migration, partir d'une base de version 1 : créer `data/producer.sqlite` avec `git show f0c4e41:producer/lib/schema.sql | sqlite3 …`, y insérer les cartes « Ancienne carte à faire » (todo), « Ancien bug en cours » (doing), « Ancienne carte à vérifier » (review, avec une note `agent` puis une note `julien`) et « Ancienne carte faite » (done), puis lancer le test avec `PRODUCER_EXPECT_MIGRATION=1`. Avec plusieurs requêtes en parallèle (images), lancer `php -S` avec `PHP_CLI_SERVER_WORKERS=6`.

Le test (Chromium, 36 vérifications) couvre :

- la connexion, refusée puis acceptée ;
- un perso colorisé, un décor et une musique (y compris la requête Range) ;
- les commentaires et le XSS échappé ;
- le kanban (bouton et glisser-déposer) ;
- `cli.py` ;
- le mobile ;
- le CSRF, le jeton, la traversée de répertoire, la limitation des tentatives et la déconnexion.

Les captures vont dans `tests/out/producer/`. `php -S` ignore les `.htaccess` : les refus d'accès direct se vérifient sous Apache.
