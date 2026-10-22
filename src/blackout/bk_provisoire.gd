class_name GkProvisoire
extends Node2D
## Décor provisoire dessiné par le code (revue de carte du 2026-10-20) : pour un élément du décor qui
## n'a pas encore d'image de pixelforge (index.json → « provisoire » : sa sorte de dessin), un dessin
## simple dans le style du jeu (aplats, contour encre), animé quand l'objet doit vivre (fanions et linge
## au vent, lanterne qui vacille, fumée, filet qui se balance, mouette qui hoche la tête, chat qui bat
## de la queue). Dès que l'image arrive (integre_decor.py), GkDecor la pose à la place.
##
## Le nœud est placé au pied de l'objet (bas, centre) ; `size` est son emprise en px (largeur, hauteur
## au sol) ; il dessine vers le haut. Ornements (sans effet de jeu) et objets de jeu (barriques, pots,
## platanes : leur collision reste celle des cases, posée par GkMap).

const INK: Color = GkDraw.INK
## Redessin des provisoires animés (images par seconde) : peu, comme l'eau.
const FPS: float = 12.0

var kind: String = ""
var size: Vector2 = Vector2(64, 64)
var mirror: bool = false
var phase: float = 0.0
var _t: float = 0.0
var _acc: float = 0.0

const ANIMATED: Array[String] = ["fanions", "linge", "lanterne", "fumee", "filet_suspendu", "mouette", "chat",
	"drapeau", "platane"]


func _ready() -> void:
	set_process(ANIMATED.has(kind))


func _process(dt: float) -> void:
	_t += dt
	_acc += dt
	if _acc >= 1.0 / FPS:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	if mirror:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	var w: float = size.x
	var t: float = _t + phase
	match kind:
		"barriques": _barriques(w)
		"pot_hortensias": _pot(w)
		"platane": _platane(w, t)
		"fanions": _fanions(w, t)
		"linge": _linge(w, t)
		"lanterne": _lanterne(t)
		"fumee": _fumee(t)
		"bouee": _bouee()
		"filet_suspendu": _filet(w, t)
		"mouette": _mouette(t)
		"chat": _chat(t)
		"ancre": _ancre()
		"cordage": _cordage()
		"lampadaire": _lampadaire()
		"casier_vide": _casier(w)
		"drapeau": _drapeau(t)
		"panier": _panier()
		"filet_sol": _filet_sol(w)
		_: GkDraw.rbox(self, Rect2(-w * 0.4, -w * 0.8, w * 0.8, w * 0.8), Color("c9a873"), 6.0)


# ---------------------------------------------------------------- objets de jeu

## Deux barriques de cidre côte à côte, cerclées de fer (bloquent la vue : 1 case, un peu de débord).
func _barriques(w: float) -> void:
	_shadow(w * 0.46, 8.0)
	for i: int in 2:
		var cx: float = (-0.22 + 0.44 * i) * w
		var r: Rect2 = Rect2(cx - w * 0.24, -w * 1.05 + i * 6.0, w * 0.48, w * 1.0 - i * 6.0)
		GkDraw.rbox(self, r, Color("9b6436"), 12.0)
		for k: float in [0.22, 0.75]:
			draw_rect(Rect2(r.position.x + 3, r.position.y + r.size.y * k, r.size.x - 6, 5), Color("5b5f66"))
		GkDraw.ellipse(self, Vector2(cx, r.position.y + 7), w * 0.2, 6.0, Color("c48a52"), 2.5)


## Pot d'hortensias bleus et roses (objet bas : on voit par-dessus).
func _pot(w: float) -> void:
	_shadow(w * 0.36, 6.0)
	GkDraw.poly(self, PackedVector2Array([Vector2(-w * 0.26, -w * 0.38), Vector2(w * 0.26, -w * 0.38),
		Vector2(w * 0.2, -2), Vector2(-w * 0.2, -2)]), Color("c4683e"))
	var cols: Array[Color] = [Color("7fa8e8"), Color("e98bb5"), Color("9a8fe0")]
	for i: int in 5:
		var a: float = float(i) / 4.0
		GkDraw.ellipse(self, Vector2((a - 0.5) * w * 0.5, -w * 0.5 - (0.12 if i % 2 else 0.0) * w), w * 0.16, w * 0.13,
			cols[i % 3], 2.5)
	draw_line(Vector2(-w * 0.1, -w * 0.4), Vector2(-w * 0.14, -w * 0.46), Color("4f8a3c"), 3.0)


