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

var _shot_path: String = ""
var _delay: float = 3.0
var _frames: PackedInt32Array = []
var _next_frame: int = 0
var touch_random: bool = false
var _inputs: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		elif arg == "--touchidx=random":
			touch_random = true
	if autofight != "":
		_start_autofight.call_deferred(autofight)
	if _shot_path != "":
		# Garde-fou : une capture QA ne doit jamais bloquer indéfiniment.
		get_tree().create_timer(180.0, true, false, true).timeout.connect(func() -> void:
			push_error("qa_capture: délai dépassé, abandon")
			get_tree().quit(2))
	if _shot_path == "":
		set_physics_process(false)
		return
	if _frames.is_empty():
		get_tree().create_timer(_delay).timeout.connect(_capture.bind(_shot_path, true))


func _start_autofight(spec: String) -> void:
	var parts: PackedStringArray = spec.split(",")
	var level: int = int(parts[4]) if parts.size() > 4 else 3
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
