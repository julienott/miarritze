class_name BkAi
extends RefCounted
## IA d'un joueur (GDD-BLACKOUT.md). Elle ne voit que ce que voit son rôle :
## un chassé voit toute la carte (et le chasseur) ; le chasseur ne sait que ce qu'il voit, ce que lui
## donne son coup spécial (piste de Cache-Cache !), les cachettes qui tremblent et les secteurs plongés
## dans le noir (disjoncteurs, GDD §3.2, §11). Coups spéciaux (GDD §4, BkCoups.essaie_ia) : un chassé
## lance le sien quand il est en danger (et, en réflexe, quand sa jauge passe jauge_urgence), le
## chasseur quand il voit une cible ou en a une probable (avec la probabilité « coup » de son niveau, à
## chaque décision) ; la famille du coup juge s'il sert à quelque chose. Un chassé révélé (effet
## « revele » : pelote, piment, geyser, faisceau…) devient un indice pour le chasseur.

var g: BkGame
var me: BkActor
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
var lost_pos: Vector2 = Vector2.INF     # chasseur : où il a perdu de vue le dernier chassé poursuivi
var lost_t: float = -100.0
var searched: Dictionary = {}           # chasseur : cachette → instant de la dernière fouille
var seen_t: float = 0.0                 # chasseur : dernier instant où il voyait un chassé
var react_until: float = 0.0            # chasseur : temps de réaction avant de foncer sur un chassé vu
## Chassé, idee_mouvement : dernier instant où le chasseur est passé tout près (frôlement), dernier
## contournement, et sortie de cachette pour profiter d'une fouille (contourner dès qu'on est dehors).
var close_t: float = -100.0
var slipped_at: float = -100.0
var slip_pending: bool = false
## Disjoncteur visé (index de BkGame.boitiers), -1 sinon : un chassé va couper la lumière, le chasseur
## va la rallumer.
var plan_switch: int = -1
## Réflexe d'un chassé : jauge à l'image d'avant (passage de jauge_urgence).
var _jauge_avant: float = 0.0
## Jauge qui déclenche le réflexe d'urgence (feinte de Peio, endurance de Mattin, plongeon de Maïa…).
const JAUGE_URGENCE: float = 0.7


func _init(p_game: BkGame, p_me: BkActor, p_level: String) -> void:
	g = p_game
	me = p_me
	level = p_level
	cfg = BkRules.ai(p_level)
	rng.seed = hash(p_me.id * 7919 + 17)


## Change de niveau (QA : chasseur IA d'un autre niveau que les chassés).
func set_level(p_level: String) -> void:
	level = p_level
	cfg = BkRules.ai(p_level)


func reset() -> void:
	path = PackedVector2Array()
	plan_cachette = -1
	going_exit = false
	relocate_t = _relocate_delay() * rng.randf_range(0.6, 1.4)
	close_t = -100.0
	slipped_at = -100.0
	slip_pending = false
	scan_t = 0.0
	clue = Vector2.INF
	clue_t = 0.0
	chase_id = -1
	think_t = rng.randf_range(0.0, 0.6)
	lost_pos = Vector2.INF
	lost_t = -100.0
	searched.clear()
	seen_t = clock
	plan_switch = -1


