class_name BkDecor
extends Node2D
## Décor en images (pixelforge, intégré élément par élément par tools/blackout/integre_decor.py),
## posé sur la carte avec repli sur le dessin procédural de BkMap pour tout ce qui n'a pas encore
## d'image. La grille A* reste celle des cases ; la collision et l'occlusion de la vue des objets en
## image suivent leur forme réelle, calculée au chargement depuis l'alpha de l'image (`_shape`) :
## seule l'empreinte au sol arrête le passage et la vue, le haut de l'image (toit, face haute, mât)
## passe devant les persos qui sont derrière (tri par profondeur sur le pied de l'objet).
##
## index.json (assets/blackout/decor/) : {carte, elements: {id: {type, categorie, caractere, zones,
## taille_cases, debord_haut_cases, hauteur_cases, animation, fichiers: [chemins relatifs], ombre, ombre_decalage,
## ouvert, ouvert_decalage}}}.
## - tuile_sol : texture répétée sur les cases du caractère dans ses zones (taille_cases cases par
##   tuile ; plusieurs fichiers = variantes mélangées de façon déterministe) ;
## - objet : une instance par groupe de cases contiguës du caractère dans une zone, à l'échelle de
##   l'emprise, centrée en largeur, bas aligné, débord vers le haut permis ;
## - decal (et sorties, où l'on marche) : à plat, sous les persos.
## Ce nœud porte les objets debout : il rejoint le calque y-trié des persos (les persos passent
## derrière les objets hauts) ; `under` porte les ombres et ce qui est à plat.
##
## Placement propre à une carte (assets/maps/<id>/decor.json, écrit par tools/blackout/make_port_v3.py) :
## {objets: {"x,y": {id, miroir}}} impose l'élément d'un groupe de cases (clé : son coin haut gauche) et
## le retourne en miroir (image, ombre, emprise et masque) ; {ornements: [{id, x, y, l, h, miroir}]}
## pose des éléments sans effet de jeu (fanions, linge, lanternes, fumée…) : pied en (x, y) cases,
## largeur l et hauteur h en cases. Un élément sans image mais avec « provisoire » (index.json) est
## dessiné par le code (BkProvisoire) en attendant pixelforge.

const DIR: String = "res://assets/blackout/decor"
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
## la grille ombrent (un objet n'est pas assombri par sa propre base ; voir BkGame._make_view).
const LIGHT_MASK: int = 2
## Vitesse du fondu de l'objet qui masque un coéquipier (opacité par seconde).
const FADE_SPEED: float = 4.0

## Formes déjà calculées (même image, même taille dessinée, même base), gardées d'une partie à l'autre.
static var _shape_cache: Dictionary = {}
## Masques de pixelforge déjà lus (par dossier, objet et taille dessinée).
static var _pf_cache: Dictionary = {}
## Images lues pour les formes, réduites SHAPE_SOURCE_DIV fois (une lecture par image : en WebGL, c'est
## une relecture du GPU ; réduite, elle pèse peu en mémoire et reste plus fine que le masque).
static var _image_cache: Dictionary = {}

var map: BkMap
var under: Node2D
var elements: Dictionary = {}
## Cases dont le dessin procédural est remplacé (objets en image, sols pleins sur un caractère
## non marchable comme l'eau ou les toits) : BkMap et BkWater ne les dessinent plus.
var covered: Dictionary = {}
## Cases d'un objet en image posé sur l'eau (barques du bassin) : BkWater y dessine l'eau, pas de sol.
var water_under: Dictionary = {}
## Cases d'un objet en image dont la forme a été calculée : BkMap n'y pose plus de rectangle de
## collision, mais les polygones de base de l'instance.
var shaped: Dictionary = {}
## Instances posées : {id, cells: Array[Vector2i], rect: Rect2i, zone, holder, sprite, kind, base, phase}
## et, si la forme est connue : polys (bases au sol, repère de la carte), blocks_view, mask (BitMap de
## la silhouette), mask_rect (zone dessinée, repère de la carte), mask_scale, sort_y, fade.
var instances: Array = []
## Instances qui cachent la vue mais plus basses que l'œil du chasseur (BkMap les sort de la couche de
## vue) : la vue passe au-dessus, sauf vers les points du corps plus bas qu'elles (`low_blocks`).
var low_view: Array[int] = []
var _dir: String = DIR
var _tex: Dictionary = {}           # chemin → Texture2D (ou null si absent)
var _floors: Dictionary = {}        # "car|zone" → {textures: Array, cases: Vector2i}
var _zone_grid: PackedInt32Array = PackedInt32Array()
var _animated: Array = []
var _t: float = 0.0
## decor.json de la carte : objets imposés (« x,y » → {id, miroir}) et ornements.
var _layout_objects: Dictionary = {}
var _ornaments: Array = []


