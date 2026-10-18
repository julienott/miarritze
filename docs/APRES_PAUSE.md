# À faire après la pause (2026-10-18)

Pause demandée par Julien après Amaia : file pixelforge vidée (tâches en attente annulées,
déjà générées gardées). Reprise = cette liste, dans l'ordre.

## Refonte complète des persos (`tools/pf/from_mannequin.py`, file `tools/pf/file_pf.py`)

Prêts (modèle + boule + accroupi choisis), à remettre en file :

| Perso | État | À faire |
|---|---|---|
| Mattin | ~ moitié des 37 anims générées (avant la règle « accessoire caché couché ») | relancer le reste ; refaire les chutes (jump_fwd, thrown, hit_air, knockdown, getup, ko) |
| Ramuntxo | quelques anims générées | idem |
| Patxi | quelques anims générées | idem |
| Kaio | file annulée | tout relancer |
| Itsaso | file annulée | tout relancer |
| Txomin | file annulée ; palmes à la ceinture (HIP_ACC) | tout relancer ; vérifier les palmes sur la planche |
| Xabi | modèle 1001 en attente de l'accord de Julien ; accroupi + boule prêts | après accord : tout lancer |

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

## En cours ailleurs

- Équilibrage des combats (sous-agent, branche `equilibrage`) : relire et fusionner à son retour.

## Pixelforge (côté serveur)

- Retours envoyés : poings trop gros (keep_proportions, remove_held_object), facing, ombre,
  bulles, pf__pose sur poses compactes, file (priorités, tags, annulation) — tous livrés.
- À signaler si ça revient : pf__pose réduit la tête/coiffe à celle du mannequin (Ramuntxo,
  Itsaso) ; le guidé redessine parfois un objet inventé (sac d'Amaia au jump_kick).
