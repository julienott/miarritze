class_name Prompts
extends RefCounted
## Indications « appuie sur … » adaptées au dernier appareil utilisé (InputHub.device) : clavier,
## manette (Xbox, PlayStation, Nintendo, Steam Deck, générique) ou tactile. Sur iPhone, jamais de
## touche clavier. Hérité de l'ancien jeu, réduit aux menus : à remplacer par un équivalent Blackout.
##
## Jetons reconnus dans les textes : {ok} {back} {pause} (menus), {move} (se déplacer), {nav}
## (naviguer dans un menu), {left} {right} {up} {down} (directions).
##
## Mise à jour à la volée : `Prompts.bind(label, func() -> String: …)`.

const KEYBOARD: String = "keyboard"
const GAMEPAD: String = "gamepad"
const TOUCH: String = "touch"

## Manettes : libellé imprimé sur la manette, par famille.
const PAD_LABELS: Dictionary = {
	"generic": {"ok": "A", "back": "B", "pause": "START", "move": "STICK", "nav": "STICK"},
	"xbox": {"ok": "A", "back": "B", "pause": "MENU", "move": "STICK", "nav": "STICK"},
	"steamdeck": {"ok": "A", "back": "B", "pause": "MENU", "move": "STICK", "nav": "STICK"},
	"playstation": {"ok": "CROIX", "back": "ROND", "pause": "OPTIONS", "move": "STICK", "nav": "STICK"},
	"nintendo": {"ok": "B", "back": "A", "pause": "+", "move": "STICK", "nav": "STICK"},
}

const TOUCH_LABELS: Dictionary = {"ok": "TOUCHE", "back": "RETOUR", "pause": "PAUSE", "move": "POUCE GAUCHE",
	"nav": "DOIGT"}

## Clavier : touches fixes des menus.
const KEY_LABELS: Dictionary = {"ok": "ENTRÉE", "back": "ÉCHAP", "pause": "ÉCHAP", "move": "FLÈCHES",
	"nav": "FLÈCHES"}

## Directions (flèches, stick ou pouce).
const ARROWS: Dictionary = {"left": "←", "right": "→", "up": "↑", "down": "↓"}


## Genre d'indication à donner : KEYBOARD, GAMEPAD ou TOUCH.
static func kind() -> String:
	match InputHub.device:
		InputDevice.GAMEPAD:
			return GAMEPAD
		InputDevice.TOUCH:
			return TOUCH
	return KEYBOARD


## Libellé du bouton/de la touche d'une action logique pour l'appareil courant.
## Actions : ok, back, pause, move, nav, left, right, up, down.
static func key(action: String) -> String:
	if action in ARROWS:
		return str(ARROWS[action])
	match kind():
		GAMEPAD:
			var labels: Dictionary = PAD_LABELS.get(InputHub.pad_family, PAD_LABELS["generic"])
			return str(labels.get(action, "?"))
		TOUCH:
			return str(TOUCH_LABELS.get(action, "?"))
	return str(KEY_LABELS.get(action, "?"))


## Remplace les jetons {ok}, {back}… par les boutons de l'appareil courant.
static func fmt(text: String) -> String:
	if not text.contains("{"):
		return text
	for action: String in ["ok", "back", "pause", "move", "nav", "left", "right", "up", "down"]:
		text = text.replace("{%s}" % action, key(action))
	return text


## Choisit le texte selon l'appareil : clés KEYBOARD, GAMEPAD, TOUCH (TOUCH absent : rien au
## doigt), puis fmt().
static func pick(variants: Dictionary) -> String:
	var k: String = kind()
	if not variants.has(k) and k == TOUCH:
		return ""
	return fmt(str(variants.get(k, variants.get(KEYBOARD, ""))))


## Tient le texte d'un Label/Button à jour : `render` est rappelé à chaque
## changement d'appareil (et de réglage). Rien à débrancher : le
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
