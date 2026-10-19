class_name GkView3D
extends Node3D
## Affichage 3D de la partie (SPEC-GORDEKA §9) : même vue de dessus en 3/4, mais des modèles
## en volume, ombrage « toon » et contours sombres, pour garder le style cartoon d'origine.
## Les règles restent en 2D (GkGame, GkMap) : cette vue ne fait que recopier leur état.
## 1 case (64 px de jeu) = 1 mètre.

const INK: Color = Color("1d2230")
const SKIN_WALL: Color = Color("f4efe4")         # crépi blanc à la chaux
const BASQUE_RED: Color = Color("9e1b1b")
const BASQUE_GREEN: Color = Color("1f6b3a")
const ROOF: Color = Color("c0533a")
const STONE: Color = Color("cbbfa6")
const SLAB_H: float = 0.35
## Caméra : environ 50° de plongée, assez pour voir les personnages de trois quarts.
const CAM_OFFSET: Vector3 = Vector3(0, 10.0, 8.6)                        # épaisseur des quais au-dessus de l'eau

var game: GkGame
var map: GkMap
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var spot: SpotLight3D
var near: OmniLight3D
var _cone: ImmediateMesh
var _fx: ImmediateMesh
var _actors: Dictionary = {}       # id → {root, body, legs, label}
var _cachettes: Array[Node3D] = []
var _lids: Array[MeshInstance3D] = []
var _exit_mat: StandardMaterial3D
var _exit_labels: Array[Label3D] = []
var _mats: Dictionary = {}
var _outline: StandardMaterial3D
var _t: float = 0.0
## QA : `--gk-look=x,y` (en cases) fixe la caméra sur un point de la carte.
var _look_at: Vector2 = Vector2.INF


func setup(p_game: GkGame) -> void:
	game = p_game
	map = game.map
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--gk-look="):
			var xy: PackedStringArray = arg.trim_prefix("--gk-look=").split(",")
			_look_at = Vector2(float(xy[0]), float(xy[1]))
	_outline = StandardMaterial3D.new()
	_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline.albedo_color = INK
	_outline.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline.grow = true
	_outline.grow_amount = 0.035
	_build_env()
	_build_ground()
	_build_objects()
	_build_cachettes()
	_build_exits()
	for a: GkActor in game.actors:
		_build_actor(a)
	var ci: MeshInstance3D = MeshInstance3D.new()
	_cone = ImmediateMesh.new()
	ci.mesh = _cone
	ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ci)
	var fi: MeshInstance3D = MeshInstance3D.new()
	_fx = ImmediateMesh.new()
	fi.mesh = _fx
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fi)


# ---------------------------------------------------------------- outils

func p3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x / map.tile, y, p.y / map.tile)


## Position à l'écran d'un point de jeu (pour le HUD : jauges, flèche).
func screen_pos(p: Vector2, height: float = 0.0) -> Vector2:
	return cam.unproject_position(p3(p, height))


func is_visible_pos(p: Vector2) -> bool:
	return not cam.is_position_behind(p3(p)) and get_viewport().get_visible_rect().has_point(screen_pos(p))


func mat(c: Color, unshaded: bool = false, outline: bool = false) -> StandardMaterial3D:
	var key: String = "%s|%s|%s" % [c.to_html(), unshaded, outline]
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 1.0
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if outline:
		m.next_pass = _outline
	_mats[key] = m
	return m


## Matériau texturé (textures peintes de pixelforge, assets/gordeka/textures/) : projection
## « triplanaire » en coordonnées du monde, la texture couvre `meters` mètres et se répète.
func tex_mat(name: String, meters: float, outline: bool = false) -> StandardMaterial3D:
	var key: String = "tex|%s|%s|%s" % [name, meters, outline]
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/gordeka/textures/%s.png" % name)
	# Sols plus doux que les personnages : on les garde lisibles au premier plan.
	if name == "paves":
		m.albedo_color = Color(1.0, 0.95, 0.86)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / meters
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if outline:
		m.next_pass = _outline
	_mats[key] = m
	return m


## Texture du sol selon le motif de la zone (vide : couleur unie).
const FLOOR_TEX: Dictionary = {"dalles": ["dalles", 3.0], "paves": ["paves", 4.5], "planches": ["planches", 2.5]}


func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, outline: bool = true) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var b: BoxMesh = BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat(c, false, outline)
	mi.position = pos
	parent.add_child(mi)
	return mi


func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, c: Color, outline: bool = true,
		seg: int = 16) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	mi.mesh = m
	mi.material_override = mat(c, false, outline)
	mi.position = pos
	parent.add_child(mi)
	return mi


func ball(parent: Node3D, r: float, pos: Vector3, c: Color, scale_v: Vector3 = Vector3.ONE, outline: bool = true) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var m: SphereMesh = SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	mi.mesh = m
	mi.material_override = mat(c, false, outline)
	mi.position = pos
	mi.scale = scale_v
	parent.add_child(mi)
	return mi


