class_name BkPerso
extends Sprite2D
## Le perso dessiné d'un acteur, en 2D flat cartoon façon Among Us (docs/GORDEKA_STYLE_2D.md) :
## planches pixelforge (`pf_2d__anim`) dans assets/blackout/persos/<id>/, de profil vers la
## droite (miroir à gauche). La tenue prend la couleur du joueur grâce au masque de tenue.
## L'animation suit l'état de l'acteur ; les gestes ponctuels (piège, détection, trouvé…)
## sont demandés par la partie via `play_once`.
## Mode pantin (`use_pantin`) : le mannequin articulé (BkPantin) remplace les planches ; il sera
## habillé de la garde-robe du perso (docs/GORDEKA_STYLE_2D.md §4).

const DIR: String = "res://assets/blackout/persos/%s/"
## Hauteur du perso à l'écran (px), pieds compris ; ~90 px comme dans Among Us en 720p.
const HEIGHT_PX: float = 88.0
## Hauteur du perso dans une case pixelforge (px), pour l'échelle.
const CELL_PERSO_PX: float = 199.0
const GHOST_ALPHA: float = 0.5
## Hauteur du petit saut quand le perso jaillit de sa cachette (px).
const POP_JUMP_PX: float = 22.0
## Durée visée d'un cycle de déplacement (s) à la vitesse d'un chassé (0,5 s faisait courir, Julien) :
## les planches pixelforge (mouvements Quaternius) durent plus longtemps, on les accélère, et la
## cadence suit la vitesse réelle (piège, chasseur plus rapide) pour que les pieds ne glissent pas.
const BOUNCE_PX: float = 5.0        # hauteur du rebond de marche (px à l'écran)
const SQUASH: float = 0.07          # écrasement vertical au contact du pied
const CYCLE_S: Dictionary = {"walk": 0.85, "run_scared": 0.6, "ghost_move": 1.0}
## Pieds qui glissent (recette Julien, 2026-10-20) : une planche de déplacement qui a son `stride_px`
## (recul du pied posé sur toute la planche, px de case, mesuré par tools/blackout/pieds.py) joue à la
## cadence qui garde le pied posé immobile au sol : planches/s = vitesse réelle / stride. Bornée entre
## RATE_MIN et RATE_MAX × son fps (au-delà, des pas trop courts patinent encore un peu). CYCLE_S en repli.
const RATE_MIN: float = 0.3
const RATE_MAX: float = 3.0
const SHADER: String = """
shader_type canvas_item;
uniform sampler2D tenue : filter_linear;
uniform vec4 couleur : source_color = vec4(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float m = texture(tenue, UV).r;
	// Masque gris sur noir : 1 = ton clair de la tenue, la valeur garde l'ombrage du dessin.
	vec3 teinte = couleur.rgb * clamp(m, 0.0, 1.0);
	COLOR = vec4(mix(c.rgb, teinte, smoothstep(0.03, 0.3, m)), c.a) * COLOR;
}
"""

## TEMPORAIRE (Julien, 2026-10-20 : génération des fantômes arrêtée) : fantôme des persos sans planches
## ghost/ghost_move = leurs idle/walk en vol stationnaire, avec des ailes blanches dessinées par code
## (tools/blackout/dessine_ailes.py). Les persos qui ont leurs planches fantôme (ailes comprises) gardent
## les leurs, avec le même vol stationnaire. À retirer quand tous les persos auront leurs planches.
const HOVER_PX: float = 14.0         # hauteur moyenne au-dessus du sol (px à l'écran)
const HOVER_BOB_PX: float = 4.0      # amplitude du bobbing
const HOVER_HZ: float = 1.0          # bobbing et battement d'ailes, par seconde
const HOVER_TILT_DEG: float = 7.0    # penché vers l'avant en déplacement
const HOVER_SWAY_PX: float = 2.0     # petite oscillation d'avance et de recul
const HOVER_WALK_RATE: float = 0.45  # cadence de la marche en vol : elle « nage »
const WING_PATH: String = "res://assets/blackout/communs/aile_fantome"
const WING_HEIGHT_K: float = 0.28    # hauteur de l'aile / hauteur du perso
const WING_FLAP_DEG: float = 14.0
const SHOULDER_K: float = 0.52       # épaule : part de la hauteur de la silhouette, depuis le haut
const SHOULDER_INSET_K: float = 0.06 # rentrée dans le dos, en part de la largeur de la silhouette