## Platane de la place (tronc 1 case, houppier qui déborde et frémit).
func _platane(w: float, t: float) -> void:
	_shadow(w * 0.9, 16.0)
	GkDraw.rbox(self, Rect2(-w * 0.13, -w * 1.25, w * 0.26, w * 1.22), Color("b9a07c"), 8.0)
	draw_rect(Rect2(-w * 0.06, -w * 0.9, w * 0.1, w * 0.18), Color("8f7a5c"))
	var sway: float = 2.0 * sin(t * 1.3)
	var leaves: Array[Vector3] = [Vector3(-0.45, -1.6, 0.5), Vector3(0.42, -1.65, 0.5), Vector3(0.0, -2.05, 0.6),
		Vector3(-0.15, -1.45, 0.45), Vector3(0.25, -1.35, 0.4)]
	for i: int in leaves.size():
		var l: Vector3 = leaves[i]
		GkDraw.ellipse(self, Vector2(l.x * w + sway * (1.0 + i * 0.2), l.y * w), l.z * w, l.z * w * 0.82,
			Color("5f9a4a") if i % 2 == 0 else Color("6fae55"), 3.0)
	GkDraw.ellipse(self, Vector2(-w * 0.12 + sway, -w * 2.15), w * 0.16, w * 0.09, Color(1, 1, 1, 0.25))


## Barriques vides, casiers : variante de la pile de caisses (2 × 1).
func _casier(w: float) -> void:
	_shadow(w * 0.5, 7.0)
	GkDraw.rbox(self, Rect2(-w * 0.48, -w * 0.42, w * 0.96, w * 0.4), Color("6c8fb0"), 6.0)
	for k: int in 5:
		var x: float = -w * 0.4 + k * w * 0.2
		draw_line(Vector2(x, -w * 0.4), Vector2(x, -4), Color(INK, 0.5), 2.0)


# ---------------------------------------------------------------- ornements (sans effet de jeu)

## Guirlande de fanions rouges, verts et blancs tendue d'un mur à l'autre, qui ondule au vent.
func _fanions(w: float, t: float) -> void:
	var y0: float = -size.y
	var n: int = maxi(3, int(w / 34.0))
	var cols: Array[Color] = [Color("d83a34"), Color("f4f1ea"), Color("2f9a4a")]
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n + 1:
		var a: float = float(i) / float(n)
		pts.append(Vector2(-w * 0.5 + a * w, y0 + sin(a * PI) * 26.0 + sin(t * 2.0 + a * 6.0) * 3.0))
	draw_polyline(pts, INK, 2.5, true)
	for i: int in n:
		var p: Vector2 = pts[i].lerp(pts[i + 1], 0.5)
		var flap: float = sin(t * 3.2 + i * 1.3) * 5.0
		GkDraw.poly(self, PackedVector2Array([p + Vector2(-10, -2), p + Vector2(10, -2), p + Vector2(flap, 22)]),
			cols[i % 3], 2.0)


## Corde à linge entre deux perches, draps et marinières qui flottent.
func _linge(w: float, t: float) -> void:
	var y0: float = -size.y
	for x: float in [-w * 0.5, w * 0.5]:
		draw_line(Vector2(x, 0), Vector2(x, y0 - 6), Color("8a6239"), 5.0)
	draw_line(Vector2(-w * 0.5, y0), Vector2(w * 0.5, y0), INK, 2.0)
	var cols: Array[Color] = [Color("f4f1ea"), Color("2f6fe0"), Color("d83a34"), Color("f4f1ea")]
	var n: int = maxi(2, int(w / 52.0))
	for i: int in n:
		var x: float = -w * 0.5 + (float(i) + 0.5) * w / float(n)
		var sw: float = sin(t * 2.4 + i * 1.7) * 6.0
		var hw: float = minf(w / float(n) * 0.36, 20.0)
		var pts: PackedVector2Array = PackedVector2Array([Vector2(x - hw, y0), Vector2(x + hw, y0),
			Vector2(x + hw + sw, y0 + 34), Vector2(x - hw + sw, y0 + 34)])
		GkDraw.poly(self, pts, cols[i % cols.size()], 2.0)
		if i % cols.size() == 1:
			for k: int in 3:
				draw_line(Vector2(x - hw + sw * k / 3.0, y0 + 9 + k * 9), Vector2(x + hw + sw * k / 3.0, y0 + 9 + k * 9),
					Color("f4f1ea"), 3.0)


## Lanterne de façade : la flamme vacille, petit halo.
func _lanterne(t: float) -> void:
	var f: float = 0.75 + 0.25 * sin(t * 7.0) * sin(t * 3.1)
	draw_circle(Vector2(0, -20), 22.0, Color(1.0, 0.85, 0.4, 0.18 * f))
	draw_line(Vector2(0, -44), Vector2(0, -34), INK, 3.0)
	GkDraw.rbox(self, Rect2(-9, -34, 18, 24), Color(1.0, 0.86, 0.45, 0.6 + 0.4 * f), 4.0, 2.5)
	GkDraw.poly(self, PackedVector2Array([Vector2(-12, -34), Vector2(12, -34), Vector2(0, -42)]), Color("2b2f3a"), 2.0)


