class_name FighterDef
extends RefCounted
## Fiche de combat d'un personnage (entière, immuable pendant un match).

var id: String = ""
var display_name: String = ""
var health: int = 1000
var walk_fwd: int = 640
var walk_back: int = 512
var run_speed: int = 1100
var jump_v: int = -2300
var jump_h: int = 700
var gravity: int = 120
var push_w: int = 22 * 256
var push_h: int = 70 * 256
## Boîte de poussée asymétrique : le corps déborde davantage vers l'avant.
var push_front: int = 22 * 256
var push_back: int = 22 * 256
var no_light_recoil: bool = false
## Coups, indexés ; `move_by_name` pour la résolution des entrées.
var moves: Array[MoveDef] = []
var move_by_name: Dictionary = {}
var projectiles: Array[ProjectileDef] = []
## Hurtboxes par animation et par frame d'animation : Array[Array[PackedInt32Array]].
var hurt_by_anim: Array = []
var anim_frames: PackedInt32Array = []
var anim_fps: PackedInt32Array = []
var anim_loop: PackedInt32Array = []
var anim_hit: PackedInt32Array = []
## Profil d'IA, en pour-mille.
var ai_aggression: int = 500
var ai_zoning: int = 400
var ai_anti_air: int = 600
var ai_favorites: PackedInt32Array = []
## Raccourcis vers les coups normaux / spéciaux (index, -1 si absent).
var m_punch: int = -1
var m_kick: int = -1
var m_kick_high: int = -1
var m_crouch_punch: int = -1
var m_sweep: int = -1
var m_uppercut: int = -1
var m_jump_punch: int = -1
var m_jump_kick: int = -1
var m_throw: int = -1
var m_sp: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])     # neutre, avant, bas, haut
var m_sp_plus: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var m_super: int = -1


func move(name: String) -> int:
	return int(move_by_name.get(name, -1))
