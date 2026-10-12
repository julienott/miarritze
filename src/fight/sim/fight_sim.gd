class_name FightSim
extends RefCounted
## Simulation de combat 100 % déterministe (SPEC §8.2) : entiers, XRng,
## aucun Node, ordre fixe (J1 puis J2, projectiles par id croissant).
## `step(in1, in2)` avance d'un tick ; `save_state()` / `load_state()` /
## `checksum()` servent au rollback, aux replays et aux tests.

# --- Configuration (identique des deux côtés, non sérialisée)
var defs: Array[FighterDef] = []
var rounds_to_win: int = 2
var finishers_enabled: bool = true
## Niveau d'IA par slot : 0 humain, 1 Facile, 2 Normal, 3 Expert, 4 boss,
## 10+ mannequin d'entraînement (cf. AiBrain).
var ai_level: PackedInt32Array = PackedInt32Array([0, 0])
## Garde automatique « Facile » (30 % des coups si le joueur ne touche à rien).
var autoguard: PackedInt32Array = PackedInt32Array([0, 0])
var start_health: PackedInt32Array = PackedInt32Array([0, 0])
## Entraînement : chrono figé, pas de K.O., vie rechargée hors combo.
var training: bool = false

# --- État (sérialisé)
var frame: int = 0
var phase: int = SimConst.PH_INTRO
var phase_t: int = 0
var round_num: int = 1
var timer: int = SimConst.ROUND_FRAMES
var hitstop: int = 0
var next_proj_id: int = 1
var winner: int = -2                 # -2 en cours, -1 nul, 0/1 vainqueur du match
var round_winner: int = -2
var f: Array[FighterState] = []
var buffers: Array[InputBuffer] = []
var projectiles: Array[ProjectileState] = []
var rng: XRng = XRng.new()

## Événements du dernier tick (consommés par la vue).
var events: Array[PackedInt32Array] = []


## `options` : rounds (1/3/5 → manches à gagner), seed, ai, autoguard,
## health (vie de départ par joueur, 0 = max), finishers.
func setup(def1: FighterDef, def2: FighterDef, options: Dictionary = {}) -> void:
	defs = [def1, def2]
	var rounds: int = int(options.get("rounds", 3))
	rounds_to_win = rounds / 2 + 1
	finishers_enabled = bool(options.get("finishers", true))
	rng.reseed(int(options.get("seed", 1)))
	var ai: Array = options.get("ai", [0, 0])
	ai_level = PackedInt32Array([int(ai[0]), int(ai[1])])
	var guard: Array = options.get("autoguard", [0, 0])
	autoguard = PackedInt32Array([int(guard[0]), int(guard[1])])
	training = bool(options.get("training", false))
	var health: Array = options.get("health", [0, 0])
	start_health = PackedInt32Array([int(health[0]), int(health[1])])
	f = [FighterState.new(), FighterState.new()]
	buffers = [InputBuffer.new(), InputBuffer.new()]
	projectiles = []
	frame = 0
	round_num = 1
	winner = -2
	for p: int in 2:
		f[p].max_health = defs[p].health
	_reset_round()


# ===================================================================== tick

func step(in1: int, in2: int) -> void:
	events.clear()
	frame += 1
	var inputs: PackedInt32Array = PackedInt32Array([in1, in2])
	for p: int in 2:
		if ai_level[p] > 0:
			inputs[p] = AiBrain.think(self, p)
	for p: int in 2:
		buffers[p].push(inputs[p] & 0xFF)
	if hitstop > 0:
		hitstop -= 1
		return
	phase_t += 1
	match phase:
		SimConst.PH_INTRO:
			_step_intro()
		SimConst.PH_FIGHT:
			_step_fight()
		SimConst.PH_KO:
			_step_ko()
		SimConst.PH_BUKATU:
			_step_bukatu()
		SimConst.PH_FINISHER:
			_step_finisher()
		SimConst.PH_END:
			_step_world(false)
	for p: int in 2:
		f[p].anim_t += 1
		if f[p].hit_flash > 0:
			f[p].hit_flash -= 1


func is_over() -> bool:
	return phase == SimConst.PH_END


func emit(type: int, actor: int, x: int, y: int, param: int = 0) -> void:
	events.append(PackedInt32Array([frame, type, actor, x / SimConst.SUB, y / SimConst.SUB, param]))


func opponent(p: int) -> int:
	return 1 - p


# ===================================================================== phases

func _step_intro() -> void:
	if phase_t == 1:
		emit(FxEvents.ROUND_START, -1, 0, 0, round_num)
	if phase_t == SimConst.INTRO_FIGHT_AT:
		emit(FxEvents.FIGHT, -1, 0, 0)
		for p: int in 2:
			f[p].set_state(SimConst.ST_STAND, SimConst.A_IDLE)
	if phase_t >= SimConst.INTRO_FRAMES:
		phase = SimConst.PH_FIGHT
		phase_t = 0


func _step_fight() -> void:
	_step_world(true)
	if training:
		timer = SimConst.ROUND_FRAMES
		for p: int in 2:
			var me: FighterState = f[p]
			me.health = maxi(me.health, 1)
			if me.combo_hits == 0 and me.actionable() and me.health < me.max_health:
				me.health = me.max_health
		return
	_check_wave_return()
	if f[0].health <= 0 or f[1].health <= 0:
		var w: int = -1
		if f[0].health > 0:
			w = 0
		elif f[1].health > 0:
			w = 1
		for p: int in 2:
			if f[p].health <= 0:
				_go_ko(p)
		hitstop = SimConst.HITSTOP_SUPER
		_end_round(w)
		return
	timer -= 1
	if timer <= 0:
		emit(FxEvents.TIME_OVER, -1, 0, 0)
		var r0: int = f[0].health * 1000 / f[0].max_health
		var r1: int = f[1].health * 1000 / f[1].max_health
		var w: int = -1
		if r0 > r1:
			w = 0
		elif r1 > r0:
			w = 1
		_end_round(w)


## Tick complet du monde. `fighting` = les coups peuvent toucher.
func _step_world(fighting: bool) -> void:
	for p: int in 2:
		_control(p)
	for p: int in 2:
		_advance_move(p)
	for p: int in 2:
		_physics(p)
	_push_apart()
	_update_facing()
	_step_projectiles()
	if fighting:
		_resolve_hits()
	for p: int in 2:
		_end_tick(p)


