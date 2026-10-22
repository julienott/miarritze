class_name BkLumieres
extends Node2D
## Sources de lumière fixes de la carte, de nuit (GDD-BLACKOUT.md §3.2, §9) : une PointLight2D
## additive par source (zones.json → « lumieres »), ombrée par les murs pleins (occulteurs de BkMap), et
## le dessin des sources (lampadaire, plafonnier, néon) allumées ou éteintes. Une source s'éteint
## quand le disjoncteur de son secteur est coupé (BkGame.source_allumee) et clignote en s'éteignant
## comme en se rallumant. La règle « éclairé / dans l'ombre » est calculée par la partie
## (BkGame.eclaire), pas par la lecture des pixels ; la touche L du debug montre son résultat.

## Texture de lumière : disque de TEX_PX px, bord adouci (lumiere_douceur du rayon).
const TEX_PX: int = 256
## Clignotement : durée d'une alternance (s) et intensité « presque éteinte ».
const CLIGNOTE_PAS: float = 0.07
const CLIGNOTE_BAS: float = 0.15
## Couleurs du dessin des sources (placeholders pixel art).
const C_POTEAU: Color = Color("2a2e40")
const C_ETEINT: Color = Color("4a4f62")

var game: BkGame
## Par source : lumière, intensité courante (0 → 1), allumée voulue, clignotement restant (s).
var _lights: Array[PointLight2D] = []
var _k: Array[float] = []
var _on: Array[bool] = []
var _flick: Array[float] = []
## Debug (touche L) : zones éclairées selon la règle, case par case (recalculées quand une source
## change d'état).
var debug: bool = false
var _cases_eclairees: Array[Vector2i] = []
var _cases_a_jour: bool = false

static var _tex: Texture2D


func setup(g: BkGame) -> void:
	game = g
	for i: int in game.map.lumieres.size():
		var s: Dictionary = game.map.lumieres[i]
		var l: PointLight2D = PointLight2D.new()
		l.texture = texture()
		l.texture_scale = float(s["rayon"]) * game.map.tile * 2.0 / float(TEX_PX)
		l.position = centre(game.map, s)
		l.color = couleur(s)
		l.energy = BkRules.f("lumiere_energie")
		l.blend_mode = Light2D.BLEND_MODE_ADD
		# Sol, persos et objets debout ; ombres des murs de la grille (comme la vue du chasseur).
		l.range_item_cull_mask = 1 | BkDecor.LIGHT_MASK
		l.shadow_enabled = true
		l.shadow_item_cull_mask = 1
		l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		add_child(l)
		_lights.append(l)
		_k.append(1.0)
		_on.append(true)
		_flick.append(0.0)
	queue_redraw()


## Point d'où part la lumière d'une source (px) : le centre de sa case, collé au mur pour un néon.
static func centre(m: BkMap, s: Dictionary) -> Vector2:
	return m.center(s["pos"]) + Vector2(s["mur"] as Vector2i) * m.tile * 0.4


## Couleur d'une source : la sienne, sinon celle de son type (rules.json → lumiere_couleur_<type>).
static func couleur(s: Dictionary) -> Color:
	var c: Color = s.get("couleur", Color.BLACK)
	if c != Color.BLACK:
		return c
	return BkRules.couleur("lumiere_couleur_" + str(s["type"]), BkRules.couleur("lumiere_couleur_lampadaire", Color("ffc04a")))


## Disque blanc plein jusqu'à (1 − lumiere_douceur) du rayon, puis fondu jusqu'au bord.
static func texture() -> Texture2D:
	if _tex != null:
		return _tex
	var img: Image = Image.create(TEX_PX, TEX_PX, false, Image.FORMAT_RGBA8)
	var r: float = TEX_PX * 0.5 - 1.0
	var plein: float = r * (1.0 - clampf(BkRules.f("lumiere_douceur"), 0.0, 1.0))
	var c: Vector2 = Vector2(TEX_PX, TEX_PX) * 0.5
	for y: int in TEX_PX:
		for x: int in TEX_PX:
			var d: float = (Vector2(x + 0.5, y + 0.5) - c).length()
			var k: float = 1.0 if d <= plein else clampf((r - d) / maxf(r - plein, 1.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, k * k * (3.0 - 2.0 * k)))
	_tex = ImageTexture.create_from_image(img)
	return _tex


