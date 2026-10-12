class_name FighterView
extends Node2D
## Vue d'un combattant : sprite indexé + shader de palette. Lit l'état de
## la sim (position, animation, orientation), ne le modifie jamais.

const SHADER: Shader = preload("res://src/fight/view/fighter_palette.gdshader")

var def: FighterDef
var cell: int = 128
var foot: Vector2i = Vector2i(64, 120)
var costume: int = 0

var _sprite: Sprite2D
var _first: PackedInt32Array = []
var _cols: int = 16
var _material: ShaderMaterial
var _shadow: Polygon2D


func setup(p_def: FighterDef, p_costume: int) -> void:
	def = p_def
	costume = p_costume
	var data: Dictionary = FighterDb.load_json(def.id)
	cell = int(data.get("cell", 128))
	var foot_arr: Array = data.get("foot", [64, 120])
	foot = Vector2i(int(foot_arr[0]), int(foot_arr[1]))
	var anims: Dictionary = data.get("anims", {})
	_cols = int(data.get("cols", 16))
	for anim_name: String in SimConst.ANIMS:
		_first.append(int((anims.get(anim_name, {}) as Dictionary).get("first", 0)))
	_shadow = Polygon2D.new()
	var pts: PackedVector2Array = []
	for i: int in 12:
		var a: float = TAU * i / 12.0
		pts.append(Vector2(roundf(cos(a) * 18.0), roundf(sin(a) * 4.0)))
	_shadow.polygon = pts
	_shadow.color = Color(0.23, 0.15, 0.2, 0.35)
	_shadow.top_level = true
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.texture = load("res://assets/fighters/%s/sheet.png" % def.id)
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("palette", load("res://assets/fighters/%s/palettes.png" % def.id))
	_material.set_shader_parameter("costume", costume)
	_sprite.material = _material
	add_child(_sprite)


func sync(me: FighterState) -> void:
	position = Vector2(roundi(me.x / 256.0), roundi(me.y / 256.0))
	# Ombre au sol : lit la hauteur des sauts et des envols.
	var height: float = (SimConst.GROUND_Y - me.y) / 256.0
	_shadow.global_position = Vector2(position.x, SimConst.GROUND_Y / 256.0)
	_shadow.scale = Vector2.ONE * clampf(1.0 - height / 160.0, 0.45, 1.0)
	_shadow.z_index = z_index - 5
	var frame: int = MoveRunner.anim_frame(def, me)
	# Marche arrière : lecture inversée de la marche.
	if me.anim == SimConst.A_WALK and me.vx * me.facing < 0:
		frame = def.anim_frames[me.anim] - 1 - frame
	var first: int = _first[me.anim] if me.anim >= 0 and me.anim < _first.size() else 0
	var k: int = first + frame
	_sprite.region_rect = Rect2((k % _cols) * cell, (k / _cols) * cell, cell, cell)
	var flip: bool = me.facing < 0
	_sprite.flip_h = flip
	_sprite.position = Vector2(-(cell - foot.x) if flip else -foot.x, -foot.y)
	_material.set_shader_parameter("flash", 0.6 if me.hit_flash > 0 else 0.0)


func set_silhouette(on: bool) -> void:
	_material.set_shader_parameter("silhouette", 1.0 if on else 0.0)