## Lit l'index et prépare sols et objets. Sans index (ou pour une autre carte), ne fait rien :
## tout reste procédural.
func setup(m: BkMap) -> void:
	map = m
	name = "Decor"
	y_sort_enabled = true
	under = Node2D.new()
	under.name = "DecorSol"
	# QA : `--bk-decor-dir=/chemin/abs` lit un décor hors projet (images non importées).
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--bk-decor-dir="):
			_dir = arg.trim_prefix("--bk-decor-dir=")
	_zone_grid.resize(map.width * map.height)
	for y: int in map.height:
		for x: int in map.width:
			_zone_grid[y * map.width + x] = map.zone_of(Vector2i(x, y))
	# Décor propre à la carte (assets/maps/<id>/decor/index.json : placeholders d'une nouvelle carte,
	# images communes citées en res://) ; sinon le décor commun, si son index nomme cette carte.
	var own: String = "res://assets/maps/%s/decor" % map.decor_id
	if _dir == DIR and FileAccess.file_exists(own.path_join("index.json")):
		_dir = own
	var path: String = _dir.path_join("index.json")
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or str((data as Dictionary).get("carte", map.decor_id)) != map.decor_id:
		return
	elements = (data as Dictionary).get("elements", {})
	var lp: String = "res://assets/maps/%s/decor.json" % map.map_id
	if FileAccess.file_exists(lp):
		var lay: Variant = JSON.parse_string(FileAccess.get_file_as_string(lp))
		if lay is Dictionary:
			_layout_objects = (lay as Dictionary).get("objets", {})
			_ornaments = (lay as Dictionary).get("ornements", [])
	_build_floors()
	_build_objects()
	_build_ornaments()
	set_process(not _animated.is_empty())
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--bk-export-masques="):
			export_masks(arg.trim_prefix("--bk-export-masques="))


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
	# Poses imposées par la carte (zones.json → « objets » : [{element, rect: [x, y, w, h]}]) : l'élément
	# sur les cases du rect qui portent son caractère (deux cabines côte à côte restent deux images).
	for o: Variant in map.info.get("objets", []):
		var od: Dictionary = o
		var oid: String = str(od.get("element", ""))
		var r: Array = od.get("rect", [])
		if not elements.has(oid) or r.size() != 4:
			continue
		var och: String = str((elements[oid] as Dictionary).get("caractere", ""))
		var orect: Rect2i = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		var ocells: Array[Vector2i] = []
		for yy: int in range(orect.position.y, orect.end.y):
			for xx: int in range(orect.position.x, orect.end.x):
				var ot: Vector2i = Vector2i(xx, yy)
				if map.at(ot) == och and not seen.has(ot):
					seen[ot] = true
					ocells.append(ot)
		if not ocells.is_empty():
			_place(oid, ocells, orect, zone_at(ocells[0]))
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
			var lay: Dictionary = _layout_objects.get("%d,%d" % [rect.position.x, rect.position.y], {})
			var id: String = str(lay.get("id", ""))
			# Élément imposé sans image ni provisoire (variante pas encore livrée) : celui par défaut.
			if not elements.has(id) or ((elements[id] as Dictionary).get("fichiers", []) as Array).is_empty() \
					and str((elements[id] as Dictionary).get("provisoire", "")) == "":
				id = _best(cands[key], rect.size)
			_place(id, cells, rect, zone_at(t), bool(lay.get("miroir", false)))


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