## Chaque image : sources allumées ou non (secteurs coupés), clignotement des changements.
func maj(dt: float) -> void:
	var redraw: bool = false
	for i: int in mini(_lights.size(), game.map.lumieres.size()):
		var on: bool = game.source_allumee(game.map.lumieres[i])
		if on != _on[i]:
			_on[i] = on
			_flick[i] = BkRules.f("lumiere_clignote_s")
			_cases_a_jour = false
		var k: float = 1.0 if on else 0.0
		if _flick[i] > 0.0:
			_flick[i] = maxf(0.0, _flick[i] - dt)
			# Alternance vive : la lumière hésite avant de s'éteindre ou de revenir.
			var haut: bool = int(_flick[i] / CLIGNOTE_PAS) % 2 == 0
			k = 1.0 if haut else CLIGNOTE_BAS
		if not is_equal_approx(k, _k[i]):
			_k[i] = k
			redraw = true
		_lights[i].energy = BkRules.f("lumiere_energie") * _k[i]
		_lights[i].enabled = _k[i] > 0.01
	if redraw:
		queue_redraw()


## Intensité dessinée d'une source (0 éteinte → 1 allumée), clignotement compris.
func intensite(i: int) -> float:
	return _k[i] if i < _k.size() else 1.0


func _draw() -> void:
	var t: float = game.map.tile
	for i: int in game.map.lumieres.size():
		var s: Dictionary = game.map.lumieres[i]
		var c: Vector2 = game.map.center(s["pos"]).round()
		var k: float = intensite(i)
		var col: Color = C_ETEINT.lerp(couleur(s).lightened(0.35), k)
		match str(s["type"]):
			"plafonnier":
				# Lampe ronde vue de dessus (pas de poteau dans une maison).
				draw_circle(c, 5.0, BkDraw.INK)
				draw_circle(c, 4.0, col)
				draw_rect(Rect2(c + Vector2(-1, -2), Vector2(2, 1)), Color(1, 1, 1, 0.8 * k))
			"neon":
				# Tube lumineux posé sur le mur : une barre vive à cœur blanc.
				var m: Vector2 = Vector2(s["mur"] as Vector2i)
				var bord: Vector2 = c + m * t * 0.5
				var long: Vector2 = m.orthogonal().abs() * t * 0.36
				var ep: Vector2 = m.abs() * 2.0
				var r: Rect2 = Rect2((bord - long - ep).round(), (long * 2.0 + ep * 2.0).round()).abs()
				draw_rect(r.grow(1), BkDraw.INK)
				draw_rect(r, col)
				if k > 0.5:
					draw_rect(r.grow(-1), Color(1, 1, 1, 0.7 * k))
			_:
				# Lampadaire : socle, poteau, lanterne.
				draw_rect(Rect2(c + Vector2(-3, 4), Vector2(6, 2)), BkDraw.INK)
				draw_rect(Rect2(c + Vector2(-1, -18), Vector2(2, 22)), C_POTEAU)
				draw_rect(Rect2(c + Vector2(-4, -24), Vector2(8, 7)), BkDraw.INK)
				draw_rect(Rect2(c + Vector2(-3, -23), Vector2(6, 5)), col)
				if k > 0.5:
					draw_rect(Rect2(c + Vector2(-1, -22), Vector2(2, 2)), Color(1, 1, 1, 0.9 * k))


## Debug (touche L, dessiné dans le calque non assombri) : cases éclairées selon la règle (jaune pâle),
## rayon de chaque source (trait de sa couleur, gris si elle est éteinte) et son point de départ.
func draw_debug(ci: CanvasItem) -> void:
	if not debug:
		return
	var m: BkMap = game.map
	if not _cases_a_jour:
		_cases_eclairees.clear()
		for y: int in m.height:
			for x: int in m.width:
				var tt: Vector2i = Vector2i(x, y)
				if m.walkable(tt) and game.eclaire(m.center(tt)):
					_cases_eclairees.append(tt)
		_cases_a_jour = true
	for tt: Vector2i in _cases_eclairees:
		ci.draw_rect(Rect2(Vector2(tt) * m.tile, Vector2(m.tile, m.tile)).grow(-2), Color(1, 0.85, 0.3, 0.22))
	for i: int in m.lumieres.size():
		var s: Dictionary = m.lumieres[i]
		var p: Vector2 = centre(m, s)
		var on: bool = game.source_allumee(s)
		var col: Color = couleur(s) if on else Color("8a8f9c")
		ci.draw_arc(p, float(s["rayon"]) * m.tile, 0.0, TAU, 48, col, 1.0)
		ci.draw_circle(p, 2.0, col)
		BkDraw.texte(ci, p + Vector2(0, -float(s["rayon"]) * m.tile - 3.0), "%s %s" % [str(s["secteur"]),
			"" if on else "(éteint)"], 8, col, 2, 120.0)