## Raccord des animations (SPEC-GORDEKA §16.3, tools/blackout/post_anims.py) : chaque planche est
## ramenée à la taille (`echelle`) et à la place (`decalage`, `frame_offsets`) de l'idle du perso, ne
## joue que ses images utiles (`debut`, `fin`) et sait où entrer dans l'anim suivante (`entrees`).
## Passage d'un état à l'autre : on entre dans la boucle suivante à l'image la plus proche de l'image
## courante, puis un fondu enchaîné très court (anim_fondu_s, dosé par l'écart des deux silhouettes)
## efface le reste ; les gestes brusques (found, hide_out, extract) partent d'un petit « pouf » de
## squash & stretch. Réglages dans data/blackout/rules.json (anim_*, anims).
static var _anims: Dictionary = {}     # "louis/walk" -> {tex, mask, n, fps, loop, cell, feet}
static var _shader: Shader
## QA (`--bk-mannequin`) : tous les persos en pantin articulé.
static var use_pantin: bool = false
static var _pdata: Dictionary = {}     # chorégraphie -> {ends, loop}

var pantin: BkPantin

var actor: BkActor
var _anim: String = ""
var _t: float = 0.0
var _once: String = ""
var _once_visible: bool = true
var _float_t: float = 0.0
## Hauteur de vol du fantôme (px à l'écran) : l'acteur dessine son ombre en conséquence.
var hover_lift: float = 0.0
var _wings: Array[Sprite2D] = []
## Cône de lumière de la lampe pendant hunter_reveal (BkLampe), créé à la première utilisation.
var _lampe: BkLampe
## Fondu enchaîné : l'image quittée, posée par-dessus la nouvelle, s'efface en `_prev_s` s.
var _prev: Sprite2D
var _prev_left: float = 0.0
var _prev_s: float = 0.0
var _prev_a: float = 1.0
var _pouf_left: float = 0.0
var _rate_once: float = 1.0
var _f: int = 0                        # image dessinée
static var _wing_tex: Texture2D
static var _wing_root: Vector2 = Vector2.ZERO


## Durée d'affichage du profil fixe quand un geste ponctuel n'a pas encore son animation (s).
const STATIC_ONCE_S: float = 0.6

## Vrai si le perso a ses planches 2D, ou au moins son profil validé (`modele.png`).
static func available(character: String) -> bool:
	return use_pantin or ResourceLoader.exists((DIR % character) + "idle.png") \
		or ResourceLoader.exists((DIR % character) + "modele.png")


## Durées d'une chorégraphie du pantin, au même format que les planches.
static func _pantin_data(anim: String) -> Dictionary:
	if _pdata.has(anim):
		return _pdata[anim]
	var c: Dictionary = BkPantin.load_choreo(anim)
	var d: Dictionary = {}
	if not c.is_empty():
		var ends: PackedFloat32Array = PackedFloat32Array()
		var ms: Array = c.get("frame_ms", [])
		var acc: float = 0.0
		for i: int in int(c.get("frames", 1)):
			acc += float(ms[i]) / 1000.0 if i < ms.size() else 1.0 / float(c.get("fps", 24.0))
			ends.append(acc)
		d = {"ends": ends, "loop": bool(c.get("loop", false))}
	_pdata[anim] = d
	return d