func _step_ko() -> void:
	_step_world(false)
	if phase_t == 50 and round_winner >= 0:
		var w: FighterState = f[round_winner]
		if not w.is_airborne():
			w.set_state(SimConst.ST_WIN, SimConst.A_WIN)
			w.vx = 0
	if phase_t < SimConst.KO_PAUSE_FRAMES:
		return
	var decided: bool = f[0].rounds >= rounds_to_win or f[1].rounds >= rounds_to_win
	if not decided:
		round_num += 1
		_reset_round()
		return
	if f[0].rounds >= rounds_to_win and f[1].rounds >= rounds_to_win:
		winner = -1
	else:
		winner = 0 if f[0].rounds >= rounds_to_win else 1
	if finishers_enabled and winner >= 0:
		var loser: FighterState = f[opponent(winner)]
		loser.health = 0
		loser.set_state(SimConst.ST_DIZZY, SimConst.A_DIZZY)
		loser.y = SimConst.GROUND_Y
		loser.vx = 0
		loser.vy = 0
		var w2: FighterState = f[winner]
		w2.set_state(SimConst.ST_STAND, SimConst.A_IDLE)
		w2.y = SimConst.GROUND_Y
		w2.vy = 0
		phase = SimConst.PH_BUKATU
		phase_t = 0
		emit(FxEvents.BUKATU, winner, loser.x, loser.y)
	else:
		_finish_match()


func _step_bukatu() -> void:
	var w: int = winner
	var me: FighterState = f[w]
	var loser: FighterState = f[opponent(w)]
	_step_world(false)
	if loser.state != SimConst.ST_DIZZY:
		loser.set_state(SimConst.ST_DIZZY, SimConst.A_DIZZY)
	if me.actionable() and _finisher_input(w) and absi(me.x - loser.x) <= SimConst.FINISHER_RANGE:
		buffers[w].consume(SimConst.SPECIAL)
		me.set_state(SimConst.ST_FINISHER, SimConst.A_FINISHER)
		me.vx = 0
		me.finisher_done = 1
		loser.set_state(SimConst.ST_FINISHED, SimConst.A_DIZZY)
		phase = SimConst.PH_FINISHER
		phase_t = 0
		emit(FxEvents.FINISHER, w, me.x, me.y)
		return
	if phase_t >= SimConst.BUKATU_FRAMES:
		loser.set_state(SimConst.ST_KO, SimConst.A_KO)
		_finish_match()


func _step_finisher() -> void:
	if phase_t >= SimConst.FINISHER_FRAMES:
		_finish_match()


func _finish_match() -> void:
	phase = SimConst.PH_END
	phase_t = 0
	emit(FxEvents.MATCH_END, winner, 0, 0)


## Bas, Bas + SPÉCIAL : deux appuis sur Bas dans les 30 dernières frames.
func _finisher_input(p: int) -> bool:
	var buf: InputBuffer = buffers[p]
	if not buf.pressed(SimConst.SPECIAL, 4):
		return false
	var downs: int = 0
	for ago: int in 30:
		if (buf.at(ago) & SimConst.DOWN) != 0 and (buf.at(ago + 1) & SimConst.DOWN) == 0:
			downs += 1
	return downs >= 2


func _end_round(w: int) -> void:
	round_winner = w
	if w >= 0:
		f[w].rounds += 1
		if f[w].damage_taken_round == 0:
			emit(FxEvents.PERFECT, w, f[w].x, f[w].y)
	else:
		f[0].rounds += 1
		f[1].rounds += 1
	emit(FxEvents.ROUND_END, w, 0, 0)
	phase = SimConst.PH_KO
	phase_t = 0


func _go_ko(p: int) -> void:
	var me: FighterState = f[p]
	me.health = 0
	me.move = -1
	me.set_state(SimConst.ST_KO, SimConst.A_KO)
	me.vy = -900
	me.vx = -me.facing * 500
	emit(FxEvents.KO, p, me.x, me.y)


func _reset_round() -> void:
	phase = SimConst.PH_INTRO
	phase_t = 0
	timer = SimConst.ROUND_FRAMES
	hitstop = 0
	round_winner = -2
	projectiles.clear()
	for p: int in 2:
		var me: FighterState = f[p]
		me.x = SimConst.START_X_P1 if p == 0 else SimConst.START_X_P2
		me.y = SimConst.GROUND_Y
		me.vx = 0
		me.vy = 0
		me.facing = 1 if p == 0 else -1
		me.health = me.max_health
		if round_num == 1 and start_health[p] > 0:
			me.health = mini(start_health[p], me.max_health)
		me.move = -1
		me.stun = 0
		me.invuln = 0
		me.combo_hits = 0
		me.combo_damage = 0
		me.slow = 0
		me.stunned = 0
		me.tech_window = 0
		me.damage_taken_round = 0
		me.air_attack_used = 0
		me.anim = -1
		if round_num == 1:
			me.set_state(SimConst.ST_INTRO, SimConst.A_INTRO)
		else:
			me.set_state(SimConst.ST_INTRO, SimConst.A_IDLE)


# ===================================================================== contrôle

