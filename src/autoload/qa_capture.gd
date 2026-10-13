extends Node
## Outil QA (SPEC §14.2). Inactif sans argument.
##   --shot=/abs/out.png [--delay=3]     capture après un délai puis quitte
##   --scene=<id|res://…>                (lu par boot) écran de départ
##   --autofight=p1,p2,stage,seed[,lvl]  combat IA contre IA
##   --frames=60,300,900                 captures aux frames de sim listées
##                                       (fichiers <shot>_<frame>.png), puis quitte
##   --inputs=R*60,DLP,_*30              entrées scriptées pour J1 (J2 : niveau IA du
##                                       5e champ d'--autofight, 0 = inerte)
##   --touchidx=random                   index tactiles aléatoires (régression iOS)
## Web : `?qa=1` dans l'URL publie `window.__qa` (scène + boutons visibles en
## fractions d'écran) pour les tests Playwright qui touchent par libellé.

var _shot_path: String = ""
var _delay: float = 3.0
var _frames: PackedInt32Array = []
var _next_frame: int = 0
var touch_random: bool = false
var _inputs: String = ""
## QA : le joueur est piloté par l'IA (pyramide automatique).
var autoplay: bool = false
var _autotower: String = ""
var _tower_t: float = 0.0
var _shots_taken: Dictionary = {}
var _last_scene: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web") and str(JavaScriptBridge.eval("location.search")).contains("qa=1"):
		var t: Timer = Timer.new()
		t.wait_time = 0.25
		t.autostart = true
		t.timeout.connect(_publish_web_qa)
		add_child(t)
	var autofight: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--delay="):
			_delay = float(arg.trim_prefix("--delay="))
		elif arg.begins_with("--frames="):
			for part: String in arg.trim_prefix("--frames=").split(","):
				_frames.append(int(part))
			_frames.sort()
		elif arg.begins_with("--autofight="):
			autofight = arg.trim_prefix("--autofight=")
		elif arg.begins_with("--inputs="):
			_inputs = arg.trim_prefix("--inputs=")
		elif arg.begins_with("--autotower="):
			_autotower = arg.trim_prefix("--autotower=")
			autoplay = true
		elif arg.begins_with("--speed="):
			Engine.time_scale = float(arg.trim_prefix("--speed="))
		elif arg == "--touchidx=random":
			touch_random = true
	if autofight != "":
		_start_autofight.call_deferred(autofight)
	elif _inputs != "":
		# Entrées scriptées hors autofight (tutoriel, écrans) : J1 seulement.
		InputHub.set_sources.call_deferred(0, [ScriptSource.new(_inputs)])
	if _autotower != "":
		_start_autotower.call_deferred()
	if _shot_path != "":
		# Garde-fou : une capture QA ne doit jamais bloquer indéfiniment.
		var limit: float = 180.0
		for arg2: String in OS.get_cmdline_user_args():
			if arg2.begins_with("--timeout="):
				limit = float(arg2.trim_prefix("--timeout="))
		get_tree().create_timer(limit, true, false, true).timeout.connect(func() -> void:
			push_error("qa_capture: délai dépassé, abandon")
			get_tree().quit(2))
	if _shot_path == "":
		set_physics_process(false)
		return
	if _frames.is_empty() and _autotower == "":
		get_tree().create_timer(_delay).timeout.connect(_capture.bind(_shot_path, true))


func _start_autofight(spec: String) -> void:
	var parts: PackedStringArray = spec.split(",")
	var level: int = int(parts[4]) if parts.size() > 4 else 80
	var ai: Array = [level, level]
	if _inputs != "":
		ai = [0, level if parts.size() > 4 else 0]
		InputHub.set_sources(0, [ScriptSource.new(_inputs)])
		InputHub.set_sources(1, [])
	SceneRouter.goto(&"fight", {
		"p1": parts[0], "p2": parts[1] if parts.size() > 1 else "maia",
		"stage": parts[2] if parts.size() > 2 else "grande_plage",
		"seed": int(parts[3]) if parts.size() > 3 else 1,
		"ai": ai, "return_to": "title",
	})


func _start_autotower() -> void:
	var parts: PackedStringArray = _autotower.split(",")
	TowerMode.start(parts[0], 0, int(parts[1]) if parts.size() > 1 else 0)
	SceneRouter.goto(&"tower", {"event": "start"})


## Pilote la pyramide : appuie sur « Combattre », capture chaque écran clé.
func _process(delta: float) -> void:
	if _autotower == "":
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var sname: String = scene.name
	if sname != _last_scene:
		_last_scene = sname
		_tower_t = 0.0
		print("qa_capture: scène %s (étage %d)" % [sname, TowerMode.run.floor_index if TowerMode.run != null else -1])
	_tower_t += delta / maxf(Engine.time_scale, 0.01)   # temps réel (l'iris ignore la vitesse)
	if sname == "Tower" and _tower_t > 1.6:
		var key: String = "tower_%d_%d" % [TowerMode.run.floor_index, TowerMode.run.fight_log.size()] if TowerMode.run != null else "tower"
		_shot_once(key)
	if sname == "Tower" and _tower_t > 2.2:
		_tower_t = 0.0
		scene.call("_fight")
	elif sname == "Ending" and _tower_t > 2.0:
		var ending_t: int = int(_tower_t)
		if ending_t in [3, 6, 9, 13]:
			_shot_once("ending_%02d" % ending_t)
		if _tower_t > 20.0:
			_shot_once("ending_final")
			print("qa_capture: pyramide terminée, score %d" % (TowerMode.run.score if TowerMode.run != null else -1))
			get_tree().quit()


func _shot_once(key: String) -> void:
	if _shots_taken.has(key) or _shot_path == "":
		return
	_shots_taken[key] = true
	var base: String = _shot_path.trim_suffix(".png")
	_capture("%s_%s.png" % [base, key], false)


func _physics_process(_delta: float) -> void:
	if _frames.is_empty() or _next_frame >= _frames.size():
		return
	var scene: Node = get_tree().current_scene
	if scene == null or not ("sim" in scene) or scene.get("sim") == null:
		return
	var sim: FightSim = scene.get("sim")
	if sim.frame >= _frames[_next_frame]:
		var base: String = _shot_path.trim_suffix(".png")
		var last: bool = _next_frame == _frames.size() - 1
		_capture("%s_%05d.png" % [base, _frames[_next_frame]], last)
		_next_frame += 1


func _capture(path: String, quit_after: bool) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(path)
	print("qa_capture: écrit %s" % path)
	if quit_after:
		get_tree().quit()


## Web QA : scène courante + boutons visibles (texte, rect en fractions, état).
func _publish_web_qa() -> void:
	var root: Window = get_tree().root
	var view: Vector2 = root.get_visible_rect().size
	var buttons: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		if n is BaseButton and (n as Control).is_visible_in_tree():
			var b: BaseButton = n
			var r: Rect2 = b.get_global_rect()
			var label: String = (b as Button).text if b is Button else str(b.name)
			buttons.append({"t": label, "x": (r.position.x + r.size.x * 0.5) / view.x,
				"y": (r.position.y + r.size.y * 0.5) / view.y, "w": r.size.x / view.x, "h": r.size.y / view.y,
				"off": b.disabled})
	var scene: String = get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
	var data: Dictionary = {"scene": scene, "view": [view.x, view.y], "buttons": buttons}
	JavaScriptBridge.eval("window.__qa = %s;" % JSON.stringify(data), true)
