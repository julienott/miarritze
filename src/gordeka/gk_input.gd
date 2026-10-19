class_name GkInput
extends Node
## Source d'entrées du joueur local (SPEC-GORDEKA §5) : déplacement + un seul bouton.
##   clavier : flèches ou ZQSD/WASD, Espace ou Entrée ;
##   manette : stick gauche ou croix, A ;
##   tactile : joystick flottant sur la moitié gauche (là où le pouce se pose),
##             bouton d'action en bas à droite.
## Seule source qui lit les InputEvent bruts (CLAUDE.md §0.4) ; le jeu ne voit que move/action.

signal quit_requested

const STICK_RADIUS: float = 90.0
const ACTION_RADIUS: float = 92.0

var touch_index: int = -1
var touch_origin: Vector2 = Vector2.ZERO
var touch_pos: Vector2 = Vector2.ZERO
var touch_used: bool = false        # un toucher a eu lieu : on affiche les commandes tactiles
var _action_pending: bool = false


## Centre du bouton d'action à l'écran (coordonnées de la fenêtre logique).
func action_center() -> Vector2:
	var s: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(s.x - 150, s.y - 150)


func move() -> Vector2:
	var v: Vector2 = Vector2.ZERO
	if touch_index >= 0:
		v = (touch_pos - touch_origin) / STICK_RADIUS
		return v.limit_length(1.0) if v.length() > 0.15 else Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_Q):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		v.x += 1
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_Z):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		v.y += 1
	for pad: int in Input.get_connected_joypads():
		var a: Vector2 = Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if a.length() > 0.25:
			v += a
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT):
			v.x -= 1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT):
			v.x += 1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP):
			v.y -= 1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN):
			v.y += 1
	return v.limit_length(1.0)


## Le bouton d'action a-t-il été pressé depuis le dernier appel ?
func take_action() -> bool:
	var a: bool = _action_pending
	_action_pending = false
	return a


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		touch_used = true
		var vs: Vector2 = get_viewport().get_visible_rect().size
		if t.pressed:
			# Moitié droite (sous la bande du haut, réservée à « Quitter ») = bouton d'action.
			if t.position.distance_to(action_center()) < ACTION_RADIUS * 1.3 or \
					(t.position.x > vs.x * 0.5 and t.position.y > vs.y * 0.22):
				_action_pending = true
			elif touch_index < 0:
				# Index arbitraire sur iOS (CLAUDE.md §0.4) : on retient celui-ci.
				touch_index = t.index
				touch_origin = t.position
				touch_pos = t.position
		elif t.index == touch_index:
			touch_index = -1
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == touch_index:
			touch_pos = d.position
			# Le joystick suit le pouce s'il dépasse le cercle.
			var off: Vector2 = touch_pos - touch_origin
			if off.length() > STICK_RADIUS * 1.4:
				touch_origin = touch_pos - off.normalized() * STICK_RADIUS * 1.4
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
			_action_pending = true
		elif k.physical_keycode == KEY_ESCAPE:
			quit_requested.emit()
	elif event is InputEventJoypadButton and event.pressed:
		var b: InputEventJoypadButton = event
		if b.button_index == JOY_BUTTON_A:
			_action_pending = true
		elif b.button_index == JOY_BUTTON_START:
			quit_requested.emit()