static func _data(character: String, anim: String) -> Dictionary:
	var key: String = character + "/" + anim
	if _anims.has(key):
		return _anims[key]
	var d: Dictionary = {}
	var path: String = (DIR % character) + anim
	if ResourceLoader.exists(path + ".png"):
		var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
		var n: int = int(j.get("frames", 1))
		# Fin de chaque image (s) : durées par image (`frame_ms`) ou cadence fixe (`fps`).
		var ends: PackedFloat32Array = PackedFloat32Array()
		var ms: Array = j.get("frame_ms", [])
		var acc: float = 0.0
		for i: int in n:
			acc += float(ms[i]) / 1000.0 if i < ms.size() else 1.0 / float(j.get("fps", 24.0))
			ends.append(acc)
		# Recalage par image (px de case) : les pieds posés restent fixes (tools/blackout/pieds.py).
		var offs: PackedVector2Array = PackedVector2Array()
		for o: Variant in j.get("frame_offsets", []):
			offs.append(Vector2(float(o[0]), float(o[1])))
		# Lampe du chasseur (hunter_reveal) : main par image, px de case (tools/blackout/lampe.py).
		var lampe: Array = []
		var lj: Dictionary = j.get("lampe", {})
		for p: Variant in lj.get("points", []):
			lampe.append(Vector2(float(p[0]), float(p[1])) if p is Array else null)
		# Raccord (post_anims.py) ; `anim_raccord` = 0 : planches brutes (comparaison A/B).
		var rac: bool = _regle("anim_raccord", 1.0) > 0.5
		var dec: Array = j.get("decalage", [0.0, 0.0]) if rac else [0.0, 0.0]
		var entrees: Dictionary = {}
		if rac:
			for b: String in (j.get("entrees", {}) as Dictionary):
				var t: Dictionary = j["entrees"][b]
				entrees[b] = {"i": PackedInt32Array(t.get("i", [])), "e": PackedInt32Array(t.get("e", []))}
		d = {
			"echelle": float(j.get("echelle", 1.0)) if rac else 1.0,
			"dec": Vector2(float(dec[0]), float(dec[1])),
			"debut": clampi(int(j.get("debut", 0)), 0, n - 1) if rac else 0,
			"fin": clampi(int(j.get("fin", n)), 1, n) if rac else n,
			"entrees": entrees,
			"lampe": lampe,
			"lampe_debut": int(lj.get("debut", -1)),
			"offs": offs,
			"stride": float(j.get("stride_px", 0.0)),
			"ends": ends,
			"tex": load(path + ".png"),
			"mask": load(path + "_tenue.png") if ResourceLoader.exists(path + "_tenue.png") else null,
			"n": n,
			"loop": bool(j.get("loop", false)),
			"cell": Vector2(j.get("cell", [256, 256])[0], j.get("cell", [256, 256])[1]),
			"feet": Vector2(j.get("feet_anchor", [128, 236])[0], j.get("feet_anchor", [128, 236])[1]),
			"height": CELL_PERSO_PX,
		}
	elif ResourceLoader.exists((DIR % character) + "modele.png"):
		d = _static(character, anim)
	_anims[key] = d
	return d


## Repli pour la recette (Julien, 2026-10-20) : toute animation absente montre le profil validé, fixe.
## Pas de masque de tenue : le perso garde ses couleurs. Les gestes ponctuels durent STATIC_ONCE_S.
## Une emote (`emote_*`) dure plus longtemps : toute la durée de sa bulle (`emote_duration`).
static func _static(character: String, anim: String) -> Dictionary:
	var tex: Texture2D = load((DIR % character) + "modele.png")
	var used: Rect2i = tex.get_image().get_used_rect()
	var noir: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	noir.fill(Color.BLACK)
	var once_s: float = BkRules.f("emote_duration") if anim.begins_with("emote_") else STATIC_ONCE_S
	return {
		"ends": PackedFloat32Array([once_s]),
		"tex": tex,
		"mask": ImageTexture.create_from_image(noir),
		"n": 1,
		"loop": anim in ["idle", "walk", "run_scared", "ghost", "ghost_move", "trapped", "search", "victory", "sad"],
		"cell": Vector2(tex.get_size()),
		"feet": Vector2(used.position.x + used.size.x * 0.5, used.end.y),
		"height": float(used.size.y),
		"static": true,
		"debut": 0,
		"fin": 1,
	}


## Le perso change (set_character) : l'image en fondu part avec lui.
func _exit_tree() -> void:
	if _prev != null:
		_prev.queue_free()
		_prev = null