func _place(id: String, cells: Array[Vector2i], rect: Rect2i, zone: int, mirror: bool = false) -> void:
	var el: Dictionary = elements[id]
	var files: Array = el.get("fichiers", [])
	var tex: Texture2D = _texture(str(files[0])) if not files.is_empty() else null
	if tex == null:
		if str(el.get("provisoire", "")) != "":
			_place_provisoire(id, el, cells, rect, mirror)
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
			elif BkMap.WALK.contains(nb):
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
	sp.flip_h = mirror
	holder.add_child(sp)
	var s: float
	if str(el.get("type", "")) == "decal":
		# À plat : tient dans l'emprise, centré.
		s = minf(foot.size.x / size.x, foot.size.y / size.y)
		holder.position = foot.get_center()
	else:
		# Debout : largeur de l'emprise, bas aligné, débord vers le haut permis ; ou, avec hauteur_cases,
		# hauteur dessinée imposée (la largeur suit, centrée : débord latéral si l'image est plus large).
		s = _standing_scale(el, foot.size, size, t)
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
		if mirror:
			# Miroir autour de l'axe vertical de l'objet.
			sh.flip_h = true
			sh.position.x = 2.0 * holder.position.x - sh.position.x - shadow.get_width() * s
		under.add_child(sh)
	var kind: String = ""
	if str((el.get("animation", {}) as Dictionary).get("methode", "")) == "jeu":
		kind = "tremble" if cat == "cachette" else "tangage"
	var inst: Dictionary = {"id": id, "cells": cells, "rect": rect, "zone": zone, "holder": holder, "sprite": sp,
		"kind": kind, "base": sp.position, "phase": float(_hash(rect.position) % 628) / 100.0, "miroir": mirror}
	# Image de l'état ouvert (cachette) : même échelle, calée sur le coin haut gauche de la fermée.
	var open_tex: Texture2D = _texture(str(el.get("ouvert", "")))
	if open_tex:
		var off2: Array = el.get("ouvert_decalage", [0, 0])
		var op: Sprite2D = Sprite2D.new()
		op.texture = open_tex
		op.centered = false
		op.scale = Vector2(s, s)
		op.position = sp.position - size * s * 0.5 + Vector2(float(off2[0]), float(off2[1])) * s
		if mirror:
			op.flip_h = true
			op.position.x = -op.position.x - open_tex.get_width() * s
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


## Échelle d'un objet debout dessiné sur une emprise de `foot` px (image de `size` px, case de `t` px) :
## - hauteur_cases (index.json, décimales) : hauteur dessinée imposée, quelle que soit l'emprise (une maison
##   reste une maison sur 3 ou 4 cases) ; l'image, centrée sur ses cases, peut en déborder sur les côtés
##   (débord latéral : emprise bloquante et masque suivent, BkMap bloque les cases de sol couvertes) ;
## - sinon largeur des cases, débord vers le haut de debord_haut_cases au plus (règle d'origine).
static func _standing_scale(el: Dictionary, foot: Vector2, size: Vector2, t: float) -> float:
	var h: float = float(el.get("hauteur_cases", 0.0))
	if h > 0.0:
		return h * t / size.y
	return minf(foot.x / size.x, (foot.y + float(el.get("debord_haut_cases", 0)) * t) / size.y)


# ---------------------------------------------------------------- forme des objets

