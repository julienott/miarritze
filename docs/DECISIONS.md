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