func capsule(parent: Node3D, r: float, h: float, pos: Vector3, c: Color, outline: bool = true) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var m: CapsuleMesh = CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 6
	mi.mesh = m
	mi.material_override = mat(c, false, outline)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Rectangles fusionnés des cases qui ont la même clé (clé vide = ignorée).
func _merge(key: Callable) -> Array:
	var used: Dictionary = {}
	var out: Array = []
	for y: int in map.height:
		for x: int in map.width:
			var k: String = key.call(Vector2i(x, y))
			if k == "" or used.has(Vector2i(x, y)):
				continue
			var w: int = 1
			while x + w < map.width and not used.has(Vector2i(x + w, y)) and key.call(Vector2i(x + w, y)) == k:
				w += 1
			var h: int = 1
			while y + h < map.height:
				var ok: bool = true
				for xx: int in range(x, x + w):
					if used.has(Vector2i(xx, y + h)) or key.call(Vector2i(xx, y + h)) != k:
						ok = false
						break
				if not ok:
					break
				h += 1
			for yy: int in range(y, y + h):
				for xx: int in range(x, x + w):
					used[Vector2i(xx, yy)] = true
			out.append([k, Rect2i(x, y, w, h)])
	return out


# ---------------------------------------------------------------- monde

func _build_env() -> void:
	var we: WorldEnvironment = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2e86c1")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9d6ff")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -28, 0)
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.current = true
	add_child(cam)
	# Lampe torche du chasseur : son cône de vision, avec de vraies ombres.
	spot = SpotLight3D.new()
	spot.spot_range = GkRules.f("cone_range") + 1.0
	spot.spot_angle = GkRules.f("cone_deg") * 0.5
	spot.spot_angle_attenuation = 0.4
	spot.light_energy = 4.0
	spot.shadow_enabled = not OS.get_cmdline_user_args().has("--gk-noshadow")
	spot.light_color = Color("fff3d6")
	spot.visible = false
	add_child(spot)
	near = OmniLight3D.new()
	near.omni_range = GkRules.f("near_radius") + 0.8
	near.light_energy = 0.9
	near.shadow_enabled = false
	near.visible = false
	add_child(near)


func _floor_color(t: Vector2i) -> String:
	var ch: String = map.at(t)
	if ch == "~" or (ch == "B" and _afloat(t)):
		return ""
	var z: int = map.zone_of(t)
	if z < 0:
		return "d0c6b0"
	var f: Array = map._floor_of(str(map.zones[z]["name"]))
	return str(f[0]) + "|%d" % z


