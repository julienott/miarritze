# Banque d'animations pixelforge (pf_2d__animate) — référence au 21/10/2026

Fournie par pixelforge à la demande de Julien. Liste à jour : `GET /v2/motions`.

## Règles générales
1. Le squelette décide du mouvement ; `action` précise le geste sans pouvoir le contredire. Autre geste = un clip (le demander à pixelforge).
2. Le visage vient de l'IMAGE DE RÉFÉRENCE, pas de `expression` : pour une émotion lisible, retoucher d'abord le profil (`pf_2d__character`, `edit: true`, « change only the facial expression: … ») puis animer depuis la retouche.
3. Jambes et accessoires viennent aussi de la référence (fantôme en vol : retoucher le profil en pose de vol).
4. Bras : pas au-dessus de la tête (la main revient contre le visage) ; bras tendus devant à hauteur d'épaule = lisible.
5. Prompts sans négation : décrire seulement ce qu'on veut.
6. Réglages au premier niveau du JSON : `motion`, `action`, `expression`, `tenue`, `arms`, `hold`, `exaggerate` (0,5–2), `bounce` (0–0,2), `frames`, `fps`.

## Préréglages (motion · boucle/une fois · notes)

| Famille | motion | Lecture | Notes |
|---|---|---|---|
| Déplacements | idle | boucle | respiration, clignement |
| | walk | boucle | trot sautillant (exaggerate 1,3, bounce 0,05 inclus) |
| | sneak | boucle | accroupi qui avance |
| | run_scared | boucle | fuite bras levés ; visage via une référence « peur » |
| | jump | une fois | départ de saut |
| Cache-cache | hide_in | une fois | s'assoit / se cache (peu lisible de profil) |
| | hide_out | une fois | CLIP : jaillit, bond bras en étoile, se redresse |
| | dive_hide | une fois | CLIP : appel, envol, sommet, plongée, tassé (utilisé par pf_px) |
| | found | une fois | CLIP : grand sursaut, puis rire penaud ; référence « surprise » |
| | trap | une fois | CLIP : penché, jambes tendues, pose l'objet (préciser l'objet dans `action`) |
| | trapped | boucle | se débat |
| | search | boucle | torche et balayage, porté par les BRAS |
| | detect | une fois | repère et tend la main, porté par les BRAS |
| | extract | une fois | ouvre un coffre |
| | hunter_reveal | une fois | CLIP : sort la lampe, la tient bras tendu (cône dessiné par le jeu) |
| Émotions | victory | boucle | peu ample |
| | sad | boucle | secoue la tête |
| | dance | boucle | CLIP, préférable à victory |
| | wave | une fois | CLIP : bras tendu devant, main qui s'agite |
| | thumbs_up | une fois | CLIP : poing devant la poitrine, pouce dressé |
| | shush | une fois | CLIP : main devant la bouche |
| | laugh | une fois | CLIP : mains sur le ventre, sautille |
| | tongue | une fois | CLIP : penché, langue rose sortie |
| Fantômes | ghost, ghost_move | boucle | CLIP « vol », depuis une référence en pose de vol ; ailes avec pf_2d__flap |

Les 87 clips Quaternius bruts restent appelables par leur nom (ex. `"motion": "Dance_Loop"`).

## Persos non humains (`arms`)
- `wings` : ailes qui battent le long du corps ; `wings_up` : ailes levées (panique, un peu floues).
- `side` : bras collés au corps — search/detect deviennent presque immobiles : donner le mouvement par le corps (exaggerate 1,4, bounce 0,05).
- `pincers` : inefficace sur Karramarro (pinces gardées telles que dessinées).
- `hold` : `{"left_arm"|"right_arm": "down"|"forward"|"tucked"|"up"|"back"}` pour tenir un objet ; pas de hold sur right_arm avec un clip.

## Post-traitements (sur une tâche finie)
- `pf_2d__tenue` : recalcule le masque de tenue ; `pf_2d__flap` : fait battre des ailes figées.
- `pf_px__character_set` puis `pf_px__reduce` : pixel art 128 px puis 32 px (reboot Party Hard, voir docs/STYLE_PARTY_HARD.md).
