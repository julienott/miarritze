class_name BkDraw
extends RefCounted
## Petits outils de dessin vectoriel « cartoon propre » (SPEC-GORDEKA §9) : formes arrondies
## avec contour sombre épais, aplat + ombre douce. Tout est tracé à l'exécution : net à toute
## taille, recolorable (la tenue prend la couleur choisie par le joueur).

const INK: Color = Color("1d2230")

static var _boxes: Dictionary = {}


## Rectangle arrondi plein avec contour (StyleBoxFlat mis en cache par style).
static func rbox(ci: CanvasItem, r: Rect2, fill: Color, radius: float, border: float = 3.0,
		ink: Color = INK) -> void:
	var key: String = "%s|%d|%d|%s" % [fill.to_html(), int(radius), int(border * 10), ink.to_html()]
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(int(radius))
		sb.set_border_width_all(int(border))
		sb.border_color = ink
		sb.anti_aliasing = true
		sb.corner_detail = 10
		_boxes[key] = sb
	sb.draw(ci.get_canvas_item(), r)


## Ellipse pleine (polygone), avec contour optionnel.
static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, fill: Color, border: float = 0.0,
		ink: Color = INK) -> void:
	var pts: PackedVector2Array = ellipse_points(c, rx, ry, 28)
	ci.draw_colored_polygon(pts, fill)
	if border > 0.0:
		pts.append(pts[0])
		ci.draw_polyline(pts, ink, border, true)


static func ellipse_points(c: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Polygone plein avec contour.
static func poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, border: float = 3.0,
		ink: Color = INK) -> void:
	ci.draw_colored_polygon(pts, fill)
	if border > 0.0:
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, ink, border, true)


# ---------------------------------------------------------------- emotes

const SKIN: Color = Color("f6c79a")
const SMILEY: Color = Color("ffd34a")


## Bulle d'emote au-dessus d'une tête : rond blanc à gros contour, pointe vers `tip`, icône dedans.
static func emote_bubble(ci: CanvasItem, c: Vector2, tip: Vector2, i: int, r: float) -> void:
	var d: Vector2 = (tip - c).normalized()
	var side: Vector2 = d.orthogonal() * r * 0.42
	var base: Vector2 = c + d * r * 0.7
	poly(ci, PackedVector2Array([base + side, tip, base - side]), Color.WHITE, 3.0)
	emote_disc(ci, c, r, i)
	# Raccord bulle-pointe sans contour.
	ci.draw_colored_polygon(PackedVector2Array([base + side * 0.8, c + d * (r - 1.0), base - side * 0.8]), Color.WHITE)


## Rond blanc à contour avec l'icône de l'emote `i` (éventail, bouton) ; `ring` surligne.
static func emote_disc(ci: CanvasItem, c: Vector2, r: float, i: int, ring: Color = Color(0, 0, 0, 0)) -> void:
	ellipse(ci, c, r, r, Color.WHITE, 3.0)
	if ring.a > 0.0:
		ci.draw_arc(c, r + 5.0, 0.0, TAU, 40, ring, 6.0, true)
	emote_icon(ci, c, r * 0.72, i)


