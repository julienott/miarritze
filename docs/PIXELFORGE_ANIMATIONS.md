# Animations pixelforge : uniquement Quaternius (au 21/10/2026)

Décision de Julien (21/10) : **uniquement les animations Quaternius**. Les clips sur mesure (wave, thumbs_up,
shush, laugh, tongue, dance, hunter_reveal, dive_hide, versions sur mesure de found, trap, hide_out, ghost) sont
retirés. **Toute demande d'animation nomme explicitement un préréglage ou un clip Quaternius exact dans
`motion`.** Liste à jour : `GET /v2/motions`.

## Préréglages (motion → clip Quaternius)

| motion | clip | | motion | clip |
|---|---|---|---|---|
| idle | Idle_Loop | | trapped | Push_Loop |
| walk | Jog_Fwd_Loop | | search | Idle_Torch_Loop |
| sneak | Crouch_Fwd_Loop | | detect | Interact |
| run_scared | Sprint_Loop (bras levés) | | extract | Chest_Open |
| hide_in | Sitting_Enter | | victory | Dance_Loop |
| hide_out | Sitting_Exit | | sad | Idle_No_Loop |
| found | Hit_Chest | | jump | Jump_Start |
| trap | Farm_PlantSeed | | ghost | Swim_Idle_Loop |
| | | | ghost_move | Walk_Formal_Loop |

`pf_px__character_set` (pixel art) utilise **Sprint_Loop** pour la course et **Jump_Start** pour le saut vers la cachette.

## Les 87 clips, utilisables en `"motion": "<nom>"`
- **Marcher, courir** : Walk_Loop, Walk_Formal_Loop, Walk_Carry_Loop, Jog_Fwd_Loop, Sprint_Loop, Crouch_Fwd_Loop, Crouch_Idle_Loop, Zombie_Walk_Fwd_Loop, Swim_Fwd_Loop, Swim_Idle_Loop
- **Repos, attitudes** : Idle_Loop, Idle_FoldArms_Loop, Idle_Talking_Loop, Idle_TalkingPhone_Loop, Idle_Lantern_Loop, Idle_Torch_Loop, Idle_Rail_Loop, Idle_Rail_Call, Idle_No_Loop, Yes, Zombie_Idle_Loop, Zombie_Scratch, Sitting_Enter, Sitting_Idle_Loop, Sitting_Talking_Loop, Sitting_Exit, LayToIdle
- **Sauts, acrobaties** : Jump_Start, Jump_Loop, Jump_Land, NinjaJump_Start, NinjaJump_Idle_Loop, NinjaJump_Land, Roll, Roll_RM, Slide_Start, Slide_Loop, Slide_Exit, ClimbUp_1m_RM
- **Interactions** : Interact, PickUp_Table, Chest_Open, Consume, Push_Loop, Fixing_Kneeling, Farm_PlantSeed, Farm_Harvest, Farm_Watering, TreeChopping_Loop, Driving_Loop, OverhandThrow
- **Danse, réactions** : Dance_Loop, Hit_Chest, Hit_Head, Hit_Knockback, Hit_Knockback_RM, Death01
- **Combat** (hors sujet pour un jeu d'enfants, listé pour mémoire) : Punch_*, Melee_*, Sword_*, Shield_*, Idle_Shield_*, Pistol_*, Spell_Simple_*

Les clips en `_RM` avancent dans la vidéo : préférer les versions sans `_RM`.

## Réglages possibles par-dessus un clip (sans changer l'animation)
`exaggerate` (0,5–2), `bounce` (0–0,2), `arms` (up / wings / wings_up / side / pincers), `hold`
(`{"left_arm"|"right_arm": "down"|"forward"|"tucked"|"up"|"back"}`), `action`, `expression`.

## Règles
1. Le squelette (le clip) décide du mouvement ; `action` précise sans contredire.
2. Visage et accessoires viennent de l'IMAGE DE RÉFÉRENCE : pour une émotion, retoucher d'abord le profil (`pf_2d__character`, `edit: true`).
3. Bras au-dessus de la tête peu lisibles ; bras devant à hauteur d'épaule = lisible.
4. Prompts sans négation.
5. `arms: "side"` fige les clips portés par les bras (search, detect) : donner le mouvement par le corps.

## Post-traitements
`pf_2d__tenue` (masque de tenue), `pf_2d__flap` (ailes qui battent), `pf_px__character_set` puis `pf_px__reduce` (pixel art 128 px puis 32 px, voir docs/STYLE_PARTY_HARD.md).
