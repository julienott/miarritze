class_name BkMap
extends Node2D
## Carte lue depuis assets/maps/<id>/map.txt (GDD-BLACKOUT.md §10) : une lettre par case (légende
## ci-dessous et dans tools/blackout/make_bac_a_sable.py), et zones.json (zones, sorties, lampadaires,
## disjoncteurs, places des gâteaux et des mouettes). Construit les collisions (couche 1 : on ne passe
## pas ; couche 2 : on ne voit pas à travers), les occulteurs de lumière (vue du chasseur), la grille
## A* des IA et le dessin en placeholders pixel art (aplats et formes simples, cases de tile_px).

const LAYER_MOVE: int = 1
const LAYER_SIGHT: int = 2
## Légende des cases (GDD §3.1, §10.1, §10.2) :
##   sol : « . » sol de la zone, « E » sortie, « S » départ, « : » sol meuble (sable), « = » jetée ;
##   cachent la vue et bloquent le passage : « # » mur plein, « c » objet haut (caisses, armoire),
##     « B » barque, « H » cachette, « R » grand rocher, « v » végétation haute,
##     « | » et « - » cloisons fines (verticale, horizontale : une forme de cloison_epaisseur case) ;
##   bloquent le passage, pas la vue d'un perso debout : « t » objet bas (table, étal), « ~ » eau,
##     « r » rochers bas, « m » muret d'une case, « b » buisson, « g » grille, « f » fenêtre.
const OCCLUDE: String = "#cBHRv|-"
const LOW: String = "t~rmbgf"
const WALK: String = ".ES:="
## Cloisons fines (forme mince centrée dans la case, sens de la cloison).
const THIN_V: String = "|"
const THIN_H: String = "-"
## Sol meuble (Karramarro s'y enfouit, GDD §4.4).
const MEUBLE: String = ":"

const COLORS: Dictionary = {
	"#": Color("3b4253"), "c": Color("a0703e"), "B": Color("e8eef2"), "H": Color("e08a2e"),
	"t": Color("c9a873"), "~": Color("2f7fb8"), "R": Color("8c6446"), "r": Color("9a7a5c"), "v": Color("5f8a4a"),
}
## Sols particuliers, case par case (le reste prend le sol de sa zone).
const TILE_FLOORS: Dictionary = {":": Color("c9b27e"), "=": Color("8f8a80")}
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
## Emplacements des lampadaires {pos: Vector2i, rayon (cases), secteur} et des disjoncteurs
## {pos: Vector2i (case où l'on se tient), mur: Vector2i (côté du boîtier), secteur} (zones.json) :
## données et marqueurs seulement, la lumière vient à l'étape suivante (GDD §3.2).
var lampadaires: Array = []
var disjoncteurs: Array = []
## Secteurs de la carte {id, rect: Rect2i} (un disjoncteur par secteur).
var secteurs: Array = []
## Places des gâteaux basques et des mouettes (zones.json → « gateaux », « mouettes ») ; vides : tirage
## au hasard sur les cases dégagées.
var gateaux_places: Array[Vector2i] = []
var mouettes_places: Array[Vector2i] = []
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
		zones.append({"name": str(z["name"]), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])),
			"sol": str((z as Dictionary).get("sol", ""))})
	info = zj as Dictionary
	_read_points()
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


