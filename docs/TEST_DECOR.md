# Test du décor : taille, masques, tri, vue du chasseur

Méthode utilisée le 21/10/2026 sur le port (demande de Julien : « vérifier si les éléments de décor ont la
bonne taille et le bon masque, en mode debug et en profondeur, en joueur comme en chasseur, sans être en
partie »). À refaire après chaque lot de décor ou de masques, et sur chaque nouvelle carte.

## 1. Mesurer (headless, ~1 min par carte)

```bash
godot --headless --path . --script res://tests/decor/mesure_decor.gd -- --map=port_pecheurs --out=/abs/mesures.json
```

Une entrée par objet posé (`decor.json` de la carte), en mode visite chassé :

| champ | sens | repère |
|---|---|---|
| `h_perso` | hauteur dessinée / hauteur d'un perso (88 px) | bitte ≈ 0,4 ; barriques ≥ 1 ; porte ≈ 1,1 ; confessionnal ≈ 1,3 ; cabine ≈ 1,4 ; maison ≥ 2,5 (porte ≈ 1,1) ; platane ≥ 2,5 ; fronton ≥ 3,5 |
| `fill_w` | largeur de l'image / largeur de ses cases | < 0,8 : cases vides (marchables pour tous depuis #606, voir ci-dessous) ; > 1 : débord latéral |
| `cases_vide_bloque` / `cases_plein_marchable` | cases de l'objet (et voisines) bloquées pour l'A* sans emprise dedans / marchables avec l'emprise dedans | 0 attendu (restent : îlots sans accès, barques sur l'eau) |
| `ecart_base_min/med/max` | écart (px) entre le bas de l'emprise et la base dessinée, colonne par colonne | \|med\| ≤ 6 ; min/max très négatifs = on bute dans le vide |
| `cols_sans_emprise`, `cols_emprise_sous_base` | colonnes de l'image sans emprise / emprise débordant sous la base | 0 attendu, quelques-unes tolérées aux bords |
| `sondes` | point où un cercle de perso s'arrête en avançant vers l'objet par les 4 côtés | doit être au contact de l'objet dessiné, jamais au milieu |
| `masque_derriere` / `masque_devant` | un perso derrière est-il masqué / un perso devant recouvert ? | objet haut : vrai / faux |
| `blocks_view`, `vu_derriere`, `vu_cote` | l'objet bloque-t-il la vue du chasseur ; part du perso vue derrière lui / à côté (9 points : 3 lignes × pieds, buste, tête, depuis l'œil du chasseur) | objet haut : 0 derrière ; objet qui cache mais plus bas que l'œil (`vue_basse`) : ≈ 0,33 (tête vue) ; objet bas qui ne cache pas (banc, étal) : 1 |
| `vue_h_perso`, `vue_basse` | hauteur de la silhouette (persos) ; vrai si plus basse que l'œil (vue_oeil) : hors couche de vue, sans ombre de lampe, la vue passe au-dessus | cachettes basses, caisses : basse ; maisons, platane, cabine : non |
| `info` | source du masque (pixelforge `masks.json` ou repli local), avertissements, confiance | « repli » ou masque périmé (`size` ≠ image) = à refaire |
| `provisoire` | objet encore dessiné par le code | 0 attendu une fois les images livrées |

Masques périmés ou absents, en un coup : `.venv/bin/python tools/producer/masques_manquants.py --essai`.

## 2. Regarder (fenêtre, captures)

```bash
godot --path . --script res://tests/decor/visite_decor.gd -- --role=chasse   --out=/abs/chasse   [--map=port_pecheurs] [--only=id,id]
godot --path . --script res://tests/decor/visite_decor.gd -- --role=chasseur --out=/abs/chasseur [--only=id,id]
.venv/bin/python tools/gordeka/planche_test_decor.py /abs/chasse /abs/planche.png devant,devant_F,derriere,derriere_F,gauche_F,droite_F
```

Pour chaque objet (une pose par id, taille et miroir), le perso est posé là où il s'arrête en marchant vers
l'objet (devant, derrière, gauche, droite) ; captures recadrées avec et sans les formes (touche F du mode
visite : emprise bloquante, zone qui cache, ligne de tri ; cases de la grille des IA corrigées par
l'emprise : bleu = case de l'objet libérée, rouge = case de sol bloquée par un débord). En `chasseur`, le chasseur est devant l'objet et
regarde vers lui ; le chassé figurant est remis à neuf à chaque pose et `_visite_chasseur.json` note la part
vue instantanée (0 à 1). À vérifier à l'œil :

1. **échelle** : objet vs perso et vs objets voisins (porte un peu plus haute qu'un enfant, bitte au genou…) ;
2. **emprise** : on bute sur la base dessinée, ni dans l'air ni à travers l'objet ;
3. **occlusion** : derrière un objet haut, le perso est masqué (transparent pour les coéquipiers) ; devant,
   il n'est jamais recouvert ;
4. **tri** : le perso passe devant / derrière au bon moment (ligne de base) ;
5. **cachettes et sorties** : on entre, on sort, rien ne bloque l'accès.

## 3. Corriger

- **Données** (sans régénérer) : `taille_cases`, `debord_haut_cases` (décimales permises, négatif pour un
  objet plus bas que ses cases), `hauteur_cases` (hauteur dessinée imposée, en cases : h_perso × 1,375 ;
  la largeur suit et peut déborder des cases sur les côtés, emprise et masque compris, les cases de sol
  couvertes sont bloquées pour l'IA ; c'est le réglage des objets plus larges que leurs cases) dans `assets/gordeka/decor/index.json` et `tools/gordeka/prompts_decor.json` ;
  placement dans `assets/maps/<carte>/decor.json` ; seuil `decor_masques_pf_part_max` de `rules.json`
  (part maximale de la silhouette qu'un masque pixelforge peut couvrir avant d'être écarté). Remesurer et
  recapturer après chaque correction.
- **Image ou masque à refaire** : une carte par objet (image + masque ensemble), avec la consigne précise
  (format d'image en px de `taille_jeu_px`, forme d'emprise attendue), en Backlog ; Julien priorise.
- **Code** : carte « feature » en Backlog (ex. débord latéral #605, cases vides traversables #606, vue du
  chasseur qui vise les pieds #607).

## 4. Tests de non-régression

```bash
godot --headless --path . --fixed-fps 60 --script res://tests/gk_tests.gd
```

Bilan du 21/10 (port, 140 objets) : bitte, fronton et banc de la chapelle corrigés en données ; 13 objets
renvoyés en Backlog (image ou masque) ; 3 cartes de code. Mesures et planches de ce passage : rapport dans
la conversation du 21/10, cartes #602 à #607.
