# Style « Party Hard » : analyse visuelle et recettes pixelforge

> **Document d'analyse, pas de décisions.** Les décisions de style (échelle, persos, éléments
> d'animation, lumière, prompts) sont dans `GDD-BLACKOUT.md` §8, §9 et §14, qui fait foi ; en cas
> d'écart, c'est le GDD qui a raison. Ce document garde l'étude du 21/10/2026 de *Party Hard*
> (Pinokl Games / tinyBuild, 2015 ; *Party Hard 2*, 2018) : 31 captures mesurées, 2 vidéos de la
> fiche Steam, l'audio de 2 bandes-annonces (sources en fin de document). Blocs de prompts pour les
> scripts : `data/blackout/style_party_hard.json` ; prompts de musique : `docs/PROMPTS_MUSIQUE.md`.
> Les captures restent hors du dépôt (droits d'auteur). On garde **l'esthétique**, pas le contenu
> (meurtres, sang, drogue, nudité : tout est écarté).

## 1. Ce qu'il faut retenir

1. **Un niveau = un écran.** Résolution native **640×360**, affichée ×3 en 1080p (×4 en 1440p).
   La caméra est fixe : quatre joueurs différents capturent Miami au même cadrage, quatre autres le
   casino au même cadrage, et un let's play de 4 min ne bouge pas.
2. **Animation sobre** : poses tenues 100 ms (10 i/s), marche en 4 poses, rebond de 1 px (vidéos,
   § 10).
3. **Musique** : électro dansante 4/4 à 120 BPM, basse de synthé lourde ; plus funk dans PH2
   (§ 11).
4. **Vue de dessus oblique « maison de poupée »** (projection orthographique, sans point de fuite),
   toit retiré : le sol vu d'en haut, les murs du fond montrent leur face, les autres murs se
   réduisent à leur arête.
5. **Persos minuscules : ~30–32 px de haut, 7–9 px de large**, environ 5 têtes de haut, vus de
   face ou de trois quarts, sans contour noir.
6. **Une foule de 40 à 60 PNJ** par niveau, tous différents par une silhouette-cliché (cow-boy,
   videur, maillot de bain, déguisement), une couleur franche et un accessoire.
7. **La nuit partout**, fond sombre (luminance médiane ≈ 40–50 sur 255), avec des **sources de
   lumière colorées et additives** : halos ronds jaunes, projecteurs de scène en cône, néons,
   gyrophares avec bloom.
8. **Décor très dense** : chaque pièce est meublée bord à bord, avec du mobilier reconnaissable
   au premier coup d'œil (baignoire, canapé, platines, toilettes de chantier).
9. **Sols à motif** (parquet en lames de ~5 px, carrelage sur une grille de 8 px, damier, tapis
   à frise) qui identifient chaque pièce sans texte.
10. **HUD minimal** en police pixel : score et compteur en haut à gauche, rappel de touche en bas à
   gauche, bulles « ! » et répliques violettes au-dessus des PNJ.

## 2. Mesures

Mesuré sur des captures ramenées à la résolution native (on prend le centre de chaque cellule ×3),
puis zoomées en plus proche voisin. La période de la grille est calculée par FFT des bords : 3,00 px
sur toutes les captures 1920 de PH1, 4,00 sur les 2560. Les JPEG Steam brouillent ±1 px.

| Élément | Mesure native | Capture |
|---|---|---|
| Résolution de jeu | 640×360, ×3 (1080p) ou ×4 (1440p), plus proche voisin | toutes PH1 ; comm_08 en 2560 |
| Zoom des DLC sur Steam | ×4 à ×5, soit 320×180 visibles ou moins | hc_04 à hc_07, dc_03 à dc_05 |
| Hauteur d'un perso adulte | 30–32 px | ph1_01 (fille au tapis 32, hawaïen 30), comm_60 |
| Largeur d'un perso | torse 6–7 px, 8–9 px avec les bras | ph1_01 |
| Tête | ~6 px, soit environ 1/5 de la hauteur | ph1_01 |
| Couleurs par perso | 6 à 10 teintes propres (quantification : l'erreur plafonne à 10–12 couleurs, fond compris) | ph1_01 |
| Contour des persos | aucun contour noir ; seuls les cheveux et chaussures sombres font bord | ph1_01, ph1_04 |
| Arête de mur (vue de dessus) | bande quasi noire de 5–6 px (#141718 à #1b1e1f) | ph1_01 |
| Face visible d'un mur du fond | 16–27 px, soit 0,5 à 0,9 fois un perso | ph1_01 (séjour 22, couloir 27) |
| Porte double intérieure | ouverture ~28 px, battants ~27 px de haut (≈ 1 perso) | ph1_01 |
| Porte de WC de chantier | 19 × 43 px (toit compris), porte ≈ 33 px, soit 1,1 perso | comm_60 |
| Baignoire / canapé | 47 × 28 / 42 × 27 px | ph1_01 |
| Bibliothèque | 30 × 45 px (dessus compris) | ph1_01 |
| Cheval | 48 × 37 px | comm_60 |
| Carrelage | grille de 8 px (salle de bain, piscine) ; damiers de cuisine plus larges, ~12–16 px | ph1_01, comm_42 |
| Parquet / pont de bateau | lames de ~5 px de large | ph1_01, ph1_04 |
| Pièce typique | 70–110 × 50–90 px (un séjour ≈ 3 × 3 persos de large) | ph1_01, ph1_05 |
| Palette d'ambiance (maison) | #2a2d29 · #5f4840 · #1b1e1f · #a09a86 · #4c322a | ph1_01 |
| Palette (casino) | #1f1f27 · #4e688d · #72a4b6 · #343541 · #3d2137 | ph1_02 |
| Palette (plage, crépuscule) | #2e3339 · #2c3245 · #252831 · #2b2541 · #636160 | comm_01 |
| Palette (BBQ au bord du lac) | #48432d · #293519 · #2b3e1e · #3c655c · #385146 | comm_60 |
| Palette (yacht, le plus clair) | #113145 · #375e6d · #83a1a8 · #5c392a | ph1_04 |

## 3. Perspective

- **Angle.** C'est une vue de dessus oblique façon RPG 16 bits, pas de l'isométrie. Le sol est un
  plan vu d'en haut, et tout ce qui est vertical (murs du fond, meubles, persos, véhicules) est
  dessiné de face, collé au sol. Aucun point de fuite : la grille reste orthogonale à l'écran
  (ph1_01, ph1_05, comm_36).
- **Murs.**
  - Les murs « nord » (en haut de chaque pièce) montrent leur face, avec papier peint, lambris ou
    carrelage, et les meubles s'y adossent (bibliothèque, canapé, drapeau dans ph1_01).
  - Les murs sud, est et ouest se réduisent à leur arête : une bande noire de 5–6 px.
  - La façade sud du bâtiment est dessinée sous le sol, comme une maison de poupée coupée :
    soubassement et fenêtres visibles (ph1_05, comm_36, ph1_10).
- **Toits.** Ils sont absents et ne réapparaissent pas : tout l'intérieur est lisible en
  permanence. Il n'y a ni transparence ni découpe dynamique. Les seules occlusions sont de petits
  objets devant les persos (comptoir, bord de piscine, cabines).
- **Meubles.** Ils sont alignés sur la grille et vus « dessus + face » : on voit le plateau de la
  table et le devant du canapé. Quelques objets sont tournés pour animer la scène (transats en
  biais sur le yacht, voitures de police de trois quarts).
- **Extérieurs.**
  - Même convention : arbres en boule vus d'au-dessus, avec ombre portée sombre vers le bas à
    gauche (comm_60).
  - Tentes, cabines et estrades sont vues dessus + face.
  - L'eau occupe un bord de l'écran : mer en haut sur la plage (comm_01), lac à droite au BBQ
    (comm_60), océan autour du yacht (ph1_04).
- **PH2, pour comparer** (ph2_01 à ph2_07). Le décor y est en vraie 3D, faite de voxels et de
  textures pixel, avec une caméra perspective inclinée d'environ 55–60°. Les murs du premier plan y
  sont abaissés en coupe, la lumière et les ombres dynamiques sont réelles et un léger flou de
  profondeur s'ajoute. C'est plus riche mais beaucoup moins lisible : la foule se confond avec le
  décor. **Pour Blackout, la référence utile est PH1.**

## 4. Personnages

- **Silhouette.** Grande et fine, environ 5 têtes de haut, avec des jambes de 1 px chacune séparées
  de 1 px, des bras de 1 px et des chaussures en 2 px de couleur vive. La tête est un bloc de
  cheveux de 5–6 px, et le visage se résume à 2–3 px de peau, souvent sans yeux visibles. On
  reconnaît le perso à sa **silhouette et à ses deux ou trois aplats de couleur**, jamais au
  visage.
- **Différenciation des PNJ.** Chacun repose sur un cliché lisible, avec un haut et un bas de
  couleurs contrastées :
  - chemise hawaïenne rose et short vert ;
  - salopette bleue et casquette rouge ;
  - cow-boy marron et beige ;
  - videur tout en noir, lunettes jaunes ;
  - serveur en chemise blanche, plateau à la main ;
  - maillots de bain, culturistes, déguisements (Dark Vador, aliens, squelette, mascottes à
    grosse tête).

  Les têtes « mascotte » (cochon rose, citrouille, ph1_04) sont plus grosses de 2–3 px et
  ressortent dans la foule.
- **Joueur et PNJ.** Le joueur porte une tenue sombre et unie (noir, bleu nuit) et se distingue
  par une **ellipse blanche pointillée sous les pieds** (ph1_04, hc_06, dc_05) ; dans PH2, c'est un
  cercle rose. Ce marqueur fonctionne très bien dans une foule dense.
- **Animations visibles.**
  - Sur les images fixes : marche (jambes écartées), danse bras levés (culturistes, aliens de
    ph1_10), DJ penché sur ses platines, assis, endormi (« Z » jaune), allongé, porté.
  - Les persos regardent surtout vers le bas ou de trois quarts ; le profil gauche-droite se voit
    sur les marcheurs et les animaux.
  - Les mesures sur les vidéos sont au § 10 : poses à 10 i/s, marche en 4 poses, danse en 5.
- **Densité.** Il y a 40 à 70 PNJ par niveau (compteurs « 00/40 » à « 56/56 ») : ce sont eux qui
  font « fête ». La piste de danse rassemble 10 à 15 persos dans environ 120 × 70 px (ph1_02,
  ph1_10).

## 5. Décor

- **Palette.** Elle est sombre et désaturée sur les grandes surfaces (sols et murs entre #14 et
  #60 en luminance). Les couleurs franches sont réservées aux persos, aux néons et aux objets
  interactifs. Chaque niveau a sa dominante :
  - maison : brun chaud ;
  - casino : bleu-violet ;
  - plage : violet crépuscule ;
  - BBQ : vert forêt ;
  - yacht : bleu pétrole.
- **Éclairage.** Tout se passe la nuit. La lumière est additive et douce, sans ombre au sol
  dynamique :
  - halos ronds jaunes autour des réverbères et des lampes (ph1_01, comm_36, comm_42) ;
  - cônes de projecteurs violets et bleus sur les scènes (comm_01) ;
  - néons en tubes cyan et magenta qui dessinent les comptoirs (ph1_02) ;
  - gyrophares bleu et rouge avec un fort bloom ;
  - une pièce peut changer de teinte en entier (chambre en feu orange, ph1_01).

  L'image se termine par une vignette sombre aux bords et un grain sur les sols extérieurs.
- **Ombres portées.** Elles sont rares : les gros volumes (arbres, pile de bûches, cabines) ont une
  ombre sombre et diffuse décalée (comm_60), les persos n'en ont pas.
- **Mobilier.** Il est dense et narratif :
  - platines et enceintes ;
  - bar avec tabourets ;
  - canapés en L, plantes vertes en pot, palmiers ;
  - baignoire, WC, frigo ;
  - billard, table de casino ;
  - piscine avec bouée et toboggan jaune ;
  - WC de chantier, tentes, combis VW ;
  - bouées de sauvetage, transats rayés, parasols.

  On compte environ 1 objet tous les 30 × 30 px. Les objets sont saturés à l'intérieur mais sans
  contour noir. Seul un liseré plus sombre de leur propre couleur les détache du sol.
- **Sols.** Chaque pièce a son motif :
  - parquet sombre en lames ;
  - carrelage gris-vert de salle de bain ;
  - damier crème de cuisine ;
  - tapis rouge à frise grecque ;
  - moquette violette de casino ;
  - pont en teck ;
  - herbe texturée, sable sombre, asphalte avec marquage jaune.

  Les motifs restent peu contrastés, à ±15 de luminance, pour que les persos ressortent.
- **Effets.** Feu animé, fumée, confettis, ballons, « Z » de sommeil, éclairs de flash photo,
  banderoles lumineuses (guirlandes de petits points colorés sur la plage) et néons qui clignotent.

## 6. Cartes et niveaux

- **Taille.** Un niveau tient en un écran de 640×360. Le pourtour (rue, jardin, mer) sert de
  cadre, et la police arrive par la rue en bas de l'écran.
- **Structures observées.**
  - **Maison** (ph1_01, ph1_05) : 8 à 12 pièces de tailles variées autour d'un grand séjour
    central, un couloir, 2–3 entrées et un jardin latéral.
  - **Campus et dortoir** (comm_36) : une grande salle centrale, deux colonnes de chambres
    empilées à gauche et à droite, et les douches en haut.
  - **Club et casino** (ph1_02) : une piste centrale ronde, une scène en haut, des zones annexes
    dans les coins (cuisine, coffre, piscine, voiture exposée) et une entrée avec tapis rouge en
    bas.
  - **Plein air** (comm_01, comm_60, ph1_03) : une clairière ou une plage avec une scène en haut,
    des îlots de décor (tentes, cabines, pontons, véhicules) et de l'eau sur un bord.
  - **Toit, bateau, station** (comm_42, ph1_04, ph1_10) : une forme fermée, avec un centre
    attractif (piscine, piste) et un pourtour de services.
- **Points d'intérêt.** Chaque niveau a un aimant central (piste, scène, piscine) qui concentre la
  foule. Les **cachettes** sont des meubles et des volumes nommés : armoires, WC, cabines de
  chantier, poubelles, buissons, coffres de voiture. On les repère comme mobilier, pas par une
  icône permanente. Les sorties sont des portes en bord de carte ou de façade.
- **Lecture de l'espace.** Les pièces fermées par des arêtes noires épaisses et les sols à motif
  par pièce font qu'on comprend le plan en une seconde, sans mini-carte.

## 7. Interface

- **PH1.**
  - Police pixel en capitales, chasse fixe d'environ 7 px de haut natif.
  - Libellés en couleur (« POINTS » violet, « KILLS » rose, « TIME » vert) et valeurs en blanc,
    en haut à gauche.
  - Icône d'objet tenu dans un carré bleu-gris arrondi.
  - Rappel de touche en bas à gauche : icône de bouton cerclée et verbe.
  - Au-dessus des PNJ : bulle ronde rouge « ! » (alerte), réplique en blanc sur un bandeau violet
    vif (#a020f0 environ), et « Z » jaune pour les dormeurs.
- **PH2.** Police vectorielle géométrique, liste d'objectifs à cases en haut à gauche, portrait
  rond et inventaire en croix en bas à gauche, jauge de suspicion au centre en haut. Les accents
  sont magenta.
- **Menus PH1.** Carte des États-Unis désaturée, posters de niveaux, objets posés sur une table
  (hc_03, comm_15).

## 8. Recettes pixelforge

Les anciennes recettes détaillées du 21/10 (`archive/2026-10-22-docs-gordeka/style/`) sont archivées :
elles supposaient une toile de 48 px et 5 éléments. Recettes en vigueur : `GDD-BLACKOUT.md` §8 et §14.

## 9. Ce qui reste incertain (mesures)

- **Couleurs.** Les mesures sont faites sur des JPEG et des vidéos compressées : les teintes
  exactes et le nombre de couleurs par sprite sont approchés (±2 couleurs, ±1 px).
- **Tempo en jeu.** Il n'a pas pu être mesuré : le let's play a un commentaire par-dessus. Les
  120 BPM viennent des bandes-annonces.

Taille des persos, caméra, directions et abandon du style HD : tranchés, voir `GDD-BLACKOUT.md`.

## 10. Vidéos : mesures d'animation

**Sources** : fiche Steam de *Party Hard* (app 356570), flux HLS des vidéos téléchargés avec ffmpeg
dans le scratchpad (jamais commités) :
- « Lets Play by Mike Rose » : 720p30, soit ×2 exact du natif, 236 s, niveau d'Halloween, caméra
  fixe ;
- « Launch Trailer » : 1080p60, 86 s, plans zoomés ×4,7 à ×5.

**Méthode** :
1. Images extraites à pleine cadence (`ffmpeg -ss … -t …`), ramenées au natif (plus proche
   voisin).
2. Bandes d'images consécutives zoomées pour compter les poses.
3. Pour les animations sur place (DJ), autocorrélation des images d'un cadre fixe pour trouver la
   période.

| Mesure | Valeur | Où |
|---|---|---|
| Cadence des poses | 10 i/s : pose tenue 3 images à 30 i/s, 6 images à 60 i/s (images de fondu à 3, 9, 15, 21, 27, 33) | let's play à 60 s ; bande-annonce à 19 s |
| Cycle de marche | 4 poses (enjambée, passage, enjambée, passage) ≈ 0,4 s ; bras écartés de 1 px du corps ; tête qui monte de 1 px au passage | PNJ aux cheveux rouges, let's play à 60 s |
| Vitesse de marche | ≈ 0,9 px natif par image à 30 i/s, soit ≈ 27 px/s | même PNJ |
| Directions | profil gauche-droite et vue de face ; le PNJ qui descend en diagonale garde son sprite de face | let's play |
| Danse | 5 poses en boucle à 10 i/s (jambe arrière levée, jambe tendue, accroupi, pas, debout), soit environ 0,5 s | PNJ en salopette, bande-annonce à 19 s |
| DJ | 3 poses, période ≈ 9,3 images à 30 i/s (≈ 0,31 s) | let's play à 100 s |
| Bulle « ! » | grossit en 5 images (≈ 0,17 s) au-dessus du PNJ | let's play à 60 s |
| Squash and stretch | aucun sur les corps ; seulement sur la bulle | — |
| Caméra | fixe pendant les 4 min du let's play ; zooms et panoramiques dans la bande-annonce (montage) | — |

## 11. Musique : analyse

**Sources** :
- fiches Steam des OST : *Party Hard Remastered OST* (app 554790), *Party Hard 2 OST* (964370),
  *Party Hard Tycoon OST* (733080) ;
- gamegrin.com (titres de l'OST d'origine par niveau) ;
- audio des bandes-annonces Steam, analysé dans le scratchpad (flux spectral et autocorrélation,
  numpy).

- **Histoire de la BO de PH1.** Elle était sous licence, sans droit de vente. Après des
  revendications de droits sur YouTube, elle a été **entièrement réécrite** (*Remastered OST*,
  12 titres : *Beat Dreams*, *I Said We Party Tonight*, *Wild Of Bass*, *Heart Of The Beat*,
  *He Knows You're A Dancer*, *E-Motions*…). Titres d'origine par niveau, selon gamegrin : *Goon
  Squad* (BBQ), *Come On Baby* (bateau), *Video Game Doc* (casino), *Afterparty* (Halloween),
  *My Future Broken Heart* (Miami), *Pure Dance* (plein air), *In The Lights* (toit).
- **PH2.** 27 titres, dont 11 originaux de **Ressa Schwarzwald** (*Party Infinite*, *City
  Stalker*, *Space Cabrio*, *Swing It*, *Groovy Move*, *Sunny Funny*…) et des titres sous licence.
- **Mesures.**
  - Bande-annonce de PH1 (de 40 à 80 s) : **120 BPM**. La grosse caisse tombe sur chaque temps
    (corrélation 0,77 à 1 temps, négative au demi-temps) : c'est un *four-on-the-floor*.
    Charleston régulier. **≈ 50 % de l'énergie sous 150 Hz** (basse lourde). Centroïde spectral
    ≈ 2,7 kHz. L'intro est plus lente (≈ 108 BPM, cinématique).
  - Bande-annonce de PH2 : **120 BPM**, motifs en croches (forte corrélation au demi-temps), plus
    funk et disco. Centroïde ≈ 2,1 kHz.
- **Genre.** Électro dansante rétro (house filtrée, synthwave, électro-disco), instrumentale,
  boucles longues sans couplet. PH2 tire vers le nu-disco et le funk (titres *Groovy Move*,
  *Swing It*, *Sunny Funny*). L'univers sonore de la série est sombre ; chez nous, il devient
  joyeux.
- **Prompts réutilisables** : `docs/PROMPTS_MUSIQUE.md` et `data/blackout/style_party_hard.json`
  → `musique`.

## 12. Captures et sources

**Steam, fiche *Party Hard*** (app 356570, `store.steampowered.com/api/appdetails?appids=356570`,
captures `ss_*.1920x1080.jpg`) : ph1_01 maison de soirée, ph1_02 club-casino Vegas,
ph1_03 *Peace Date* plein air, ph1_04 yacht *SS Royale*, ph1_05 maison d'Halloween, ph1_06 et
ph1_07 cinématiques, ph1_08 casino en cours de partie, ph1_09 entrepôt et rue, ph1_10 station
spatiale (UFO Party), ph1_11 maison en mode zombie.

**Steam, fiche *Party Hard 2*** (app 572430) : ph2_01 rue de la boîte de nuit, ph2_02 bureaux,
ph2_03 bar et billard, ph2_04 club (filtre rouge), ph2_05 parking du motel, ph2_06 *Empire Club*,
ph2_07 motel.

**Steam, DLC *High Crimes*** (app 554791) : hc_01 et hc_02 cinématiques, hc_03 carte des niveaux,
hc_04 commissariat (zoom), hc_05 ghetto, hc_06 usine, hc_07 studio.
**DLC *Dark Castle*** (app 530180) : dc_01 titre, dc_02 cinématique, dc_03 cour, dc_04 salon du
château, dc_05 cimetière.

**Captures de joueurs** (Steam Communauté, `steamcommunity.com/app/356570/screenshots/`, les
mieux notées, images `images.steamusercontent.com/ugc/…`) :
- comm_01 : *Miami Party*, plage au crépuscule (`ugc/10150792145033888703/…`) ;
- comm_08 : *Underground Sick*, métro (`ugc/15402972414477313709/…`) ;
- comm_15 : choix des niveaux et des héros ;
- comm_19 : *Party Bus* ;
- comm_36 : *Campus Party*, dortoir (`ugc/11349473703111100893/…`) ;
- comm_42 : *Rooftop / Pool Party* (`ugc/14525825124510615368/…`) ;
- comm_60 : *BBQ Party*, ranch au bord du lac (`ugc/18258776064519267816/…`).

En plus, une cinquantaine de captures de joueurs ont été survolées en planche (cadrages identiques
entre joueurs, ce qui confirme la caméra fixe).

**Liste des niveaux** : speedrun.com/party_hard/levels. Le wiki Fandom (plans de niveaux en PNG)
et MobyGames sont protégés par Cloudflare et n'ont pas pu être téléchargés.

**Vidéos et audio** (fiches Steam, flux HLS `video.akamai.steamstatic.com/store_trailers/…`) :
- *Party Hard* « Lets Play by Mike Rose » (`356570/40205/…`) ;
- *Party Hard* « Launch Trailer » (`356570/41616/…`) ;
- *Party Hard 2* « Launch Trailer », audio seul (`572430/192280/…`).

Fichiers dans le scratchpad (`partyhard_refs/video/`), jamais commités.

**Bandes-son** : fiches Steam des apps 554790, 964370 et 733080 ;
gamegrin.com/directory/game/party-hard/music.
