# Journal des décisions

Choix pris en mode autonome (SPEC §0.6, §0.8) : l'option la plus simple qui respecte les piliers.

| Date | Sujet | Décision | Pourquoi |
|---|---|---|---|
| 2026-10-12 | `scale_mode` (§8.4) | `fractional` + filtre nearest | En paysage iPhone (390 px de haut), `integer` donnerait ×1 (image minuscule). Le fractionnaire remplit l'écran ; le léger flou de pixels inégaux est acceptable à 1,8×. |
| 2026-10-12 | Photos sources des décors | Les photos originales ne sont plus disponibles (ancien scratchpad effacé). Les décors i2i existants `bg_*` servent d'*input* aux élargissements ; les nouveaux stages passent en txt2img. | Spec §11.4 prévoit déjà ce repli. |
| 2026-10-12 | Tarifs RD | La doc à jour facture `rd_fast` à 0,03 $/image et `rd_plus` à 0,06 $/image, à plat, quelle que soit la taille (la spec supposait un coût à la surface). | Le client lit toujours le coût réel par `check_cost`. |
| 2026-10-12 | Cache RD | `tools/rd/cache/` est **versionné** (petits PNG) ; seul `tools/rd/out/` est ignoré. | Ne jamais repayer une image, même sur un autre clone. |
| 2026-10-12 | Gros lots RD (> 5 $) | Pas de confirmation humaine (mode autonome §0.8) : consignés dans `docs/REVIEWS.md` avant envoi. Le plafond reste dur. | §0.8. |
| 2026-10-12 | Actions d'entrée | Clavier dans `project.godot` (actions `p1_*`, `p2_*`) ; manettes lues par appareil dans `GamepadSource` (pas d'action) pour ne pas mélanger J1/J2. | Plus simple, et le versus à 2 manettes marche. |
| 2026-10-12 | IA : niveaux | `ai_level` = compétence 1–100 (réaction 26→7 frames, garde 10→82 %), mannequins d'entraînement à 200+. Pyramide : rampe par difficulté (Facile 8→32, Normal 35→62, Expert 62→90), boss +10, −10 après chaque paire de défaites au même étage. | Permet l'interpolation étage par étage demandée au §13. |
| 2026-10-12 | Équilibrage | Levier unique `damage_pct` par perso (75–130 %), ajusté par `tools/balance_tune.py` ; vitesses et PV inchangés (±10 %). Résultat n=20 : 43–57 %. | §5.2 : PV et vitesses proches ; les dégâts compensent les archétypes. |
| 2026-10-12 | Feuilles de sprites | Grille compacte 16 colonnes (2048 px), 12 colonnes pour les cellules 160 ; hauteur ≤ 4096 (WebGL2). | Une rangée par anim dépassait 4096 px. |
| 2026-10-12 | Sprites RD : génération | Exploration `rd_fast` en img2img depuis la pose de garde du mannequin, finale `rd_pro` (strength 0,5), toutes contraintes à la palette costume 1 du perso. | Les couleurs retombent sur les index de palette ; les costumes restent un swap. |
| 2026-10-12 | Sprites RD : rig | Les finales `rd_pro` s'écartent de la pose du mannequin (plus belles) : rig propre à chaque perso découpé sur l'image RD (§11.3.3) plutôt qu'un transfert automatique depuis le mannequin. | Qualité nettement supérieure. |
| 2026-10-12 | Stages élargis | Outpainting RD par côté (fenêtre de 256 px : 192 + 64) avec raccord tramé de 12 px, ou miroir gratuit quand l'outpainting change la perspective. Grande Plage : RD à gauche, miroir à droite ; Côte des Basques : miroir à gauche, RD à droite ; Port : miroir des deux côtés. | Avec la parallaxe 0,25 en 16:9, les 64 px de droite ne sont jamais visibles ; les raccords imparfaits ne se voient qu'en 19,5:9. |
| 2026-10-12 | Sols | Procéduraux 576×40 (sable, sable mouillé + écume, pavés de quai), aucun `rd_tile`. | Gratuit et suffisant sur planche contact. |
| 2026-10-12 | Build réseau local | Preset « Web LAN » sans threads, mais Godot web exige un contexte sécurisé : jouable seulement via `localhost` (ou HTTPS). | Constaté en test. |
