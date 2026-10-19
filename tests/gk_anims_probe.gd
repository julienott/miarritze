extends SceneTree
## Relève, pendant une partie IA contre IA accélérée, quelles animations les persos jouent
## vraiment (GkPerso._anim et _once), pour vérifier qu'elles sont toutes embarquées.
##   godot --headless --path . -s tests/gk_anims_probe.gd -- --gk-bots-only --speed=6

var _game: Node
var _t: float = 0.0
var _seen: Dictionary = {}


func _initialize() -> void:
	_game = load("res://src/gordeka/gk_game.tscn").instantiate()
	root.add_child(_game)


func _process(dt: float) -> bool:
	_t += dt
	for a: GkActor in (_game as GkGame).actors:
		if a.perso != null:
			var k: String = a.perso._once if a.perso._once != "" else a.perso._anim
			_seen[k] = int(_seen.get(k, 0)) + 1
	if _t > 240.0:
		print("[anims] ", JSON.stringify(_seen))
		quit()
	return false