## Icône d'une emote, sans texte (BkGame.EMOTES) : salut, rire, danse, pouce, chut, langue.
## Dessinée dans un repère de -10 à 10 centré sur `c`, mis à l'échelle de `r`.
static func emote_icon(ci: CanvasItem, c: Vector2, r: float, i: int) -> void:
	ci.draw_set_transform(c, 0.0, Vector2.ONE * r / 10.0)
	match i:
		0:      # salut : main ouverte qui s'agite
			var fingers: Array = [[Vector2(-3.6, 0), Vector2(-4.8, -6.8)], [Vector2(-1.2, -1), Vector2(-1.5, -8.4)],
				[Vector2(1.2, -1), Vector2(1.7, -8.1)], [Vector2(3.6, 0), Vector2(4.6, -6.2)], [Vector2(4.2, 3.5), Vector2(8, 0.5)]]
			_caps(ci, fingers, 2.6, SKIN, Vector2(0, 3.2), Vector2(5.4, 5.0))
			ci.draw_arc(Vector2(-6.5, -1), 4.5, PI * 0.75, PI * 1.25, 8, INK, 1.1, true)
			ci.draw_arc(Vector2(-6.5, -1), 7.0, PI * 0.8, PI * 1.2, 8, INK, 1.1, true)
		1:      # rire : yeux fermés de plaisir, grande bouche, larmes de rire
			ellipse(ci, Vector2.ZERO, 9.0, 9.0, SMILEY, 1.2)
			ci.draw_arc(Vector2(-3.4, -1.8), 2.0, PI * 1.1, PI * 1.9, 8, INK, 1.4, true)
			ci.draw_arc(Vector2(3.4, -1.8), 2.0, PI * 1.1, PI * 1.9, 8, INK, 1.4, true)
			var mouth: PackedVector2Array = PackedVector2Array()
			for k: int in 13:
				mouth.append(Vector2(0, 1.6) + Vector2.from_angle(PI * float(k) / 12.0) * Vector2(5.2, 5.0))
			poly(ci, mouth, Color("7a1f2b"), 1.0)
			ellipse(ci, Vector2(0, 5.0), 2.4, 1.2, Color("ff6f91"))
			ellipse(ci, Vector2(-8.6, 0.5), 1.4, 2.1, Color("6cc6ff"), 0.6)
			ellipse(ci, Vector2(8.6, 0.5), 1.4, 2.1, Color("6cc6ff"), 0.6)
		2:      # danse : deux notes de musique
			var col: Color = Color("9b4fd6")
			poly(ci, PackedVector2Array([Vector2(-2.6, -7.2), Vector2(8.2, -9.6), Vector2(8.2, -6.4),
				Vector2(-2.6, -4.0)]), col, 1.0)
			_caps(ci, [[Vector2(-2.2, 5.5), Vector2(-2.2, -5.6)], [Vector2(7.4, 3.5), Vector2(7.4, -8.0)]], 1.4, col)
			ellipse(ci, Vector2(-4.6, 6.0), 3.0, 2.3, col, 1.0)
			ellipse(ci, Vector2(5.0, 4.0), 3.0, 2.3, col, 1.0)
		3:      # pouce levé
			_caps(ci, [[Vector2(-2.2, 0), Vector2(-2.6, -8.2)]], 3.6, SKIN, Vector2(1.2, 3.4), Vector2(6.2, 5.0))
			for k: int in 3:
				ci.draw_line(Vector2(2.5, 0.8 + k * 2.6), Vector2(6.6, 0.8 + k * 2.6), INK, 0.9, true)
		4:      # chut : un doigt sur la bouche
			ellipse(ci, Vector2.ZERO, 9.0, 9.0, SMILEY, 1.2)
			ellipse(ci, Vector2(-3.4, -2.4), 1.3, 1.5, INK)
			ellipse(ci, Vector2(3.4, -2.4), 1.3, 1.5, INK)
			ellipse(ci, Vector2(0, 4.2), 3.0, 1.7, Color("e0566e"), 0.8)
			_caps(ci, [[Vector2(0, 10.5), Vector2(0, 0.6)]], 2.8, SKIN)
		5:      # tirer la langue, un œil fermé
			ellipse(ci, Vector2.ZERO, 9.0, 9.0, SMILEY, 1.2)
			ci.draw_line(Vector2(-5.0, -2.6), Vector2(-2.0, -2.2), INK, 1.4, true)
			ellipse(ci, Vector2(3.4, -2.4), 1.3, 1.5, INK)
			ellipse(ci, Vector2(1.2, 5.6), 2.8, 3.2, Color("ff6f91"), 1.0)
			ci.draw_line(Vector2(1.2, 4.0), Vector2(1.2, 7.0), Color("c23a5a"), 0.8, true)
			ci.draw_arc(Vector2(0, -1.0), 5.2, PI * 0.25, PI * 0.75, 10, INK, 1.4, true)
	ci.draw_set_transform(Vector2.ZERO)


## Traits arrondis à contour (doigts, pouce, hampes), avec une paume ovale optionnelle :
## tous les contours d'abord, puis les aplats, pour une forme d'un seul tenant.
static func _caps(ci: CanvasItem, segs: Array, w: float, fill: Color, palm: Vector2 = Vector2.INF,
		palm_r: Vector2 = Vector2.ZERO) -> void:
	for pass_i: int in 2:
		var o: float = 1.1 if pass_i == 0 else 0.0
		var col: Color = INK if pass_i == 0 else fill
		for s: Array in segs:
			ci.draw_line(s[0], s[1], col, w + o * 2.0, true)
			ci.draw_circle(s[0], w * 0.5 + o, col)
			ci.draw_circle(s[1], w * 0.5 + o, col)
		if palm != Vector2.INF:
			ci.draw_colored_polygon(ellipse_points(palm, palm_r.x + o, palm_r.y + o, 28), col)