func setup(a: BkActor) -> void:
	actor = a
	if use_pantin:
		pantin = BkPantin.new()
		pantin.setup("humain")
		add_child(pantin)
		scale = Vector2.ONE * HEIGHT_PX / pantin.height
		return
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = _shader
	material = m
	centered = false
	region_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	scale = Vector2.ONE * HEIGHT_PX / CELL_PERSO_PX


## Joue une animation une fois (piège, détection, trouvé, cachette…), puis reprend l'état.
func play_once(anim: String) -> void:
	if _get_data(anim).is_empty():
		return
	_once = anim
	_once_visible = actor.shown
	_rate_once = 1.0
	# Geste trop long pour son état (rules.json anims.duree_max) : joué plus vite, en entier.
	var dmax: float = _par_anim("duree_max", anim)
	if dmax > 0.0 and pantin == null:
		_rate_once = maxf(1.0, _utile(_get_data(anim)) / dmax)
	if _anim == anim:
		_t = _t0(_get_data(anim)) if pantin == null else 0.0     # rejouer le même geste repart du début
	_set_anim(anim)


## Durée jouée d'une animation (s) : images utiles, accélérée par anims.duree_max ; 0 si absente.
func length(anim: String) -> float:
	var d: Dictionary = _get_data(anim)
	if d.is_empty():
		return 0.0
	var u: float = _utile(d)
	var dmax: float = _par_anim("duree_max", anim)
	return minf(u, dmax) if dmax > 0.0 and pantin == null else u


## Début et fin (s) des images jouées d'une planche.
static func _t0(d: Dictionary) -> float:
	var deb: int = int(d.get("debut", 0))
	return (d["ends"] as PackedFloat32Array)[deb - 1] if deb > 0 else 0.0


static func _t1(d: Dictionary) -> float:
	var ends: PackedFloat32Array = d["ends"]
	return ends[clampi(int(d.get("fin", ends.size())), 1, ends.size()) - 1]


static func _utile(d: Dictionary) -> float:
	return _t1(d) - _t0(d)


## Réglage du raccord (rules.json), avec sa valeur par défaut si la clé manque.
static func _regle(key: String, def: float) -> float:
	return float(BkRules.data().get(key, def))


## Réglage par geste (rules.json anims.<table>.<anim>, `emote` pour toutes les emotes) ; 0 si absent.
static func _par_anim(table: String, anim: String) -> float:
	if _regle("anim_durees", 1.0) < 0.5:
		return 0.0
	var t: Dictionary = (BkRules.data().get("anims", {}) as Dictionary).get(table, {})
	return float(t.get("emote" if anim.begins_with("emote_") else anim, 0.0))


## Arrête une emote en cours ; l'animation d'état reprend à l'image suivante.
func stop_emote() -> void:
	if _once.begins_with("emote_"):
		_once = ""


func _set_anim(anim: String) -> void:
	if anim == _anim:
		return
	var old: Dictionary = _get_data(_anim) if _anim != "" else {}
	_anim = anim
	_t = 0.0
	if pantin != null:
		pantin.play(anim)
		return
	var d: Dictionary = _get_data(anim)
	if d.is_empty():
		return
	_t = _t0(d)
	# Point d'entrée : l'image de la boucle suivante la plus proche de l'image quittée (table
	# `entrees` de l'anim quittée) ; l'écart des deux silhouettes dose le fondu.
	var ecart: float = 1.0
	var tab: Dictionary = (old.get("entrees", {}) as Dictionary).get(_source_anim(anim), {})
	if not tab.is_empty():
		var e: PackedInt32Array = tab["e"]
		var ii: PackedInt32Array = tab["i"]
		if _f < e.size():
			ecart = float(e[_f]) / 100.0
		if _f < ii.size() and bool(d["loop"]) and _regle("anim_entrees", 1.0) > 0.5:
			# Table d'une version précédente de l'anim visée : index borné plutôt qu'une erreur.
			var ends: PackedFloat32Array = d["ends"]
			var j: int = mini(ii[_f], ends.size())
			_t = ends[j - 1] if j > 0 else 0.0
	if not old.is_empty() and visible:
		_fondu(ecart)
	if (BkRules.data().get("anims", {}) as Dictionary).get("pouf", []).has(anim):
		_pouf_left = _regle("anim_pouf_s", 0.0)
	texture = d["tex"]
	(material as ShaderMaterial).set_shader_parameter("tenue", d["mask"])


