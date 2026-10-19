class_name GkRules
extends RefCounted
## Règles de Gordeka (data/gordeka/rules.json, SPEC-GORDEKA §2-4). Tout réglage de jeu vient
## de ce fichier ; `--gk-rules=clé:valeur,…` les surcharge pour la QA (phases raccourcies).

const PATH: String = "res://data/gordeka/rules.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--gk-rules="):
				for pair: String in arg.trim_prefix("--gk-rules=").split(","):
					var kv: PackedStringArray = pair.split(":")
					if kv.size() == 2:
						_data[kv[0]] = float(kv[1])
	return _data


static func f(key: String) -> float:
	return float(data().get(key, 0.0))


## Distance en cases → pixels.
static func px(key: String) -> float:
	return f(key) * f("tile_px")


static func score(key: String) -> int:
	return int((data().get("score", {}) as Dictionary).get(key, 0))


static func ai(level: String) -> Dictionary:
	return (data().get("ai", {}) as Dictionary).get(level, {})


static func color(i: int) -> Color:
	var cs: Array = data().get("colors", ["#ffffff"])
	return Color(str(cs[i % cs.size()]))
