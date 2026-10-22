class_name BkEffetsRendu
extends Node2D
## Rendu des effets communs (GDD-BLACKOUT.md §4.5), séparé des règles (BkEffets) : placeholders dessinés
## par le code, posés sur n'importe quel sprite.
##
## | Effet      | Rendu                                                                 |
## | figé       | contour bleu clair, petites étoiles                                   |
## | renversé   | sprite couché (rotation 90°), étoiles                                 |
## | collé      | flaque de résine sous les pieds                                       |
## | ralenti    | traits bleus derrière, sprite qui oscille                             |
## | révélé     | contour lumineux par-dessus les murs, pour le chasseur (ce calque)    |
## | inversé    | plumes qui tournent au-dessus de la tête                              |
## | aveuglé    | écran noir ou bleu d'eau, silhouette du joueur seule (HUD, `ecran`)   |
## | tracté     | ligne tendue vers le point visé, poussière de glissade                |
## | insensible | halo doré                                                            |
## | invisible  | sprite à 30 % pour son joueur, rien pour les autres                   |
## | rapide     | traits de vitesse jaunes derrière (bonus)                             |
##
## Une instance de cette classe est le calque des révélés (calque du monde non assombri, par-dessus les
## murs) ; le reste est fait par des fonctions statiques appelées par BkActor, BkPerso et BkHud.

const C_BLEU_CLAIR: Color = Color("9fe2ff")
const C_REVELE: Color = Color("6ff0ff")
const C_RESINE: Color = Color("c98a1e")
const C_OR: Color = Color("ffd34a")
const C_EAU: Color = Color("1d4f8a")
## Libellés des effets (planche de QA, `--bk-qa-etiquettes`).
const NOMS: Dictionary = {"fige": "figé", "renverse": "renversé", "colle": "collé", "ralenti": "ralenti",
	"revele": "révélé", "inverse": "inversé", "aveugle": "aveuglé", "tracte": "tracté",
	"insensible": "insensible", "invisible": "invisible", "rapide": "rapide"}
const CONTOUR_SHADER: String = """shader_type canvas_item;
render_mode unshaded;
uniform vec4 contour : source_color;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float bord = 0.0;
	if (c.a < 0.5) {
		bord = max(max(texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a, texture(TEXTURE, UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a),
			max(texture(TEXTURE, UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y)).a, texture(TEXTURE, UV - vec2(0.0, TEXTURE_PIXEL_SIZE.y)).a));
	}
	COLOR = c.a >= 0.5 ? c * COLOR : vec4(contour.rgb, contour.a * step(0.5, bord));
}
"""

## QA : tout montrer (révélés et invisibles vus de tous) et nommer les effets sous les pieds.
static var qa: bool = false
static var _contours: Dictionary = {}

var game: BkGame


## Matériau « sprite + contour d'un pixel » de la couleur `c` (mis en cache).
static func contour(c: Color) -> ShaderMaterial:
	var key: String = c.to_html()
	if not _contours.has(key):
		var sh: Shader = Shader.new()
		sh.code = CONTOUR_SHADER
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("contour", c)
		_contours[key] = m
	return _contours[key]


static func _t() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## Pose du sprite selon les effets (BkPerso) : {modulate, rotation, decalage, material (ou null)}.
## `moi` : le joueur local regarde son propre perso.
static func pose(a: BkActor, moi: bool) -> Dictionary:
	var out: Dictionary = {"modulate": Color.WHITE, "rotation": 0.0, "decalage": Vector2.ZERO, "material": null}
	if a.effets.is_empty():
		return out
	if BkEffets.actif(a, "fige"):
		out["modulate"] = Color(0.75, 0.9, 1.0)
		out["material"] = contour(C_BLEU_CLAIR)
	if BkEffets.actif(a, "renverse"):
		out["rotation"] = -PI * 0.5 * (1.0 if cos(a.look) >= 0.0 else -1.0)
	if BkEffets.actif(a, "ralenti"):
		out["decalage"] = Vector2(roundf(sin(_t() * 14.0) * 1.5), 0)
	if BkEffets.actif(a, "invisible") and (moi or qa):
		var m: Color = out["modulate"]
		out["modulate"] = Color(m, BkRules.f("effet_invisible_alpha"))
	return out


