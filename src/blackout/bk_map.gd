class_name BkMap
extends Node2D
## Carte du prototype gris (SPEC-GORDEKA §8) lue depuis assets/maps/<id>/map.txt :
## une lettre par case (légende dans tools/blackout/make_proto_map.py). Construit les
## collisions (couche 1 : on ne passe pas ; couche 2 : on ne voit pas à travers), les
## occulteurs de lumière (vue du chasseur), la grille A* des IA et le dessin en blocs.

const LAYER_MOVE: int = 1
const LAYER_SIGHT: int = 2
## Pleins qui cachent la vue / objets bas et eau qui bloquent seulement le passage.
## Lieux réels (tools/blackout/carte_reelle.py) : R grand rocher, v végétation (cachent la vue),
## r rochers bas (bloquent le passage) ; sol de sable « : » et de jetée « = ».
const OCCLUDE: String = "#cBHRv"
const LOW: String = "t~r"
const WALK: String = ".ES:="

const COLORS: Dictionary = {
	"#": Color("3b4253"), "c": Color("a0703e"), "B": Color("e8eef2"), "H": Color("e08a2e"),
	"t": Color("c9a873"), "~": Color("2f7fb8"), "R": Color("8c6446"), "r": Color("9a7a5c"), "v": Color("5f8a4a"),
}
## Sols particuliers, case par case (le reste prend le sol de sa zone).
const TILE_FLOORS: Dictionary = {":": Color("e6cf98"), "=": Color("b8b2a6")}
const FLOOR_TINTS: Array[Color] = [Color("d9d2c3"), Color("cfc8b6"), Color("d4cdbf")]

var map_id: String = ""
## Décor en images de la carte (index.json → carte) : une variante de carte (zones.json → « decor »)
## reprend celui de la carte dont elle dérive.
var decor_id: String = ""
## Réglages propres à la carte (zones.json → « regles »), posés par BkGame (BkRules.surcharge_carte).
var regles: Dictionary = {}
var tiles: Array[String] = []
var width: int = 0
var height: int = 0
var tile: float = 64.0
var astar: AStarGrid2D
var zones: Array = []               # [{name, rect: Rect2i}]
var cachettes: Array[Vector2i] = []
var exits: Array[Vector2i] = []
## Sorties possibles, groupées (zones.json → exits) : {zone, tiles: Array[Vector2i]} ; le jeu en
## tire quelques-unes à chaque round.
var exit_groups: Array = []
var spawns: Array[Vector2i] = []
## Contenu de zones.json (zones, sorties, « objets » posés par BkDecor…).
var info: Dictionary = {}
## Cases sombres (grottes, tunnels) : zones.json → zones[].sombre et « sombres » [[x, y, w, h]…] ;
## la vue du chasseur y porte moins loin si `idee_grottes` est active (BkGame.sight_range).
var dark: Dictionary = {}
## Abri de chaque case de sol : nombre de voisins (8) qui cachent la vue.
var cover: Dictionary = {}
## Cases dont la grille A* suit l'emprise réelle d'un objet en image plutôt que sa lettre (vrai :
## marchable, case de l'objet que l'emprise ne couvre pas ; faux : bloquée, case de sol couverte par
## l'emprise d'un objet qui déborde de ses cases). Voir `_fit_grid_to_decor`.
var _walk_fix: Dictionary = {}
## Dessin à plat (prototype gris) ; faux en 3D, où BkView3D dessine la carte.
var draw_2d: bool = true
## Décor en images (assets/blackout/decor/, au fil des livraisons de pixelforge) ; tout ce qui n'a
## pas d'image garde le dessin procédural ci-dessous.
var decor: BkDecor
## Contours des formes du décor (QA), cachés sauf `--bk-qa-formes` ou la touche F de la visite.
var formes: Node2D


