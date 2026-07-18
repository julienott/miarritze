class_name Lighthouse
extends ChallengeBase
## Phare — ascension-plateforme verticale (cf. DESIGN.md §4.6).
## Louis marche automatiquement sur chaque palier ; tap = saut vers le
## palier suivant. Au sommet : la salle des trophées et un bonus.
## FSM : Climb, Jump, Fall, Reach.

const _PLATFORM_W: float = 112.0
const _LEFT_X: float = 440.0
const _RIGHT_X: float = 840.0
const _BASE_Y: float = 640.0
const _STEP_Y: float = 150.0

@export var platform_count: int = 25
@export var walk_speed: float = 240.0
@export var jump_velocity: float = -880.0
@export var jump_horizontal_speed: float = 320.0
@export var gravity: float = 2100.0
@export var platform_points: int = 15
@export var summit_points: int = 200

var _fsm: StateMachine
var _player: LouisSprite
var _camera: Camera2D
var _current_level: int = 0
var _walk_direction: float = 1.0
var _velocity: Vector2 = Vector2.ZERO
var _trophy_layer: CanvasLayer = null
var _trophy_rows: VBoxContainer = null
var _trophy_status: Label = null


func _on_begin() -> void:
	# décor : la tour (image haute), calée pour que le sol touche le bas
	var bg: Sprite2D = SpriteUtil.sprite("bg_lighthouse")
	bg.position = Vector2(0.0, 720.0 - 1100.0 * 4.0)
	bg.z_index = -10
	add_child(bg)
	move_child(bg, 0)

	for i: int in platform_count:
		var ledge: Sprite2D = SpriteUtil.sprite("ledge")
		ledge.position = Vector2(_platform_x(i) - _PLATFORM_W * 0.5, _level_y(i))
		add_child(ledge)

	_player = LouisSprite.new()
	add_child(_player)
	_place_on_level(0)
	_player.play(&"climb")

	_camera = Camera2D.new()
	_camera.position = Vector2(640.0, 400.0)
	add_child(_camera)
	_camera.make_current()

	_fsm = StateMachine.new(self)
	_fsm.add_state(&"climb", ClimbState.new())
	_fsm.add_state(&"jump", JumpState.new())
	_fsm.add_state(&"fall", FallState.new())
	_fsm.add_state(&"reach", ReachState.new())
	_fsm.transition_to(&"climb")


func _on_tapped(position: Vector2) -> void:
	_fsm.handle_tap(position)


func _physics_process(delta: float) -> void:
	if not is_running():
		return
	_fsm.update(delta)
	var target_y: float = minf(_player.position.y - 160.0, 400.0)
	_camera.position.y = lerpf(_camera.position.y, target_y, 6.0 * delta)


func _platform_x(level: int) -> float:
	return _LEFT_X if level % 2 == 0 else _RIGHT_X


func _level_y(level: int) -> float:
	return _BASE_Y - level * _STEP_Y


func _place_on_level(level: int) -> void:
	_current_level = level
	_player.position = Vector2(_platform_x(level) - 32.0, _level_y(level) - LouisSprite.FEET_Y)


func player_feet() -> float:
	return _player.position.y + LouisSprite.FEET_Y


func player_center_x() -> float:
	return _player.position.x + 32.0


func landing_level() -> int:
	var feet: float = player_feet()
	var center_x: float = player_center_x()
	for level: int in range(platform_count - 1, -1, -1):
		var top: float = _level_y(level)
		if feet >= top and feet <= top + 40.0:
			if absf(center_x - _platform_x(level)) <= _PLATFORM_W * 0.5 + 10.0:
				return level
	return -1


