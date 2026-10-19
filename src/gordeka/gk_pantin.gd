class_name GkPantin
extends Node2D
## Pantin articulé (docs/GORDEKA_STYLE_2D.md §4) : le mannequin pixelforge
## (assets/gordeka/mannequin/<gabarit>/) habillé de sa garde-robe, animé en direct par les
## chorégraphies (assets/gordeka/choreo/). La composition suit exactement `rig.json` → `compose` :
##   M_local = T(pivot) · T(x·H, −y·H) · R(rot) · S(sx, sy) · T(−pivot)
##   M(segment) = M(parent) · M_local ; root s'applique à tout ; `lag` décale les ancêtres.
## Le pantin est dessiné dans le repère du canevas ; le nœud parent place les pieds (root.pivot).

const MANNEQUIN: String = "res://assets/gordeka/mannequin/%s/"
const CHOREO: String = "res://assets/gordeka/choreo/%s.json"
## Expressions de tête (head_<nom>.png ; « neutral » = head.png), cf. docs/GORDEKA_STYLE_2D.md.
const EXPRESSIONS: Array[String] = ["neutral", "blink", "malicious", "scared", "surprised", "happy", "sad",
	"focused"]

static var _rigs: Dictionary = {}
static var _choreos: Dictionary = {}

var rig: Dictionary
var height: float = 466.0
var feet: Vector2 = Vector2.ZERO
var segs: Array[Dictionary] = []            # {name, parent, pivot, sprites: Array[Sprite2D]}
var by_name: Dictionary = {}                # nom → index dans segs
var _eval: Array[Dictionary] = []           # segs dans l'ordre parent → enfant (calcul des matrices)
var _heads: Dictionary = {}                 # expression → texture de tête du mannequin
var _ghost_body: Texture2D
var _body_tex: Texture2D
var choreo: Dictionary
var frame: int = 0
## Expression imposée par le jeu (ex. « surprised » dès que le chasseur le voit) ; "" = celle de
## la chorégraphie.
var head_override: String = ""


static func load_rig(gabarit: String) -> Dictionary:
	if not _rigs.has(gabarit):
		_rigs[gabarit] = JSON.parse_string(FileAccess.get_file_as_string((MANNEQUIN % gabarit) + "rig.json"))
	return _rigs[gabarit]


static func load_choreo(nom: String) -> Dictionary:
	if not _choreos.has(nom):
		var path: String = CHOREO % nom
		_choreos[nom] = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return _choreos[nom]


func setup(gabarit: String) -> void:
	rig = load_rig(gabarit)
	height = float(rig.get("height_px", 466.0))
	feet = _v(rig["root"]["pivot"])
	var dir: String = MANNEQUIN % gabarit
	var list: Array = rig["segments"].duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["z"]) < int(b["z"]))
	for s: Dictionary in list:
		var sp: Sprite2D = Sprite2D.new()
		sp.centered = false
		sp.texture = load(dir + str(s["name"]) + ".png")
		add_child(sp)
		by_name[str(s["name"])] = segs.size()
		segs.append({"name": str(s["name"]), "parent": str(s["parent"]), "pivot": _v(s["pivot"]), "sprites": [sp]})
	_eval = segs.duplicate()
	_eval.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _depth(a) < _depth(b))
	for e: String in EXPRESSIONS:
		var p: String = dir + ("head.png" if e == "neutral" else "head_%s.png" % e)
		if ResourceLoader.exists(p):
			_heads[e] = load(p)
	_body_tex = load(dir + "body.png")
	if ResourceLoader.exists(dir + "body_ghost.png"):
		_ghost_body = load(dir + "body_ghost.png")


func play(nom: String) -> void:
	choreo = load_choreo(nom)
	frame = 0


## Nombre d'images et durée de chaque image (s) de la chorégraphie courante.
func frame_count() -> int:
	return int(choreo.get("frames", 1))


func frame_time(i: int) -> float:
	var ms: Array = choreo.get("frame_ms", [])
	return float(ms[i]) / 1000.0 if i < ms.size() else 1.0 / float(choreo.get("fps", 24.0))