func _control(p: int) -> void:
	var me: FighterState = f[p]
	var def: FighterDef = defs[p]
	var buf: InputBuffer = buffers[p]
	me.state_t += 1
	if me.invuln > 0:
		me.invuln -= 1
	if me.slow > 0:
		me.slow -= 1
	match me.state:
		SimConst.ST_HITSTUN, SimConst.ST_BLOCKSTUN:
			me.stun -= 1
			if me.stun <= 0:
				me.combo_hits = 0
				me.combo_damage = 0
				_to_neutral(p)
		SimConst.ST_KNOCKDOWN:
			me.stun -= 1
			if me.state_t <= 6 and buf.pressed(SimConst.GUARD, 6) and me.quick_rise == 0:
				me.quick_rise = 1
				me.stun = mini(me.stun, SimConst.QUICK_KNOCKDOWN_FRAMES)
			if me.stun <= 0:
				me.set_state(SimConst.ST_GETUP, SimConst.A_GETUP)
				me.stun = SimConst.GETUP_FRAMES
				me.invuln = SimConst.GETUP_INVULN
				me.combo_hits = 0
				me.combo_damage = 0
				emit(FxEvents.GETUP, p, me.x, me.y)
		SimConst.ST_GETUP, SimConst.ST_LAND, SimConst.ST_STUNNED:
			me.stun -= 1
			if me.stun <= 0:
				_to_neutral(p)
		SimConst.ST_PREJUMP:
			me.stun -= 1
			if me.stun <= 0:
				me.vy = def.jump_v
				me.vx = me.jump_dir * def.jump_h * me.facing
				me.y -= 1
				me.set_state(SimConst.ST_AIR,
					SimConst.A_JUMP_UP if me.jump_dir <= 0 else SimConst.A_JUMP_FWD)
				emit(FxEvents.JUMP, p, me.x, me.y)
		SimConst.ST_AIR:
			if me.air_attack_used == 0:
				_air_attack(p)
		SimConst.ST_MOVE:
			_move_cancels(p)
		SimConst.ST_THROWN:
			if me.tech_window > 0:
				me.tech_window -= 1
				if buf.pressed(SimConst.PUNCH, SimConst.THROW_TECH_WINDOW):
					buf.consume(SimConst.PUNCH)
					_tech_throw(p)
		SimConst.ST_STAND, SimConst.ST_CROUCH, SimConst.ST_BLOCK, SimConst.ST_RUN:
			if phase == SimConst.PH_FIGHT or phase == SimConst.PH_BUKATU:
				_decide(p)
			else:
				me.vx = 0


func _to_neutral(p: int) -> void:
	var me: FighterState = f[p]
	me.move = -1
	if me.is_airborne():
		me.set_state(SimConst.ST_AIR, SimConst.A_FALL)
	elif buffers[p].held(SimConst.DOWN):
		me.set_state(SimConst.ST_CROUCH, SimConst.A_CROUCH_IDLE)
	else:
		me.set_state(SimConst.ST_STAND, SimConst.A_IDLE)


func _decide(p: int) -> void:
	var me: FighterState = f[p]
	var def: FighterDef = defs[p]
	var buf: InputBuffer = buffers[p]
	var dir: int = buf.dir_now(me.facing)
	if _try_special(p):
		return
	if buf.pressed(SimConst.PUNCH):
		var mi: int = def.m_punch
		if dir == 1 or _down_then_up(buf, me.facing):
			mi = def.m_uppercut
		elif dir == 2 or dir == 3:
			mi = def.m_crouch_punch
		elif dir == 6 and _can_throw(p):
			mi = def.m_throw
		if mi >= 0:
			buf.consume(SimConst.PUNCH)
			_start_move(p, mi, 0)
			return
	if buf.pressed(SimConst.KICK):
		var mk: int = def.m_kick
		if dir == 1 or dir == 2 or dir == 3:
			mk = def.m_sweep
		elif dir == 6:
			mk = def.m_kick_high
		if mk >= 0:
			buf.consume(SimConst.KICK)
			_start_move(p, mk, 0)
			return
	var slow_div: int = 2 if me.slow > 0 else 1
	if buf.held(SimConst.GUARD):
		me.vx = 0
		var crouch: bool = dir <= 3
		var block_anim: int = SimConst.A_CROUCH_BLOCK if crouch else SimConst.A_BLOCK
		if me.state != SimConst.ST_BLOCK:
			me.set_state(SimConst.ST_BLOCK, block_anim)
		else:
			me.set_anim(block_anim)
		return
	if dir >= 7:
		me.jump_dir = 0 if dir == 8 else (1 if dir == 9 else -1)
		me.set_state(SimConst.ST_PREJUMP, SimConst.A_CROUCH)
		me.stun = SimConst.PREJUMP_FRAMES
		me.vx = 0
		return
	if dir <= 3:
		if me.state != SimConst.ST_CROUCH:
			me.set_state(SimConst.ST_CROUCH, SimConst.A_CROUCH)
		elif me.state_t > 6:
			me.set_anim(SimConst.A_CROUCH_IDLE)
		me.vx = 0
		return
	if dir == 6:
		if me.state == SimConst.ST_RUN or buf.double_tap_forward(me.facing):
			if me.state != SimConst.ST_RUN:
				me.set_state(SimConst.ST_RUN, SimConst.A_RUN)
			me.vx = def.run_speed * me.facing / slow_div
		else:
			if me.state != SimConst.ST_STAND:
				me.set_state(SimConst.ST_STAND, SimConst.A_WALK)
			me.set_anim(SimConst.A_WALK)
			me.vx = def.walk_fwd * me.facing / slow_div
		return
	if me.state != SimConst.ST_STAND:
		me.set_state(SimConst.ST_STAND, SimConst.A_IDLE)
	if dir == 4:
		me.set_anim(SimConst.A_WALK)
		me.vx = -def.walk_back * me.facing / slow_div
	else:
		me.set_anim(SimConst.A_IDLE)
		me.vx = 0


## « Bas puis Haut + POING » : Bas tenu dans les 10 frames, Haut maintenant.
func _down_then_up(buf: InputBuffer, facing: int) -> bool:
	var d: int = buf.dir_now(facing)
	if d < 7:
		return false
	for ago: int in range(1, 10):
		if InputBuffer.numpad(buf.at(ago), facing) <= 3:
			return true
	return false


func _can_throw(p: int) -> bool:
	var me: FighterState = f[p]
	var o: FighterState = f[opponent(p)]
	if defs[p].m_throw < 0 or o.is_airborne() or o.invuln > 0:
		return false
	if o.state == SimConst.ST_HITSTUN or o.state == SimConst.ST_KNOCKDOWN \
			or o.state == SimConst.ST_GETUP or o.state == SimConst.ST_THROWN \
			or o.state == SimConst.ST_BLOCKSTUN:
		return false
	return absi(o.x - me.x) <= SimConst.THROW_RANGE + defs[p].push_front