func load_map(id: String) -> void:
	map_id = id
	tile = BkRules.f("tile_px")
	var text: String = FileAccess.get_file_as_string("res://assets/maps/%s/map.txt" % id)
	tiles.clear()
	for line: String in text.split("\n"):
		if line.strip_edges() != "":
			tiles.append(line)
	height = tiles.size()
	width = tiles[0].length()
	var zj: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/%s/zones.json" % id))
	decor_id = str((zj as Dictionary).get("decor", id))
	regles = (zj as Dictionary).get("regles", {})
	zones.clear()
	for z: Variant in (zj as Dictionary).get("zones", []):
		var r: Array = (z as Dictionary)["rect"]
		zones.append({"name": str(z["name"]), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))})
	info = zj as Dictionary
	dark.clear()
	var dark_rects: Array = (info.get("sombres", []) as Array).duplicate()
	for z: Variant in info.get("zones", []):
		if bool((z as Dictionary).get("sombre", false)):
			dark_rects.append((z as Dictionary)["rect"])
	for r: Variant in dark_rects:
		for y: int in range(int(r[1]), int(r[1]) + int(r[3])):
			for x: int in range(int(r[0]), int(r[0]) + int(r[2])):
				dark[Vector2i(x, y)] = true
	for y: int in height:
		for x: int in width:
			match at(Vector2i(x, y)):
				"H": cachettes.append(Vector2i(x, y))
				"E": exits.append(Vector2i(x, y))
				"S": spawns.append(Vector2i(x, y))
	exit_groups.clear()
	for e: Variant in (zj as Dictionary).get("exits", []):
		var ts: Array[Vector2i] = []
		for t: Variant in (e as Dictionary)["tiles"]:
			ts.append(Vector2i(int(t[0]), int(t[1])))
		exit_groups.append({"zone": str(e["zone"]), "tiles": ts})
	if exit_groups.is_empty() and not exits.is_empty():
		exit_groups.append({"zone": "", "tiles": exits.duplicate()})
	if draw_2d:
		decor = BkDecor.new()
		decor.setup(self)
	_build_bodies()
	_fit_grid_to_decor()
	_build_astar()
	_build_cover()
	if draw_2d:
		_build_chunks()
		decor.attach()
	_qa_camera()
	queue_redraw()


func at(t: Vector2i) -> String:
	if t.x < 0 or t.y < 0 or t.x >= width or t.y >= height:
		return "#"
	return tiles[t.y][t.x]


func walkable(t: Vector2i) -> bool:
	if _walk_fix.has(t):
		return bool(_walk_fix[t])
	return WALK.contains(at(t))


func to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / tile), floori(p.y / tile))