## Pose l'image `f` de la chorégraphie courante.
func pose(f: int) -> void:
	frame = f
	var lag: Dictionary = choreo.get("lag", {})
	var head_expr: String = head_override if head_override != "" else _step(choreo.get("head", []), f, "neutral")
	var ghost: bool = _step(choreo.get("body", []), f, "legs") == "ghost"
	var root_m: Transform2D = _local("root", feet, f)
	var root_a: float = _alpha("root", f)
	var mats: Dictionary = {}
	var alphas: Dictionary = {}
	for s: Dictionary in _eval:
		var nm: String = s["name"]
		var n: int = int(lag.get(nm, 0))
		var m: Transform2D
		var a: float
		if n == 0:
			var parent: String = s["parent"]
			m = (root_m if parent == "root" else mats[parent]) * _local(nm, s["pivot"], f)
			a = (root_a if parent == "root" else float(alphas[parent])) * _alpha(nm, f)
		else:
			# Retard (chapeau) : les ancêtres sous root sont pris à l'image f − n, le segment à f.
			var fl: int = _lagged(f, n)
			var chain: Array[String] = []
			var p: String = s["parent"]
			while p != "root":
				chain.push_front(p)
				p = segs[by_name[p]]["parent"]
			m = root_m
			a = root_a
			for c: String in chain:
				m = m * _local(c, segs[by_name[c]]["pivot"], fl)
				a *= _alpha(c, fl)
			m = m * _local(nm, s["pivot"], f)
			a *= _alpha(nm, f)
		mats[nm] = m
		alphas[nm] = a
		var hidden: bool = ghost and (nm.begins_with("leg_") or nm.begins_with("foot_"))
		for sp: Sprite2D in s["sprites"]:
			sp.transform = m
			sp.modulate.a = a
			sp.visible = not hidden
		var base: Sprite2D = s["sprites"][0]
		if nm == "head":
			base.texture = _heads.get(head_expr, _heads.get("neutral"))
		elif nm == "body":
			base.texture = _ghost_body if ghost and _ghost_body != null else _body_tex


func _depth(s: Dictionary) -> int:
	var d: int = 0
	var p: String = s["parent"]
	while p != "root":
		d += 1
		p = segs[by_name[p]]["parent"]
	return d


func _lagged(f: int, n: int) -> int:
	var total: int = frame_count()
	if bool(choreo.get("loop", false)):
		return posmod(f - n, total)
	return maxi(0, f - n)


func _local(track: String, pivot: Vector2, f: int) -> Transform2D:
	var keys: Array = choreo.get("tracks", {}).get(track, [])
	if keys.is_empty():
		return Transform2D.IDENTITY
	var x: float = _prop(keys, "x", f, 0.0)
	var y: float = _prop(keys, "y", f, 0.0)
	var rot: float = _prop(keys, "rot", f, 0.0)
	var sx: float = _prop(keys, "sx", f, 1.0)
	var sy: float = _prop(keys, "sy", f, 1.0)
	return Transform2D(0.0, pivot) * Transform2D(0.0, Vector2(x * height, -y * height)) \
		* Transform2D(deg_to_rad(rot), Vector2.ZERO) * Transform2D.IDENTITY.scaled(Vector2(sx, sy)) \
		* Transform2D(0.0, -pivot)


func _alpha(track: String, f: int) -> float:
	var keys: Array = choreo.get("tracks", {}).get(track, [])
	return 1.0 if keys.is_empty() else _prop(keys, "alpha", f, 1.0)


## Valeur d'une propriété à l'image f : interpolation entre les clés qui l'encadrent
## (adoucie 0,5 − 0,5·cos(πt), sauf clé de départ « linear »), constante hors des clés ;
## en boucle, la première clé est recopiée à f + frames et la dernière à f − frames.
func _prop(keys: Array, prop: String, f: int, def: float) -> float:
	var ks: Array = []
	for k: Dictionary in keys:
		if k.has(prop):
			ks.append(k)
	if ks.is_empty():
		return def
	if bool(choreo.get("loop", false)):
		var total: int = frame_count()
		var first: Dictionary = ks[0].duplicate()
		first["f"] = int(first["f"]) + total
		var last: Dictionary = ks[ks.size() - 1].duplicate()
		last["f"] = int(last["f"]) - total
		ks = [last] + ks + [first]
	if f <= int(ks[0]["f"]):
		return float(ks[0][prop])
	for i: int in ks.size() - 1:
		var k0: Dictionary = ks[i]
		var k1: Dictionary = ks[i + 1]
		var f0: int = int(k0["f"])
		var f1: int = int(k1["f"])
		if f >= f0 and f <= f1:
			if f1 == f0:
				return float(k1[prop])
			var t: float = float(f - f0) / float(f1 - f0)
			if str(k0.get("ease", "")) != "linear":
				t = 0.5 - 0.5 * cos(PI * t)
			return lerpf(float(k0[prop]), float(k1[prop]), t)
	return float(ks[ks.size() - 1][prop])


func _step(steps: Array, f: int, def: String) -> String:
	var v: String = def
	for st: Array in steps:
		if int(st[0]) <= f:
			v = str(st[1])
	return v


func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