func update(dt: float) -> Dictionary:
	clock += dt
	clue_t = maxf(0.0, clue_t - dt)
	scan_t = maxf(0.0, scan_t - dt)
	if me.frozen or me.search_left > 0.0:
		return {}
	if me.role == BkActor.Role.OUT:
		return {}
	# Enfoui (Karramarro) : il ne bouge plus tant que son coup le garde caché.
	if g.coups.garde_immobile(me):
		return {}
	# Réflexe : la jauge passe le seuil d'urgence, le coup part tout de suite (si la famille veut).
	if me.role == BkActor.Role.HIDER and g.phase == BkGame.Phase.HUNT:
		if _jauge_avant < JAUGE_URGENCE and me.gauge >= JAUGE_URGENCE and rng.randf() < float(cfg.get("coup", 0.5)):
			g.coups.essaie_ia(me, {"menace": true, "urgence": true})
		_jauge_avant = me.gauge
	think_t -= dt
	if think_t <= 0.0:
		think_t = float(cfg.get("think", 0.5))
		match me.role:
			BkActor.Role.HIDER:
				_think_hider()
			BkActor.Role.HUNTER:
				_think_hunter()
			BkActor.Role.GHOST:
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
	if me.role == BkActor.Role.HUNTER and scan_t > 0.0 and out["move"] == Vector2.ZERO:
		out["look"] = Vector2.from_angle(me.look + 1.2)
	elif me.role == BkActor.Role.HIDER and g.hunter:
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
	var h: BkActor = g.hunter
	if me.hidden_in >= 0:
		plan_cachette = -1
		plan_switch = -1
		# Mouvement : le chasseur fouille une autre cachette à côté, on en profite pour filer.
		if BkRules.on("idee_mouvement") and _search_window() and int(g._search_target.get(h.id, -1)) != me.hidden_in:
			want_action = true
			slip_pending = true
			return
		var far: bool = h.position.distance_to(me.position) > float(cfg.get("danger", 8.0)) * _tiles()
		if me.hidden_t > BkRules.f("hide_max") - 2.0 or (far and me.hidden_t > 8.0 and rng.randf() < 0.15):
			want_action = true                   # on sort avant d'être éjecté
		return
	var hunting: bool = g.phase == BkGame.Phase.HUNT
	# Disjoncteur : couper la lumière du secteur où rôde le chasseur (avant la fuite).
	if hunting and _think_switch():
		return
	# Coup spécial en danger (repéré ou chasseur menaçant) : la famille juge s'il sert (Passe-Muraille :
	# un obstacle à franchir qui casse la ligne de vue).
	if hunting and (me.gauge > 0.0 or _threatened()) and rng.randf() < float(cfg.get("coup", 0.5)) \
			and g.coups.essaie_ia(me, {"menace": true}):
		path = PackedVector2Array()
		return
	# Coup d'entraide (bouée de Txomin : un coéquipier en détresse), hors danger.
	if hunting and rng.randf() < float(cfg.get("coup", 0.5)) * 0.5 and g.coups.essaie_ia(me, {"menace": false}):
		return
	# Détection progressive : il se sait repéré (sa jauge monte) : il file vers l'abri le plus proche.
	if hunting and BkRules.on("idee_detection") and me.gauge > 0.0:
		_react_t = 0.0
		_flee(true)
		return
	if hunting and _threatened():
		_react_t += float(cfg.get("think", 0.5))
		if _react_t >= float(cfg.get("react", 0.25)):
			_flee()
		return
	_react_t = 0.0
	if hunting and BkRules.on("idee_mouvement") and _think_movement():
		return
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
	if g.phase == BkGame.Phase.HIDE and path.is_empty():
		_pick_hiding()
		return
	# Gâteau basque à portée et chasseur loin : on va le chercher, puis on repart se cacher.
	if hunting and not g.gateaux.is_empty() and _arrived():
		var danger: float = float(cfg.get("danger", 8.0)) * _tiles()
		for gt: Dictionary in g.gateaux:
			var gp: Vector2 = gt["pos"]
			if gp.distance_to(me.position) < 10.0 * _tiles() and gp.distance_to(h.position) > danger * 1.3 \
					and rng.randf() < 0.5:
				_go(gp)
				relocate_t = minf(relocate_t, 3.0)
				return
	if hunting:
		relocate_t -= float(cfg.get("think", 0.5))
		var far_relocate: float = 9.0 if BkRules.on("idee_mouvement") else 12.0
		if relocate_t <= 0.0 and _arrived() and h.position.distance_to(me.position) > far_relocate * _tiles():
			relocate_t = _relocate_delay() * rng.randf_range(0.7, 1.3)
			_pick_hiding()


