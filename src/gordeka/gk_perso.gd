class_name GkPerso
extends Sprite2D
## Le perso dessiné d'un acteur, en 2D flat cartoon façon Among Us (docs/GORDEKA_STYLE_2D.md) :
## planches pixelforge (`pf_2d__anim`) dans assets/gordeka/persos/<id>/, de profil vers la
## droite (miroir à gauche). La tenue prend la couleur du joueur grâce au masque de tenue.
## L'animation suit l'état de l'acteur ; les gestes ponctuels (piège, détection, trouvé…)
## sont demandés par la partie via `play_once`.

const DIR: String = "res://assets/gordeka/persos/%s/"
## Hauteur du perso à l'écran (px), pieds compris ; ~90 px comme dans Among Us en 720p.
const HEIGHT_PX: float = 88.0
## Hauteur du perso dans une case pixelforge (px), pour l'échelle.
const CELL_PERSO_PX: float = 157.0
const GHOST_ALPHA: float = 0.5
const SHADER: String = """
shader_type canvas_item;
uniform sampler2D tenue : filter_linear;
uniform vec4 couleur : source_color = vec4(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = texture(tenue, UV).r;
	// Masque gris sur noir : la valeur garde l'ombrage du dessin (chemise blanche ≈ 0,87).
	vec3 teinte = couleur.rgb * clamp(m / 0.87, 0.0, 1.1);
	COLOR = vec4(mix(c.rgb, teinte, smoothstep(0.03, 0.3, m)), c.a) * COLOR;
}
"""

static var _anims: Dictionary = {}     # "louis/walk" -> {tex, mask, n, fps, loop, cell, feet}
static var _shader: Shader

var actor: GkActor
var _anim: String = ""
var _t: float = 0.0
var _once: String = ""
var _once_visible: bool = true


## Vrai si le perso a ses planches 2D dans le jeu.
static func available(character: String) -> bool:
	return ResourceLoader.exists((DIR % character) + "idle.png")


static func _data(character: String, anim: String) -> Dictionary:
	var key: String = character + "/" + anim
	if _anims.has(key):
		return _anims[key]
	var d: Dictionary = {}
	var path: String = (DIR % character) + anim
	if ResourceLoader.exists(path + ".png"):
		var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
		var n: int = int(j.get("frames", 1))
		# Fin de chaque image (s) : durées par image (`frame_ms`) ou cadence fixe (`fps`).
		var ends: PackedFloat32Array = PackedFloat32Array()
		var ms: Array = j.get("frame_ms", [])
		var acc: float = 0.0
		for i: int in n:
			acc += float(ms[i]) / 1000.0 if i < ms.size() else 1.0 / float(j.get("fps", 24.0))
			ends.append(acc)
		d = {
			"ends": ends,
			"tex": load(path + ".png"),
			"mask": load(path + "_tenue.png") if ResourceLoader.exists(path + "_tenue.png") else null,
			"n": n,
			"loop": bool(j.get("loop", false)),
			"cell": Vector2(j.get("cell", [256, 256])[0], j.get("cell", [256, 256])[1]),
			"feet": Vector2(j.get("feet_anchor", [128, 236])[0], j.get("feet_anchor", [128, 236])[1]),
		}
	_anims[key] = d
	return d


func setup(a: GkActor) -> void:
	actor = a
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = _shader
	material = m
	centered = false
	region_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	scale = Vector2.ONE * HEIGHT_PX / CELL_PERSO_PX


## Joue une animation une fois (piège, détection, trouvé, cachette…), puis reprend l'état.
func play_once(anim: String) -> void:
	if _data(actor.character, anim).is_empty():
		return
	_once = anim
	_once_visible = actor.shown
	_set_anim(anim)


func _set_anim(anim: String) -> void:
	if anim == _anim:
		return
	_anim = anim
	_t = 0.0
	var d: Dictionary = _data(actor.character, anim)
	if d.is_empty():
		return
	texture = d["tex"]
	(material as ShaderMaterial).set_shader_parameter("tenue", d["mask"])


## Animation qui découle de l'état de l'acteur.
func _state_anim() -> String:
	var a: GkActor = actor
	if a.end_pose != "":
		return a.end_pose
	if a.role == GkActor.Role.GHOST or a.role == GkActor.Role.OUT:
		return "ghost_move" if a.velocity.length() > 5.0 else "ghost"
	if a.role == GkActor.Role.HUNTER:
		if a.search_left > 0.0:
			return "search"
		if a.slow_left > 0.0:
			return "trapped"
	if a.velocity.length() > 5.0:
		return "run_scared" if a.scared else "walk"
	return "idle"


func _process(dt: float) -> void:
	if actor == null:
		return
	if _once == "":
		_set_anim(_state_anim())
	var d: Dictionary = _data(actor.character, _anim)
	if d.is_empty():
		visible = false
		return
	_t += dt
	var ends: PackedFloat32Array = d["ends"]
	var total: float = ends[ends.size() - 1]
	if _t >= total:
		if _once != "":
			_once = ""
			_set_anim(_state_anim())
			d = _data(actor.character, _anim)
			ends = d["ends"]
			total = ends[ends.size() - 1]
		elif bool(d["loop"]):
			_t = fmod(_t, total)
	var f: int = 0
	while f < ends.size() - 1 and _t >= ends[f]:
		f += 1
	var cell: Vector2 = d["cell"]
	region_rect = Rect2(Vector2(cell.x * float(f), 0.0), cell)
	var face: float = 1.0 if cos(actor.look) >= 0.0 else -1.0
	flip_h = face < 0.0
	# Pieds de la case sur les pieds de l'acteur (même ligne que l'ombre au sol).
	var feet: Vector2 = d["feet"]
	var fx: float = cell.x - feet.x if flip_h else feet.x
	position = Vector2(-fx * scale.x, actor.radius * 0.6 - feet.y * scale.y)
	var ghost: bool = (actor.role == GkActor.Role.GHOST or actor.role == GkActor.Role.OUT) and _once != "found" \
		and _once != "extract"
	(material as ShaderMaterial).set_shader_parameter("couleur", actor.color)
	modulate.a = GHOST_ALPHA if ghost else 1.0
	if _once != "":
		visible = actor.draw_2d and _once_visible
	else:
		visible = actor.draw_2d and actor.shown and actor.hidden_in < 0
