extends Node
## InputHub — assigne des sources d'entrée aux slots de joueurs et
## échantillonne UNE fois par tick de sim (SPEC-BORROKA §7.1).
##
## Un slot combine plusieurs sources (OU binaire) : clavier + manette, etc.
## Le combat ne lit jamais d'InputEvent : il appelle `sample(slot)`.

signal sources_changed

const SLOT_COUNT: int = 2

var _slots: Array = [[], []]


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	set_solo()


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
	for slot: Array in _slots:
		for source: Variant in slot:
			(source as InputSource).on_event(event)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	# Une manette branchée en cours de route rejoint J1 en solo.
	if (_slots[1] as Array).is_empty():
		set_solo()
