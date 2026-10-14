class_name VfxPool
extends Node2D
## Effets visuels procéduraux (monde) : étincelles en étoile, poussière,
## onomatopées « PAF ! » / « TXAK ! », éclaboussures, projectiles.
## Purement visuel : alimenté par les événements de la sim.

const C_LINEN: Color = Color8(247, 241, 227)
const C_GOLD: Color = Color8(244, 198, 62)
const C_RED: Color = Color8(206, 52, 52)
const C_OUTLINE: Color = Color8(58, 38, 52)
const C_FOAM: Color = Color8(196, 232, 230)
const C_SEA: Color = Color8(64, 180, 188)
const C_SAND: Color = Color8(214, 168, 96)
const C_BLUE: Color = Color8(84, 112, 168)

const WORDS_LIGHT: PackedStringArray = ["PAF!", "TOC!", "PIF!"]
const WORDS_HEAVY: PackedStringArray = ["TXAK!", "BAM!", "PATAF!"]

var sim: FightSim
var defs: Array[FighterDef] = []
var particles: String = "sand"
var _fx: Array[Dictionary] = []
var _font: Font
var _word_i: int = 0


func _ready() -> void:
	_font = load("res://assets/fonts/press_start_2p.ttf")
	z_index = 20


func spark(pos: Vector2, strength: int) -> void:
	_fx.append({"k": "spark", "p": pos, "t": 0, "life": 10 + strength * 3, "s": strength})
	if strength >= 1:
		var words: PackedStringArray = WORDS_HEAVY if strength >= 1 else WORDS_LIGHT
		_word_i = (_word_i + 1) % words.size()
		_fx.append({"k": "word", "p": pos + Vector2(0, -18), "t": 0, "life": 30,
			"w": words[_word_i], "s": strength})


func block(pos: Vector2) -> void:
	_fx.append({"k": "block", "p": pos, "t": 0, "life": 10})


func dust(pos: Vector2, big: bool = false) -> void:
	_fx.append({"k": "dust", "p": pos, "t": 0, "life": 18 if big else 12, "s": 1 if big else 0})


func word(pos: Vector2, text: String, color: Color = C_GOLD) -> void:
	_fx.append({"k": "word", "p": pos, "t": 0, "life": 40, "w": text, "s": 0, "c": color})


func _physics_process(_delta: float) -> void:
	var keep: Array[Dictionary] = []
	for fx: Dictionary in _fx:
		fx["t"] = int(fx["t"]) + 1
		if int(fx["t"]) < int(fx["life"]):
			keep.append(fx)
	_fx = keep
	queue_redraw()


