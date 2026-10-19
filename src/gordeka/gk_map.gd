class_name GkMap
extends Node2D
## Carte du prototype gris (SPEC-GORDEKA §8) lue depuis assets/maps/<id>/map.txt :
## une lettre par case (légende dans tools/gordeka/make_proto_map.py). Construit les
## collisions (couche 1 : on ne passe pas ; couche 2 : on ne voit pas à travers), les
## occulteurs de lumière (vue du chasseur), la grille A* des IA et le dessin en blocs.

const LAYER_MOVE: int = 1
const LAYER_SIGHT: int = 2
## Pleins qui cachent la vue / objets bas et eau qui bloquent seulement le passage.
const OCCLUDE: String = "#cBH"
const LOW: String = "t~"
const WALK: String = ".ES"

const COLORS: Dictionary = {
	"#": Color("3b4253"), "c": Color("a0703e"), "B": Color("e8eef2"), "H": Color("e08a2e"),
	"t": Color("c9a873"), "~": Color("2f7fb8"),
}
const FLOOR_TINTS: Array[Color] = [Color("d9d2c3"), Color("cfc8b6"), Color("d4cdbf")]

var map_id: String = ""
var tiles: Array[String] = []
var width: int = 0
var height: int = 0
var tile: float = 64.0
var astar: AStarGrid2D
var zones: Array = []               # [{name, rect: Rect2i}]
var cachettes: Array[Vector2i] = []
var exits: Array[Vector2i] = []
var spawns: Array[Vector2i] = []
## Abri de chaque case de sol : nombre de voisins (8) qui cachent la vue.
var cover: Dictionary = {}


func load_map(id: String) -> void:
	map_id = id
	tile = GkRules.f("tile_px")
	var text: String = FileAccess.get_file_as_string("res://assets/maps/%s/map.txt" % id)
	tiles.clear()
	for line: String in text.split("\n"):
		if line.strip_edges() != "":
			tiles.append(line)
	height = tiles.size()
	width = tiles[0].length()
	var zj: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/%s/zones.json" % id))
	zones.clear()
	for z: Variant in (zj as Dictionary).get("zones", []):
		var r: Array = (z as Dictionary)["rect"]
		zones.append({"name": str(z["name"]), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))})
	for y: int in height:
		for x: int in width:
			match at(Vector2i(x, y)):
				"H": cachettes.append(Vector2i(x, y))
				"E": exits.append(Vector2i(x, y))
				"S": spawns.append(Vector2i(x, y))
	_build_bodies()
	_build_astar()
	_build_cover()
	_build_chunks()
	queue_redraw()


func at(t: Vector2i) -> String:
	if t.x < 0 or t.y < 0 or t.x >= width or t.y >= height:
		return "#"
	return tiles[t.y][t.x]


func walkable(t: Vector2i) -> bool:
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


## Rectangles fusionnés (en cases) des cases dont la lettre est dans `chars`.
func merged_rects(chars: String) -> Array[Rect2i]:
	var used: Dictionary = {}
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
	for r: Rect2i in merged_rects(OCCLUDE):
		var px: Rect2 = Rect2(Vector2(r.position) * tile, Vector2(r.size) * tile)
		_add_shape(solid, px)
		var occ: LightOccluder2D = LightOccluder2D.new()
		var poly: OccluderPolygon2D = OccluderPolygon2D.new()
		poly.polygon = PackedVector2Array([px.position, Vector2(px.end.x, px.position.y), px.end,
			Vector2(px.position.x, px.end.y)])
		occ.occluder = poly
		add_child(occ)
	for r: Rect2i in merged_rects(LOW):
		_add_shape(low, Rect2(Vector2(r.position) * tile, Vector2(r.size) * tile))


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
					if OCCLUDE.contains(at(t + Vector2i(dx, dy))):
						n += 1
			cover[t] = n


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


func _floor_of(name: String) -> Array:
	for k: String in FLOORS:
		if name.begins_with(k):
			return FLOORS[k]
	return ["d0c9b8", "dalles"]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size_px()), Color("b9b2a3"))


## Découpe du dessin en morceaux (une zone chacun, plus les murs entre zones) : Godot ne
## dessine que les morceaux visibles à l'écran.
func _build_chunks() -> void:
	var groups: Dictionary = {}
	for ch: String in "#cBt":
		for r: Rect2i in merged_rects(ch):
			var z: int = zone_of(r.position + r.size / 2)
			if not groups.has(z):
				groups[z] = []
			(groups[z] as Array).append([ch, r])
	for z: int in range(-1, zones.size()):
		var c: GkMapChunk = GkMapChunk.new()
		c.map = self
		c.zone = z
		c.items = groups.get(z, [])
		add_child(c)


