class_name RockCrossing
extends ChallengeBase
## Rocher de la Vierge — traversée-timing façon Frogger (cf. DESIGN.md §4.4).
## Les vagues déferlent par cycles télégraphiés ; on tape pour avancer de
## plateforme en plateforme quand le passage est dégagé.
## FSM : Wait, Step, Swept.

const _PLATFORM_COUNT: int = 8
const _PLATFORM_Y: float = 500.0
const _FIRST_X: float = 90.0
const _SPACING_X: float = 145.0

@export var wave_cycle: float = 2.4
@export var safe_fraction: float = 0.45
@export var step_duration: float = 0.22
@export var swept_penalty_steps: int = 2
@export var swept_stun: float = 0.8
@export var crossing_points: int = 100
@export var step_points: int = 5

var _fsm: StateMachine
var _player: LouisSprite
var _wave_overlay: ColorRect
var _foam_line: Line2D
var _cycle_time: float = 0.0
var _position_index: int = 0
var _crossings: int = 0


func _on_begin() -> void:
	for i: int in _PLATFORM_COUNT:
		var platform: Sprite2D = SpriteUtil.sprite("rock_platform")
		var size: Vector2 = SpriteUtil.display_size(platform)
		platform.position = Vector2(_platform_x(i) - size.x * 0.5, _PLATFORM_Y)
		add_child(platform)

	_wave_overlay = ColorRect.new()
	_wave_overlay.position = Vector2(0.0, 340.0)
	_wave_overlay.size = Vector2(1280.0, 380.0)
	_wave_overlay.color = Color(0.87, 0.96, 0.94, 0.0)
	add_child(_wave_overlay)

	_foam_line = Line2D.new()
	_foam_line.width = 10.0
	_foam_line.default_color = Color(0.87, 0.96, 0.94, 0.9)
	add_child(_foam_line)

	_player = LouisSprite.new()
	add_child(_player)
	_place_player_at(0)
	_player.play(&"idle")

	_fsm = StateMachine.new(self)
	_fsm.add_state(&"wait", WaitState.new())
	_fsm.add_state(&"step", StepState.new())
	_fsm.add_state(&"swept", SweptState.new())
	_fsm.transition_to(&"wait")


func _on_tapped(position: Vector2) -> void:
	_fsm.handle_tap(position)


func _physics_process(delta: float) -> void:
	if not is_running():
		return
	_cycle_time = fposmod(_cycle_time + delta, wave_cycle)
	_fsm.update(delta)
	_update_wave_visual()


func is_safe() -> bool:
	return _cycle_time < wave_cycle * safe_fraction


func _update_wave_visual() -> void:
	var fraction: float = _cycle_time / wave_cycle
	var alpha: float
	if fraction < safe_fraction:
		alpha = lerpf(0.30, 0.0, fraction / safe_fraction)
	else:
		var danger: float = (fraction - safe_fraction) / (1.0 - safe_fraction)
		alpha = 0.12 + 0.5 * sin(danger * PI)
	_wave_overlay.color.a = alpha
	# ligne d'écume qui monte et descend avec le cycle (télégraphe visuel)
	var foam_y: float = 720.0 - 300.0 * alpha
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 17:
		var x: float = i * 80.0
		points.append(Vector2(x, foam_y + 14.0 * sin(x * 0.02 + _cycle_time * 4.0)))
	_foam_line.points = points
	_foam_line.modulate.a = clampf(alpha * 2.5, 0.0, 1.0)


func _platform_x(index: int) -> float:
	return _FIRST_X + index * _SPACING_X


func _place_player_at(index: int) -> void:
	_position_index = index
	_player.position = player_target(index)


func player_target(index: int) -> Vector2:
	return Vector2(_platform_x(index) - 32.0, _PLATFORM_Y + 8.0 - LouisSprite.FEET_Y)


func _complete_crossing() -> void:
	_crossings += 1
	add_score(crossing_points)
	AudioManager.sfx(&"crossed")
	_place_player_at(0)


# --- États ---

class WaitState extends State:
	func enter(_previous: StringName) -> void:
		var crossing: RockCrossing = machine.owner_node as RockCrossing
		crossing._player.play(&"idle")

	func handle_tap(_position: Vector2) -> void:
		var crossing: RockCrossing = machine.owner_node as RockCrossing
		if crossing.is_safe():
			machine.transition_to(&"step")
		else:
			machine.transition_to(&"swept")


class StepState extends State:
	var _elapsed: float = 0.0
	var _from: Vector2
	var _to: Vector2

	func enter(_previous: StringName) -> void:
		var crossing: RockCrossing = machine.owner_node as RockCrossing
		_elapsed = 0.0
		_from = crossing._player.position
		_to = crossing.player_target(crossing._position_index + 1)
		crossing._player.play(&"jump")
		AudioManager.sfx(&"step")

	func update(delta: float) -> void:
		var crossing: RockCrossing = machine.owner_node as RockCrossing
		_elapsed += delta
		var t: float = clampf(_elapsed / crossing.step_duration, 0.0, 1.0)
		var arc: float = -60.0 * sin(t * PI)
		crossing._player.position = _from.lerp(_to, t) + Vector2(0.0, arc)
		if t >= 1.0:
			crossing._position_index += 1
			crossing.add_score(crossing.step_points)
			if crossing._position_index >= RockCrossing._PLATFORM_COUNT - 1:
				crossing._complete_crossing()
			machine.transition_to(&"wait")


class SweptState extends State:
	var _time_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var crossing: RockCrossing = machine.owner_node as RockCrossing
		_time_left = crossing.swept_stun
		var back_to: int = maxi(crossing._position_index - crossing.swept_penalty_steps, 0)
		crossing._place_player_at(back_to)
		crossing._player.play(&"hit")
		crossing._player.modulate = Color(1, 1, 1, 0.6)
		AudioManager.sfx(&"splash")
		crossing.lose_life()

	func update(delta: float) -> void:
		var crossing: RockCrossing = machine.owner_node as RockCrossing
		_time_left -= delta
		if _time_left <= 0.0:
			crossing._player.modulate = Color.WHITE
			machine.transition_to(&"wait")