func center(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * tile


func size_px() -> Vector2:
	return Vector2(width, height) * tile


func zone_of(t: Vector2i) -> int:
	for i: int in zones.size():
		if (zones[i]["rect"] as Rect2i).has_point(t):
			return i
	return -1


## Rectangles fusionnés (en cases) des cases dont la lettre est dans `chars`, hors cases de `skip`.
func merged_rects(chars: String, skip: Dictionary = {}) -> Array[Rect2i]:
	var used: Dictionary = skip.duplicate()
	var out: Array[Rect2i] = []
	for y: int in height:
		for x: int in width:
			var ch: String = at(Vector2i(x, y))
			if not chars.contains(ch) or used.has(Vector2i(x, y)):
				continue
			var w: int = 1
			while x + w < width and at(Vector2i(x + w, y)) == ch and not used.has(Vector2i(x + w, y)):
				w += 1
			var h: int = 1
			while y + h < height:
				var ok: bool = true
				for xx: int in range(x, x + w):
					if at(Vector2i(xx, y + h)) != ch or used.has(Vector2i(xx, y + h)):
						ok = false
						break
				if not ok:
					break
				h += 1
			for yy: int in range(y, y + h):
				for xx: int in range(x, x + w):
					used[Vector2i(xx, yy)] = true
			out.append(Rect2i(x, y, w, h))
	return out


func _build_bodies() -> void:
	var solid: StaticBody2D = StaticBody2D.new()
	solid.collision_layer = LAYER_MOVE | LAYER_SIGHT
	solid.collision_mask = 0
	add_child(solid)
	var low: StaticBody2D = StaticBody2D.new()
	low.collision_layer = LAYER_MOVE
	low.collision_mask = 0
	add_child(low)
	# Cases d'un objet en image : son empreinte au sol (forme réelle) remplace le rectangle des cases.
	var shaped: Dictionary = decor.shaped if decor else {}
	for r: Rect2i in merged_rects(OCCLUDE, shaped):
		var px: Rect2 = Rect2(Vector2(r.position) * tile, Vector2(r.size) * tile)
		_add_shape(solid, px)
		_add_occluder(PackedVector2Array([px.position, Vector2(px.end.x, px.position.y), px.end,
			Vector2(px.position.x, px.end.y)]), 1)
	for r: Rect2i in merged_rects(LOW, shaped):
		_add_shape(low, Rect2(Vector2(r.position) * tile, Vector2(r.size) * tile))
	if decor == null:
		return
	# QA : `--bk-qa-formes` (ou la touche F de la visite) montre les formes (vert : bloque la vue ;
	# jaune : le passage seul).
	var qa: Node2D = Node2D.new()
	qa.z_index = 100
	qa.visible = OS.get_cmdline_user_args().has("--bk-qa-formes")
	add_child(qa)
	formes = qa
	# Objets qui cachent la vue mais plus bas que l'œil du chasseur (#607) : hors de la couche de vue et
	# sans ombre de la lampe ; BkGame.sight_fraction teste leur hauteur point du corps par point.
	var eye: float = BkGame.eye_height()
	decor.low_view.clear()
	for i: int in decor.instances.size():
		var inst: Dictionary = decor.instances[i]
		if not inst.has("polys"):
			continue
		var blocks: bool = bool(inst["blocks_view"])
		if blocks and float(inst.get("view_h", INF)) < eye:
			blocks = false
			decor.low_view.append(i)
		for poly: PackedVector2Array in inst["polys"]:
			var cp: CollisionPolygon2D = CollisionPolygon2D.new()
			cp.polygon = poly
			(solid if blocks else low).add_child(cp)
			if blocks:
				_add_occluder(poly, BkDecor.LIGHT_MASK)
			if qa:
				var line: Line2D = Line2D.new()
				line.points = poly
				line.closed = true
				line.width = 3.0
				line.default_color = Color("2fe05a") if blocks else Color("f2c12e")
				qa.add_child(line)


## Occulteur de la vue du chasseur (ombre des lumières) ; `mask` 1 : murs de la grille (ombrent
## aussi les objets du décor), BkDecor.LIGHT_MASK : base d'un objet (n'ombre que le sol et les persos).
func _add_occluder(poly: PackedVector2Array, mask: int) -> void:
	var occ: LightOccluder2D = LightOccluder2D.new()
	var op: OccluderPolygon2D = OccluderPolygon2D.new()
	op.polygon = poly
	occ.occluder = op
	occ.occluder_light_mask = mask
	add_child(occ)


func _add_shape(body: StaticBody2D, px: Rect2) -> void:
	var cs: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = px.size
	cs.shape = shape
	cs.position = px.get_center()
	body.add_child(cs)


func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(tile, tile)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y: int in height:
		for x: int in width:
			if not walkable(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y), true)


func _build_cover() -> void:
	for y: int in height:
		for x: int in width:
			var t: Vector2i = Vector2i(x, y)
			if not walkable(t):
				continue
			var n: int = 0
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var nb: Vector2i = t + Vector2i(dx, dy)
					if OCCLUDE.contains(at(nb)) and not bool(_walk_fix.get(nb, false)):
						n += 1
			cover[t] = n


