# À faire après la pause (2026-10-18)

Pause demandée par Julien après Amaia : file pixelforge vidée (tâches en attente annulées,
déjà générées gardées). Reprise = cette liste, dans l'ordre.

## Refonte complète des persos (`tools/pf/from_mannequin.py`, file `tools/pf/file_pf.py`)

Prêts (modèle + boule + accroupi choisis), à remettre en file :

| Perso | État | À faire |
|---|---|---|
| Mattin | **en ligne le 2026-10-18** (pierre seulement pour ses grands coups) | sp_down : bras détaché images 4–5 ; sp_up/super : coups peu lisibles |
| Ramuntxo | 37 générées le 19/10 ; bon dans l'ensemble | 9 ratés relancés (graine +500) |
| Patxi | 37 générées le 19/10 ; correct | 5 ratés relancés |
| Kaio | 37 générées : chips devant le bec, plumage taché | chips seulement grands coups (ACC_ONLY) ; tout relancé |
| Itsaso | 37 générées ; correcte sauf chutes/balayage | 11 ratés relancés |
| Txomin | 37 générées ; propre | 3 ratés relancés ; vérifier les palmes à la ceinture |
| Xabi | modèle garde 1014 (bras plié), boule 1021 ; chistera cachait tous les coups | chistera seulement grands coups (ACC_ONLY) ; 29 anims relancées |

Pour chacun, après les 37 anims :
1. relecture de la planche (`tools/pf/planche_revue.py <id>`) et des bords (rien de coupé) ;
2. relancer les ratés (`from_mannequin.py <id> <anim> --refaire --graine 1000`), cacher
   l'accessoire si le bras ne suit pas (`NO_ACC_ANIMS`) ;
3. portrait + image de fin depuis le nouveau modèle (`tools/pf/extras_pf.py portrait|fin <id>`),
   effets des spéciaux à vérifier ;
4. `build_rd_anims.py` → `build_fighter.py` → `qa_fighter.py`, captures en combat ;
5. réponse aux commentaires /producer (#1 Amaia, #3 Itsaso, #4 Kaio, #7 Mattin, #8 Patxi,
   #9 Ramuntxo, #10 Txomin, #11 Xabi).

## Amaia (en ligne le 2026-10-18) — à améliorer

- QA « coup invisible » (le coup dépasse à peine la garde) : kick_high, crouch_punch, jump_punch,
  jump_kick, sp_up ; win presque immobile. Cause : gestes timides du mannequin → amplifier ces
  poses (amp des fiches mannequin ou poses dédiées) puis refaire ces anims.
- Effets des spéciaux (assets/vfx/amaia) : gardés de l'ancienne version, à revoir avec le nouveau look.

## En attente de Julien

- Xabi : valider le modèle 1001 (petit poing).
- Tester sur vraie machine : manette dans le navigateur, iPhone (aucune touche clavier, tutoriel
  « Gestes »), Steam Deck (`docs/STEAMDECK.md`), Recalbox Pi 4/5 64 bits (`docs/RECALBOX.md`).
- Libellé « En ligne : express (sans finish) », épaisseur du focus doré (1 px) assez visible ?

## Équilibrage (fusionné le 2026-10-18, docs/EQUILIBRAGE.md)

- Après chaque perso refait : relancer `tools/balance/matrix.py` puis `tune.py` (boîtes de corps et
  hauteur des coups viennent des sprites ; sensibles : Karramarro, Mattin, Patxi, Kaio).
- Restent > 60/40 : Kaio > Ramuntxo, Maïa > Amaia, Patxi > Maïa.
- À ressentir en jeu : IA de la Pyramide plus active au contact ; poussée de Karramarro 54 → 44 px.

## Pixelforge (côté serveur)

- Retours envoyés : poings trop gros (keep_proportions, remove_held_object), facing, ombre,
  bulles, pf__pose sur poses compactes, file (priorités, tags, annulation) — tous livrés.
- À signaler si ça revient : pf__pose réduit la tête/coiffe à celle du mannequin (Ramuntxo,
  Itsaso) ; le guidé redessine parfois un objet inventé (sac d'Amaia au jump_kick).
