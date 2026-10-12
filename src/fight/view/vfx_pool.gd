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


## Projectiles procéduraux (en attendant leurs sprites) : forme par nom.
func _draw_projectile(pr: ProjectileState) -> void:
	var pd: ProjectileDef = defs[pr.owner].projectiles[pr.def]
	var p: Vector2 = Vector2(roundi(pr.x / 256.0), roundi(pr.y / 256.0))
	var hb: PackedInt32Array = pd.hitbox
	var w: float = hb[2] / 256.0
	var h: float = hb[3] / 256.0
	var spin: int = (pr.age / 3) % 4
	match pd.name:
		"espadrille":
			var rect: Rect2 = Rect2(p - Vector2(7, 3), Vector2(14, 6)) if spin % 2 == 0 \
				else Rect2(p - Vector2(3, 7), Vector2(6, 14))
			draw_rect(rect.grow(1), C_OUTLINE)
			draw_rect(rect, C_LINEN)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)) if spin % 2 == 0
				else Rect2(rect.position, Vector2(2, rect.size.y)), C_SAND)
		_:
			var r: Rect2 = Rect2(p + Vector2(hb[0] / 256.0, hb[1] / 256.0), Vector2(w, h))
			draw_rect(r.grow(1), C_OUTLINE)
			draw_rect(r, C_SEA if pd.ground else C_GOLD)
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), C_FOAM)
