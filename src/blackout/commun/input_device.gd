class_name InputDevice
extends RefCounted
## D'où vient une entrée ? (clavier/souris, manette, écran tactile) et
## petites aides de menu liées aux manettes. Hérité de l'ancien jeu : les
## écrans passent par ici au lieu de tester eux-mêmes les classes d'événements.

const NONE: int = -1
const KEYBOARD: int = 0
const GAMEPAD: int = 1
const TOUCH: int = 2

## Familles de manettes (libellés des boutons, voir Prompts).
const FAMILY_GENERIC: String = "generic"
const FAMILY_XBOX: String = "xbox"
const FAMILY_PLAYSTATION: String = "playstation"
const FAMILY_NINTENDO: String = "nintendo"
const FAMILY_STEAMDECK: String = "steamdeck"

## Un stick qui dérive un peu ne doit pas faire basculer les indications.
const AXIS_THRESHOLD: float = 0.5


## Appareil d'origine d'un événement « volontaire » (appui, stick franchement
## poussé), ou NONE (relâchement, mouvement de souris, événement émulé…).
static func classify(event: InputEvent) -> int:
	if event is InputEventKey:
		return KEYBOARD if event.is_pressed() and not event.is_echo() else NONE
	if event is InputEventJoypadButton:
		return GAMEPAD if event.is_pressed() else NONE
	if event is InputEventJoypadMotion:
		return GAMEPAD if absf((event as InputEventJoypadMotion).axis_value) > AXIS_THRESHOLD else NONE
	if event is InputEventScreenTouch:
		if not event.is_pressed():
			return NONE
		# Toucher émulé depuis un clic de souris (emulate_touch_from_mouse).
		return KEYBOARD if event.device == InputEvent.DEVICE_ID_EMULATION else TOUCH
	if event is InputEventMouseButton:
		# Clic émulé depuis un toucher (iPhone) : c'est le toucher qui compte.
		if not event.is_pressed() or event.device == InputEvent.DEVICE_ID_EMULATION:
			return NONE
		return KEYBOARD
	return NONE


## Famille d'une manette d'après son nom (Godot/SDL ou navigateur, qui
## glisse souvent l'identifiant USB du fabricant : 054c Sony, 057e Nintendo…).
static func family_of(joy_name: String) -> String:
	var n: String = joy_name.to_lower()
	if n.contains("steam deck"):
		return FAMILY_STEAMDECK
	for word: String in ["054c", "playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5", "sony",
			"wireless controller"]:
		if n.contains(word):
			return FAMILY_PLAYSTATION
	for word: String in ["057e", "nintendo", "switch", "pro controller", "joy-con", "joycon"]:
		if n.contains(word):
			return FAMILY_NINTENDO
	for word: String in ["xbox", "xinput", "microsoft", "045e", "x-box", "steam"]:
		if n.contains(word):
			return FAMILY_XBOX
	return FAMILY_GENERIC


## Godot ne met AUCUN bouton de manette dans ui_accept / ui_cancel par
## défaut (seulement la croix et le stick dans ui_up…) : A et B ne faisaient
## donc rien dans les menus. On ajoute A + START (valider) et B (retour).
## À rappeler après InputMap.load_from_project_settings() (réinitialisation).
static func install_menu_actions() -> void:
	_add_pad_button(&"ui_accept", JOY_BUTTON_A)
	_add_pad_button(&"ui_accept", JOY_BUTTON_START)
	_add_pad_button(&"ui_cancel", JOY_BUTTON_B)


static func _add_pad_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return
	var jb: InputEventJoypadButton = InputEventJoypadButton.new()
	jb.device = -1
	jb.button_index = button
	InputMap.action_add_event(action, jb)
