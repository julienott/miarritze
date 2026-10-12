class_name LogoView
extends Sprite2D
## Logo « MIARRITZE / BORROKA » animé : le lauburu tourne, l'écume bouge (3 frames).

@export var fps: float = 6.0

var _frames: Array[Texture2D] = []
var _t: float = 0.0


func _ready() -> void:
	for i: int in 3:
		_frames.append(load("res://assets/ui/logo_%d.png" % i))
	texture = _frames[0]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_t += delta
	texture = _frames[int(_t * fps) % _frames.size()]
