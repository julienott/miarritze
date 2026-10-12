class_name KeyboardSource
extends InputSource
## Clavier via les actions Godot `<prefix>_up`… (project.godot, §4.1).
## Plusieurs préfixes possibles : en solo, J1 accepte aussi les touches J2.

var prefixes: PackedStringArray


func _init(p_prefixes: PackedStringArray) -> void:
	prefixes = p_prefixes


func sample() -> int:
	var mask: int = 0
	for prefix: String in prefixes:
		if Input.is_action_pressed(prefix + "_up"):
			mask |= UP
		if Input.is_action_pressed(prefix + "_down"):
			mask |= DOWN
		if Input.is_action_pressed(prefix + "_left"):
			mask |= LEFT
		if Input.is_action_pressed(prefix + "_right"):
			mask |= RIGHT
		if Input.is_action_pressed(prefix + "_punch"):
			mask |= PUNCH
		if Input.is_action_pressed(prefix + "_kick"):
			mask |= KICK
		if Input.is_action_pressed(prefix + "_special"):
			mask |= SPECIAL
		if Input.is_action_pressed(prefix + "_guard"):
			mask |= GUARD
	return mask


func label() -> String:
	return "Clavier " + ("J1" if prefixes.has("p1") else "J2")
