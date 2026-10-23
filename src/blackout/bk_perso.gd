class_name BkPerso
extends Sprite2D
## Le perso dessiné d'un acteur, en pixel art 32 px (GDD-BLACKOUT.md §8.1, §9) : planches de
## assets/blackout/persos/<id>/px32/, ou pnj/, animaux/, boss/ (FAMILLES) : `<élément>_sheet.png` en
## bande horizontale, `animations.json` : images, fps et boucle par élément ; `set.json` : canevas et
## ligne des pieds. De profil vers la droite, miroir pour la gauche, dessiné pixel pour pixel (aucune mise à l'échelle).
## Un élément ou un perso sans planche prend une silhouette de repli (capsule de la couleur du perso,
## son initiale), au même format : case de 64×64, pieds à y = 60. Les vraies planches, quand elles
## arrivent, sont prises automatiquement (rien à changer dans le code).
## L'animation suit l'état de l'acteur (GDD §8.1) : course, attente, attente longue ; effets subis
## (§4.5 : etourdi, renverse, colle, ralenti, aveugle, tracte) ; interagir pendant une fouille ou un
## disjoncteur ; victoire et defaite en fin de round ; fantôme commun (assets/blackout/fantome/, appear
## puis float à l'arrêt et advance en mouvement). Les gestes ponctuels (cachette, trouvé, lancement d'un
## coup `cast`, sursaut d'un PNJ) sont demandés par la partie via `play_once`.
## Élément manquant dans un set : élément voisin (VOISINS), sinon silhouette de repli, jamais d'image vide.

const DIR: String = "res://assets/blackout/persos/%s/px32/"
## Familles de sets, cherchées dans cet ordre (même format pixelforge) : persos jouables, PNJ humains et
## animaux (§3.8, §8.4), boss (§5, §8.3 : 64 px dans une case de 128), fantôme commun (§3.6, §8.1). Un set
## peut être un placeholder (set.json → "placeholder": true, tools/blackout/placeholders_sets.py) : chargé pareil.
const FAMILLES: PackedStringArray = ["persos", "pnj", "animaux", "boss", "fantome"]
const RACINE: String = "res://assets/blackout/%s/%s/px32/"
## Éléments d'un perso (GDD §8.1). Plus d'élément ghost par perso : le fantôme est commun (FANTOME).
const ELEMENTS: PackedStringArray = ["profile", "portrait", "idle", "idle_long", "run", "jump_hide", "lift",
	"interagir", "victoire", "defaite", "etourdi", "renverse", "colle", "ralenti", "aveugle", "tracte",
	"cast_chasse", "cast_chasseur"]
## Fantôme commun à tous les persos (GDD §8.1, carte #646) : son set et ses éléments.
const FANTOME: String = "fantome"
const ELEMENTS_FANTOME: PackedStringArray = ["appear", "float", "advance"]
## Effet subi → animation du perso (GDD §4.5), dans l'ordre de priorité quand plusieurs effets se cumulent.
const EFFETS_ANIM: Array = [["renverse", "renverse"], ["fige", "etourdi"], ["tracte", "tracte"],
	["colle", "colle"], ["aveugle", "aveugle"], ["inverse", "etourdi"], ["ralenti", "ralenti"]]
## Animation d'effet sans boucle : jouée au plus lentement à EFFET_RATE_MIN pour couvrir l'effet, puis
## tenue sur sa dernière image.
const EFFET_RATE_MIN: float = 0.4
## Au-delà de cette durée (s), l'effet est maintenu par la QA : animation en boucle.
const EFFET_QA_S: float = 1.0e5
## Élément manquant dans un set → éléments voisins essayés dans l'ordre (planches livrées), puis la
## silhouette de repli de l'élément ou d'un voisin, puis l'idle.
const VOISINS: Dictionary = {"portrait": ["profile"], "idle": ["profile"], "idle_long": ["idle"],
	"run": ["marcher", "idle"], "jump_hide": ["idle"], "interagir": ["idle_long", "idle"],
	"victoire": ["idle_long", "idle"], "defaite": ["idle"], "etourdi": ["idle"], "renverse": ["etourdi", "idle"],
	"colle": ["etourdi", "idle"], "ralenti": ["marcher", "run"], "aveugle": ["etourdi", "idle"],
	"tracte": ["idle"], "cast_chasse": ["cast_chasseur", "idle_long", "idle"],
	"cast_chasseur": ["cast_chasse", "idle_long", "idle"], "marcher": ["run", "idle"], "sursaut": ["idle"],
	"appear": ["float"], "float": ["advance", "profile"], "advance": ["float", "profile"]}
