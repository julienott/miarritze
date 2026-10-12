class_name FxEvents
extends RefCounted
## Événements émis par la sim pour la vue (son, vfx, shake, annonces).
## Format : PackedInt32Array [frame, type, acteur, x_px, y_px, param].
## La vue ne joue un événement qu'une fois par (frame, type, acteur) (§8.6).

const HIT: int = 1          # param = force (0 léger, 1 lourd, 2 uppercut, 3 super)
const BLOCK: int = 2
const PROJ_SPAWN: int = 3   # param = index du projectile
const PROJ_HIT: int = 4
const PROJ_CLASH: int = 5
const KO: int = 6           # acteur = perdant
const ROUND_START: int = 7  # param = numéro du round
const FIGHT: int = 8
const TIME_OVER: int = 9
const PERFECT: int = 10
const WAVE_RETURN: int = 11
const SUPER_START: int = 12
const JUMP: int = 13
const LAND: int = 14
const THROW: int = 15
const TECH: int = 16
const BUKATU: int = 17
const FINISHER: int = 18
const MATCH_END: int = 19   # acteur = vainqueur (-1 = nul)
const WHIFF: int = 20       # param = index du coup
const SPECIAL_START: int = 21  # param = index du coup
const COMBO: int = 22       # param = nombre de coups
const ROUND_END: int = 23   # acteur = vainqueur du round (-1 = nul)
const GETUP: int = 24
const SHAKE: int = 25       # param = amplitude px
const KNOCKDOWN: int = 26
const DIZZY: int = 27
const METER_UP: int = 28    # param = nouveau nombre de segments
