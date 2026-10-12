class_name GamepadSource
extends InputSource
## Manette (API Gamepad en web) : stick gauche ou croix, X/A/B/RB (§4.1).

## Zone morte du stick (0..1).
const DEADZONE: float = 0.45

var device: int = 0


func _init(p_device: int) -> void:
	device = p_device


func sample() -> int:
	var mask: int = 0
	var x: float = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var y: float = Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	if y < -DEADZONE or Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
		mask |= UP
	if y > DEADZONE or Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
		mask |= DOWN
	if x < -DEADZONE or Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
		mask |= LEFT
	if x > DEADZONE or Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
		mask |= RIGHT
	if Input.is_joy_button_pressed(device, JOY_BUTTON_X):
		mask |= PUNCH
	if Input.is_joy_button_pressed(device, JOY_BUTTON_A):
		mask |= KICK
	if Input.is_joy_button_pressed(device, JOY_BUTTON_B):
		mask |= SPECIAL
	if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER) \
			or Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5:
		mask |= GUARD
	return mask


func label() -> String:
	return "Manette %d" % (device + 1)
