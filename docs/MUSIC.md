# Musique : sources et droits

Toute la bande-son est **synthétisée** par `tools/gen_audio.py` (numpy, aucun échantillon tiers), exportée en OGG Vorbis mono 32 kHz (VBR qualité 0,55 : de 45 à 85 kbps selon la densité du morceau ; crête ≤ −3 dBFS vérifiée après décodage).

## Thèmes de décor : de vrais airs traditionnels basques (depuis le 2026-10-15)

Chaque décor a son propre morceau, bâti sur une **mélodie traditionnelle anonyme** relevée note à note dans un recueil vérifiable, puis harmonisée et orchestrée pour le jeu. L'harmonisation, l'introduction et l'orchestration sont **originales**. Les mélodies viennent :
- de la **Doinutegia** de Bertsozale Elkartea (`bdb.bertsozale.eus`). Pour chaque air, elle publie la partition et le MIDI de la transcription des grands recueils, avec le lieu et le siècle de la collecte. Les recueils sont ceux d'Azkue (*Cancionero popular vasco*, 1922), d'Aita Donostia, d'Iztueta (*Gipuzkoako dantzak*, 1824), de Salaberry (*Chants populaires du Pays Basque*, 1870) et de Santesteban (*Aires vascongados*, XIXe s.) ;
- ou, une seule fois (signalé plus bas), de la partition de l'article de la **Wikipédia en basque**.

