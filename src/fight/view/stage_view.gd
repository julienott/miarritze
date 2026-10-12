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
		_layers.append({"node": sprite, "factor": float(l.get("parallax", 1.0)),
			"y": float(l.get("y", 0.0))})


func _build_fallback() -> void:
	var sky: ColorRect = ColorRect.new()
	sky.color = Color(0.59, 0.84, 0.93)
	sky.size = Vector2(WORLD_W + 200, 216)
	sky.position = Vector2(-100, 0)
	add_child(sky)
	var far: Sprite2D = Sprite2D.new()
	far.texture = load("res://assets/sprites/bg_beach_0.png")
	far.centered = false
	far.scale = Vector2(1.6, 1.6)
	add_child(far)
	_layers.append({"node": far, "factor": 0.25, "y": -70.0})
	for i: int in 3:
		_anim_frames.append(load("res://assets/sprites/bg_beach_%d.png" % i))
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


func _process(delta: float) -> void:
	if _anim_sprite == null or _anim_frames.size() < 2:
		return
	_anim_t += delta
	var index: int = int(_anim_t * 3.0) % _anim_frames.size()
	_anim_sprite.texture = _anim_frames[index]
