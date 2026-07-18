class_name Espadrille
extends ChallengeBase
## Port Vieux — lancer d'espadrille façon Angry Birds (cf. DESIGN.md §4.5).
## Glisser = viser/doser (trajectoire prévisualisée), relâcher = lancer.
## Cibles : boîtes de conserve, bouées, mouettes chapardeuses (mobiles).
## FSM : Aim, Charge, Throw, Resolve.

const _LAUNCH_POS: Vector2 = Vector2(118.0, 452.0)

@export var throws_total: int = 5
@export var power_scale: float = 3.4
@export var power_max: float = 1500.0
@export var gravity: float = 1400.0
@export var box_points: int = 10
@export var buoy_points: int = 20
@export var gull_points: int = 40
@export var combo_multiplier: int = 2

var _fsm: StateMachine
var _player: LouisSprite
var _projectile: Sprite2D
var _preview: Line2D
var _throws_left_label: Label
var _throws_left: int = 0
var _velocity: Vector2 = Vector2.ZERO
var _drag_vector: Vector2 = Vector2.ZERO
var _hits_this_throw: int = 0
var _targets: Array[Dictionary] = []


func _on_begin() -> void:
	_throws_left = throws_total

	_player = LouisSprite.new()
	_player.position = Vector2(60.0, 508.0 - LouisSprite.FEET_Y)
	add_child(_player)
	_player.play(&"idle")

	_projectile = SpriteUtil.sprite("espadrille_shoe")
	_projectile.position = _LAUNCH_POS
	add_child(_projectile)

	_preview = Line2D.new()
	_preview.width = 5.0
	_preview.default_color = Color(0.97, 0.95, 0.89, 0.65)
	add_child(_preview)

	_throws_left_label = Label.new()
	_throws_left_label.add_theme_font_size_override(&"font_size", 22)
	_throws_left_label.position = Vector2(24.0, 96.0)
	add_child(_throws_left_label)

	_spawn_targets()

	_fsm = StateMachine.new(self)
	_fsm.add_state(&"aim", AimState.new())
	_fsm.add_state(&"charge", ChargeState.new())
	_fsm.add_state(&"throw", ThrowState.new())
	_fsm.add_state(&"resolve", ResolveState.new())
	_fsm.transition_to(&"aim")


func _spawn_targets() -> void:
	# pile de boîtes de conserve sur des caisses (droite)
	for i: int in 3:
		for j: int in (3 - i):
			_add_target("can", Vector2(920.0 + j * 44.0 + i * 22.0, 560.0 - i * 40.0),
				box_points, Vector2.ZERO)
	# bouées dans l'eau
	_add_target("buoy", Vector2(690.0, 566.0), buoy_points, Vector2.ZERO)
	_add_target("buoy", Vector2(1140.0, 572.0), buoy_points, Vector2.ZERO)
	# mouettes chapardeuses
	_add_target("gull", Vector2(820.0, 210.0), gull_points, Vector2(120.0, 0.0))
	_add_target("gull", Vector2(1050.0, 120.0), gull_points, Vector2(-90.0, 0.0))


func _add_target(kind: String, target_position: Vector2, points: int, velocity: Vector2) -> void:
	var node: Node2D
	if kind == "gull":
		node = SpriteUtil.animated(["gull_1", "gull_2"], 6.0)
	else:
		node = SpriteUtil.sprite(kind)
	node.position = target_position
	add_child(node)
	_targets.append({"node": node, "points": points, "velocity": velocity})


func _physics_process(delta: float) -> void:
	if not is_running():
		return
	_fsm.update(delta)
	_move_gulls(delta)
	_throws_left_label.text = "Espadrilles : %d" % _throws_left


func _move_gulls(delta: float) -> void:
	for target: Dictionary in _targets:
		var velocity: Vector2 = target["velocity"]
		if velocity == Vector2.ZERO:
			continue
		var node: Node2D = target["node"]
		node.position += velocity * delta
		if node is AnimatedSprite2D:
			(node as AnimatedSprite2D).flip_h = velocity.x < 0.0
		if node.position.x < 600.0 or node.position.x > 1220.0:
			target["velocity"] = -velocity