## Chassé : va couper le disjoncteur de son secteur quand le chasseur y est et qu'il est éclairé ou en
## danger (chance « disjoncteur » de son niveau, boîtier à disjoncteur_ia_portee cases au plus, 4 s'il
## est déjà repéré) ; arrivé au boîtier, il l'actionne. Vrai s'il s'en occupe.
func _think_switch() -> bool:
	if plan_switch >= 0:
		if not g.boitier_utile(me, plan_switch) and me.use_left <= 0.0:
			plan_switch = -1
			return false
		if me.use_left > 0.0:
			return true
		if g.near_boitier(me) == plan_switch:
			want_action = true
		elif _arrived():
			_go(g.map.center(g.boitiers[plan_switch]["pos"]))
		return true
	var h: BkActor = g.hunter
	var sect: String = g.map.secteur_of(g.map.to_tile(me.position))
	if sect == "" or g.map.secteur_of(g.map.to_tile(h.position)) != sect:
		return false
	var spotted: bool = me.gauge > 0.0
	if not (me.lit or spotted or _threatened()):
		return false
	if rng.randf() >= float(cfg.get("disjoncteur", 0.5)):
		return false
	var reach: float = (4.0 if spotted else BkRules.f("disjoncteur_ia_portee")) * _tiles()
	for i: int in g.boitiers.size():
		var b: Dictionary = g.boitiers[i]
		if str(b["secteur"]) != sect or not g.boitier_utile(me, i) or _switch_claimed(i):
			continue
		var p: Vector2 = g.map.center(b["pos"])
		if p.distance_to(me.position) > reach:
			continue
		plan_switch = i
		plan_cachette = -1
		going_exit = false
		_go(p)
		return true
	return false


func _switch_claimed(i: int) -> bool:
	for b: BkAi in g.brains.values():
		if b != self and b.plan_switch == i:
			return true
	return false


## Délai avant de changer de planque (s) ; plus court avec idee_mouvement.
func _relocate_delay() -> float:
	var k: float = BkRules.f("mouvement_relocate") if BkRules.on("idee_mouvement") else 1.0
	return float(cfg.get("relocate", 25.0)) * k


## Le chasseur fouille une cachette (1 s immobile) à portée : une fenêtre pour bouger.
func _search_window() -> bool:
	var h: BkActor = g.hunter
	return h.search_left > 0.0 and h.position.distance_to(me.position) < BkRules.px("mouvement_fenetre_portee")


## idee_mouvement, chassé dehors et pas menacé : profiter d'une fouille, ou contourner le chasseur
## qui vient de passer tout près et s'éloigne en nous tournant le dos. Vrai si on a bougé.
func _think_movement() -> bool:
	var h: BkActor = g.hunter
	var dh: float = h.position.distance_to(me.position) / _tiles()
	if dh < 4.0:
		close_t = clock
	if slip_pending or (_search_window() and dh > 2.5):
		slip_pending = false
		return _slip_behind()
	var away: bool = absf(angle_difference(h.look, (me.position - h.position).angle())) > deg_to_rad(110.0)
	if clock - close_t < 8.0 and dh > 6.0 and away and clock - slipped_at > 10.0 and _arrived() \
			and rng.randf() < BkRules.f("mouvement_contourne"):
		return _slip_behind()
	return false


## Se glisser derrière le chasseur, là où il vient de chercher : une case abritée, hors de sa vue,
## dans son dos, à 5 cases au moins de lui.
func _slip_behind() -> bool:
	var h: BkActor = g.hunter
	var fwd: Vector2 = Vector2.from_angle(h.look)
	var here: Vector2i = g.map.to_tile(h.position)
	var best: Vector2i = Vector2i(-1, -1)
	var bs: float = -INF
	for i: int in 40:
		var t: Vector2i = here + Vector2i(rng.randi_range(-10, 10), rng.randi_range(-8, 8))
		if not g.map.walkable(t):
			continue
		var p: Vector2 = g.map.center(t)
		if p.distance_to(h.position) < 5.0 * _tiles():
			continue
		var s: float = float(g.map.cover.get(t, 0)) * 1.5 - p.distance_to(me.position) / _tiles() * 0.4 + rng.randf() * 2.0
		if fwd.dot(p - h.position) < 0.0:
			s += 6.0
		if g.clear_line(h.position, p):
			s -= 10.0
		if s > bs:
			bs = s
			best = t
	if best == Vector2i(-1, -1):
		return false
	going_exit = false
	plan_cachette = -1
	slipped_at = clock
	relocate_t = maxf(relocate_t, _relocate_delay() * 0.5)
	_go(g.map.center(best))
	return true


## Le chasseur pourrait me voir bientôt : il est proche, rien ne nous sépare et il regarde à peu près vers moi.
func _threatened() -> bool:
	var h: BkActor = g.hunter
	var v: Vector2 = me.position - h.position
	var d: float = v.length()
	if d > float(cfg.get("danger", 8.0)) * _tiles():
		return false
	if not g.clear_line(h.position, me.position):
		return false
	var facing: bool = absf(angle_difference(h.look, v.angle())) < deg_to_rad(BkRules.f("cone_deg")) * 0.5 + 0.8
	return facing or d < 3.5 * _tiles()