## Grille des IA alignée sur la physique (carte #606) : les objets en image ne bloquent que par leur
## emprise au sol (`BkDecor` → polys), pas par leurs cases. Une case est bloquée si l'emprise entre dans
## la case rétrécie de decor_grille_marge cases sur chaque bord (un perso au centre ou qui la traverse
## la toucherait), libre sinon : les cases vides d'un objet plus étroit que ses cases deviennent
## marchables, les cases de sol couvertes par un objet qui déborde (débord latéral) bloquées. Les
## cachettes gardent leur case (on y entre par l'action). Une case libérée que rien ne relie au reste
## du sol (îlot entre l'eau et l'objet) reste bloquée.
func _fit_grid_to_decor() -> void:
	_walk_fix.clear()
	if decor == null:
		return
	var m: float = clampf(BkRules.f("decor_grille_marge"), 0.0, 0.45) * tile
	var freed: Array[Vector2i] = []
	var over: Dictionary = {}
	for inst: Dictionary in decor.instances:
		if not inst.has("polys"):
			continue
		var polys: Array = inst["polys"]
		var bb: Rect2 = Rect2(polys[0][0], Vector2.ZERO)
		for poly: PackedVector2Array in polys:
			for p: Vector2 in poly:
				bb = bb.expand(p)
		var own: Array = inst["cells"]
		var area: Rect2i = (inst["rect"] as Rect2i).merge(Rect2i(to_tile(bb.position), Vector2i.ONE)) \
			.merge(Rect2i(to_tile(bb.end), Vector2i.ONE))
		for y: int in range(area.position.y, area.end.y):
			for x: int in range(area.position.x, area.end.x):
				var c: Vector2i = Vector2i(x, y)
				var inner: Rect2 = Rect2(Vector2(c) * tile, Vector2(tile, tile)).grow(-m)
				var box: PackedVector2Array = PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y),
					inner.end, Vector2(inner.position.x, inner.end.y)])
				var hit: bool = false
				for poly: PackedVector2Array in polys:
					if not Geometry2D.intersect_polygons(poly, box).is_empty():
						hit = true
						break
				if own.has(c):
					if not hit and at(c) != "H" and not _walk_fix.has(c):
						_walk_fix[c] = true
						freed.append(c)
				elif hit:
					over[c] = true
	# Débords (après coup : une case libérée d'un objet peut être couverte par le débord d'un voisin).
	for c: Vector2i in over:
		if WALK.contains(at(c)) or bool(_walk_fix.get(c, false)):
			_walk_fix[c] = false
	# Cases libérées reliées au sol de la carte (départs des joueurs), sinon rendues à l'objet.
	var seen: Dictionary = {}
	var todo: Array[Vector2i] = []
	for s: Vector2i in spawns:
		if walkable(s):
			seen[s] = true
			todo.append(s)
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if not seen.has(nb) and nb.x >= 0 and nb.y >= 0 and nb.x < width and nb.y < height and walkable(nb):
				seen[nb] = true
				todo.append(nb)
	for c: Vector2i in freed:
		if not seen.has(c) and bool(_walk_fix.get(c, false)):
			_walk_fix.erase(c)
	# QA (formes) : cases libérées en bleu, cases de sol bloquées par un débord en rouge.
	if formes:
		for c: Vector2i in _walk_fix:
			var line: Line2D = Line2D.new()
			var r: Rect2 = Rect2(Vector2(c) * tile, Vector2(tile, tile)).grow(-6.0)
			line.points = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
			line.closed = true
			line.width = 2.0
			line.default_color = Color("3aa0ff") if bool(_walk_fix[c]) else Color("ff4040")
			formes.add_child(line)


## Chemin (centres de cases) de a vers b, en pixels.
func path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ta: Vector2i = to_tile(a)
	var tb: Vector2i = to_tile(b)
	if not walkable(ta) or not walkable(tb):
		return PackedVector2Array()
	var pts: PackedVector2Array = astar.get_point_path(ta, tb)
	for i: int in pts.size():
		pts[i] += Vector2(tile, tile) * 0.5
	return pts


