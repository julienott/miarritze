class_name AiBrain
extends RefCounted
## IA (SPEC §13) : produit un InputFrame par tick. Tourne DANS la sim
## (lit l'état, utilise le XRng de la sim) : les replays IA sont
## déterministes. Son état vit dans FighterState (ai_timer, ai_hold, ai_plan).
##
## Niveaux : 1 Facile, 2 Normal, 3 Expert, 4 boss.
## Mannequins d'entraînement : 10 inerte, 11 garde tout, 12 saute, 13 répète un coup.

const REACTION: PackedInt32Array = [24, 24, 14, 8, 7]
const GUARD_PERMILLE: PackedInt32Array = [150, 150, 450, 750, 800]

const PLAN_NONE: int = 0
const PLAN_COMBO: int = 1


static func think(sim: FightSim, p: int) -> int:
	var level: int = sim.ai_level[p]
	var me: FighterState = sim.f[p]
	if level >= 10:
		return _dummy(sim, p, level)
	if sim.phase != SimConst.PH_FIGHT and sim.phase != SimConst.PH_BUKATU:
		return 0
	var lv: int = clampi(level, 1, 4)
	var o: FighterState = sim.f[1 - p]
	var fwd: int = SimConst.RIGHT if o.x >= me.x else SimConst.LEFT
	var back: int = SimConst.LEFT if fwd == SimConst.RIGHT else SimConst.RIGHT
	# Phase finale : le vainqueur tente toujours le finish.
	if sim.phase == SimConst.PH_BUKATU:
		return _bukatu(sim, p, fwd)
	# Réaction défensive immédiate (garde) : vérifiée à chaque frame mais
	# tirée au sort une seule fois par coup adverse.
	if o.state == SimConst.ST_MOVE and o.move >= 0 and me.actionable() and me.ai_plan != -(o.move + 2):
		var omv: MoveDef = sim.defs[1 - p].moves[o.move]
		var dist: int = absi(o.x - me.x)
		if dist < 110 * SimConst.SUB or omv.spawn_projectile >= 0:
			me.ai_plan = -(o.move + 2)
			if sim.rng.chance(GUARD_PERMILLE[lv]):
				var low: bool = omv.hit_level == SimConst.LVL_LOW and (lv >= 3 or sim.rng.chance(300))
				me.ai_hold = SimConst.GUARD | (SimConst.DOWN if low else 0)
				me.ai_timer = omv.total - o.move_t + 2
				return me.ai_hold
	if me.ai_timer > 0:
		me.ai_timer -= 1
		var hold: int = me.ai_hold
		# Les boutons ne sont pressés qu'à la première frame d'une décision.
		if me.ai_plan == PLAN_COMBO and me.state == SimConst.ST_MOVE and me.ai_timer % 5 == 0:
			return hold | SimConst.PUNCH
		return hold & ~(SimConst.PUNCH | SimConst.KICK | SimConst.SPECIAL)
	return _decide(sim, p, lv, fwd, back)


