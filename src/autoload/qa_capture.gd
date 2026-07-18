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
	get_tree().create_timer(_delay).timeout.connect(_capture)


func _capture() -> void:
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(_shot_path)
	print("qa_capture: écrit %s" % _shot_path)
	get_tree().quit()
