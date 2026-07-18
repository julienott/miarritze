class_name Surf
extends ChallengeBase
## Côte des Basques — surf (cf. DESIGN.md §4.2).
## Louis suit la vague ; tape au sommet pour décoller, tape en l'air pour
## enchaîner des figures, retombe proprement pour valider. Tout est timing.
## FSM : Ride, Launch, Trick, Land, Wipeout.

const _PLAYER_X: float = 420.0
const _WATER_BASE_Y: float = 430.0
const _PLAYER_SIZE: Vector2 = Vector2(44, 60)

@export var wave_cycle: float = 2.4          # durée d'un cycle de vague (s)
@export var wave_amplitude: float = 90.0     # hauteur de bosse (px)
@export var launch_window: float = 0.4       # fenêtre de tap au sommet (s), indulgente
@export var launch_velocity: float = -820.0
@export var gravity: float = 1600.0
@export var trick_duration: float = 0.38     # durée d'une figure (rotation)
@export var trick_points: int = 25
@export var landing_points: int = 10
@export var streak_bonus: int = 5            # bonus par réception propre consécutive

var _fsm: StateMachine
var _player: ColorRect
var _wave_line: Line2D
var _window_hint: Label
var _wave_time: float = 0.0
var _velocity_y: float = 0.0
var _streak: int = 0
var _tricks_this_air: int = 0


func _on_begin() -> void:
	_player = ColorRect.new()
	_player.size = _PLAYER_SIZE
	_player.color = Color(0.85, 0.25, 0.2)
	add_child(_player)

	_wave_line = Line2D.new()
	_wave_line.width = 6.0
	_wave_line.default_color = Color(1, 1, 1, 0.8)
	add_child(_wave_line)

	_window_hint = Label.new()
	_window_hint.text = "TAPE !"
	_window_hint.add_theme_font_size_override(&"font_size", 44)
	_window_hint.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.2))
	_window_hint.position = Vector2(_PLAYER_X - 30.0, 180.0)
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
	# Le signal visuel "TAPE !" n'apparaît que sur la vague, dans la fenêtre.
	_window_hint.visible = _fsm.current_name == &"ride" and _is_in_launch_window()


## Hauteur de la vague au point x, pour l'instant courant.
func wave_y(x: float) -> float:
	var phase: float = TAU * (_wave_time / wave_cycle) - x * 0.006
	return _WATER_BASE_Y - wave_amplitude * (0.5 + 0.5 * sin(phase))


## Le sommet passe sous Louis quand la sinusoïde y est à son max.
func _is_in_launch_window() -> bool:
	var phase: float = fposmod(TAU * (_wave_time / wave_cycle) - _PLAYER_X * 0.006, TAU)
	var half_window: float = PI * launch_window / wave_cycle
	return absf(phase - PI * 0.5) <= half_window


func _redraw_wave() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 33:
		var x: float = i * 40.0
		points.append(Vector2(x, wave_y(x)))
	_wave_line.points = points


func _player_on_wave() -> void:
	_player.position = Vector2(_PLAYER_X, wave_y(_PLAYER_X) - _PLAYER_SIZE.y)


func is_in_launch_window() -> bool:
	return _is_in_launch_window()


# --- États ---

class RideState extends State:
	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._player.rotation = 0.0
		surf._tricks_this_air = 0

	func update(_delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._player_on_wave()

	func handle_tap(_position: Vector2) -> void:
		var surf: Surf = machine.owner_node as Surf
		if surf.is_in_launch_window():
			machine.transition_to(&"launch")
		# Tap hors fenêtre : rien de punitif, Louis reste sur la vague.


class LaunchState extends State:
	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._velocity_y = surf.launch_velocity
		AudioManager.sfx(&"jump")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._velocity_y += surf.gravity * delta
		surf._player.position.y += surf._velocity_y * delta
		if surf._player.position.y + Surf._PLAYER_SIZE.y >= surf.wave_y(Surf._PLAYER_X):
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
		surf._player.position.y += surf._velocity_y * delta
		surf._player.rotation += TAU * delta / surf.trick_duration
		_time_left -= delta
		var touched_water: bool = surf._player.position.y + Surf._PLAYER_SIZE.y >= surf.wave_y(Surf._PLAYER_X)
		if touched_water:
			# Toucher l'eau en pleine rotation = chute.
			machine.transition_to(&"wipeout")
		elif _time_left <= 0.0:
			surf._player.rotation = 0.0
			machine.transition_to(&"launch")

	func handle_tap(_position: Vector2) -> void:
		# Le tap est ignoré pendant la rotation : on enchaîne après.
		pass


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
		surf._player.color = Color(0.6, 0.6, 0.6)
		AudioManager.sfx(&"splash")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._player_on_wave()
		_time_left -= delta
		if _time_left <= 0.0:
			surf._player.color = Color(0.85, 0.25, 0.2)
			surf._player.rotation = 0.0
			machine.transition_to(&"ride")
