class_name TouchInput
extends Node
## Abstraction d'entrée : unifie tactile, souris et clavier (cf. CLAUDE.md §5.3).
##
## Robuste mobile : on ne présume PAS que l'index du toucher est 0 (sur
## iOS/Safari les identifiants sont arbitraires) — on suit le premier
## toucher actif, quel que soit son index. Les événements souris servent
## de repli (desktop, et doublons émulés dédupliqués par l'état _pressed).

## Émis sur un appui bref (toucher, clic ou Espace).
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
var _touch_index: int = -1          # -1 = appui souris/clavier
var _press_position: Vector2 = Vector2.ZERO
var _current_position: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if not _pressed:
				_touch_index = touch.index
				_begin_press(touch.position)
		elif _pressed and touch.index == _touch_index:
			_end_press(touch.position)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if _pressed and drag.index == _touch_index:
			_update_press(drag.position)
	elif event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			if not _pressed:
				_touch_index = -1
				_begin_press(mouse.position)
		elif _pressed and _touch_index == -1:
			_end_press(mouse.position)
	elif event is InputEventMouseMotion:
		if _pressed and _touch_index == -1:
			_update_press((event as InputEventMouseMotion).position)
	elif event is InputEventKey:
		var key: InputEventKey = event
		if key.keycode == KEY_SPACE and not key.echo:
			# Espace = tap clavier (pas de drag possible au clavier).
			if key.pressed:
				if not _pressed:
					_touch_index = -1
					_begin_press(get_viewport().get_visible_rect().size * 0.5)
			elif _pressed:
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
	_touch_index = -1
	if _dragging:
		_dragging = false
		drag_ended.emit(position, position - _press_position)
	else:
		tapped.emit(position)


## Vrai tant que le doigt (ou le clic/Espace) est maintenu — utile à la pêche.
func is_pressed() -> bool:
	return _pressed