## Case de repli et ligne des pieds (GDD §8.1 : case de 64×64, pieds à y = 60).
const CASE_PX: int = 64
const PIEDS_Y: int = 60
const MONTEE_MIN_PX: int = 3      # écart de hauteur des pieds dans la planche au-delà duquel elle « monte »
## Silhouette de repli : largeur et hauteur de la capsule (px), images et cadence par élément.
const CAPSULE_L: int = 12
const CAPSULE_H: int = 30
const REPLI: Dictionary = {"profile": [1, 1.0, false], "idle": [2, 3.0, true], "idle_long": [4, 4.0, true],
	"run": [4, 12.0, true], "jump_hide": [5, 12.0, false], "ghost": [4, 6.0, true]}
## Vitesse sous laquelle un acteur est immobile (px/s).
const IMMOBILE: float = 5.0

static var _cache: Dictionary = {}     # "id/élément" → {tex, n, fps, loop, cell, feet}
static var _dossiers: Dictionary = {}  # id → dossier px32 du set
## Silhouette sombre (vue du chasseur, chassé dans l'ombre, GDD §3.2) : le sprite en aplat de
## silhouette_couleur, un liseré plus clair d'un pixel autour pour qu'elle se détache du sol de nuit.
static var _silhouette: ShaderMaterial
const SILHOUETTE_SHADER: String = """shader_type canvas_item;
render_mode unshaded;
uniform vec4 teinte : source_color;
uniform vec4 lisere : source_color;
void fragment() {
	float a = texture(TEXTURE, UV).a;
	float bord = 0.0;
	if (a < 0.5) {
		bord = max(max(texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a, texture(TEXTURE, UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a),
			max(texture(TEXTURE, UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y)).a, texture(TEXTURE, UV - vec2(0.0, TEXTURE_PIXEL_SIZE.y)).a));
	}
	COLOR = a >= 0.5 ? vec4(teinte.rgb, teinte.a) : vec4(lisere.rgb, lisere.a * step(0.5, bord));
}
"""

var actor: BkActor
var _anim: String = ""
var _t: float = 0.0
var _once: String = ""
var _once_t: float = 0.0
var _once_el: String = ""
var _once_len: float = 0.0
var _etait_fantome: bool = false
var _appear_attendu: bool = false
var _reverse: bool = false
var _idle_t: float = 0.0
## Hauteur d'envol (px) : l'acteur dessine son ombre en conséquence.
var hover_lift: float = 0.0


## Hauteur d'un perso dans le monde (px) : perso_hauteur cases.
static func hauteur_px() -> float:
	return BkRules.f("perso_hauteur") * BkRules.f("tile_px")


static func silhouette_material() -> ShaderMaterial:
	if _silhouette == null:
		var sh: Shader = Shader.new()
		sh.code = SILHOUETTE_SHADER
		_silhouette = ShaderMaterial.new()
		_silhouette.shader = sh
		var c: Color = BkRules.couleur("silhouette_couleur", Color("10121f"))
		_silhouette.set_shader_parameter("teinte", c)
		_silhouette.set_shader_parameter("lisere", Color(c.lightened(0.35), 0.8))
	return _silhouette


## Tout perso du roster est jouable : sans planches, il a sa silhouette de repli.
static func available(_character: String) -> bool:
	return true


## Vrai si le perso a ses planches px32 (au moins l'idle).
static func has_sheets(character: String) -> bool:
	return ResourceLoader.exists(dossier(character) + "idle_sheet.png")


## Dossier px32 du set d'un id (perso, PNJ, animal ou boss) ; celui des persos si aucun n'existe.
static func dossier(character: String) -> String:
	if _dossiers.has(character):
		return _dossiers[character]
	var d: String = DIR % character
	for fam: String in FAMILLES:
		var c: String = RACINE % [fam, character]
		if FileAccess.file_exists(c + "set.json") or ResourceLoader.exists(c + "idle_sheet.png"):
			d = c
			break
	_dossiers[character] = d
	return d


