class_name FighterDb
extends RefCounted
## Charge assets/fighters/<id>/data.json et le convertit en FighterDef
## entier (px → sous-pixels, flottants → pour-mille). Cache par id.

const ROOT: String = "res://assets/fighters/%s/data.json"
const SUB: int = 256

const _LEVELS: Dictionary = {
	"mid": SimConst.LVL_MID, "low": SimConst.LVL_LOW, "air": SimConst.LVL_AIR,
	"throw": SimConst.LVL_THROW, "unblockable": SimConst.LVL_UNBLOCKABLE,
}
const _DIRS: Dictionary = {
	"DB": 1, "D": 2, "DF": 3, "B": 4, "N": 5, "F": 6, "UB": 7, "U": 8, "UF": 9,
}

static var _cache: Dictionary = {}


static func get_def(id: String) -> FighterDef:
	if _cache.has(id):
		return _cache[id]
	var data: Dictionary = load_json(id)
	if data.is_empty():
		push_error("FighterDb: data.json introuvable pour %s" % id)
		return null
	var def: FighterDef = parse(data)
	_cache[id] = def
	return def


static func load_json(id: String) -> Dictionary:
	var path: String = ROOT % id
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Liste des ids présents dans assets/fighters/ (ordre alphabétique).
static func list_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open("res://assets/fighters")
	if dir == null:
		return out
	for name: String in dir.get_directories():
		if FileAccess.file_exists(ROOT % name):
			out.append(name)
	out.sort()
	return out


static func parse(data: Dictionary) -> FighterDef:
	var def: FighterDef = FighterDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("name", def.id))
	def.health = int(data.get("health", 1000))
	def.walk_fwd = int(data.get("walk_fwd", 640))
	def.walk_back = int(data.get("walk_back", 512))
	def.run_speed = int(data.get("run", 1100))
	def.jump_v = int(data.get("jump_v", -2300))
	def.jump_h = int(data.get("jump_h", 700))
	def.gravity = int(data.get("gravity", 120))
	def.push_w = int(data.get("push_w", 22)) * SUB
	def.push_h = int(data.get("push_h", 70)) * SUB
	def.no_light_recoil = bool(data.get("no_light_recoil", false))
	_parse_anims(def, data)
	var projectiles: Dictionary = data.get("projectiles", {})
	var proj_names: Array = projectiles.keys()
	proj_names.sort()
	for pname: Variant in proj_names:
		def.projectiles.append(_parse_projectile(str(pname), projectiles[pname]))
	var moves: Dictionary = data.get("moves", {})
	var names: Array = moves.keys()
	names.sort()
	for mname: Variant in names:
		var mv: MoveDef = MoveDef.new()
		mv.name = str(mname)
		mv.index = def.moves.size()
		def.moves.append(mv)
		def.move_by_name[mv.name] = mv.index
	for mv: MoveDef in def.moves:
		_parse_move(def, mv, moves[mv.name], proj_names)
	def.m_punch = def.move("punch_1")
	def.m_kick = def.move("kick")
	def.m_kick_high = def.move("kick_high")
	def.m_crouch_punch = def.move("crouch_punch")
	def.m_sweep = def.move("sweep")
	def.m_uppercut = def.move("uppercut")
	def.m_jump_punch = def.move("jump_punch")
	def.m_jump_kick = def.move("jump_kick")
	def.m_throw = def.move("throw")
	def.m_super = def.move("super")
	var slots: PackedStringArray = ["sp_neutral", "sp_forward", "sp_down", "sp_up"]
	for i: int in 4:
		def.m_sp[i] = def.move(slots[i])
		def.m_sp_plus[i] = def.move(slots[i] + "_plus")
	var ai: Dictionary = data.get("ai", {})
	def.ai_aggression = int(round(float(ai.get("aggression", 0.5)) * 1000.0))
	def.ai_zoning = int(round(float(ai.get("zoning", 0.4)) * 1000.0))
	def.ai_anti_air = int(round(float(ai.get("anti_air", 0.6)) * 1000.0))
	for fav: Variant in ai.get("favorite_moves", []):
		var fi: int = def.move(str(fav))
		if fi >= 0:
			def.ai_favorites.append(fi)
	return def


static func _parse_anims(def: FighterDef, data: Dictionary) -> void:
	var anims: Dictionary = data.get("anims", {})
	var hurt: Dictionary = data.get("hurtboxes", {})
	for anim_name: String in SimConst.ANIMS:
		var a: Dictionary = anims.get(anim_name, {})
		def.anim_frames.append(int(a.get("frames", 1)))
		def.anim_fps.append(int(a.get("fps", 10)))
		def.anim_loop.append(1 if bool(a.get("loop", false)) else 0)
		def.anim_hit.append(int(a.get("hit_frame", int(a.get("frames", 1)) / 2)))
		var per_frame: Array = []
		for frame_boxes: Variant in hurt.get(anim_name, []):
			var boxes: Array = []
			for box: Variant in frame_boxes:
				boxes.append(_box(box))
			per_frame.append(boxes)
		def.hurt_by_anim.append(per_frame)


static func _box(raw: Variant) -> PackedInt32Array:
	var arr: Array = raw
	return PackedInt32Array([int(arr[0]) * SUB, int(arr[1]) * SUB, int(arr[2]) * SUB, int(arr[3]) * SUB])


