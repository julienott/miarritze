class_name GkGame
extends Node2D
## Partie de Gordeka contre l'IA (prototype gris, SPEC-GORDEKA §2-4, jalon 1).
## La partie tourne entièrement ici (rôle d'hôte) : rounds, vision du chasseur, capture,
## cachettes, pièges, détections, sorties et points. Les joueurs n'envoient que move/look/action.

enum Phase { DRAW, HIDE, HUNT, END, PODIUM }

const COUNT_WORDS: PackedStringArray = ["bat", "bi", "hiru", "lau", "bost", "sei", "zazpi", "zortzi",
	"bederatzi", "hamar", "hamaika", "hamabi", "hamahiru", "hamalau", "hamabost"]

## Réglages de la partie, posés par le menu (gk_menu.gd).
static var config: Dictionary = {"players": 6, "level": "normal", "map": "port_pecheurs",
	"name": "Toi", "color": 0}

var map: GkMap
var actors: Array[GkActor] = []
var brains: Dictionary = {}          # id → GkAi
var local: GkActor
var input: GkInput
var hud: GkHud
var phase: Phase = Phase.DRAW
var phase_t: float = 0.0
var hunt_elapsed: float = 0.0
var round_no: int = 0
var hunter: GkActor
var cachettes: Array = []            # [{tile, pos, occupant, lock, shake}]
var traps: Array = []                # [{pos, owner}]
## Sorties tirées au sort pour ce round (parmi les sorties possibles de la carte).
var open_exits: Array[Vector2i] = []
var open_exit_zones: Array[String] = []
var reveals: Array = []              # [{pos, left, id}] (détection du chasseur)
var messages: Array = []             # [{text, left, color}]
var _sac: Array[int] = []
var _last_hunter: int = -1
var _seen: Dictionary = {}           # id → vu par le chasseur cette image
var _search_target: Dictionary = {}  # id du chasseur → index de cachette fouillée
var _round_hiders: int = 0
var _round_found: int = 0
var _overlay: Node2D
var _camera: Camera2D
var _dark: CanvasModulate
var _cone_light: PointLight2D
var _near_light: PointLight2D
var _bots_only: bool = false
var _force_role: String = ""
var _log: bool = false
var _local_bot: bool = false          # QA : le joueur local est piloté par l'IA (garde son perso)
## Affichage 3D abandonné le 2026-10-19 (docs/GORDEKA_STYLE_2D.md) : 2D par défaut, `--gk-3d`
## rouvre l'ancienne vue 3D.
var use_3d: bool = false
## QA : `--gk-perso=louis` donne ce perso à tout le monde (voir ses animations sur toutes les IA).
var _all_char: String = ""
## QA gameplay : niveau imposé au chasseur IA (`--gk-hunter-level=`), arrêt après N rounds
## (`--gk-rounds=`), statistiques par round en JSON (`--gk-stats`).
var _hunter_level: String = ""
var _rounds_max: int = 0
var _stats: bool = false
var _st: Dictionary = {}
var _revealed_at: Dictionary = {}     # id du chassé → instant de la dernière onde qui l'a montré
var _trap_hit_at: float = -100.0
var view: GkView3D
var _last_dt: float = 0.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--gk-bots-only":
			_bots_only = true
		elif arg == "--gk-local-bot":
			_local_bot = true
		elif arg == "--gk-3d":
			use_3d = true
		elif arg.begins_with("--gk-level="):
			config["level"] = arg.trim_prefix("--gk-level=")
		elif arg.begins_with("--gk-players="):
			config["players"] = int(arg.trim_prefix("--gk-players="))
		elif arg.begins_with("--gk-hunter-level="):
			_hunter_level = arg.trim_prefix("--gk-hunter-level=")
		elif arg.begins_with("--gk-rounds="):
			_rounds_max = int(arg.trim_prefix("--gk-rounds="))
		elif arg == "--gk-mannequin":
			GkPerso.use_pantin = true
		elif arg == "--gk-stats":
			_stats = true
		elif arg.begins_with("--gk-perso="):
			_all_char = arg.trim_prefix("--gk-perso=")
		elif arg == "--gk-log":
			_log = true
		elif arg.begins_with("--gk-local-role="):
			_force_role = arg.trim_prefix("--gk-local-role=")
	map = GkMap.new()
	map.draw_2d = not use_3d
	add_child(map)
	map.load_map(str(config.get("map", "port_pecheurs")))
	if not use_3d:
		var water: GkWater = GkWater.new()
		water.map = map
		map.add_child(water)
		map.move_child(water, 0)
	for t: Vector2i in map.cachettes:
		cachettes.append({"tile": t, "pos": map.center(t), "occupant": -1, "lock": 0.0, "shake": 0.0})
	var people: Node2D = Node2D.new()
	people.y_sort_enabled = true
	add_child(people)
	_make_actors(people)
	_make_view()
	if use_3d:
		view = GkView3D.new()
		add_child(view)
		view.setup(self)
	input = GkInput.new()
	add_child(input)
	input.quit_requested.connect(quit_to_podium)
	hud = GkHud.new()
	hud.game = self
	var hud_layer: CanvasLayer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud_layer.add_child(hud)
	_start_round()


