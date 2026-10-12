class_name SimConst
extends RefCounted
## Constantes de la simulation (SPEC §4.6, §4.7, §8.2). Toutes entières.
## Positions et vitesses en sous-pixels : 1 px = 256 unités.

const SUB: int = 256

# --- Entrées (InputFrame, §8.3)
const UP: int = 1
const DOWN: int = 2
const LEFT: int = 4
const RIGHT: int = 8
const PUNCH: int = 16
const KICK: int = 32
const SPECIAL: int = 64
const GUARD: int = 128
const DIRS: int = 15
const BUTTONS: int = 240

# --- Arène (§4.6, §10.6)
const GROUND_Y: int = 196 * SUB
const WALL_L: int = 16 * SUB
const WALL_R: int = 560 * SUB
const WORLD_W: int = 576 * SUB
## Écart max entre les combattants : largeur de vue de référence − 2×24 px.
const MAX_SEPARATION: int = (384 - 48) * SUB
const START_X_P1: int = 218 * SUB
const START_X_P2: int = 358 * SUB

# --- Match
const ROUND_FRAMES: int = 60 * 60
const INTRO_FRAMES: int = 150
const INTRO_FIGHT_AT: int = 90
const KO_PAUSE_FRAMES: int = 120
const TIMEOUT_PAUSE_FRAMES: int = 120
const BUKATU_FRAMES: int = 240
const FINISHER_FRAMES: int = 270
## Distance max du finish : « 2 corps » (px).
const FINISHER_RANGE: int = 96 * SUB

# --- Ressenti (§4.7)
const HITSTOP_LIGHT: int = 4
const HITSTOP_HEAVY: int = 8
const HITSTOP_UPPERCUT: int = 14
const HITSTOP_SUPER: int = 20
const INPUT_BUFFER: int = 8
const AUTO_COMBO_WINDOW: int = 14
const MOTION_WINDOW: int = 20
const DOUBLE_TAP_WINDOW: int = 12
const COMBO_SCALE_STEP: int = 10
const COMBO_SCALE_MIN: int = 40
const COMBO_MAX_HITS: int = 6
const CLASSIC_BONUS_PCT: int = 10
const ENHANCED_BONUS_PCT: int = 30
const SUPER_DAMAGE_PCT: int = 30
const CHIP_PERMILLE: int = 150
const PREJUMP_FRAMES: int = 3
const LANDING_FRAMES: int = 4
const KNOCKDOWN_FRAMES: int = 36
const QUICK_KNOCKDOWN_FRAMES: int = 10
const GETUP_FRAMES: int = 24
const GETUP_INVULN: int = 20
const THROW_TECH_WINDOW: int = 10
const THROW_RANGE: int = 46 * SUB
const THROW_DAMAGE: int = 110
const TECH_PUSH: int = 900
## Recul quand le défenseur est au mur : appliqué à l'attaquant.
const CORNER_RECOIL_PCT: int = 100
const BLOCK_PUSH_EXTRA: int = 4 * SUB
const EASY_AUTOGUARD_PERMILLE: int = 300
const DIZZY_FRAMES: int = 240

# --- Jauge Marée (§4.4)
const METER_SEGMENT: int = 100
const METER_MAX: int = 300
const WAVE_RETURN_THRESHOLD_PCT: int = 25

# --- Niveaux de coups
const LVL_MID: int = 0
const LVL_LOW: int = 1
const LVL_AIR: int = 2
const LVL_THROW: int = 3
const LVL_UNBLOCKABLE: int = 4

# --- Phases du match
const PH_INTRO: int = 0
const PH_FIGHT: int = 1
const PH_KO: int = 2
const PH_BUKATU: int = 3
const PH_FINISHER: int = 4
const PH_END: int = 5

# --- États d'un combattant
const ST_STAND: int = 0
const ST_CROUCH: int = 1
const ST_PREJUMP: int = 2
const ST_AIR: int = 3
const ST_LAND: int = 4
const ST_MOVE: int = 5
const ST_BLOCK: int = 6
const ST_HITSTUN: int = 7
const ST_BLOCKSTUN: int = 8
const ST_AIR_HIT: int = 9
const ST_KNOCKDOWN: int = 10
const ST_GETUP: int = 11
const ST_THROWN: int = 12
const ST_DIZZY: int = 13
const ST_KO: int = 14
const ST_WIN: int = 15
const ST_INTRO: int = 16
const ST_FINISHER: int = 17
const ST_FINISHED: int = 18
const ST_RUN: int = 19
const ST_STUNNED: int = 20

# --- Animations (ordre des rangées, docs/PIPELINE_CONTRACT.md §3)
const ANIMS: PackedStringArray = [
	"intro", "idle", "walk", "run", "crouch", "crouch_idle", "jump_up", "jump_fwd",
	"fall", "block", "crouch_block", "punch_1", "punch_2", "punch_3", "kick",
	"kick_high", "crouch_punch", "sweep", "uppercut", "jump_punch", "jump_kick",
	"throw", "thrown", "hit_high", "hit_low", "hit_air", "knockdown", "getup",
	"dizzy", "ko", "win", "sp_neutral", "sp_forward", "sp_down", "sp_up", "super",
	"finisher",
]
const A_INTRO: int = 0
const A_IDLE: int = 1
const A_WALK: int = 2
const A_RUN: int = 3
const A_CROUCH: int = 4
const A_CROUCH_IDLE: int = 5
const A_JUMP_UP: int = 6
const A_JUMP_FWD: int = 7
const A_FALL: int = 8
const A_BLOCK: int = 9
const A_CROUCH_BLOCK: int = 10
const A_THROWN: int = 22
const A_HIT_HIGH: int = 23
const A_HIT_LOW: int = 24
const A_HIT_AIR: int = 25
const A_KNOCKDOWN: int = 26
const A_GETUP: int = 27
const A_DIZZY: int = 28
const A_KO: int = 29
const A_WIN: int = 30
const A_FINISHER: int = 36


static func anim_index(anim_name: String) -> int:
	return ANIMS.find(anim_name)
