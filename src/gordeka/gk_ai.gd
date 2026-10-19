class_name GkAi
extends RefCounted
## IA d'un joueur (SPEC-GORDEKA §10). Elle ne voit que ce que voit son rôle :
## un chassé voit toute la carte (et le chasseur) ; le chasseur ne sait que ce qu'il voit,
## ce que lui donnent ses ondes, les pièges qu'il déclenche et les cachettes qui tremblent.

var g: GkGame
var me: GkActor
var level: String
var cfg: Dictionary
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var path: PackedVector2Array = PackedVector2Array()
var path_i: int = 0
var think_t: float = 0.0
var want_action: bool = false
var plan_cachette: int = -1
var going_exit: bool = false
var relocate_t: float = 0.0
var scan_t: float = 0.0
var clue: Vector2 = Vector2.INF
var clue_t: float = 0.0
var chase_id: int = -1
var visited: Dictionary = {}         # zone → instant de la dernière visite
var clock: float = 0.0
var _stuck_t: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _react_t: float = 0.0


func _init(p_game: GkGame, p_me: GkActor, p_level: String) -> void:
	g = p_game
	me = p_me
	level = p_level
	cfg = GkRules.ai(p_level)
	rng.seed = hash(p_me.id * 7919 + 17)


## Change de niveau (QA : chasseur IA d'un autre niveau que les chassés).
func set_level(p_level: String) -> void:
	level = p_level
	cfg = GkRules.ai(p_level)


func reset() -> void:
	path = PackedVector2Array()
	plan_cachette = -1
	going_exit = false
	relocate_t = float(cfg.get("relocate", 25.0)) * rng.randf_range(0.6, 1.4)
	scan_t = 0.0
	clue = Vector2.INF
	clue_t = 0.0
	chase_id = -1
	think_t = rng.randf_range(0.0, 0.6)


func update(dt: float) -> Dictionary:
	clock += dt
	clue_t = maxf(0.0, clue_t - dt)
	scan_t = maxf(0.0, scan_t - dt)
	if me.frozen or me.search_left > 0.0:
		return {}
	if me.role == GkActor.Role.OUT:
		return {}
	think_t -= dt
	if think_t <= 0.0:
		think_t = float(cfg.get("think", 0.5))
		match me.role:
			GkActor.Role.HIDER:
				_think_hider()
			GkActor.Role.HUNTER:
				_think_hunter()
			GkActor.Role.GHOST:
				_think_ghost()
	# Coincé contre un obstacle : on refait le chemin.
	if me.position.distance_to(_last_pos) < 2.0 and path_i < path.size():
		_stuck_t += dt
		if _stuck_t > 1.2:
			_stuck_t = 0.0
			if path.size() > 0:
				_go(path[path.size() - 1])
	else:
		_stuck_t = 0.0
	_last_pos = me.position
	var out: Dictionary = {"move": _follow(dt)}
	if me.role == GkActor.Role.HUNTER and scan_t > 0.0 and out["move"] == Vector2.ZERO:
		out["look"] = Vector2.from_angle(me.look + 1.2)
	elif me.role == GkActor.Role.HIDER and g.hunter:
		out["look"] = g.hunter.position - me.position
	if want_action:
		want_action = false
		out["action"] = true
	return out


# ---------------------------------------------------------------- chemins

func _go(target: Vector2) -> void:
	path = g.map.path(me.position, target)
	path_i = 1 if path.size() > 1 else 0


func _follow(dt: float) -> Vector2:
	if path_i >= path.size():
		return Vector2.ZERO
	var wp: Vector2 = path[path_i]
	# Seuil d'arrivée ≥ un pas de déplacement : pas d'oscillation autour d'un point (jeu accéléré).
	if me.position.distance_to(wp) < maxf(12.0, me.speed() * dt * 1.2):
		path_i += 1
		if path_i >= path.size():
			return Vector2.ZERO
		wp = path[path_i]
	return (wp - me.position).normalized()


func _arrived() -> bool:
	return path_i >= path.size()


func _tiles() -> float:
	return g.map.tile


# ---------------------------------------------------------------- chassé

