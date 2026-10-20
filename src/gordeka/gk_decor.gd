class_name GkDecor
extends Node2D
## Décor en images (pixelforge, intégré élément par élément par tools/gordeka/integre_decor.py),
## posé sur la carte avec repli sur le dessin procédural de GkMap pour tout ce qui n'a pas encore
## d'image. La grille A* reste celle des cases ; la collision et l'occlusion de la vue des objets en
## image suivent leur forme réelle, calculée au chargement depuis l'alpha de l'image (`_shape`) :
## seule l'empreinte au sol arrête le passage et la vue, le haut de l'image (toit, face haute, mât)
## passe devant les persos qui sont derrière (tri par profondeur sur le pied de l'objet).
##
## index.json (assets/gordeka/decor/) : {carte, elements: {id: {type, categorie, caractere, zones,
## taille_cases, debord_haut_cases, animation, fichiers: [chemins relatifs], ombre, ombre_decalage,
## ouvert, ouvert_decalage}}}.
## - tuile_sol : texture répétée sur les cases du caractère dans ses zones (taille_cases cases par
##   tuile ; plusieurs fichiers = variantes mélangées de façon déterministe) ;
## - objet : une instance par groupe de cases contiguës du caractère dans une zone, à l'échelle de
##   l'emprise, centrée en largeur, bas aligné, débord vers le haut permis ;
## - decal (et sorties, où l'on marche) : à plat, sous les persos.
## Ce nœud porte les objets debout : il rejoint le calque y-trié des persos (les persos passent
## derrière les objets hauts) ; `under` porte les ombres et ce qui est à plat.

const DIR: String = "res://assets/gordeka/decor"
## Cases dont le sol « . » de la zone passe dessous (même règle que le dessin procédural).
const UNDER_FLOOR: String = ".ESHtcB#"
## Tangage des barques (methode « jeu ») : amplitude en degrés, flottement en px, vitesses.
const SWAY_DEG: float = 2.2
const SWAY_SPEED: float = 1.1
const BOB_PX: float = 3.0
const BOB_SPEED: float = 1.7
## Fondu fermé → ouvert : l'image ouverte est pleine dès open = 1 / OPEN_FADE (bascule franche).
const OPEN_FADE: float = 2.0
## Forme des objets : un point de masque pour SHAPE_STEP px de jeu, contour simplifié à SHAPE_EPSILON
## point près, opaque au-delà de SHAPE_ALPHA ; les îlots de moins de SHAPE_MIN_AREA points sont ignorés.
const SHAPE_STEP: float = 4.0
const SHAPE_EPSILON: float = 1.0
const SHAPE_ALPHA: float = 0.5
const SHAPE_MIN_AREA: float = 6.0
const SHAPE_SOURCE_DIV: int = 4
## Calque de lumière des objets debout : éclairés par les lumières du chasseur que seuls les murs de
## la grille ombrent (un objet n'est pas assombri par sa propre base ; voir GkGame._make_view).
const LIGHT_MASK: int = 2
## Vitesse du fondu de l'objet qui masque un coéquipier (opacité par seconde).
const FADE_SPEED: float = 4.0

## Formes déjà calculées (même image, même taille dessinée, même base), gardées d'une partie à l'autre.
static var _shape_cache: Dictionary = {}
## Images lues pour les formes, réduites SHAPE_SOURCE_DIV fois (une lecture par image : en WebGL, c'est
## une relecture du GPU ; réduite, elle pèse peu en mémoire et reste plus fine que le masque).
static var _image_cache: Dictionary = {}

