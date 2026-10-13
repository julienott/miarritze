extends Node
## Settings — réglages de l'appareil (pas du profil) : contrôles tactiles,
## sons, difficulté par défaut, touches. Persistés dans user://settings.json.

signal changed

const SAVE_PATH: String = "user://settings.json"
const PAD_MODES: PackedStringArray = ["pad", "gestures"]
const PAD_SIZES: PackedStringArray = ["S", "M", "L"]
## Facteurs ≥ 1 : un bouton fait toujours au moins 64 pt (§7.3).
const PAD_SIZE_FACTORS: PackedFloat32Array = [1.0, 1.15, 1.3]

var touch_mode: String = "pad"        # "pad" (manette virtuelle) | "gestures"
var pad_size: int = 1                 # index dans PAD_SIZES
var pad_opacity: float = 0.55
## "auto" : pad affiché sur écran tactile ; "on" / "off" forcés.
var pad_visible: String = "auto"
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var voice_volume: float = 1.0
## Version de settings.json : bumpé quand on change les valeurs par défaut.
## Les sauvegardes plus anciennes se font restaurer les volumes au premier
## chargement (fichier d'un ancien test qui pouvait les avoir à 0).
const SETTINGS_VERSION: int = 2
var _version: int = 0
var default_difficulty: int = 0
var express_fights: bool = false      # désactive les finishs en ligne
var colorblind: bool = false          # HUD lisible pour les daltoniens
var vibrations: bool = true
## Remappages clavier : action -> [physical_keycode, …]
var key_overrides: Dictionary = {}


func _ready() -> void:
	_load()
	if _version < SETTINGS_VERSION:
		music_volume = maxf(music_volume, 0.5)
		sfx_volume = maxf(sfx_volume, 0.6)
		voice_volume = maxf(voice_volume, 0.6)
		_version = SETTINGS_VERSION
		save()
	_apply_keys()


func pad_scale() -> float:
	return PAD_SIZE_FACTORS[clampi(pad_size, 0, 2)]


## Le pad tactile doit-il s'afficher ?
func touch_enabled() -> bool:
	if pad_visible == "on":
		return true
	if pad_visible == "off":
		return false
	if OS.get_cmdline_user_args().has("--touch"):
		return true
	return DisplayServer.is_touchscreen_available() and (OS.has_feature("web_ios")
		or OS.has_feature("web_android") or OS.has_feature("mobile") or _web_touch_device())


func _web_touch_device() -> bool:
	if not OS.has_feature("web"):
		return false
	var coarse: Variant = JavaScriptBridge.eval(
		"window.matchMedia('(pointer: coarse)').matches || location.search.indexOf('touch=1') >= 0", true)
	return bool(coarse)


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	save()
	changed.emit()


func remap(action: String, keycodes: Array) -> void:
	key_overrides[action] = keycodes
	_apply_keys()
	save()


func reset_keys() -> void:
	key_overrides.clear()
	InputMap.load_from_project_settings()
	save()


func _apply_keys() -> void:
	for action: Variant in key_overrides:
		var name: String = str(action)
		if not InputMap.has_action(name):
			continue
		for ev: InputEvent in InputMap.action_get_events(name):
			if ev is InputEventKey:
				InputMap.action_erase_event(name, ev)
		for code: Variant in key_overrides[action]:
			var k: InputEventKey = InputEventKey.new()
			k.physical_keycode = int(code) as Key
			InputMap.action_add_event(name, k)


func save() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"touch_mode": touch_mode, "pad_size": pad_size, "pad_opacity": pad_opacity,
		"pad_visible": pad_visible, "music_volume": music_volume, "sfx_volume": sfx_volume,
		"voice_volume": voice_volume, "default_difficulty": default_difficulty,
		"express_fights": express_fights, "key_overrides": key_overrides,
		"colorblind": colorblind, "vibrations": vibrations,
		"version": _version,
	}))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		return
	for key: Variant in data:
		if str(key) in ["touch_mode", "pad_visible"]:
			set(str(key), str(data[key]))
		elif str(key) in ["pad_size", "default_difficulty"]:
			set(str(key), int(data[key]))
		elif str(key) in ["pad_opacity", "music_volume", "sfx_volume", "voice_volume"]:
			set(str(key), float(data[key]))
		elif str(key) in ["express_fights", "colorblind", "vibrations"]:
			set(str(key), bool(data[key]))
		elif str(key) == "key_overrides" and data[key] is Dictionary:
			key_overrides = data[key]
		elif str(key) == "version":
			_version = int(data[key])