## Case de bateau au mouillage : de l'eau à côté (pas de quai sous la coque).
func _afloat(t: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		if map.at(t + d) == "~":
			return true
	return false


func _build_ground() -> void:
	# Eau du port, sous les quais.
	var water: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(map.width + 40, map.height + 40)
	water.mesh = plane
	var wm: StandardMaterial3D = StandardMaterial3D.new()
	wm.albedo_color = Color("2f8fcf")
	wm.roughness = 0.25
	wm.metallic_specular = 0.6
	water.material_override = wm
	water.position = Vector3(map.width * 0.5, -SLAB_H, map.height * 0.5)
	add_child(water)
	# Quais et sols : une dalle par rectangle de même zone ; on voit leur tranche au-dessus de l'eau.
	for it: Array in _merge(_floor_color):
		var k: String = it[0]
		var r: Rect2i = it[1]
		var c: Color = Color(k.split("|")[0])
		var mi: MeshInstance3D = box(self, Vector3(r.size.x, SLAB_H, r.size.y),
			Vector3(r.position.x + r.size.x * 0.5, -SLAB_H * 0.5, r.position.y + r.size.y * 0.5), c, false)
		var parts: PackedStringArray = k.split("|")
		var zi: int = int(parts[1]) if parts.size() > 1 else -1
		var motif: String = str(map._floor_of(str(map.zones[zi]["name"]))[1]) if zi >= 0 else ""
		if FLOOR_TEX.has(motif):
			mi.material_override = tex_mat(str(FLOOR_TEX[motif][0]), float(FLOOR_TEX[motif][1]))
		else:
			mi.material_override = mat(c)
	for it: Array in _merge(func(t: Vector2i) -> String: return "q" if _floor_color(t) != "" and map.at(t + Vector2i(0, 1)) == "~" else ""):
		var r: Rect2i = it[1]
		var edge: MeshInstance3D = box(self, Vector3(r.size.x, SLAB_H + 0.02, 0.12), Vector3(r.position.x + r.size.x * 0.5, -SLAB_H * 0.5,
			r.end.y), STONE.darkened(0.25), false)
		edge.material_override = tex_mat("gres", 1.5)


func _zone_name(r: Rect2i) -> String:
	var z: int = map.zone_of(r.position + r.size / 2)
	return str(map.zones[z]["name"]) if z >= 0 else ""


func _build_objects() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for r: Rect2i in map.merged_rects("#"):
		var zn: String = _zone_name(r)
		var c: Vector3 = Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
		var sz: Vector3 = Vector3(r.size.x, 0, r.size.y)
		if zn == "":
			_stone_wall(c, sz)
		elif zn.begins_with("Crampottes") or zn.begins_with("Rue"):
			_house(c, sz, rng)
		elif zn.begins_with("Place"):
			_fountain(c, sz)
		elif zn.begins_with("Hangar"):
			_shelf(c, sz, rng)
		else:
			_white_block(c, sz)
	for r: Rect2i in map.merged_rects("c"):
		var c2: Vector3 = Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
		if _zone_name(r).begins_with("Parking"):
			_car(c2, Vector3(r.size.x, 0, r.size.y), rng)
		else:
			_crates(c2, Vector3(r.size.x, 0, r.size.y), rng)
	for r: Rect2i in map.merged_rects("B"):
		var on_water: bool = _afloat(r.position)
		_boat(Vector3(r.position.x + r.size.x * 0.5, -0.25 if on_water else 0.0, r.position.y + r.size.y * 0.5),
			Vector3(r.size.x, 0, r.size.y), rng)
	for r: Rect2i in map.merged_rects("t"):
		var c3: Vector3 = Vector3(r.position.x + r.size.x * 0.5, 0, r.position.y + r.size.y * 0.5)
		var zn2: String = _zone_name(r)
		if r.size == Vector2i(1, 1) and (zn2.begins_with("Jetée") or zn2.begins_with("Bassin")):
			cyl(self, 0.18, 0.24, 0.55, c3 + Vector3(0, 0.27, 0), Color("2a2d34"))     # bitte d'amarrage
			ball(self, 0.2, c3 + Vector3(0, 0.58, 0), Color("2a2d34"), Vector3(1, 0.6, 1))
		else:
			_table(c3, Vector3(r.size.x, 0, r.size.y), zn2)


func _stone_wall(c: Vector3, sz: Vector3) -> void:
	box(self, Vector3(sz.x, 1.1, sz.z), c + Vector3(0, 0.55, 0), STONE).material_override = tex_mat("gres", 2.0, true)
	box(self, Vector3(sz.x + 0.08, 0.12, sz.z + 0.08), c + Vector3(0, 1.16, 0), STONE.lightened(0.15))


func _white_block(c: Vector3, sz: Vector3) -> void:
	box(self, Vector3(sz.x - 0.05, 1.5, sz.z - 0.05), c + Vector3(0, 0.75, 0), SKIN_WALL)
	box(self, Vector3(sz.x, 0.3, sz.z), c + Vector3(0, 0.15, 0), STONE)
	box(self, Vector3(sz.x + 0.06, 0.12, sz.z + 0.06), c + Vector3(0, 1.52, 0), BASQUE_RED)


## Maison labourdine / crampotte : murs blanchis, colombages et volets rouges ou verts,
## toit de tuiles à deux pentes (faîte dans la longueur).
func _house(c: Vector3, sz: Vector3, rng: RandomNumberGenerator) -> void:
	var trim: Color = BASQUE_RED if rng.randf() < 0.7 else BASQUE_GREEN
	var w: float = sz.x - 0.1
	var d: float = sz.z - 0.1
	var h: float = 1.9
	box(self, Vector3(w, h, d), c + Vector3(0, h * 0.5, 0), SKIN_WALL)
	box(self, Vector3(w + 0.04, 0.3, d + 0.04), c + Vector3(0, 0.15, 0), STONE).material_override = tex_mat("gres", 1.5, true)
	# Colombages : poteaux d'angle et sablière, sur les quatre faces.
	for sx: float in [-0.5, 0.5]:
		for sz2: float in [-0.5, 0.5]:
			box(self, Vector3(0.14, h, 0.14), c + Vector3(sx * w, h * 0.5, sz2 * d), trim, false)
	box(self, Vector3(w + 0.06, 0.13, d + 0.06), c + Vector3(0, h - 0.5, 0), trim, false)
	# Fenêtres à volets sur la face avant (vers la caméra, +z).
	var n: int = maxi(1, int(w / 1.6))
	for i: int in n:
		var x: float = -w * 0.5 + w * (float(i) + 0.5) / float(n)
		var fz: float = c.z + d * 0.5 + 0.03
		box(self, Vector3(0.42, 0.5, 0.05), Vector3(c.x + x, 0.95, fz), Color("2c3e66"), false)
		for s: float in [-1.0, 1.0]:
			box(self, Vector3(0.2, 0.52, 0.06), Vector3(c.x + x + s * 0.33, 0.95, fz + 0.01), trim, false)
	# Toit à deux pentes, légèrement asymétrique, avec débord.
	var along_x: bool = w >= d
	var span: float = (d if along_x else w) + 0.5
	var length: float = (w if along_x else d) + 0.4
	var rise: float = 0.9
	var roof: MeshInstance3D = MeshInstance3D.new()
	roof.mesh = _roof_mesh(length, span, rise, 0.42)
	roof.material_override = mat(ROOF, false, true)
	roof.position = c + Vector3(0, h, 0)
	if not along_x:
		roof.rotation.y = PI * 0.5
	add_child(roof)


## Toit en prisme : faîte le long de X, à `ridge` (0..1) de la largeur ; pignons fermés.
func _roof_mesh(length: float, span: float, rise: float, ridge: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl: float = length * 0.5
	var z0: float = -span * 0.5
	var z1: float = span * 0.5
	var zr: float = z0 + span * ridge
	var quads: Array = [
		[Vector3(-hl, 0, z0), Vector3(hl, 0, z0), Vector3(hl, rise, zr), Vector3(-hl, rise, zr)],
		[Vector3(-hl, rise, zr), Vector3(hl, rise, zr), Vector3(hl, 0, z1), Vector3(-hl, 0, z1)],
	]
	for q: Array in quads:
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[idx])
	for x: float in [-hl, hl]:
		st.add_vertex(Vector3(x, 0, z0))
		st.add_vertex(Vector3(x, rise, zr))
		st.add_vertex(Vector3(x, 0, z1))
	st.generate_normals()
	return st.commit()


func _fountain(c: Vector3, sz: Vector3) -> void:
	var r: float = minf(sz.x, sz.z) * 0.5
	cyl(self, r, r, 0.45, c + Vector3(0, 0.22, 0), STONE)
	cyl(self, r - 0.12, r - 0.12, 0.05, c + Vector3(0, 0.44, 0), Color("4fb3e6"), false)
	cyl(self, 0.16, 0.2, 1.1, c + Vector3(0, 0.55, 0), STONE.lightened(0.1))
	ball(self, 0.3, c + Vector3(0, 1.15, 0), STONE.lightened(0.1), Vector3(1, 0.5, 1))


func _shelf(c: Vector3, sz: Vector3, rng: RandomNumberGenerator) -> void:
	box(self, Vector3(sz.x - 0.1, 1.6, sz.z - 0.1), c + Vector3(0, 0.8, 0), Color("8a5a32"))
	for i: int in int(sz.z):
		var z: float = c.z - sz.z * 0.5 + 0.5 + i
		box(self, Vector3(sz.x * 0.7, 0.35, 0.6), Vector3(c.x, 1.78, z), [Color("2f8fcf"), Color("e0a03a"), Color("2fb24a")][rng.randi() % 3])


func _crates(c: Vector3, sz: Vector3, rng: RandomNumberGenerator) -> void:
	for x: int in int(sz.x):
		for z: int in int(sz.z):
			var p: Vector3 = Vector3(c.x - sz.x * 0.5 + 0.5 + x, 0, c.z - sz.z * 0.5 + 0.5 + z)
			var h: float = 0.7 if rng.randf() < 0.6 else 1.25
			box(self, Vector3(0.9, h, 0.9), p + Vector3(0, h * 0.5, 0), Color("d29a55"))
			box(self, Vector3(0.94, 0.08, 0.94), p + Vector3(0, h - 0.04, 0), Color("a8743a"), false)


func _car(c: Vector3, sz: Vector3, rng: RandomNumberGenerator) -> void:
	var col: Color = [Color("e8e2d0"), BASQUE_RED, Color("2f6fe0"), BASQUE_GREEN, Color("f2c12e")][rng.randi() % 5]
	box(self, Vector3(sz.x - 0.25, 0.6, sz.z - 0.3), c + Vector3(0, 0.4, 0), col)
	box(self, Vector3(sz.x * 0.5, 0.45, sz.z - 0.45), c + Vector3(-0.1, 0.92, 0), Color("bfe3f2"))
	for sx: float in [-0.32, 0.32]:
		for sz2: float in [-0.5, 0.5]:
			cyl(self, 0.18, 0.18, 0.12, Vector3(c.x + sx * sz.x, 0.18, c.z + sz2 * (sz.z - 0.3)), Color("222222"), false)


func _boat(c: Vector3, sz: Vector3, rng: RandomNumberGenerator) -> void:
	var stripe: Color = [BASQUE_RED, BASQUE_GREEN, Color("2f6fe0"), Color("f2c12e")][rng.randi() % 4]
	var big: bool = sz.x * sz.z >= 18.0
	var h: float = 0.9 if big else 0.65
	var along_x: bool = sz.x >= sz.z
	var length: float = (sz.x if along_x else sz.z) - 0.15
	var width: float = (sz.z if along_x else sz.x) - 0.25
	var n: Node3D = Node3D.new()
	n.position = c
	if not along_x:
		n.rotation.y = -PI * 0.5
	add_child(n)
	var hull: MeshInstance3D = MeshInstance3D.new()
	hull.mesh = _hull_mesh(length, width, h)
	hull.material_override = mat(Color("f7f8fa"), false, true)
	n.add_child(hull)
	var band: MeshInstance3D = MeshInstance3D.new()
	band.mesh = _hull_mesh(length + 0.1, width + 0.12, 0.16)
	band.material_override = mat(stripe, false, false)
	band.position.y = h - 0.22
	n.add_child(band)
	var deck: MeshInstance3D = MeshInstance3D.new()
	deck.mesh = _hull_mesh(length - 0.4, width - 0.3, 0.06)
	deck.material_override = mat(Color("b98250"), false, false)
	deck.position.y = h + 0.005
	n.add_child(deck)
	if big:
		box(n, Vector3(length * 0.22, 1.0, width * 0.6), Vector3(-length * 0.15, h + 0.5, 0), SKIN_WALL)
		box(n, Vector3(length * 0.24, 0.1, width * 0.68), Vector3(-length * 0.15, h + 1.02, 0), stripe)
		cyl(n, 0.05, 0.05, 1.8, Vector3(length * 0.12, h + 0.9, 0), Color("6b4a2a"))


## Coque : contour pointu à la proue (+X), arrière plat, flancs rentrés vers le fond.
func _hull_mesh(length: float, width: float, h: float) -> ArrayMesh:
	var hl: float = length * 0.5
	var hw: float = width * 0.5
	var top: PackedVector3Array = [Vector3(-hl, h, -hw), Vector3(hl * 0.35, h, -hw), Vector3(hl, h, 0),
		Vector3(hl * 0.35, h, hw), Vector3(-hl, h, hw)]
	var bot: PackedVector3Array = PackedVector3Array()
	for p: Vector3 in top:
		bot.append(Vector3(p.x * 0.85, 0, p.z * 0.6))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in top.size():
		var k: int = (i + 1) % top.size()
		for v: Vector3 in [top[i], bot[i], bot[k], top[i], bot[k], top[k]]:
			st.add_vertex(v)
	for i: int in range(1, top.size() - 1):
		for v: Vector3 in [top[0], top[i], top[i + 1]]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _table(c: Vector3, sz: Vector3, zone: String) -> void:
	var top: Color = Color("e2c28c")
	if zone.begins_with("Terrasse"):
		top = Color("f4efe4")
	elif zone.begins_with("Criée"):
		top = Color("cfd8dc")
	box(self, Vector3(sz.x - 0.15, 0.08, sz.z - 0.15), c + Vector3(0, 0.72, 0), top)
	if zone.begins_with("Terrasse"):
		for i: int in 3:                    # nappe en linge basque
			box(self, Vector3(sz.x - 0.2, 0.09, 0.06), c + Vector3(0, 0.73, -0.25 + i * 0.25),
				[BASQUE_RED, BASQUE_GREEN, Color("2f6fe0")][i], false)
	for sx: float in [-0.5, 0.5]:
		for sz2: float in [-0.5, 0.5]:
			box(self, Vector3(0.07, 0.7, 0.07), c + Vector3(sx * (sz.x - 0.35), 0.35, sz2 * (sz.z - 0.35)), Color("8a6239"), false)


func _build_cachettes() -> void:
	for cdata: Dictionary in game.cachettes:
		var n: Node3D = Node3D.new()
		n.position = p3(cdata["pos"])
		add_child(n)
		# Casier de pêcheur vert basque, avec couvercle.
		box(n, Vector3(0.8, 1.05, 0.8), Vector3(0, 0.52, 0), BASQUE_GREEN)
		for i: int in 3:
			box(n, Vector3(0.82, 0.05, 0.82), Vector3(0, 0.25 + i * 0.3, 0), BASQUE_GREEN.darkened(0.3), false)
		var lid: MeshInstance3D = box(n, Vector3(0.9, 0.12, 0.9), Vector3(0, 1.1, 0), BASQUE_GREEN.lightened(0.2))
		_cachettes.append(n)
		_lids.append(lid)


func _build_exits() -> void:
	_exit_mat = StandardMaterial3D.new()
	_exit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_exit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_exit_mat.albedo_color = Color(0.5, 0.5, 0.5, 0.35)
	for r: Rect2i in map.merged_rects("E"):
		var mi: MeshInstance3D = MeshInstance3D.new()
		var pm: PlaneMesh = PlaneMesh.new()
		pm.size = Vector2(r.size.x, r.size.y)
		mi.mesh = pm
		mi.material_override = _exit_mat
		mi.position = Vector3(r.position.x + r.size.x * 0.5, 0.02, r.position.y + r.size.y * 0.5)
		add_child(mi)
		var l: Label3D = Label3D.new()
		l.text = "SORTIE"
		l.font_size = 64
		l.outline_size = 16
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = mi.position + Vector3(0, 1.4, 0)
		add_child(l)
		_exit_labels.append(l)


# ---------------------------------------------------------------- personnages

## Petit bonhomme façon Among Us en volume : corps en capsule, visière, sac (ou l'objet du
## perso), jambes, et l'accessoire qui le rend reconnaissable.
func _build_actor(a: GkActor) -> void:
	var root: Node3D = Node3D.new()
	add_child(root)
	var body: Node3D = Node3D.new()
	root.add_child(body)
	var col: Color = a.color
	var dark: Color = col.darkened(0.35)
	var legs: Array[MeshInstance3D] = []
	for s: float in [-0.13, 0.13]:
		legs.append(capsule(body, 0.11, 0.42, Vector3(0, 0.2, s), dark))
	capsule(body, 0.3, 0.95, Vector3(0, 0.72, 0), col)
	ball(body, 0.17, Vector3(0.24, 0.86, 0), Color("8fd3ee"), Vector3(0.55, 0.75, 1.15))
	ball(body, 0.05, Vector3(0.31, 0.93, -0.06), Color(1, 1, 1), Vector3(0.6, 0.6, 1.4), false)
	_back_item(body, a.character, dark)
	_head_item(body, a.character, col)
	var label: Label3D = Label3D.new()
	label.text = a.display_name
	label.font_size = 40
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 1.75 if a.character == "ramuntxo" else 1.5, 0)
	root.add_child(label)
	_actors[a.id] = {"root": root, "body": body, "legs": legs, "label": label, "ghost": false}