var map: GkMap
var under: Node2D
var elements: Dictionary = {}
## Cases dont le dessin procédural est remplacé (objets en image, sols pleins sur un caractère
## non marchable comme l'eau ou les toits) : GkMap et GkWater ne les dessinent plus.
var covered: Dictionary = {}
## Cases d'un objet en image posé sur l'eau (barques du bassin) : GkWater y dessine l'eau, pas de sol.
var water_under: Dictionary = {}
## Cases d'un objet en image dont la forme a été calculée : GkMap n'y pose plus de rectangle de
## collision, mais les polygones de base de l'instance.
var shaped: Dictionary = {}
## Instances posées : {id, cells: Array[Vector2i], rect: Rect2i, zone, holder, sprite, kind, base, phase}
## et, si la forme est connue : polys (bases au sol, repère de la carte), blocks_view, mask (BitMap de
## la silhouette), mask_rect (zone dessinée, repère de la carte), mask_scale, sort_y, fade.
var instances: Array = []
var _dir: String = DIR
var _tex: Dictionary = {}           # chemin → Texture2D (ou null si absent)
var _floors: Dictionary = {}        # "car|zone" → {textures: Array, cases: Vector2i}
var _zone_grid: PackedInt32Array = PackedInt32Array()
var _animated: Array = []
var _t: float = 0.0


## Lit l'index et prépare sols et objets. Sans index (ou pour une autre carte), ne fait rien :
## tout reste procédural.
func setup(m: GkMap) -> void:
	map = m
	name = "Decor"
	y_sort_enabled = true
	under = Node2D.new()
	under.name = "DecorSol"
	# QA : `--gk-decor-dir=/chemin/abs` lit un décor hors projet (images non importées).
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--gk-decor-dir="):
			_dir = arg.trim_prefix("--gk-decor-dir=")
	_zone_grid.resize(map.width * map.height)
	for y: int in map.height:
		for x: int in map.width:
			_zone_grid[y * map.width + x] = map.zone_of(Vector2i(x, y))
	var path: String = _dir.path_join("index.json")
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or str((data as Dictionary).get("carte", map.map_id)) != map.map_id:
		return
	elements = (data as Dictionary).get("elements", {})
	_build_floors()
	_build_objects()
	set_process(not _animated.is_empty())
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--gk-export-masques="):
			export_masks(arg.trim_prefix("--gk-export-masques="))


## Accroche les nœuds : `under` sur la carte (après ses morceaux), les objets dans le calque y-trié
## des persos dès qu'il existe (créé par le jeu juste après la carte).
func attach() -> void:
	map.add_child(under)
	_attach_late.call_deferred()


func _attach_late() -> void:
	var host: Node = map
	var parent: Node = map.get_parent()
	if parent:
		for c: Node in parent.get_children():
			if c != map and c is Node2D and (c as Node2D).y_sort_enabled:
				host = c
				break
	host.add_child(self)


func zone_at(t: Vector2i) -> int:
	if t.x < 0 or t.y < 0 or t.x >= map.width or t.y >= map.height:
		return -1
	return _zone_grid[t.y * map.width + t.x]


func has_floor(ch: String, zone: int) -> bool:
	return _floors.has("%s|%d" % [ch, zone])


## Vrai si une image d'objet (cachette, sortie, objet) occupe cette case.
func has_image_at(t: Vector2i) -> bool:
	return _instance_at(t) >= 0


## État ouvert d'une cachette (0 fermée → 1 ouverte) : l'image `ouvert` de l'index, si elle existe,
## se fond par-dessus l'image fermée (calée par `ouvert_decalage`, comme l'ombre) ; sans elle, seule
## l'image fermée reste (elle s'écrase et tremble quand même).
func set_open(t: Vector2i, k: float) -> void:
	var i: int = _instance_at(t)
	if i < 0:
		return
	var inst: Dictionary = instances[i]
	var op: Sprite2D = inst.get("open_sprite")
	if op == null:
		return
	op.visible = k > 0.01
	op.modulate.a = clampf(k * OPEN_FADE, 0.0, 1.0)
	(inst["sprite"] as Sprite2D).modulate.a = 1.0 - clampf((k - 0.5) * OPEN_FADE, 0.0, 1.0)


# ---------------------------------------------------------------- sols