static func _decide(sim: FightSim, p: int, lv: int, fwd: int, back: int) -> int:
	var me: FighterState = sim.f[p]
	var o: FighterState = sim.f[1 - p]
	var def: FighterDef = sim.defs[p]
	var rng: XRng = sim.rng
	var dist: int = absi(o.x - me.x) / SimConst.SUB
	var react: int = REACTION[lv]
	var out: int = 0
	me.ai_plan = PLAN_NONE
	me.ai_timer = react / 2 + rng.below(react / 2 + 1)
	if not me.actionable() and me.state != SimConst.ST_AIR:
		me.ai_hold = 0
		return 0
	# Facile : l'IA « respire » parfois.
	if lv == 1 and rng.chance(250):
		me.ai_hold = 0
		return 0
	# Anti-aérien.
	if o.is_airborne() and dist < 90 and o.state == SimConst.ST_AIR and rng.chance(def.ai_anti_air * (lv + 1) / 4):
		if def.m_sp[3] >= 0 and rng.chance(500):
			out = SimConst.UP | SimConst.SPECIAL
		else:
			out = SimConst.DOWN | back | SimConst.PUNCH
		me.ai_hold = 0
		me.ai_timer = 10
		return out
	# Super quand la jauge est pleine et l'adversaire proche.
	if me.meter >= SimConst.METER_MAX and dist < 80 and def.m_super >= 0 and rng.chance(400):
		me.ai_hold = 0
		me.ai_timer = 20
		return SimConst.SPECIAL | SimConst.GUARD
	# Punition (Expert) : l'adversaire rate un coup près de nous.
	if lv >= 3 and o.state == SimConst.ST_MOVE and o.move_connected == 0 and dist < 70 \
			and o.move_t > sim.defs[1 - p].moves[o.move].startup + sim.defs[1 - p].moves[o.move].active:
		me.ai_hold = 0
		me.ai_timer = 8
		return SimConst.DOWN | back | SimConst.PUNCH
	if dist > 130:
		if rng.chance(def.ai_zoning) and _has_projectile(def) and o.state != SimConst.ST_MOVE:
			me.ai_hold = 0
			me.ai_timer = react
			return SimConst.SPECIAL
		if rng.chance(300):
			me.ai_hold = fwd
			me.ai_timer = 4
			return fwd if (me.state == SimConst.ST_RUN or rng.chance(500)) else 0
		me.ai_hold = fwd
		return fwd
	if dist > 60:
		var r: int = rng.below(1000)
		if r < 120:
			me.ai_hold = fwd | SimConst.UP
			me.ai_timer = 14
			return fwd | SimConst.UP
		if r < 120 + def.ai_aggression / 4 and def.m_sp[1] >= 0:
			me.ai_hold = 0
			return fwd | SimConst.SPECIAL
		if r < 260 + def.ai_aggression / 4 and _has_projectile(def) and rng.chance(def.ai_zoning):
			me.ai_hold = 0
			return SimConst.SPECIAL
		me.ai_hold = fwd
		return fwd
	# Au contact.
	if me.state == SimConst.ST_AIR:
		return SimConst.KICK
	var pick: int = rng.below(100)
	if not def.ai_favorites.is_empty() and pick < 25:
		var fav: MoveDef = def.moves[def.ai_favorites[rng.below(def.ai_favorites.size())]]
		return _input_for(fav, fwd, back)
	if pick < 55:
		me.ai_plan = PLAN_COMBO
		me.ai_hold = 0
		me.ai_timer = 22
		return SimConst.PUNCH
	if pick < 68:
		return SimConst.DOWN | SimConst.KICK
	if pick < 78:
		return SimConst.KICK
	if pick < 86 and dist < 50:
		return fwd | SimConst.PUNCH
	if pick < 94:
		return SimConst.DOWN | back | SimConst.PUNCH
	me.ai_hold = back
	me.ai_timer = react
	return back


static func _input_for(mv: MoveDef, fwd: int, back: int) -> int:
	match mv.name:
		"sp_neutral":
			return SimConst.SPECIAL
		"sp_forward":
			return fwd | SimConst.SPECIAL
		"sp_down":
			return SimConst.DOWN | SimConst.SPECIAL
		"sp_up":
			return SimConst.UP | SimConst.SPECIAL
		"uppercut":
			return SimConst.DOWN | back | SimConst.PUNCH
		"sweep":
			return SimConst.DOWN | SimConst.KICK
		"kick_high":
			return fwd | SimConst.KICK
		"kick":
			return SimConst.KICK
	return SimConst.PUNCH


static func _has_projectile(def: FighterDef) -> bool:
	for slot: int in 4:
		var mi: int = def.m_sp[slot]
		if mi >= 0 and def.moves[mi].spawn_projectile >= 0 and slot == 0:
			return true
	return false


static func _bukatu(sim: FightSim, p: int, fwd: int) -> int:
	var me: FighterState = sim.f[p]
	if sim.winner != p:
		return 0
	var o: FighterState = sim.f[1 - p]
	if absi(o.x - me.x) > SimConst.FINISHER_RANGE - 16 * SimConst.SUB:
		return fwd
	# Bas, neutre, Bas + SPÉCIAL, sur 6 frames.
	var t: int = sim.phase_t % 12
	if t < 2:
		return SimConst.DOWN
	if t < 4:
		return 0
	if t < 6:
		return SimConst.DOWN | (SimConst.SPECIAL if t == 5 else 0)
	return 0


static func _dummy(sim: FightSim, p: int, level: int) -> int:
	var me: FighterState = sim.f[p]
	match level:
		11:
			return SimConst.GUARD
		12:
			return SimConst.UP if sim.frame % 60 < 2 else 0
		13:
			return SimConst.PUNCH if sim.frame % 50 == 0 else 0
	me.ai_hold = 0
	return 0