func _on_drag_started(position: Vector2) -> void:
	_fsm.handle_tap(position)


func _on_drag_updated(_position: Vector2, vector: Vector2) -> void:
	if _fsm.current_name == &"charge":
		_drag_vector = vector
		_update_preview()


func _on_drag_ended(_position: Vector2, vector: Vector2) -> void:
	if _fsm.current_name == &"charge":
		_drag_vector = vector
		_fsm.transition_to(&"throw")


func launch_velocity() -> Vector2:
	var velocity: Vector2 = -_drag_vector * power_scale
	return velocity.limit_length(power_max)


func _update_preview() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var pos: Vector2 = _LAUNCH_POS
	var vel: Vector2 = launch_velocity()
	var step: float = 0.05
	for i: int in 22:
		points.append(pos)
		vel.y += gravity * step
		pos += vel * step
		if pos.y > 700.0:
			break
	_preview.points = points


func check_hits() -> void:
	var projectile_rect: Rect2 = Rect2(_projectile.position, SpriteUtil.display_size(_projectile))
	for target: Dictionary in _targets.duplicate():
		var node: Node2D = target["node"]
		if projectile_rect.intersects(Rect2(node.position, SpriteUtil.display_size(node))):
			_hits_this_throw += 1
			var points: int = target["points"]
			if _hits_this_throw >= 2:
				points *= combo_multiplier
			add_score(points)
			_targets.erase(target)
			node.queue_free()
			AudioManager.sfx(&"impact")


func maybe_finish() -> void:
	if _throws_left <= 0 or _targets.is_empty():
		end()


# --- États ---

class AimState extends State:
	func enter(_previous: StringName) -> void:
		var espadrille: Espadrille = machine.owner_node as Espadrille
		espadrille._projectile.position = Espadrille._LAUNCH_POS
		espadrille._projectile.rotation = 0.0
		espadrille._projectile.visible = true
		espadrille._preview.points = PackedVector2Array()
		espadrille._hits_this_throw = 0
		espadrille._player.play(&"idle")

	func handle_tap(_position: Vector2) -> void:
		machine.transition_to(&"charge")


class ChargeState extends State:
	func enter(_previous: StringName) -> void:
		var espadrille: Espadrille = machine.owner_node as Espadrille
		espadrille._drag_vector = Vector2.ZERO
		espadrille._player.play(&"throw")
		espadrille._player.pause()   # bras armé tant qu'on vise


class ThrowState extends State:
	func enter(_previous: StringName) -> void:
		var espadrille: Espadrille = machine.owner_node as Espadrille
		espadrille._velocity = espadrille.launch_velocity()
		espadrille._preview.points = PackedVector2Array()
		espadrille._throws_left -= 1
		espadrille._player.play(&"throw")
		AudioManager.sfx(&"throw")

	func update(delta: float) -> void:
		var espadrille: Espadrille = machine.owner_node as Espadrille
		espadrille._velocity.y += espadrille.gravity * delta
		espadrille._projectile.position += espadrille._velocity * delta
		espadrille._projectile.rotation += 8.0 * delta
		espadrille.check_hits()
		var pos: Vector2 = espadrille._projectile.position
		if pos.y > 740.0 or pos.x > 1320.0 or pos.x < -40.0:
			machine.transition_to(&"resolve")


class ResolveState extends State:
	var _time_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var espadrille: Espadrille = machine.owner_node as Espadrille
		espadrille._projectile.visible = false
		_time_left = 0.6

	func update(delta: float) -> void:
		var espadrille: Espadrille = machine.owner_node as Espadrille
		_time_left -= delta
		if _time_left <= 0.0:
			espadrille.maybe_finish()
			if espadrille.is_running():
				machine.transition_to(&"aim")
