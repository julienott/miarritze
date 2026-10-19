class_name GkPerso
extends Sprite2D
## Le perso dessiné d'un acteur, en 2D flat cartoon façon Among Us (docs/GORDEKA_STYLE_2D.md) :
## planches pixelforge (`pf_2d__anim`) dans assets/gordeka/persos/<id>/, de profil vers la
## droite (miroir à gauche). La tenue prend la couleur du joueur grâce au masque de tenue.
## L'animation suit l'état de l'acteur ; les gestes ponctuels (piège, détection, trouvé…)
## sont demandés par la partie via `play_once`.
## Mode pantin (`use_pantin`) : le mannequin articulé (GkPantin) remplace les planches ; il sera
## habillé de la garde-robe du perso (docs/GORDEKA_STYLE_2D.md §4).

const DIR: String = "res://assets/gordeka/persos/%s/"
## Hauteur du perso à l'écran (px), pieds compris ; ~90 px comme dans Among Us en 720p.
const HEIGHT_PX: float = 88.0
## Hauteur du perso dans une case pixelforge (px), pour l'échelle.
const CELL_PERSO_PX: float = 199.0
const GHOST_ALPHA: float = 0.5
## Durée visée d'un cycle de déplacement (s) à la vitesse d'un chassé (0,5 s faisait courir, Julien) :
## les planches pixelforge (mouvements Quaternius) durent plus longtemps, on les accélère, et la
## cadence suit la vitesse réelle (piège, chasseur plus rapide) pour que les pieds ne glissent pas.
const BOUNCE_PX: float = 5.0        # hauteur du rebond de marche (px à l'écran)
const SQUASH: float = 0.07          # écrasement vertical au contact du pied
const CYCLE_S: Dictionary = {"walk": 0.85, "run_scared": 0.6, "ghost_move": 1.0}
const SHADER: String = """
shader_type canvas_item;
uniform sampler2D tenue : filter_linear;
uniform vec4 couleur : source_color = vec4(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = texture(tenue, UV).r;
	// Masque gris sur noir : 1 = ton clair de la tenue, la valeur garde l'ombrage du dessin.
	vec3 teinte = couleur.rgb * clamp(m, 0.0, 1.0);
	COLOR = vec4(mix(c.rgb, teinte, smoothstep(0.03, 0.3, m)), c.a) * COLOR;
}
"""

static var _anims: Dictionary = {}     # "louis/walk" -> {tex, mask, n, fps, loop, cell, feet}
static var _shader: Shader
## QA (`--gk-mannequin`) : tous les persos en pantin articulé.
static var use_pantin: bool = false
static var _pdata: Dictionary = {}     # chorégraphie -> {ends, loop}

var pantin: GkPantin

var actor: GkActor
var _anim: String = ""
var _t: float = 0.0
var _once: String = ""
var _once_visible: bool = true
var _float_t: float = 0.0


## Vrai si le perso a ses planches 2D dans le jeu.
static func available(character: String) -> bool:
	return use_pantin or ResourceLoader.exists((DIR % character) + "idle.png")


## Durées d'une chorégraphie du pantin, au même format que les planches.
static func _pantin_data(anim: String) -> Dictionary:
	if _pdata.has(anim):
		return _pdata[anim]
	var c: Dictionary = GkPantin.load_choreo(anim)
	var d: Dictionary = {}
	if not c.is_empty():
		var ends: PackedFloat32Array = PackedFloat32Array()
		var ms: Array = c.get("frame_ms", [])
		var acc: float = 0.0
		for i: int in int(c.get("frames", 1)):
			acc += float(ms[i]) / 1000.0 if i < ms.size() else 1.0 / float(c.get("fps", 24.0))
			ends.append(acc)
		d = {"ends": ends, "loop": bool(c.get("loop", false))}
	_pdata[anim] = d
	return d


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
	if use_pantin:
		pantin = GkPantin.new()
		pantin.setup("humain")
		add_child(pantin)
		scale = Vector2.ONE * HEIGHT_PX / pantin.height
		return
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
	if _get_data(anim).is_empty():
		return
	_once = anim
	_once_visible = actor.shown
	_set_anim(anim)