## Forme de l'objet posé : masques de pixelforge s'il y en a pour cet objet (`_pf_shape`), sinon le
## calcul local sur la silhouette (`_shape`, repli ; `decor_masques_pf` = 0 l'impose partout). Elle
## est ramenée dans le repère de la carte et l'empreinte est coupée aux cases de l'objet, élargies au
## débord latéral de l'image (BkMap aligne la grille A* des IA sur cette emprise). Vue bloquée : `blocks_view` de pixelforge, sinon « bloque_vue » de l'index,
## sinon les caractères de BkMap.OCCLUDE ; les autres objets bloquent le passage seulement.
## Pixelforge donne aussi la ligne de tri (baseline_y : un perso dont les pieds sont au-dessus est
## derrière l'objet) : le porteur, que trie le calque des persos, y est descendu ou remonté.
func _add_shape(inst: Dictionary, el: Dictionary, tex: Texture2D, rel: String, drawn: Vector2) -> void:
	var ch: String = str(el.get("caractere", ""))
	var blocks: bool = bool(el.get("bloque_vue", BkMap.OCCLUDE.contains(ch)))
	if not BkRules.on("decor_formes") or not blocks and not BkMap.LOW.contains(ch):
		return
	var sh: Dictionary = {}
	var refus: String = ""
	if BkRules.on("decor_masques_pf"):
		sh = _pf_shape(str(inst["id"]), tex, rel, drawn)
		refus = str(sh.get("refus", ""))
	if not sh.has("polys"):
		sh = _shape(tex, rel, drawn)
	if (sh.get("polys", []) as Array).is_empty():
		return
	if bool(inst.get("miroir", false)):
		sh = _mirror_shape(sh, drawn)
	# La carte décide des objets bas (banc, étal…) : pixelforge peut seulement lever le blocage de vue.
	blocks = blocks and bool(sh.get("blocks_view", blocks))
	var holder: Node2D = inst["holder"]
	var sp: Sprite2D = inst["sprite"]
	var top_left: Vector2 = holder.position + sp.position - drawn * 0.5
	var r: Rect2 = Rect2(Vector2((inst["rect"] as Rect2i).position) * map.tile, Vector2((inst["rect"] as Rect2i).size) * map.tile)
	# Image plus large que ses cases (hauteur_cases) : l'emprise peut déborder sur les côtés, jusqu'au
	# bord de l'image.
	var lat: float = maxf(0.0, (drawn.x - r.size.x) * 0.5)
	r = r.grow_individual(lat, 0.0, lat, 0.0)
	var box: PackedVector2Array = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)])
	var polys: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in sh["polys"]:
		var pts: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in poly:
			pts.append(top_left + p)
		for clipped: PackedVector2Array in Geometry2D.intersect_polygons(pts, box):
			polys.append(clipped)
	if polys.is_empty():
		return
	if sh.has("baseline"):
		var dy: float = top_left.y + float(sh["baseline"]) - holder.position.y
		holder.position.y += dy
		for c: Node in holder.get_children():
			(c as Node2D).position.y -= dy
		inst["base"] = sp.position
	inst["polys"] = polys
	inst["blocks_view"] = blocks
	inst["mask"] = sh["mask"]
	inst["mask_scale"] = sh["scale"]
	inst["mask_rect"] = Rect2(top_left, drawn)
	# Hauteur de l'objet pour la vue (#607) : hauteur de la silhouette dessinée à l'écran (la profondeur
	# en vue 3/4 compte : on penche vers « ça cache », comme avant).
	var pbb: Rect2 = Rect2(polys[0][0], Vector2.ZERO)
	for poly: PackedVector2Array in polys:
		for p: Vector2 in poly:
			pbb = pbb.expand(p)
	inst["poly_bb"] = pbb
	var sil: Dictionary = _shape(tex, rel, drawn)
	if sil.has("mask"):
		inst["view_h"] = _mask_height(sil["mask"]) * (sil["scale"] as Vector2).y
	else:
		inst["view_h"] = _mask_height(sh["mask"]) * (sh["scale"] as Vector2).y
	inst["sort_y"] = holder.position.y
	inst["fade"] = 1.0
	inst["shape_source"] = str(sh.get("source", "repli"))
	inst["shape_info"] = sh.get("info", {"refus_pixelforge": refus} if refus != "" else {})
	for c: Vector2i in inst["cells"]:
		shaped[c] = true


## Hauteur de la silhouette (en points du masque) : de sa première à sa dernière ligne opaque.
static func _mask_height(bm: BitMap) -> int:
	var sz: Vector2i = bm.get_size()
	var y0: int = -1
	var y1: int = -1
	for y: int in sz.y:
		for x: int in sz.x:
			if bm.get_bit(x, y):
				if y0 < 0:
					y0 = y
				y1 = y
				break
	return 0 if y0 < 0 else y1 - y0 + 1


## Forme retournée en miroir (objet posé en miroir) : emprise et masque autour de l'axe vertical de l'image.
func _mirror_shape(sh: Dictionary, drawn: Vector2) -> Dictionary:
	var out: Dictionary = sh.duplicate()
	var polys: Array[PackedVector2Array] = []
	for poly: PackedVector2Array in sh["polys"]:
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(poly.size() - 1, -1, -1):
			pts.append(Vector2(drawn.x - poly[i].x, poly[i].y))
		polys.append(pts)
	out["polys"] = polys
	var bm: BitMap = sh["mask"]
	var sz: Vector2i = bm.get_size()
	var m2: BitMap = BitMap.new()
	m2.create(sz)
	for y: int in sz.y:
		for x: int in sz.x:
			if bm.get_bit(x, y):
				m2.set_bit(sz.x - 1 - x, y, true)
	out["mask"] = m2
	return out