## Vrai si le set de cet id est un placeholder en attendant le rendu pixelforge.
static func placeholder(character: String) -> bool:
	return bool(_json(dossier(character) + "set.json").get("placeholder", false))


## Couleur propre au perso (rules.json → perso_couleurs), pour la silhouette de repli.
static func couleur(character: String) -> Color:
	var cs: Dictionary = BkRules.data().get("perso_couleurs", {})
	return Color(str(cs.get(character, "#9aa1ad")))


## Données d'un élément : planche livrée, sinon planche d'un élément voisin (VOISINS, marquée
## « voisin »), sinon silhouette de repli (« repli ») ; {} seulement pour `lift` sans planche (envol
## fait par le code avec l'idle).
static func element(character: String, el: String) -> Dictionary:
	var key: String = character + "/" + el
	if _cache.has(key):
		return _cache[key]
	var d: Dictionary = _planche(character, el)
	if d.is_empty() and el != "lift":
		var voisins: Array = VOISINS.get(el, ["idle"])
		for v: Variant in voisins:
			d = _planche(character, str(v))
			if not d.is_empty():
				d = d.duplicate()
				d["voisin"] = str(v)
				break
		if d.is_empty():
			for r: Variant in [el] + voisins:
				if REPLI.has(str(r)) and str(r) != "ghost":
					d = _repli(character, str(r))
					break
		if d.is_empty():
			d = _repli(character, "idle")
	_cache[key] = d
	return d


## Vrai si le set de `character` a sa propre planche pour `el` (ni voisin ni repli).
static func livre(character: String, el: String) -> bool:
	var d: Dictionary = element(character, el)
	return not d.is_empty() and not d.has("voisin") and not d.has("repli")


## Élément du fantôme commun (appear, float, advance : GDD §8.1, carte #646), le même pour tous ; sans
## set du fantôme, la silhouette fantôme de repli aux couleurs du perso.
static func fantome(character: String, el: String) -> Dictionary:
	var d: Dictionary = element(FANTOME, el)
	if not d.has("repli"):
		return d
	var key: String = character + "/#fantome"
	if not _cache.has(key):
		_cache[key] = _repli(character, "ghost")
	return _cache[key]


## Portrait de trois-quarts (GDD §8.1) : {tex, cell} de sa première image (profil en repli).
static func portrait(character: String) -> Dictionary:
	return element(character, "portrait")


## Portrait réduit à `px` × `px` (HUD, listes), lissé une fois et mis en cache.
static func portrait_tex(character: String, px: int) -> Texture2D:
	var key: String = "%s/#portrait%d" % [character, px]
	if _cache.has(key):
		return _cache[key]["tex"]
	var d: Dictionary = portrait(character)
	var cell: Vector2 = d["cell"]
	var img: Image = (d["tex"] as Texture2D).get_image()
	if img == null:
		return d["tex"]
	if img.is_compressed():
		img.decompress()
	img = img.get_region(Rect2i(0, 0, int(cell.x), int(cell.y)))
	img.convert(Image.FORMAT_RGBA8)
	img.resize(px, px, Image.INTERPOLATE_LANCZOS if px < int(cell.x) else Image.INTERPOLATE_NEAREST)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_cache[key] = {"tex": tex}
	return tex


## Planche livrée : bande horizontale d'images carrées (ou de la taille du canevas de set.json).
static func _planche(character: String, el: String) -> Dictionary:
	var dir: String = dossier(character)
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
		"cell": cell, "feet": Vector2(floorf(cell.x * 0.5), feet_y),
		"monte": (el == "lift" or el == "jump_hide") and _monte(tex, cell, maxi(1, n))}


## La planche monte-t-elle d'elle-même (pieds qui quittent le sol, pixelforge 23/10) ? Le jeu n'ajoute
## alors ni l'envol (lift_px) ni l'arc de sortie de cachette : sinon la montée compte deux fois.
static func _monte(tex: Texture2D, cell: Vector2, n: int) -> bool:
	var img: Image = tex.get_image()
	if img == null:
		return false
	if img.is_compressed():
		img.decompress()
	var bas: Array[int] = []
	for f: int in n:
		var r: Rect2i = img.get_region(Rect2i(int(cell.x) * f, 0, int(cell.x), int(cell.y))).get_used_rect()
		bas.append(r.end.y if r.has_area() else 0)
	return bas.max() - bas.min() >= MONTEE_MIN_PX


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


