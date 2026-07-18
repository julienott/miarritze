class_name BeachRun
extends ChallengeBase
## Grande Plage — runner latéral (cf. DESIGN.md §4.1).
## Louis court automatiquement ; tap = saut par-dessus les obstacles
## (châteaux de sable, crabes) ; pièces à ramasser. Score = distance + pièces.
## FSM : Run, Jump, Fall, Hit.

const _GROUND_Y: float = 560.0
const _PLAYER_X: float = 250.0
const _PLAYER_SIZE: Vector2 = Vector2(48, 64)
const _SPAWN_X: float = 1400.0

@export var run_speed_start: float = 340.0
@export var run_speed_max: float = 680.0
@export var speed_ramp_per_second: float = 10.0
@export var jump_velocity: float = -950.0
@export var gravity: float = 2300.0
@export var obstacle_interval_min: float = 0.9
@export var obstacle_interval_max: float = 1.7
@export var coin_chance: float = 0.55
@export var hit_stun_duration: float = 1.0
@export var points_per_meter: int = 1
@export var coin_points: int = 20

var _fsm: StateMachine
var _speed: float = 0.0
var _velocity_y: float = 0.0
var _player: ColorRect
var _spawn_countdown: float = 0.0
var _distance_accumulator: float = 0.0
var _obstacles: Array[ColorRect] = []
var _coins: Array[ColorRect] = []


func _on_begin() -> void:
	_speed = run_speed_start
	_player = _make_rect(Vector2(_PLAYER_X, _GROUND_Y - _PLAYER_SIZE.y), _PLAYER_SIZE,
		Color(0.85, 0.25, 0.2))
	_spawn_countdown = 1.2
	_fsm = StateMachine.new(self)
	_fsm.add_state(&"run", RunState.new())
	_fsm.add_state(&"jump", JumpState.new())
	_fsm.add_state(&"fall", FallState.new())
	_fsm.add_state(&"hit", HitState.new())
	_fsm.transition_to(&"run")


func _on_tapped(position: Vector2) -> void:
	_fsm.handle_tap(position)


func _physics_process(delta: float) -> void:
	if not is_running():
		return
	_speed = minf(_speed + speed_ramp_per_second * delta, run_speed_max)
	_fsm.update(delta)
	_scroll_world(delta)
	_check_collisions()


func _scroll_world(delta: float) -> void:
	var step: float = _speed * delta
	if _fsm.current_name != &"hit":
		_distance_accumulator += step
		while _distance_accumulator >= 10.0:
			_distance_accumulator -= 10.0
			add_score(points_per_meter)
	_spawn_countdown -= delta
	if _spawn_countdown <= 0.0:
		_spawn_obstacle()
		_spawn_countdown = randf_range(obstacle_interval_min, obstacle_interval_max)
	for node: ColorRect in _obstacles + _coins:
		node.position.x -= step
	_obstacles = _obstacles.filter(_keep_on_screen)
	_coins = _coins.filter(_keep_on_screen)


func _keep_on_screen(node: ColorRect) -> bool:
	if node.position.x < -120.0:
		node.queue_free()
		return false
	return true


func _spawn_obstacle() -> void:
	# Alterne crabes (bas, rouges) et châteaux de sable (hauts, ocre).
	var is_crab: bool = randf() < 0.5
	var size: Vector2 = Vector2(52, 36) if is_crab else Vector2(64, 84)
	var color: Color = Color(0.9, 0.4, 0.3) if is_crab else Color(0.8, 0.65, 0.35)
	_obstacles.append(_make_rect(Vector2(_SPAWN_X, _GROUND_Y - size.y), size, color))
	if randf() < coin_chance:
		var coin_y: float = _GROUND_Y - randf_range(140.0, 260.0)
		_coins.append(_make_rect(Vector2(_SPAWN_X + 90.0, coin_y), Vector2(26, 26),
			Color(1.0, 0.85, 0.2)))


func _check_collisions() -> void:
	var player_rect: Rect2 = Rect2(_player.position, _PLAYER_SIZE).grow(-6.0)
	for coin: ColorRect in _coins.duplicate():
		if player_rect.intersects(Rect2(coin.position, coin.size)):
			_coins.erase(coin)
			coin.queue_free()
			add_score(coin_points)
			AudioManager.sfx(&"coin")
	if _fsm.current_name == &"hit":
		return
	for obstacle: ColorRect in _obstacles:
		if player_rect.intersects(Rect2(obstacle.position, obstacle.size).grow(-6.0)):
			_fsm.transition_to(&"hit")
			return


func _make_rect(rect_position: Vector2, size: Vector2, color: Color) -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.position = rect_position
	rect.size = size
	rect.color = color
	add_child(rect)
	return rect


func player_bottom() -> float:
	return _player.position.y + _PLAYER_SIZE.y


# --- États ---

class RunState extends State:
	func enter(_previous: StringName) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		run._player.position.y = BeachRun._GROUND_Y - BeachRun._PLAYER_SIZE.y
		run._velocity_y = 0.0

	func handle_tap(_position: Vector2) -> void:
		machine.transition_to(&"jump")


class JumpState extends State:
	func enter(_previous: StringName) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		run._velocity_y = run.jump_velocity
		AudioManager.sfx(&"jump")

	func update(delta: float) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		run._velocity_y += run.gravity * delta
		run._player.position.y += run._velocity_y * delta
		if run._velocity_y >= 0.0:
			machine.transition_to(&"fall")


class FallState extends State:
	func update(delta: float) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		run._velocity_y += run.gravity * delta
		run._player.position.y += run._velocity_y * delta
		if run.player_bottom() >= BeachRun._GROUND_Y:
			machine.transition_to(&"run")


class HitState extends State:
	var _stun_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		_stun_left = run.hit_stun_duration
		run._speed = run.run_speed_start
		run._player.color = Color(0.6, 0.6, 0.6)
		AudioManager.sfx(&"hit")

	func update(delta: float) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		# Retombe au sol pendant l'étourdissement (si touché en l'air).
		if run.player_bottom() < BeachRun._GROUND_Y:
			run._velocity_y += run.gravity * delta
			run._player.position.y += run._velocity_y * delta
		_stun_left -= delta
		if _stun_left <= 0.0:
			run._player.color = Color(0.85, 0.25, 0.2)
			machine.transition_to(&"run")
