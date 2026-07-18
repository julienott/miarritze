class_name TouchInput
extends Node
## Abstraction d'entrée : unifie tactile et clavier/souris (bonus desktop).
##
## Trois gestes (cf. CLAUDE.md §5.3) : tap, drag (vecteur + magnitude),
## et leurs signaux. Aucune épreuve ne lit les InputEvent bruts.
## À instancier comme nœud enfant de la scène qui consomme les gestes.

## Émis sur un appui bref (toucher, Espace ou clic).
signal tapped(position: Vector2)

## Émis au début d'un glisser (position de départ).
signal drag_started(position: Vector2)

## Émis pendant le glisser. `vector` = position courante - départ.
signal drag_updated(position: Vector2, vector: Vector2)

## Émis au relâcher du glisser, avec le vecteur final.
signal drag_ended(position: Vector2, vector: Vector2)

## Distance (px) au-delà de laquelle un appui devient un drag et non un tap.
@export var drag_threshold: float = 24.0

var _pressed: bool = false
var _dragging: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _current_position: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.index != 0:
			return
		if touch.pressed:
			_begin_press(touch.position)
		else:
			_end_press(touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == 0 and _pressed:
			_update_press(drag.position)
	elif event is InputEventKey:
		var key: InputEventKey = event
		if key.keycode == KEY_SPACE and not key.echo:
			# Espace = tap clavier (pas de drag possible au clavier).
			if key.pressed:
				_begin_press(get_viewport().get_visible_rect().size * 0.5)
			else:
				_end_press(_current_position)


func _begin_press(position: Vector2) -> void:
	_pressed = true
	_dragging = false
	_press_position = position
	_current_position = position


func _update_press(position: Vector2) -> void:
	_current_position = position
	var vector: Vector2 = position - _press_position
	if not _dragging and vector.length() >= drag_threshold:
		_dragging = true
		drag_started.emit(_press_position)
	if _dragging:
		drag_updated.emit(position, vector)


func _end_press(position: Vector2) -> void:
	if not _pressed:
		return
	_pressed = false
	if _dragging:
		_dragging = false
		drag_ended.emit(position, position - _press_position)
	else:
		tapped.emit(position)


## Vrai tant que le doigt (ou Espace) est maintenu — utile pour la pêche.
func is_pressed() -> bool:
	return _pressed