## Joue un geste une fois puis reprend l'état : hide_in, hide_out, saut (jump_hide), found (lift),
## cast (cast_chasse ou cast_chasseur selon le rôle, GDD §4.6), appear (fantôme commun), ou tout élément
## livré du set (sursaut d'un PNJ). Sans élément : rien.
func play_once(anim: String) -> void:
	var el: String = _element_geste(anim)
	if el == "" or length(anim) <= 0.0:
		return
	_once = anim
	_once_el = el
	_once_t = 0.0
	_once_len = length(anim)


## Élément joué par un geste ponctuel, "" s'il n'en a pas.
func _element_geste(anim: String) -> String:
	match anim:
		"hide_in", "hide_out", "saut":
			return "jump_hide"
		"found":
			return "lift"
		"cast":
			return "cast_chasseur" if actor.role == BkActor.Role.HUNTER else "cast_chasse"
		"appear":
			return "appear"
	return anim if livre(actor.character, anim) else ""


## Durée d'un geste ponctuel (s), 0 s'il n'existe pas.
func length(anim: String) -> float:
	match anim:
		"found":
			return BkRules.f("lift_s")
		"appear":
			var f: Dictionary = fantome(actor.character, "appear")
			return float(f["n"]) / float(f["fps"]) if not f.has("repli") else 0.0
	var el: String = _element_geste(anim)
	if el == "":
		return 0.0
	var d: Dictionary = element(actor.character, el)
	return float(d["n"]) / float(d["fps"])


## Élément en cours (QA, tests) : celui de la dernière image dessinée.
func element_courant() -> String:
	return _anim


func _est_fantome() -> bool:
	return actor.role == BkActor.Role.GHOST or actor.role == BkActor.Role.OUT


## Élément de l'état de l'acteur (hors geste ponctuel) : [élément, cadence, boucle forcée].
func _state_anim(dt: float) -> Array:
	var a: BkActor = actor
	var bouge: bool = a.velocity.length() > IMMOBILE
	if _est_fantome():
		return ["advance" if bouge else "float", 1.0, false]
	# Élément imposé par un cerveau extérieur (PNJ : marcher, activité, fuite).
	if a.anim_impose != "":
		return [a.anim_impose, 1.0, false]
	# Effets subis (GDD §4.5) : l'animation d'effet du perso, la même pour tous.
	if not a.effets.is_empty():
		for paire: Array in EFFETS_ANIM:
			if a.effets.has(paire[0]):
				var el: String = paire[1]
				var d: Dictionary = element(a.character, el)
				var rate: float = 1.0
				var duree: float = float((a.effets[paire[0]] as Dictionary).get("duree", 1.0))
				if not bool(d["loop"]):
					rate = clampf(float(d["n"]) / float(d["fps"]) / maxf(duree, 0.01), EFFET_RATE_MIN, 1.0)
				# Effet maintenu par la QA (BkEffets.force, sans fin) : en boucle, pour le voir en entier.
				return [el, rate, duree >= EFFET_QA_S]
	# Fouille d'une cachette, disjoncteur : interagir, en boucle tant que l'action dure.
	if a.search_left > 0.0 or a.use_left > 0.0:
		return ["interagir", 1.0, true]
	# Fin de round (et avatars du podium) : victoire ou défaite.
	if a.end_pose == "victory":
		return ["victoire", 1.0, true]
	if a.end_pose == "sad":
		return ["defaite", 1.0, true]
	if bouge:
		_idle_t = 0.0
		return ["run", clampf(a.velocity.length() / maxf(BkRules.px("speed_hider"), 1.0), 0.6, 1.5), false]
	_idle_t += dt
	if _idle_t >= BkRules.f("idle_long_apres"):
		return ["idle_long", 1.0, false]
	return ["idle", 1.0, false]