func draw_chunk(ci: CanvasItem, zi: int, items: Array) -> void:
	var t: float = tile
	if zi >= 0:
		var z: Dictionary = zones[zi]
		var r: Rect2i = z["rect"]
		var f: Array = _floor_of(str(z["name"]))
		var px: Rect2 = Rect2(Vector2(r.position) * t, Vector2(r.size) * t)
		var base: Color = Color(str(f[0]))
		ci.draw_rect(px, base)
		var line: Color = base.darkened(0.12)
		match str(f[1]):
			"dalles":
				for y: int in range(r.position.y, r.end.y):
					for x: int in range(r.position.x, r.end.x):
						var o: float = 0.5 * t if y % 2 == 0 else 0.0
						ci.draw_rect(Rect2(Vector2(x, y) * t + Vector2(o, 0), Vector2(t, t)).intersection(px), line, false, 2.0)
			"paves":
				for y: int in range(r.position.y * 2, r.end.y * 2):
					for x: int in range(r.position.x * 2, r.end.x * 2):
						var c: Vector2 = (Vector2(x, y) + Vector2(0.5 + 0.25 * (y % 2), 0.5)) * t * 0.5
						if px.has_point(c):
							ci.draw_circle(c, t * 0.2, base.lightened(0.04 * float((x * 7 + y * 3) % 3)))
			"carrelage":
				for y: int in range(r.position.y, r.end.y):
					for x: int in range(r.position.x, r.end.x):
						if (x + y) % 2 == 0:
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
	for ch: String in "tcB#":
		for it: Array in items:
			if str(it[0]) != ch:
				continue
			var rr: Rect2i = it[1]
			var p3: Rect2 = Rect2(Vector2(rr.position) * t, Vector2(rr.size) * t)
			match ch:
				"t": _low(ci, p3)
				"c": _crate(ci, p3)
				"B": _boat(ci, p3, rr.position.x * 3 + rr.position.y)
				"#": _wall(ci, p3)


## Bloc avec un dessus clair et une face avant plus sombre (vue 3/4), contour épais.
func _block(ci: CanvasItem, px: Rect2, top: Color, front: Color, radius: float = 6.0) -> Rect2:
	var d: float = minf(tile * DEPTH, px.size.y * 0.45)
	GkDraw.rbox(ci, px, front, radius, 3.0)
	var top_r: Rect2 = Rect2(px.position, Vector2(px.size.x, px.size.y - d))
	GkDraw.rbox(ci, top_r, top, radius, 3.0)
	return top_r


func _wall(ci: CanvasItem, px: Rect2) -> void:
	var top: Rect2 = _block(ci, px, Color("aeb3bf"), Color("6e7383"), 4.0)
	# Joints de pierre sur la face avant.
	var y0: float = top.end.y
	for x: float in range(int(px.position.x) + 24, int(px.end.x) - 8, 48):
		ci.draw_line(Vector2(x, y0 + 4), Vector2(x, px.end.y - 4), Color(0, 0, 0, 0.18), 2.0)


func _crate(ci: CanvasItem, px: Rect2) -> void:
	var top: Rect2 = _block(ci, px, Color("dca865"), Color("a8743a"), 5.0)
	for x: float in range(int(top.position.x) + 16, int(top.end.x) - 8, 16):
		ci.draw_line(Vector2(x, top.position.y + 5), Vector2(x, top.end.y - 5), Color(0, 0, 0, 0.15), 2.0)


func _low(ci: CanvasItem, px: Rect2) -> void:
	# Objet bas (étal, table, filet) : petit plateau sur pieds, on voit par-dessus.
	var top: Rect2 = Rect2(px.position + Vector2(4, 2), px.size - Vector2(8, 14))
	for x: float in [px.position.x + 10, px.end.x - 14]:
		GkDraw.rbox(ci, Rect2(x, top.end.y - 4, 6, 14), Color("8a6239"), 2.0, 2.0)
	GkDraw.rbox(ci, top, Color("e2c28c"), 6.0, 3.0)
	GkDraw.rbox(ci, Rect2(top.position + Vector2(6, 5), Vector2(top.size.x - 12, 5)), Color(1, 1, 1, 0.35), 2.0, 0.0)


func _boat(ci: CanvasItem, px: Rect2, seed: int) -> void:
	var stripes: Array[Color] = [Color("2f6fe0"), Color("d83a34"), Color("2fb24a"), Color("f2c12e")]
	var hull: Rect2 = px.grow(-4)
	var top: Rect2 = _block(ci, hull, Color("f4f6f8"), Color("c9d2da"), minf(hull.size.y * 0.45, 26.0))
	var inner: Rect2 = top.grow(-maxf(8.0, top.size.y * 0.18))
	GkDraw.rbox(ci, inner, Color("c08a55"), minf(inner.size.y * 0.45, 18.0), 2.5)
	ci.draw_rect(Rect2(hull.position.x + 6, top.end.y + 3, hull.size.x - 12, 5), stripes[seed % stripes.size()])
