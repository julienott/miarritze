extends Node
## QuitCombo — quitter le jeu à la manette : Select (ou Home) + Start tenus.
##
## Le jeu n'a pas de bouton « Quitter » (le web n'en a pas besoin, le Deck a
## son bouton STEAM). Sur Recalbox, c'est la convention « Hotkey + Start »
## qui ramène au menu des jeux : on la reproduit ici, tenue un instant pour
## ne jamais quitter par accident pendant un combat.
## Actif seulement dans l'export Recalbox (fonctionnalité `recalbox`) ou avec
## l'argument `--quit-combo` (tests).

## Durée de maintien avant de quitter (secondes).
const HOLD_S: float = 1.0
const HOTKEYS: Array[JoyButton] = [JOY_BUTTON_BACK, JOY_BUTTON_GUIDE]

var _held_s: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(OS.has_feature("recalbox") or OS.get_cmdline_user_args().has("--quit-combo"))


func _process(delta: float) -> void:
	if _combo_pressed():
		_held_s += delta
		if _held_s >= HOLD_S:
			set_process(false)
			get_tree().quit()
	else:
		_held_s = 0.0


func _combo_pressed() -> bool:
	for device: int in Input.get_connected_joypads():
		if not Input.is_joy_button_pressed(device, JOY_BUTTON_START):
			continue
		for button: JoyButton in HOTKEYS:
			if Input.is_joy_button_pressed(device, button):
				return true
	return false
