class_name GkWater
extends Node2D
## Eau du port, animée (vaguelettes qui glissent, écume le long des quais). Redessinée
## 12 fois par seconde seulement : le reste de la carte est un dessin fixe.

var map: GkMap
var _t: float = 0.0
var _acc: float = 0.0
var _rects: Array[Rect2i] = []
## Eau couverte par une image (texture de mer) : seulement l'écume au pied des quais et des reflets
## qui scintillent par-dessus (provisoire, en attendant les boucles eau_mer et bord_quai_eau).
var _over: Array[Rect2i] = []


func _ready() -> void:
	# L'eau couverte par une image du décor (texture de mer, lavoir…) n'est plus dessinée ici ; sous
	# un objet posé sur l'eau (barques), si.
	_rects = map.merged_rects("~", map.decor.covered if map.decor else {})
	if map.decor:
		var mine: Dictionary = {}
		for r: Rect2i in _rects:
			for y: int in range(r.position.y, r.end.y):
				for x: int in range(r.position.x, r.end.x):
					mine[Vector2i(x, y)] = true
		# Le lavoir (objet posé sur « ~ ») n'est pas la mer.
		for c: Vector2i in map.decor.covered:
			if map.at(c) == "~" and not mine.has(c) and map.decor.zone_at(c) >= 0 \
					and map.zones[map.decor.zone_at(c)]["name"] != "Lavoir":
				_over.append(Rect2i(c, Vector2i.ONE))
	if map.decor:
		for c: Vector2i in map.decor.water_under:
			_rects.append(Rect2i(c, Vector2i.ONE))
	_reorder.call_deferred()


## Au-dessus des morceaux de la carte (cache les motifs de sol qui débordent sur l'eau) mais au même
## z que les persos et le décor en image : les objets qui débordent sur l'eau (barques qui tanguent,
## chalutier) restent visibles par-dessus, et les ombres du décor tombent sur l'eau.
func _reorder() -> void:
	var under: Node = map.decor.under if map.decor else null
	if under and under.get_parent() == map:
		var i: int = under.get_index()
		map.move_child(self, i - 1 if get_index() < i else i)
	else:
		map.move_child(self, -1)


func _process(dt: float) -> void:
	_t += dt
	_acc += dt
	if _acc >= 1.0 / 12.0:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	var t: float = map.tile
	# Seulement l'eau à l'écran (redessinée 12 fois par seconde).
	var view: Rect2 = get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	var vis: Rect2i = Rect2i(Vector2i((view.position / t).floor()) - Vector2i(1, 1), Vector2i((view.size / t).ceil()) + Vector2i(3, 3))
	var rects: Array[Rect2i] = []
	for r: Rect2i in _rects:
		if r.intersects(vis):
			rects.append(r.intersection(vis))
	for r: Rect2i in _over:
		if not r.intersects(vis):
			continue
		var x: int = r.position.x
		var y: int = r.position.y
		var above: String = map.at(Vector2i(x, y - 1))
		if above != "~" and above != "B":
			var y1: float = y * t + 8.0 + 4.0 * sin(_t * 1.8 + x * 0.7)
			draw_line(Vector2(x * t, y1), Vector2((x + 1) * t, y1 + 2.0 * sin(_t * 2.3 + x)), Color(1, 1, 1, 0.55), 6.0)
			draw_line(Vector2(x * t + 10, y1 + 10), Vector2((x + 1) * t - 14, y1 + 10), Color(1, 1, 1, 0.25), 3.0)
		var below: String = map.at(Vector2i(x, y + 1))
		if below != "~" and below != "B":
			var y2: float = (y + 1) * t - 6.0 + 3.0 * sin(_t * 1.6 + x * 0.9)
			draw_line(Vector2(x * t, y2), Vector2((x + 1) * t, y2), Color(1, 1, 1, 0.45), 5.0)
		var h: int = absi(x * 92821 ^ y * 68917) % 11
		if h < 2:
			var k: float = fmod(_t * 0.45 + float(h) * 0.37 + float(x) * 0.13, 1.0)
			var a: float = sin(k * PI)
			var p: Vector2 = (Vector2(x, y) + Vector2(0.3 + 0.4 * float(h), 0.5)) * t
			draw_line(p - Vector2(7, 0) * a, p + Vector2(7, 0) * a, Color(1, 1, 1, 0.7 * a), 3.0)
			draw_line(p - Vector2(0, 5) * a, p + Vector2(0, 5) * a, Color(1, 1, 1, 0.5 * a), 2.0)
	for r: Rect2i in rects:
		draw_rect(Rect2(Vector2(r.position) * t, Vector2(r.size) * t), Color("2e86c1"))
	for r: Rect2i in rects:
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var ph: float = _t * 1.4 + float(x) * 0.9 + float(y) * 1.7
				var p: Vector2 = (Vector2(x, y) + Vector2(0.2 + 0.15 * sin(ph), 0.55)) * t
				if (x + y * 2) % 3 == 0:
					draw_line(p, p + Vector2(t * 0.45, 0), Color(1, 1, 1, 0.22 + 0.12 * sin(ph)), 4.0)
	# Écume au bord des quais (case d'eau sous une case de sol).
	for r: Rect2i in rects:
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var above: String = map.at(Vector2i(x, y - 1))
				if above != "~" and above != "B":
					var y0: float = y * t + 6.0 + 3.0 * sin(_t * 2.0 + x)
					draw_line(Vector2(x * t, y0), Vector2((x + 1) * t, y0), Color(1, 1, 1, 0.6), 5.0)
				if map.at(Vector2i(x, y - 1)) != "~":
					draw_rect(Rect2(Vector2(x, y) * t, Vector2(t, 10)), Color(0, 0, 0, 0.12))
