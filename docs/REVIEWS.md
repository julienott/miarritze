# Revues visuelles autonomes

Chaque revue est faite par un sous-agent qui n'a pas produit le travail (SPEC §0.8), au plus 2 itérations. Verdict : **ACCEPTÉ** ou **À REFAIRE**.

## Phase 0 — écran titre et export web (2026-10-12)
**ACCEPTÉ** (itération 1). Plein écran paysage sans bandes ni déformation (WebKit 844×390 ×3, Chromium), pixels nets, titre lisible, Biarritz reconnaissable, aucun artefact. Remarque mineure corrigée : contour sombre ajouté à « Appuie pour commencer ».

## Phase 1 — sim + mannequins Louis/Maïa (2026-10-12)
**ACCEPTÉ avec réserves** (itération 1). On se bat à deux au clavier dans le build web, l'uppercut « se sent » (hitstop, flash, « BAM ! », envol, chute). Taille stable en idle/walk, costumes sans toucher la peau.
- Corrigé : chevauchement des sprites au contact (push_w 22 → 26), annonces remontées au-dessus des têtes, ombre au sol ajoutée, flash adouci (0,6).
- Reporté au lot sprites de la Phase 2 : bras de l'uppercut/super devant le visage, `punch_2` peu tendu, main flottante en knockdown/ko, bras sales en fin de finisher, articulations « robot » de Maïa.

## Phase 2 — roster en mannequins, pyramide, entraînement, équilibrage (2026-10-12)
- **Itération 1 : À REFAIRE.** Portraits identiques en build web (feuilles absentes au moment de l'export), menu pause hors écran, matrice d'équilibrage vide (bug de copie de PackedInt32Array), portraits de pyramide coupés, titre de la sélection mangé, canne de Patxi « en fusil », captures de fin pendant l'iris, chevauchements entraînement/liste des coups, costumes trop proches.
- Corrections : vignettes de tête indexées (`portrait_small`) + `PortraitView`, phare dessiné dans un enfant, menu pause ancré, matrice à plat + heatmap, canne relevée, rampes neutres remplacées par costume, captures en temps réel, liste des coups opaque.
- **Itération 2 : ACCEPTÉ.** Équilibrage 43,2–56,8 %. Restes mineurs : quelques duels extrêmes (bruit à n=20), stage de repli « Halles » = décor du Port tant que le stage n'existe pas, costumes de Hondar identiques (voulu).

## Phase 3 — pipeline graphique, 4 persos RD, 3 stages (2026-10-12/13)
- **Itération 1 : À REFAIRE.** Peau recolorée dans les costumes de Maïa et Xabi (rampes partagées peau/tissu), poing détaché de Maïa (punch_1/2), uppercut de Louis/Maïa mou, super/finisher illisibles, coups de pied de Patxi illisibles, captures périmées, corps qui se chevauchent, portrait de Xabi rogné.
- Corrections : indexation par couple (groupe, couleur) avec groupes figés pour la peau et le visage ; avant-bras continu ; uppercut avec décollage (`lift`) ; super/finisher réécrits ; coups de Patxi ; portraits nettoyés ; captures refaites ; `push_w` 26 → 30.
- **Itération 2 : À REFAIRE** sur un seul point bloquant, le chevauchement au contact ; tout le reste est validé.
- **Blocage consigné (règle §0.8 : 2 itérations maximum) :** boîte de poussée rendue asymétrique (avant/arrière mesurés sur le torse de l'idle). La sim garde au moins 50 px entre les deux pieds, et la garde au neutre est nette. Ce qui se superpose encore, ce sont les poings et la planche au moment du contact, comme dans tout jeu de combat (sans contact, aucun coup ne porte). Point à revoir en playtest (§16).
- Registre RD en fin de phase : 3,41 $ (≤ 8 $ ✔).

## Phase 4 — tactile iPhone (2026-10-13)
**ACCEPTÉ** (itération 1), en émulation Playwright (Chromium mobile + multitouch CDP à index aléatoires, WebKit pour les taps). Tutoriel complet au doigt avec super au bouton MARÉE, combat entier au tactile contre l'IA Facile jusqu'au K.O. Le test sur vrai iPhone reste à faire (`docs/TEST_IPHONE.md`).
- Corrigé après la revue : marges sûres de 44 pt sur les quatre bords (et l'encoche/la barre d'accueil si le navigateur les donne), boutons ≥ 64 pt quelle que soit la taille choisie, icônes (poing, espadrille, lauburu, bouclier) à la place des lettres, losange plus bas, super à deux doigts seulement sur deux taps courts quasi simultanés, garde maintenue tant qu'un autre doigt la tient, second doigt gauche ignoré, tests du mode Gestes.

## Phase 5 — profils, menus, DA complète, audio (2026-10-13)
- **Itération 1 : À REFAIRE.** VS non démontré ; HUD pas en DA finale ; sélection en ASCII sans fond flouté ni verrou ; costumes 3–4 jugés non déblocables (ils l'étaient, au terme de la Pyramide) ; rang de groupe absent ; suppression de profil sans confirmation ; mauvais profil actif après suppression.
- Corrections : VS en grands portraits RD + « VS » basque ; HUD en cadres de planche 9-patch, portraits 40×40 cadrés laiton, jauge Marée en vagues, txapelas lisibles ; sélection en étoiles, fond flouté, cadenas ; rang de groupe (API `rating`) ; confirmation de suppression ; index actif corrigé.
- **Itération 2 : ACCEPTÉ.** Restes mineurs : projectiles encore procéduraux (rectangle de la pelote de Xabi) → Phase 7/8.