## Dessin des effets sur l'acteur (repère de l'acteur, sous et autour du sprite). Appelé par BkActor._draw.
static func dessine(a: BkActor) -> void:
	if a.effets.is_empty():
		return
	var t: float = BkRules.f("tile_px")
	var fy: float = a.feet_dy()
	var top: float = a.name_y()
	var face: float = 1.0 if cos(a.look) >= 0.0 else -1.0
	var now: float = _t()
	if BkEffets.actif(a, "colle"):
		BkDraw.ellipse(a, Vector2(0, fy), roundf(t * 0.38), roundf(t * 0.14), Color(C_RESINE, 0.85))
		BkDraw.ellipse(a, Vector2(-3, fy - 1), roundf(t * 0.12), 1.5, Color("f2c766"))
	if BkEffets.actif(a, "insensible"):
		var k: float = 0.6 + 0.4 * sin(now * 6.0)
		var ring: PackedVector2Array = BkDraw.ellipse_points(Vector2(0, fy - t * 0.45), t * 0.42, t * 0.62, 24)
		ring.append(ring[0])
		a.draw_polyline(ring, Color(C_OR, 0.5 + 0.4 * k), 2.0)
		BkDraw.ellipse(a, Vector2(0, fy), roundf(t * 0.4), roundf(t * 0.13), Color(C_OR, 0.3))
	if BkEffets.actif(a, "ralenti"):
		for i: int in 3:
			var y: float = roundf(fy - t * (0.75 - 0.22 * i))
			var x0: float = roundf(-face * (t * 0.3 + fmod(now * 8.0 + i, 3.0)))
			a.draw_line(Vector2(x0, y), Vector2(x0 - face * t * 0.3, y), Color("4aa3ff"), 1.0)
	if BkEffets.actif(a, "rapide"):
		for i2: int in 3:
			var y2: float = roundf(fy - t * (0.7 - 0.2 * i2))
			var x2: float = roundf(-face * (t * 0.3 + fmod(now * 12.0 + i2, 3.0)))
			a.draw_line(Vector2(x2, y2), Vector2(x2 - face * t * 0.25, y2), C_OR, 1.0)
	if BkEffets.actif(a, "tracte"):
		var vers: Variant = BkEffets.params(a, "tracte").get("vers", null)
		if vers is Vector2:
			var v: Vector2 = (vers as Vector2) - a.position
			# Corde tendue, point par point (pixel art).
			var bout: Vector2 = v.limit_length(t * 4.0)
			var n: int = int(bout.length() / 2.0)
			for k: int in n:
				var cp: Vector2 = (bout * float(k) / float(maxi(n, 1)) + Vector2(0, fy - t * 0.5)).round()
				a.draw_rect(Rect2(cp, Vector2(1, 1)), Color("f0e6c8") if k % 3 != 2 else Color("b89a5a"))
			var back: Vector2 = -v.normalized()
			for i3: int in 3:
				var p: Vector2 = (back * (t * 0.3 + i3 * 4.0) + Vector2(i3 * 2 - 2, fy)).round()
				a.draw_rect(Rect2(p, Vector2(2, 1)), Color(0.9, 0.85, 0.7, 0.7))
	# Au-dessus de la tête : étoiles (figé, renversé), plumes (inversé), nuage (aveuglé), œil (révélé).
	# Au-dessus du pseudo : le sprite, dessiné par-dessus l'acteur, cacherait le reste.
	var tete: Vector2 = Vector2(0, top - 12)
	if BkEffets.actif(a, "fige") or BkEffets.actif(a, "renverse"):
		for i4: int in 3:
			var ang: float = now * 4.0 + TAU * i4 / 3.0
			var sp: Vector2 = (tete + Vector2(cos(ang) * t * 0.32, sin(ang) * t * 0.1)).round()
			var col: Color = C_BLEU_CLAIR if BkEffets.actif(a, "fige") else C_OR
			a.draw_rect(Rect2(sp + Vector2(-1, 0), Vector2(3, 1)), col)
			a.draw_rect(Rect2(sp + Vector2(0, -1), Vector2(1, 3)), col)
	if BkEffets.actif(a, "inverse"):
		for i5: int in 3:
			var ang2: float = -now * 5.0 + TAU * i5 / 3.0
			var fp: Vector2 = (tete + Vector2(cos(ang2) * t * 0.34, sin(ang2) * t * 0.12 - 3.0)).round()
			a.draw_rect(Rect2(fp, Vector2(4, 1)), Color.WHITE)
			a.draw_rect(Rect2(fp + Vector2(4, 0), Vector2(1, 1)), Color("aab4c0"))
	if BkEffets.actif(a, "aveugle"):
		var eau: bool = str(BkEffets.params(a, "aveugle").get("masque", "noir")) == "eau"
		var nc: Color = Color(C_EAU, 0.9) if eau else Color(0.05, 0.05, 0.08, 0.9)
		BkDraw.ellipse(a, tete + Vector2(2, 0), 7, 4, nc)
		BkDraw.ellipse(a, tete + Vector2(-4, -1), 5, 3, nc)
		a.draw_rect(Rect2(tete + Vector2(-6, 4), Vector2(1, 2)), nc)
		a.draw_rect(Rect2(tete + Vector2(3, 5), Vector2(1, 2)), nc)
	if BkEffets.actif(a, "revele"):
		var k2: float = 0.5 + 0.5 * sin(now * 8.0)
		a.draw_arc(Vector2(0, fy - t * 0.5), t * 0.55, 0, TAU, 20, Color(C_REVELE, 0.35 + 0.4 * k2), 1.0)
	if qa:
		var noms: PackedStringArray = []
		for type: Variant in a.effets:
			noms.append(str(NOMS.get(type, type)))
		BkDraw.texte(a, Vector2(0, fy + 12), " ".join(noms), 8, Color("ffd34a"), 2, 120.0)