func show_trophy_room() -> void:
	_trophy_layer = CanvasLayer.new()
	add_child(_trophy_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(240.0, 80.0)
	panel.custom_minimum_size = Vector2(800.0, 560.0)
	_trophy_layer.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = "Salle des trophees"
	title.add_theme_font_size_override(&"font_size", 30)
	box.add_child(title)

	_trophy_rows = VBoxContainer.new()
	_trophy_rows.add_theme_constant_override(&"separation", 8)
	_trophy_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_trophy_rows)

	_trophy_status = Label.new()
	_trophy_status.text = "Chargement du classement…"
	_trophy_status.add_theme_font_size_override(&"font_size", 18)
	_trophy_rows.add_child(_trophy_status)

	var done_button: Button = Button.new()
	done_button.text = "Terminer"
	done_button.custom_minimum_size = Vector2(280, 70)
	done_button.pressed.connect(end)
	box.add_child(done_button)

	LeaderboardClient.leaderboard_fetched.connect(
		_on_trophy_leaderboard_fetched, CONNECT_ONE_SHOT)
	LeaderboardClient.fetch_leaderboard()


func _on_trophy_leaderboard_fetched(entries: Array[Dictionary]) -> void:
	if _trophy_status != null:
		_trophy_status.queue_free()
		_trophy_status = null
	if entries.is_empty():
		var empty: Label = Label.new()
		empty.text = "Sois le premier au sommet !"
		empty.add_theme_font_size_override(&"font_size", 18)
		_trophy_rows.add_child(empty)
		return
	var rank: int = 1
	for entry: Dictionary in entries.slice(0, 8):
		var row: Label = Label.new()
		row.add_theme_font_size_override(&"font_size", 18)
		row.text = "%d.  %s — %d" % [rank, str(entry.get("pseudo", "?")),
			int(entry.get("total", entry.get("best_score", 0)))]
		_trophy_rows.add_child(row)
		rank += 1


# --- États ---

class ClimbState extends State:
	func enter(_previous: StringName) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		lighthouse._velocity = Vector2.ZERO
		lighthouse._player.play(&"climb")

	func update(delta: float) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		var platform_center: float = lighthouse._platform_x(lighthouse._current_level)
		var half: float = Lighthouse._PLATFORM_W * 0.5 - 20.0
		var center_x: float = lighthouse.player_center_x()
		center_x += lighthouse.walk_speed * lighthouse._walk_direction * delta
		if center_x > platform_center + half:
			center_x = platform_center + half
			lighthouse._walk_direction = -1.0
		elif center_x < platform_center - half:
			center_x = platform_center - half
			lighthouse._walk_direction = 1.0
		lighthouse._player.flip_h = lighthouse._walk_direction < 0.0
		lighthouse._player.position.x = center_x - 32.0

	func handle_tap(_position: Vector2) -> void:
		machine.transition_to(&"jump")


class JumpState extends State:
	func enter(_previous: StringName) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		var next_x: float = lighthouse._platform_x(lighthouse._current_level + 1)
		var direction: float = signf(next_x - lighthouse.player_center_x())
		lighthouse._velocity = Vector2(lighthouse.jump_horizontal_speed * direction,
			lighthouse.jump_velocity)
		lighthouse._player.play(&"jump")
		AudioManager.sfx(&"jump")

	func update(delta: float) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		lighthouse._velocity.y += lighthouse.gravity * delta
		lighthouse._player.position += lighthouse._velocity * delta
		if lighthouse._velocity.y >= 0.0:
			machine.transition_to(&"fall")


class FallState extends State:
	func enter(_previous: StringName) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		lighthouse._player.play(&"fall")

	func update(delta: float) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		lighthouse._velocity.y += lighthouse.gravity * delta
		lighthouse._player.position += lighthouse._velocity * delta
		var level: int = lighthouse.landing_level()
		if level >= 0:
			var reached_higher: bool = level > lighthouse._current_level
			lighthouse._place_on_level(level)
			if reached_higher:
				lighthouse.add_score(lighthouse.platform_points)
				AudioManager.sfx(&"step")
			if level >= lighthouse.platform_count - 1:
				machine.transition_to(&"reach")
			else:
				machine.transition_to(&"climb")
		elif lighthouse._player.position.y > Lighthouse._BASE_Y + 200.0:
			lighthouse._place_on_level(0)
			machine.transition_to(&"climb")


class ReachState extends State:
	func enter(_previous: StringName) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		lighthouse.add_score(lighthouse.summit_points)
		lighthouse._player.play(&"idle")
		AudioManager.sfx(&"victory")
		lighthouse.show_trophy_room()