## Sol de chaque zone selon son nom : (couleur, motif).
const FLOORS: Dictionary = {
	"Jetée": ["cfc6b4", "dalles"], "Bassin": ["cfc6b4", "dalles"], "Quai": ["d3cab7", "dalles"],
	"Rampe": ["bdb8ad", "beton"], "Criée": ["d6d2c8", "carrelage"], "Hangar": ["c3beb3", "beton"],
	"Atelier": ["c3beb3", "beton"], "Crampottes": ["cdb99e", "paves"], "Rue": ["cdb99e", "paves"],
	"Place": ["dccdb0", "paves"], "Parking": ["6f747d", "parking"], "Cale": ["bdb8ad", "beton"],
	"Terrasse": ["c99662", "planches"],
}
const DEPTH: float = 0.42                # hauteur de la face avant des objets (en cases)


## QA : `--bk-cam=<zone>[@zoom]` (début du nom, sans casse ni accents ; zoom par défaut : la zone
## tient à l'écran) ou `--bk-cam=x,y[@zoom]` (case) : caméra fixe, pour les captures du décor.
func _qa_camera() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--bk-cam="):
			continue
		var spec: PackedStringArray = arg.trim_prefix("--bk-cam=").split("@")
		var target: Rect2i = Rect2i()
		var xy: PackedStringArray = spec[0].split(",")
		if xy.size() == 2 and xy[0].is_valid_int():
			target = Rect2i(int(xy[0]) - 8, int(xy[1]) - 4, 16, 9)
		else:
			for z: Dictionary in zones:
				if _plain(str(z["name"])).begins_with(_plain(spec[0])):
					target = z["rect"]
					break
		if target.size == Vector2i.ZERO:
			push_warning("--bk-cam : zone inconnue « %s »" % spec[0])
			return
		var px: Rect2 = Rect2(Vector2(target.position) * tile, Vector2(target.size) * tile)
		var vp: Vector2 = get_viewport_rect().size
		var cam: Camera2D = Camera2D.new()
		cam.position = px.get_center()
		var zoom: float = float(spec[1]) if spec.size() > 1 else minf(1.25, minf(vp.x / px.size.x, vp.y / px.size.y))
		cam.zoom = Vector2(zoom, zoom)
		cam.limit_right = int(size_px().x)
		cam.limit_bottom = int(size_px().y)
		cam.limit_left = 0
		cam.limit_top = 0
		add_child(cam)
		cam.make_current.call_deferred()
		return


static func _plain(s: String) -> String:
	var out: String = s.to_lower().replace("_", " ")
	for pair: String in ["ée", "èe", "êe", "àa", "âa", "çc", "ôo", "ûu", "ùu", "îi"]:
		out = out.replace(pair[0], pair[1])
	return out


func _floor_of(name: String) -> Array:
	for k: String in FLOORS:
		if name.begins_with(k):
			return FLOORS[k]
	return ["d0c9b8", "dalles"]


func _draw() -> void:
	if draw_2d:
		draw_rect(Rect2(Vector2.ZERO, size_px()), Color("b9b2a3"))


## Découpe du dessin en morceaux (une zone chacun, plus les murs entre zones) : Godot ne
## dessine que les morceaux visibles à l'écran.
func _build_chunks() -> void:
	var groups: Dictionary = {}
	# Les cases couvertes par une image du décor ne sont plus dessinées ici.
	for ch: String in "#cBtRrv":
		for r: Rect2i in merged_rects(ch, decor.covered if decor else {}):
			var z: int = zone_of(r.position + r.size / 2)
			if not groups.has(z):
				groups[z] = []
			(groups[z] as Array).append([ch, r])
	for z: int in range(-1, zones.size()):
		var c: BkMapChunk = BkMapChunk.new()
		c.map = self
		c.zone = z
		c.items = groups.get(z, [])
		add_child(c)


