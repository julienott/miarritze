class_name GkDraw
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