func _build_floors() -> void:
	for id: String in elements:
		var el: Dictionary = elements[id]
		var ch: String = str(el.get("caractere", ""))
		if str(el.get("type", "")) != "tuile_sol" or ch.length() != 1:
			continue
		var texs: Array = []
		for rel: Variant in el.get("fichiers", []):
			var tex: Texture2D = _texture(str(rel))
			if tex:
				texs.append(tex)
		if texs.is_empty():
			continue
		var tc: Array = el.get("taille_cases", [2, 2])
		var cases: Vector2i = Vector2i(maxi(1, int(tc[0])), maxi(1, int(tc[1])))
		for z: int in _zones_of(el):
			var key: String = "%s|%d" % [ch, z]
			if _floors.has(key):
				continue
			_floors[key] = {"textures": texs, "cases": cases}
			# Sol plein sur un caractère qui n'est pas du sol (eau, toits) : remplace son dessin.
			if not UNDER_FLOOR.contains(ch):
				for y: int in map.height:
					for x: int in map.width:
						if map.at(Vector2i(x, y)) == ch and zone_at(Vector2i(x, y)) == z:
							covered[Vector2i(x, y)] = true


## Dessine les sols en image d'une zone (-1 : hors zones) dans le morceau `ci` de la carte.
func draw_floors(ci: CanvasItem, zone: int) -> void:
	if _floors.is_empty():
		return
	var r: Rect2i = Rect2i(0, 0, map.width, map.height)
	if zone >= 0:
		r = map.zones[zone]["rect"]
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var t: Vector2i = Vector2i(x, y)
			if zone_at(t) != zone or water_under.has(t):
				continue
			var ch: String = map.at(t)
			# Sol de la zone sous un objet en image posé sur un caractère non marchable (lavoir sur « ~ »).
			var under_floor: bool = UNDER_FLOOR.contains(ch) or covered.has(t)
			if not _draw_cell(ci, t, "%s|%d" % [ch, zone]) and under_floor and ch != ".":
				_draw_cell(ci, t, ".|%d" % zone)


func _draw_cell(ci: CanvasItem, t: Vector2i, key: String) -> bool:
	var f: Dictionary = _floors.get(key, {})
	if f.is_empty():
		return false
	var texs: Array = f["textures"]
	var n: Vector2i = f["cases"]
	var block: Vector2i = Vector2i(floori(float(t.x) / n.x), floori(float(t.y) / n.y))
	var tex: Texture2D = texs[_hash(block) % texs.size()]
	var s: Vector2 = Vector2(tex.get_width() / (n.x * map.tile), tex.get_height() / (n.y * map.tile))
	var src: Vector2 = Vector2(posmod(t.x, n.x), posmod(t.y, n.y)) * map.tile * s
	ci.draw_texture_rect_region(tex, Rect2(Vector2(t) * map.tile, Vector2(map.tile, map.tile)),
		Rect2(src, Vector2(map.tile, map.tile) * s))
	return true


## Mélange déterministe des variantes (même carte → même tirage, en ligne comme hors ligne).
static func _hash(b: Vector2i) -> int:
	return absi((b.x * 73856093) ^ (b.y * 19349663))


# ---------------------------------------------------------------- objets

func _build_objects() -> void:
	# Éléments candidats par caractère et par zone.
	var cands: Dictionary = {}
	for id: String in elements:
		var el: Dictionary = elements[id]
		var ch: String = str(el.get("caractere", ""))
		if not ["objet", "decal"].has(str(el.get("type", ""))) or ch.length() != 1:
			continue
		for z: int in _zones_of(el):
			var key: String = "%s|%d" % [ch, z]
			if not cands.has(key):
				cands[key] = []
			(cands[key] as Array).append(id)
	var seen: Dictionary = {}
	for y: int in map.height:
		for x: int in map.width:
			var t: Vector2i = Vector2i(x, y)
			var ch: String = map.at(t)
			var key: String = "%s|%d" % [ch, zone_at(t)]
			if seen.has(t) or not cands.has(key):
				continue
			var cells: Array[Vector2i] = _component(t, ch, zone_at(t), seen)
			var rect: Rect2i = Rect2i(cells[0], Vector2i.ONE)
			for c: Vector2i in cells:
				rect = rect.merge(Rect2i(c, Vector2i.ONE))
			_place(_best(cands[key], rect.size), cells, rect, zone_at(t))