func _make_actors(parent: Node2D) -> void:
	var n: int = clampi(int(config.get("players", 6)), 2, 8)
	var all_names: Array = GkRules.data().get("bot_names", [])
	var all_chars: Array = GkRules.data().get("characters", [])
	var my_name: String = str(config.get("name", "Toi"))
	var my_char: String = str(config.get("character", "louis"))
	# Les IA prennent les autres persos du roster, dans le désordre.
	var picks: Array[int] = []
	for i: int in all_chars.size():
		if str(all_chars[i]) != my_char or _bots_only:
			picks.append(i)
	picks.shuffle()
	var drawn: Array[String] = []
	for c: Variant in all_chars:
		if GkPerso.available(str(c)):
			drawn.append(str(c))
	var my_color: int = int(config.get("color", 0))
	var colors: Array[int] = []
	for i: int in 12:
		if i != my_color:
			colors.append(i)
	colors.shuffle()
	for i: int in n:
		var a: GkActor = GkActor.new()
		var bot: bool = i > 0 or _bots_only or _local_bot
		var me: bool = i == 0 and not _bots_only
		var k: int = picks[(i - (0 if _bots_only else 1)) % picks.size()] if not me else -1
		var nm: String = my_name if me else str(all_names[k]) + " (IA)"
		a.character = my_char if me else str(all_chars[k])
		# Tant que tous les persos ne sont pas dessinés, les IA prennent un perso qui l'est.
		if not GkPerso.available(a.character) and not drawn.is_empty():
			a.character = drawn[i % drawn.size()]
		if _all_char != "":
			a.character = _all_char
		a.setup(i, nm, GkRules.color(my_color if i == 0 else colors[i - 1]), bot)
		parent.add_child(a)
		actors.append(a)
		if bot:
			brains[i] = GkAi.new(self, a, str(config.get("level", "normal")))
	local = actors[0]


func _make_view() -> void:
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	# Zoom proche d'Among Us : un personnage fait environ 1/11 de la hauteur d'écran.
	_camera.zoom = Vector2(1.25, 1.25)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(map.size_px().x)
	_camera.limit_bottom = int(map.size_px().y)
	add_child(_camera)
	# Vue du chasseur : tout est sombre sauf son cône et un petit cercle, que les objets
	# bloquent (ombres des LightOccluder2D de la carte).
	_dark = CanvasModulate.new()
	_dark.color = Color.WHITE
	add_child(_dark)
	_cone_light = _make_light(_cone_texture(GkRules.f("cone_deg")), GkRules.px("cone_range"))
	_near_light = _make_light(_cone_texture(360.0), GkRules.px("near_radius") + 10.0)
	# Calque « dans le monde » non assombri : cône rouge vu des chassés, sorties, cachettes, pièges.
	var layer: CanvasLayer = CanvasLayer.new()
	layer.follow_viewport_enabled = true
	layer.layer = 1
	add_child(layer)
	_overlay = Node2D.new()
	layer.add_child(_overlay)
	_overlay.draw.connect(func() -> void: _draw_overlay(_overlay))


func _make_light(tex: Texture2D, radius: float) -> PointLight2D:
	var l: PointLight2D = PointLight2D.new()
	l.texture = tex
	l.texture_scale = radius * 2.0 / float(tex.get_width())
	l.shadow_enabled = true
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.energy = 0.8
	l.enabled = false
	add_child(l)
	return l


## Texture de lumière (256 px, agrandie par texture_scale) : secteur de `deg` degrés vers +X,
## bords adoucis.
static func _cone_texture(deg: float) -> Texture2D:
	var size: int = 256
	var r: float = 127.0
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half: float = deg_to_rad(deg) * 0.5
	var c: Vector2 = Vector2(size, size) * 0.5
	for y: int in size:
		for x: int in size:
			var v: Vector2 = Vector2(x + 0.5, y + 0.5) - c
			var d: float = v.length()
			if d > r:
				continue
			var k: float = clampf((r - d) / (r * 0.12), 0.0, 1.0)
			if deg < 359.0:
				var a: float = absf(v.angle())
				if a > half:
					continue
				k *= clampf((half - a) / deg_to_rad(4.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, k))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- rounds