## Fondu enchaîné : l'image quittée reste posée par-dessus la nouvelle et s'efface, d'autant plus
## longtemps que les deux silhouettes diffèrent (écart 1 − IoU, entre anim_fondu_ecart_min et _plein).
func _fondu(ecart: float) -> void:
	var lo: float = _regle("anim_fondu_ecart_min", 0.12)
	var hi: float = maxf(_regle("anim_fondu_ecart_plein", 0.45), lo + 0.01)
	var s: float = _regle("anim_fondu_s", 0.0) * clampf((ecart - lo) / (hi - lo), 0.0, 1.0)
	if s <= 0.01 or texture == null or actor == null:
		return
	if _prev == null:
		_prev = Sprite2D.new()
		_prev.centered = false
		_prev.region_enabled = true
		_prev.texture_filter = texture_filter
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = _shader
		_prev.material = m
		actor.add_child(_prev)
	actor.move_child(_prev, get_index() + 1)
	var pm: ShaderMaterial = material as ShaderMaterial
	var mm: ShaderMaterial = _prev.material as ShaderMaterial
	mm.set_shader_parameter("tenue", pm.get_shader_parameter("tenue"))
	mm.set_shader_parameter("couleur", actor.color)
	_prev.texture = texture
	_prev.region_rect = region_rect
	_prev.flip_h = flip_h
	_prev.position = position
	_prev.rotation = rotation
	_prev.scale = scale
	_prev_a = modulate.a
	_prev_s = s
	_prev_left = s
	_prev.visible = true


func _update_fondu(dt: float) -> void:
	if _prev == null:
		return
	_prev_left = maxf(0.0, _prev_left - dt)
	_prev.visible = _prev_left > 0.0 and visible
	var k: float = _prev_left / maxf(_prev_s, 0.001)
	_prev.modulate.a = _prev_a * k * k * (3.0 - 2.0 * k)


## Animation qui découle de l'état de l'acteur.
func _state_anim() -> String:
	var a: BkActor = actor
	if a.end_pose != "":
		return a.end_pose
	if a.role == BkActor.Role.GHOST or a.role == BkActor.Role.OUT:
		return "ghost_move" if a.velocity.length() > 5.0 else "ghost"
	if a.role == BkActor.Role.HUNTER:
		if a.search_left > 0.0:
			return "search"
		# Piégé : il se débat sur place ; s'il avance (à vitesse réduite), il marche, sinon la planche
		# sur place glisserait sous ses pieds (anim_piege_marche).
		if a.slow_left > 0.0 and (a.velocity.length() <= 5.0 or _regle("anim_piege_marche", 1.0) < 0.5):
			return "trapped"
	if a.velocity.length() > 5.0:
		return "run_scared" if a.scared else "walk"
	return "idle"


