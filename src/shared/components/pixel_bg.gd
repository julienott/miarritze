class_name PixelBg
extends Sprite2D
## Fond pixel art plein écran, animé (frames bg_<nom>_0/1/2 générées
## par tools/gen_bg.py). Échelle x4 : 320x180 → 1280x720, filtre nearest.

@export var bg_name: String = "bg_menu"
@export var frame_count: int = 3
@export var fps: float = 3.0

var _frames: Array[Texture2D] = []
var _elapsed: float = 0.0
var _index: int = 0


func _ready() -> void:
	centered = false
	scale = Vector2(4.0, 4.0)
	if frame_count <= 1:
		texture = load("res://assets/sprites/%s.png" % bg_name)
		set_process(false)
		return
	for i: int in frame_count:
		_frames.append(load("res://assets/sprites/%s_%d.png" % [bg_name, i]))
	texture = _frames[0]


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 1.0 / fps:
		_elapsed = 0.0
		_index = (_index + 1) % _frames.size()
		texture = _frames[_index]