func _try_special(p: int) -> bool:
	var me: FighterState = f[p]
	var def: FighterDef = defs[p]
	var buf: InputBuffer = buffers[p]
	if buf.pressed(SimConst.SPECIAL):
		var dir: int = buf.dir_now(me.facing)
		var slot: int = 0
		if dir == 6 or dir == 9:
			slot = 1
		elif dir <= 3:
			slot = 2
		elif dir == 8 or dir == 7:
			slot = 3
		var guard: bool = buf.held(SimConst.GUARD)
		if guard and slot == 0 and me.meter >= SimConst.METER_MAX and def.m_super >= 0:
			buf.consume(SimConst.SPECIAL)
			me.meter = 0
			_start_move(p, def.m_super, 0)
			return true
		if guard and me.meter >= SimConst.METER_SEGMENT:
			var plus: int = def.m_sp_plus[slot] if def.m_sp_plus[slot] >= 0 else def.m_sp[slot]
			if plus >= 0:
				buf.consume(SimConst.SPECIAL)
				me.meter -= SimConst.METER_SEGMENT
				_start_move(p, plus, SimConst.ENHANCED_BONUS_PCT)
				return true
		var mi: int = def.m_sp[slot]
		if mi < 0:
			mi = def.m_sp[0]
		if mi >= 0 and (not me.is_airborne() or def.moves[mi].air_ok):
			buf.consume(SimConst.SPECIAL)
			_start_move(p, mi, 0)
			return true
	# Manipulations classiques : bonus de dégâts pour les experts (§4.4).
	for button: int in [SimConst.PUNCH, SimConst.KICK]:
		if not buf.pressed(button, 3):
			continue
		for slot2: int in 4:
			var ms: int = def.m_sp[slot2]
			if ms < 0:
				continue
			var mv: MoveDef = def.moves[ms]
			if mv.classic_button == button and buf.motion(mv.classic_dirs, me.facing):
				buf.consume(button)
				_start_move(p, ms, SimConst.CLASSIC_BONUS_PCT)
				return true
	return false


func _air_attack(p: int) -> void:
	var me: FighterState = f[p]
	var def: FighterDef = defs[p]
	var buf: InputBuffer = buffers[p]
	if buf.pressed(SimConst.SPECIAL):
		var dir: int = buf.dir_now(me.facing)
		var slot: int = 0
		if dir == 6 or dir == 9:
			slot = 1
		elif dir <= 3:
			slot = 2
		elif dir >= 7:
			slot = 3
		var ms: int = def.m_sp[slot]
		if ms >= 0 and def.moves[ms].air_ok:
			buf.consume(SimConst.SPECIAL)
			me.air_attack_used = 1
			_start_move(p, ms, 0)
			return
	var mi: int = -1
	if buf.pressed(SimConst.PUNCH):
		mi = def.m_jump_punch
		buf.consume(SimConst.PUNCH)
	elif buf.pressed(SimConst.KICK):
		mi = def.m_jump_kick
		buf.consume(SimConst.KICK)
	if mi >= 0:
		me.air_attack_used = 1
		_start_move(p, mi, 0)


func _move_cancels(p: int) -> void:
	var me: FighterState = f[p]
	var def: FighterDef = defs[p]
	var buf: InputBuffer = buffers[p]
	var mv: MoveDef = def.moves[me.move]
	if mv.chain_next >= 0 and me.move_t >= mv.startup + mv.active \
			and buf.pressed(SimConst.PUNCH, SimConst.AUTO_COMBO_WINDOW):
		buf.consume(SimConst.PUNCH)
		_start_move(p, mv.chain_next, 0)
		return
	if mv.cancel_specials and me.move_connected > 0 and me.move_t >= mv.startup:
		_try_special(p)


func _start_move(p: int, mi: int, bonus: int) -> void:
	var me: FighterState = f[p]
	var mv: MoveDef = defs[p].moves[mi]
	me.state = SimConst.ST_MOVE
	me.state_t = 0
	me.move = mi
	me.move_t = 0
	me.move_hits = 0
	me.move_last_hit = -100
	me.move_connected = 0
	me.move_bonus = bonus
	me.armor_left = mv.armor
	me.last_move = mi
	me.anim = mv.anim
	me.anim_t = 0
	if not me.is_airborne():
		me.vx = 0
	if mv.is_super:
		emit(FxEvents.SUPER_START, p, me.x, me.y)
		hitstop = maxi(hitstop, 30)
	elif mv.is_special:
		emit(FxEvents.SPECIAL_START, p, me.x, me.y, mi)


func _advance_move(p: int) -> void:
	var me: FighterState = f[p]
	if me.state != SimConst.ST_MOVE or me.move < 0:
		return
	var mv: MoveDef = defs[p].moves[me.move]
	var o: FighterState = f[opponent(p)]
	for v: PackedInt32Array in mv.velocity:
		if v[0] == me.move_t:
			me.vx = v[1] * me.facing
			if v[2] != 0:
				me.vy = v[2]
				if me.y >= SimConst.GROUND_Y:
					me.y = SimConst.GROUND_Y - 1
	if me.move_t == mv.spawn_frame and mv.spawn_projectile >= 0:
		_spawn_projectile(p, mv.spawn_projectile, mv.spawn_x, mv.spawn_y)
	if me.move_t == mv.teleport_frame:
		var side: int = 1 if o.x >= me.x else -1
		me.x = clampi(o.x + side * 56 * SimConst.SUB, SimConst.WALL_L, SimConst.WALL_R)
		me.facing = -side
	if me.move_t >= mv.invuln_from and me.move_t <= mv.invuln_to:
		me.invuln = maxi(me.invuln, 1)
	if mv.is_throw and me.move_t == mv.startup:
		if _can_throw(p):
			o.move = -1
			o.set_state(SimConst.ST_THROWN, SimConst.A_THROWN)
			o.tech_window = SimConst.THROW_TECH_WINDOW
			o.thrower = p
			o.vx = 0
			o.vy = 0
			me.move_connected = 1
			emit(FxEvents.THROW, p, me.x, me.y)
	if o.state == SimConst.ST_THROWN and o.thrower == p:
		o.x = me.x + me.facing * (defs[p].push_front + defs[opponent(p)].push_front)
		if o.tech_window <= 0 and me.move_t >= mv.startup + mv.active:
			_land_throw(p)