## Cases contiguës (4-voisinage) de même caractère dans la même zone.
func _component(start: Vector2i, ch: String, zone: int, seen: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var todo: Array[Vector2i] = [start]
	seen[start] = true
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		out.append(c)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if not seen.has(nb) and map.at(nb) == ch and zone_at(nb) == zone:
				seen[nb] = true
				todo.append(nb)
	return out


## Parmi plusieurs éléments du même caractère dans la zone, celui dont l'emprise ressemble le plus.
func _best(ids: Array, size: Vector2i) -> String:
	var best: String = str(ids[0])
	var bd: int = 1 << 30
	for id: Variant in ids:
		var tc: Array = (elements[id] as Dictionary).get("taille_cases", [1, 1])
		var d: int = absi(int(tc[0]) - size.x) + absi(int(tc[1]) - size.y)
		if d < bd:
			bd = d
			best = str(id)
	return best


func _place(id: String, cells: Array[Vector2i], rect: Rect2i, zone: int) -> void:
	var el: Dictionary = elements[id]
	var files: Array = el.get("fichiers", [])
	var tex: Texture2D = _texture(str(files[0])) if not files.is_empty() else null
	if tex == null:
		return
	# Objet entouré surtout d'eau : de l'eau dessous (les marges transparentes de l'image ne
	# doivent pas montrer un carré de sol).
	var wet: int = 0
	var dry: int = 0
	for c: Vector2i in cells:
		covered[c] = true
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			# Voisins hors de l'objet seulement (un lavoir posé sur « ~ » n'est pas entouré d'eau).
			if cells.has(c + d):
				continue
			var nb: String = map.at(c + d)
			if nb == "~":
				wet += 1
			elif GkMap.WALK.contains(nb):
				dry += 1
	if wet > dry:
		for c: Vector2i in cells:
			water_under[c] = true
	var t: float = map.tile
	var foot: Rect2 = Rect2(Vector2(rect.position) * t, Vector2(rect.size) * t)
	var size: Vector2 = tex.get_size()
	var cat: String = str(el.get("categorie", ""))
	var flat: bool = str(el.get("type", "")) == "decal" or cat == "sortie"
	var holder: Node2D = Node2D.new()
	var sp: Sprite2D = Sprite2D.new()
	sp.texture = tex
	holder.add_child(sp)
	var s: float
	if str(el.get("type", "")) == "decal":
		# À plat : tient dans l'emprise, centré.
		s = minf(foot.size.x / size.x, foot.size.y / size.y)
		holder.position = foot.get_center()
	else:
		# Debout : largeur de l'emprise, bas aligné, débord vers le haut permis.
		var hmax: float = foot.size.y + float(el.get("debord_haut_cases", 0)) * t
		s = minf(foot.size.x / size.x, hmax / size.y)
		holder.position = Vector2(foot.get_center().x, foot.end.y)
		sp.position = Vector2(0, -size.y * s * 0.5)
	sp.scale = Vector2(s, s)
	if not flat:
		sp.light_mask = LIGHT_MASK
	(under if flat else self).add_child(holder)
	# Ombre portée fournie à part, décalée par rapport au coin haut gauche de l'objet.
	var shadow: Texture2D = _texture(str(el.get("ombre", "")))
	if shadow:
		var off: Array = el.get("ombre_decalage", [0, 0])
		var sh: Sprite2D = Sprite2D.new()
		sh.texture = shadow
		sh.centered = false
		sh.scale = Vector2(s, s)
		sh.position = holder.position + sp.position - size * s * 0.5 + Vector2(float(off[0]), float(off[1])) * s
		under.add_child(sh)
	var kind: String = ""
	if str((el.get("animation", {}) as Dictionary).get("methode", "")) == "jeu":
		kind = "tremble" if cat == "cachette" else "tangage"
	var inst: Dictionary = {"id": id, "cells": cells, "rect": rect, "zone": zone, "holder": holder, "sprite": sp,
		"kind": kind, "base": sp.position, "phase": float(_hash(rect.position) % 628) / 100.0}
	# Image de l'état ouvert (cachette) : même échelle, calée sur le coin haut gauche de la fermée.
	var open_tex: Texture2D = _texture(str(el.get("ouvert", "")))
	if open_tex:
		var off2: Array = el.get("ouvert_decalage", [0, 0])
		var op: Sprite2D = Sprite2D.new()
		op.texture = open_tex
		op.centered = false
		op.scale = Vector2(s, s)
		op.position = sp.position - size * s * 0.5 + Vector2(float(off2[0]), float(off2[1])) * s
		op.visible = false
		op.light_mask = sp.light_mask
		holder.add_child(op)
		inst["open_sprite"] = op
	if not flat:
		_add_shape(inst, el, tex, str(files[0]), size * s)
	instances.append(inst)
	inst["x0"] = holder.position.x
	if kind != "":
		_animated.append(inst)


# ---------------------------------------------------------------- forme des objets

## Empreinte au sol et silhouette de l'objet posé (`_shape`), ramenées dans le repère de la carte et
## coupées aux cases de l'objet (la grille A* des IA reste juste). Objets qui cachent la vue
## (« bloque_vue » de l'index, sinon les caractères de GkMap.OCCLUDE) : corps solide qui bloque aussi
## la vue ; objets bas (GkMap.LOW) : le passage seulement.
func _add_shape(inst: Dictionary, el: Dictionary, tex: Texture2D, rel: String, drawn: Vector2) -> void:
	var ch: String = str(el.get("caractere", ""))
	var blocks: bool = bool(el.get("bloque_vue", GkMap.OCCLUDE.contains(ch)))
	if not GkRules.on("decor_formes") or not blocks and not GkMap.LOW.contains(ch):
		return
	var sh: Dictionary = _shape(tex, rel, drawn)
	if (sh.get("polys", []) as Array).is_empty():
		return
	var holder: Node2D = inst["holder"]
	var r: Rect2 = Rect2(Vector2((inst["rect"] as Rect2i).position) * map.tile, Vector2((inst["rect"] as Rect2i).size) * map.tile)
	var box: PackedVector2Array = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)])
	var polys: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in sh["polys"]:
		var pts: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in poly:
			pts.append(holder.position + p)
		for clipped: PackedVector2Array in Geometry2D.intersect_polygons(pts, box):
			polys.append(clipped)
	if polys.is_empty():
		return
	inst["polys"] = polys
	inst["blocks_view"] = blocks
	inst["mask"] = sh["mask"]
	inst["mask_scale"] = sh["scale"]
	inst["mask_rect"] = Rect2(holder.position + Vector2(-drawn.x * 0.5, -drawn.y), drawn)
	inst["sort_y"] = holder.position.y
	inst["fade"] = 1.0
	for c: Vector2i in inst["cells"]:
		shaped[c] = true