func _process(dt: float) -> void:
	if actor == null:
		return
	if _once == "":
		_set_anim(_state_anim())
	var d: Dictionary = _get_data(_anim)
	if d.is_empty():
		visible = false
		return
	var ends: PackedFloat32Array = d["ends"]
	var total: float = ends[ends.size() - 1]
	var rate: float = _rate_once if _once != "" else 1.0
	var fake: bool = _once == "" and _fake_ghost(_anim)
	# Boucle calée sur la durée de son état (anims.cale_etat, ex. la fouille : un cycle exactement).
	var cales: Dictionary = (BkRules.data().get("anims", {}) as Dictionary).get("cale_etat", {})
	var cale: String = str(cales.get(_anim, ""))
	if _once == "" and cale != "" and BkRules.f(cale) > 0.0 and not d.has("static") and _regle("anim_durees", 1.0) > 0.5:
		rate = total / BkRules.f(cale)
	if CYCLE_S.has(_anim) and pantin == null and not d.has("static"):
		var stride: float = float(d.get("stride", 0.0))
		if stride > 0.0 and not fake:
			# Vitesse en px de case par seconde ÷ stride = planches par seconde ; × durée de la planche.
			var v_case: float = actor.velocity.length() * float(d["height"]) / HEIGHT_PX
			rate = clampf(total * v_case / stride, RATE_MIN, RATE_MAX)
		else:
			rate = total / float(CYCLE_S[_anim]) * clampf(actor.velocity.length() / BkRules.px("speed_hider"), 0.5, 1.5)
		if fake:
			rate *= HOVER_WALK_RATE
	_t += dt * rate
	# Geste coupé par le mouvement (anims.coupe_mouv : part du geste jouée avant qu'un pas le coupe) :
	# sans ça, une planche sur place glisserait sous ses pieds pendant qu'il avance.
	var coupe: float = _par_anim("coupe_mouv", _once) if _once != "" else 0.0
	var fini: bool = _t >= _t1(d)
	if coupe > 0.0 and actor.velocity.length() > 5.0 and (_t - _t0(d)) >= coupe * _utile(d):
		fini = true
	if fini:
		if _once != "":
			_once = ""
			_set_anim(_state_anim())
			d = _get_data(_anim)
			ends = d["ends"]
			total = ends[ends.size() - 1]
		elif bool(d["loop"]):
			_t = _t0(d) + fmod(_t - _t0(d), maxf(_utile(d), 0.001))
	var f: int = int(d.get("debut", 0))
	var f_fin: int = int(d.get("fin", ends.size())) - 1
	while f < f_fin and _t >= ends[f]:
		f += 1
	_f = f
	var face: float = 1.0 if cos(actor.look) >= 0.0 else -1.0
	var ghost: bool = (actor.role == BkActor.Role.GHOST or actor.role == BkActor.Role.OUT) and _once != "found" \
		and _once != "extract"
	modulate.a = GHOST_ALPHA if ghost else 1.0
	# Dans une cachette : visible pendant la plongée seulement (la cachette se referme dessus).
	if _once != "":
		visible = actor.draw_2d and _once_visible and not actor.inside()
	else:
		visible = actor.draw_2d and actor.shown and not actor.inside()
	var pop: Vector2 = _pop_offset()
	if pantin != null:
		# Étonné dès que le chasseur le voit (la jauge de capture monte).
		pantin.head_override = "surprised" if actor.gauge > 0.0 and actor.role == BkActor.Role.HIDER else ""
		pantin.pose(f)
		var k: float = HEIGHT_PX / pantin.height
		scale = Vector2(k * face, k)
		position = Vector2(-pantin.feet.x * scale.x, actor.radius * 0.6 - pantin.feet.y * k) + pop
		# Mannequin gris teinté de la couleur du joueur, en attendant sa garde-robe.
		pantin.modulate = actor.color.lerp(Color.WHITE, 0.35)
		return
	var cell: Vector2 = d["cell"]
	region_rect = Rect2(Vector2(cell.x * float(f), 0.0), cell)
	flip_h = face < 0.0
	# Pieds de la case sur les pieds de l'acteur (même ligne que l'ombre au sol).
	var feet: Vector2 = d["feet"]
	var offs: PackedVector2Array = d.get("offs", PackedVector2Array())
	if f < offs.size():
		feet -= offs[f]      # l'image décalée de offs : ses pieds posés restent sous l'acteur
	feet -= d.get("dec", Vector2.ZERO)
	var fx: float = cell.x - feet.x if flip_h else feet.x
	# Petit rebond façon Among Us à chaque pas, avec un léger écrasement quand le pied touche le sol
	# (idée de Julien) : deux rebonds par cycle, au rythme de la planche.
	var k: float = HEIGHT_PX / float(d["height"]) * float(d.get("echelle", 1.0))
	var lift: float = 0.0
	var squash: float = 0.0
	if CYCLE_S.has(_anim) and actor.velocity.length() > 5.0 and not ghost:
		var b: float = absf(sin(_t / total * TAU))       # 0 au contact du pied, 1 en l'air
		lift = BOUNCE_PX * (1.4 if _anim == "run_scared" else 1.0) * b
		squash = SQUASH * pow(1.0 - b, 3.0)
	# Pouf : étiré puis écrasé, amorti, autour des pieds (anim_pouf_s, anim_pouf_k).
	if _pouf_left > 0.0:
		_pouf_left = maxf(0.0, _pouf_left - dt)
		var p: float = 1.0 - _pouf_left / maxf(_regle("anim_pouf_s", 0.1), 0.001)
		squash -= _regle("anim_pouf_k", 0.0) * sin(p * TAU) * (1.0 - p)
	scale = Vector2(k * (1.0 + squash * 0.6), k * (1.0 - squash))
	var anchor: Vector2 = Vector2(0.0, actor.radius * 0.6 - lift) + pop
	var rot: float = 0.0
	hover_lift = 0.0
	if ghost:
		# Vol stationnaire : il décolle, monte et descend doucement, penché vers l'avant et avec un
		# petit mouvement d'avance et de recul quand il se déplace ; l'ombre reste au sol (BkActor).
		_float_t += dt
		var w: float = TAU * HOVER_HZ * _float_t
		hover_lift = HOVER_PX + HOVER_BOB_PX * sin(w)
		anchor.y -= hover_lift
		var moving: float = clampf(actor.velocity.length() / maxf(BkRules.px("speed_ghost"), 1.0), 0.0, 1.0)
		anchor.x += face * HOVER_SWAY_PX * (0.5 + moving) * cos(w)
		rot = face * deg_to_rad(HOVER_TILT_DEG) * moving
	var o: Vector2 = Vector2(-fx * scale.x, -feet.y * scale.y)
	rotation = rot
	position = anchor + o.rotated(rot)
	_update_wings(fake and ghost, d, f, flip_h, _float_t)
	_update_lampe(d, f, _t1(d), dt)
	_update_fondu(dt)
	(material as ShaderMaterial).set_shader_parameter("couleur", actor.color)


