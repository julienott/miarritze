extends Node
## InputHub — assigne des sources d'entrée aux slots de joueurs et
## échantillonne UNE fois par tick de sim (SPEC-BORROKA §7.1).
##
## Un slot combine plusieurs sources (OU binaire) : clavier + manette, etc.
## Le combat ne lit jamais d'InputEvent : il appelle `sample(slot)`.

signal sources_changed
## Le joueur vient de changer d'appareil (InputDevice.KEYBOARD/GAMEPAD/TOUCH)
## ou de famille de manette : les textes d'aide se remettent à jour.
signal device_changed(device: int)

const SLOT_COUNT: int = 2

var _slots: Array = [[], []]

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
	set_solo()


## Appareil de départ : tactile sur téléphone, manette si une est déjà là
## (Steam Deck), clavier sinon. `--device=gamepad[:famille]|touch|keyboard` (QA).
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


## Solo : J1 = clavier (WASD+JKL ET flèches+Num) + toutes les manettes.
func set_solo() -> void:
	_slots = [[KeyboardSource.new(PackedStringArray(["p1", "p2"]))], []]
	for device: int in Input.get_connected_joypads():
		(_slots[0] as Array).append(GamepadSource.new(device))
	sources_changed.emit()


## Versus local : J1 = clavier gauche + manette 0, J2 = clavier droit + manette 1.
func set_versus() -> void:
	_slots = [[KeyboardSource.new(PackedStringArray(["p1"]))],
		[KeyboardSource.new(PackedStringArray(["p2"]))]]
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.size() >= 1:
		(_slots[0] as Array).append(GamepadSource.new(pads[0]))
	if pads.size() >= 2:
		(_slots[1] as Array).append(GamepadSource.new(pads[1]))
	sources_changed.emit()


## Remplace les sources d'un slot (IA, pad virtuel, réseau…).
func set_sources(slot: int, sources: Array) -> void:
	_slots[slot] = sources
	sources_changed.emit()


## Ajoute une source à un slot (ex. pad virtuel tactile en plus du clavier).
func add_source(slot: int, source: InputSource) -> void:
	(_slots[slot] as Array).append(source)
	sources_changed.emit()


func sources(slot: int) -> Array:
	return _slots[slot]


## Masque d'entrée (directions absolues) du slot à cet instant.
func sample(slot: int) -> int:
	var mask: int = 0
	for source: Variant in _slots[slot]:
		mask |= (source as InputSource).sample()
	return mask


func _input(event: InputEvent) -> void:
	var d: int = InputDevice.classify(event)
	if d != InputDevice.NONE:
		_set_device(d, InputDevice.family_of(Input.get_joy_name(event.device))
			if d == InputDevice.GAMEPAD else pad_family)
	for slot: Array in _slots:
		for source: Variant in slot:
			(source as InputSource).on_event(event)


func _on_joy_connection_changed(joy: int, connected: bool) -> void:
	# Web : une manette ne se déclare qu'à son premier appui → elle sert déjà.
	if connected:
		_set_device(InputDevice.GAMEPAD, InputDevice.family_of(Input.get_joy_name(joy)))
	# Une manette branchée en cours de route rejoint J1 en solo.
	if (_slots[1] as Array).is_empty():
		set_solo()