func _start_round() -> void:
	round_no += 1
	phase = Phase.DRAW
	phase_t = GkRules.f("phase_draw")
	hunt_elapsed = 0.0
	traps.clear()
	reveals.clear()
	_search_target.clear()
	for c: Dictionary in cachettes:
		c["occupant"] = -1
		c["lock"] = 0.0
	hunter = _draw_hunter()
	_pick_exits()
	_round_hiders = actors.size() - 1
	_round_found = 0
	_st = {"vue": 0, "fouille_ok": 0, "fouille_vide": 0, "ondes": 0, "ondes_utiles": 0, "montres": 0,
		"trouves_apres_onde": 0, "pieges_poses": 0, "pieges_pris": 0, "trouves_apres_piege": 0,
		"entrees_cachette": 0, "ejections_cachette": 0, "trouves_en_cachette": 0, "sorties": 0,
		"evasions_de_vue": 0, "t_trouves": [], "lieux_trouves": [], "sorties_round": open_exit_zones.duplicate()}
	_revealed_at.clear()
	_trap_hit_at = -100.0
	for a2: GkActor in actors:
		a2.speed_mult = 1.0
	if hunter.is_bot:
		var hl: String = _hunter_level if _hunter_level != "" else str(config.get("level", "normal"))
		hunter.speed_mult = float(GkRules.ai(hl).get("hunter_speed", 1.0))
	if _hunter_level != "":
		for id: int in brains:
			var b: GkAi = brains[id]
			b.set_level(_hunter_level if actors[id] == hunter else str(config.get("level", "normal")))
	var spots: Array[Vector2i] = _spawn_spots(actors.size())
	var k: int = 1
	for a: GkActor in actors:
		a.set_role(GkActor.Role.HUNTER if a == hunter else GkActor.Role.HIDER)
		a.gauge = 0.0
		a.extract_t = 0.0
		a.alive_t = 0.0
		a.round_points = 0
		a.won_round = false
		a.end_pose = ""
		a.scared = false
		a.hidden_in = -1
		a.search_left = 0.0
		a.slow_left = 0.0
		a.power_cd = 0.0
		a.frozen = true
		a.look = PI * 0.5
		a.position = map.center(spots[0] if a == hunter else spots[mini(k, spots.size() - 1)])
		if a != hunter:
			k += 1
	for b: GkAi in brains.values():
		b.reset()
	_say("Tu es le CHASSEUR !" if local == hunter else "%s est le chasseur. Cache-toi !" % hunter.display_name,
		Color("ff3b30") if local == hunter else Color("ffffff"), 3.0)


## Tirage « en sac » : chacun est chasseur une fois avant qu'on recommence, jamais deux fois de suite.
func _draw_hunter() -> GkActor:
	if _sac.is_empty():
		for a: GkActor in actors:
			_sac.append(a.id)
		_sac.shuffle()
		if _sac.size() > 1 and _sac[0] == _last_hunter:
			_sac.append(_sac.pop_front())
		if round_no == 1 and _force_role != "":
			_sac.erase(local.id)
			if _force_role == "hunter":
				_sac.push_front(local.id)
			else:
				_sac.append(local.id)
	var id: int = _sac.pop_front()
	_last_hunter = id
	return actors[id]


func _spawn_spots(n: int) -> Array[Vector2i]:
	var c: Vector2i = map.spawns[0] if not map.spawns.is_empty() else Vector2i(map.width / 2, map.height / 2)
	var out: Array[Vector2i] = [c]
	var r: int = 1
	while out.size() < n and r < 6:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var t: Vector2i = c + Vector2i(dx * 2, dy * 2)
				if maxi(absi(dx), absi(dy)) == r and map.walkable(t) and not out.has(t):
					out.append(t)
		r += 1
	return out


func _finish_round() -> void:
	phase = Phase.END
	phase_t = GkRules.f("phase_end")
	for a: GkActor in actors:
		a.frozen = true
		if a == hunter:
			continue
		if a.role == GkActor.Role.HIDER:
			if a.hidden_in >= 0:
				_leave_cachette(a, false)
			_give(a, GkRules.score("hider_survive"))
			a.won_round = true
		_give(a, int(a.alive_t / 10.0) * GkRules.score("hider_per_10s"))
		if a.role == GkActor.Role.OUT:
			a.won_round = true
	if _round_found >= _round_hiders and _round_hiders > 0:
		_give(hunter, GkRules.score("hunter_all"))
	hunter.won_round = _round_found * 2 > _round_hiders
	for a: GkActor in actors:
		if a.role == GkActor.Role.HIDER or a.role == GkActor.Role.HUNTER:
			a.end_pose = "victory" if a.won_round else "sad"
	if _stats:
		_st["round"] = round_no
		_st["niveau"] = str(config.get("level", "normal"))
		_st["niveau_chasseur"] = _hunter_level if _hunter_level != "" else _st["niveau"]
		_st["chasses"] = _round_hiders
		_st["trouves"] = _round_found
		_st["restes_caches"] = _hiders_left()
		_st["duree"] = snappedf(hunt_elapsed, 0.1)
		print("[gk-stats] " + JSON.stringify(_st))
		if _rounds_max > 0 and round_no >= _rounds_max:
			get_tree().quit()
	if _log:
		var out: int = actors.filter(func(a: GkActor) -> bool: return a.role == GkActor.Role.OUT).size()
		print("[gk] round %d : chasseur %s, trouvés %d/%d, échappés %d, restés cachés %d, durée %.0f s" % [
			round_no, hunter.display_name, _round_found, _round_hiders, out,
			_round_hiders - _round_found - out, hunt_elapsed])