func _think_hider() -> void:
	var h: GkActor = g.hunter
	if me.hidden_in >= 0:
		plan_cachette = -1
		var far: bool = h.position.distance_to(me.position) > float(cfg.get("danger", 8.0)) * _tiles()
		if me.hidden_t > GkRules.f("hide_max") - 2.0 or (far and me.hidden_t > 8.0 and rng.randf() < 0.15):
			want_action = true                   # on sort avant d'être éjecté
		return
	var hunting: bool = g.phase == GkGame.Phase.HUNT
	if hunting and _threatened():
		_react_t += float(cfg.get("think", 0.5))
		if _react_t >= float(cfg.get("react", 0.25)):
			_flee()
		return
	_react_t = 0.0
	if plan_cachette >= 0:
		var c: Dictionary = g.cachettes[plan_cachette]
		if int(c["occupant"]) >= 0 or float(c["lock"]) > 0.0:
			plan_cachette = -1
			_pick_hiding()
		elif g.near_cachette(me, true) == plan_cachette:
			want_action = true
		return
	if going_exit:
		if not g.exits_open():
			going_exit = false
		return
	if hunting and g.exits_open() and rng.randf() < float(cfg.get("extract_chance", 0.2)) * float(cfg.get("think", 0.5)):
		var e: Vector2i = _safest_exit()
		if e != Vector2i(-1, -1):
			going_exit = true
			_go(g.map.center(e))
			return
	if g.phase == GkGame.Phase.HIDE and path.is_empty():
		_pick_hiding()
		return
	if hunting:
		relocate_t -= float(cfg.get("think", 0.5))
		if relocate_t <= 0.0 and _arrived() and h.position.distance_to(me.position) > 12.0 * _tiles():
			relocate_t = float(cfg.get("relocate", 25.0)) * rng.randf_range(0.7, 1.3)
			_pick_hiding()


## Le chasseur pourrait me voir bientôt : il est proche, rien ne nous sépare et il regarde à peu près vers moi.
func _threatened() -> bool:
	var h: GkActor = g.hunter
	var v: Vector2 = me.position - h.position
	var d: float = v.length()
	if d > float(cfg.get("danger", 8.0)) * _tiles():
		return false
	if not g.clear_line(h.position, me.position):
		return false
	var facing: bool = absf(angle_difference(h.look, v.angle())) < deg_to_rad(GkRules.f("cone_deg")) * 0.5 + 0.8
	return facing or d < 3.5 * _tiles()


func _flee() -> void:
	var h: GkActor = g.hunter
	# Piège sur son chemin si le chasseur est tout près, ou cachette libre à portée.
	if h.position.distance_to(me.position) < 5.0 * _tiles():
		if g.near_cachette(me, true) >= 0 and rng.randf() < 0.5:
			want_action = true
			return
		if me.power_cd <= 0.0:
			want_action = true
	var best: Vector2i = Vector2i(-1, -1)
	var bs: float = -INF
	var here: Vector2i = g.map.to_tile(me.position)
	for i: int in 36:
		var t: Vector2i = here + Vector2i(rng.randi_range(-12, 12), rng.randi_range(-9, 9))
		if not g.map.walkable(t):
			continue
		var p: Vector2 = g.map.center(t)
		var s: float = p.distance_to(h.position) / _tiles() * 1.5 + float(g.map.cover.get(t, 0)) * 1.2 \
			- p.distance_to(me.position) / _tiles() * 0.3
		if g.clear_line(h.position, p):
			s -= 12.0
		if s > bs:
			bs = s
			best = t
	if best != Vector2i(-1, -1):
		going_exit = false
		plan_cachette = -1
		_go(g.map.center(best))


func _pick_hiding() -> void:
	# Une cachette libre (parfois), sinon une case abritée loin du départ et des autres.
	if rng.randf() < 0.3:
		var free: Array[int] = []
		for i: int in g.cachettes.size():
			var c: Dictionary = g.cachettes[i]
			if int(c["occupant"]) < 0 and float(c["lock"]) <= 0.0 and not _cachette_claimed(i):
				free.append(i)
		if not free.is_empty():
			plan_cachette = free[rng.randi() % free.size()]
			var ct: Vector2i = g.cachettes[plan_cachette]["tile"]
			for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if g.map.walkable(ct + d):
					_go(g.map.center(ct + d))
					return
	var best: Vector2i = Vector2i(-1, -1)
	var bs: float = -INF
	var spawn: Vector2 = g.map.center(g.map.spawns[0]) if not g.map.spawns.is_empty() else Vector2.ZERO
	var keys: Array = g.map.cover.keys()
	for i: int in 60:
		var t: Vector2i = keys[rng.randi() % keys.size()]
		var cov: int = int(g.map.cover[t])
		if cov < 3:
			continue
		var p: Vector2 = g.map.center(t)
		var s: float = float(cov) * 2.0 + minf(p.distance_to(spawn) / _tiles(), 30.0) * 0.4 + rng.randf() * 6.0
		for b: GkAi in g.brains.values():
			if b != self and b.path.size() > 0 and b.path[b.path.size() - 1].distance_to(p) < 4.0 * _tiles():
				s -= 8.0
		if g.phase == GkGame.Phase.HUNT:
			s += minf(p.distance_to(g.hunter.position) / _tiles(), 25.0) * 0.6
		if s > bs:
			bs = s
			best = t
	if best != Vector2i(-1, -1):
		_go(g.map.center(best))


