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


func _draw() -> void:
	# Sol teinté par zone, puis les blocs, puis un liseré sombre pour la lisibilité.
	draw_rect(Rect2(Vector2.ZERO, size_px()), Color("bfb8a8"))
	for i: int in zones.size():
		var r: Rect2i = zones[i]["rect"]
		draw_rect(Rect2(Vector2(r.position) * tile, Vector2(r.size) * tile), FLOOR_TINTS[i % FLOOR_TINTS.size()])
	for ch: String in "~t#cB":
		for r: Rect2i in merged_rects(ch):
			var px: Rect2 = Rect2(Vector2(r.position) * tile, Vector2(r.size) * tile)
			if ch == "B":
				draw_rect(px.grow(-6), COLORS[ch])
				draw_rect(px.grow(-6), Color("2a3442"), false, 4.0)
				draw_rect(px.grow(-px.size.y * 0.3), Color("9db8c9"))
			elif ch == "~":
				draw_rect(px, COLORS[ch])
			else:
				draw_rect(px.grow(-2 if ch != "#" else 0), COLORS[ch])
				if ch != "#":
					draw_rect(px.grow(-2), Color(0, 0, 0, 0.35), false, 3.0)
	# Vaguelettes sur l'eau.
	for r: Rect2i in merged_rects("~"):
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x, 2):
				var p: Vector2 = (Vector2(x, y) + Vector2(0.3, 0.5 + 0.15 * (x % 3))) * tile
				draw_line(p, p + Vector2(tile * 0.5, 0), Color(1, 1, 1, 0.25), 3.0)
	# Noms des zones, discrets.
	var font: Font = ThemeDB.fallback_font
	for z: Dictionary in zones:
		var r: Rect2i = z["rect"]
		draw_string(font, Vector2(r.position) * tile + Vector2(14, 34), str(z["name"]).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.28))
