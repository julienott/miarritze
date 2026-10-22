class_name BkDraw
extends RefCounted
## Petits outils de dessin (GDD-BLACKOUT.md) : formes arrondies
## avec contour, ellipses, police pixel du jeu et lettres 3×5 des silhouettes de repli.

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


# ---------------------------------------------------------------- pixel art

## Police du jeu en 640×360 (GDD §9 : HUD minimal en police pixel) : la police par défaut, rendue
## sans lissage, pour des lettres nettes une fois agrandies ×2 au plus proche voisin.
static var _police: FontFile


static func police() -> Font:
	if _police == null:
		var base: Font = ThemeDB.fallback_font
		if base is FontFile:
			_police = (base as FontFile).duplicate() as FontFile
			_police.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			_police.hinting = TextServer.HINTING_NONE
			_police.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		else:
			return base
	return _police


## Texte centré sur `at.x` (ligne de base en `at.y`), cerné d'encre d'un pixel.
static func texte(ci: CanvasItem, at: Vector2, t: String, taille: int, col: Color, contour: int = 2,
		largeur: float = 400.0) -> void:
	var f: Font = police()
	var p: Vector2 = Vector2(at.x - largeur * 0.5, at.y).round()
	if contour > 0:
		ci.draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_CENTER, largeur, taille, contour, Color(INK, col.a))
	ci.draw_string(f, p, t, HORIZONTAL_ALIGNMENT_CENTER, largeur, taille, col)


## Lettres 3×5 (majuscules) pour les silhouettes de repli des persos : une chaîne de 15 bits par
## lettre, ligne par ligne.
const GLYPHES: Dictionary = {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
	"E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
	"Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
	"U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111",
}


## Pose la lettre `ch` (3×5) dans `img`, coin haut gauche en `o`.
static func glyphe(img: Image, ch: String, o: Vector2i, col: Color) -> void:
	var g: String = str(GLYPHES.get(ch.to_upper(), ""))
	for i: int in g.length():
		if g[i] == "1":
			img.set_pixel(o.x + i % 3, o.y + i / 3, col)
