class_name TouchControls
extends Control
## Manette virtuelle iPhone (SPEC §7.3) et mode « Gestes » (§7.4).
##
## Multitouch : chaque toucher est suivi par son `index`, ARBITRAIRE sur iOS
## (jamais supposé à 0). Une table index → contrôle est attribuée à l'appui
## et libérée au relâcher. Le glisser d'un bouton à l'autre est permis.
## L'état est lu par VirtualPadSource / GestureSource (InputFrame identique).

signal super_requested

const C_PUNCH: Color = Color8(206, 52, 52)
const C_KICK: Color = Color8(52, 128, 72)
const C_SPECIAL: Color = Color8(244, 198, 62)
const C_GUARD: Color = Color8(84, 112, 168)
const C_OUTLINE: Color = Color8(58, 38, 52)
const C_LINEN: Color = Color8(247, 241, 227)

## Rayon du joystick en points (×échelle), zone morte, hystérésis (°).
const STICK_RADIUS_PT: float = 56.0
const DEADZONE: float = 0.25
const HYSTERESIS_DEG: float = 10.0
const BUTTON_PT: float = 64.0
const SAFE_MARGIN_PT: float = 44.0
## Gestes : seuil de swipe (px logiques) et durées (ms).
const SWIPE_PX: float = 28.0
const SWIPE_MS: int = 220
const LONG_PRESS_MS: int = 180
const DOUBLE_TAP_MS: int = 260

var mode: String = "pad"
## Orientation du combattant contrôlé (1 = regarde à droite), fournie par la scène.
var facing_getter: Callable = func() -> int: return 1
## La jauge est-elle pleine ? (affiche le bouton MARÉE)
var meter_full_getter: Callable = func() -> bool: return false
## Rectangles écran des combattants : un bouton qui en recouvre un s'efface
## (le combat reste visible quand un perso passe sous le losange).
var fighter_rects_getter: Callable = func() -> Array: return []
## Opacité d'un bouton posé sur un combattant (fraction de l'opacité normale).
const OVER_FIGHTER_ALPHA: float = 0.35
var _over_mask: int = 0

var _touches: Dictionary = {}      # index -> {kind, start, pos, t0, button}
var _stick_center: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _stick_active: bool = false
var _dir: int = 5                  # pavé numérique ABSOLU (6 = droite)
var _held: int = 0                 # boutons tenus (bits InputSource)
var _latched: int = 0              # appuis brefs non encore lus
var _pulse: Dictionary = {}        # bit -> frames restantes (gestes)
var _buttons: Dictionary = {}      # nom -> {center, radius, bit, color, label}
var _last_tap_ms: int = -1000
var _scale_pt: float = 0.55        # px logiques par point
var _font: Font
var _safe: Vector4 = Vector4.ZERO
var _icons: Dictionary = {}
var _tap_releases: Array[int] = []    # gestes : instants des derniers taps courts


## Opacité minimale du cercle du joystick au repos (toujours repérable).
const STICK_HINT_MIN_ALPHA: float = 0.5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode = Settings.touch_mode
	_font = load("res://assets/fonts/press_start_2p.ttf")
	get_viewport().size_changed.connect(_layout)
	_layout()


## Mise en page : zones sûres, taille des boutons en points physiques.
## Géométrie forcée (tests) : taille logique et hauteur d'écran en points.
var forced_view: Vector2 = Vector2.ZERO
var forced_height_pt: float = 0.0