func _cachette_claimed(i: int) -> bool:
	for b: GkAi in g.brains.values():
		if b != self and b.plan_cachette == i:
			return true
	return false


func _safest_exit() -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var bd: float = -INF
	for e: Vector2i in g.map.exits:
		var p: Vector2 = g.map.center(e)
		var dh: float = p.distance_to(g.hunter.position) / _tiles()
		if dh < 12.0:
			continue
		var s: float = dh - p.distance_to(me.position) / _tiles() * 0.7
		if s > bd:
			bd = s
			best = e
	return best


# ---------------------------------------------------------------- chasseur

func _think_hunter() -> void:
	if g.phase != GkGame.Phase.HUNT:
		return
	# 1. Un chassé est en vue : on fonce.
	var target: GkActor = null
	for a: GkActor in g.actors:
		if a.role == GkActor.Role.HIDER and bool(g._seen.get(a.id, false)):
			if target == null or a.position.distance_to(me.position) < target.position.distance_to(me.position):
				target = a
	if target:
		chase_id = target.id
		clue = target.position
		clue_t = 4.0
		if g.clear_line(me.position, target.position):
			path = PackedVector2Array([me.position, target.position])
			path_i = 1
		else:
			_go(target.position)
		return
	# 2. Une cachette tremble ou on passe à côté : on fouille (plus souvent si l'IA est maligne).
	var c: int = g.near_cachette(me, false)
	if c >= 0:
		var shook: bool = float(g.cachettes[c]["shake"]) > 0.0
		if shook or rng.randf() < float(cfg.get("search_chance", 0.5)) * 0.35:
			want_action = true
			return
	# 3. Un indice (onde, piège déclenché, dernière position vue) : on y va puis on regarde autour.
	if clue_t > 0.0 and clue != Vector2.INF:
		if me.position.distance_to(clue) < 1.5 * _tiles():
			clue = Vector2.INF
			scan_t = 1.6 * float(cfg.get("hunter_scan", 0.7)) + 0.4
		elif _arrived() or path.is_empty() or path[path.size() - 1].distance_to(clue) > _tiles():
			_go(clue)
		return
	# 4. Onde dès qu'elle est prête.
	if me.power_cd <= 0.0 and rng.randf() < 0.6:
		want_action = true
		return
	# 5. Patrouille : la zone la moins visitée récemment, puis un tour d'horizon.
	if _arrived() and scan_t <= 0.0:
		var z: int = g.map.zone_of(g.map.to_tile(me.position))
		if z >= 0:
			visited[z] = clock
		scan_t = 1.4 * float(cfg.get("hunter_scan", 0.7))
		_patrol()


func _patrol() -> void:
	var order: Array = range(g.map.zones.size())
	order.sort_custom(func(a: int, b: int) -> bool: return float(visited.get(a, -1000.0)) < float(visited.get(b, -1000.0)))
	var pick: int = order[rng.randi() % mini(3, order.size())]
	var r: Rect2i = g.map.zones[pick]["rect"]
	for i: int in 30:
		var t: Vector2i = r.position + Vector2i(rng.randi_range(1, r.size.x - 2), rng.randi_range(1, r.size.y - 2))
		if g.map.walkable(t):
			_go(g.map.center(t))
			return


func on_found(a: GkActor) -> void:
	if a.id == chase_id:
		chase_id = -1
		clue = Vector2.INF
		clue_t = 0.0


func on_trap(pos: Vector2) -> void:
	if me.role == GkActor.Role.HUNTER:
		clue = pos
		clue_t = 6.0


func on_detect(found: Array[Vector2]) -> void:
	if found.is_empty():
		return
	var best: Vector2 = found[0]
	for p: Vector2 in found:
		if p.distance_to(me.position) < best.distance_to(me.position):
			best = p
	clue = best
	clue_t = 8.0
	_go(best)


# ---------------------------------------------------------------- fantôme

func _think_ghost() -> void:
	if _arrived() and rng.randf() < 0.25:
		var keys: Array = g.map.cover.keys()
		_go(g.map.center(keys[rng.randi() % keys.size()]))