func _process(dt: float) -> void:
	if actor == null:
		return
	# Devenu fantôme : appear (fantôme commun) dès que le geste en cours (envol) est fini.
	var fant: bool = _est_fantome()
	if fant and not _etait_fantome:
		_appear_attendu = true
	_etait_fantome = fant
	if not fant:
		_appear_attendu = false
	var el: String = ""
	var k_lift: float = -1.0
	var rate: float = 1.0
	var boucle: bool = false
	if _once != "":
		_once_t += dt
		if _once_t >= _once_len:
			_once = ""
	if _once == "" and _appear_attendu:
		_appear_attendu = false
		play_once("appear")
	if _once != "":
		el = _once_el
		_reverse = _once == "hide_out"
		if _once == "found":
			k_lift = _once_t / maxf(BkRules.f("lift_s"), 0.01)
	if el == "":
		var st: Array = _state_anim(dt)
		el = st[0]
		rate = st[1]
		boucle = st[2]
		_reverse = false
	var d: Dictionary
	if ELEMENTS_FANTOME.has(el):
		d = fantome(actor.character, el)
	else:
		d = element(actor.character, el)
	if d.is_empty():
		d = element(actor.character, "idle")      # pas de planche lift : l'idle s'envole
	if el != _anim:
		_anim = el
		_t = 0.0
	_t += dt * rate
	var n: int = int(d["n"])
	var f: int = int(_t * float(d["fps"]))
	f = f % n if (bool(d["loop"]) or boucle) else mini(f, n - 1)
	if _reverse:
		f = n - 1 - f
	var cell: Vector2 = d["cell"]
	texture = d["tex"]
	# Effets communs subis (GDD §4.5) : teinte, contour, sprite couché, oscillation (BkEffetsRendu).
	var pose: Dictionary = BkEffetsRendu.pose(actor, actor == _local())
	material = silhouette_material() if actor.silhouette else pose["material"]
	region_rect = Rect2(Vector2(cell.x * float(f), 0.0), cell)
	var face: float = 1.0 if cos(actor.look) >= 0.0 else -1.0
	flip_h = face < 0.0
	var feet: Vector2 = d["feet"]
	var fx: float = cell.x - feet.x - 1.0 if flip_h else feet.x
	# Hauteur : envol du trouvé (il monte en clignotant, GDD §3.6), saut d'un coup spécial.
	hover_lift = actor.saut_px
	var ghost: bool = fant and k_lift < 0.0
	if k_lift >= 0.0 and not bool(d.get("monte", false)):
		hover_lift = maxf(hover_lift, BkRules.f("lift_px") * k_lift)
	modulate = pose["modulate"]
	if ghost:
		modulate.a = BkRules.f("fantome_alpha")
	var blink: bool = k_lift >= 0.0 and fmod(_once_t * BkRules.f("lift_clignote_hz"), 1.0) < 0.5
	visible = actor.draw_2d and (actor.shown or _once != "") and not actor.inside() and not blink
	var pieds: Vector2 = Vector2(0, actor.feet_dy() - hover_lift) + _pop_offset(bool(d.get("monte", false))) + (pose["decalage"] as Vector2)
	rotation = float(pose["rotation"])
	# Le sprite tourne autour de ses pieds (renversé sans planche : couché sur le sol).
	position = (pieds - Vector2(fx, feet.y).rotated(rotation)).round()


## Joueur local de la partie (le perso invisible reste visible à 30 % pour lui seul).
func _local() -> BkActor:
	var g: Node = actor.get_parent().get_parent() if actor.get_parent() != null else null
	return (g as BkGame).local if g is BkGame else null


## Sortie de cachette : décalage de dessin qui part de la cachette et rejoint l'acteur (posé sur
## la case voisine) en sautant un peu, pendant `cachette_out_s`.
func _pop_offset(planche_monte: bool = false) -> Vector2:
	if actor.pop_left <= 0.0:
		return Vector2.ZERO
	var p: float = 1.0 - clampf(actor.pop_left / maxf(BkRules.f("cachette_out_s"), 0.01), 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - p, 3.0)
	var arc: float = 0.0 if planche_monte else BkRules.f("tile_px") * 0.3 * sin(p * PI)
	return (actor.pop_from - actor.position) * (1.0 - e) + Vector2(0, -arc)
