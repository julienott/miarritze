extends Control
## Écran de démarrage : fond + titre "Miarritze", puis bascule vers
## l'orientation_gate après un court délai. Rien d'autre en Phase 0.

## Durée d'affichage du titre avant de basculer, en secondes.
@export var splash_duration: float = 1.5


func _ready() -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(splash_duration)
	timer.timeout.connect(_on_splash_timer_timeout)


func _on_splash_timer_timeout() -> void:
	if _route_debug_hash():
		return
	SceneRouter.goto_orientation_gate()


## Accès direct à une scène via l'URL (QA) : /#scene=hub, /#scene=surf…
func _route_debug_hash() -> bool:
	if not OS.has_feature("web"):
		return false
	var hash_value: Variant = JavaScriptBridge.eval("window.location.hash", true)
	var text: String = str(hash_value)
	print("boot: hash='%s'" % text)
	if not text.begins_with("#scene="):
		return false
	var target: StringName = StringName(text.trim_prefix("#scene="))
	match target:
		&"hub":
			SceneRouter.goto_hub()
		&"pseudo_entry":
			SceneRouter.goto_pseudo_entry()
		&"leaderboard":
			SceneRouter.goto_leaderboard()
		&"results":
			SceneRouter.goto_results(&"surf", 123, true)
		_:
			SceneRouter.goto_challenge(target)
	return true
