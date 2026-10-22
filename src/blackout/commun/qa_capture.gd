extends Node
## Outil QA. Inactif sans argument. Hérité de l'ancien jeu, réduit aux captures : à garder tant que
## les captures QA (`--shot`) et les tests web (`window.__qa`) s'en servent.
##   --shot=/abs/out.png [--delay=3]     capture après un délai puis quitte
##   --timeout=180                       garde-fou : abandon d'une capture bloquée
##   --speed=8                           accélère le temps (rounds IA contre IA)
##   --device=gamepad[:famille]|touch|keyboard   appareil figé pour les indications
##                                       (famille : xbox, playstation, nintendo, steamdeck ;
##                                       lu par InputHub)
##   --press=ui_cancel@3,joy:start@4     appuis simulés (action de l'InputMap, ou bouton
##                                       de manette joy:a|b|x|y|start|up|down|left|right)
##                                       à l'instant donné (s), pour capturer menus/pause
## L'écran de départ (`--scene=bk_<écran>`) est lu par bk_boot.
## Web : `?qa=1` dans l'URL publie `window.__qa` (scène + boutons visibles en
## fractions d'écran) pour les tests Playwright qui touchent par libellé.

var _shot_path: String = ""
var _delay: float = 3.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web") and str(JavaScriptBridge.eval("location.search")).contains("qa=1"):
		var t: Timer = Timer.new()
		t.wait_time = 0.25
		t.autostart = true
		t.timeout.connect(_publish_web_qa)
		add_child(t)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--delay="):
			_delay = float(arg.trim_prefix("--delay="))
		elif arg.begins_with("--speed="):
			Engine.time_scale = float(arg.trim_prefix("--speed="))
		elif arg.begins_with("--press="):
			for part: String in arg.trim_prefix("--press=").split(","):
				var at: PackedStringArray = part.split("@")
				if at.size() == 2:
					get_tree().create_timer(float(at[1])).timeout.connect(_press.bind(at[0]))
	if _shot_path == "":
		return
	# Garde-fou : une capture QA ne doit jamais bloquer indéfiniment.
	var limit: float = 180.0
	for arg2: String in OS.get_cmdline_user_args():
		if arg2.begins_with("--timeout="):
			limit = float(arg2.trim_prefix("--timeout="))
	get_tree().create_timer(limit, true, false, true).timeout.connect(func() -> void:
		push_error("qa_capture: délai dépassé, abandon")
		get_tree().quit(2))
	get_tree().create_timer(_delay).timeout.connect(_capture.bind(_shot_path, true))


const _JOY_NAMES: Dictionary = {"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"start": JOY_BUTTON_START, "up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN,
	"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT}


## Appui + relâché simulés (QA) : action de l'InputMap ou bouton de manette.
func _press(what: String) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEvent
		if what.begins_with("joy:"):
			var jb: InputEventJoypadButton = InputEventJoypadButton.new()
			jb.button_index = _JOY_NAMES.get(what.trim_prefix("joy:"), JOY_BUTTON_A)
			jb.pressed = pressed
			ev = jb
		else:
			var ac: InputEventAction = InputEventAction.new()
			ac.action = StringName(what)
			ac.pressed = pressed
			ev = ac
		Input.parse_input_event(ev)
		await get_tree().process_frame
	print("qa_capture: appui %s" % what)


func _capture(path: String, quit_after: bool) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	# Jeu en 640×360 étiré en « viewport » (BkEchelle) : la capture a la taille de la fenêtre, pixels
	# agrandis au plus proche voisin, comme à l'écran.
	var root: Window = get_tree().root
	if root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT and DisplayServer.get_name() != "headless":
		var w: Vector2i = DisplayServer.window_get_size()
		var k: int = maxi(1, mini(w.x / maxi(image.get_width(), 1), w.y / maxi(image.get_height(), 1)))
		image.resize(image.get_width() * k, image.get_height() * k, Image.INTERPOLATE_NEAREST)
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
