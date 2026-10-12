class_name FightHud
extends Control
## HUD de combat (SPEC §10.5) : barres de vie en cadre de planche avec vie
## perdue retardée, chrono dans une bouée, txapelas de rounds, jauges Marée
## en 3 segments, compteur de combo. Dessin immédiat, pixel-net.

const C_OUTLINE: Color = Color8(58, 38, 52)
const C_WOOD: Color = Color8(150, 104, 62)
const C_WOOD_DARK: Color = Color8(108, 72, 46)
const C_GREEN: Color = Color8(52, 128, 72)
const C_GOLD: Color = Color8(244, 198, 62)
const C_RED: Color = Color8(206, 52, 52)
const C_LINEN: Color = Color8(247, 241, 227)
const C_SEA: Color = Color8(32, 120, 154)
const C_FOAM: Color = Color8(196, 232, 230)
const C_DARK: Color = Color8(24, 16, 28)

var sim: FightSim
var names: PackedStringArray = ["", ""]
var _lag: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
var _combo_text: Array[String] = ["", ""]
var _combo_t: PackedInt32Array = PackedInt32Array([0, 0])
var _font: Font
var _portraits: Array[PortraitView] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)
	_font = load("res://assets/fonts/press_start_2p.ttf")


## Portraits aux extrémités des barres de vie (40×40 si disponibles).
func set_portraits(ids: Array, costumes: Array) -> void:
	_portraits.clear()
	for p: int in 2:
		var kind: String = "portrait_hud" if ResourceLoader.exists(
			"res://assets/fighters/%s/portrait_hud.png" % ids[p]) else "portrait_small"
		var face: PortraitView = PortraitView.create(str(ids[p]), int(costumes[p]), kind)
		face.flip_h = p == 1
		add_child(face)
		_portraits.append(face)
	_place_portraits()


func _place_portraits() -> void:
	for p: int in _portraits.size():
		var face: PortraitView = _portraits[p]
		var sz: Vector2 = face.texture.get_size() if face.region_enabled == false else face.region_rect.size
		var scale_f: float = 1.0 if sz.x <= 28.0 else 0.5
		face.scale = Vector2(scale_f, scale_f)
		var w: float = sz.x * scale_f
		face.position = Vector2(3.0 if p == 0 else size.x - 3.0 - w, 3.0)


func show_combo(attacker: int, hits: int) -> void:
	_combo_text[attacker] = "%d COUPS !" % hits
	_combo_t[attacker] = 70


func _process(_delta: float) -> void:
	if sim == null:
		return
	for p: int in 2:
		var ratio: float = float(sim.f[p].health) / float(sim.f[p].max_health)
		if _lag[p] < ratio:
			_lag[p] = ratio
		elif sim.f[p].state != SimConst.ST_HITSTUN or _lag[p] - ratio > 0.25:
			_lag[p] = maxf(ratio, _lag[p] - 0.006)
		if _combo_t[p] > 0:
			_combo_t[p] -= 1
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var w: float = size.x
	var inset: float = 26.0 if not _portraits.is_empty() else 0.0
	var bar_w: float = floorf(w * 0.5) - 28.0 - inset
	for p: int in 2:
		var me: FighterState = sim.f[p]
		var x0: float = 6.0 + inset if p == 0 else w - 6.0 - inset - bar_w
		_draw_life(Rect2(x0, 6, bar_w, 9), float(me.health) / float(me.max_health), _lag[p], p == 1)
		var name_x: float = x0 if p == 0 else x0 + bar_w - _text_w(names[p])
		_text(Vector2(name_x, 25), names[p], C_LINEN)
		for r: int in sim.rounds_to_win:
			var cx: float = x0 + 4.0 + r * 10.0 if p == 0 else x0 + bar_w - 4.0 - r * 10.0
			_draw_txapela(Vector2(cx, 32), r < me.rounds)
		var mw: float = 3.0 * 22.0
		var mx: float = 6.0 if p == 0 else w - 6.0 - mw
		_draw_meter(Rect2(mx, size.y - 12.0, mw, 6), me.meter, p == 1)
		if _combo_t[p] > 0:
			var cxp: float = 8.0 if p == 0 else w - 8.0 - _text_w(_combo_text[p])
			_text(Vector2(cxp, 70), _combo_text[p], C_GOLD)
	_draw_timer(Vector2(floorf(w * 0.5), 14))