func _land_throw(p: int) -> void:
	var me: FighterState = f[p]
	var o: FighterState = f[opponent(p)]
	var dmg: int = SimConst.THROW_DAMAGE
	if me.move >= 0 and defs[p].moves[me.move].damage > 0:
		dmg = defs[p].moves[me.move].damage
	o.health = maxi(0, o.health - dmg)
	o.damage_taken_round += dmg
	o.thrower = -1
	o.set_state(SimConst.ST_AIR_HIT, SimConst.A_HIT_AIR)
	o.vx = me.facing * 700
	o.vy = -1300
	o.y = SimConst.GROUND_Y - 1
	o.hit_flash = 2
	_gain_meter(p, 8)
	_gain_meter(opponent(p), 4)
	hitstop = maxi(hitstop, SimConst.HITSTOP_HEAVY)
	emit(FxEvents.HIT, opponent(p), o.x, o.y - 40 * SimConst.SUB, 1)
	emit(FxEvents.SHAKE, -1, 0, 0, 4)


func _tech_throw(p: int) -> void:
	var o: FighterState = f[p]
	var t: int = o.thrower
	o.thrower = -1
	o.tech_window = 0
	o.set_state(SimConst.ST_BLOCKSTUN, SimConst.A_BLOCK)
	o.stun = 12
	if t >= 0:
		var me: FighterState = f[t]
		me.move = -1
		me.set_state(SimConst.ST_BLOCKSTUN, SimConst.A_BLOCK)
		me.stun = 12
		me.vx = -me.facing * SimConst.TECH_PUSH
		o.vx = me.facing * SimConst.TECH_PUSH
	emit(FxEvents.TECH, p, o.x, o.y)


func _end_tick(p: int) -> void:
	var me: FighterState = f[p]
	if me.state != SimConst.ST_MOVE or me.move < 0:
		return
	var mv: MoveDef = defs[p].moves[me.move]
	me.move_t += 1
	if me.move_t < mv.total:
		return
	var o: FighterState = f[opponent(p)]
	if o.state == SimConst.ST_THROWN and o.thrower == p:
		_land_throw(p)
	if me.move_connected == 0 and not mv.is_throw:
		emit(FxEvents.WHIFF, p, me.x, me.y, me.move)
	me.move = -1
	if me.is_airborne():
		me.set_state(SimConst.ST_AIR, SimConst.A_FALL)
	else:
		_to_neutral(p)


# ===================================================================== physique

func _physics(p: int) -> void:
	var me: FighterState = f[p]
	var def: FighterDef = defs[p]
	var airborne: bool = me.y < SimConst.GROUND_Y or me.vy < 0
	var slow_div: int = 2 if me.slow > 0 else 1
	if me.state == SimConst.ST_THROWN:
		return
	if airborne:
		me.vy += def.gravity / slow_div
		me.y += me.vy / slow_div
		me.x += me.vx / slow_div
		if me.y >= SimConst.GROUND_Y:
			me.y = SimConst.GROUND_Y
			me.vy = 0
			_land(p)
	else:
		me.x += me.vx / slow_div
		if me.state == SimConst.ST_HITSTUN or me.state == SimConst.ST_BLOCKSTUN \
				or me.state == SimConst.ST_KNOCKDOWN or me.state == SimConst.ST_LAND \
				or me.state == SimConst.ST_KO or me.state == SimConst.ST_GETUP:
			me.vx = me.vx * 3 / 4
	if me.x < SimConst.WALL_L:
		me.x = SimConst.WALL_L
	elif me.x > SimConst.WALL_R:
		me.x = SimConst.WALL_R


func _land(p: int) -> void:
	var me: FighterState = f[p]
	me.air_attack_used = 0
	match me.state:
		SimConst.ST_AIR_HIT:
			me.set_state(SimConst.ST_KNOCKDOWN, SimConst.A_KNOCKDOWN)
			me.stun = SimConst.KNOCKDOWN_FRAMES
			me.quick_rise = 0
			me.vx = me.vx / 2
			emit(FxEvents.KNOCKDOWN, p, me.x, me.y)
		SimConst.ST_KO:
			me.vx = me.vx / 2
			emit(FxEvents.LAND, p, me.x, me.y, 1)
		SimConst.ST_MOVE:
			var mv: MoveDef = defs[p].moves[me.move]
			if mv.air_ok and not mv.velocity.is_empty() and me.move_t < mv.startup + mv.active:
				# Coup aérien qui touche le sol en cours (piqué) : il glisse au sol.
				me.vy = 0
				return
			me.move = -1
			me.set_state(SimConst.ST_LAND, SimConst.A_CROUCH)
			me.stun = SimConst.LANDING_FRAMES
			me.vx = 0
			emit(FxEvents.LAND, p, me.x, me.y)
		SimConst.ST_HITSTUN, SimConst.ST_BLOCKSTUN, SimConst.ST_WIN, SimConst.ST_DIZZY:
			me.vx = 0
		_:
			me.set_state(SimConst.ST_LAND, SimConst.A_CROUCH)
			me.stun = SimConst.LANDING_FRAMES
			me.vx = 0
			emit(FxEvents.LAND, p, me.x, me.y)


func _push_apart() -> void:
	var a: FighterState = f[0]
	var b: FighterState = f[1]
	if a.state == SimConst.ST_THROWN or b.state == SimConst.ST_THROWN:
		return
	var dx: int = b.x - a.x
	# Chacun présente son avant s'il regarde l'autre, son dos sinon.
	var a_toward: bool = (dx >= 0) == (a.facing > 0)
	var b_toward: bool = (dx <= 0) == (b.facing < 0)
	var need: int = (defs[0].push_front if a_toward else defs[0].push_back) \
		+ (defs[1].push_front if b_toward else defs[1].push_back)
	var dist: int = absi(dx)
	var vertical: bool = absi(a.y - b.y) < (defs[0].push_h + defs[1].push_h) / 2
	if vertical and dist < need:
		var overlap: int = need - dist
		var side: int = 1 if dx > 0 else (-1 if dx < 0 else (1 if a.facing > 0 else -1))
		var half: int = overlap / 2
		a.x -= side * half
		b.x += side * (overlap - half)
		# Au mur, l'autre absorbe tout le recul.
		if a.x < SimConst.WALL_L:
			b.x += SimConst.WALL_L - a.x
			a.x = SimConst.WALL_L
		elif a.x > SimConst.WALL_R:
			b.x -= a.x - SimConst.WALL_R
			a.x = SimConst.WALL_R
		if b.x < SimConst.WALL_L:
			a.x += SimConst.WALL_L - b.x
			b.x = SimConst.WALL_L
		elif b.x > SimConst.WALL_R:
			a.x -= b.x - SimConst.WALL_R
			b.x = SimConst.WALL_R
	# La caméra garde les deux combattants dans la vue (§4.6).
	dx = b.x - a.x
	if absi(dx) > SimConst.MAX_SEPARATION:
		var excess: int = absi(dx) - SimConst.MAX_SEPARATION
		var side2: int = 1 if dx > 0 else -1
		var a_away: bool = a.vx * side2 < 0
		var b_away: bool = b.vx * side2 > 0
		if a_away and not b_away:
			a.x += side2 * excess
		elif b_away and not a_away:
			b.x -= side2 * excess
		else:
			a.x += side2 * (excess / 2)
			b.x -= side2 * (excess - excess / 2)