Les notes écrites dans `gen_audio.py` ont été **comparées automatiquement** aux MIDI de la Doinutegia : les hauteurs sont identiques à 100 %. Seule différence : sur certains airs, la dernière note est allongée pour fermer la boucle (c'est signalé en commentaire dans le code).

Les timbres basques sont **évoqués** en synthèse :
- **txistu** : flûte à 3 trous. Son pur, souffle, attaque par en dessous, vibrato ;
- **trikitixa** : accordéon diatonique. Deux anches désaccordées qui battent, main gauche « um-pa » ;
- **alboka** : anche double en corne. Spectre nasal, bourdon ;
- **chœur** : 3 voix, voyelles « a / o » par formants ;
- **txalaparta** : planches frappées aux partiels inharmoniques, deux joueurs qui alternent ;
- **pandero** (tambourin à cymbalettes), **atabal** / tamboril (caisse claire), **bombo** ;
- **ttun-ttun** : tambour à cordes souletin ;
- cuivres de peña, cloche de port, vagues et foule (bruit filtré).

**Principe de droits.** On n'utilise que des airs **anonymes de tradition orale** (aucun auteur identifié), dans la version du collecteur, jamais dans un arrangement moderne. Ces airs ont été **écartés** après vérification :
- *Agur jaunak* : la version chantée aujourd'hui est l'adaptation de José Olaizola (1918), encore protégée ;
- *Txanton Piperri* : opéra de B. Zapirain (1899) ;
- *Hator hator* : des frères De la Fuente, de Durango ;
- *Isil-isilik* : de F. Goenaga ;
- *Ikusi mendizaleak* : de S. Gereño (1966) ;
- *Goizean argi hastean* : d'Etxahun-Iruri ;
- *Atun hegaluzea* : de J. M. Altuna ;
- *Maitia nun zira* : la version connue a été harmonisée par Uruñuela vers 1930 ;
- *Txoria txori* : de Mikel Laboa ;
- *Boga boga* : aucun relevé fiable de la mélodie trouvé.

Le jeu choisit la musique par le champ `music` de `assets/stages/<id>/stage.json` : `fight_scene._play_stage_music()` appelle `AudioManager.play_music()`, qui force la boucle. Chaque décor pointe sur son propre fichier. Les variantes `grande_plage_soir` et `cote_basques_crepuscule` reprennent le fichier du décor de jour. Contre le boss, c'est toujours `phare_sommet`.

| Décor (`music/<id>.ogg`) | Air traditionnel retenu | Source vérifiée (mélodie) | Forme, tonalité, tempo, durée | Instrumentation et idée |
|---|---|---|---|---|
| `grande_plage` | **O Pello Pello** (chanson à récapitulation, relevée à Azkaine au XIXe s.) | [Doinutegia : Azkue, *Cancionero* 875](https://bdb.bertsozale.eus/web/doinutegia/view/2169-o-pello-pello-i-oi-pello-pello-i) | Arin-arin 2/4, sol majeur, ♩=136, 45,9 s | Txistu seul, puis trikitixa à la tierce, puis tutti, sur main gauche « um-pa », pandero et bombo. Une fête ensoleillée sur la promenade. |
| `cote_basques` | **Untziak eder du bela** (« le bateau a de belles voiles », variante de *Uso xuria errazu*) | [Doinutegia : Azkue, manuscrits 274 (Hazparne, XIXe s.)](https://bdb.bertsozale.eus/web/doinutegia/view/2826-untziak-eder-du-bela-uso-xuriak-errazu-iii) | 2/4 balancé, la majeur, ♩=118, 52,9 s | Txistu, puis trikitixa en tierces, sur des arpèges de corde pincée (l'« écume »). Une vague toutes les deux mesures, avec l'écume dans l'aigu. |
| `port_pecheurs` | **Itsasoa laino dago** (« la mer est dans la brume », chant de marins) | [Doinutegia : Azkue, conférence de Bilbao 1901 ; Aita Donostia, *Itsasoetan* 33](https://bdb.bertsozale.eus/web/doinutegia/view/1993-itsasoa-laino-dago-i-a) | 3/4 calme, mi mineur, ♩=96, 63,8 s | 1er tour : chœur d'hommes (« o ») à deux voix. 2e tour : txistu doux sur le chœur tenu. Dessous : bourdon d'alboka très discret, cloche du port, clapot continu, coque contre le quai (txalaparta feutrée). |
| `rocher_vierge` | **Ene mutilik tipiena** (chanson de marins du Labourd : le mousse monte en haut du mât guetter la terre) | [Wikipédia basque, d'après Aita Donostia, *Gure Herrian* 1924 p. 231 (relevée à Azkaine)](https://eu.wikipedia.org/wiki/Ene_mutilik_tipiena). **Seule source qui n'est pas recoupée par un MIDI de la Doinutegia.** | 2/4 avec une mesure à 3/4, sol majeur, ♩=116, 55,3 s | Alboka nasale sur txalaparta « ttakun » (deux joueurs qui se répondent), puis txistu, puis alboka et txistu à la tierce. Bourdon de sol, vagues et embruns. |
| `port_vieux` | **Ama begira zazu** (« Maman, regarde-moi danser sur la place ») | [Doinutegia : Aita Donostia, *Gure Herria* 1924 ; *Itsasoetan*](https://bdb.bertsozale.eus/web/doinutegia/view/ama-begira-zazu) | Air à danser 2/4, sol majeur, ♩=120, 52,0 s | Txistu, puis deux txistus à la tierce, puis xirula à l'octave avec une corde pincée, le tout sur ttun-ttun (sol et ré pincés). Pandero léger, clapot. |
| `halles` | **Maritxu nora zoaz** (zortziko txiki : Maritxu et Bartolo se parlent à la fontaine) | [Doinutegia : Aita Donostia ; Santesteban, *Aires vascongados* 64 (Gartzain, Baztan)](https://bdb.bertsozale.eus/web/doinutegia/view/501-maritxu-nora-zoaz-i-maria-nora-zoaz) · [Wikipédia basque](https://eu.wikipedia.org/wiki/Maritxu,_nora_zoaz%3F) | Arin-arin 2/4, sol majeur, ♩=144, 56,7 s | Trikitixa : main droite seule, puis à la tierce, puis à l'octave avec un txistu doux. Main gauche « um-pa », pandero en doubles croches, bombo. Un marché couvert un jour de fête. |
| `fronton` | **Alpargatak urratuta / Azeri-dantza** (air de danse d'Iztueta, « esku-aldatzeko soinua ») | [Doinutegia : Iztueta, *Gipuzkoako dantzak* 49 (XVIIIe s.)](https://bdb.bertsozale.eus/web/doinutegia/view/2088-alpargatak-urratuta-azeri-dantza) | Danse vive 4/4, do majeur, ♩=168, 48,6 s | Txistu et atabal (tamboril « pa-ra-pam »), silbote en doublure aiguë au 2e tour. La pelote ponctue les silences de la danse (« pok », puis rebond sur le mur). |
| `stade` | **Pello Josepe tabernan dela** (chanson populaire relevée à Sare au XIXe s.) | [Doinutegia : Aita Donostia ; Santesteban, *Aires vascongados* 61](https://bdb.bertsozale.eus/web/doinutegia/view/1551-pello-josepe-tabernan-dela-i-a) · [Wikipédia basque (Azkue, Uitzi)](https://eu.wikipedia.org/wiki/Pello_Joxepe_(kanta)) | Marche de peña 2/4, sol majeur, ♩=144, 53,3 s | Cuivres à la tierce et tuba « um-pa », grosse caisse et caisses claires, applaudissements sur 2 et 4, clameur continue de la foule. Le txistu de la peña entre au 2e tour. |
| `aquarium` | **Haurtxo txikia negarrez dago** (berceuse) | [Doinutegia : M. Lekuona ; *Mariya* 35, *Donostiko kantu zaharrak* 111 (paroles déjà imprimées au XIXe s.)](https://bdb.bertsozale.eus/web/doinutegia/view/1468-haurtxo-txikia-negarrez-dago-i) | Berceuse 2/4, sol mineur, ♩=84, 51,4 s | Flûte feutrée, chœur « o » lointain, arpèges de harpe, txalaparta en sourdine et bulles ; reflets de cloche dans la 2e moitié. Calme et un peu mystérieux. |
| `phare_sommet` | **Haltzak ez du bihotzik / Berterretxen kantoria** (ballade souletine du XVe s.) | [Doinutegia : Salaberry 1870 p. 211 ; Azkue 417 ; Aita Donostia](https://bdb.bertsozale.eus/web/doinutegia/view/1843-haltzak-ez-du-bihotzik-i-berreterretxen-kantoria-belatsarena-aitak-eman-daut-dotea) | 2/4 solennel, mi dorien, ♩=104, 50,8 s | Le boss au crépuscule. 1er tour : chœur d'hommes et alboka sur des tambours de guerre. 2e tour : tutti (chœur à deux voix, txistu à l'octave, txalaparta lancée), sur un bourdon de mi. Sombre, jamais agressif. |

À signaler franchement :
- **Aucun thème de décor n'est une composition originale** : les 10 mélodies sont des airs traditionnels attestés. Seuls l'harmonisation, les introductions (2 à 4 mesures d'accompagnement) et l'orchestration sont de nous.
- *Ene mutilik tipiena* (Rocher de la Vierge) n'a qu'une source, la partition de la Wikipédia basque, qui cite Aita Donostia (1924) et Riezu (1948). Elle n'a pas été recoupée avec le recueil imprimé.
- *Ama begira zazu* et *Ene mutilik tipiena* ne sont connus que par les relevés d'Aita Donostia, mort en 1956. La mélodie est populaire et anonyme, et un simple relevé ne crée pas d'œuvre. Pour écarter toute discussion, un air de remplacement est prêt : *Iruten ari nuzu* (Salaberry 1870, [Doinutegia](https://bdb.bertsozale.eus/web/doinutegia/view/831-iruten-ari-nuzu-albanista-sagasta)).
- *Berterretxen kantoria* : nous suivons le relevé de la Doinutegia (Salaberry, Aita Donostia), **pas** la version enregistrée par Mikel Laboa, qui est protégée.
- *Haurtxo txikia* : relevé de Manuel Lekuona (XXe s.) d'une berceuse populaire anonyme, dont les paroles étaient déjà imprimées au XIXe s.

## Autres morceaux : compositions originales

Les autres morceaux (titre, menus, pyramide, fins, jingles) sont des **compositions originales** écrites dans une forme traditionnelle basque. Ces formes (fandango, aurresku, berceuse « lo-lo »…) sont des genres populaires anonymes, sans auteur. Ces morceaux gardent le timbre chiptune (carré, triangle, bruit LFSR, steel pan).

*Hegoak* (Txoria txori, musique de Mikel Laboa) est une œuvre protégée. Retirée en Phase 0, elle a été **rétablie le 2026-10-13 à la demande de Julien** sur l'accueil (titre, profils, menu, réglages) : `assets/audio/music/hegoak.mp3`, l'arrangement de l'ancien jeu. `title.ogg` reste dans le dépôt, prêt à servir si on la retire de nouveau.

| Fichier | Rôle | Forme traditionnelle (domaine public) | Mélodie | Notes d'arrangement |
|---|---|---|---|---|
| `music/title.ogg` | Écran titre | Marche d'honneur (ezpata-dantza / aurresku) | Originale, sol majeur, 4/4 | Lead carré 50 %, doublure steel pan à l'octave, basse fondamentale/quinte, arpèges 12,5 %, caisse claire de défilé. A B A, 55 s. |
| `music/select.ogg` | Sélection, menus | Fandango (3/4 vif) | Originale, ré majeur | Lead carré 25 %, basse valse, shaker au contretemps. A B A B A, 43 s. |
| `music/tower.ogg` | Pyramide du Phare | Aurresku (danse d'honneur, marche) | Originale, la mineur → do majeur | Tambour régulier qui « monte ». 50 s. |
| `music/victory.ogg` | Jingle de victoire | — | Originale | 3,4 s, non bouclé. |
| `music/txapeldun.ogg` | Fanfare « TXAPELDUN ! » | Fanfare de remise de prix | Originale, sol majeur (motif du titre) | Roulements de caisse claire, harmonie à la tierce. 8,5 s, non bouclé. |
| `music/ending.ogg` | Fins illustrées | Berceuse « lo-lo » (bercement 6/8) | Originale, fa majeur | Txistu simulé : triangle + vibrato lent, arpèges de steel pan, très doux. 51 s. |

Les musiques bouclées sont coupées exactement à la mesure, et la queue des dernières notes est repliée au début de la boucle : pas de trou ni de clic. `tools/check_music.py` le vérifie sur les fichiers décodés.

## Bruitages et jingles

- `sfx/` (31 fichiers, ≈ 0,3 Mo) : coups léger/lourd/uppercut/super, garde (« toc » de bois), coup dans le vide, saut, réception, projection, esquive, PLOUF, vague, super, spécial, projectile, K.O., parfait, round, tic du chrono, interface (ok/déplacement/refus), sifflet (Txomin), pelote (Xabi), goéland (Kaio), pince (Karramarro), feu (Ramuntxo), foule, éclaboussure, seau, BORROKA. Tous synthétisés, avec fondus d'entrée et de sortie (aucun clic) et une crête ≤ −3 dBFS après décodage.
- `voice/` : **pas de voix enregistrée**. Décision : annonces textuelles à l'écran et jingles chiptune courts (`borroka`, `bukatu`, `txapeldun`, `plouf`). La piste « voix enregistrées par les enfants » (SPEC §12) reste possible plus tard : il suffit de déposer des fichiers du même nom dans `assets/audio/voice/`.

## Régénérer

```bash
.venv/bin/pip install soundfile numpy        # libsndfile embarque Vorbis ; ffmpeg n'est pas requis
.venv/bin/python tools/gen_audio.py all       # ou : music | sfx | voice [noms…]
.venv/bin/python tools/check_music.py         # durée, crête, débit, raccord de boucle des 10 décors
```