## Fuite : une case loin du chasseur, abritée et hors de sa vue. `spotted` (il se sait repéré) :
## la plus proche possible, pour casser la ligne de vue au plus vite.
func _flee(spotted: bool = false) -> void:
	var h: BkActor = g.hunter
	# Cachette libre à portée quand le chasseur est tout près : on plonge dedans.
	if h.position.distance_to(me.position) < 5.0 * _tiles() and g.near_cachette(me, true) >= 0 \
			and rng.randf() < 0.5:
		want_action = true
		return
	var best: Vector2i = Vector2i(-1, -1)
	var bs: float = -INF
	var here: Vector2i = g.map.to_tile(me.position)
	for i: int in 36:
		var t: Vector2i = here + Vector2i(rng.randi_range(-12, 12), rng.randi_range(-9, 9))
		if not g.map.walkable(t):
			continue
		var p: Vector2 = g.map.center(t)
		var s: float = p.distance_to(h.position) / _tiles() * 1.5 + float(g.map.cover.get(t, 0)) * 1.2 \
			- p.distance_to(me.position) / _tiles() * (1.2 if spotted else 0.3)
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
		for b: BkAi in g.brains.values():
			if b != self and b.path.size() > 0 and b.path[b.path.size() - 1].distance_to(p) < 4.0 * _tiles():
				s -= 8.0
		if g.phase == BkGame.Phase.HUNT:
			s += minf(p.distance_to(g.hunter.position) / _tiles(), 25.0) * 0.6
		# Planque dans l'ombre (GDD §11) : la jauge y monte 3 fois moins vite.
		if g.eclaire(p):
			s -= 6.0
		if s > bs:
			bs = s
			best = t
	if best != Vector2i(-1, -1):
		_go(g.map.center(best))


func _cachette_claimed(i: int) -> bool:
	for b: BkAi in g.brains.values():
		if b != self and b.plan_cachette == i:
			return true
	return false


