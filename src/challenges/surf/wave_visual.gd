class_name WaveVisual
extends Node2D
## La vague du surf, dessinée en PIXEL ART : tout est quantifié sur une
## grille de 4 px (l'échelle du jeu), colonnes crantées, dithering en
## damier entre les deux tons, écume en paquets de gros pixels.
## La scène anime les paramètres, ce nœud dessine.

const PX: float = 4.0                       # taille d'un « pixel » du jeu

const BODY_COLOR: Color = Color(0.075, 0.33, 0.47)
const FACE_COLOR: Color = Color(0.18, 0.58, 0.64)
const BACK_COLOR: Color = Color(0.06, 0.27, 0.40)
const CREST_COLOR: Color = Color(0.94, 0.98, 0.97)
const SPRAY_COLOR: Color = Color(0.87, 0.96, 0.94, 0.85)

## Ligne d'eau de base (le pied de la vague).
var base_y: float = 620.0
## Centre horizontal de la bosse.
var center_x: float = 1500.0
## Hauteur de la bosse (px).
var height: float = 260.0
## Largeur caractéristique (px).
var sigma: float = 240.0
## 0..1 : intensité de l'écume de crête.
var breaking: float = 0.3
## 0..1 : mousse d'effondrement (closeout).
var collapse: float = 0.0

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func surface_y(x: float) -> float:
	var hump: float = height * exp(-pow((x - center_x) / sigma, 2.0))
	return base_y - hump - 5.0 * sin(_time * 1.8 + x * 0.01)


## Position (x, y) le long de la FACE (pente gauche) : s = 0 pied, 1 crête.
func face_point(s: float) -> Vector2:
	var x: float = center_x - sigma * 1.5 * (1.0 - s)
	return Vector2(x, surface_y(x))


func _q(v: float) -> float:
	return floorf(v / PX) * PX


func _cell(x: float, y: float, color: Color) -> void:
	draw_rect(Rect2(_q(x), _q(y), PX, PX), color)


func _dither(x: float, y: float) -> bool:
	# damier 2x2 cellules (8 px écran), stable dans le temps
	return int(floorf(x / (PX * 2.0)) + floorf(y / (PX * 2.0))) % 2 == 0


func _draw() -> void:
	# --- corps : colonnes crantées de 4 px, deux tons + dithering ---
	var x: float = -PX * 2.0
	while x <= 1300.0:
		var top: float = _q(surface_y(x + PX * 0.5))
		var on_face: bool = x < center_x            # pente avant (où l'on surfe)
		var depth_face: float = 130.0               # épaisseur de la teinte claire
		var y: float = top
		while y < 740.0:
			var color: Color
			var depth: float = y - top
			if depth < PX:
				color = CREST_COLOR                 # liseré de surface
			elif on_face and depth < depth_face:
				# transition dithérée face claire -> corps
				color = FACE_COLOR if (depth < depth_face - 24.0 or _dither(x, y)) else BODY_COLOR
			elif not on_face and depth < 60.0:
				color = BACK_COLOR if (depth < 36.0 or _dither(x, y)) else BODY_COLOR
			else:
				color = BODY_COLOR
			draw_rect(Rect2(_q(x), y, PX, minf(PX, 740.0 - y)), color)
			y += PX
		x += PX

	# --- écume de crête : paquets de gros pixels qui roulent ---
	if breaking > 0.05 and height > 10.0:
		var count: int = 4 + int(breaking * 7.0)
		for i: int in count:
			var t: float = i / float(maxi(count - 1, 1))
			var p: Vector2 = face_point(1.0 - t * 0.4 * breaking)
			var wob: float = PX * floorf(2.0 * sin(_time * 6.0 + i * 1.7))
			var blob: float = (2.0 + 3.0 * breaking) * (1.0 - t * 0.45)
			_foam_blob(p.x + wob, p.y - PX, int(blob))

	# --- cascade d'effondrement (closeout) ---
	if collapse > 0.02:
		for i: int in 12:
			var s: float = 1.0 - i / 11.0
			var p: Vector2 = face_point(s)
			var fall: float = collapse * (1.0 - s) * 70.0
			var jitter: float = PX * floorf(2.5 * sin(_time * 8.0 + i * 2.1))
			_foam_blob(p.x + jitter, p.y + fall, 2 + int(collapse * 3.0 * (1.0 - s * 0.5)))

	# --- mousse résiduelle au pied (fin de vie) ---
	if height < 60.0 and height > 4.0:
		for i: int in 7:
			var fx: float = center_x - sigma + i * sigma * 0.35
			var fy: float = base_y - PX + PX * floorf(1.5 * sin(_time * 4.0 + i))
			_foam_blob(fx, fy, 2)


## Petit tas d'écume : carré central + débords en croix (pixel clusters).
func _foam_blob(x: float, y: float, size_cells: int) -> void:
	var s: float = size_cells * PX
	draw_rect(Rect2(_q(x - s * 0.5), _q(y - s * 0.5), s, s), CREST_COLOR)
	draw_rect(Rect2(_q(x - s * 0.5 - PX), _q(y - PX * 0.5), PX, PX), SPRAY_COLOR)
	draw_rect(Rect2(_q(x + s * 0.5), _q(y - PX), PX, PX), SPRAY_COLOR)
	draw_rect(Rect2(_q(x), _q(y - s * 0.5 - PX), PX, PX), SPRAY_COLOR)