## Objet de jeu sans image, dessiné par le code (BkProvisoire) : posé au pied de son emprise, trié avec
## les persos ; sa collision reste le rectangle des cases (BkMap), qui ne le dessine plus.
func _place_provisoire(id: String, el: Dictionary, cells: Array[Vector2i], rect: Rect2i, mirror: bool) -> void:
	var t: float = map.tile
	for c: Vector2i in cells:
		covered[c] = true
	var pv: BkProvisoire = BkProvisoire.new()
	pv.kind = str(el["provisoire"])
	pv.size = Vector2(rect.size) * t
	pv.mirror = mirror
	pv.phase = float(_hash(rect.position) % 628) / 100.0
	pv.position = Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y) * t
	pv.light_mask = LIGHT_MASK
	add_child(pv)
	instances.append({"id": id, "cells": cells, "rect": rect, "zone": zone_at(rect.position), "holder": pv,
		"sprite": null, "kind": "", "base": Vector2.ZERO, "phase": pv.phase, "x0": pv.position.x, "provisoire": true})


## Ornements de decor.json (sans effet de jeu) : image de l'élément s'il en a une, sinon son provisoire.
## Couche (index.json → « couche ») : « sol » à plat sous les persos, « haut » au-dessus d'eux (fanions,
## linge tendus en hauteur), sinon triés avec eux sur leur pied.
func _build_ornaments() -> void:
	var t: float = map.tile
	for o: Variant in _ornaments:
		var od: Dictionary = o
		var id: String = str(od.get("id", ""))
		if not elements.has(id):
			continue
		var el: Dictionary = elements[id]
		var tc: Array = el.get("taille_cases", [1, 1])
		var l: float = float(od.get("l", tc[0]))
		var h: float = float(od.get("h", tc[1]))
		var foot: Vector2 = Vector2(float(od.get("x", 0.0)), float(od.get("y", 0.0))) * t
		var mirror: bool = bool(od.get("miroir", false))
		var layer: String = str(el.get("couche", ""))
		var host: Node2D = under if layer == "sol" else self
		var files: Array = el.get("fichiers", [])
		var tex: Texture2D = _texture(str(files[0])) if not files.is_empty() else null
		var node: Node2D
		if tex:
			var sp: Sprite2D = Sprite2D.new()
			sp.texture = tex
			sp.flip_h = mirror
			var sc: float = _standing_scale(el, Vector2(l, h) * t, tex.get_size(), t)
			sp.scale = Vector2(sc, sc)
			sp.position = Vector2(0, -tex.get_height() * sc * 0.5)
			node = Node2D.new()
			node.add_child(sp)
		elif str(el.get("provisoire", "")) != "":
			var pv: BkProvisoire = BkProvisoire.new()
			pv.kind = str(el["provisoire"])
			pv.size = Vector2(l, h) * t
			pv.mirror = mirror
			pv.phase = float(_hash(Vector2i(foot)) % 628) / 100.0
			node = pv
		else:
			continue
		node.position = foot
		if layer == "haut":
			node.z_index = 3
		host.add_child(node)


