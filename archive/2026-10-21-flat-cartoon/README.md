# Archive du 21/10/2026 : style « flat cartoon » (avant le reboot façon Party Hard)

Julien, 21/10 : « archive tout du projet, on reboote tout (sauf le gameplay et les menus) ; le kanban peut
repartir de zéro ». Tag git : `avant-reboot-2026-10-21`.

- `assets/persos/` : persos pf_2d (profils, animations, masques de tenue, json de calage) ;
- `assets/decor/` : décor du port (objets, sols, masques de gameplay pf_2d__footprint, index.json) ;
- `assets/maps/<carte>/decor/` : décor propre au parc Mazon et à la plage (placeholders) ;
- `assets/{choreo,communs,mannequin,models,textures}/` : pistes plus anciennes (chorégraphies, mannequin, 3D) ;
- `tools/` : prompts (prompts_anims.json, prompts_decor.json), retouches de recette, suivis de tâches pixelforge ;
- `kanban.json` : export complet de /producer (577 cartes avec historique et commentaires, commentaires
  d'assets, jalons).

Restent en place : le code (gameplay, menus, IA, réseau, outils), les règles (data/gordeka), le plan des
cartes (assets/maps/*/map.txt, zones.json, decor.json). Sans visuels, le jeu affiche les persos dessinés par
le code et des blocs gris.