func draw_chunk(ci: CanvasItem, zi: int, items: Array) -> void:
	var t: float = tile
	if zi < 0 and decor:
		decor.draw_floors(ci, -1)
	if zi >= 0:
		var z: Dictionary = zones[zi]
		var r: Rect2i = z["rect"]
		var f: Array = _floor_of(str(z["name"]))
		var px: Rect2 = Rect2(Vector2(r.position) * t, Vector2(r.size) * t)
		var base: Color = Color(str(f[0]))
		# Sol case par case (par plages d'une ligne) : pas de sol peint sur l'eau ni sous les rochers.
		for y: int in range(r.position.y, r.end.y):
			var x: int = r.position.x
			while x < r.end.x:
				var ch: String = at(Vector2i(x, y))
				var dry: bool = WALK.contains(ch) or "cBHt#".contains(ch) \
						or decor != null and decor.covered.has(Vector2i(x, y))
				if not dry or decor and decor.water_under.has(Vector2i(x, y)):
					x += 1
					continue
				var x2: int = x
				while x2 < r.end.x and at(Vector2i(x2, y)) == ch:
					x2 += 1
				ci.draw_rect(Rect2(Vector2(x, y) * t, Vector2(x2 - x, 1) * t), TILE_FLOORS.get(ch, base))
				x = x2
		var line: Color = base.darkened(0.12)
		# Sol en image si le décor en a un pour cette zone, sinon motif procédural.
		var pattern: String = str(f[1])
		if decor:
			decor.draw_floors(ci, zi)
			if decor.has_floor(".", zi):
				pattern = ""
		match pattern:
			"dalles":
				for y: int in range(r.position.y, r.end.y):
					for x: int in range(r.position.x, r.end.x):
						if at(Vector2i(x, y)) != ".":
							continue
						var o: float = 0.5 * t if y % 2 == 0 else 0.0
						ci.draw_rect(Rect2(Vector2(x, y) * t + Vector2(o, 0), Vector2(t, t)).intersection(px), line, false, 2.0)
			"paves":
				for y: int in range(r.position.y * 2, r.end.y * 2):
					for x: int in range(r.position.x * 2, r.end.x * 2):
						var c: Vector2 = (Vector2(x, y) + Vector2(0.5 + 0.25 * (y % 2), 0.5)) * t * 0.5
						if px.has_point(c) and at(Vector2i(int(c.x / t), int(c.y / t))) == ".":
							ci.draw_circle(c, t * 0.2, base.lightened(0.04 * float((x * 7 + y * 3) % 3)))
			"carrelage":
				for y: int in range(r.position.y, r.end.y):
					for x: int in range(r.position.x, r.end.x):
						if (x + y) % 2 == 0 and at(Vector2i(x, y)) == ".":
							ci.draw_rect(Rect2(Vector2(x, y) * t, Vector2(t, t)), base.darkened(0.05))
			"planches":
				for y: int in range(r.position.y * 4, r.end.y * 4):
					ci.draw_line(Vector2(px.position.x, y * t * 0.25), Vector2(px.end.x, y * t * 0.25), line, 2.0)
			"parking":
				for x: int in range(r.position.x, r.end.x, 4):
					ci.draw_line(Vector2(x * t + t * 0.5, px.position.y + t), Vector2(x * t + t * 0.5, px.end.y - t),
						Color(1, 1, 1, 0.55), 4.0)
			"beton":
				for y: int in range(r.position.y, r.end.y, 3):
					ci.draw_line(Vector2(px.position.x, y * t), Vector2(px.end.x, y * t), line, 2.0)
		ci.draw_string(ThemeDB.fallback_font, Vector2(r.position) * t + Vector2(16, 40), str(z["name"]).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0, 0, 0, 0.22))
	# Ombres portées, puis les objets (bas, caisses, bateaux, murs).
	for it: Array in items:
		var rr: Rect2i = it[1]
		var p2: Rect2 = Rect2(Vector2(rr.position) * t, Vector2(rr.size) * t)
		ci.draw_rect(Rect2(p2.position + Vector2(t * 0.18, t * 0.22), p2.size), Color(0, 0, 0, 0.16))
	for ch: String in "rtcBRv#":
		for it: Array in items:
			if str(it[0]) != ch:
				continue
			var rr: Rect2i = it[1]
			var p3: Rect2 = Rect2(Vector2(rr.position) * t, Vector2(rr.size) * t)
			match ch:
				"t": _low(ci, p3)
				"c": _crate(ci, p3)
				"B": _boat(ci, p3, rr.position.x * 3 + rr.position.y)
				"#":
					if zi < 0 and decor and decor.has_floor("#", -1):
						_roofs(ci, rr)
					else:
						_wall(ci, p3)
				"R": _block(ci, p3, Color("a07a58"), Color("6e5038"), 10.0)
				"r": BkDraw.rbox(ci, p3.grow(-2), Color("9a7a5c"), 8.0, 2.0)
				"v": _block(ci, p3, Color("6f9a55"), Color("4c7038"), 12.0)


