class_name ScriptSource
extends InputSource
## Entrées scriptées (QA, démos) : « R*60,DL*3,DLP,_*30 ».
## Lettres : U D L R (directions absolues), P K S G (boutons), _ = rien.
## Un pas par appel à sample() (donc un pas par tick de sim).

var _frames: PackedInt32Array = []
var _i: int = 0


func _init(script_text: String) -> void:
	for token: String in script_text.split(","):
		var parts: PackedStringArray = token.strip_edges().split("*")
		var count: int = int(parts[1]) if parts.size() > 1 else 1
		var mask: int = 0
		for ch: String in parts[0]:
			match ch:
				"U": mask |= UP
				"D": mask |= DOWN
				"L": mask |= LEFT
				"R": mask |= RIGHT
				"P": mask |= PUNCH
				"K": mask |= KICK
				"S": mask |= SPECIAL
				"G": mask |= GUARD
		for k: int in count:
			_frames.append(mask)


func sample() -> int:
	if _i >= _frames.size():
		return 0
	_i += 1
	return _frames[_i - 1]


func label() -> String:
	return "Script"
