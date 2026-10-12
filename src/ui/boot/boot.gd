extends Control
## Démarrage : bascule immédiatement vers l'écran titre (ou vers une scène
## de QA passée par l'URL `#scene=<id>` en web, ou `--scene=` en natif).


func _ready() -> void:
	_route.call_deferred()


func _route() -> void:
	var target: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--autofight="):
			return   # QaCapture lance le combat
		if arg.begins_with("--scene="):
			target = arg.trim_prefix("--scene=")
	if target == "" and OS.has_feature("web"):
		var hash_value: Variant = JavaScriptBridge.eval("window.location.hash", true)
		var text: String = str(hash_value)
		if text.begins_with("#scene="):
			target = text.trim_prefix("#scene=")
	if target.begins_with("res://"):
		SceneRouter.goto_path(target)
	elif target != "":
		SceneRouter.goto(StringName(target))
	else:
		SceneRouter.goto(&"title")