## Bloc avec un dessus clair et une face avant plus sombre (vue 3/4), contour épais.
func _block(ci: CanvasItem, px: Rect2, top: Color, front: Color, radius: float = 6.0) -> Rect2:
	var d: float = minf(tile * DEPTH, px.size.y * 0.45)
	BkDraw.rbox(ci, px, front, radius, 3.0)
	var top_r: Rect2 = Rect2(px.position, Vector2(px.size.x, px.size.y - d))
	BkDraw.rbox(ci, top_r, top, radius, 3.0)
	return top_r


func _wall(ci: CanvasItem, px: Rect2) -> void:
	var top: Rect2 = _block(ci, px, Color("aeb3bf"), Color("6e7383"), 4.0)
	# Joints de pierre sur la face avant.
	var y0: float = top.end.y
	for x: float in range(int(px.position.x) + 24, int(px.end.x) - 8, 48):
		ci.draw_line(Vector2(x, y0 + 4), Vector2(x, px.end.y - 4), Color(0, 0, 0, 0.18), 2.0)


## Masses bâties entre les zones, vues du dessus : le toit de tuiles (image du décor, déjà posée par
## BkDecor.draw_floors) cerné d'encre, et sur chaque case dont le sud donne sur le sol, la façade
## blanche labourdine dessinée par le code (provisoire, en attendant facade_labourdine de pixelforge) :
## colombages rouges, fenêtres à volets rouges ou verts, parfois une porte ou des géraniums.
func _roofs(ci: CanvasItem, rr: Rect2i) -> void:
	var t: float = tile
	var ink: Color = BkDraw.INK
	for y: int in range(rr.position.y, rr.end.y):
		for x: int in range(rr.position.x, rr.end.x):
			var c: Vector2i = Vector2i(x, y)
			var o: Vector2 = Vector2(c) * t
			for d: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
				if at(c + d) != "#":
					var a: Vector2 = o + (Vector2(0, 0) if d.x <= 0 else Vector2(t, 0))
					var b: Vector2 = a + (Vector2(t, 0) if d.y != 0 else Vector2(0, t))
					ci.draw_line(a, b, ink, 3.0)
			var below: String = at(c + Vector2i(0, 1))
			if below == "#" or below == "~" or y + 1 >= height:
				continue
			var h: float = t * 0.8
			var f: Rect2 = Rect2(o + Vector2(0, t - h), Vector2(t, h))
			ci.draw_rect(f, Color("f4f1ea"))
			ci.draw_rect(Rect2(f.position, Vector2(t, 7)), Color("9e1b1b"))
			ci.draw_rect(Rect2(f.position + Vector2(0, 7), Vector2(t, 5)), Color(0, 0, 0, 0.12))
			var k: int = absi(x * 7 + y * 13) % 7
			if k == 0:
				# Porte rouge, linteau de grès.
				ci.draw_rect(Rect2(f.position + Vector2(t * 0.3, h * 0.32), Vector2(t * 0.4, h * 0.68)), Color("9e1b1b"))
				ci.draw_rect(Rect2(f.position + Vector2(t * 0.26, h * 0.26), Vector2(t * 0.48, 5)), Color("d9c39a"))
			elif k != 3:
				var shut: Color = Color("9e1b1b") if (x + y) % 3 != 0 else Color("2f6b45")
				var wr: Rect2 = Rect2(f.position + Vector2(t * 0.34, h * 0.34), Vector2(t * 0.32, h * 0.36))
				ci.draw_rect(wr, Color("33405a"))
				ci.draw_rect(Rect2(wr.position - Vector2(t * 0.14, 0), Vector2(t * 0.13, wr.size.y)), shut)
				ci.draw_rect(Rect2(wr.end - Vector2(0, wr.size.y), Vector2(t * 0.13, wr.size.y)), shut)
				if k == 5:
					for i: int in 3:
						ci.draw_circle(wr.position + Vector2(wr.size.x * (0.2 + 0.3 * i), wr.size.y + 4), 4.5, Color("e3526b"))
			ci.draw_line(f.position + Vector2(0, h), f.position + Vector2(t, h), ink, 3.0)
			if at(c + Vector2i(-1, 0)) != "#" or at(c + Vector2i(-1, 1)) != "#" and at(c + Vector2i(-1, 1)) != ".":
				ci.draw_line(f.position, f.position + Vector2(0, h), ink, 3.0)
			if at(c + Vector2i(1, 0)) != "#":
				ci.draw_line(f.position + Vector2(t, 0), f.position + Vector2(t, h), ink, 3.0)