func _update_facing() -> void:
	for p: int in 2:
		var me: FighterState = f[p]
		var o: FighterState = f[opponent(p)]
		var grounded_ctrl: bool = me.state == SimConst.ST_STAND or me.state == SimConst.ST_CROUCH \
			or me.state == SimConst.ST_BLOCK or me.state == SimConst.ST_RUN \
			or me.state == SimConst.ST_LAND or me.state == SimConst.ST_PREJUMP \
			or me.state == SimConst.ST_INTRO or me.state == SimConst.ST_GETUP
		if not grounded_ctrl or o.x == me.x:
			continue
		var want: int = 1 if o.x > me.x else -1
		if want != me.facing:
			me.facing = want
			if me.state == SimConst.ST_RUN:
				me.set_state(SimConst.ST_STAND, SimConst.A_IDLE)


# ===================================================================== projectiles

func _spawn_projectile(p: int, index: int, ox: int, oy: int) -> void:
	var me: FighterState = f[p]
	var pd: ProjectileDef = defs[p].projectiles[index]
	var pr: ProjectileState = ProjectileState.new()
	pr.id = next_proj_id
	next_proj_id += 1
	pr.owner = p
	pr.src = p
	pr.def = index
	pr.facing = me.facing
	pr.x = me.x + me.facing * ox
	pr.y = me.y + oy
	pr.vx = pd.speed * me.facing
	pr.vy = pd.vy
	pr.life = pd.life
	pr.hits_left = pd.hits
	pr.bonus = me.move_bonus
	projectiles.append(pr)
	emit(FxEvents.PROJ_SPAWN, p, pr.x, pr.y, index)


func _step_projectiles() -> void:
	var keep: Array[ProjectileState] = []
	for pr: ProjectileState in projectiles:
		var pd: ProjectileDef = defs[pr.src].projectiles[pr.def]
		pr.age += 1
		pr.life -= 1
		if pd.returns and pr.returning == 0 and pr.age * 2 >= pd.life:
			pr.returning = 1
		if pr.returning == 1:
			var owner: FighterState = f[pr.owner]
			var toward: int = 1 if owner.x > pr.x else -1
			pr.vx = toward * pd.speed
			pr.facing = toward
			if absi(owner.x - pr.x) < 16 * SimConst.SUB and absi(owner.y - 50 * SimConst.SUB - pr.y) < 60 * SimConst.SUB:
				pr.life = 0
		pr.vy += pd.gravity
		pr.x += pr.vx
		pr.y += pr.vy
		if pd.gravity != 0 and pr.y >= SimConst.GROUND_Y:
			pr.life = 0
		if pr.x < -32 * SimConst.SUB or pr.x > SimConst.WORLD_W + 32 * SimConst.SUB:
			pr.life = 0
		if pr.life > 0 and pr.hits_left > 0:
			keep.append(pr)
	projectiles = keep
	# Chocs entre projectiles adverses.
	for i: int in projectiles.size():
		for j: int in range(i + 1, projectiles.size()):
			var a: ProjectileState = projectiles[i]
			var b: ProjectileState = projectiles[j]
			if a.owner == b.owner or a.life <= 0 or b.life <= 0:
				continue
			var pa: ProjectileDef = defs[a.src].projectiles[a.def]
			var pb: ProjectileDef = defs[b.src].projectiles[b.def]
			if pa.trap or pb.trap:
				continue
			if Collision.overlap(Collision.world(pa.hitbox, a.x, a.y, a.facing),
					Collision.world(pb.hitbox, b.x, b.y, b.facing)):
				if not (pa.heavy and not pb.heavy):
					a.life = 0
				if not (pb.heavy and not pa.heavy):
					b.life = 0
				emit(FxEvents.PROJ_CLASH, -1, (a.x + b.x) / 2, (a.y + b.y) / 2)


# ===================================================================== touches

func _resolve_hits() -> void:
	# On collecte toutes les touches puis on les applique : les échanges
	# de coups (trades) sont simultanés et l'ordre n'avantage personne.
	var pending: Array[PackedInt32Array] = []   # [type 0 coup / 1 projectile, attaquant, index]
	for p: int in 2:
		var me: FighterState = f[p]
		var o: FighterState = f[opponent(p)]
		if me.state != SimConst.ST_MOVE or me.move < 0:
			continue
		var mv: MoveDef = defs[p].moves[me.move]
		if mv.is_throw or not mv.is_active_frame(me.move_t):
			continue
		if me.move_hits >= mv.hits:
			continue
		if me.move_hits > 0 and (mv.rehit_interval <= 0 or me.move_t - me.move_last_hit < mv.rehit_interval):
			continue
		var boxes: Array[PackedInt32Array] = MoveRunner.hitboxes(defs[p], me)
		if mv.reflects:
			_reflect(p, boxes)
		if not _hittable(opponent(p)):
			continue
		if _boxes_touch(boxes, MoveRunner.hurtboxes(defs[opponent(p)], o)):
			pending.append(PackedInt32Array([0, p, me.move]))
	for pr: ProjectileState in projectiles:
		var target: int = opponent(pr.owner)
		if pr.hits_left <= 0 or not _hittable(target):
			continue
		var pd: ProjectileDef = defs[pr.src].projectiles[pr.def]
		if pr.age - pr.last_hit < pd.rehit_interval and pr.last_hit >= 0:
			continue
		var box: PackedInt32Array = Collision.world(pd.hitbox, pr.x, pr.y, pr.facing)
		if _boxes_touch([box], MoveRunner.hurtboxes(defs[target], f[target])):
			pending.append(PackedInt32Array([1, pr.owner, pr.id]))
	for hit: PackedInt32Array in pending:
		if hit[0] == 0:
			_apply_move_hit(hit[1], hit[2])
		else:
			_apply_projectile_hit(hit[2])