func _give(a: GkActor, pts: int) -> void:
	a.score += pts
	a.round_points += pts


func quit_to_podium() -> void:
	if phase == Phase.PODIUM:
		return
	phase = Phase.PODIUM
	for a: GkActor in actors:
		a.frozen = true


func go_menu() -> void:
	get_tree().change_scene_to_file("res://src/gordeka/gk_menu.tscn")


# ---------------------------------------------------------------- boucle

func _physics_process(dt: float) -> void:
	_last_dt = dt
	if phase == Phase.PODIUM:
		_update_view()
		return
	phase_t -= dt
	match phase:
		Phase.DRAW:
			if phase_t <= 0.0:
				phase = Phase.HIDE
				phase_t = GkRules.f("phase_hide")
				for a: GkActor in actors:
					a.frozen = a == hunter
				_say("Cachez-vous !" if local != hunter else "Compte jusqu'à quinze…", Color.WHITE, 2.0)
		Phase.HIDE:
			if phase_t <= 0.0:
				phase = Phase.HUNT
				phase_t = GkRules.f("phase_hunt")
				hunter.frozen = false
				hunter.play_once("hunter_reveal")
				_say("Le chasseur arrive !", Color("ff3b30"), 2.0)
		Phase.HUNT:
			hunt_elapsed += dt
			if absf(hunt_elapsed - GkRules.f("exits_open_at")) < dt * 0.5 + 0.0001:
				_say("Les sorties sont ouvertes !", Color("6fe08a"), 3.0)
			if phase_t <= 0.0 or _hiders_left() == 0:
				_finish_round()
		Phase.END:
			if phase_t <= 0.0:
				_start_round()
				return
	_control(dt)
	if phase == Phase.HUNT:
		_update_searches(dt)
		_update_traps()
		_update_capture(dt)
		_update_exits(dt)
		for a: GkActor in actors:
			if a.role == GkActor.Role.HIDER:
				a.alive_t += dt
	_update_cachettes(dt)
	for r: Dictionary in reveals:
		r["left"] = float(r["left"]) - dt
	reveals = reveals.filter(func(r: Dictionary) -> bool: return float(r["left"]) > 0.0)
	for m: Dictionary in messages:
		m["left"] = float(m["left"]) - dt
	messages = messages.filter(func(m: Dictionary) -> bool: return float(m["left"]) > 0.0)
	_update_view()


func _control(dt: float) -> void:
	for a: GkActor in actors:
		var move: Vector2 = Vector2.ZERO
		var look_dir: Vector2 = Vector2.ZERO
		var act: bool = false
		if a.is_bot:
			var cmd: Dictionary = (brains[a.id] as GkAi).update(dt)
			move = cmd.get("move", Vector2.ZERO)
			look_dir = cmd.get("look", Vector2.ZERO)
			act = bool(cmd.get("action", false))
		else:
			move = input.move()
			act = input.take_action()
		a.step(move, look_dir, dt)
		if act:
			act_for(a)


## Le bouton d'action, selon le rôle et l'endroit (SPEC-GORDEKA §4, §8).
func act_for(a: GkActor) -> void:
	if phase != Phase.HIDE and phase != Phase.HUNT:
		return
	match a.role:
		GkActor.Role.HIDER:
			if a.hidden_in >= 0:
				_leave_cachette(a, false)
				return
			var c: int = near_cachette(a, true)
			if c >= 0:
				_enter_cachette(a, c)
			elif a.power_cd <= 0.0:
				_place_trap(a)
		GkActor.Role.HUNTER:
			if phase != Phase.HUNT or a.search_left > 0.0:
				return
			var c2: int = near_cachette(a, false)
			if c2 >= 0:
				a.search_left = GkRules.f("search_time")
				_search_target[a.id] = c2
			elif a.power_cd <= 0.0:
				_detect(a)


## Libellé du bouton d'action pour un joueur (HUD).
func action_label(a: GkActor) -> String:
	match a.role:
		GkActor.Role.HIDER:
			if a.hidden_in >= 0:
				return "Sortir"
			if near_cachette(a, true) >= 0:
				return "Entrer"
			return "Piège"
		GkActor.Role.HUNTER:
			if near_cachette(a, false) >= 0:
				return "Fouiller"
			return "Onde"
	return ""