func _back_item(body: Node3D, ch: String, dark: Color) -> void:
	match ch:
		"maia":
			var b: MeshInstance3D = capsule(body, 0.09, 1.1, Vector3(-0.3, 0.7, 0), Color("f7efdc"))
			b.scale = Vector3(0.5, 1, 1.6)
		"mattin":
			ball(body, 0.26, Vector3(-0.38, 0.75, 0), Color("8d939e"), Vector3(1, 0.85, 1.1))
		"xabi":
			ball(body, 0.2, Vector3(-0.34, 0.7, 0), Color("c9a46a"), Vector3(0.6, 1.4, 0.8))
		"amaia":
			var st: MeshInstance3D = cyl(body, 0.03, 0.03, 1.3, Vector3(-0.32, 0.8, 0), Color("7a4a24"))
			st.rotation.z = 0.35
		"karramarro":
			ball(body, 0.17, Vector3(0.25, 0.45, 0.32), dark, Vector3(1.3, 0.8, 0.9))
			ball(body, 0.17, Vector3(0.25, 0.45, -0.32), dark, Vector3(1.3, 0.8, 0.9))
		_:
			box(body, Vector3(0.18, 0.42, 0.42), Vector3(-0.3, 0.72, 0), dark)


func _head_item(body: Node3D, ch: String, col: Color) -> void:
	match ch:
		"louis":                                                   # txapela rouge
			cyl(body, 0.3, 0.3, 0.07, Vector3(0.02, 1.2, 0), Color("c62828"))
			cyl(body, 0.02, 0.02, 0.1, Vector3(0.02, 1.28, 0), Color("c62828"), false)
		"maia":
			cyl(body, 0.31, 0.31, 0.08, Vector3(0, 1.08, 0), Color("f2c12e"))
		"patxi":                                                   # bonnet de marin et barbe
			ball(body, 0.31, Vector3(0, 1.14, 0), Color("2b4c8c"), Vector3(1, 0.75, 1))
			cyl(body, 0.32, 0.32, 0.1, Vector3(0, 1.08, 0), Color("1f3a70"))
			ball(body, 0.13, Vector3(0.24, 0.62, 0), Color("6b4226"), Vector3(0.8, 0.9, 1.4))
		"xabi":
			cyl(body, 0.31, 0.31, 0.07, Vector3(0, 1.06, 0), Color.WHITE)
		"mattin":
			cyl(body, 0.32, 0.3, 0.06, Vector3(0, 1.2, 0), Color("2a2a30"))
		"amaia":
			ball(body, 0.09, Vector3(-0.05, 1.18, 0.18), Color("e53935"))
		"txomin":                                                  # lunettes noires et sifflet
			box(body, Vector3(0.12, 0.13, 0.44), Vector3(0.33, 0.9, 0), Color("111111"))
			ball(body, 0.06, Vector3(0.28, 0.5, 0.1), Color("f2c12e"))
		"kaio":                                                    # bec et houppette
			var beak: MeshInstance3D = cyl(body, 0.0, 0.1, 0.32, Vector3(0.48, 0.86, 0), Color("f6a91e"))
			beak.rotation.z = -PI * 0.5
			for i: int in 3:
				ball(body, 0.08, Vector3(-0.05 + i * 0.08, 1.2 + (0.04 if i == 1 else 0.0), 0), Color("eef1f4"), Vector3(0.8, 1.4, 0.8))
		"karramarro":                                              # yeux sur pédoncules
			for s: float in [-0.12, 0.12]:
				cyl(body, 0.025, 0.025, 0.3, Vector3(0.05, 1.28, s), Color("1d2230"), false)
				ball(body, 0.08, Vector3(0.05, 1.45, s), Color.WHITE)
		"ramuntxo":                                                # toque de chef
			cyl(body, 0.24, 0.22, 0.32, Vector3(0, 1.3, 0), Color.WHITE)
			for s: float in [-0.13, 0.0, 0.13]:
				ball(body, 0.15, Vector3(s * 0.4, 1.52, s), Color.WHITE)
		"itsaso":                                                  # couronne d'écume
			for i: int in 5:
				var a2: float = TAU * float(i) / 5.0
				ball(body, 0.09, Vector3(cos(a2) * 0.2, 1.15, sin(a2) * 0.2),
					Color("e8fbff") if i % 2 == 0 else Color("7fd6f0"))
		"peio":                                                    # casque de rugby
			ball(body, 0.32, Vector3(0, 1.08, 0), Color("c62828"), Vector3(1, 0.7, 1))


