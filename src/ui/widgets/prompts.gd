class_name Prompts
extends RefCounted
## Indications « appuie sur … » adaptées au dernier appareil utilisé
## (InputHub.device) : clavier (touches réelles de l'InputMap, remappages
## compris), manette (Xbox, PlayStation, Nintendo, Steam Deck, générique) ou
## tactile (manette virtuelle ou gestes). Sur iPhone, jamais de touche clavier.
##
## Jetons reconnus dans les textes : {punch} {kick} {special} {guard} (boutons
## de combat), {ok} {back} {pause} (menus), {move} (se déplacer), {nav}
## (naviguer dans un menu), {left} {right} {up} {down} (directions).
##
## Mise à jour à la volée : `Prompts.bind(label, func() -> String: …)`.

const KEYBOARD: String = "keyboard"
const GAMEPAD: String = "gamepad"
const TOUCH: String = "touch"
const GESTURES: String = "gestures"

## Nom des boutons de combat (affiché avec le bouton de l'appareil).
const BUTTON_NAMES: Dictionary = {"punch": "POING", "kick": "PIED", "special": "SPÉCIAL", "guard": "GARDE"}

## Manettes : placement SDL (Godot) → libellé imprimé sur la manette.
## POING = bouton de gauche, PIED = bas, SPÉCIAL = droite, GARDE = gâchette droite.
const PAD_LABELS: Dictionary = {
	"generic": {"punch": "X", "kick": "A", "special": "B", "guard": "RB", "ok": "A", "back": "B",
		"pause": "START", "move": "STICK", "nav": "STICK"},
	"xbox": {"punch": "X", "kick": "A", "special": "B", "guard": "RB", "ok": "A", "back": "B",
		"pause": "MENU", "move": "STICK", "nav": "STICK"},
	"steamdeck": {"punch": "X", "kick": "A", "special": "B", "guard": "R1", "ok": "A", "back": "B",
		"pause": "MENU", "move": "STICK", "nav": "STICK"},
	"playstation": {"punch": "CARRÉ", "kick": "CROIX", "special": "ROND", "guard": "R1", "ok": "CROIX",
		"back": "ROND", "pause": "OPTIONS", "move": "STICK", "nav": "STICK"},
	"nintendo": {"punch": "Y", "kick": "B", "special": "A", "guard": "R", "ok": "B", "back": "A",
		"pause": "+", "move": "STICK", "nav": "STICK"},
}

## Manette virtuelle de l'iPhone : couleurs des boutons (TouchControls).
const TOUCH_LABELS: Dictionary = {"punch": "ROUGE", "kick": "VERT", "special": "JAUNE", "guard": "BLEU",
	"ok": "TOUCHE", "back": "RETOUR", "pause": "PAUSE", "move": "POUCE GAUCHE", "nav": "DOIGT"}

## Mode « Gestes » (TouchControls, §7.4).
const GESTURE_LABELS: Dictionary = {"punch": "TAPE À DROITE", "kick": "GLISSE VERS L'AVANT",
	"special": "GLISSE VERS L'ARRIÈRE", "guard": "APPUI LONG À DROITE", "ok": "TOUCHE", "back": "RETOUR",
	"pause": "PAUSE", "move": "POUCE GAUCHE", "nav": "DOIGT"}

## Clavier : action de l'InputMap lue pour chaque bouton de combat (J1).
const KEY_ACTIONS: Dictionary = {"punch": "p1_punch", "kick": "p1_kick", "special": "p1_special", "guard": "p1_guard"}

## Godot web ne sait pas traduire une touche physique selon la disposition :
## en français, on suppose un AZERTY (W→Z, A→Q…), comme les anciens textes.
const AZERTY: Dictionary = {KEY_W: KEY_Z, KEY_Z: KEY_W, KEY_A: KEY_Q, KEY_Q: KEY_A, KEY_SEMICOLON: KEY_M,
	KEY_M: KEY_COMMA}

