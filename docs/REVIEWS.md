# Revues visuelles autonomes

Chaque revue est faite par un sous-agent qui n'a pas produit le travail (SPEC §0.8), au plus 2 itérations. Verdict : **ACCEPTÉ** ou **À REFAIRE**.

## Phase 0 — écran titre et export web (2026-10-12)
**ACCEPTÉ** (itération 1). Plein écran paysage sans bandes ni déformation (WebKit 844×390 ×3, Chromium), pixels nets, titre lisible, Biarritz reconnaissable, aucun artefact. Remarque mineure corrigée : contour sombre ajouté à « Appuie pour commencer ».

## Phase 1 — sim + mannequins Louis/Maïa (2026-10-12)
**ACCEPTÉ avec réserves** (itération 1). On se bat à deux au clavier dans le build web, l'uppercut « se sent » (hitstop, flash, « BAM ! », envol, chute). Taille stable en idle/walk, costumes sans toucher la peau.
- Corrigé : chevauchement des sprites au contact (push_w 22 → 26), annonces remontées au-dessus des têtes, ombre au sol ajoutée, flash adouci (0,6).
- Reporté au lot sprites de la Phase 2 : bras de l'uppercut/super devant le visage, `punch_2` peu tendu, main flottante en knockdown/ko, bras sales en fin de finisher, articulations « robot » de Maïa.