## Lampe du chasseur : allumée de l'image `lampe_debut` à la fin de l'animation, sur la main de
## l'image ; éteinte (fondu) dès que la main n'est plus mesurée, juste avant la fin du geste ou s'il
## est interrompu.
func _update_lampe(d: Dictionary, f: int, total: float, dt: float) -> void:
	var pts: Array = d.get("lampe", [])
	if pts.is_empty() and _lampe == null:
		return
	if _lampe == null:
		_lampe = BkLampe.new()
		add_child(_lampe)
	var on: bool = _once != "" and _once == _anim and f < pts.size() and pts[f] != null \
		and f >= int(d.get("lampe_debut", -1)) and _t < total - BkLampe.FONDU_S
	var p: Vector2 = Vector2.ZERO
	if on:
		var cell: Vector2 = d["cell"]
		var q: Vector2 = pts[f]
		p = Vector2(cell.x - q.x if flip_h else q.x, q.y)
	_lampe.suivre(on, p, -1.0 if flip_h else 1.0, scale, dt)


## Sortie de cachette : décalage de dessin qui part de la cachette et rejoint l'acteur (posé sur
## la case voisine) en sautant un peu, pendant `cachette_out_s`.
func _pop_offset() -> Vector2:
	if actor.pop_left <= 0.0:
		return Vector2.ZERO
	var p: float = 1.0 - clampf(actor.pop_left / maxf(BkRules.f("cachette_out_s"), 0.01), 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - p, 3.0)
	return (actor.pop_from - actor.position) * (1.0 - e) + Vector2(0, -POP_JUMP_PX * sin(p * PI))


func _get_data(anim: String) -> Dictionary:
	return _pantin_data(anim) if pantin != null else _data(actor.character, _source_anim(anim))


## Planche réellement jouée : un fantôme sans planches fantôme prend idle (immobile) ou walk.
func _source_anim(anim: String) -> String:
	if not _fake_ghost(anim):
		return anim
	var alt: String = "walk" if anim == "ghost_move" else "idle"
	if not ResourceLoader.exists((DIR % actor.character) + alt + ".png"):
		alt = "idle"
	return alt