func _hittable(p: int) -> bool:
	var me: FighterState = f[p]
	if me.invuln > 0 or me.health <= 0:
		return false
	return not (me.state == SimConst.ST_KNOCKDOWN or me.state == SimConst.ST_GETUP
		or me.state == SimConst.ST_THROWN or me.state == SimConst.ST_KO
		or me.state == SimConst.ST_INTRO)


func _boxes_touch(a: Array, b: Array) -> bool:
	for box_a: Variant in a:
		for box_b: Variant in b:
			if Collision.overlap(box_a as PackedInt32Array, box_b as PackedInt32Array):
				return true
	return false


func _reflect(p: int, boxes: Array[PackedInt32Array]) -> void:
	for pr: ProjectileState in projectiles:
		if pr.owner == p:
			continue
		var pd: ProjectileDef = defs[pr.src].projectiles[pr.def]
		if pd.trap:
			continue
		var box: PackedInt32Array = Collision.world(pd.hitbox, pr.x, pr.y, pr.facing)
		if _boxes_touch(boxes, [box]):
			# Le projectile change de camp : il garde ses données d'origine.
			pr.vx = -pr.vx
			pr.facing = -pr.facing
			pr.returning = 2
			pr.owner = p
			pr.age = 0
			pr.life = maxi(pr.life, 40)
			emit(FxEvents.PROJ_CLASH, p, pr.x, pr.y)


## Peut garder ce niveau de coup ?
func _blocks(p: int, level: int) -> bool:
	var me: FighterState = f[p]
	if level == SimConst.LVL_THROW or level == SimConst.LVL_UNBLOCKABLE:
		return false
	var guarding: bool = me.state == SimConst.ST_BLOCK or me.state == SimConst.ST_BLOCKSTUN
	var crouching: bool = me.anim == SimConst.A_CROUCH_BLOCK
	if not guarding and autoguard[p] != 0 and me.actionable() \
			and buffers[p].current() == 0 and rng.chance(SimConst.EASY_AUTOGUARD_PERMILLE):
		guarding = true
		crouching = level == SimConst.LVL_LOW
		me.set_state(SimConst.ST_BLOCK, SimConst.A_CROUCH_BLOCK if crouching else SimConst.A_BLOCK)
	if not guarding or me.is_airborne():
		return false
	if level == SimConst.LVL_LOW and not crouching:
		return false
	if level == SimConst.LVL_AIR and crouching:
		return false
	return true


func _apply_move_hit(p: int, mi: int) -> void:
	var me: FighterState = f[p]
	var mv: MoveDef = defs[p].moves[mi]
	var result: int = _apply_damage(p, mv.damage, mv.hitstun, mv.blockstun, mv.pushback,
		mv.hit_level, mv.knockdown, mv.launch_vx, mv.launch_vy, mv.hitstop,
		mv.meter_gain, mv.chip_permille, me.move_bonus, mv.pull_on_hit,
		mv.stun_on_hit, mv.slow_on_hit, mv.steal_meter, me.x, me.y)
	me.move_hits += 1
	me.move_last_hit = me.move_t
	if result > 0 and me.move_connected != 1:
		me.move_connected = result


func _apply_projectile_hit(proj_id: int) -> void:
	for pr: ProjectileState in projectiles:
		if pr.id != proj_id:
			continue
		var pd: ProjectileDef = defs[pr.src].projectiles[pr.def]
		_apply_damage(pr.owner, pd.damage, pd.hitstun, pd.blockstun, 4 * SimConst.SUB,
			pd.hit_level, pd.knockdown, pd.launch_vx, pd.launch_vy, pd.hitstop,
			pd.meter_gain, pd.chip_permille, pr.bonus, pd.pull_on_hit,
			pd.stun_on_hit, pd.slow_on_hit, 0, pr.x - pr.facing * 64 * SimConst.SUB, pr.y)
		pr.hits_left -= 1
		pr.last_hit = pr.age
		emit(FxEvents.PROJ_HIT, pr.src, pr.x, pr.y, pr.def)
		if pr.hits_left <= 0:
			pr.life = 0
		return


