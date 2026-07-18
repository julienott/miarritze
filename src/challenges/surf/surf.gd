class_name Surf
extends ChallengeBase
## Côte des Basques — surf (cf. DESIGN.md §4.2).
## Louis suit la vague ; tape au sommet pour décoller, tape en l'air pour
## enchaîner des figures, retombe proprement pour valider. Tout est timing.
## FSM : Ride, Launch, Trick, Land, Wipeout.

const _PLAYER_X: float = 420.0
const _WATER_BASE_Y: float = 430.0

@export var wave_cycle: float = 2.4
@export var wave_amplitude: float = 90.0
@export var launch_window: float = 0.4
@export var launch_velocity: float = -820.0
@export var gravity: float = 1600.0
@export var trick_duration: float = 0.38
@export var trick_points: int = 25
@export var landing_points: int = 10
@export var streak_bonus: int = 5

var _fsm: StateMachine
var _rider: Node2D
var _player: LouisSprite
var _board: Sprite2D
var _wave_line: Line2D
var _wave_crest: Line2D
var _window_hint: Label
var _wave_time: float = 0.0
var _velocity_y: float = 0.0
var _streak: int = 0
var _tricks_this_air: int = 0


func _on_begin() -> void:
	_rider = Node2D.new()
	_rider.z_index = 1
	add_child(_rider)
	_board = SpriteUtil.sprite("surfboard")
	_board.position = Vector2(-20.0, LouisSprite.FEET_Y - 4.0)
	_rider.add_child(_board)
	_player = LouisSprite.new()
	_rider.add_child(_player)
	_player.play(&"surf")

	_wave_line = Line2D.new()
	_wave_line.width = 26.0
	_wave_line.default_color = Color(0.125, 0.47, 0.6, 0.85)
	add_child(_wave_line)
	_wave_crest = Line2D.new()
	_wave_crest.width = 8.0
	_wave_crest.default_color = Color(0.87, 0.96, 0.94)
	add_child(_wave_crest)

	_window_hint = Label.new()
	_window_hint.text = "TAPE !"
	_window_hint.add_theme_font_size_override(&"font_size", 40)
	_window_hint.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.2))
	_window_hint.position = Vector2(_PLAYER_X - 30.0, 170.0)
	_window_hint.visible = false
	add_child(_window_hint)

	_fsm = StateMachine.new(self)
	_fsm.add_state(&"ride", RideState.new())
	_fsm.add_state(&"launch", LaunchState.new())
	_fsm.add_state(&"trick", TrickState.new())
	_fsm.add_state(&"land", LandState.new())
	_fsm.add_state(&"wipeout", WipeoutState.new())
	_fsm.transition_to(&"ride")


func _on_tapped(position: Vector2) -> void:
	_fsm.handle_tap(position)


func _physics_process(delta: float) -> void:
	if not is_running():
		return
	_wave_time += delta
	_fsm.update(delta)
	_redraw_wave()
	_window_hint.visible = _fsm.current_name == &"ride" and is_in_launch_window()


func wave_y(x: float) -> float:
	var phase: float = TAU * (_wave_time / wave_cycle) - x * 0.006
	return _WATER_BASE_Y - wave_amplitude * (0.5 + 0.5 * sin(phase))


func is_in_launch_window() -> bool:
	var phase: float = fposmod(TAU * (_wave_time / wave_cycle) - _PLAYER_X * 0.006, TAU)
	var half_window: float = PI * launch_window / wave_cycle
	return absf(phase - PI * 0.5) <= half_window


func _redraw_wave() -> void:
	var crest: PackedVector2Array = PackedVector2Array()
	var body: PackedVector2Array = PackedVector2Array()
	for i: int in 33:
		var x: float = i * 40.0
		crest.append(Vector2(x, wave_y(x)))
		body.append(Vector2(x, wave_y(x) + 16.0))
	_wave_crest.points = crest
	_wave_line.points = body


func rider_feet() -> float:
	return _rider.position.y + LouisSprite.FEET_Y


func _rider_on_wave() -> void:
	_rider.position = Vector2(_PLAYER_X, wave_y(_PLAYER_X) - LouisSprite.FEET_Y)
	# la planche épouse la pente de la vague
	var slope: float = (wave_y(_PLAYER_X + 30.0) - wave_y(_PLAYER_X - 30.0)) / 60.0
	_rider.rotation = atan(slope) * 0.7


# --- États ---

class RideState extends State:
	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._player.rotation = 0.0
		surf._tricks_this_air = 0
		surf._board.visible = true
		surf._player.play(&"surf")

	func update(_delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._rider_on_wave()

	func handle_tap(_position: Vector2) -> void:
		var surf: Surf = machine.owner_node as Surf
		if surf.is_in_launch_window():
			machine.transition_to(&"launch")


class LaunchState extends State:
	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._velocity_y = surf.launch_velocity
		surf._rider.rotation = 0.0
		surf._player.play(&"jump")
		AudioManager.sfx(&"jump")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._velocity_y += surf.gravity * delta
		surf._rider.position.y += surf._velocity_y * delta
		if surf.rider_feet() >= surf.wave_y(Surf._PLAYER_X):
			machine.transition_to(&"land")

	func handle_tap(_position: Vector2) -> void:
		machine.transition_to(&"trick")


class TrickState extends State:
	var _time_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		_time_left = surf.trick_duration
		surf._tricks_this_air += 1
		surf.add_score(surf.trick_points)
		AudioManager.sfx(&"trick")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._velocity_y += surf.gravity * delta
		surf._rider.position.y += surf._velocity_y * delta
		surf._rider.rotation += TAU * delta / surf.trick_duration
		_time_left -= delta
		var touched_water: bool = surf.rider_feet() >= surf.wave_y(Surf._PLAYER_X)
		if touched_water:
			machine.transition_to(&"wipeout")
		elif _time_left <= 0.0:
			surf._rider.rotation = 0.0
			machine.transition_to(&"launch")


class LandState extends State:
	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._streak += 1
		surf.add_score(surf.landing_points + surf.streak_bonus * (surf._streak - 1)
			+ surf.trick_points * surf._tricks_this_air / 2)
		AudioManager.sfx(&"land")
		machine.transition_to(&"ride")


class WipeoutState extends State:
	var _time_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		_time_left = 1.0
		surf._streak = 0
		surf._rider.rotation = 0.0
		surf._board.visible = false
		surf._player.play(&"hit")
		surf._player.modulate = Color(1, 1, 1, 0.6)
		AudioManager.sfx(&"splash")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._rider_on_wave()
		_time_left -= delta
		if _time_left <= 0.0:
			surf._player.modulate = Color.WHITE
			machine.transition_to(&"ride")
