class_name WaveVisual
extends Node2D
## La vague du surf, dessinée pour être LUE d'un coup d'œil :
## bosse gaussienne à deux tons (dos sombre / face claire), crête d'écume
## animée qui roule, mousse au pied quand elle déferle. Tout est piloté
## par quelques paramètres — la scène anime, ce nœud dessine.

const BODY_COLOR: Color = Color(0.075, 0.33, 0.47)
const FACE_COLOR: Color = Color(0.18, 0.58, 0.64)
const CREST_COLOR: Color = Color(0.94, 0.98, 0.97)
const OUTLINE_COLOR: Color = Color(0.86, 0.95, 0.94, 0.9)

## Ligne d'eau de base (le pied de la vague).
var base_y: float = 620.0
## Centre horizontal de la bosse.
var center_x: float = 1500.0
## Hauteur de la bosse (px).
var height: float = 260.0
## Largeur caractéristique (px) : la vague s'étale sur ~3 sigma.
var sigma: float = 240.0
## 0..1 : intensité de l'écume de crête (0 = houle lisse, 1 = ça déferle).
var breaking: float = 0.3
## 0..1 : mousse d'effondrement (closeout).
var collapse: float = 0.0

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Hauteur de la surface de l'eau au point x (la houle comprise).
func surface_y(x: float) -> float:
	var hump: float = height * exp(-pow((x - center_x) / sigma, 2.0))
	return base_y - hump - 5.0 * sin(_time * 1.8 + x * 0.01)


## Position (x, y) le long de la FACE (pente gauche) : s = 0 pied, 1 crête.
func face_point(s: float) -> Vector2:
	var x: float = center_x - sigma * 1.5 * (1.0 - s)
	return Vector2(x, surface_y(x))


func _draw() -> void:
	# corps de la vague (du bord gauche au bord droit de l'écran)
	var body: PackedVector2Array = PackedVector2Array()
	body.append(Vector2(-60.0, 740.0))
	var top_points: PackedVector2Array = PackedVector2Array()
	var x: float = -60.0
	while x <= 1340.0:
		var p: Vector2 = Vector2(x, surface_y(x))
		body.append(p)
		top_points.append(p)
		x += 24.0
	body.append(Vector2(1340.0, 740.0))
	draw_polygon(body, PackedColorArray([BODY_COLOR]))

	# face éclairée : bande le long de la pente gauche (là où on surfe)
	var face: PackedVector2Array = PackedVector2Array()
	for i: int in 15:
		face.append(face_point(1.0 - i / 14.0))
	for i: int in 15:
		var p: Vector2 = face_point(i / 14.0)
		face.append(Vector2(p.x, minf(p.y + 60.0 + 30.0 * (1.0 - i / 14.0), 738.0)))
	if height > 12.0:
		draw_polygon(face, PackedColorArray([FACE_COLOR]))

	# liseré de surface
	draw_polyline(top_points, OUTLINE_COLOR, 5.0)

	# écume de crête : boules blanches qui roulent au sommet
	if breaking > 0.05 and height > 10.0:
		var crest: Vector2 = Vector2(center_x, surface_y(center_x))
		var count: int = 3 + int(breaking * 6.0)
		for i: int in count:
			var t: float = i / float(maxi(count - 1, 1))
			var p: Vector2 = face_point(1.0 - t * 0.35 * breaking)
			var wob: float = 4.0 * sin(_time * 6.0 + i * 1.7)
			var radius: float = (10.0 + 14.0 * breaking) * (1.0 - t * 0.5) + wob
			draw_circle(Vector2(p.x, p.y - 4.0), radius, CREST_COLOR)
		draw_circle(crest + Vector2(6.0, -6.0), 12.0 + 10.0 * breaking, CREST_COLOR)

	# mousse d'effondrement : cascade blanche sur toute la face
	if collapse > 0.02:
		for i: int in 10:
			var s: float = 1.0 - i / 9.0
			var p: Vector2 = face_point(s)
			var fall: float = collapse * (1.0 - s) * 60.0
			draw_circle(Vector2(p.x + 8.0 * sin(_time * 8.0 + i), p.y + fall),
				10.0 + 12.0 * collapse * (1.0 - s * 0.5), CREST_COLOR)

	# mousse résiduelle au pied (fin de vie)
	if height < 60.0 and height > 4.0:
		for i: int in 6:
			var fx: float = center_x - sigma + i * sigma * 0.4
			draw_circle(Vector2(fx, base_y - 6.0 + 3.0 * sin(_time * 4.0 + i)),
				8.0, Color(CREST_COLOR, 0.7))
