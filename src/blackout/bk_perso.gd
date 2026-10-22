class_name BkPerso
extends Sprite2D
## Le perso dessiné d'un acteur, en pixel art 32 px (GDD-BLACKOUT.md §8.1, §9) : planches de
## assets/blackout/persos/<id>/px32/ (`<élément>_sheet.png` en bande horizontale, `animations.json` :
## images, fps et boucle par élément ; `set.json` : canevas et ligne des pieds). De profil vers la
## droite, miroir pour la gauche, dessiné pixel pour pixel (aucune mise à l'échelle).
## Un élément ou un perso sans planche prend une silhouette de repli (capsule de la couleur du perso,
## son initiale), au même format : case de 64×64, pieds à y = 60. Les vraies planches, quand elles
## arrivent, sont prises automatiquement (rien à changer dans le code).
## L'animation suit l'état de l'acteur ; les gestes ponctuels (cachette, trouvé) sont demandés par la
## partie via `play_once`.

const DIR: String = "res://assets/blackout/persos/%s/px32/"
## Éléments d'un perso (GDD §8.1) ; `lift` absent : envol fait par le code (clignote en montant).
const ELEMENTS: PackedStringArray = ["profile", "idle", "idle_long", "run", "jump_hide", "ghost", "lift"]
## Case de repli et ligne des pieds (GDD §8.1 : case de 64×64, pieds à y = 60).
const CASE_PX: int = 64
const PIEDS_Y: int = 60
## Silhouette de repli : largeur et hauteur de la capsule (px), images et cadence par élément.
const CAPSULE_L: int = 12
const CAPSULE_H: int = 30
const REPLI: Dictionary = {"profile": [1, 1.0, false], "idle": [2, 3.0, true], "idle_long": [4, 4.0, true],
	"run": [4, 12.0, true], "jump_hide": [5, 12.0, false], "ghost": [4, 6.0, true]}
## Vitesse sous laquelle un acteur est immobile (px/s).
const IMMOBILE: float = 5.0

static var _cache: Dictionary = {}     # "id/élément" → {tex, n, fps, loop, cell, feet}

var actor: BkActor
var _anim: String = ""
var _t: float = 0.0
var _once: String = ""
var _once_t: float = 0.0
var _reverse: bool = false
var _idle_t: float = 0.0
## Hauteur d'envol (px) : l'acteur dessine son ombre en conséquence.
var hover_lift: float = 0.0


## Hauteur d'un perso dans le monde (px) : perso_hauteur cases.
static func hauteur_px() -> float:
	return BkRules.f("perso_hauteur") * BkRules.f("tile_px")


## Tout perso du roster est jouable : sans planches, il a sa silhouette de repli.
static func available(_character: String) -> bool:
	return true


## Vrai si le perso a ses planches px32 (au moins l'idle).
static func has_sheets(character: String) -> bool:
	return ResourceLoader.exists((DIR % character) + "idle_sheet.png")


## Couleur propre au perso (rules.json → perso_couleurs), pour la silhouette de repli.
static func couleur(character: String) -> Color:
	var cs: Dictionary = BkRules.data().get("perso_couleurs", {})
	return Color(str(cs.get(character, "#9aa1ad")))


## Données d'un élément : planche livrée, sinon silhouette de repli ({} pour `lift` sans planche).
static func element(character: String, el: String) -> Dictionary:
	var key: String = character + "/" + el
	if _cache.has(key):
		return _cache[key]
	var d: Dictionary = _planche(character, el)
	if d.is_empty() and REPLI.has(el):
		d = _repli(character, el)
	_cache[key] = d
	return d


