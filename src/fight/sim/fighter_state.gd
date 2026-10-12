class_name FighterState
extends RefCounted
## État d'un combattant (entiers uniquement). Sérialisé champ par champ
## dans l'ordre de FIELDS : ajouter un champ = l'ajouter à FIELDS.

const FIELDS: PackedStringArray = [
	"x", "y", "vx", "vy", "facing", "health", "max_health", "meter",
	"state", "state_t", "move", "move_t", "move_hits", "move_last_hit",
	"move_connected", "move_bonus", "stun", "invuln", "armor_left",
	"combo_hits", "combo_damage", "air_attack_used", "jump_dir", "rounds",
	"wave_used", "anim", "anim_t", "slow", "chain_until", "chain_move",
	"tech_window", "thrower", "quick_rise", "damage_taken_round",
	"last_move", "ai_timer", "ai_hold", "ai_plan", "ai_losses", "hit_flash",
	"stunned", "landing_move", "finisher_done",
]

var x: int = 0
var y: int = SimConst.GROUND_Y
var vx: int = 0
var vy: int = 0
var facing: int = 1
var health: int = 1000
var max_health: int = 1000
var meter: int = 0
var state: int = SimConst.ST_STAND
var state_t: int = 0
var move: int = -1
var move_t: int = 0
var move_hits: int = 0          # touches déjà portées par le coup courant
var move_last_hit: int = -100   # move_t de la dernière touche
var move_connected: int = 0     # 0 rien, 1 touché, 2 gardé
var move_bonus: int = 0         # bonus de dégâts en % (classique, renforcé)
var stun: int = 0               # frames restantes de l'état subi
var invuln: int = 0
var armor_left: int = 0
var combo_hits: int = 0         # coups reçus dans le combo en cours
var combo_damage: int = 0
var air_attack_used: int = 0
var jump_dir: int = 0           # -1 arrière, 0 neutre, 1 avant
var rounds: int = 0
var wave_used: int = 0
var anim: int = SimConst.A_IDLE
var anim_t: int = 0
var slow: int = 0
var chain_until: int = 0        # frame (sim) limite d'enchaînement auto-combo
var chain_move: int = -1
var tech_window: int = 0        # victime d'une projection : frames pour la « tech »
var thrower: int = -1
var quick_rise: int = 0
var damage_taken_round: int = 0
var last_move: int = -1         # dernier coup lancé (lecture IA)
var ai_timer: int = 0
var ai_hold: int = 0            # masque tenu par l'IA entre deux décisions
var ai_plan: int = 0
var ai_losses: int = 0
var hit_flash: int = 0
var stunned: int = 0            # étourdi (sifflet, filet) : ne peut rien faire
var landing_move: int = 0
var finisher_done: int = 0


func is_airborne() -> bool:
	return y < SimConst.GROUND_Y or state == SimConst.ST_AIR or state == SimConst.ST_AIR_HIT


## Peut agir (marcher, frapper, garder) ?
func actionable() -> bool:
	return state == SimConst.ST_STAND or state == SimConst.ST_CROUCH \
		or state == SimConst.ST_BLOCK or state == SimConst.ST_RUN


func set_state(new_state: int, anim_id: int) -> void:
	state = new_state
	state_t = 0
	if anim != anim_id:
		anim = anim_id
		anim_t = 0


func set_anim(anim_id: int) -> void:
	if anim != anim_id:
		anim = anim_id
		anim_t = 0


func write(buf: StreamPeerBuffer) -> void:
	for field: String in FIELDS:
		buf.put_32(int(get(field)))


func read(buf: StreamPeerBuffer) -> void:
	for field: String in FIELDS:
		set(field, buf.get_32())