static func _parse_projectile(pname: String, raw: Dictionary) -> ProjectileDef:
	var pd: ProjectileDef = ProjectileDef.new()
	pd.name = pname
	pd.anim = str(raw.get("anim", "proj_" + pname))
	pd.speed = int(raw.get("speed", 1024))
	pd.vy = int(raw.get("vy", 0))
	pd.gravity = int(raw.get("gravity", 0))
	pd.returns = bool(raw.get("returns", false))
	pd.damage = int(raw.get("damage", 60))
	pd.hitstun = int(raw.get("hitstun", 16))
	pd.blockstun = int(raw.get("blockstun", 10))
	pd.hit_level = int(_LEVELS.get(str(raw.get("hit_level", "mid")), 0))
	pd.knockdown = bool(raw.get("knockdown", false))
	var launch: Array = raw.get("launch", [0, 0])
	pd.launch_vx = int(launch[0])
	pd.launch_vy = int(launch[1])
	if raw.has("hitbox"):
		pd.hitbox = _box(raw["hitbox"])
	pd.life = int(raw.get("life", 90))
	pd.hits = int(raw.get("hits", 1))
	pd.rehit_interval = int(raw.get("rehit_interval", 20))
	pd.hitstop = int(raw.get("hitstop", 6))
	pd.meter_gain = int(raw.get("meter_gain", 3))
	pd.chip_permille = int(raw.get("chip", SimConst.CHIP_PERMILLE))
	pd.trap = bool(raw.get("trap", false))
	pd.slow_on_hit = int(raw.get("slow_on_hit", 0))
	pd.stun_on_hit = int(raw.get("stun_on_hit", 0))
	pd.pull_on_hit = int(raw.get("pull_on_hit", 0))
	pd.heavy = bool(raw.get("heavy", false))
	pd.ground = bool(raw.get("ground", false))
	return pd


static func _parse_move(def: FighterDef, mv: MoveDef, raw: Dictionary, proj_names: Array) -> void:
	mv.anim = maxi(SimConst.anim_index(str(raw.get("anim", mv.name))), 0)
	mv.startup = int(raw.get("startup", 4))
	mv.active = int(raw.get("active", 2))
	mv.recovery = int(raw.get("recovery", 8))
	mv.damage = int(raw.get("damage", 0))
	mv.hitstun = int(raw.get("hitstun", 12))
	mv.blockstun = int(raw.get("blockstun", 8))
	mv.pushback = int(raw.get("pushback", 6)) * SUB
	mv.hit_level = int(_LEVELS.get(str(raw.get("hit_level", "mid")), 0))
	mv.knockdown = bool(raw.get("knockdown", false))
	var launch: Array = raw.get("launch", [0, 0])
	mv.launch_vx = int(launch[0])
	mv.launch_vy = int(launch[1])
	mv.hitstop = int(raw.get("hitstop", SimConst.HITSTOP_LIGHT))
	mv.meter_gain = int(raw.get("meter_gain", 4))
	mv.is_special = mv.name.begins_with("sp_")
	mv.is_super = mv.name == "super"
	mv.is_throw = mv.name == "throw" or str(raw.get("hit_level", "")) == "throw"
	mv.chip_permille = int(raw.get("chip", SimConst.CHIP_PERMILLE if (mv.is_special or mv.is_super) else 0))
	mv.hits = int(raw.get("hits", 1))
	mv.rehit_interval = int(raw.get("rehit_interval", 0))
	mv.air_ok = bool(raw.get("air", mv.name.begins_with("jump_")))
	mv.armor = int(raw.get("armor", 0))
	mv.teleport_frame = int(raw.get("teleport_frame", -1))
	mv.pull_on_hit = int(raw.get("pull_on_hit", 0))
	mv.steal_meter = int(raw.get("steal_meter", 0))
	mv.reflects = bool(raw.get("reflects", false))
	mv.stun_on_hit = int(raw.get("stun_on_hit", 0))
	mv.slow_on_hit = int(raw.get("slow_on_hit", 0))
	var hb: Variant = raw.get("hitboxes", [])
	if hb is Dictionary:
		var keys: Array = (hb as Dictionary).keys()
		keys.sort()
		if not keys.is_empty():
			for box: Variant in (hb as Dictionary)[keys[0]]:
				mv.hitboxes.append(_box(box))
	else:
		for box: Variant in hb:
			mv.hitboxes.append(_box(box))
	var chain: String = str(raw.get("chain", ""))
	if chain != "":
		mv.chain_next = def.move(chain)
	for target: Variant in raw.get("cancel_into", []):
		if str(target) == "specials":
			mv.cancel_specials = true
		elif mv.chain_next < 0 and def.move(str(target)) >= 0:
			mv.chain_next = def.move(str(target))
	if raw.has("counter"):
		mv.counter_move = def.move(str(raw["counter"]))
	for v: Variant in raw.get("velocity", []):
		var arr: Array = v
		mv.velocity.append(PackedInt32Array([int(arr[0]), int(arr[1]), int(arr[2]) if arr.size() > 2 else 0]))
	if raw.has("spawn"):
		var sp: Dictionary = raw["spawn"]
		mv.spawn_frame = int(sp.get("frame", mv.startup))
		mv.spawn_projectile = proj_names.find(str(sp.get("projectile", "")))
		var off: Array = sp.get("offset", [24, -58])
		mv.spawn_x = int(off[0]) * SUB
		mv.spawn_y = int(off[1]) * SUB
	if raw.has("invuln"):
		var inv: Array = raw["invuln"]
		mv.invuln_from = int(inv[0])
		mv.invuln_to = int(inv[1])
	var classic: String = str(raw.get("classic", ""))
	if classic != "":
		var parts: PackedStringArray = classic.split("+")
		for token: String in parts[0].split(","):
			mv.classic_dirs.append(int(_DIRS.get(token.strip_edges(), 5)))
		var button: String = parts[1].strip_edges() if parts.size() > 1 else "P"
		mv.classic_button = SimConst.PUNCH if button == "P" else SimConst.KICK
	mv.finalize()
