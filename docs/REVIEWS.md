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
