extends Node
## Settings — réglages de l'appareil (pas du profil) : volumes, vibrations, détection du tactile.
## Persistés dans user://settings.json. Hérité de l'ancien jeu, réduit à ce que Gordeka lit
## (écran Réglages, GkFrisson, InputHub) : à remplacer par un équivalent Gordeka.

signal changed

const SAVE_PATH: String = "user://settings.json"

## "auto" : tactile détecté selon l'appareil ; "on" / "off" forcés.
var pad_visible: String = "auto"
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var vibrations: bool = true


func _ready() -> void:
	_load()


## L'appareil est-il tactile (téléphone, tablette) ?
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


func save() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"pad_visible": pad_visible, "music_volume": music_volume,
		"sfx_volume": sfx_volume, "vibrations": vibrations}))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		return
	var d: Dictionary = data
	pad_visible = str(d.get("pad_visible", pad_visible))
	music_volume = float(d.get("music_volume", music_volume))
	sfx_volume = float(d.get("sfx_volume", sfx_volume))
	vibrations = bool(d.get("vibrations", vibrations))