func _safest_exit() -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var bd: float = -INF
	for e: Vector2i in g.open_exits:
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
	if g.phase != BkGame.Phase.HUNT:
		return
	# 1. Un chassé est en vue : on fonce. Détection progressive : seulement à partir du « ? » (un
	# coin de silhouette au bout du cône ne se remarque pas tout de suite) ; il se tourne alors vers
	# lui et va voir.
	var notice: float = BkRules.f("detection_doute") if BkRules.on("idee_detection") else 0.0
	var target: BkActor = null
	for a: BkActor in g.actors:
		if a.role == BkActor.Role.HIDER and bool(g._seen.get(a.id, false)) and a.gauge >= notice:
			if target == null or a.position.distance_to(me.position) < target.position.distance_to(me.position):
				target = a
	if target == null and chase_id >= 0 and clue != Vector2.INF:
		lost_pos = clue                      # perdu de vue : on retient où
		lost_t = clock
		chase_id = -1
	if target:
		seen_t = clock
		if target.id != chase_id:
			react_until = clock + float(cfg.get("hunter_react", 0.3))
		chase_id = target.id
		clue = target.position
		clue_t = 4.0 * float(cfg.get("clue_memory", 1.0))
		if clock < react_until:
			return                           # surpris : il met un instant à réagir
		# Coup spécial sur la cible vue (pelote, ligne, pierre, faisceau, glissade, take-off, sifflet…).
		if rng.randf() < float(cfg.get("coup", 0.5)):
			g.coups.essaie_ia(me, {"cible_probable": true, "cible": target, "vers": target.position})
		if g.clear_line(me.position, target.position):
			path = PackedVector2Array([me.position, target.position])
			path_i = 1
		else:
			_go(target.position)
		return
	# 1 bis. Un secteur est dans le noir : il va rallumer le disjoncteur (un « ? » l'en distrait : 1).
	if _think_repair():
		return
	# 1 ter. Coup spécial quand il a une cible probable : un chassé perdu de vue depuis peu, un indice,
	# ou personne vu depuis longtemps. Piste de Cache-Cache ! : le dernier pas devient l'indice.
	var probable: bool = (lost_pos != Vector2.INF and clock - lost_t < 8.0) or (clue_t > 0.0 and clue != Vector2.INF) \
		or clock - seen_t > 20.0
	var vers: Vector2 = lost_pos if lost_pos != Vector2.INF and clock - lost_t < 8.0 else (clue if clue_t > 0.0 else Vector2.INF)
	if probable and rng.randf() < float(cfg.get("coup", 0.5)) \
			and g.coups.essaie_ia(me, {"cible_probable": true, "vers": vers}):
		seen_t = clock
	# Un chassé révélé (à travers les murs) : on y va.
	var rv: BkActor = _revele_proche()
	if rv != null:
		clue = rv.position
		clue_t = 2.0 * float(cfg.get("clue_memory", 1.0))
		if path.is_empty() or _arrived() or path[path.size() - 1].distance_to(clue) > 1.5 * _tiles():
			_go(clue)
		return
	var piste: Vector2 = g.coups.piste_de(me)
	if piste != Vector2.INF:
		var t: Vector2i = g.map.to_tile(piste)
		if g.map.walkable(t) and (clue == Vector2.INF or clue.distance_to(piste) > _tiles()):
			clue = g.map.center(t)
			clue_t = 3.0 * float(cfg.get("clue_memory", 1.0))
			_go(clue)
	# 2. Une cachette tremble ou on passe à côté : on fouille (plus souvent si l'IA est maligne).
	var c: int = g.near_cachette(me, false)
	if c >= 0:
		# Le tremblement de fin de sa propre fouille ne compte pas (sinon le malin, qui réfléchit
		# plus vite que ce tremblement ne dure, refouillait sans fin la même cachette vide).
		var shook: bool = float(g.cachettes[c]["shake"]) > 0.0 and clock - float(searched.get(c, -100.0)) > 2.0
		var chance: float = float(cfg.get("search_chance", 0.5)) * 0.35
		var fresh: bool = clock - float(searched.get(c, -100.0)) > 15.0
		if bool(cfg.get("smart_search", false)):
			# Fouille réfléchie : là où un chassé a disparu, sinon rarement, jamais deux fois de suite.
			var cpos: Vector2 = g.cachettes[c]["pos"]
			var suspect: bool = lost_pos != Vector2.INF and clock - lost_t < 12.0 \
				and cpos.distance_to(lost_pos) < 5.0 * _tiles()
			chance = 0.9 if suspect else chance * 0.25
		if shook or (fresh and rng.randf() < chance):
			searched[c] = clock
			want_action = true
			return
	# 3. Un indice (piste, bruit, dernière position vue) : on y va puis on regarde autour.
	if clue_t > 0.0 and clue != Vector2.INF:
		if me.position.distance_to(clue) < 1.5 * _tiles():
			clue = Vector2.INF
			scan_t = 1.6 * float(cfg.get("hunter_scan", 0.7)) + 0.4
		elif _arrived() or path.is_empty() or path[path.size() - 1].distance_to(clue) > _tiles():
			_go(clue)
		return
	# 4. Garder une sortie ouverte (plus souvent si l'IA est maligne).
	if g.exits_open() and _arrived() and scan_t <= 0.0 and not g.open_exits.is_empty() \
			and rng.randf() < float(cfg.get("guard_exits", 0.0)) * 0.5:
		var e: Vector2i = g.open_exits[rng.randi() % g.open_exits.size()]
		for i: int in 20:
			var t: Vector2i = e + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
			if g.map.walkable(t):
				_go(g.map.center(t))
				scan_t = 2.0 * float(cfg.get("hunter_scan", 0.7))
				return
	# 5. Patrouille : la zone la moins visitée récemment, puis un tour d'horizon.
	if _arrived() and scan_t <= 0.0:
		var z: int = g.map.zone_of(g.map.to_tile(me.position))
		if z >= 0:
			visited[z] = clock
		scan_t = 1.4 * float(cfg.get("hunter_scan", 0.7))
		_patrol()


## Chasseur : le chassé révélé (effet « revele ») le plus proche, hors cachette, null sinon.
func _revele_proche() -> BkActor:
	var best: BkActor = null
	for a: BkActor in g.actors:
		if a.role == BkActor.Role.HIDER and a.hidden_in < 0 and BkEffets.actif(a, "revele") \
				and (best == null or a.position.distance_to(me.position) < best.position.distance_to(me.position)):
			best = a
	return best