const KEY_PRETTY: Dictionary = {"Space": "ESPACE", "Enter": "ENTRÉE", "Escape": "ÉCHAP", "Up": "↑", "Down": "↓",
	"Left": "←", "Right": "→", "Comma": ",", "Period": ".", "Slash": "/", "Semicolon": ";", "Shift": "MAJ",
	"Ctrl": "CTRL", "Alt": "ALT", "Tab": "TAB", "Backspace": "EFFACER"}

## Directions de la liste des coups pour le mode Gestes (pouce gauche).
const GESTURE_DIRS: Dictionary = {"Avant": "pouce vers l'avant", "Arrière": "pouce vers l'arrière",
	"Bas": "pouce en bas", "Haut": "pouce en haut", "Arrière-Bas": "pouce en bas vers l'arrière",
	"Avant-Bas": "pouce en bas vers l'avant"}


## Genre d'indication à donner : KEYBOARD, GAMEPAD, TOUCH ou GESTURES.
static func kind() -> String:
	match InputHub.device:
		InputDevice.GAMEPAD:
			return GAMEPAD
		InputDevice.TOUCH:
			return GESTURES if Settings.touch_mode == "gestures" else TOUCH
	return KEYBOARD


## Directions (stick / pouce) hors clavier.
const ARROWS: Dictionary = {"left": "←", "right": "→", "up": "↑", "down": "↓"}


## Libellé du bouton/de la touche d'une action logique pour l'appareil courant.
## Actions : punch, kick, special, guard, ok, back, pause, move, nav,
## left, right, up, down.
static func key(action: String) -> String:
	if action in ARROWS and kind() != KEYBOARD:
		return str(ARROWS[action])
	match kind():
		GAMEPAD:
			var labels: Dictionary = PAD_LABELS.get(InputHub.pad_family, PAD_LABELS["generic"])
			return str(labels.get(action, "?"))
		TOUCH:
			return str(TOUCH_LABELS.get(action, "?"))
		GESTURES:
			return str(GESTURE_LABELS.get(action, "?"))
	match action:
		"ok":
			return "ENTRÉE"
		"back", "pause":
			return "ÉCHAP"
		"nav":
			return "FLÈCHES"
		"left", "right", "up", "down":
			return key_name("p1_" + action)
		"move":
			var keys: PackedStringArray = []
			for a: String in ["p1_up", "p1_left", "p1_down", "p1_right"]:
				keys.append(key_name(a))
			var joined: String = "".join(keys)
			return joined if joined.length() == 4 else "/".join(keys)
	return key_name(str(KEY_ACTIONS.get(action, action)))


## Nom lisible de la première touche clavier d'une action de l'InputMap.
static func key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev: InputEvent in InputMap.action_get_events(action):
		if not ev is InputEventKey:
			continue
		var k: InputEventKey = ev
		var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		var shown: Key = code
		# Web : la traduction physique → disposition n'existe pas (erreur
		# « Not supported ») ; on garde la touche physique, puis l'AZERTY.
		if k.physical_keycode != KEY_NONE and not OS.has_feature("web") \
				and DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_keycode_from_physical(code)
			if shown == KEY_NONE:
				shown = code
			if OS.has_feature("web") and shown == code and OS.get_locale_language() == "fr":
				shown = AZERTY.get(code, code)
		var text: String = OS.get_keycode_string(shown)
		return str(KEY_PRETTY.get(text, text.to_upper()))
	return "?"


## Remplace les jetons {punch}, {ok}… par les boutons de l'appareil courant.
static func fmt(text: String) -> String:
	if not text.contains("{"):
		return text
	for action: String in ["punch", "kick", "special", "guard", "ok", "back", "pause", "move", "nav",
			"left", "right", "up", "down"]:
		text = text.replace("{%s}" % action, key(action))
	return text


## Choisit le texte selon l'appareil : clés KEYBOARD, GAMEPAD, TOUCH, GESTURES
## (GESTURES retombe sur TOUCH, TOUCH sur KEYBOARD si absents), puis fmt().
static func pick(variants: Dictionary) -> String:
	var k: String = kind()
	if not variants.has(k) and k == GESTURES:
		k = TOUCH
	if not variants.has(k) and k == TOUCH:
		return ""
	return fmt(str(variants.get(k, variants.get(KEYBOARD, ""))))