## Applique un coup de `p` sur son adversaire. Renvoie 1 touché, 2 gardé, 0 annulé.
func _apply_damage(p: int, damage: int, hitstun: int, blockstun: int, pushback: int,
		level: int, knockdown: bool, launch_vx: int, launch_vy: int, stop: int,
		gain: int, chip: int, bonus: int, pull: int, stun_hit: int, slow_hit: int,
		steal: int, src_x: int, src_y: int) -> int:
	var d: int = opponent(p)
	var a: FighterState = f[p]
	var v: FighterState = f[d]
	var away: int = 1 if v.x >= src_x else -1
	# Contre (Karramarro) : un coup reçu pendant la fenêtre active déclenche la riposte.
	if v.state == SimConst.ST_MOVE and v.move >= 0:
		var vm: MoveDef = defs[d].moves[v.move]
		if vm.counter_move >= 0 and vm.is_active_frame(v.move_t):
			_start_move(d, vm.counter_move, 0)
			v.invuln = 6
			emit(FxEvents.BLOCK, d, v.x, v.y - 50 * SimConst.SUB)
			return 0
	# Effet seul (pavillon rouge, vol de jauge…) : ni dégâts ni étourdissement.
	if damage == 0 and hitstun == 0:
		if slow_hit > 0:
			v.slow = maxi(v.slow, slow_hit)
		if steal > 0:
			var stolen: int = mini(steal, v.meter)
			v.meter -= stolen
			a.meter = mini(SimConst.METER_MAX, a.meter + stolen)
		return 1
	if _blocks(d, level):
		if chip > 0 and damage > 0:
			var chip_dmg: int = damage * chip / 1000
			v.health = maxi(1, v.health - chip_dmg)
			v.damage_taken_round += chip_dmg
		v.set_state(SimConst.ST_BLOCKSTUN, v.anim if v.anim == SimConst.A_CROUCH_BLOCK else SimConst.A_BLOCK)
		v.stun = blockstun
		v.vx = away * (pushback + SimConst.BLOCK_PUSH_EXTRA) / 4
		if _at_wall(v):
			a.vx = -away * (pushback + SimConst.BLOCK_PUSH_EXTRA) / 4
		_gain_meter(p, gain / 2)
		_gain_meter(d, gain / 2)
		hitstop = maxi(hitstop, maxi(stop / 2, 3))
		emit(FxEvents.BLOCK, d, v.x, src_y - 0, 0)
		return 2
	var scale: int = maxi(SimConst.COMBO_SCALE_MIN, 100 - SimConst.COMBO_SCALE_STEP * v.combo_hits)
	var dmg: int = maxi(1, damage * scale / 100 * (100 + bonus) / 100) if damage > 0 else 0
	if v.state == SimConst.ST_MOVE and v.armor_left > 0:
		# Super-armure : encaisse sans être interrompu.
		v.armor_left -= 1
		v.health = maxi(0, v.health - dmg)
		v.damage_taken_round += dmg
		v.hit_flash = 2
		hitstop = maxi(hitstop, stop)
		emit(FxEvents.HIT, d, v.x, v.y - 50 * SimConst.SUB, 0)
		return 1
	v.health = maxi(0, v.health - dmg)
	v.damage_taken_round += dmg
	v.combo_hits += 1
	v.combo_damage += dmg
	v.hit_flash = 2
	v.move = -1
	v.tech_window = 0
	_gain_meter(p, gain)
	_gain_meter(d, gain / 2)
	if steal > 0:
		var taken: int = mini(steal, v.meter)
		v.meter -= taken
		a.meter = mini(SimConst.METER_MAX, a.meter + taken)
	if slow_hit > 0:
		v.slow = maxi(v.slow, slow_hit)
	var force_down: bool = v.combo_hits >= SimConst.COMBO_MAX_HITS
	if knockdown or launch_vy != 0 or v.is_airborne() or force_down:
		v.set_state(SimConst.ST_AIR_HIT, SimConst.A_HIT_AIR)
		v.vx = away * (launch_vx if launch_vx != 0 else 420)
		v.vy = launch_vy if launch_vy != 0 else -900
		if force_down:
			v.vy = mini(v.vy, -900)
		v.y = mini(v.y, SimConst.GROUND_Y - 1)
		v.stun = 0
	else:
		var crouched: bool = v.anim == SimConst.A_CROUCH or v.anim == SimConst.A_CROUCH_IDLE \
			or v.anim == SimConst.A_CROUCH_BLOCK or v.state == SimConst.ST_CROUCH
		v.set_state(SimConst.ST_HITSTUN, SimConst.A_HIT_LOW if crouched else SimConst.A_HIT_HIGH)
		v.anim_t = 0
		v.stun = maxi(hitstun, stun_hit)
		v.vx = away * pushback / 4
		if _at_wall(v):
			a.vx = -away * pushback / 4
	if pull != 0:
		v.vx = -away * pull
	hitstop = maxi(hitstop, stop)
	var strength: int = 0
	if stop >= SimConst.HITSTOP_SUPER:
		strength = 3
	elif stop >= SimConst.HITSTOP_UPPERCUT:
		strength = 2
	elif stop >= SimConst.HITSTOP_HEAVY:
		strength = 1
	emit(FxEvents.HIT, d, v.x, src_y - 0, strength)
	emit(FxEvents.SHAKE, -1, 0, 0, [0, 2, 4, 6][strength])
	if v.combo_hits >= 2:
		emit(FxEvents.COMBO, p, v.x, v.y, v.combo_hits)
	return 1


func _at_wall(v: FighterState) -> bool:
	return v.x <= SimConst.WALL_L + 2 * SimConst.SUB or v.x >= SimConst.WALL_R - 2 * SimConst.SUB


func _gain_meter(p: int, amount: int) -> void:
	var me: FighterState = f[p]
	var before: int = me.meter / SimConst.METER_SEGMENT
	me.meter = mini(SimConst.METER_MAX, me.meter + amount)
	var after: int = me.meter / SimConst.METER_SEGMENT
	if after > before:
		emit(FxEvents.METER_UP, p, me.x, me.y, after)


func _check_wave_return() -> void:
	for p: int in 2:
		var me: FighterState = f[p]
		if me.wave_used == 0 and me.health > 0 and me.health * 100 < me.max_health * SimConst.WAVE_RETURN_THRESHOLD_PCT:
			me.wave_used = 1
			me.meter = SimConst.METER_MAX
			emit(FxEvents.WAVE_RETURN, p, me.x, me.y)


# ===================================================================== état

func save_state() -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	for value: int in [frame, phase, phase_t, round_num, timer, hitstop, next_proj_id,
			winner, round_winner, rng.state]:
		buf.put_32(value)
	for p: int in 2:
		f[p].write(buf)
		buffers[p].write(buf)
	buf.put_u8(projectiles.size())
	for pr: ProjectileState in projectiles:
		pr.write(buf)
	return buf.data_array


## Phase du match lue directement dans un état sérialisé (sans le charger).
## Couplée à l'ordre d'écriture de save_state : frame, puis phase.
static func phase_of_state(bytes: PackedByteArray) -> int:
	return bytes.decode_s32(4) if bytes.size() >= 8 else -1


func load_state(bytes: PackedByteArray) -> void:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = bytes
	frame = buf.get_32()
	phase = buf.get_32()
	phase_t = buf.get_32()
	round_num = buf.get_32()
	timer = buf.get_32()
	hitstop = buf.get_32()
	next_proj_id = buf.get_32()
	winner = buf.get_32()
	round_winner = buf.get_32()
	rng.state = buf.get_32() & XRng.MASK
	for p: int in 2:
		f[p].read(buf)
		buffers[p].read(buf)
	projectiles = []
	var count: int = buf.get_u8()
	for i: int in count:
		var pr: ProjectileState = ProjectileState.new()
		pr.read(buf)
		projectiles.append(pr)
	events.clear()


## Hash FNV-1a 32 bits de l'état sérialisé.
func checksum() -> int:
	return Fnv.hash32(save_state())