## Masques de pixelforge (tools/blackout/masques_pf.py) : <dossier du décor>/masques/<id>/masks.json
## (polygons de l'emprise au sol, baseline_y, blocks_view, en px de l'image intégrée) et occluder.png
## (ce qui passe devant un perso derrière). Alignés sur l'image intégrée : ignorés si sa taille a
## changé depuis (image réintégrée). Un calcul par objet et par taille dessinée, partagé par toutes
## ses poses sur la carte. Vide s'il n'y en a pas ; {refus: raison} si on les écarte pour le repli :
## confiance sous decor_masques_pf_confiance_min, ou emprise de plus de decor_masques_pf_part_max de
## la silhouette (emprise ratée, pleine).
func _pf_shape(id: String, tex: Texture2D, rel: String, drawn: Vector2) -> Dictionary:
	var tex_size: Vector2 = tex.get_size()
	var ck: String = "%s|%s|%d|%d" % [_dir, id, roundi(drawn.x), roundi(drawn.y)]
	if _pf_cache.has(ck):
		return _pf_cache[ck]
	var out: Dictionary = {}
	_pf_cache[ck] = out
	var dir: String = _dir.path_join("masques").path_join(id)
	if not FileAccess.file_exists(dir.path_join("masks.json")):
		# Image commune reprise par le décor d'une autre carte : ses masques restent au décor commun.
		dir = DIR.path_join("masques").path_join(id)
	if not FileAccess.file_exists(dir.path_join("masks.json")):
		return out
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("masks.json")))
	if not m is Dictionary:
		push_warning("BkDecor : masks.json illisible pour « %s », repli" % id)
		return out
	var md: Dictionary = m
	var size: Array = md.get("size", [0, 0])
	if size.size() != 2 or Vector2(float(size[0]), float(size[1])) != tex_size:
		push_warning("BkDecor : masques pixelforge de « %s » pour une image de %s, l'image fait %s : repli" % [id, size, tex_size])
		return out
	var k: Vector2 = drawn / tex_size          # px de jeu par px de l'image
	var polys: Array[PackedVector2Array] = []
	for poly: Variant in md.get("polygons", []):
		var pts: PackedVector2Array = PackedVector2Array()
		for q: Variant in (poly as Array):
			pts.append(Vector2(float(q[0]), float(q[1])) * k)
		if pts.size() >= 3:
			polys.append(pts)
	if polys.is_empty():
		return out
	var conf: float = float(md.get("confidence", 0.0))
	if conf < BkRules.f("decor_masques_pf_confiance_min"):
		out["refus"] = "confiance %.2f" % conf
		return out
	var sil: Dictionary = _shape(tex, rel, drawn)
	if sil.has("mask"):
		var area: float = 0.0
		for poly: PackedVector2Array in polys:
			area += absf(_area(poly))
		var sc: Vector2 = sil["scale"]
		var sil_area: float = float((sil["mask"] as BitMap).get_true_bit_count()) * sc.x * sc.y
		if sil_area > 0.0 and area / sil_area > BkRules.f("decor_masques_pf_part_max"):
			out["refus"] = "emprise = %d %% de la silhouette" % roundi(100.0 * area / sil_area)
			return out
	# Masquage : occluder.png à SHAPE_STEP px près (à défaut, la silhouette de l'image).
	var occ: Image = _read_image(dir.path_join("occluder.png"))
	if occ == null:
		return out
	occ.convert(Image.FORMAT_RGBA8)
	var mw: int = maxi(1, ceili(drawn.x / SHAPE_STEP))
	var mh: int = maxi(1, ceili(drawn.y / SHAPE_STEP))
	occ.resize(mw, mh, Image.INTERPOLATE_BILINEAR)
	var bm: BitMap = BitMap.new()
	bm.create_from_image_alpha(occ, SHAPE_ALPHA)
	out["polys"] = polys
	out["mask"] = bm
	out["scale"] = Vector2(drawn.x / mw, drawn.y / mh)
	# Tri sur le bord ARRIÈRE de l'emprise (pratique courante pour les objets fixes : la collision empêche
	# d'entrer dans l'emprise, tout perso aux pieds plus bas que back_y est devant) ; baseline_y en repli.
	out["baseline"] = clampf(float(md.get("back_y", md.get("baseline_y", tex_size.y))), 0.0, tex_size.y) * k.y
	out["blocks_view"] = bool(md.get("blocks_view", true))
	out["source"] = "pixelforge"
	out["info"] = {"confidence": md.get("confidence", 0.0), "warnings": md.get("warnings", [])}
	return out


## Image d'un fichier du décor : importée (jeu exporté) ou lue directement (QA, fichier pas encore
## importé par l'éditeur).
static func _read_image(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path) as Texture2D
		if t:
			img = t.get_image()
	elif FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	return img


## Forme d'un objet à sa taille dessinée, calculée une fois par image et par taille (GDD-BLACKOUT.md,
## décor) : {mask: BitMap de la silhouette, foot: BitMap de l'empreinte au sol, scale (px de jeu par
## point), polys: contours de l'empreinte en px de jeu depuis le coin haut gauche de l'image dessinée}.
## C'est le repli quand pixelforge n'a pas (encore) fourni les masques de l'objet (`_pf_shape`).
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
	var thin: float = BkRules.f("decor_finesse_px")
	var dmin_px: float = BkRules.px("decor_profondeur_min")
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
		push_warning("BkDecor : image illisible pour la forme de « %s », collision par cases" % key)
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
	var org: Vector2 = Vector2.ZERO
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