## Fumée de cheminée : trois bouffées qui montent et s'effacent.
func _fumee(t: float) -> void:
	GkDraw.rbox(self, Rect2(-9, -22, 18, 22), Color("9e4a33"), 3.0, 2.5)
	for i: int in 3:
		var k: float = fmod(t * 0.35 + float(i) / 3.0, 1.0)
		var p: Vector2 = Vector2(sin(k * 5.0 + i) * 8.0 + k * 14.0, -26.0 - k * 70.0)
		draw_circle(p, 7.0 + k * 12.0, Color(0.93, 0.93, 0.95, 0.55 * (1.0 - k)))


## Bouée de sauvetage accrochée au mur.
func _bouee() -> void:
	GkDraw.ellipse(self, Vector2(0, -26), 15.0, 15.0, Color("f4f1ea"), 3.0)
	for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		draw_arc(Vector2(0, -26), 11.5, a + 0.2, a + 0.9, 6, Color("d83a34"), 7.0)
	GkDraw.ellipse(self, Vector2(0, -26), 6.0, 6.0, Color("8a8f99"), 2.5)


## Filet de pêche suspendu au mur, flotteurs orange, qui se balance doucement.
func _filet(w: float, t: float) -> void:
	var sw: float = sin(t * 1.6) * 4.0
	var top: float = -size.y
	var hw: float = minf(w * 0.4, 46.0)
	var pts: PackedVector2Array = PackedVector2Array([Vector2(-hw, top), Vector2(hw, top),
		Vector2(hw * 0.7 + sw, top + 46), Vector2(-hw * 0.7 + sw, top + 52)])
	draw_colored_polygon(pts, Color(0.35, 0.62, 0.5, 0.55))
	for k: int in 6:
		var a: float = float(k) / 5.0
		draw_line(Vector2(-hw + a * 2 * hw, top), Vector2(-hw * 0.7 + a * 1.4 * hw + sw, top + 50), Color(INK, 0.45), 1.5)
	for k: int in 4:
		draw_line(Vector2(-hw + k * 3.0, top + k * 13.0), Vector2(hw - k * 3.0 + sw, top + k * 13.0), Color(INK, 0.45), 1.5)
	for k: int in 4:
		GkDraw.ellipse(self, Vector2(-hw + 8 + k * (2 * hw - 16) / 3.0, top + 2), 6.0, 4.5, Color("f08a2e"), 2.0)


## Mouette posée sur un muret, qui hoche la tête (ornement : les mouettes de jeu restent celles de GkGame).
func _mouette(t: float) -> void:
	var bob: float = 2.0 * maxf(0.0, sin(t * 2.2))
	GkDraw.ellipse(self, Vector2(0, -14), 14.0, 9.0, Color("f4f6f8"), 2.5)
	GkDraw.ellipse(self, Vector2(10, -22 + bob), 7.0, 6.5, Color("f4f6f8"), 2.5)
	GkDraw.poly(self, PackedVector2Array([Vector2(-6, -18), Vector2(10, -16), Vector2(-14, -10)]), Color("9aa3ad"), 2.0)
	GkDraw.poly(self, PackedVector2Array([Vector2(16, -22 + bob), Vector2(24, -20 + bob), Vector2(16, -19 + bob)]),
		Color("f2c12e"), 1.5)
	draw_circle(Vector2(12, -24 + bob), 1.6, INK)
	draw_line(Vector2(-2, -5), Vector2(-2, 0), Color("f2a53a"), 2.0)
	draw_line(Vector2(4, -5), Vector2(4, 0), Color("f2a53a"), 2.0)


## Chat roux endormi en boule, la queue qui bat.
func _chat(t: float) -> void:
	GkDraw.ellipse(self, Vector2(0, -10), 18.0, 10.0, Color("e8954a"), 2.5)
	GkDraw.ellipse(self, Vector2(-13, -14), 8.0, 7.0, Color("e8954a"), 2.5)
	GkDraw.poly(self, PackedVector2Array([Vector2(-19, -18), Vector2(-17, -26), Vector2(-13, -20)]), Color("e8954a"), 2.0)
	GkDraw.poly(self, PackedVector2Array([Vector2(-12, -20), Vector2(-8, -26), Vector2(-7, -18)]), Color("e8954a"), 2.0)
	var a: float = sin(t * 2.6) * 0.5
	var tail: Vector2 = Vector2(18, -8)
	draw_polyline(PackedVector2Array([tail, tail + Vector2(8, -2).rotated(a), tail + Vector2(14, -8).rotated(a * 1.4)]),
		Color("c8762e"), 5.0, true)
	draw_line(Vector2(-16, -14), Vector2(-12, -14), INK, 1.5)


