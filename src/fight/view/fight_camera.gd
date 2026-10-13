class_name FightCamera
extends Camera2D
## Caméra : centrée entre les combattants, zoom fixe, lissée sur ~6 frames,
## bornée au monde, tremblement pixel-snappé (SPEC §10.7).

const WORLD_W: float = 576.0
const VIEW_H: float = 216.0

var _target_x: float = 288.0
var _shake: float = 0.0
var _shake_t: int = 0
var _bias: float = 0.0


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position = Vector2(288, VIEW_H / 2.0)


## Hauteur max dont la caméra monte pour garder un combattant projeté en vue.
const MAX_RISE: float = 30.0
var _top: float = 999.0


func set_top(top_y: float) -> void:
	_top = top_y


func follow(x1: float, x2: float, snap: bool = false) -> void:
	_target_x = (x1 + x2) * 0.5 + _bias
	var view_w: float = get_viewport_rect().size.x
	var half: float = view_w * 0.5
	_target_x = clampf(_target_x, half, maxf(WORLD_W - half, half))
	if WORLD_W < view_w:
		_target_x = WORLD_W * 0.5
	if snap:
		position.x = _target_x
	else:
		position.x = lerpf(position.x, _target_x, 1.0 / 6.0)
	# Le sommet du combattant le plus haut doit rester sous le HUD (~44 px).
	var rise: float = clampf(44.0 - (_top - 0.0), 0.0, MAX_RISE)
	var target_y: float = VIEW_H / 2.0 - rise
	position.y = target_y if snap else lerpf(position.y, target_y, 0.2)
	if _shake_t > 0:
		_shake_t -= 1
		var amp: float = _shake * float(_shake_t) / 10.0
		offset = Vector2(roundf(randf_range(-amp, amp)), roundf(randf_range(-amp, amp)))
	else:
		offset = Vector2.ZERO


func shake(amplitude: int) -> void:
	if amplitude <= 0:
		return
	_shake = maxf(_shake if _shake_t > 0 else 0.0, float(amplitude))
	_shake_t = 10


## Léger décentrage vers l'attaquant pendant le super.
func set_bias(px: float) -> void:
	_bias = px


func view_left() -> float:
	return position.x - get_viewport_rect().size.x * 0.5