## Écran du joueur local aveuglé (HUD) : noir ou bleu d'eau, sa silhouette seule par-dessus.
static func ecran(hud: Control, g: BkGame) -> void:
	var me: BkActor = g.local
	if me == null or not BkEffets.actif(me, "aveugle") or me.perso == null:
		return
	var eau: bool = str(BkEffets.params(me, "aveugle").get("masque", "noir")) == "eau"
	hud.draw_rect(Rect2(Vector2.ZERO, hud.size), Color(C_EAU, 0.97) if eau else Color(0.01, 0.01, 0.02, 0.98))
	_sprite(hud, me.perso, g.get_viewport().get_canvas_transform() * me.perso.global_transform, null)
	hud.draw_set_transform_matrix(Transform2D.IDENTITY)


## Dessine l'image courante d'un perso avec la transformation `xf`.
static func _sprite(ci: CanvasItem, p: BkPerso, xf: Transform2D, _mat: Material) -> void:
	if p.texture == null:
		return
	ci.draw_set_transform_matrix(xf)
	var r: Rect2 = p.region_rect
	var dst: Rect2 = Rect2(Vector2.ZERO, Vector2(-r.size.x if p.flip_h else r.size.x, r.size.y))
	ci.draw_texture_rect_region(p.texture, dst, r)


## Petite icône ronde de famille de coup (annonce, bouton, versus) : centre `c`, rayon `r`.
static func icone(ci: CanvasItem, c: Vector2, r: float, famille: String, alpha: float = 1.0) -> void:
	var ink: Color = Color(BkDraw.INK, alpha)
	var fond: Color = Color(1, 1, 1, alpha)
	var col: Color = Color(Color("e8392c"), alpha)
	ci.draw_circle(c, r + 1.0, ink)
	ci.draw_circle(c, r, fond)
	var w: float = maxf(1.0, r * 0.22)
	match famille:
		"deplacement":
			# Saut : arc et flèche.
			ci.draw_arc(c + Vector2(0, r * 0.35), r * 0.6, PI * 1.05, PI * 1.95, 8, col, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.7, r * 0.1), c + Vector2(r * 0.3, r * 0.2),
				c + Vector2(r * 0.6, r * 0.55)]), col)
		"revele":
			# Œil.
			BkDraw.ellipse(ci, c, r * 0.7, r * 0.4, col)
			ci.draw_circle(c, r * 0.22, fond)
		"lance":
			ci.draw_circle(c + Vector2(r * 0.25, 0), r * 0.32, col)
			ci.draw_line(c + Vector2(-r * 0.7, 0), c + Vector2(-r * 0.05, 0), col, w)
		"zone":
			ci.draw_circle(c, r * 0.18, col)
			ci.draw_arc(c, r * 0.6, 0, TAU, 16, col, w)
		"pose":
			ci.draw_rect(Rect2(c - Vector2(r * 0.45, r * 0.35), Vector2(r * 0.9, r * 0.7)), col)
		"reflexe":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.15, -r * 0.75), c + Vector2(-r * 0.35, r * 0.1),
				c + Vector2(0, r * 0.1), c + Vector2(-r * 0.15, r * 0.75), c + Vector2(r * 0.4, -r * 0.1),
				c + Vector2(0, -r * 0.1)]), col)
		_:
			ci.draw_circle(c, r * 0.25, col)


# ---------------------------------------------------------------- calque des révélés

func _process(_dt: float) -> void:
	queue_redraw()


## Révélés (GDD §4.5) : vus du chasseur à travers les murs, sprite et contour lumineux qui pulse,
## par-dessus le décor et la nuit.
func _draw() -> void:
	if game == null or game.local == null:
		return
	if game.local != game.hunter and not qa:
		return
	var k: float = 0.55 + 0.45 * sin(_t() * 7.0)
	material = contour(Color(C_REVELE.r, C_REVELE.g, C_REVELE.b, 1.0))
	for a: BkActor in game.actors:
		if a == game.local or not BkEffets.actif(a, "revele") or a.role != BkActor.Role.HIDER or a.inside():
			continue
		if a.perso == null:
			continue
		_sprite(self, a.perso, a.perso.global_transform, null)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_arc(a.position + Vector2(0, a.feet_dy() - BkRules.f("tile_px") * 0.5), BkRules.f("tile_px") * 0.6, 0, TAU, 24,
			Color(C_REVELE, k), 1.0)