## Ancre posée au pied d'un mur.
func _ancre() -> void:
	draw_line(Vector2(0, -40), Vector2(0, -6), Color("4b505a"), 6.0)
	draw_arc(Vector2(0, -16), 14.0, 0.2, PI - 0.2, 10, Color("4b505a"), 6.0)
	draw_line(Vector2(-10, -34), Vector2(10, -34), Color("4b505a"), 5.0)
	draw_arc(Vector2(0, -44), 5.0, 0.0, TAU, 10, Color("4b505a"), 3.0)


## Cordage enroulé à plat sur le quai.
func _cordage() -> void:
	for k: int in 3:
		GkDraw.ellipse(self, Vector2(0, -8), 16.0 - k * 4.5, 8.0 - k * 2.2, Color("d9b878") if k % 2 == 0 else Color("c4a062"), 2.0)


## Réverbère du port (fonte verte, globe blanc).
func _lampadaire() -> void:
	_shadow(10.0, 4.0)
	draw_line(Vector2(0, 0), Vector2(0, -92), Color("2f5a46"), 6.0)
	GkDraw.ellipse(self, Vector2(0, -100), 10.0, 11.0, Color("fbf6e4"), 2.5)
	GkDraw.poly(self, PackedVector2Array([Vector2(-11, -108), Vector2(11, -108), Vector2(0, -116)]), Color("2f5a46"), 2.0)


## Petit drapeau rouge et vert sur un mât (bateau, jetée).
func _drapeau(t: float) -> void:
	draw_line(Vector2(0, 0), Vector2(0, -70), Color("8a6239"), 4.0)
	var pts: PackedVector2Array = PackedVector2Array()
	for k: int in 6:
		var a: float = float(k) / 5.0
		pts.append(Vector2(2 + a * 34, -70 + sin(t * 4.0 + a * 4.0) * 4.0 * a))
	for k: int in range(5, -1, -1):
		var a2: float = float(k) / 5.0
		pts.append(Vector2(2 + a2 * 34, -50 + sin(t * 4.0 + a2 * 4.0) * 4.0 * a2))
	GkDraw.poly(self, pts, Color("d83a34"), 2.0)


## Panier d'osier plein de poissons (posé au sol, ornement).
func _panier() -> void:
	_shadow(20.0, 6.0)
	GkDraw.poly(self, PackedVector2Array([Vector2(-20, -22), Vector2(20, -22), Vector2(15, -2), Vector2(-15, -2)]),
		Color("c9a062"))
	for k: int in 3:
		draw_line(Vector2(-18 + k, -15 + k * 5), Vector2(18 - k, -15 + k * 5), Color(INK, 0.35), 2.0)
	for i: int in 3:
		var c: Vector2 = Vector2(-10 + i * 10, -25 - (i % 2) * 3)
		GkDraw.ellipse(self, c, 8.0, 3.5, Color("9fb7c9"), 2.0)
		GkDraw.poly(self, PackedVector2Array([c + Vector2(7, 0), c + Vector2(12, -4), c + Vector2(12, 4)]), Color("9fb7c9"), 1.5)


## Filet étendu à plat sur le sol pour sécher (ornement, couche sol).
func _filet_sol(w: float) -> void:
	var hw: float = w * 0.45
	var pts: PackedVector2Array = PackedVector2Array([Vector2(-hw, -30), Vector2(hw * 0.9, -34), Vector2(hw, -4),
		Vector2(-hw * 0.85, -2)])
	draw_colored_polygon(pts, Color(0.3, 0.55, 0.45, 0.35))
	for k: int in 7:
		var a: float = float(k) / 6.0
		draw_line(pts[0].lerp(pts[1], a), pts[3].lerp(pts[2], a), Color(0.2, 0.4, 0.33, 0.6), 1.5)
	for k: int in 4:
		var a2: float = float(k) / 3.0
		draw_line(pts[0].lerp(pts[3], a2), pts[1].lerp(pts[2], a2), Color(0.2, 0.4, 0.33, 0.6), 1.5)
	for k: int in 3:
		GkDraw.ellipse(self, pts[0].lerp(pts[1], 0.2 + 0.3 * k), 5.0, 3.5, Color("f08a2e"), 1.5)


func _shadow(rx: float, ry: float) -> void:
	GkDraw.ellipse(self, Vector2(0, -ry * 0.3), rx, ry, Color(0, 0, 0, 0.16))