## Forme d'un objet à sa taille dessinée, calculée une fois par image et par taille (SPEC-GORDEKA,
## décor) : {mask: BitMap de la silhouette, foot: BitMap de l'empreinte au sol, scale (px de jeu par
## point), polys: contours de l'empreinte dans le repère du porteur (pied au milieu du bord bas)}.
##
## Empreinte au sol en vue 3/4 (de face ou en coin) :
## 1. silhouette (alpha) à SHAPE_STEP px près, puis ouverture morphologique : les parties plus fines
##    que decor_finesse_px (mât, pieds, perche, corde) disparaissent, elles ne bloquent pas ;
## 2. enveloppe basse : pour chaque colonne, le point opaque le plus bas (le contact avec le sol) ;
## 3. le dessus de l'empreinte s'en déduit par symétrie centrale (rectangle, losange d'une vue en coin,
##    fuseau d'une coque, disque : toutes symétriques par leur centre), autour du centre placé à la
##    hauteur des coins gauche et droit (les coins d'un losange) mais au moins decor_profondeur_min
##    au-dessus du point le plus bas (objet vu de face) ; jamais au-dessus de la silhouette ;
## 4. nouvelle ouverture, puis contours simplifiés (SHAPE_EPSILON).
## Tout ce qui est au-dessus de l'empreinte (toit, face haute, mât) passe devant un perso qui est
## derrière et le masque (`masking`).
static func _shape(tex: Texture2D, key: String, drawn: Vector2) -> Dictionary:
	var thin: float = GkRules.f("decor_finesse_px")
	var dmin_px: float = GkRules.px("decor_profondeur_min")
	var ck: String = "%s|%d|%d|%.1f|%.1f" % [key, roundi(drawn.x), roundi(drawn.y), thin, dmin_px]
	if _shape_cache.has(ck):
		return _shape_cache[ck]
	var out: Dictionary = {}
	_shape_cache[ck] = out
	if not _image_cache.has(key):
		var src: Image = tex.get_image()
		if src != null and not src.is_empty():
			src = src.duplicate() as Image
			if src.is_compressed():
				src.decompress()
			src.convert(Image.FORMAT_RGBA8)
			src.resize(maxi(1, src.get_width() / SHAPE_SOURCE_DIV), maxi(1, src.get_height() / SHAPE_SOURCE_DIV),
				Image.INTERPOLATE_BILINEAR)
		_image_cache[key] = src
	var img: Image = _image_cache[key]
	if img == null or img.is_empty():
		push_warning("GkDecor : image illisible pour la forme de « %s », collision par cases" % key)
		return out
	img = img.duplicate() as Image
	var mw: int = maxi(1, ceili(drawn.x / SHAPE_STEP))
	var mh: int = maxi(1, ceili(drawn.y / SHAPE_STEP))
	img.resize(mw, mh, Image.INTERPOLATE_BILINEAR)
	var full: Rect2i = Rect2i(0, 0, mw, mh)
	var sc: Vector2 = Vector2(drawn.x / mw, drawn.y / mh)
	var r: int = maxi(0, roundi(thin * 0.5 / SHAPE_STEP))
	var bm: BitMap = BitMap.new()
	bm.create_from_image_alpha(img, SHAPE_ALPHA)
	# 1. Silhouette sans ses parties fines.
	var solid: BitMap = BitMap.new()
	solid.create_from_image_alpha(img, SHAPE_ALPHA)
	if r > 0:
		solid.grow_mask(-r, full)
		solid.grow_mask(r, full)
	var sil: PackedByteArray = bm.convert_to_image().get_data()
	var sol: PackedByteArray = solid.convert_to_image().get_data()
	# 2. Enveloppe basse (et haut de la silhouette, que l'empreinte ne dépasse pas).
	var bottom: PackedInt32Array = PackedInt32Array()
	var top: PackedInt32Array = PackedInt32Array()
	bottom.resize(mw)
	top.resize(mw)
	var x0: int = -1
	var x1: int = -1
	var ymax: int = -1
	for x: int in mw:
		bottom[x] = -1
		for y: int in range(mh - 1, -1, -1):
			if sol[y * mw + x] > 0:
				bottom[x] = y
				break
		top[x] = mh
		for y: int in mh:
			if sil[y * mw + x] > 0:
				top[x] = y
				break
		if bottom[x] >= 0:
			x1 = x
			if x0 < 0:
				x0 = x
			ymax = maxi(ymax, bottom[x])
	if x0 < 0:
		return out
	# 3. Centre : hauteur des coins gauche et droit (quelques colonnes), au moins dmin/2 au-dessus du bas.
	var k: int = maxi(1, (x1 - x0 + 1) / 16)
	var side: float = (_mean_valid(bottom, x0, x0 + k) + _mean_valid(bottom, x1 - k, x1)) * 0.5
	var yc: float = minf(side, float(ymax) - dmin_px / sc.y * 0.5)
	var foot_data: PackedByteArray = PackedByteArray()
	foot_data.resize(mw * mh * 2)
	for x: int in range(x0, x1 + 1):
		if bottom[x] < 0:
			continue
		var xm: int = x0 + x1 - x
		var bm_y: int = bottom[xm] if bottom[xm] >= 0 else bottom[x]
		var t: int = maxi(roundi(2.0 * yc - float(bm_y)), top[x])
		for y: int in range(maxi(t, 0), bottom[x] + 1):
			foot_data[(y * mw + x) * 2] = 255
			foot_data[(y * mw + x) * 2 + 1] = 255
	var foot: BitMap = BitMap.new()
	foot.create_from_image_alpha(Image.create_from_data(mw, mh, false, Image.FORMAT_LA8, foot_data), 0.5)
	# 4. Sans parties fines, puis contours.
	if r > 0:
		foot.grow_mask(-r, full)
		foot.grow_mask(r, full)
	var org: Vector2 = Vector2(-drawn.x * 0.5, -drawn.y)
	var polys: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in foot.opaque_to_polygons(full, SHAPE_EPSILON):
		if poly.size() < 3 or absf(_area(poly)) < SHAPE_MIN_AREA:
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in poly:
			pts.append(org + p * sc)
		polys.append(pts)
	out["mask"] = bm
	out["foot"] = foot
	out["scale"] = sc
	out["polys"] = polys
	return out