func _layout() -> void:
	var vp: Vector2 = forced_view if forced_view != Vector2.ZERO else get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	var dpr: float = maxf(DisplayServer.screen_get_scale(), 1.0)
	var height_pt: float = maxf(win.y / dpr, 200.0)
	if forced_height_pt > 0.0:
		height_pt = forced_height_pt
		win = Vector2(0, 0)
	_scale_pt = vp.y / height_pt
	# Rien d'essentiel dans les 44 pt du bord, ni sous l'encoche ou la barre d'accueil.
	var edge: float = SAFE_MARGIN_PT * _scale_pt
	var m: Vector4 = Vector4(edge, edge, edge, edge)
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if safe.size.x > 0 and win.x > 0 and safe.size.x < int(win.x):
		var k: float = vp.x / win.x
		m = Vector4(maxf(edge, safe.position.x * k), maxf(edge, safe.position.y * k),
			maxf(edge, (win.x - safe.end.x) * k), maxf(edge, (win.y - safe.end.y) * k))
	_safe = m
	var r: float = BUTTON_PT * _scale_pt * Settings.pad_scale() * 0.5
	var gap: float = r * 2.05
	# Losange calé en bas à droite, à l'intérieur des marges sûres.
	var c: Vector2 = Vector2(vp.x - m.z - gap - r * 1.15, vp.y - m.w - gap - r)
	_buttons = {
		"guard": {"center": c + Vector2(0, -gap), "radius": r, "bit": InputSource.GUARD, "color": C_GUARD, "icon": "shield"},
		"punch": {"center": c + Vector2(-gap, 0), "radius": r, "bit": InputSource.PUNCH, "color": C_PUNCH, "icon": "punch"},
		"special": {"center": c + Vector2(gap, 0), "radius": r * 1.15, "bit": InputSource.SPECIAL, "color": C_SPECIAL, "icon": "lauburu"},
		"kick": {"center": c + Vector2(0, gap), "radius": r, "bit": InputSource.KICK, "color": C_KICK, "icon": "espadrille"},
		"maree": {"center": c + Vector2(0, -gap * 2.0), "radius": r, "bit": InputSource.SPECIAL | InputSource.GUARD,
			"color": Color8(196, 232, 230), "icon": "star"},
	}
	_icons.clear()
	for name: String in _buttons:
		var path: String = "res://assets/ui/icon_%s.png" % str(_buttons[name]["icon"])
		if ResourceLoader.exists(path):
			_icons[name] = load(path)


func stick_radius() -> float:
	return STICK_RADIUS_PT * _scale_pt * Settings.pad_scale()


# ------------------------------------------------------------------ entrées

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		var pos: Vector2 = _to_local(t.position)
		# Bandeau du HUD (pause, barres) : laissé aux boutons de l'interface.
		if t.pressed and pos.y < 34.0 and not _touches.has(t.index):
			return
		if t.pressed:
			_on_press(t.index, pos)
		else:
			_on_release(t.index, pos)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		_on_drag(d.index, _to_local(d.position))
		get_viewport().set_input_as_handled()


## Les événements tactiles arrivent déjà en coordonnées logiques du viewport
## (stretch « viewport ») ; le Control couvre tout l'écran depuis (0, 0).
func _to_local(screen_pos: Vector2) -> Vector2:
	return screen_pos


func _on_press(index: int, pos: Vector2) -> void:
	var now: int = Time.get_ticks_msec()
	if mode == "gestures":
		_gesture_press(index, pos, now)
		return
	var btn: String = _button_at(pos)
	if btn != "":
		_touches[index] = {"kind": "button", "button": btn, "pos": pos}
		_press_button(btn)
	elif pos.x < size.x * 0.5 and not _stick_active:
		_touches[index] = {"kind": "stick", "pos": pos}
		_stick_center = pos
		_stick_pos = pos
		_stick_active = true
		_update_dir()
	queue_redraw()


