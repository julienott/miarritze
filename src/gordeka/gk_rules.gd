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


## Arguments du jeu : ligne de commande, plus, sur le web, le hash de l'adresse
## (`#scene=gk_game&visite=chasse` → `--scene=gk_game`, `--gk-visite=chasse`).
static func args() -> PackedStringArray:
	var out: PackedStringArray = OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		var h: String = str(JavaScriptBridge.eval("window.location.hash", true)).trim_prefix("#")
		for part: String in h.split("&", false):
			out.append("--" + part if part.begins_with("scene=") or part.begins_with("gk-") else "--gk-" + part)
	return out


static func f(key: String) -> float:
	return float(data().get(key, 0.0))


## Drapeau d'une idée de gameplay (0 ou 1 dans rules.json, `--gk-rules=idee_x:1` pour l'A/B).
static func on(key: String) -> bool:
	return f(key) > 0.5


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