# ---------------------------------------------------------------- image par image

func refresh(dt: float) -> void:
	_t += dt
	var as_hunter: bool = game.local == game.hunter and game.phase != GkGame.Phase.END \
		and game.phase != GkGame.Phase.PODIUM
	# Lumière : plein jour pour les chassés ; nuit et lampe torche pour le chasseur.
	sun.light_energy = 0.0 if as_hunter else 0.42
	env.ambient_light_energy = 0.05 if as_hunter else 0.13
	env.background_color = Color("0f2a40") if as_hunter else Color("2e86c1")
	spot.visible = as_hunter
	near.visible = as_hunter
	if game.hunter:
		var fwd: Vector3 = Vector3(cos(game.hunter.look), 0, sin(game.hunter.look))
		var hp: Vector3 = p3(game.hunter.position, 1.0)
		# Devant le corps : à l'intérieur, la capsule du chasseur bloquerait sa propre lampe.
		spot.position = hp + fwd * 0.45
		spot.look_at(spot.position + fwd + Vector3(0, -0.12, 0), Vector3.UP)
		near.position = hp
	# Caméra : vue de dessus en 3/4 qui suit le joueur.
	var target: Vector3 = p3(game.local.position) if _look_at == Vector2.INF else Vector3(_look_at.x, 0, _look_at.y)
	var want: Vector3 = target + CAM_OFFSET
	cam.position = want if _t < 0.2 else cam.position.lerp(want, minf(1.0, dt * 6.0))
	cam.look_at(cam.position - CAM_OFFSET + Vector3(0, 0.6, 0), Vector3.UP)
	# Personnages.
	for a: GkActor in game.actors:
		var n: Dictionary = _actors[a.id]
		var root: Node3D = n["root"]
		var vis: bool = a.shown and a.hidden_in < 0
		root.visible = vis
		if not vis:
			continue
		root.position = p3(a.position)
		var body: Node3D = n["body"]
		body.rotation.y = -a.look
		var moving: bool = a.walk_phase != 0.0
		body.position.y = absf(sin(a.walk_phase)) * 0.08 if moving else 0.0
		var legs: Array = n["legs"]
		(legs[0] as Node3D).rotation.z = sin(a.walk_phase) * 0.5
		(legs[1] as Node3D).rotation.z = -sin(a.walk_phase) * 0.5
		var ghost: bool = a.role == GkActor.Role.GHOST or a.role == GkActor.Role.OUT
		if ghost != bool(n["ghost"]):
			n["ghost"] = ghost
			_set_ghost(body, ghost)
		if ghost:
			body.position.y = 0.25 + sin(_t * 3.0 + a.id) * 0.08
		(n["label"] as Label3D).modulate = Color(1, 1, 1, 0.5 if ghost else 1.0)
	# Cachettes (secouées quand on entre ou qu'on fouille ; couvercle de la couleur de l'occupant
	# pour les chassés).
	for i: int in _cachettes.size():
		var cdata: Dictionary = game.cachettes[i]
		var sh: float = float(cdata["shake"])
		_cachettes[i].rotation.z = sin(sh * 60.0) * 0.08 if sh > 0.0 else 0.0
		var occ: int = int(cdata["occupant"])
		var lid_col: Color = BASQUE_GREEN.lightened(0.2)
		if occ >= 0 and not as_hunter:
			lid_col = game.actors[occ].color
		elif float(cdata["lock"]) > 0.0:
			lid_col = Color("7a7a7a")
		_lids[i].material_override = mat(lid_col, false, true)
	# Sorties.
	var open: bool = game.exits_open()
	_exit_mat.albedo_color = Color(0.3, 0.95, 0.45, 0.45 + 0.15 * sin(_t * 4.0)) if open else Color(0.5, 0.5, 0.5, 0.3)
	for l: Label3D in _exit_labels:
		l.text = "SORTIE" if open else "FERMÉE"
		l.modulate = Color("6fe08a") if open else Color("bbbbbb")
	_draw_cone(as_hunter)
	_draw_fx(as_hunter)


