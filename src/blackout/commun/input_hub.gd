extends Node
## InputHub — dernier appareil utilisé (clavier, manette, tactile) et famille de la manette, pour
## les textes d'aide (Prompts) et les écrans qui s'adaptent à l'appareil. Hérité de l'ancien jeu,
## réduit au suivi de l'appareil : à remplacer par un équivalent Blackout.

## Le joueur vient de changer d'appareil (InputDevice.KEYBOARD/GAMEPAD/TOUCH)
## ou de famille de manette : les textes d'aide se remettent à jour.
signal device_changed(device: int)

## Dernier appareil utilisé (InputDevice.KEYBOARD, GAMEPAD ou TOUCH).
var device: int = InputDevice.KEYBOARD
## Famille de la dernière manette utilisée (InputDevice.FAMILY_*).
var pad_family: String = InputDevice.FAMILY_GENERIC
## QA (--device=…) : l'appareil est figé pour les captures.
var _device_forced: bool = false


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	InputDevice.install_menu_actions()
	_init_device()


## Appareil de départ : tactile sur téléphone, manette si une est déjà là,
## clavier sinon. `--device=gamepad[:famille]|touch|keyboard` (QA).
func _init_device() -> void:
	if Settings.touch_enabled():
		device = InputDevice.TOUCH
	var pads: Array[int] = Input.get_connected_joypads()
	if not pads.is_empty():
		pad_family = InputDevice.family_of(Input.get_joy_name(pads[0]))
		if device != InputDevice.TOUCH:
			device = InputDevice.GAMEPAD
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--device="):
			var spec: PackedStringArray = arg.trim_prefix("--device=").split(":")
			device = {"keyboard": InputDevice.KEYBOARD, "gamepad": InputDevice.GAMEPAD,
				"touch": InputDevice.TOUCH}.get(spec[0], device)
			if spec.size() > 1:
				pad_family = spec[1]
			_device_forced = true


## Vrai si le dernier appareil utilisé est une manette / l'écran tactile.
func using_gamepad() -> bool:
	return device == InputDevice.GAMEPAD


func using_touch() -> bool:
	return device == InputDevice.TOUCH


func _set_device(d: int, family: String) -> void:
	if _device_forced or (d == device and family == pad_family):
		return
	device = d
	pad_family = family
	device_changed.emit(device)


func _input(event: InputEvent) -> void:
	var d: int = InputDevice.classify(event)
	if d != InputDevice.NONE:
		_set_device(d, InputDevice.family_of(Input.get_joy_name(event.device))
			if d == InputDevice.GAMEPAD else pad_family)


func _on_joy_connection_changed(joy: int, connected: bool) -> void:
	# Web : une manette ne se déclare qu'à son premier appui → elle sert déjà.
	if connected:
		_set_device(InputDevice.GAMEPAD, InputDevice.family_of(Input.get_joy_name(joy)))
