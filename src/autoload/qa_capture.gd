extends Node
## Outil QA : `godot <scène> -- --shot=/chemin.png [--delay=3]`
## capture le viewport après le délai puis quitte. Inactif sans l'argument.

var _shot_path: String = ""
var _delay: float = 3.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--delay="):
			_delay = float(arg.trim_prefix("--delay="))
	if _shot_path == "":
		set_process(false)
		return
	if OS.get_cmdline_user_args().has("--autostart"):
		get_tree().create_timer(0.5).timeout.connect(_auto_start)
	if OS.get_cmdline_user_args().has("--autotap"):
		var timer: Timer = Timer.new()
		timer.wait_time = 0.14
		timer.timeout.connect(_auto_tap)
		add_child(timer)
		timer.start()
	get_tree().create_timer(_delay).timeout.connect(_capture)


func _auto_tap() -> void:
	var press: InputEventScreenTouch = InputEventScreenTouch.new()
	press.index = 3   # index arbitraire : vérifie aussi le correctif iOS
	press.position = Vector2(640.0, 400.0)
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventScreenTouch = InputEventScreenTouch.new()
	release.index = 3
	release.position = Vector2(640.0, 400.0)
	release.pressed = false
	Input.parse_input_event(release)


func _auto_start() -> void:
	var root: Node = get_tree().current_scene
	if root is ChallengeBase and root.has_method("_on_start_pressed"):
		root.call("_on_start_pressed")


func _capture() -> void:
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(_shot_path)
	print("qa_capture: écrit %s" % _shot_path)
	get_tree().quit()