func action_cooldown(a: GkActor) -> float:
	var label: String = action_label(a)
	if label == "Piège":
		return a.power_cd / GkRules.f("trap_cooldown")
	if label == "Onde":
		return a.power_cd / GkRules.f("detect_cooldown")
	return 0.0


func _hiders_left() -> int:
	return actors.filter(func(a: GkActor) -> bool: return a.role == GkActor.Role.HIDER).size()


# ---------------------------------------------------------------- vision et capture

## Le chasseur voit-il un corps de rayon `r` en `p` ? Cône (ou petit cercle) puis ligne de vue
## libre vers le centre ou un des bords du corps (couche 2 : murs, caisses, bateaux, cachettes).
func sees(h: GkActor, p: Vector2, r: float) -> bool:
	var v: Vector2 = p - h.position
	var d: float = v.length()
	if d > GkRules.px("cone_range") + r:
		return false
	if d > GkRules.px("near_radius") + r:
		var half: float = deg_to_rad(GkRules.f("cone_deg")) * 0.5 + atan2(r, maxf(d, 1.0))
		if absf(angle_difference(h.look, v.angle())) > half:
			return false
	var side: Vector2 = v.orthogonal().normalized() * r * 0.8
	for target: Vector2 in [p, p + side, p - side]:
		if clear_line(h.position, target):
			return true
	return false


func clear_line(a: Vector2, b: Vector2) -> bool:
	var q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(a, b, GkMap.LAYER_SIGHT)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _update_capture(dt: float) -> void:
	_seen.clear()
	if hunter.frozen:
		return
	for a: GkActor in actors:
		if a.role != GkActor.Role.HIDER or a.hidden_in >= 0:
			a.gauge = 0.0
			continue
		var seen: bool = sees(hunter, a.position, a.radius)
		_seen[a.id] = seen
		if seen:
			a.gauge += dt / GkRules.f("capture_time")
			if a.gauge >= 1.0:
				_found(a)
		elif a.gauge > 0.0:
			a.gauge = maxf(0.0, a.gauge - dt * GkRules.f("capture_decay") / GkRules.f("capture_time"))
			if a.gauge <= 0.0 and _stats:
				_st["evasions_de_vue"] += 1


func _found(a: GkActor, via: String = "vue") -> void:
	if _stats:
		_st[via] = int(_st.get(via, 0)) + 1
		(_st["t_trouves"] as Array).append(snappedf(hunt_elapsed, 0.1))
		var tt: Vector2i = map.to_tile(a.position)
		(_st["lieux_trouves"] as Array).append([tt.x, tt.y])
		if hunt_elapsed - float(_revealed_at.get(a.id, -100.0)) < 12.0:
			_st["trouves_apres_onde"] += 1
		if hunt_elapsed - _trap_hit_at < 8.0:
			_st["trouves_apres_piege"] += 1
	if a.hidden_in >= 0:
		_leave_cachette(a, false)
	a.play_once("found")
	a.set_role(GkActor.Role.GHOST)
	a.gauge = 0.0
	_round_found += 1
	_give(hunter, GkRules.score("hunter_find"))
	_say("%s : trouvé !" % a.display_name, Color("ffcf4a"), 2.0)
	for b: GkAi in brains.values():
		b.on_found(a)


# ---------------------------------------------------------------- cachettes

## Cachette à portée de main (`free_only` : libre et pas verrouillée), sinon -1.
func near_cachette(a: GkActor, free_only: bool) -> int:
	var best: int = -1
	var bd: float = GkRules.px("use_range") + map.tile * 0.5
	for i: int in cachettes.size():
		var c: Dictionary = cachettes[i]
		if free_only and (int(c["occupant"]) >= 0 or float(c["lock"]) > 0.0):
			continue
		var d: float = a.position.distance_to(c["pos"])
		if d < bd:
			bd = d
			best = i
	return best


func _enter_cachette(a: GkActor, i: int) -> void:
	var c: Dictionary = cachettes[i]
	c["occupant"] = a.id
	c["shake"] = 0.6
	a.hidden_in = i
	a.hidden_t = 0.0
	a.gauge = 0.0
	a.position = c["pos"]
	a.play_once("hide_in")
	if _stats and phase == Phase.HUNT:
		_st["entrees_cachette"] += 1


func _leave_cachette(a: GkActor, forced: bool) -> void:
	var i: int = a.hidden_in
	if i < 0:
		return
	var c: Dictionary = cachettes[i]
	c["occupant"] = -1
	c["shake"] = 0.4
	if forced:
		c["lock"] = GkRules.f("hide_lock")
	a.hidden_in = -1
	a.play_once("hide_out")
	# Ressort sur la case libre voisine la plus loin du chasseur.
	var best: Vector2 = c["pos"]
	var bd: float = -1.0
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = (c["tile"] as Vector2i) + d
		if map.walkable(t):
			var dist: float = map.center(t).distance_to(hunter.position) if hunter else 0.0
			if dist > bd:
				bd = dist
				best = map.center(t)
	a.position = best


