class_name BeachRun
extends ChallengeBase
## Grande Plage — runner latéral (cf. DESIGN.md §4.1).
## Louis court automatiquement ; tap = saut par-dessus les obstacles
## (châteaux de sable, crabes) ; pièces à ramasser. Score = distance + pièces.
## FSM : Run, Jump, Fall, Hit.

const _GROUND_Y: float = 620.0
const _PLAYER_X: float = 250.0
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
var _player: LouisSprite
var _gull: AnimatedSprite2D
var _spawn_countdown: float = 0.0
var _distance_accumulator: float = 0.0
var _obstacles: Array[Node2D] = []
var _coins: Array[Node2D] = []


func _on_begin() -> void:
	_speed = run_speed_start
	_player = LouisSprite.new()
	_player.position = Vector2(_PLAYER_X, _GROUND_Y - LouisSprite.FEET_Y)
	add_child(_player)
	_player.play(&"run")
	# une mouette passe dans le ciel pour la vie du décor
	_gull = SpriteUtil.animated(["gull_1", "gull_2"], 5.0)
	_gull.position = Vector2(1400.0, 120.0)
	add_child(_gull)
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
	_gull.position.x -= 90.0 * delta
	if _gull.position.x < -80.0:
		_gull.position = Vector2(1400.0, randf_range(60.0, 220.0))


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
	for node: Node2D in _obstacles + _coins:
		node.position.x -= step
	_obstacles = _obstacles.filter(_keep_on_screen)
	_coins = _coins.filter(_keep_on_screen)


func _keep_on_screen(node: Node2D) -> bool:
	if node.position.x < -120.0:
		node.queue_free()
		return false
	return true


func _spawn_obstacle() -> void:
	var node: Node2D
	if randf() < 0.5:
		node = SpriteUtil.animated(["crab", "crab_2"], 6.0)
	else:
		node = SpriteUtil.sprite("sandcastle")
	var size: Vector2 = SpriteUtil.display_size(node)
	node.position = Vector2(_SPAWN_X, _GROUND_Y - size.y)
	add_child(node)
	_obstacles.append(node)
	if randf() < coin_chance:
		var coin: AnimatedSprite2D = SpriteUtil.animated(["coin", "coin_2", "coin_3", "coin_2"], 8.0)
		coin.position = Vector2(_SPAWN_X + 90.0, _GROUND_Y - randf_range(190.0, 330.0))
		add_child(coin)
		_coins.append(coin)


func _player_rect() -> Rect2:
	# corps utile de la frame 64x96 (marges transparentes exclues)
	return Rect2(_player.position + Vector2(14.0, 10.0), Vector2(36.0, 76.0))


func _check_collisions() -> void:
	var player_rect: Rect2 = _player_rect()
	for coin: Node2D in _coins.duplicate():
		if player_rect.intersects(Rect2(coin.position, SpriteUtil.display_size(coin))):
			_coins.erase(coin)
			coin.queue_free()
			add_score(coin_points)
			AudioManager.sfx(&"coin")
	if _fsm.current_name == &"hit":
		return
	for obstacle: Node2D in _obstacles:
		var rect: Rect2 = Rect2(obstacle.position, SpriteUtil.display_size(obstacle)).grow(-10.0)
		if player_rect.intersects(rect):
			_fsm.transition_to(&"hit")
			return


func player_feet() -> float:
	return _player.position.y + LouisSprite.FEET_Y


# --- États ---

class RunState extends State:
	func enter(_previous: StringName) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		run._player.position.y = BeachRun._GROUND_Y - LouisSprite.FEET_Y
		run._velocity_y = 0.0
		run._player.play(&"run")

	func handle_tap(_position: Vector2) -> void:
		machine.transition_to(&"jump")


class JumpState extends State:
	func enter(_previous: StringName) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		run._velocity_y = run.jump_velocity
		run._player.play(&"jump")
		AudioManager.sfx(&"jump")

	func update(delta: float) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		run._velocity_y += run.gravity * delta
		run._player.position.y += run._velocity_y * delta
		if run._velocity_y >= 0.0:
			machine.transition_to(&"fall")


class FallState extends State:
	func enter(_previous: StringName) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		run._player.play(&"fall")

	func update(delta: float) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		run._velocity_y += run.gravity * delta
		run._player.position.y += run._velocity_y * delta
		if run.player_feet() >= BeachRun._GROUND_Y:
			machine.transition_to(&"run")


class HitState extends State:
	var _stun_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		_stun_left = run.hit_stun_duration
		run._speed = run.run_speed_start
		run._player.play(&"hit")
		run._player.modulate = Color(1, 1, 1, 0.6)
		AudioManager.sfx(&"hit")

	func update(delta: float) -> void:
		var run: BeachRun = machine.owner_node as BeachRun
		if run.player_feet() < BeachRun._GROUND_Y:
			run._velocity_y += run.gravity * delta
			run._player.position.y += run._velocity_y * delta
		_stun_left -= delta
		if _stun_left <= 0.0:
			run._player.modulate = Color.WHITE
			machine.transition_to(&"run")
