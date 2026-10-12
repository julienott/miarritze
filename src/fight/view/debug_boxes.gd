class_name DebugBoxes
extends Node2D
## Visualiseur F3 (SPEC §11.6) : hit en rouge, hurt en vert, push en bleu,
## plus la frame data du coup en cours.

var sim: FightSim
var _font: Font


func _ready() -> void:
	z_index = 50
	visible = false
	_font = load("res://assets/fonts/press_start_2p.ttf")


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	for p: int in 2:
		var def: FighterDef = sim.defs[p]
		var me: FighterState = sim.f[p]
		for box: PackedInt32Array in MoveRunner.hurtboxes(def, me):
			_box(box, Color(0.2, 0.9, 0.3, 0.35), Color(0.2, 0.9, 0.3))
		for box: PackedInt32Array in MoveRunner.hitboxes(def, me):
			_box(box, Color(0.95, 0.15, 0.15, 0.45), Color(1, 0.2, 0.2))
		var push: PackedInt32Array = PackedInt32Array([me.x - def.push_w, me.y - def.push_h, def.push_w * 2, def.push_h])
		_box(push, Color(0, 0, 0, 0), Color(0.3, 0.5, 1.0))
		var info: String = SimConst.ANIMS[me.anim] if me.anim >= 0 else "?"
		if me.state == SimConst.ST_MOVE and me.move >= 0:
			var mv: MoveDef = def.moves[me.move]
			info = "%s %d/%d s%d a%d r%d" % [mv.name, me.move_t, mv.total, mv.startup, mv.active, mv.recovery]
		draw_string(_font, Vector2(me.x / 256.0 - 30, me.y / 256.0 + 12), info,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	for pr: ProjectileState in sim.projectiles:
		var pd: ProjectileDef = sim.defs[pr.src].projectiles[pr.def]
		_box(Collision.world(pd.hitbox, pr.x, pr.y, pr.facing), Color(0.95, 0.15, 0.15, 0.45), Color(1, 0.2, 0.2))


func _box(b: PackedInt32Array, fill: Color, line: Color) -> void:
	var r: Rect2 = Rect2(b[0] / 256.0, b[1] / 256.0, b[2] / 256.0, b[3] / 256.0)
	if fill.a > 0.0:
		draw_rect(r, fill)
	draw_rect(r, line, false, 1.0)