func _draw_life(r: Rect2, ratio: float, lag: float, mirror: bool) -> void:
	draw_rect(r.grow(2), C_OUTLINE)
	draw_rect(r.grow(1), C_WOOD)
	draw_rect(Rect2(r.position.x, r.position.y + r.size.y - 1, r.size.x, 1).grow_individual(1, 0, 1, 1), C_WOOD_DARK)
	draw_rect(r, C_DARK)
	var lag_w: float = floorf(r.size.x * clampf(lag, 0.0, 1.0))
	var w: float = floorf(r.size.x * clampf(ratio, 0.0, 1.0))
	var color: Color = C_GREEN if ratio > 0.5 else (C_GOLD if ratio > 0.25 else C_RED)
	if mirror:
		draw_rect(Rect2(r.end.x - lag_w, r.position.y, lag_w, r.size.y), C_LINEN)
		draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), color)
		draw_rect(Rect2(r.end.x - w, r.position.y, w, 2), color.lightened(0.25))
	else:
		draw_rect(Rect2(r.position.x, r.position.y, lag_w, r.size.y), C_LINEN)
		draw_rect(Rect2(r.position.x, r.position.y, w, r.size.y), color)
		draw_rect(Rect2(r.position.x, r.position.y, w, 2), color.lightened(0.25))
	# rivets
	for rx: float in [r.position.x - 1, r.end.x]:
		draw_rect(Rect2(rx, r.position.y + 3, 1, 1), C_GOLD)


func _draw_txapela(c: Vector2, won: bool) -> void:
	var col: Color = C_RED if won else C_DARK
	draw_rect(Rect2(c.x - 3, c.y - 2, 7, 3), C_OUTLINE)
	draw_rect(Rect2(c.x - 2, c.y - 1, 5, 1), col)
	draw_rect(Rect2(c.x - 1, c.y - 3, 3, 1), C_OUTLINE)
	draw_rect(Rect2(c.x, c.y - 4, 1, 1), C_OUTLINE)


func _draw_meter(r: Rect2, meter: int, mirror: bool) -> void:
	var seg_w: float = floorf(r.size.x / 3.0)
	for i: int in 3:
		var sx: float = r.position.x + (i * seg_w if not mirror else (2 - i) * seg_w)
		var seg: Rect2 = Rect2(sx + 1, r.position.y, seg_w - 2, r.size.y)
		draw_rect(seg.grow(1), C_OUTLINE)
		draw_rect(seg, C_DARK)
		var fill: float = clampf(float(meter - i * SimConst.METER_SEGMENT) / SimConst.METER_SEGMENT, 0.0, 1.0)
		var fw: float = floorf(seg.size.x * fill)
		var fx: float = seg.position.x if not mirror else seg.end.x - fw
		draw_rect(Rect2(fx, seg.position.y, fw, seg.size.y), C_SEA if fill < 1.0 else C_FOAM)
		if fill >= 1.0:
			draw_rect(Rect2(fx, seg.position.y, fw, 1), C_LINEN)


func _draw_timer(c: Vector2) -> void:
	draw_circle(c, 12, C_OUTLINE)
	draw_circle(c, 11, C_RED)
	for k: int in 4:
		var a: float = PI * 0.25 + k * PI * 0.5
		draw_line(c + Vector2(cos(a), sin(a)) * 7, c + Vector2(cos(a), sin(a)) * 11, C_LINEN, 3)
	draw_circle(c, 7, C_LINEN)
	var secs: int = ceili(sim.timer / 60.0)
	var t: String = str(secs)
	_text(Vector2(c.x - _text_w(t) * 0.5, c.y + 4), t, C_OUTLINE, false)


func _text_w(t: String) -> float:
	return _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x


func _text(pos: Vector2, t: String, color: Color, shadow: bool = true) -> void:
	if shadow:
		draw_string(_font, pos + Vector2(1, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, C_OUTLINE)
	draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)


## Un Control sous un CanvasLayer n'a pas de parent dimensionné : on
## recopie la taille visible du viewport (largeur variable en paysage).
func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	_place_portraits()