func _set_ghost(body: Node3D, ghost: bool) -> void:
	for c: Node in body.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.transparency = 0.6 if ghost else 0.0


func _draw_cone(as_hunter: bool) -> void:
	_cone.clear_surfaces()
	if as_hunter or game.hunter == null or not (game.phase == GkGame.Phase.HUNT or game.phase == GkGame.Phase.HIDE):
		return
	var poly: PackedVector2Array = game.cone_polygon(game.hunter)
	var m: StandardMaterial3D = mat(Color(1, 0.15, 0.1, 0.28 if game.phase == GkGame.Phase.HUNT else 0.12), true)
	m.no_depth_test = false
	_cone.surface_begin(Mesh.PRIMITIVE_TRIANGLES, m)
	var c: Vector3 = p3(poly[0], 0.04)
	for i: int in range(1, poly.size() - 1):
		_cone.surface_add_vertex(c)
		_cone.surface_add_vertex(p3(poly[i], 0.04))
		_cone.surface_add_vertex(p3(poly[i + 1], 0.04))
	_cone.surface_end()
	_ring(_cone, game.hunter.position, GkRules.f("near_radius"), 0.06, Color(1, 0.2, 0.15, 0.5))


func _draw_fx(as_hunter: bool) -> void:
	_fx.clear_surfaces()
	# Pièges (filets jaunes) : visibles des chassés ; le chasseur ne les voit que tout près.
	for t: Dictionary in game.traps:
		var p: Vector2 = t["pos"]
		if as_hunter and (p.distance_to(game.hunter.position) > GkRules.px("trap_seen_range") or not game.sees(game.hunter, p, 6.0)):
			continue
		_disc(_fx, p, 0.32, Color(0.95, 0.75, 0.2, 0.85))
		_ring(_fx, p, 0.32, 0.05, Color("5a3410"))
	# Onde de détection et silhouettes révélées.
	for r: Dictionary in game.reveals:
		var left: float = float(r["left"])
		if int(r["id"]) < 0:
			var k: float = 1.0 - left / 0.6
			_ring(_fx, r["pos"], GkRules.f("detect_radius") * k, 0.12, Color(0.6, 0.85, 1.0, 1.0 - k))
		elif as_hunter or not game.local.is_hider():
			_disc(_fx, r["pos"], 0.45, Color(0.6, 0.85, 1.0, 0.55))
	# Sortie en cours.
	for a: GkActor in game.actors:
		if a.extract_t > 0.0 and a.role == GkActor.Role.HIDER and a.shown:
			_ring(_fx, a.position, 0.6 * a.extract_t / GkRules.f("extract_hold") + 0.2, 0.08, Color("6fe08a"))