func _update_cachettes(dt: float) -> void:
	for c: Dictionary in cachettes:
		c["lock"] = maxf(0.0, float(c["lock"]) - dt)
		c["shake"] = maxf(0.0, float(c["shake"]) - dt)
	for a: GkActor in actors:
		if a.hidden_in >= 0:
			a.hidden_t += dt
			if a.hidden_t >= GkRules.f("hide_max"):
				_leave_cachette(a, true)
				if _stats:
					_st["ejections_cachette"] += 1
				if a == local:
					_say("Trop longtemps caché : dehors !", Color("ffcf4a"), 2.0)


func _update_searches(dt: float) -> void:
	for a: GkActor in actors:
		if a.search_left <= 0.0:
			continue
		a.search_left -= dt
		if a.search_left <= 0.0:
			var c: Dictionary = cachettes[int(_search_target.get(a.id, 0))]
			var occ: int = int(c["occupant"])
			c["shake"] = 0.5
			if occ >= 0:
				if _stats:
					_st["fouille_ok"] += 1
					_st["trouves_en_cachette"] += 1
				_found(actors[occ], "fouille")
			else:
				if _stats:
					_st["fouille_vide"] += 1
				if a == local:
					_say("Personne…", Color.WHITE, 1.2)


# ---------------------------------------------------------------- pouvoirs

func _place_trap(a: GkActor) -> void:
	traps.append({"pos": a.position, "owner": a.id})
	var mine: Array = traps.filter(func(t: Dictionary) -> bool: return int(t["owner"]) == a.id)
	if mine.size() > int(GkRules.f("trap_max")):
		traps.erase(mine[0])
	a.power_cd = GkRules.f("trap_cooldown")
	a.play_once("trap")
	if _stats:
		_st["pieges_poses"] += 1


func _update_traps() -> void:
	if hunter.frozen:
		return
	for t: Dictionary in traps.duplicate():
		if hunter.position.distance_to(t["pos"]) < hunter.radius + map.tile * 0.3:
			traps.erase(t)
			hunter.slow_left = GkRules.f("trap_duration")
			if _stats:
				_st["pieges_pris"] += 1
				_trap_hit_at = hunt_elapsed
			var owner: GkActor = actors[int(t["owner"])]
			_give(owner, GkRules.score("hider_trap_hit"))
			_say("Piège de %s !" % owner.display_name, Color("f2c12e"), 1.6)
			for b: GkAi in brains.values():
				b.on_trap(t["pos"])


func _detect(h: GkActor) -> void:
	h.power_cd = GkRules.f("detect_cooldown")
	h.play_once("detect")
	var found: Array[Vector2] = []
	for a: GkActor in actors:
		if a.role == GkActor.Role.HIDER and a.position.distance_to(h.position) <= GkRules.px("detect_radius"):
			reveals.append({"pos": a.position, "left": GkRules.f("detect_duration"), "id": a.id})
			found.append(a.position)
			_revealed_at[a.id] = hunt_elapsed
	reveals.append({"pos": h.position, "left": 0.6, "id": -1})     # l'onde elle-même
	# Personne dans le rayon : une flèche vers le chassé libre le plus proche (l'onde donne
	# toujours un indice, sans révéler où il est exactement).
	var hint: Vector2 = Vector2.ZERO
	if found.is_empty():
		var best: GkActor = null
		for a: GkActor in actors:
			if a.role == GkActor.Role.HIDER and (best == null
					or a.position.distance_to(h.position) < best.position.distance_to(h.position)):
				best = a
		if best != null:
			hint = (best.position - h.position).normalized()
			reveals.append({"pos": h.position, "dir": hint, "left": GkRules.f("detect_hint_duration"), "id": -2})
	if _stats:
		_st["ondes"] += 1
		_st["montres"] += found.size()
		if not found.is_empty():
			_st["ondes_utiles"] += 1
	if h.is_bot:
		(brains[h.id] as GkAi).on_detect(found, hint)
	if h != local:
		_say("Le chasseur lance une onde !", Color("9fd8ef"), 1.4)


# ---------------------------------------------------------------- sorties

## Tire les sorties du round : `exits_per_round` groupes, éloignés d'au moins `exits_min_gap` cases
## (pour ne pas ouvrir deux sorties voisines). On rompt ainsi la routine d'un round à l'autre.
func _pick_exits() -> void:
	open_exits.clear()
	open_exit_zones.clear()
	var groups: Array = map.exit_groups.duplicate()
	groups.shuffle()
	var picked: Array = []
	for grp: Dictionary in groups:
		if picked.size() >= int(GkRules.f("exits_per_round")):
			break
		var c: Vector2 = _group_center(grp)
		var ok: bool = true
		for p: Dictionary in picked:
			if c.distance_to(_group_center(p)) < GkRules.f("exits_min_gap"):
				ok = false
		if ok:
			picked.append(grp)
	for grp: Dictionary in picked:
		open_exits.append_array(grp["tiles"])
		open_exit_zones.append(str(grp["zone"]))


