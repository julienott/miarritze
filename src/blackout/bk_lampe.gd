class_name BkLampe
extends Node2D
## Cône de lumière de la lampe du chasseur pendant son animation `hunter_reveal` (Julien, 2026-10-20 :
## les faisceaux dessinés par l'IA ne sont « pas crédibles », c'est le jeu qui dessine la lumière).
## Enfant du BkPerso : il part de la main mesurée image par image (« lampe » du .json de l'anim,
## tools/blackout/lampe.py), vers l'avant du perso. Il s'allume en clignotant à l'image `debut`,
## suit la main, puis s'éteint en fondu à la fin du geste, quand le cône de vision prend le relais.
## Dessiné en px d'écran : son échelle annule celle du perso.

## Même lumière chaude que la lampe ; le cône de vision du chasseur (lumière blanche, cône rouge vu
## des chassés) prend le relais à la fin.
const COULEUR: Color = Color(1.0, 0.87, 0.34)
const COEUR: Color = Color(1.0, 0.98, 0.82)
const LONGUEUR_PX: float = 150.0      # longueur du cône à l'écran
const DEMI_ANGLE_DEG: float = 15.0
const SOURCE_PX: float = 3.5          # demi-largeur du cône à la lampe
const ALPHA: float = 0.6              # opacité du cône à la source
const BORD_ALPHA: float = 0.55        # trait du bord, net
const HALO_PX: float = 11.0           # halo autour de la lampe
const TRANCHES: int = 14              # tranches du dégradé le long du cône
## Clignotement à l'allumage : alternance allumé / presque éteint (durées en s).
const CLIGNOTE: Array[float] = [0.05, 0.05, 0.04, 0.07, 0.05]
const ETEINT_K: float = 0.12
const FONDU_S: float = 0.2            # extinction

var _on: bool = false
var _t_on: float = 0.0
var _k: float = 0.0                   # intensité 0..1 (fondu)
var _dir: float = 1.0


## Appelé à chaque image par le perso : `on` si la lampe éclaire, `p` la main (repère du perso),
## `dir` +1 vers la droite / -1 vers la gauche, `ech` l'échelle du perso.
func suivre(on: bool, p: Vector2, dir: float, ech: Vector2, dt: float) -> void:
	if on:
		if not _on:
			_t_on = 0.0
		_t_on += dt
		_k = 1.0
		position = p
		_dir = dir
	else:
		_k = maxf(0.0, _k - dt / FONDU_S)
	_on = on
	scale = Vector2(1.0 / maxf(ech.x, 0.001), 1.0 / maxf(ech.y, 0.001))
	visible = _k > 0.0
	if visible:
		queue_redraw()


func eteindre() -> void:
	_on = false
	_k = 0.0
	visible = false


## Intensité du moment : clignotement à l'allumage, puis stable.
func _intensite() -> float:
	var t: float = _t_on
	var allume: bool = true
	for d: float in CLIGNOTE:
		if t < d:
			return _k * (1.0 if allume else ETEINT_K)
		t -= d
		allume = not allume
	return _k


func _draw() -> void:
	var k: float = _intensite()
	if k <= 0.0:
		return
	var tg: float = tan(deg_to_rad(DEMI_ANGLE_DEG))
	var lg: float = LONGUEUR_PX
	# Corps du cône : tranches en dégradé, de l'opacité de la source à rien au bout.
	for i: int in TRANCHES:
		var x0: float = lg * float(i) / float(TRANCHES)
		var x1: float = lg * float(i + 1) / float(TRANCHES)
		var w0: float = SOURCE_PX + x0 * tg
		var w1: float = SOURCE_PX + x1 * tg
		var a0: float = ALPHA * k * pow(1.0 - float(i) / float(TRANCHES), 1.3)
		var a1: float = ALPHA * k * pow(1.0 - float(i + 1) / float(TRANCHES), 1.3)
		var c0: Color = Color(COULEUR, a0)
		var c1: Color = Color(COULEUR, a1)
		draw_polygon(PackedVector2Array([
			Vector2(x0 * _dir, -w0), Vector2(x1 * _dir, -w1), Vector2(x1 * _dir, w1), Vector2(x0 * _dir, w0)]),
			PackedColorArray([c0, c1, c1, c0]))
		# Cœur plus clair, deux fois plus étroit, qui s'éteint plus vite.
		var h0: float = SOURCE_PX * 0.6 + x0 * tg * 0.45
		var h1: float = SOURCE_PX * 0.6 + x1 * tg * 0.45
		var d0: Color = Color(COEUR, a0 * 0.55 * (1.0 - float(i) / float(TRANCHES)))
		var d1: Color = Color(COEUR, a1 * 0.55 * (1.0 - float(i + 1) / float(TRANCHES)))
		draw_polygon(PackedVector2Array([
			Vector2(x0 * _dir, -h0), Vector2(x1 * _dir, -h1), Vector2(x1 * _dir, h1), Vector2(x0 * _dir, h0)]),
			PackedColorArray([d0, d1, d1, d0]))
	# Bords nets, qui s'effacent vers le bout (style cartoon : un trait plutôt qu'un flou).
	for s: float in [-1.0, 1.0]:
		var pts: PackedVector2Array = PackedVector2Array()
		var cols: PackedColorArray = PackedColorArray()
		for i: int in 7:
			var x: float = lg * 0.85 * float(i) / 6.0
			pts.append(Vector2(x * _dir, s * (SOURCE_PX + x * tg)))
			cols.append(Color(COULEUR.lightened(0.3), BORD_ALPHA * k * (1.0 - float(i) / 6.0)))
		draw_polyline_colors(pts, cols, 1.6, true)
	# Halo et éclat de la lampe.
	draw_circle(Vector2.ZERO, HALO_PX, Color(COULEUR, 0.22 * k), true, -1.0, true)
	draw_circle(Vector2.ZERO, HALO_PX * 0.55, Color(COULEUR, 0.4 * k), true, -1.0, true)
	draw_circle(Vector2.ZERO, HALO_PX * 0.25, Color(1, 1, 1, 0.9 * k), true, -1.0, true)