func _disc(im: ImmediateMesh, p: Vector2, r: float, c: Color) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat(c, true))
	var ctr: Vector3 = p3(p, 0.05)
	for i: int in 20:
		var a0: float = TAU * float(i) / 20.0
		var a1: float = TAU * float(i + 1) / 20.0
		im.surface_add_vertex(ctr)
		im.surface_add_vertex(ctr + Vector3(cos(a0), 0, sin(a0)) * r)
		im.surface_add_vertex(ctr + Vector3(cos(a1), 0, sin(a1)) * r)
	im.surface_end()


func _ring(im: ImmediateMesh, p: Vector2, r: float, w: float, c: Color) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat(c, true))
	var ctr: Vector3 = p3(p, 0.06)
	for i: int in 40:
		var a0: float = TAU * float(i) / 40.0
		var a1: float = TAU * float(i + 1) / 40.0
		var o0: Vector3 = Vector3(cos(a0), 0, sin(a0))
		var o1: Vector3 = Vector3(cos(a1), 0, sin(a1))
		im.surface_add_vertex(ctr + o0 * r)
		im.surface_add_vertex(ctr + o0 * (r + w))
		im.surface_add_vertex(ctr + o1 * r)
		im.surface_add_vertex(ctr + o1 * r)
		im.surface_add_vertex(ctr + o0 * (r + w))
		im.surface_add_vertex(ctr + o1 * (r + w))
	im.surface_end()