func _group_center(grp: Dictionary) -> Vector2:
	var s: Vector2 = Vector2.ZERO
	for t: Vector2i in grp["tiles"]:
		s += Vector2(t)
	return s / float((grp["tiles"] as Array).size())


func _open_exit_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for grp: Dictionary in map.exit_groups:
		if open_exits.has((grp["tiles"] as Array)[0]):
			var r: Rect2i = Rect2i(grp["tiles"][0], Vector2i.ONE)
			for t: Vector2i in grp["tiles"]:
				r = r.merge(Rect2i(t, Vector2i.ONE))
			out.append(r)
	return out


func exits_open() -> bool:
	return phase == Phase.HUNT and hunt_elapsed >= GkRules.f("exits_open_at")


func _update_exits(dt: float) -> void:
	if not exits_open():
		return
	for a: GkActor in actors:
		if a.role != GkActor.Role.HIDER or a.hidden_in >= 0:
			continue
		if open_exits.has(map.to_tile(a.position)) and a.gauge <= 0.0:
			a.extract_t += dt
			if a.extract_t >= GkRules.f("extract_hold"):
				a.play_once("extract")
				a.set_role(GkActor.Role.OUT)
				if _stats:
					_st["sorties"] += 1
				_give(a, GkRules.score("hider_extract"))
				_say("%s s'est échappé !" % a.display_name, Color("6fe08a"), 2.0)
		else:
			a.extract_t = 0.0


# ---------------------------------------------------------------- affichage

func _say(text: String, color: Color, seconds: float) -> void:
	messages.append({"text": text, "left": seconds, "color": color})
	if messages.size() > 3:
		messages.pop_front()


func _update_view() -> void:
	var as_hunter: bool = local == hunter and phase != Phase.END and phase != Phase.PODIUM
	_dark.color = Color(0.3, 0.3, 0.4) if as_hunter else Color.WHITE
	_cone_light.enabled = as_hunter
	_near_light.enabled = as_hunter
	if as_hunter:
		_cone_light.position = hunter.position
		_cone_light.rotation = hunter.look
		_near_light.position = hunter.position
	var scare: float = GkRules.px("scared_range")
	for a: GkActor in actors:
		a.scared = phase == Phase.HUNT and a.role == GkActor.Role.HIDER \
			and a.position.distance_to(hunter.position) < scare
		var show: bool = true
		if a.role == GkActor.Role.OUT:
			show = a == local
		elif as_hunter and a != hunter:
			show = a.role == GkActor.Role.HIDER and bool(_seen.get(a.id, false))
		if a.shown != show:
			a.shown = show
			a.queue_redraw()
	_camera.position = local.position
	if use_3d:
		view.refresh(_last_dt)
		for a: GkActor in actors:
			a.draw_2d = false
		_dark.color = Color.WHITE
		_cone_light.enabled = false
		_near_light.enabled = false
	else:
		_overlay.queue_redraw()
	hud.queue_redraw()


## Position à l'écran d'un point du jeu (HUD), en 2D comme en 3D.
func screen_pos(p: Vector2, height: float = 0.0) -> Vector2:
	if use_3d:
		return view.screen_pos(p, height)
	return get_viewport().get_canvas_transform() * p


## Cône du chasseur (polygone par lancer de rayons), vu des chassés et des fantômes.
func cone_polygon(h: GkActor) -> PackedVector2Array:
	var pts: PackedVector2Array = [h.position]
	var half: float = deg_to_rad(GkRules.f("cone_deg")) * 0.5
	var rng: float = GkRules.px("cone_range")
	var n: int = 40
	for i: int in n + 1:
		var a: float = h.look - half + 2.0 * half * float(i) / float(n)
		pts.append(_ray_end(h.position, h.position + Vector2.from_angle(a) * rng))
	return pts


func _ray_end(a: Vector2, b: Vector2) -> Vector2:
	var q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(a, b, GkMap.LAYER_SIGHT)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else b


