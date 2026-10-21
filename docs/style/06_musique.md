# Musique et sons « façon Party Hard » (Gordeka)

> Proposition du 21/10/2026. L'analyse est dans `docs/STYLE_PARTY_HARD.md` §11. Les prompts
> réutilisables sont dans `data/gordeka/style_party_hard.json` → `musique`. Ils sont descriptifs,
> en anglais, sans nom d'artiste ni de jeu, et prévus pour un générateur comme Suno.
> Rappel (CLAUDE.md, règle 10) : seulement des compositions originales ou des airs du domaine
> public ; *Hegoak* reste la musique de l'accueil et des menus.

## 1. Ce qu'on garde de Party Hard

- **L'énergie « fête »** :
  - électro dansante en 4/4 autour de **120 BPM** ;
  - grosse caisse sur chaque temps ;
  - charleston ouvert sur les contretemps ;
  - basse de synthé analogique ronde (la moitié de l'énergie sous 150 Hz dans la bande-annonce) ;
  - arpèges et nappes de synthé rétro façon années 80.
- **Le côté funk et disco de PH2** : motifs en croches, guitare ou basse « slap » synthétique,
  titres solaires (*Groovy Move*, *Sunny Funny*).
- **Des boucles longues** qui montent tous les 16 temps, sans couplet chanté : la musique tient
  pendant tout le niveau.

**Ce qu'on change** :
- l'ambiance est **joyeuse et familiale**, pour des enfants de 9 ans, au lieu d'être sombre ;
- on ajoute des **touches basques** : txalaparta, accordéon trikitixa, pandero, txistu ;
- on ajoute une **montée de tension** dans les 20 dernières secondes, déjà prévue par
  SPEC-GORDEKA §9.

## 2. Bloc de base (à mettre en tête de chaque prompt)

```text
Upbeat retro electronic dance music for a cheerful children's party game, analog synth bass, bright arpeggiated synths, punchy drum machine, catchy hook, instrumental, playful and fun, family friendly, light Basque folk color.
```

Touches basques, à piocher (une ou deux par morceau) :
- `txalaparta wooden plank percussion playing interlocking rhythms` ;
- `trikitixa diatonic button accordion riff` ;
- `pandero frame drum with jingles` ;
- `txistu three-hole flute melody` ;
- `irrintzi-like joyful high call as a short sample`.

## 3. Morceaux

| Usage | BPM | Durée | Prompt (après le bloc de base) |
|---|---|---|---|
| Menu (si on veut une alternative à *Hegoak*) | 110 | 2 min, boucle | Warm synthwave groove at 110 BPM, mellow analog pads, gentle arpeggio, a trikitixa accordion melody answering the lead synth, relaxed sunset mood by the ocean, loopable. |
| Phase « cache-toi » | 120 | 30 s, boucle | Sneaky playful electro at 120 BPM, plucky staccato bass, tiptoe pizzicato synth, soft txalaparta clicks on the offbeats, a countdown feel, loopable. |
| Chasse (round) | 124 | 3 min, boucle | Bouncy French-house style party track at 124 BPM, four-on-the-floor kick, offbeat open hi-hats, filtered disco chords, funky slap synth bass, pandero jingles, a trikitixa accordion hook in the chorus, builds every 16 bars, loopable. |
| 20 dernières secondes | 132 | 20 s | Urgent but fun electro finale at 132 BPM, rising synth riser, rapid txalaparta rolls, driving octave bass, cheerful tension, ends on a bright accent. |
| Victoire des chassés | 120 | 8 s | Short triumphant festive jingle, bright brass synth stab, trikitixa flourish, pandero shake, happy ending chord. |
| Victoire du chasseur | 120 | 8 s | Short cheeky victory jingle, bouncy synth bass, playful whistle-like txistu run, cartoon sparkle, happy ending chord. |
| « Trouvé ! » | — | 1,5 s | Funny short surprise sting, cartoon boing, synth pluck going up, a quick pandero shake. |

**Exemple complet** (chasse), prêt à copier :

```text
Upbeat retro electronic dance music for a cheerful children's party game, analog synth bass, bright arpeggiated synths, punchy drum machine, catchy hook, instrumental, playful and fun, family friendly, light Basque folk color. Bouncy French-house style party track at 124 BPM, four-on-the-floor kick, offbeat open hi-hats, filtered disco chords, funky slap synth bass, pandero jingles, a trikitixa accordion hook in the chorus, builds every 16 bars, loopable.
```

## 4. Sons

Ils doivent être courts, synthétiques et passer par-dessus la musique :

| Son | Prompt |
|---|---|
| Alerte (vu par le chasseur) | short bright two-note synth blip rising, playful |
| Entrer dans une cachette | soft wooden thump with a muffled cloth swish |
| Piège | sticky cartoon squelch |
| Pas | soft tiny footstep tap |

Dans Party Hard, la bulle « ! » est accompagnée d'un blip et la police d'une sirène. Chez nous,
le « Trouvé ! » rigolo et le jingle de panique (SPEC §9) jouent ce rôle.
