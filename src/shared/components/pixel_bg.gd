class_name PixelBg
extends Sprite2D
## Fond pixel art plein écran, animé (frames bg_<nom>_0/1/2 générées
## par tools/gen_bg.py ou rd_post.py). Couvre TOUT le viewport, y compris
## sur les écrans plus larges que 16:9 (iPhone paysage ≈ 19,5:9) : échelle
## « cover » + recentrage, recalculés à chaque redimensionnement.

@export var bg_name: String = "bg_menu"
@export var frame_count: int = 3
@export var fps: float = 3.0

var _frames: Array[Texture2D] = []
var _elapsed: float = 0.0
var _index: int = 0


func _ready() -> void:
	centered = false
	if frame_count <= 1:
		texture = load("res://assets/sprites/%s.png" % bg_name)
		set_process(false)
	else:
		for i: int in frame_count:
			_frames.append(load("res://assets/sprites/%s_%d.png" % [bg_name, i]))
		texture = _frames[0]
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()


func _fit_viewport() -> void:
	var view: Vector2 = get_viewport_rect().size
	var tex: Vector2 = texture.get_size()
	# cover : on remplit tout, quitte à rogner un peu en haut/bas
	var factor: float = maxf(view.x / tex.x, view.y / tex.y)
	scale = Vector2(factor, factor)
	# centré horizontalement, calé en bas (l'action est en bas de l'écran)
	position = Vector2((view.x - tex.x * factor) * 0.5, view.y - tex.y * factor)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 1.0 / fps:
		_elapsed = 0.0
		_index = (_index + 1) % _frames.size()
		texture = _frames[_index]