## Chasseur : le boîtier d'un secteur coupé le plus proche ; il y va et l'actionne. Vrai s'il s'en occupe.
func _think_repair() -> bool:
	if me.use_left > 0.0:
		return true
	var best: int = -1
	var bd: float = INF
	for i: int in g.boitiers.size():
		if not g.boitier_utile(me, i):
			continue
		var d: float = g.map.center(g.boitiers[i]["pos"]).distance_to(me.position)
		if d < bd:
			bd = d
			best = i
	plan_switch = best
	if best < 0:
		return false
	if g.near_boitier(me) == best:
		want_action = true
		return true
	var p: Vector2 = g.map.center(g.boitiers[best]["pos"])
	if path.is_empty() or _arrived() or path[path.size() - 1].distance_to(p) > _tiles():
		_go(p)
	return true


func _patrol() -> void:
	var order: Array = range(g.map.zones.size())
	order.sort_custom(func(a: int, b: int) -> bool: return float(visited.get(a, -1000.0)) < float(visited.get(b, -1000.0)))
	var pick: int = order[rng.randi() % mini(3, order.size())]
	var r: Rect2i = g.map.zones[pick]["rect"]
	# Ronde (idee_ronde) : le plus souvent, aller voir derrière un gros objet (case abritée, là où
	# les chassés se cachent) plutôt qu'au milieu de la zone : il passe tout près des planques.
	if BkRules.on("idee_ronde") and rng.randf() < BkRules.f("ronde_recoins"):
		var best: Vector2i = Vector2i(-1, -1)
		var bs: float = -INF
		for i: int in 40:
			var t: Vector2i = r.position + Vector2i(rng.randi_range(0, r.size.x - 1), rng.randi_range(0, r.size.y - 1))
			var cov: int = int(g.map.cover.get(t, -1))
			if cov < 3:
				continue
			var s: float = float(cov) + rng.randf() * 3.0
			if not g.clear_line(me.position, g.map.center(t)):
				s += 2.0                     # caché d'ici : c'est là qu'il faut aller voir
			if s > bs:
				bs = s
				best = t
		if best != Vector2i(-1, -1):
			_go(g.map.center(best))
			return
	for i: int in 30:
		var t: Vector2i = r.position + Vector2i(rng.randi_range(1, r.size.x - 2), rng.randi_range(1, r.size.y - 2))
		if g.map.walkable(t):
			_go(g.map.center(t))
			return


func on_found(a: BkActor) -> void:
	if a.id == chase_id:
		chase_id = -1
		clue = Vector2.INF
		clue_t = 0.0


## Fantôme : il traverse les murs, il va donc tout droit.
func _go_ghost(target: Vector2) -> void:
	path = PackedVector2Array([me.position, target])
	path_i = 1


## Chasseur : un bruit entendu (cachette qui grince, mouettes qui s'envolent) devient un indice.
func on_noise(pos: Vector2) -> void:
	if me.role != BkActor.Role.HUNTER or chase_id >= 0:
		return
	# Une cachette n'est pas praticable : on vise la case libre voisine la plus proche.
	var here: Vector2i = g.map.to_tile(pos)
	var best: Vector2 = Vector2.INF
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var t: Vector2i = here + Vector2i(dx, dy)
			if g.map.walkable(t) and (best == Vector2.INF or g.map.center(t).distance_to(pos) < best.distance_to(pos)):
				best = g.map.center(t)
	if best == Vector2.INF:
		return
	clue = best
	clue_t = 5.0 * float(cfg.get("clue_memory", 1.0))
	_go(best)


# ---------------------------------------------------------------- fantôme

func _think_ghost() -> void:
	if g.phase == BkGame.Phase.HUNT:
		# Délivrance : rejoindre le chassé libre le plus loin du chasseur (une seule fois par round).
		if BkRules.on("idee_delivrance") and not me.rescued and g._rescues < int(BkRules.f("delivrance_max")):
			var best: BkActor = null
			var bs: float = -INF
			for a: BkActor in g.actors:
				if a.role == BkActor.Role.HIDER and a.hidden_in < 0:
					var s: float = a.position.distance_to(g.hunter.position) - a.position.distance_to(me.position) * 0.5
					if s > bs:
						bs = s
						best = a
			if best != null:
				if me.position.distance_to(best.position) > BkRules.px("delivrance_portee") * 0.6:
					_go_ghost(best.position)
				else:
					path = PackedVector2Array()
				return
	if _arrived() and rng.randf() < 0.25:
		var keys: Array = g.map.cover.keys()
		_go(g.map.center(keys[rng.randi() % keys.size()]))