## Planche livrée : bande horizontale d'images carrées (ou de la taille du canevas de set.json).
static func _planche(character: String, el: String) -> Dictionary:
	var dir: String = DIR % character
	var path: String = dir + el + "_sheet.png"
	if el == "profile" and not ResourceLoader.exists(path):
		path = dir + "profile_00.png"
	if not ResourceLoader.exists(path):
		return {}
	var tex: Texture2D = load(path)
	var anims: Dictionary = _json(dir + "animations.json")
	var infos: Dictionary = _json(dir + "set.json")
	var info: Dictionary = anims.get(el, (infos.get("elements", {}) as Dictionary).get(el, {}))
	var canvas: Array = infos.get("canvas", [tex.get_height(), tex.get_height()])
	var cell: Vector2 = Vector2(float(canvas[0]), float(canvas[1]))
	var n: int = int(info.get("count", info.get("frames", maxi(1, int(tex.get_width() / cell.x)))))
	var feet_y: float = float(infos.get("feet_y", roundf(cell.y * float(PIEDS_Y) / float(CASE_PX))))
	return {"tex": tex, "n": maxi(1, n), "fps": maxf(0.1, float(info.get("fps", 8.0))),
		"loop": bool(info.get("loop", el != "jump_hide" and el != "profile" and el != "lift")),
		"cell": cell, "feet": Vector2(floorf(cell.x * 0.5), feet_y)}


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## Silhouette de repli : capsule de la couleur du perso, plus sombre au bord, un œil côté droit et
## l'initiale du perso sur le ventre. Une image par pose (rebond, course, saut, fantôme ondulant).
static func _repli(character: String, el: String) -> Dictionary:
	var spec: Array = REPLI[el]
	var n: int = int(spec[0])
	var img: Image = Image.create(CASE_PX * n, CASE_PX, false, Image.FORMAT_RGBA8)
	var col: Color = couleur(character)
	for f: int in n:
		var dy: int = 0
		var squash: int = 0
		var lean: int = 0
		var legs: int = -1
		match el:
			"idle":
				dy = f
			"idle_long":
				lean = [0, 1, 0, -1][f]
			"run":
				dy = -(f % 2)
				legs = f % 2
			"jump_hide":
				dy = [0, -4, -8, -6, -2][f]
				squash = [3, 0, -2, 0, 4][f]
		_capsule(img, f * CASE_PX, dy, squash, lean, legs, col, character, el == "ghost", f)
	return {"tex": ImageTexture.create_from_image(img), "n": n, "fps": float(spec[1]), "loop": bool(spec[2]),
		"cell": Vector2(CASE_PX, CASE_PX), "feet": Vector2(CASE_PX / 2, PIEDS_Y), "repli": true}


static func _capsule(img: Image, ox: int, dy: int, squash: int, lean: int, legs: int, col: Color,
		character: String, ghost: bool, f: int) -> void:
	var w: int = CAPSULE_L + squash
	var h: int = CAPSULE_H - squash
	var x0: int = ox + CASE_PX / 2 - w / 2
	var y1: int = PIEDS_Y + dy                    # bas du corps (pieds)
	var y0: int = y1 - h
	var bord: Color = col.darkened(0.45)
	var r: float = float(w) * 0.5
	for y: int in range(y0, y1):
		var shift: int = roundi(float(lean) * float(y1 - y) / float(h))
		for x: int in range(x0, x0 + w):
			# Coins arrondis en haut (tête) et en bas.
			var cx: float = float(x - x0) + 0.5 - r
			var top: float = float(y - y0) + 0.5
			var bottom: float = float(y1 - y) - 0.5
			if top < r and cx * cx + (r - top) * (r - top) > r * r:
				continue
			if not ghost and bottom < 2.0 and absf(cx) > r - 1.5:
				continue
			if ghost and bottom < 3.0 and (x + f + ox / CASE_PX) % 3 == 0:
				continue                              # bas du fantôme ondulant
			var edge: bool = absf(cx) > r - 1.0 or top < 1.0 or bottom < 1.0
			var c: Color = bord if edge else col
			if ghost:
				c = Color(c.lerp(Color.WHITE, 0.55), 0.85)
			img.set_pixel(x + shift, y, c)
	# Œil (profil vers la droite) et initiale.
	var eye: Vector2i = Vector2i(x0 + w - 4, y0 + 5)
	img.set_pixel(eye.x, eye.y, BkDraw.INK)
	img.set_pixel(eye.x, eye.y + 1, BkDraw.INK)
	var ink: Color = BkDraw.INK if col.get_luminance() > 0.55 else Color.WHITE
	BkDraw.glyphe(img, character.substr(0, 1), Vector2i(x0 + w / 2 - 1, y0 + 12), Color(ink, 0.9))
	# Jambes de course : un pied en avant, l'autre en arrière.
	if legs >= 0 and not ghost:
		var lx: int = x0 + w / 2
		for k: int in 2:
			var px: int = lx + (2 if (k == legs) else -3)
			img.set_pixel(px, y1, bord)
			img.set_pixel(px + 1, y1, bord)


