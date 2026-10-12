class_name StageView
extends Node2D
## Décor d'un stage : calques en parallaxe (far 0,25, mid 0,6, sol 1,0,
## avant-plan 1,15) lus depuis assets/stages/<id>/stage.json (SPEC §10.6).
## Repli : décor provisoire construit depuis un ancien fond `bg_*`.

const WORLD_W: float = 576.0

var stage_id: String = ""
var data: Dictionary = {}
var _layers: Array[Dictionary] = []   # {node, factor}
var _anim_frames: Array[Texture2D] = []
var _anim_sprite: Sprite2D
var _anim_t: float = 0.0
var _anim_fps: float = 3.0
## Éléments d'ambiance (goélands…) : {node, speed, parallax, base_x, frames}
var _props: Array[Dictionary] = []


func setup(id: String) -> void:
	stage_id = id
	var path: String = "res://assets/stages/%s/stage.json" % id
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		data = parsed if parsed is Dictionary else {}
	if data.is_empty():
		_build_fallback()
		return
	for layer: Variant in data.get("layers", []):
		var l: Dictionary = layer
		var tex_path: String = "res://assets/stages/%s/%s" % [id, l["file"]]
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load(tex_path)
		sprite.centered = false
		sprite.z_index = int(l.get("z", 0))
		add_child(sprite)
		var frames: Array = l.get("frames", [])
		if not frames.is_empty():
			for fp: Variant in frames:
				_anim_frames.append(load("res://assets/stages/%s/%s" % [id, fp]))
			_anim_sprite = sprite
			_anim_fps = float(l.get("fps", 3.0))
		_layers.append({"node": sprite, "factor": float(l.get("parallax", 1.0)),
			"y": float(l.get("y", 0.0))})
	_build_props()


## Repli tant que le stage n'a pas ses calques : ancien décor i2i le plus proche.
const FALLBACK_BG: Dictionary = {
	"grande_plage": "bg_beach", "grande_plage_soir": "bg_beach", "cote_basques": "bg_surf",
	"cote_basques_crepuscule": "bg_surf", "port_pecheurs": "bg_fishing", "rocher_vierge": "bg_rock",
	"port_vieux": "bg_espadrille", "phare_sommet": "bg_lighthouse_intro", "halles": "bg_fishing", "fronton": "bg_espadrille",
	"stade": "bg_beach", "aquarium": "bg_surf",
}


func _build_props() -> void:
	for raw: Variant in data.get("props", []):
		var pr: Dictionary = raw
		if str(pr.get("kind", "")) != "gull":
			continue
		var frames: Array[Texture2D] = [load("res://assets/sprites/gull_1.png"), load("res://assets/sprites/gull_2.png")]
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = frames[0]
		sprite.z_index = -8
		sprite.flip_h = float(pr.get("speed", 8.0)) < 0.0
		add_child(sprite)
		_props.append({"node": sprite, "speed": float(pr.get("speed", 8.0)), "parallax": float(pr.get("parallax", 0.5)),
			"x": randf() * WORLD_W, "y": float(pr.get("y", 40)), "frames": frames})


func _build_fallback() -> void:
	var sky: ColorRect = ColorRect.new()
	sky.color = Color(0.59, 0.84, 0.93)
	sky.size = Vector2(WORLD_W + 200, 216)
	sky.position = Vector2(-100, 0)
	add_child(sky)
	var far: Sprite2D = Sprite2D.new()
	var bg: String = str(FALLBACK_BG.get(stage_id, "bg_beach"))
	var animated: bool = ResourceLoader.exists("res://assets/sprites/%s_0.png" % bg)
	far.texture = load("res://assets/sprites/%s%s.png" % [bg, "_0" if animated else ""])
	far.centered = false
	far.scale = Vector2(1.6, 1.6)
	add_child(far)
	_layers.append({"node": far, "factor": 0.25, "y": -70.0})
	if animated:
		for i: int in 3:
			_anim_frames.append(load("res://assets/sprites/%s_%d.png" % [bg, i]))
	_anim_sprite = far
	var floor_rect: ColorRect = ColorRect.new()
	floor_rect.color = Color(0.93, 0.79, 0.50)
	floor_rect.size = Vector2(WORLD_W + 200, 40)
	floor_rect.position = Vector2(-100, 176)
	add_child(floor_rect)
	var line: ColorRect = ColorRect.new()
	line.color = Color(0.84, 0.66, 0.38)
	line.size = Vector2(WORLD_W + 200, 2)
	line.position = Vector2(-100, 176)
	add_child(line)


## Place les calques selon la position de la caméra (bord gauche de la vue).
func update_scroll(view_left: float) -> void:
	for layer: Dictionary in _layers:
		var node: Node2D = layer["node"]
		var factor: float = layer["factor"]
		# Parallaxe classique : le calque défile à `factor` fois la caméra.
		var x: float = view_left * (1.0 - factor)
		node.position = Vector2(roundf(x), float(layer["y"]))
	for pr: Dictionary in _props:
		var node2: Sprite2D = pr["node"]
		node2.position = Vector2(roundf(float(pr["x"]) + view_left * (1.0 - float(pr["parallax"]))), float(pr["y"]))


func _process(delta: float) -> void:
	_anim_t += delta
	for pr: Dictionary in _props:
		var px: float = float(pr["x"]) + float(pr["speed"]) * delta
		if px > WORLD_W + 40.0:
			px = -40.0
		elif px < -40.0:
			px = WORLD_W + 40.0
		pr["x"] = px
		var frames: Array[Texture2D] = pr["frames"]
		(pr["node"] as Sprite2D).texture = frames[int(_anim_t * 4.0) % frames.size()]
	if _anim_sprite == null or _anim_frames.size() < 2:
		return
	var index: int = int(_anim_t * _anim_fps) % _anim_frames.size()
	_anim_sprite.texture = _anim_frames[index]
