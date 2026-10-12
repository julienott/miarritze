class_name MoveRunner
extends RefCounted
## Exécute la frame data d'un coup : démarrage, vitesses, projectiles,
## invulnérabilité, téléportation, et calcul de la frame d'animation.


## Frame d'animation à afficher pour un combattant (partagé sim / vue).
## Pendant un coup, l'animation est calée sur la frame data : les frames
## avant `hit_frame` couvrent le startup, `hit_frame` la fenêtre active,
## la suite la récupération.
static func anim_frame(def: FighterDef, me: FighterState) -> int:
	var anim: int = me.anim
	var frames: int = maxi(def.anim_frames[anim], 1) if anim < def.anim_frames.size() else 1
	if me.state == SimConst.ST_MOVE and me.move >= 0:
		var mv: MoveDef = def.moves[me.move]
		if mv.anim == anim:
			return move_anim_frame(def, mv, me.move_t, frames)
	var fps: int = def.anim_fps[anim] if anim < def.anim_fps.size() else 10
	var index: int = me.anim_t * fps / 60
	var loops: bool = anim < def.anim_loop.size() and def.anim_loop[anim] != 0
	if loops:
		return index % frames
	return mini(index, frames - 1)


static func move_anim_frame(def: FighterDef, mv: MoveDef, move_t: int, frames: int) -> int:
	var hit: int = clampi(def.anim_hit[mv.anim] if mv.anim < def.anim_hit.size() else frames / 2, 0, frames - 1)
	if move_t < mv.startup:
		return move_t * hit / maxi(mv.startup, 1)
	if move_t < mv.startup + mv.active:
		return hit
	var after: int = frames - hit - 1
	if after <= 0:
		return hit
	var rec_t: int = move_t - mv.startup - mv.active
	return mini(hit + 1 + rec_t * after / maxi(mv.recovery, 1), frames - 1)


## Hurtboxes monde du combattant à cette frame.
static func hurtboxes(def: FighterDef, me: FighterState) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var local: Array = []
	if me.anim < def.hurt_by_anim.size():
		var per_frame: Array = def.hurt_by_anim[me.anim]
		if not per_frame.is_empty():
			local = per_frame[mini(anim_frame(def, me), per_frame.size() - 1)]
	if local.is_empty():
		local = [_default_hurt(def, me)]
	for box: Variant in local:
		out.append(Collision.world(box as PackedInt32Array, me.x, me.y, me.facing))
	return out


static func _default_hurt(def: FighterDef, me: FighterState) -> PackedInt32Array:
	var w: int = def.push_w
	var h: int = def.push_h + 20 * SimConst.SUB
	if me.state == SimConst.ST_CROUCH or me.anim == SimConst.A_CROUCH_BLOCK \
			or me.anim == SimConst.A_CROUCH_IDLE or me.anim == SimConst.A_HIT_LOW:
		h = h * 6 / 10
	elif me.state == SimConst.ST_KNOCKDOWN:
		return PackedInt32Array([-2 * w, -20 * SimConst.SUB, 4 * w, 20 * SimConst.SUB])
	return PackedInt32Array([-w, -h, 2 * w, h])


## Hitboxes monde du coup courant (vide hors fenêtre active).
static func hitboxes(def: FighterDef, me: FighterState) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	if me.state != SimConst.ST_MOVE or me.move < 0:
		return out
	var mv: MoveDef = def.moves[me.move]
	if not mv.is_active_frame(me.move_t):
		return out
	for box: PackedInt32Array in mv.hitboxes:
		out.append(Collision.world(box, me.x, me.y, me.facing))
	return out