## Vue du chasseur (#607) : le point du corps à `z` px au-dessus du pied `p` est-il recouvert à l'écran
## par un objet qui cache la vue, dessiné devant le perso (pied du perso au-dessus de sa ligne de tri) ?
func covered_at(p: Vector2, z: float) -> bool:
	var q: Vector2 = p - Vector2(0.0, z)
	for inst: Dictionary in instances:
		if inst.get("blocks_view", false) and p.y < float(inst["sort_y"]) and _covers(inst, q):
			return true
	return false


## Vue du chasseur (#607) : la ligne de l'œil (`eye` px au-dessus de `a`) au point du corps à `z` px
## au-dessus de `b` passe-t-elle sous le haut d'un objet bas (hors couche de vue, `low_view`) dont elle
## traverse l'emprise ? Hauteur de la ligne linéaire le long du trajet : on teste l'entrée et la
## sortie de chaque morceau dans l'emprise.
func low_blocks(a: Vector2, b: Vector2, eye: float, z: float) -> bool:
	var seg: Rect2 = Rect2(a, Vector2.ZERO).expand(b)
	var len: float = maxf(a.distance_to(b), 1.0)
	for i: int in low_view:
		var inst: Dictionary = instances[i]
		var vh: float = float(inst["view_h"])
		if vh <= minf(eye, z) or not seg.intersects(inst["poly_bb"], true):
			continue
		for poly: PackedVector2Array in inst["polys"]:
			for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), poly):
				for q: Vector2 in piece:
					if lerpf(eye, z, a.distance_to(q) / len) < vh:
						return true
	return false


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


## Contrôle des formes (tools/blackout/masques_decor.py, `--bk-export-masques=<dossier>`) : pour chaque
## objet en image, sa première pose sur la carte en PNG (2 px par px de jeu), avec la forme que le jeu
## utilise vraiment : l'empreinte qui bloque (polygones de collision, coupés aux cases) en vert, la
## zone qui masque un perso derrière en violet, la ligne de tri en rouge, les cases en pointillé
## blanc. `_sources.json` donne la source de chaque forme (pixelforge ou repli).
func export_masks(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var done: Dictionary = {}
	var sources: Dictionary = {}
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
		var polys: Array = inst["polys"]
		var sort_y: float = float(inst["sort_y"])
		for y: int in h:
			for x: int in w:
				var wp: Vector2 = view.position + Vector2(x, y) / k        # repère de la carte
				var c: Color = Color("cfc8b6") if (x / 16 + y / 16) % 2 == 0 else Color("bdb6a4")
				var q: Vector2i = Vector2i(x, y) - off
				if q.x >= 0 and q.y >= 0 and q.x < src.get_width() and q.y < src.get_height():
					c = c.blend(src.get_pixelv(q))
				var inside: bool = false
				for poly: PackedVector2Array in polys:
					if Geometry2D.is_point_in_polygon(wp, poly):
						inside = true
						break
				if inside:
					c = c.blend(Color(0.1, 0.85, 0.3, 0.55))
				elif _covers(inst, wp):
					c = c.blend(Color(0.6, 0.2, 0.9, 0.35))
				if absf(wp.y - sort_y) < 0.75:
					c = Color(0.9, 0.15, 0.15)
				var on_edge: bool = absf(wp.x - cells.position.x) < 1.0 or absf(wp.x - cells.end.x) < 1.0 \
					or absf(wp.y - cells.position.y) < 1.0 or absf(wp.y - cells.end.y) < 1.0
				if on_edge and cells.grow(1.0).has_point(wp) and (x + y) / 6 % 2 == 0:
					c = Color.WHITE
				outi.set_pixel(x, y, c)
		outi.save_png(dir.path_join(id + ".png"))
		sources[id] = {"source": inst["shape_source"], "bloque_vue": inst["blocks_view"]}
		sources[id].merge(inst["shape_info"])
	var f: FileAccess = FileAccess.open(dir.path_join("_sources.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(sources, " "))
	f.close()
	print("[bk] masques du décor : %d images dans %s" % [done.size(), dir])
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
				# Ouverture, écrasement et tremblement décidés par la partie (bk_game.cachette_look),
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
	var p: String = rel if rel.begins_with("res://") else _dir.path_join(rel)
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