static func _mean_valid(a: PackedInt32Array, from: int, to: int) -> float:
	var s: float = 0.0
	var n: int = 0
	for i: int in range(maxi(from, 0), mini(to, a.size() - 1) + 1):
		if a[i] >= 0:
			s += a[i]
			n += 1
	return s / maxf(1.0, n)


static func _area(poly: PackedVector2Array) -> float:
	var a: float = 0.0
	for i: int in poly.size():
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Instance d'un objet qui cache la vue dessiné devant ce point (pied d'un perso en `p`) et dont la
## silhouette le recouvre, au pied et à `h` px au-dessus ; -1 sinon.
func masking(p: Vector2, h: float) -> int:
	for i: int in instances.size():
		var inst: Dictionary = instances[i]
		if not inst.get("blocks_view", false) or p.y >= float(inst["sort_y"]):
			continue
		var r: Rect2 = inst["mask_rect"]
		if r.has_point(p) and _covers(inst, p) and _covers(inst, p - Vector2(0, h)):
			return i
	return -1


func _covers(inst: Dictionary, p: Vector2) -> bool:
	var r: Rect2 = inst["mask_rect"]
	if not r.has_point(p):
		return false
	var bm: BitMap = inst["mask"]
	var q: Vector2i = Vector2i((p - r.position) / (inst["mask_scale"] as Vector2))
	var sz: Vector2i = bm.get_size()
	return bm.get_bitv(q.clamp(Vector2i.ZERO, sz - Vector2i.ONE))


