class_name GkDecor
extends Node2D
## Décor en images (pixelforge, intégré élément par élément par tools/gordeka/integre_decor.py),
## posé sur la carte avec repli sur le dessin procédural de GkMap pour tout ce qui n'a pas encore
## d'image. La collision, l'occlusion de la vue et la grille A* restent celles de la grille.
##
## index.json (assets/gordeka/decor/) : {carte, elements: {id: {type, categorie, caractere, zones,
## taille_cases, debord_haut_cases, animation, fichiers: [chemins relatifs], ombre, ombre_decalage,
## ouvert}}}.
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
## Tremblement des cachettes, calqué sur la caisse orange du calque de jeu (gk_game).
const SHAKE_FREQ: float = 60.0
const SHAKE_PX: float = 4.0

var map: GkMap
var under: Node2D
var elements: Dictionary = {}
## Cases dont le dessin procédural est remplacé (objets en image, sols pleins sur un caractère
## non marchable comme l'eau ou les toits) : GkMap et GkWater ne les dessinent plus.
var covered: Dictionary = {}
## Cases d'un objet en image posé sur l'eau (barques du bassin) : GkWater y dessine l'eau, pas de sol.
var water_under: Dictionary = {}
## Instances posées : {id, cells: Array[Vector2i], rect: Rect2i, zone, holder, sprite, kind, base, phase}.
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


## Point d'accroche de l'état ouvert (cachette, sortie) : prend l'image `ouvert` de l'index si
## elle existe, sinon garde l'image fermée.
func set_open(t: Vector2i, open: bool) -> void:
	var i: int = _instance_at(t)
	if i < 0:
		return
	var inst: Dictionary = instances[i]
	var el: Dictionary = elements[inst["id"]]
	var rel: String = str(el.get("ouvert", "")) if open else str((el["fichiers"] as Array)[0])
	var tex: Texture2D = _texture(rel)
	if tex:
		(inst["sprite"] as Sprite2D).texture = tex


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
			if not _draw_cell(ci, t, "%s|%d" % [ch, zone]) and UNDER_FLOOR.contains(ch) and ch != ".":
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
	instances.append(inst)
	if kind != "":
		_animated.append(inst)


func _instance_at(t: Vector2i) -> int:
	for i: int in instances.size():
		if (instances[i]["cells"] as Array).has(t):
			return i
	return -1


# ---------------------------------------------------------------- animation « jeu »

func _process(dt: float) -> void:
	_t += dt
	var game: Node = map.get_parent()
	var caches: Variant = game.get("cachettes") if game else null
	for inst: Dictionary in _animated:
		var sp: Sprite2D = inst["sprite"]
		var base: Vector2 = inst["base"]
		var ph: float = inst["phase"]
		match str(inst["kind"]):
			"tangage":
				sp.rotation = deg_to_rad(SWAY_DEG) * sin(_t * SWAY_SPEED + ph)
				sp.position = base + Vector2(0, BOB_PX * sin(_t * BOB_SPEED + ph))
			"tremble":
				# Le jeu arme `shake` quand on entre, sort ou fouille (gk_game, cachettes[i]).
				var shake: float = 0.0
				var i: int = map.cachettes.find((inst["cells"] as Array)[0])
				if caches is Array and i >= 0 and i < (caches as Array).size():
					shake = float(((caches as Array)[i] as Dictionary).get("shake", 0.0))
				sp.position = base + Vector2(sin(shake * SHAKE_FREQ) * SHAKE_PX * signf(shake), 0)


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