func setup(a: BkActor) -> void:
	actor = a
	centered = false
	region_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Joue un geste une fois (hide_in, hide_out, found), puis reprend l'état. Sans élément : rien.
func play_once(anim: String) -> void:
	if length(anim) <= 0.0:
		return
	_once = anim
	_once_t = 0.0


## Durée d'un geste ponctuel (s), 0 s'il n'existe pas.
func length(anim: String) -> float:
	match anim:
		"hide_in", "hide_out":
			var d: Dictionary = element(actor.character, "jump_hide")
			return float(d["n"]) / float(d["fps"])
		"found":
			return BkRules.f("lift_s")
	return 0.0


## Élément de l'état de l'acteur (hors geste ponctuel).
func _state_anim(dt: float) -> String:
	var a: BkActor = actor
	if a.role == BkActor.Role.GHOST or a.role == BkActor.Role.OUT:
		return "ghost"
	if a.velocity.length() > IMMOBILE:
		_idle_t = 0.0
		return "run"
	_idle_t += dt
	if _idle_t >= BkRules.f("idle_long_apres") and a.end_pose == "":
		return "idle_long"
	return "idle"


func _process(dt: float) -> void:
	if actor == null:
		return
	var el: String = ""
	var k_lift: float = -1.0
	if _once != "":
		_once_t += dt
		if _once_t >= length(_once):
			_once = ""
		else:
			match _once:
				"hide_in", "hide_out":
					el = "jump_hide"
					_reverse = _once == "hide_out"
				"found":
					el = "lift"
					k_lift = _once_t / maxf(BkRules.f("lift_s"), 0.01)
	if el == "":
		el = _state_anim(dt)
		_reverse = false
	var d: Dictionary = element(actor.character, el)
	if d.is_empty():
		d = element(actor.character, "idle")      # pas de planche lift : l'idle s'envole
	if el != _anim:
		_anim = el
		_t = 0.0
	var rate: float = 1.0
	if el == "run":
		rate = clampf(actor.velocity.length() / maxf(BkRules.px("speed_hider"), 1.0), 0.6, 1.5)
	_t += dt * rate
	var n: int = int(d["n"])
	var f: int = int(_t * float(d["fps"]))
	f = f % n if bool(d["loop"]) else mini(f, n - 1)
	if _reverse:
		f = n - 1 - f
	var cell: Vector2 = d["cell"]
	texture = d["tex"]
	region_rect = Rect2(Vector2(cell.x * float(f), 0.0), cell)
	var face: float = 1.0 if cos(actor.look) >= 0.0 else -1.0
	flip_h = face < 0.0
	var feet: Vector2 = d["feet"]
	var fx: float = cell.x - feet.x - 1.0 if flip_h else feet.x
	# Envol du chassé trouvé : il monte en clignotant (GDD §3.6).
	hover_lift = 0.0
	var ghost: bool = (actor.role == BkActor.Role.GHOST or actor.role == BkActor.Role.OUT) and k_lift < 0.0
	if k_lift >= 0.0:
		hover_lift = BkRules.f("lift_px") * k_lift
	modulate.a = BkRules.f("fantome_alpha") if ghost else 1.0
	var blink: bool = k_lift >= 0.0 and fmod(_once_t * BkRules.f("lift_clignote_hz"), 1.0) < 0.5
	visible = actor.draw_2d and (actor.shown or _once != "") and not actor.inside() and not blink
	position = (Vector2(-fx, -feet.y + actor.feet_dy() - hover_lift) + _pop_offset()).round()


## Sortie de cachette : décalage de dessin qui part de la cachette et rejoint l'acteur (posé sur
## la case voisine) en sautant un peu, pendant `cachette_out_s`.
func _pop_offset() -> Vector2:
	if actor.pop_left <= 0.0:
		return Vector2.ZERO
	var p: float = 1.0 - clampf(actor.pop_left / maxf(BkRules.f("cachette_out_s"), 0.01), 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - p, 3.0)
	return (actor.pop_from - actor.position) * (1.0 - e) + Vector2(0, -BkRules.f("tile_px") * 0.3 * sin(p * PI))
