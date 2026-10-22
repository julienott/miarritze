class_name BkRules
extends RefCounted
## Règles de Blackout (data/blackout/rules.json, SPEC-GORDEKA §2-4). Tout réglage de jeu vient
## de ce fichier ; `--bk-rules=clé:valeur,…` les surcharge pour la QA (phases raccourcies).

const PATH: String = "res://data/blackout/rules.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--bk-rules="):
				for pair: String in arg.trim_prefix("--bk-rules=").split(","):
					var kv: PackedStringArray = pair.split(":")
					if kv.size() == 2:
						_data[kv[0]] = float(kv[1])
	return _data


## Arguments du jeu : ligne de commande, plus, sur le web, le hash de l'adresse
## (`#scene=bk_game&visite=chasse` → `--scene=bk_game`, `--bk-visite=chasse`).
static func args() -> PackedStringArray:
	var out: PackedStringArray = OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		var h: String = str(JavaScriptBridge.eval("window.location.hash", true)).trim_prefix("#")
		for part: String in h.split("&", false):
			out.append("--" + part if part.begins_with("scene=") or part.begins_with("bk-") else "--bk-" + part)
	return out


## Options de partie validées par Julien (data/blackout/options_partie.json), pour le futur menu de
## création de partie : liste des options avec leurs réglages (clé de rules.json, type, bornes, défaut).
const OPTIONS_PATH: String = "res://data/blackout/options_partie.json"


static func options_partie() -> Array:
	var f: FileAccess = FileAccess.open(OPTIONS_PATH, FileAccess.READ)
	if f == null:
		return []
	var d: Variant = JSON.parse_string(f.get_as_text())
	return (d as Dictionary).get("options", []) if d is Dictionary else []


## Pose les choix du menu ({clé: valeur}) par-dessus rules.json pour la partie qui commence. Seules les
## clés déclarées dans options_partie.json sont acceptées, bornées à leur min/max.
static func appliquer_options(choix: Dictionary) -> void:
	for o: Dictionary in options_partie():
		for r: Dictionary in o.get("reglages", []):
			var cle: String = str(r.get("cle", ""))
			if not choix.has(cle):
				continue
			var v: float = float(choix[cle])
			if str(r.get("type", "")) == "on_off":
				v = 1.0 if v > 0.5 else 0.0
			else:
				v = clampf(v, float(r.get("min", v)), float(r.get("max", v)))
			data()[cle] = v


## Réglages propres à une carte (zones.json → « regles », écrit par le générateur de la carte) : posés
## par-dessus rules.json pour la partie, retirés quand elle se termine (`retire_carte`). Une clé passée
## en ligne de commande (`--bk-rules=`, A/B) garde la priorité. Valeurs d'avant, pour les remettre.
static var _carte: Dictionary = {}


static func surcharge_carte(regles: Dictionary) -> void:
	retire_carte()
	var cli: Array = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--bk-rules="):
			for pair: String in arg.trim_prefix("--bk-rules=").split(","):
				cli.append(pair.split(":")[0])
	for k: Variant in regles:
		var key: String = str(k)
		if cli.has(key):
			continue
		_carte[key] = data().get(key)
		data()[key] = float(regles[k])


static func retire_carte() -> void:
	for k: String in _carte:
		if _carte[k] == null:
			data().erase(k)
		else:
			data()[k] = _carte[k]
	_carte.clear()


static func f(key: String) -> float:
	return float(data().get(key, 0.0))


## Drapeau d'une idée de gameplay (0 ou 1 dans rules.json, `--bk-rules=idee_x:1` pour l'A/B).
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