func _draw() -> void:
	if sim != null:
		for pr: ProjectileState in sim.projectiles:
			_draw_projectile(pr)
	for fx: Dictionary in _fx:
		var p: Vector2 = (fx["p"] as Vector2).round()
		var t: int = fx["t"]
		var life: int = fx["life"]
		match String(fx["k"]):
			"spark":
				var s: int = fx["s"]
				var r: float = (6.0 + s * 4.0) * (1.0 - float(t) / life) + 2.0
				for k: int in 8:
					var a: float = k * PI / 4.0 + (0.4 if t % 2 == 0 else 0.0)
					var len: float = r if k % 2 == 0 else r * 0.5
					var end: Vector2 = (p + Vector2(cos(a), sin(a)) * len).round()
					draw_line(p, end, C_GOLD if t < 3 else C_LINEN, 2.0 if s >= 2 else 1.0)
				if t < 3:
					draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), C_LINEN)
			"block":
				var rr: float = 4.0 + t
				draw_arc(p, rr, -PI * 0.5, PI * 0.5, 6, C_BLUE, 2.0)
			"dust":
				for k: int in 4:
					var dx: float = (k - 1.5) * (3.0 + t * 0.8)
					var dy: float = -t * 0.4 - (k % 2) * 2.0
					var rad: float = maxf(1.0, 3.0 - t * 0.15)
					draw_rect(Rect2((p + Vector2(dx, dy)).round(), Vector2(rad, rad)), _particle_color())
			"word":
				var text: String = fx["w"]
				var col: Color = fx.get("c", C_GOLD if int(fx["s"]) < 2 else C_RED)
				var sz: int = 8 if int(fx["s"]) < 2 else 16
				var off: Vector2 = Vector2(-_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x * 0.5,
					-mini(t, 6))
				for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
					draw_string(_font, p + off + d, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, C_OUTLINE)
				draw_string(_font, p + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _particle_color() -> Color:
	match particles:
		"water":
			return C_FOAM
		"flour":
			return C_LINEN
		"wood":
			return Color8(150, 104, 62)
	return C_SAND


## Projectiles et pièges procéduraux : une forme lisible par nom (SPEC §11.1).
func _draw_projectile(pr: ProjectileState) -> void:
	var pd: ProjectileDef = defs[pr.src].projectiles[pr.def]
	var p: Vector2 = Vector2(roundi(pr.x / 256.0), roundi(pr.y / 256.0))
	var f: float = float(pr.facing)
	var spin: int = (pr.age / 3) % 4
	var tex: Texture2D = _proj_texture(defs[pr.src].id, pd.name)
	if tex != null:
		# Sprite RD : quart de tour toutes les 3 frames (pixels nets).
		draw_set_transform(p, spin * PI * 0.5 * f, Vector2(f, 1.0))
		draw_texture(tex, -Vector2(tex.get_width(), tex.get_height()) * 0.5)
		draw_set_transform(Vector2.ZERO)
		return
	match pd.name:
		"espadrille":
			var rect: Rect2 = Rect2(p - Vector2(7, 3), Vector2(14, 6)) if spin % 2 == 0 else Rect2(p - Vector2(3, 7), Vector2(6, 14))
			draw_rect(rect.grow(1), C_OUTLINE)
			draw_rect(rect, C_LINEN)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)) if spin % 2 == 0 else Rect2(rect.position, Vector2(2, rect.size.y)), C_SAND)
		"pelote", "rasante", "rebond", "cloche":
			draw_circle(p, 5, C_OUTLINE)
			draw_circle(p, 4, C_LINEN)
			draw_arc(p, 3, spin * 0.8, spin * 0.8 + 2.4, 6, C_RED, 1.0)
			draw_line(p - Vector2(10 * f, 0), p - Vector2(5 * f, 0), Color(C_LINEN, 0.5), 1.0)
		"sardines":
			for k: int in 3:
				_fish(p + Vector2(0, (k - 1) * 7), f)
		"hamecon":
			var owner: FighterState = sim.f[pr.owner]
			draw_line(Vector2(owner.x / 256.0, owner.y / 256.0 - 70), p, Color8(108, 72, 46), 1.0)
			draw_arc(p + Vector2(0, 2), 3, 0, PI, 6, C_OUTLINE, 2.0)
		"filet":
			var r: Rect2 = Rect2(p - Vector2(11, 14), Vector2(22, 28))
			for k: int in 5:
				draw_line(Vector2(r.position.x + k * 5.5, r.position.y), Vector2(r.position.x + k * 5.5, r.end.y), Color8(150, 104, 62), 1.0)
				draw_line(Vector2(r.position.x, r.position.y + k * 7), Vector2(r.end.x, r.position.y + k * 7), Color8(150, 104, 62), 1.0)
		"pierre":
			draw_circle(p, 10, C_OUTLINE)
			draw_circle(p, 9, Color8(140, 150, 162))
			draw_rect(Rect2(p + Vector2(-4, -5), Vector2(3, 2)), Color8(200, 208, 214))
		"onde":
			for k: int in 3:
				draw_arc(p + Vector2(0, 0), 6 + k * 3, PI, TAU, 8, Color(C_SAND, 0.9 - k * 0.25), 2.0)
		"fiente":
			draw_circle(p, 4, C_OUTLINE)
			draw_circle(p, 3, C_LINEN)
		"bulles":
			draw_arc(p, 9, 0, TAU, 12, C_FOAM, 2.0)
			draw_rect(Rect2(p + Vector2(-4, -5), Vector2(2, 2)), C_LINEN)
		"gateau":
			draw_rect(Rect2(p + Vector2(-11, -7), Vector2(22, 7)), C_OUTLINE)
			draw_rect(Rect2(p + Vector2(-10, -6), Vector2(20, 5)), Color8(222, 176, 82))
			draw_rect(Rect2(p + Vector2(-10, -6), Vector2(20, 1)), Color8(160, 112, 50))
		"perle":
			draw_circle(p, 6, Color(C_FOAM, 0.6))
			draw_circle(p, 4, C_LINEN)
			draw_rect(Rect2(p + Vector2(-2, -3), Vector2(1, 1)), Color.WHITE)
		"flaque":
			draw_rect(Rect2(p + Vector2(-16, -3), Vector2(32, 3)), Color(C_SEA, 0.85))
			draw_rect(Rect2(p + Vector2(-12, -4), Vector2(24, 1)), C_FOAM)
		"ballon":
			var rr: Rect2 = Rect2(p - Vector2(8, 5), Vector2(16, 10))
			draw_rect(rr.grow(1), C_OUTLINE)
			draw_rect(rr, Color8(140, 96, 60))
			draw_line(p - Vector2(4, 0), p + Vector2(4, 0), C_LINEN, 1.0)
		"faisceau":
			draw_rect(Rect2(p + Vector2(-40, -5), Vector2(80, 10)), Color(1.0, 0.95, 0.6, 0.55))
			draw_rect(Rect2(p + Vector2(-40, -2), Vector2(80, 4)), Color(1.0, 1.0, 0.9, 0.9))
		"bouee":
			draw_arc(p, 8, 0, TAU, 14, C_OUTLINE, 5.0)
			draw_arc(p, 8, 0, TAU, 14, Color8(238, 140, 58), 3.0)
			for k: int in 4:
				var a: float = k * PI * 0.5 + pr.age * 0.2
				draw_rect(Rect2(p + Vector2(cos(a), sin(a)) * 8 - Vector2(1, 1), Vector2(2, 2)), C_LINEN)
		"pavillon":
			draw_rect(Rect2(p + Vector2(-1, -58), Vector2(2, 58)), C_OUTLINE)
			var wave: float = sin(pr.age * 0.2) * 2.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(1, -58), p + Vector2(18, -52 + wave), p + Vector2(1, -46)]), C_RED)
			draw_rect(Rect2(p + Vector2(-24, -1), Vector2(48, 1)), Color(C_RED, 0.35))
		"rouleau":
			draw_arc(p + Vector2(0, -2), 8, PI * 0.9, TAU, 10, C_SEA, 4.0)
			draw_arc(p + Vector2(0, -2), 8, PI * 1.1, PI * 1.6, 6, C_FOAM, 2.0)
		_:
			var hb: PackedInt32Array = pd.hitbox
			var r2: Rect2 = Rect2(p + Vector2(hb[0] / 256.0, hb[1] / 256.0), Vector2(hb[2] / 256.0, hb[3] / 256.0))
			draw_rect(r2.grow(1), C_OUTLINE)
			draw_rect(r2, C_GOLD)


var _proj_tex: Dictionary = {}


func _proj_texture(fid: String, proj: String) -> Texture2D:
	var key: String = fid + "/" + proj
	if not _proj_tex.has(key):
		var path: String = "res://assets/vfx/%s/proj_%s.png" % [fid, proj]
		_proj_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _proj_tex[key]


func _fish(p: Vector2, f: float) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(-6 * f, 0), p + Vector2(0, -3), p + Vector2(6 * f, 0), p + Vector2(0, 3)]), Color8(140, 150, 162))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-6 * f, 0), p + Vector2(-10 * f, -3), p + Vector2(-10 * f, 3)]), Color8(92, 100, 116))
	draw_rect(Rect2(p + Vector2(3 * f - 0.5, -1), Vector2(1, 1)), C_OUTLINE)