func _fake_ghost(anim: String) -> bool:
	return (anim == "ghost" or anim == "ghost_move") and pantin == null \
		and not ResourceLoader.exists((DIR % actor.character) + anim + ".png")


## Épaule (dos) de chaque image d'une planche, en px de la case : bord gauche de la silhouette (le
## perso regarde à droite) à SHOULDER_K de sa hauteur, un peu rentré. Lu une fois sur l'image.
static func _shoulders(d: Dictionary) -> PackedVector2Array:
	if d.has("shoulders"):
		return d["shoulders"]
	var out: PackedVector2Array = PackedVector2Array()
	var cell: Vector2 = d["cell"]
	var n: int = int(d["n"])
	var img: Image = (d["tex"] as Texture2D).get_image()
	if img != null and not img.is_empty():
		img = img.duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var q: int = 4                       # une mesure pour q px
		var cw: int = maxi(1, int(cell.x) / q)
		var ch: int = maxi(1, int(cell.y) / q)
		img.resize(cw * n, ch, Image.INTERPOLATE_BILINEAR)
		var px: PackedByteArray = img.get_data()
		var w: int = cw * n
		for f: int in n:
			var top: int = -1
			var bottom: int = -1
			var left: int = cw
			var right: int = -1
			for y: int in ch:
				for x: int in cw:
					if px[(y * w + f * cw + x) * 4 + 3] > 96:
						if top < 0:
							top = y
						bottom = y
						left = mini(left, x)
						right = maxi(right, x)
			if top < 0:
				out.append(cell * 0.5)
				continue
			var row: int = top + roundi(float(bottom - top) * SHOULDER_K)
			var lx: int = cw
			for x: int in cw:
				if px[(row * w + f * cw + x) * 4 + 3] > 96:
					lx = x
					break
			out.append(Vector2((float(lx) + float(right - left) * SHOULDER_INSET_K) * q, float(row) * q))
	d["shoulders"] = out
	return out


## Ailes du fantôme sans planches fantôme : deux ailes dans le dos (celle du fond plus petite et
## grisée), derrière le corps, qui battent au rythme du vol.
func _update_wings(on: bool, d: Dictionary, f: int, flip: bool, t: float) -> void:
	if not on or not ResourceLoader.exists(WING_PATH + ".png"):
		for w: Sprite2D in _wings:
			w.visible = false
		return
	if _wings.is_empty():
		if _wing_tex == null:
			_wing_tex = load(WING_PATH + ".png")
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(WING_PATH + ".json"))
			var a: Array = (j as Dictionary).get("attache", [0, 0]) if j is Dictionary else [0, 0]
			_wing_root = Vector2(float(a[0]), float(a[1]))
		for i: int in 2:
			var w: Sprite2D = Sprite2D.new()
			w.texture = _wing_tex
			w.centered = false
			w.show_behind_parent = true
			w.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			if i == 0:
				w.self_modulate = Color(0.82, 0.86, 0.92)     # aile du fond
			add_child(w)
			_wings.append(w)
	var sh: PackedVector2Array = _shoulders(d)
	var cell: Vector2 = d["cell"]
	var p: Vector2 = sh[mini(f, sh.size() - 1)] if not sh.is_empty() else cell * 0.5
	var k: float = WING_HEIGHT_K * float(d["height"]) / float(_wing_tex.get_height())
	var flap: float = deg_to_rad(WING_FLAP_DEG) * sin(TAU * HOVER_HZ * t)
	for i: int in 2:
		var w: Sprite2D = _wings[i]
		var kk: float = k * (0.85 if i == 0 else 1.0)
		var at: Vector2 = p + (Vector2(cell.x * 0.03, -cell.y * 0.02) if i == 0 else Vector2.ZERO)
		w.visible = true
		w.offset = -_wing_root
		w.position = Vector2(cell.x - at.x if flip else at.x, at.y)
		w.scale = Vector2(-kk if flip else kk, kk)
		var a: float = -flap * (0.8 if i == 0 else 1.0) - deg_to_rad(4.0 if i == 0 else 0.0)
		w.rotation = -a if flip else a