## Lampadaires, disjoncteurs, secteurs, places des gâteaux et des mouettes (zones.json).
func _read_points() -> void:
	lampadaires.clear()
	disjoncteurs.clear()
	secteurs.clear()
	gateaux_places.clear()
	mouettes_places.clear()
	for l: Variant in info.get("lampadaires", []):
		var ld: Dictionary = l
		lampadaires.append({"pos": _v2i(ld["pos"]), "rayon": float(ld.get("rayon", 3.0)),
			"secteur": str(ld.get("secteur", ""))})
	for d: Variant in info.get("disjoncteurs", []):
		var dd: Dictionary = d
		disjoncteurs.append({"pos": _v2i(dd["pos"]), "mur": _v2i(dd.get("mur", [0, -1])),
			"secteur": str(dd.get("secteur", ""))})
	for sct: Variant in info.get("secteurs", []):
		var r: Array = (sct as Dictionary)["rect"]
		secteurs.append({"id": str(sct["id"]), "rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))})
	for g: Variant in info.get("gateaux", []):
		gateaux_places.append(_v2i(g))
	for m: Variant in info.get("mouettes", []):
		mouettes_places.append(_v2i(m))


static func _v2i(a: Variant) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


## Vrai si la case est un sol meuble (sable).
func meuble(t: Vector2i) -> bool:
	return MEUBLE.contains(at(t))


## Règles des cases, sans le décor en image : bloque le passage / bloque la vue d'un perso debout.
func blocks_move(t: Vector2i) -> bool:
	return OCCLUDE.contains(at(t)) or LOW.contains(at(t))


func blocks_view(t: Vector2i) -> bool:
	return OCCLUDE.contains(at(t))


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
		var px: Rect2 = thin_rect(r)
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


## Rectangle (px) de la forme de cases fusionnées : la case entière, ou une bande mince centrée pour
## une cloison fine (cloison_epaisseur case ; « | » verticale, « - » horizontale).
func thin_rect(r: Rect2i) -> Rect2:
	var px: Rect2 = Rect2(Vector2(r.position) * tile, Vector2(r.size) * tile)
	var ch: String = at(r.position)
	var e: float = roundf(clampf(BkRules.f("cloison_epaisseur"), 0.05, 1.0) * tile)
	if ch == THIN_V:
		return Rect2(roundf(px.get_center().x - e * 0.5), px.position.y, e, px.size.y)
	if ch == THIN_H:
		return Rect2(px.position.x, roundf(px.get_center().y - e * 0.5), px.size.x, e)
	return px


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


## Sols des zones, en placeholders (GDD §9 : sols à motif par zone, peu contrastés, couleurs de nuit
## désaturées) : zones.json → zones[].sol, sinon selon le nom de la zone (anciennes cartes).
const FLOORS: Dictionary = {
	"Jetée": "5d6273", "Bassin": "5d6273", "Quai": "61667a", "Rampe": "575c6c", "Criée": "676c80",
	"Hangar": "565b6b", "Atelier": "565b6b", "Crampottes": "6a6070", "Rue": "6a6070", "Place": "6e6575",
	"Parking": "4a4e5a", "Cale": "575c6c", "Terrasse": "735f5a",
}
## Couleurs des placeholders de la carte (aplats, GDD §9 : nuit bleutée, objets lisibles).
const C_MUR_HAUT: Color = Color("262a3d")
const C_MUR_FACE: Color = Color("4b5372")
const C_MUR_JOINT: Color = Color("3e4562")
const C_CLOISON: Color = Color("8a7a66")
const C_HAUT: Color = Color("b07a45")
const C_HAUT_FACE: Color = Color("7a5230")
const C_BAS: Color = Color("c9a873")
const C_BAS_FACE: Color = Color("8a6a40")
const C_MURET: Color = Color("9a9488")
const C_MURET_FACE: Color = Color("6e695f")
const C_BUISSON: Color = Color("4f7d3c")
const C_BUISSON_CLAIR: Color = Color("6f9a55")
const C_GRILLE: Color = Color("b8c0cc")
const C_VITRE: Color = Color("7fb8d8")
const C_ROCHER: Color = Color("8c7a6a")
const C_BARQUE: Color = Color("d8dde3")
const C_LAMPE: Color = Color("ffd34a")
const C_DISJ: Color = Color("c9cfd8")
## Hauteur de la face avant des objets debout (en cases), vue « maison de poupée » (GDD §9).
const DEPTH: float = 0.35


func _floor_color(zi: int) -> Color:
	var z: Dictionary = zones[zi]
	if str(z.get("sol", "")) != "":
		return Color(str(z["sol"]))
	for k: String in FLOORS:
		if str(z["name"]).begins_with(k):
			return Color(str(FLOORS[k]))
	return Color("5f6474")


func _draw() -> void:
	if draw_2d:
		draw_rect(Rect2(Vector2.ZERO, size_px()), Color("4a4f60"))


## Découpe du dessin en morceaux (une zone chacun, plus les murs entre zones) : Godot ne
## dessine que les morceaux visibles à l'écran.
func _build_chunks() -> void:
	var groups: Dictionary = {}
	# Les cases couvertes par une image du décor ne sont plus dessinées ici.
	for ch: String in "#cBtRrvm|-gfb":
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
	# Marqueurs des lampadaires et des disjoncteurs, par-dessus le sol (données de l'étape suivante).
	var marks: BkMapChunk = BkMapChunk.new()
	marks.map = self
	marks.zone = -2
	add_child(marks)


func draw_chunk(ci: CanvasItem, zi: int, items: Array) -> void:
	if zi == -2:
		_draw_marks(ci)
		return
	var t: float = tile
	if zi < 0 and decor:
		decor.draw_floors(ci, -1)
	if zi >= 0:
		var z: Dictionary = zones[zi]
		var r: Rect2i = z["rect"]
		var base: Color = _floor_color(zi)
		# Sol case par case : un damier très doux (sol à motif peu contrasté), pas sous l'eau.
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var c: Vector2i = Vector2i(x, y)
				var ch: String = at(c)
				if ch == "~" or ch == "#" or decor and decor.water_under.has(c):
					continue
				var col: Color = TILE_FLOORS.get(ch, base)
				if (x + y) % 2 == 0:
					col = col.darkened(0.04)
				ci.draw_rect(Rect2(Vector2(c) * t, Vector2(t, t)), col)
				if ch == ":" and absi(x * 7 + y * 13) % 3 == 0:
					# Sable : quelques grains.
					ci.draw_rect(Rect2(Vector2(c) * t + Vector2(t * 0.3, t * 0.4).round(), Vector2(1, 1)), col.lightened(0.2))
					ci.draw_rect(Rect2(Vector2(c) * t + Vector2(t * 0.7, t * 0.75).round(), Vector2(1, 1)), col.darkened(0.15))
		if decor:
			decor.draw_floors(ci, zi)
		BkDraw.texte(ci, Vector2(r.position) * t + Vector2(r.size.x * t * 0.5, 12), str(z["name"]).to_upper(), 8,
			Color(1, 1, 1, 0.22), 0, r.size.x * t)
	# Objets : bas d'abord, puis hauts et murs (la face avant recouvre le sol de la case du dessous).
	for ch: String in "rtmbgfcBRv|-#":
		for it: Array in items:
			if str(it[0]) != ch:
				continue
			var rr: Rect2i = it[1]
			var p3: Rect2 = Rect2(Vector2(rr.position) * t, Vector2(rr.size) * t)
			match ch:
				"#": _wall(ci, rr)
				"c": _block(ci, p3.grow(-1), C_HAUT, C_HAUT_FACE, 0.5)
				"B": _block(ci, p3.grow(-2), C_BARQUE, Color("2f6fe0"), 0.4)
				"R": _block(ci, p3.grow(-1), C_ROCHER, C_ROCHER.darkened(0.3), 0.5)
				"v": _bush(ci, p3, Color("3f6a32"), Color("5b8a45"))
				"t": _block(ci, p3.grow(-3), C_BAS, C_BAS_FACE, 0.2)
				"m": _block(ci, p3, C_MURET, C_MURET_FACE, 0.25)
				"r": _block(ci, p3.grow(-3), C_ROCHER.lightened(0.1), C_ROCHER.darkened(0.2), 0.2)
				"b": _bush(ci, p3, C_BUISSON, C_BUISSON_CLAIR)
				"g": _grille(ci, rr)
				"f": _window(ci, rr)
				"|", "-": _cloison(ci, rr)


## Bloc vu « maison de poupée » : dessus clair, face avant plus sombre de `depth` cases, contour d'un
## pixel.
func _block(ci: CanvasItem, px: Rect2, top: Color, front: Color, depth: float) -> void:
	px = Rect2(px.position.round(), px.size.round())
	var d: float = roundf(minf(tile * depth, px.size.y * 0.5))
	ci.draw_rect(px, BkDraw.INK)
	ci.draw_rect(px.grow(-1), front)
	ci.draw_rect(Rect2(px.position + Vector2(1, 1), Vector2(px.size.x - 2, px.size.y - d - 1)), top)
	ci.draw_rect(Rect2(px.position + Vector2(1, 1), Vector2(px.size.x - 2, 1)), top.lightened(0.2))


## Mur plein : dessus sombre ; sa face (pierre) se montre côté sud quand le sol est dessous (mur du
## fond, GDD §9), les autres bords réduits à une arête sombre.
func _wall(ci: CanvasItem, rr: Rect2i) -> void:
	var t: float = tile
	var face_h: float = roundf(t * DEPTH * 1.6)
	for y: int in range(rr.position.y, rr.end.y):
		for x: int in range(rr.position.x, rr.end.x):
			var c: Vector2i = Vector2i(x, y)
			var o: Vector2 = Vector2(c) * t
			ci.draw_rect(Rect2(o, Vector2(t, t)), C_MUR_HAUT)
			var below: String = at(c + Vector2i(0, 1))
			if below != "#" and y + 1 < height:
				var f: Rect2 = Rect2(o + Vector2(0, t - face_h), Vector2(t, face_h))
				ci.draw_rect(f, C_MUR_FACE)
				ci.draw_rect(Rect2(f.position, Vector2(t, 1)), C_MUR_FACE.lightened(0.25))
				var off: float = 0.0 if y % 2 == 0 else t * 0.5
				for k: int in 2:
					ci.draw_rect(Rect2(o + Vector2(roundf(fmod(off + k * t * 0.5, t)), t - face_h + 2), Vector2(1, face_h - 3)), C_MUR_JOINT)
				ci.draw_rect(Rect2(o + Vector2(0, t - roundf(face_h * 0.5)), Vector2(t, 1)), C_MUR_JOINT)


## Cloison fine : bande mince (forme de collision) avec un dessus clair et une petite face.
func _cloison(ci: CanvasItem, rr: Rect2i) -> void:
	var px: Rect2 = thin_rect(rr)
	ci.draw_rect(px, BkDraw.INK)
	ci.draw_rect(px.grow(-1), C_CLOISON)
	if at(rr.position) == THIN_H:
		ci.draw_rect(Rect2(px.position + Vector2(1, px.size.y - 3), Vector2(px.size.x - 2, 2)), C_CLOISON.darkened(0.3))


## Buisson : touffes rondes (objet bas).
func _bush(ci: CanvasItem, px: Rect2, dark: Color, light: Color) -> void:
	var t: float = tile
	for y: int in range(int(px.size.y / t)):
		for x: int in range(int(px.size.x / t)):
			var c: Vector2 = px.position + Vector2(x + 0.5, y + 0.55) * t
			ci.draw_circle(c.round() + Vector2(0, 2), t * 0.45, BkDraw.INK)
			ci.draw_circle(c.round() + Vector2(0, 2), t * 0.42, dark)
			ci.draw_circle(c.round() + Vector2(-3, -2), t * 0.24, light)
			ci.draw_circle(c.round() + Vector2(4, -1), t * 0.2, light)


## Grille (vue oui, passage non) : barreaux sur le sol, une traverse en haut et en bas.
func _grille(ci: CanvasItem, rr: Rect2i) -> void:
	var px: Rect2 = Rect2(Vector2(rr.position) * tile, Vector2(rr.size) * tile)
	var vertical: bool = rr.size.y > rr.size.x
	if vertical:
		var x0: float = roundf(px.get_center().x)
		ci.draw_rect(Rect2(x0 - 2, px.position.y, 4, px.size.y), Color(BkDraw.INK, 0.5))
		for y: int in range(int(px.position.y) + 2, int(px.end.y), 5):
			ci.draw_rect(Rect2(x0 - 3, y, 6, 1), C_GRILLE)
		ci.draw_rect(Rect2(x0 - 1, px.position.y, 2, px.size.y), C_GRILLE.darkened(0.2))
	else:
		var top: float = px.position.y + roundf(tile * 0.3)
		ci.draw_rect(Rect2(px.position.x, top, px.size.x, 1), C_GRILLE)
		ci.draw_rect(Rect2(px.position.x, px.end.y - 3, px.size.x, 1), C_GRILLE.darkened(0.2))
		for x: int in range(int(px.position.x) + 2, int(px.end.x), 4):
			ci.draw_rect(Rect2(x, top, 1, px.end.y - 3 - top), C_GRILLE)


## Fenêtre dans un mur (vue oui, passage non) : le mur, percé d'une vitre claire.
func _window(ci: CanvasItem, rr: Rect2i) -> void:
	var t: float = tile
	for y: int in range(rr.position.y, rr.end.y):
		for x: int in range(rr.position.x, rr.end.x):
			var o: Vector2 = Vector2(x, y) * t
			ci.draw_rect(Rect2(o, Vector2(t, t)), C_MUR_HAUT)
			var g: Rect2 = Rect2(o, Vector2(t, t)).grow(-roundf(t * 0.22))
			ci.draw_rect(g, Color(C_VITRE, 0.75))
			ci.draw_rect(Rect2(g.position, Vector2(g.size.x, 1)), Color.WHITE)
			ci.draw_rect(Rect2(Vector2(roundf(g.get_center().x), g.position.y), Vector2(1, g.size.y)), C_MUR_HAUT)
			ci.draw_rect(Rect2(Vector2(g.position.x, roundf(g.get_center().y)), Vector2(g.size.x, 1)), C_MUR_HAUT)


## Marqueurs des lampadaires (poteau, lanterne, portée de la lumière en pointillés) et des
## disjoncteurs (boîtier gris avec un éclair, sur le mur indiqué).
func _draw_marks(ci: CanvasItem) -> void:
	var t: float = tile
	for l: Dictionary in lampadaires:
		var c: Vector2 = center(l["pos"]).round()
		var rad: float = float(l["rayon"]) * t
		for k: int in 32:
			var a: float = TAU * float(k) / 32.0
			ci.draw_rect(Rect2((c + Vector2.from_angle(a) * rad).round(), Vector2(1, 1)), Color(C_LAMPE, 0.35))
		ci.draw_rect(Rect2(c + Vector2(-3, 4), Vector2(6, 2)), BkDraw.INK)
		ci.draw_rect(Rect2(c + Vector2(-1, -18), Vector2(2, 22)), Color("3a3f52"))
		ci.draw_rect(Rect2(c + Vector2(-4, -24), Vector2(8, 7)), BkDraw.INK)
		ci.draw_rect(Rect2(c + Vector2(-3, -23), Vector2(6, 5)), C_LAMPE)
	for d: Dictionary in disjoncteurs:
		var c2: Vector2 = (center(d["pos"]) + Vector2(d["mur"]) * t * 0.5).round()
		var b: Rect2 = Rect2(c2 - Vector2(5, 7), Vector2(10, 12))
		ci.draw_rect(b, BkDraw.INK)
		ci.draw_rect(b.grow(-1), C_DISJ)
		ci.draw_colored_polygon(PackedVector2Array([c2 + Vector2(1, -5), c2 + Vector2(-2, 0), c2 + Vector2(0, 0),
			c2 + Vector2(-1, 4), c2 + Vector2(2, -1), c2 + Vector2(0, -1)]), C_LAMPE.darkened(0.1))
		BkDraw.texte(ci, c2 + Vector2(0, -10), str(d["secteur"]), 8, Color(1, 1, 1, 0.8), 2, 40)