func _draw_overlay(ci: CanvasItem) -> void:
	var as_hunter: bool = local == hunter and phase != Phase.END and phase != Phase.PODIUM
	var font: Font = ThemeDB.fallback_font
	# Sorties : grisées tant qu'elles sont fermées.
	var open: bool = exits_open()
	for r: Rect2i in _open_exit_rects():
		var px: Rect2 = Rect2(Vector2(r.position) * map.tile, Vector2(r.size) * map.tile)
		ci.draw_rect(px, Color(0.3, 0.9, 0.45, 0.35) if open else Color(0.4, 0.4, 0.4, 0.25))
		ci.draw_rect(px, Color("6fe08a") if open else Color("8a8a8a"), false, 4.0)
		ci.draw_string(font, px.position + Vector2(0, px.size.y * 0.5 + 8), "SORTIE" if open else "FERMÉE",
			HORIZONTAL_ALIGNMENT_CENTER, px.size.x, 22, Color.WHITE)
	# Cachettes : caisse orange, qui tremble quand on y entre ou qu'on la fouille.
	for c: Dictionary in cachettes:
		var shake: float = float(c["shake"])
		var off: Vector2 = Vector2(sin(shake * 60.0) * 4.0 * signf(shake), 0)
		var px2: Rect2 = Rect2((c["pos"] as Vector2) - Vector2(map.tile, map.tile) * 0.42 + off, Vector2(map.tile, map.tile) * 0.84)
		ci.draw_rect(px2, Color("e08a2e") if float(c["lock"]) <= 0.0 else Color("8a6a4a"))
		ci.draw_rect(px2, Color("5a3410"), false, 4.0)
		ci.draw_line(px2.position + Vector2(6, px2.size.y * 0.35), Vector2(px2.end.x - 6, px2.position.y + px2.size.y * 0.35), Color("5a3410"), 3.0)
		var occ: int = int(c["occupant"])
		if occ >= 0 and not as_hunter:
			# Les chassés savent qui est dedans : deux yeux de la couleur du joueur.
			ci.draw_circle(px2.get_center() + Vector2(-9, 8), 6, actors[occ].color)
			ci.draw_circle(px2.get_center() + Vector2(9, 8), 6, actors[occ].color)
	# Pièges : visibles des chassés ; le chasseur ne les voit que tout près, dans sa vue.
	for t: Dictionary in traps:
		var p: Vector2 = t["pos"]
		if as_hunter and (p.distance_to(hunter.position) > GkRules.px("trap_seen_range") or not sees(hunter, p, 6.0)):
			continue
		ci.draw_circle(p, 18, Color(0.95, 0.75, 0.2, 0.55))
		for k: int in 4:
			var a: float = float(k) * PI / 4.0
			ci.draw_line(p - Vector2.from_angle(a) * 18, p + Vector2.from_angle(a) * 18, Color("5a3410"), 3.0)
	# Cône rouge du chasseur, vu des chassés et des fantômes.
	if not as_hunter and hunter and (phase == Phase.HUNT or phase == Phase.HIDE):
		var poly: PackedVector2Array = cone_polygon(hunter)
		ci.draw_colored_polygon(poly, Color(1, 0.15, 0.1, 0.22 if phase == Phase.HUNT else 0.1))
		ci.draw_polyline(poly, Color(1, 0.2, 0.15, 0.5), 2.0)
		ci.draw_arc(hunter.position, GkRules.px("near_radius"), 0, TAU, 32, Color(1, 0.2, 0.15, 0.45), 2.0)
	# Onde de détection et silhouettes révélées.
	for r2: Dictionary in reveals:
		var left: float = float(r2["left"])
		if int(r2["id"]) == -2:
			if as_hunter or not local.is_hider():
				_draw_hint_arrow(ci, hunter.position, r2["dir"], left)
		elif int(r2["id"]) < 0:
			var k2: float = 1.0 - left / 0.6
			ci.draw_arc(r2["pos"], GkRules.px("detect_radius") * k2, 0, TAU, 64, Color(0.6, 0.85, 1.0, 1.0 - k2), 6.0)
		elif as_hunter or not local.is_hider():
			ci.draw_circle(r2["pos"], 26, Color(0.6, 0.85, 1.0, 0.5))
			ci.draw_arc(r2["pos"], 30, 0, TAU, 24, Color(0.6, 0.85, 1.0), 3.0)
	# Progression de la sortie.
	for a: GkActor in actors:
		if a.extract_t > 0.0 and a.role == GkActor.Role.HIDER and (not as_hunter or bool(_seen.get(a.id, false))):
			ci.draw_arc(a.position, a.radius + 14, -PI * 0.5, -PI * 0.5 + TAU * a.extract_t / GkRules.f("extract_hold"),
				32, Color("6fe08a"), 6.0)


## Flèche d'indice de l'onde : part du chasseur dans la direction du chassé le plus proche.
func _draw_hint_arrow(ci: CanvasItem, from: Vector2, dir: Vector2, left: float) -> void:
	var a: float = clampf(left, 0.0, 1.0)
	var c: Color = Color(0.6, 0.85, 1.0, a)
	var p0: Vector2 = from + dir * map.tile * 1.4
	var p1: Vector2 = from + dir * map.tile * 3.2
	ci.draw_line(p0, p1, c, 8.0, true)
	var side: Vector2 = dir.orthogonal() * map.tile * 0.45
	ci.draw_colored_polygon(PackedVector2Array([p1 + dir * map.tile * 0.7, p1 + side, p1 - side]), c)