func _crate(ci: CanvasItem, px: Rect2) -> void:
	var top: Rect2 = _block(ci, px, Color("dca865"), Color("a8743a"), 5.0)
	for x: float in range(int(top.position.x) + 16, int(top.end.x) - 8, 16):
		ci.draw_line(Vector2(x, top.position.y + 5), Vector2(x, top.end.y - 5), Color(0, 0, 0, 0.15), 2.0)


func _low(ci: CanvasItem, px: Rect2) -> void:
	# Objet bas (étal, table, filet) : petit plateau sur pieds, on voit par-dessus.
	var top: Rect2 = Rect2(px.position + Vector2(4, 2), px.size - Vector2(8, 14))
	for x: float in [px.position.x + 10, px.end.x - 14]:
		BkDraw.rbox(ci, Rect2(x, top.end.y - 4, 6, 14), Color("8a6239"), 2.0, 2.0)
	BkDraw.rbox(ci, top, Color("e2c28c"), 6.0, 3.0)
	BkDraw.rbox(ci, Rect2(top.position + Vector2(6, 5), Vector2(top.size.x - 12, 5)), Color(1, 1, 1, 0.35), 2.0, 0.0)


func _boat(ci: CanvasItem, px: Rect2, seed: int) -> void:
	var stripes: Array[Color] = [Color("2f6fe0"), Color("d83a34"), Color("2fb24a"), Color("f2c12e")]
	var hull: Rect2 = px.grow(-4)
	var top: Rect2 = _block(ci, hull, Color("f4f6f8"), Color("c9d2da"), minf(hull.size.y * 0.45, 26.0))
	var inner: Rect2 = top.grow(-maxf(8.0, top.size.y * 0.18))
	BkDraw.rbox(ci, inner, Color("c08a55"), minf(inner.size.y * 0.45, 18.0), 2.5)
	ci.draw_rect(Rect2(hull.position.x + 6, top.end.y + 3, hull.size.x - 12, 5), stripes[seed % stripes.size()])