func _on_drag(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	t["pos"] = pos
	if mode == "gestures":
		_gesture_drag(index, pos)
		return
	if t["kind"] == "stick":
		_stick_pos = pos
		_update_dir()
	elif t["kind"] == "button":
		# Glisser d'un bouton à l'autre sans lever le doigt (roll).
		var btn: String = _button_at(pos)
		if btn != "" and btn != t["button"]:
			var old: String = str(t["button"])
			t["button"] = btn
			_release_button(old)
			_press_button(btn)
	queue_redraw()


func _on_release(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	if mode == "gestures":
		_gesture_release(index, pos)
	elif t["kind"] == "stick":
		_stick_active = false
		_dir = 5
	elif t["kind"] == "button":
		_touches.erase(index)
		_release_button(str(t["button"]))
	_touches.erase(index)
	queue_redraw()


func _press_button(btn: String) -> void:
	var bit: int = int(_buttons[btn]["bit"])
	if btn == "maree":
		if not meter_full_getter.call():
			return
		super_requested.emit()
		_latched |= bit
		return
	_held |= bit
	_latched |= bit


func _release_button(btn: String) -> void:
	if btn == "maree":
		return
	# Un autre doigt peut encore tenir le même bouton : on le garde enfoncé.
	for t: Variant in _touches.values():
		var td: Dictionary = t
		if td.get("kind") == "button" and td.get("button") == btn:
			return
	_held &= ~int(_buttons[btn]["bit"])


func _button_at(pos: Vector2) -> String:
	var best: String = ""
	var best_d: float = INF
	for name: String in _buttons:
		if name == "maree" and not meter_full_getter.call():
			continue
		var b: Dictionary = _buttons[name]
		var d: float = pos.distance_to(b["center"])
		# Cibles généreuses : 15 % de marge autour du bouton.
		if d <= float(b["radius"]) * 1.15 and d < best_d:
			best = name
			best_d = d
	return best


## 8 directions numériques, zone morte 25 %, hystérésis angulaire de 10°.
func _update_dir() -> void:
	var v: Vector2 = _stick_pos - _stick_center
	var r: float = stick_radius()
	if v.length() > r:
		_stick_center = _stick_pos - v.normalized() * r   # le stick suit le pouce
		v = _stick_pos - _stick_center
	if v.length() < r * DEADZONE:
		_dir = 5
		return
	var angle: float = rad_to_deg(atan2(-v.y, v.x))
	var current_sector: int = _sector_of(_dir)
	if current_sector >= 0:
		var center_angle: float = current_sector * 45.0
		var diff: float = absf(wrapf(angle - center_angle, -180.0, 180.0))
		if diff <= 22.5 + HYSTERESIS_DEG:
			return
	var sector: int = int(roundf(angle / 45.0)) % 8
	if sector < 0:
		sector += 8
	_dir = [6, 9, 8, 7, 4, 1, 2, 3][sector]


static func _sector_of(dir: int) -> int:
	return {6: 0, 9: 1, 8: 2, 7: 3, 4: 4, 1: 5, 2: 6, 3: 7}.get(dir, -1)


# ------------------------------------------------------------------ gestes (§7.4)

func _gesture_press(index: int, pos: Vector2, now: int) -> void:
	var left: bool = pos.x < size.x * 0.5
	_touches[index] = {"kind": "left" if left else "right", "start": pos, "pos": pos, "t0": now,
		"guard": false, "swiped": false}
	if left:
		_stick_center = pos
		_stick_pos = pos
		_stick_active = true


func _gesture_drag(index: int, pos: Vector2) -> void:
	var t: Dictionary = _touches[index]
	if t["kind"] == "left":
		_stick_pos = pos
		var v: Vector2 = pos - (t["start"] as Vector2)
		_dir = 5
		var h: int = 0
		if absf(v.x) > SWIPE_PX * 0.5:
			h = 1 if v.x > 0 else -1
		var vert: int = 0
		if Time.get_ticks_msec() - int(t["t0"]) < SWIPE_MS * 2 and absf(v.y) > SWIPE_PX:
			vert = -1 if v.y > 0 else 1
		_dir = 5 + h + vert * 3


func _gesture_release(index: int, pos: Vector2) -> void:
	var t: Dictionary = _touches[index]
	var now: int = Time.get_ticks_msec()
	# Tap à deux doigts (deux taps courts, sans glisser, à moins de 150 ms) : super.
	var short_tap: bool = now - int(t["t0"]) < 250 and pos.distance_to(t["start"]) < SWIPE_PX
	if short_tap:
		for other: int in _tap_releases:
			if now - other < 150:
				_tap_releases.clear()
				super_requested.emit()
				_latched |= InputSource.SPECIAL | InputSource.GUARD
				_pulse.clear()
				if t["kind"] == "left":
					_stick_active = false
					_dir = 5
				return
		_tap_releases = [now]
	if t["kind"] == "left":
		_stick_active = false
		_dir = 5
		return
	# La GARDE reste tenue si un autre doigt droit la maintient.
	var other_guard: bool = false
	for k: Variant in _touches:
		if int(k) != index and bool((_touches[k] as Dictionary).get("guard", false)):
			other_guard = true
	if not other_guard:
		_held &= ~InputSource.GUARD
	var v: Vector2 = pos - (t["start"] as Vector2)
	var dt: int = now - int(t["t0"])
	var fwd: int = InputSource.RIGHT if facing_getter.call() > 0 else InputSource.LEFT
	var back: int = InputSource.LEFT if fwd == InputSource.RIGHT else InputSource.RIGHT
	if bool(t["guard"]):
		return
	if v.length() >= SWIPE_PX and dt <= SWIPE_MS:
		if absf(v.x) > absf(v.y):
			var toward: bool = (v.x > 0) == (fwd == InputSource.RIGHT)
			_pulse_bits(fwd | InputSource.KICK if toward else InputSource.SPECIAL)
		elif v.y < 0:
			_pulse_bits(InputSource.UP | InputSource.SPECIAL)
		else:
			_pulse_bits(InputSource.DOWN | InputSource.SPECIAL)
		return
	if now - _last_tap_ms < DOUBLE_TAP_MS:
		_pulse_bits(fwd | InputSource.SPECIAL)
		_last_tap_ms = -1000
		return
	_last_tap_ms = now
	_latched |= InputSource.PUNCH


func _pulse_bits(mask: int) -> void:
	for bit: int in [InputSource.UP, InputSource.DOWN, InputSource.LEFT, InputSource.RIGHT,
			InputSource.PUNCH, InputSource.KICK, InputSource.SPECIAL]:
		if mask & bit:
			_pulse[bit] = 3


func _process(_delta: float) -> void:
	_update_fade()
	if mode != "gestures":
		return
	# Appui long sur la moitié droite : GARDE tant que maintenu.
	for t: Variant in _touches.values():
		var td: Dictionary = t
		if td["kind"] == "right" and not bool(td["guard"]) \
				and Time.get_ticks_msec() - int(td["t0"]) > LONG_PRESS_MS \
				and (td["pos"] as Vector2).distance_to(td["start"]) < SWIPE_PX:
			td["guard"] = true
			_held |= InputSource.GUARD


# ------------------------------------------------------------------ lecture

## Masque de l'instant (directions absolues), appuis brefs inclus.
func read_mask() -> int:
	var mask: int = _held | _latched
	_latched = 0
	match _dir:
		1: mask |= InputSource.DOWN | InputSource.LEFT
		2: mask |= InputSource.DOWN
		3: mask |= InputSource.DOWN | InputSource.RIGHT
		4: mask |= InputSource.LEFT
		6: mask |= InputSource.RIGHT
		7: mask |= InputSource.UP | InputSource.LEFT
		8: mask |= InputSource.UP
		9: mask |= InputSource.UP | InputSource.RIGHT
	var expired: Array = []
	for bit: Variant in _pulse:
		mask |= int(bit)
		_pulse[bit] = int(_pulse[bit]) - 1
		if int(_pulse[bit]) <= 0:
			expired.append(bit)
	for bit: Variant in expired:
		_pulse.erase(bit)
	return mask


# ------------------------------------------------------------------ dessin

func _covers_fighter(b: Dictionary) -> bool:
	var c: Vector2 = b["center"]
	var r: float = float(b["radius"])
	var box: Rect2 = Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
	for rect: Variant in fighter_rects_getter.call():
		if (rect as Rect2).intersects(box):
			return true
	return false


func _update_fade() -> void:
	# Redessin seulement quand le recouvrement change (budget web).
	var mask: int = 0
	var i: int = 0
	for name: String in _buttons:
		if _covers_fighter(_buttons[name]):
			mask |= 1 << i
		i += 1
	if mask != _over_mask:
		_over_mask = mask
		queue_redraw()


func _draw() -> void:
	var alpha: float = Settings.pad_opacity
	if mode == "gestures":
		draw_line(Vector2(size.x * 0.5, size.y * 0.35), Vector2(size.x * 0.5, size.y - 4), Color(1, 1, 1, alpha * 0.25), 1.0)
		if _stick_active:
			draw_arc(_stick_center, 10, 0, TAU, 16, Color(1, 1, 1, alpha), 1.0)
		return
	var r: float = stick_radius()
	if _stick_active:
		draw_circle(_stick_center, r, Color(C_OUTLINE, alpha * 0.5))
		draw_arc(_stick_center, r, 0, TAU, 32, Color(C_LINEN, alpha), 1.0)
		var knob: Vector2 = _stick_center + (_stick_pos - _stick_center).limit_length(r)
		draw_circle(knob, r * 0.4, Color(C_LINEN, alpha))
	else:
		var hint: Vector2 = Vector2(_safe.x + r + 6.0, size.y - _safe.w - r)
		draw_arc(hint, r * 0.7, 0, TAU, 24, Color(C_LINEN, maxf(alpha, STICK_HINT_MIN_ALPHA) * 0.8), 1.5)
	for name: String in _buttons:
		var b: Dictionary = _buttons[name]
		if name == "maree" and not meter_full_getter.call():
			continue
		var lit: bool = (_held & int(b["bit"])) != 0 and name != "maree"
		var col: Color = (b["color"] as Color)
		var fade: float = OVER_FIGHTER_ALPHA if _covers_fighter(b) and not lit else 1.0
		draw_circle(b["center"], float(b["radius"]), Color(col.lightened(0.3) if lit else col, (alpha if not lit else 0.9) * fade))
		draw_arc(b["center"], float(b["radius"]), 0, TAU, 24, Color(C_OUTLINE, 0.9 * fade), 1.5)
		if _icons.has(name):
			var tex: Texture2D = _icons[name]
			draw_texture(tex, ((b["center"] as Vector2) - tex.get_size() * 0.5).round(), Color(1, 1, 1, 0.95 * fade))
		if name == "maree":
			var tw: float = _font.get_string_size("MARÉE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_string(_font, (b["center"] as Vector2) + Vector2(-tw * 0.5, -float(b["radius"]) - 3), "MARÉE",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(C_LINEN, 0.95))
