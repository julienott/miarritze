class_name MoveFx
extends Node2D
## Effets des coups spéciaux, lus sur l'état de la sim (lecture seule) :
## sprite assets/vfx/<perso>/<coup>.png s'il existe, animé selon l'avancement
## du coup (move_t / startup / active). Deux calques : derrière les persos
## (halo, super) et devant (traînée, écume).

## Effets dessinés derrière les combattants.
const BACK: PackedStringArray = ["sp_up", "super"]

var sim: FightSim
var defs: Array[FighterDef] = []
var back: bool = false
var _tex: Dictionary = {}


func _ready() -> void:
	z_index = 8 if back else 19


func _physics_process(_delta: float) -> void:
	queue_redraw()


func texture(fid: String, fx: String) -> Texture2D:
	var key: String = fid + "/" + fx
	if not _tex.has(key):
		var path: String = "res://assets/vfx/%s/%s.png" % [fid, fx]
		_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _tex[key]


func _draw() -> void:
	if sim == null:
		return
	for i: int in sim.f.size():
		var me: FighterState = sim.f[i]
		if me.state != SimConst.ST_MOVE or me.move < 0:
			continue
		var def: FighterDef = defs[i]
		var md: MoveDef = def.moves[me.move]
		if (md.name in BACK) != back:
			continue
		var p: Vector2 = Vector2(roundi(me.x / 256.0), roundi(me.y / 256.0))
		var t: int = me.move_t
		var on: int = t - md.startup
		var f: float = float(me.facing)
		match md.name:
			"sp_forward":
				_trail(def.id, p, f, t, md)
			"sp_down":
				_foam(def.id, p, f, on, md)
			"sp_up":
				# Colonne de lumière du Saut du Phare : propre à Louis.
				if def.id == "louis":
					_beam(p, on, md)
			"super":
				_burst(def.id, p, t, md)


## Traînée de vitesse derrière le perso pendant la charge.
func _trail(fid: String, p: Vector2, f: float, t: int, md: MoveDef) -> void:
	var tex: Texture2D = texture(fid, "sp_forward")
	if tex == null or t < md.startup - 2 or t > md.startup + md.active + 4:
		return
	var fade: float = clampf(1.0 - float(t - md.startup - md.active) / 5.0, 0.0, 1.0)
	for k: int in 3:
		var y: float = p.y - 78.0 + k * 16.0
		var x: float = p.x - f * (34.0 + k * 6.0)
		var w: float = tex.get_width() * (1.0 - k * 0.2)
		var rect: Rect2 = Rect2(Vector2(x - (w if f > 0 else 0.0), y), Vector2(w, tex.get_height()))
		if f < 0:
			rect = Rect2(rect.position + Vector2(rect.size.x, 0), Vector2(-rect.size.x, rect.size.y))
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, fade * (1.0 - k * 0.25)))


## Croissant d'écume qui balaie le sol devant le perso.
func _foam(fid: String, p: Vector2, f: float, on: int, md: MoveDef) -> void:
	var tex: Texture2D = texture(fid, "sp_down")
	if tex == null or on < 0 or on > md.active + 6:
		return
	var k: float = clampf(float(on) / float(maxi(md.active, 1)), 0.0, 1.0)
	var s: float = 1.4 + 0.8 * k
	var a: float = clampf(1.0 - float(on - md.active) / 6.0, 0.0, 1.0)
	var size: Vector2 = Vector2(tex.get_width(), tex.get_height()) * s
	var x: float = p.x + f * (30.0 + 30.0 * k)
	var rect: Rect2 = Rect2(Vector2(x - size.x * 0.5, p.y - size.y), size)
	if f < 0:
		rect = Rect2(rect.position + Vector2(size.x, 0), Vector2(-size.x, size.y))
	draw_texture_rect(tex, rect.abs() if f > 0 else rect, false, Color(1, 1, 1, a))


## Saut du Phare : colonne de lumière dorée qui monte avec le perso.
func _beam(p: Vector2, on: int, md: MoveDef) -> void:
	if on < -2 or on > md.active + 10:
		return
	var a: float = clampf(1.0 - float(on - md.active) / 10.0, 0.0, 1.0)
	var top: float = p.y - 150.0 - mini(on, 10) * 6.0
	draw_rect(Rect2(p.x - 14, top, 28, p.y - top), Color(1.0, 0.82, 0.3, 0.45 * a))
	draw_rect(Rect2(p.x - 7, top, 14, p.y - top), Color(1.0, 0.97, 0.75, 0.75 * a))
	for k: int in 6:
		var sx: float = p.x + float(((k * 37 + on * 5) % 30) - 15)
		var sy: float = p.y - float(((k * 53 + on * 9) % 150))
		draw_rect(Rect2(Vector2(sx, sy).round(), Vector2(2, 2)), Color(1, 1, 1, a))


## Coup du Txapeldun : soleil au lauburu qui éclot derrière le perso.
func _burst(fid: String, p: Vector2, t: int, md: MoveDef) -> void:
	var tex: Texture2D = texture(fid, "super")
	if tex == null:
		return
	var end: int = md.startup + md.active
	if t > end + 8:
		return
	var s: float = minf(1.5, 0.5 + float(t) / 6.0)
	s = roundf(s * 2.0) / 2.0
	var a: float = clampf(1.0 - float(t - end) / 8.0, 0.0, 1.0)
	var size: Vector2 = Vector2(tex.get_width(), tex.get_height()) * s
	draw_texture_rect(tex, Rect2(Vector2(p.x, p.y - 70.0) - size * 0.5, size), false, Color(1, 1, 1, a))