## « PIED (A) » : nom du bouton de combat + bouton de l'appareil.
static func button(action: String) -> String:
	if kind() == GESTURES:
		return key(action).to_lower()
	return "%s (%s)" % [BUTTON_NAMES.get(action, action), key(action)]


## Entrée d'un coup (liste des coups) : direction(s) en mots + bouton.
## `dirs` : "", "Avant", "Bas", "Arrière-Bas"… ; `action` : punch/kick/special/guard.
static func move_input(dirs: String, action: String, note: String = "") -> String:
	var suffix: String = (" " + note) if note != "" else ""
	if kind() == GESTURES:
		var g: String = _gesture_move(dirs, action)
		return (g + suffix) if g != "" else "(manette virtuelle seulement)"
	return ("%s + %s" % [dirs, button(action)] if dirs != "" else button(action)) + suffix


## Mode Gestes : chaque geste produit une entrée fixe (TouchControls._gesture_release).
static func _gesture_move(dirs: String, action: String) -> String:
	match action:
		"punch":
			return key("punch").to_lower() if dirs == "" \
				else "%s + %s" % [GESTURE_DIRS.get(dirs, dirs), key("punch").to_lower()]
		"guard":
			return key("guard").to_lower() if dirs == "" \
				else "%s + %s" % [GESTURE_DIRS.get(dirs, dirs), key("guard").to_lower()]
		"kick":
			return "glisse vers l'avant (à droite)" if dirs == "Avant" else ""
		"special":
			return str({"": "glisse vers l'arrière (à droite)", "Avant": "double tape à droite",
				"Bas": "glisse vers le bas (à droite)", "Haut": "glisse vers le haut (à droite)"}.get(dirs, ""))
	return ""


## Manip « à l'ancienne » : « D,DF,F+P » → « Bas, Bas-Av, Av + X » (bouton de
## l'appareil). Vide en mode Gestes (pas de manip possible au doigt).
static func classic(code: String) -> String:
	if code == "" or kind() == GESTURES:
		return ""
	var names: Dictionary = {"D": "Bas", "DF": "Bas-Av", "F": "Av", "B": "Arr", "DB": "Bas-Arr",
		"U": "Haut", "UF": "Haut-Av", "UB": "Haut-Arr"}
	var buttons: Dictionary = {"P": "punch", "K": "kick", "S": "special", "G": "guard"}
	var parts: PackedStringArray = code.split("+")
	var dirs: PackedStringArray = []
	for d: String in parts[0].split(","):
		dirs.append(str(names.get(d, d)))
	var b: String = parts[1] if parts.size() > 1 else "P"
	return ", ".join(dirs) + " + " + key(str(buttons.get(b, "punch")))


## Tient le texte d'un Label/Button à jour : `render` est rappelé à chaque
## changement d'appareil (et de réglage tactile). Rien à débrancher : le
## relais est un enfant de `target`, libéré avec lui.
static func bind(target: Control, render: Callable) -> void:
	var binder: Binder = Binder.new()
	binder.render = render
	target.add_child(binder)


## Rappelle `apply` maintenant puis à chaque changement d'appareil, tant que
## `target` existe (visibilité d'un bouton réservé à la manette, etc.).
static func on_change(target: Node, apply: Callable) -> void:
	var binder: Binder = Binder.new()
	binder.apply = apply
	target.add_child(binder)


## Raccourci : texte à jetons tenu à jour.
static func bind_text(target: Control, template: String) -> void:
	bind(target, func() -> String: return fmt(template))


class Binder:
	extends Node
	var render: Callable
	var apply: Callable

	func _ready() -> void:
		InputHub.device_changed.connect(_refresh)
		Settings.changed.connect(_refresh)
		_refresh()

	func _refresh(_d: int = 0) -> void:
		if render.is_valid():
			get_parent().set(&"text", render.call())
		if apply.is_valid():
			apply.call()