## Fondu des objets qui masquent un coéquipier (`which` : index d'instance → vrai), vers l'opacité
## `alpha` ; les autres reviennent opaques.
func update_fades(which: Dictionary, alpha: float, dt: float) -> void:
	for i: int in instances.size():
		var inst: Dictionary = instances[i]
		if not inst.has("fade"):
			continue
		var want: float = alpha if which.has(i) else 1.0
		var f: float = move_toward(float(inst["fade"]), want, FADE_SPEED * dt)
		if f != float(inst["fade"]):
			inst["fade"] = f
			(inst["holder"] as Node2D).modulate.a = f


## Contrôle des formes (tools/gordeka/masques_decor.py, `--gk-export-masques=<dossier>`) : pour chaque
## objet en image, sa première pose sur la carte en PNG (2 px par px de jeu) : l'image, l'empreinte au
## sol en vert (ce qui bloque, coupée aux cases de l'objet), la zone qui masque un perso derrière en
## violet, le cadre des cases en pointillé blanc.
func export_masks(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var done: Dictionary = {}
	var n: int = 0
	for inst: Dictionary in instances:
		var id: String = str(inst["id"])
		if done.has(id) or not inst.has("polys"):
			continue
		done[id] = true
		var sp: Sprite2D = inst["sprite"]
		var src: Image = sp.texture.get_image().duplicate() as Image
		if src.is_compressed():
			src.decompress()
		src.convert(Image.FORMAT_RGBA8)
		var r: Rect2 = inst["mask_rect"]
		var cells: Rect2 = Rect2(Vector2((inst["rect"] as Rect2i).position) * map.tile, Vector2((inst["rect"] as Rect2i).size) * map.tile)
		var view: Rect2 = r.merge(cells).grow(8.0)
		var k: float = 2.0
		var w: int = ceili(view.size.x * k)
		var h: int = ceili(view.size.y * k)
		src.resize(ceili(r.size.x * k), ceili(r.size.y * k), Image.INTERPOLATE_BILINEAR)
		var outi: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		var off: Vector2i = Vector2i(((r.position - view.position) * k).round())
		var sh: Dictionary = _shape(sp.texture, str((elements[id] as Dictionary)["fichiers"][0]), r.size)
		var foot: BitMap = sh["foot"]
		var bm: BitMap = sh["mask"]
		var sc: Vector2 = sh["scale"]
		for y: int in h:
			for x: int in w:
				var wp: Vector2 = view.position + Vector2(x, y) / k        # repère de la carte
				var c: Color = Color("cfc8b6") if (x / 16 + y / 16) % 2 == 0 else Color("bdb6a4")
				var q: Vector2i = Vector2i(x, y) - off
				if q.x >= 0 and q.y >= 0 and q.x < src.get_width() and q.y < src.get_height():
					c = c.blend(src.get_pixelv(q))
				var mq: Vector2i = Vector2i((wp - r.position) / sc)
				if mq.x >= 0 and mq.y >= 0 and mq.x < bm.get_size().x and mq.y < bm.get_size().y:
					if foot.get_bitv(mq) and cells.has_point(wp):
						c = c.blend(Color(0.1, 0.85, 0.3, 0.55))
					elif bm.get_bitv(mq):
						c = c.blend(Color(0.6, 0.2, 0.9, 0.35))
				var on_edge: bool = absf(wp.x - cells.position.x) < 1.0 or absf(wp.x - cells.end.x) < 1.0 \
					or absf(wp.y - cells.position.y) < 1.0 or absf(wp.y - cells.end.y) < 1.0
				if on_edge and cells.grow(1.0).has_point(wp) and (x + y) / 6 % 2 == 0:
					c = Color.WHITE
				outi.set_pixel(x, y, c)
		outi.save_png(dir.path_join(id + ".png"))
		n += 1
	print("[gk] masques du décor : %d images dans %s" % [n, dir])
	map.get_tree().quit.call_deferred()


func _instance_at(t: Vector2i) -> int:
	for i: int in instances.size():
		if (instances[i]["cells"] as Array).has(t):
			return i
	return -1


# ---------------------------------------------------------------- animation « jeu »

func _process(dt: float) -> void:
	_t += dt
	var game: Node = map.get_parent()
	for inst: Dictionary in _animated:
		var sp: Sprite2D = inst["sprite"]
		var base: Vector2 = inst["base"]
		var ph: float = inst["phase"]
		match str(inst["kind"]):
			"tangage":
				sp.rotation = deg_to_rad(SWAY_DEG) * sin(_t * SWAY_SPEED + ph)
				sp.position = base + Vector2(0, BOB_PX * sin(_t * BOB_SPEED + ph))
			"tremble":
				# Ouverture, écrasement et tremblement décidés par la partie (gk_game.cachette_look),
				# appliqués au porteur : l'échelle part du bas de l'objet, posé au sol.
				var cell: Vector2i = (inst["cells"] as Array)[0]
				var i: int = map.cachettes.find(cell)
				if i < 0 or game == null or not game.has_method("cachette_look"):
					continue
				var look: Dictionary = game.cachette_look(i)
				var sq: float = float(look["squash"])
				var holder: Node2D = inst["holder"]
				holder.scale = Vector2(1.0 + sq * 0.6, 1.0 - sq)
				holder.position.x = float(inst["x0"]) + float(look["dx"])
				set_open(cell, float(look["open"]))


# ---------------------------------------------------------------- outils

## Zones de la carte où l'élément apparaît. « Bassin (quai nord) » vaut la zone « Bassin » ; un nom
## qui ne correspond à aucune zone (« couloirs… », « masses entre zones… ») vaut « hors zones » (-1).
func _zones_of(el: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for s: Variant in el.get("zones", []):
		var base: String = str(s).split(" (")[0].strip_edges()
		var found: bool = false
		for i: int in map.zones.size():
			if str(map.zones[i]["name"]) == base:
				found = true
				if not out.has(i):
					out.append(i)
		if not found and not out.has(-1):
			out.append(-1)
	return out


func _texture(rel: String) -> Texture2D:
	if rel == "":
		return null
	var p: String = _dir.path_join(rel)
	if _tex.has(p):
		return _tex[p]
	var tex: Texture2D = null
	if p.begins_with("res://"):
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
	elif FileAccess.file_exists(p):
		var img: Image = Image.load_from_file(p)
		if img:
			tex = ImageTexture.create_from_image(img)
	_tex[p] = tex
	return tex