func _set_anim(anim: String) -> void:
	if anim == _anim:
		return
	_anim = anim
	_t = 0.0
	if pantin != null:
		pantin.play(anim)
		return
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
	var d: Dictionary = _get_data(_anim)
	if d.is_empty():
		visible = false
		return
	var ends: PackedFloat32Array = d["ends"]
	var total: float = ends[ends.size() - 1]
	var rate: float = 1.0
	if CYCLE_S.has(_anim) and pantin == null:
		rate = total / float(CYCLE_S[_anim]) * clampf(actor.velocity.length() / GkRules.px("speed_hider"), 0.5, 1.5)
	_t += dt * rate
	if _t >= total:
		if _once != "":
			_once = ""
			_set_anim(_state_anim())
			d = _get_data(_anim)
			ends = d["ends"]
			total = ends[ends.size() - 1]
		elif bool(d["loop"]):
			_t = fmod(_t, total)
	var f: int = 0
	while f < ends.size() - 1 and _t >= ends[f]:
		f += 1
	var face: float = 1.0 if cos(actor.look) >= 0.0 else -1.0
	var ghost: bool = (actor.role == GkActor.Role.GHOST or actor.role == GkActor.Role.OUT) and _once != "found" \
		and _once != "extract"
	modulate.a = GHOST_ALPHA if ghost else 1.0
	if _once != "":
		visible = actor.draw_2d and _once_visible
	else:
		visible = actor.draw_2d and actor.shown and actor.hidden_in < 0
	if pantin != null:
		# Étonné dès que le chasseur le voit (la jauge de capture monte).
		pantin.head_override = "surprised" if actor.gauge > 0.0 and actor.role == GkActor.Role.HIDER else ""
		pantin.pose(f)
		var k: float = HEIGHT_PX / pantin.height
		scale = Vector2(k * face, k)
		position = Vector2(-pantin.feet.x * scale.x, actor.radius * 0.6 - pantin.feet.y * k)
		# Mannequin gris teinté de la couleur du joueur, en attendant sa garde-robe.
		pantin.modulate = actor.color.lerp(Color.WHITE, 0.35)
		return
	var cell: Vector2 = d["cell"]
	region_rect = Rect2(Vector2(cell.x * float(f), 0.0), cell)
	flip_h = face < 0.0
	# Pieds de la case sur les pieds de l'acteur (même ligne que l'ombre au sol).
	var feet: Vector2 = d["feet"]
	var fx: float = cell.x - feet.x if flip_h else feet.x
	# Petit rebond façon Among Us à chaque pas, avec un léger écrasement quand le pied touche le sol
	# (idée de Julien) : deux rebonds par cycle, au rythme de la planche.
	var k: float = HEIGHT_PX / CELL_PERSO_PX
	var lift: float = 0.0
	var squash: float = 0.0
	if CYCLE_S.has(_anim) and actor.velocity.length() > 5.0:
		var b: float = absf(sin(_t / total * TAU))       # 0 au contact du pied, 1 en l'air
		lift = BOUNCE_PX * (1.4 if _anim == "run_scared" else 1.0) * b
		squash = SQUASH * pow(1.0 - b, 3.0)
	scale = Vector2(k * (1.0 + squash * 0.6), k * (1.0 - squash))
	position = Vector2(-fx * scale.x, actor.radius * 0.6 - feet.y * scale.y - lift)
	if ghost:
		# Le fantôme (ailes d'ange) flotte au-dessus du sol.
		_float_t += get_process_delta_time()
		position.y -= 10.0 + 5.0 * sin(_float_t * 3.0)
	(material as ShaderMaterial).set_shader_parameter("couleur", actor.color)


func _get_data(anim: String) -> Dictionary:
	return _pantin_data(anim) if pantin != null else _data(actor.character, anim)
