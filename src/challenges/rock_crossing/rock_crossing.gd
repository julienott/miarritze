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
var _wave: WaveVisual
var _cycle_time: float = 0.0
var _position_index: int = 0
var _crossings: int = 0


func _on_begin() -> void:
	for i: int in _PLATFORM_COUNT:
		var platform: Sprite2D = SpriteUtil.sprite("rock_platform")
		var size: Vector2 = SpriteUtil.display_size(platform)
		platform.position = Vector2(_platform_x(i) - size.x * 0.5, _PLATFORM_Y)
		add_child(platform)

	# la vague déferlante réutilise le visuel du surf, en balayage
	_wave = WaveVisual.new()
	_wave.base_y = 730.0
	_wave.sigma = 320.0
	_wave.height = 0.0
	_wave.breaking = 1.0
	_wave.z_index = 1
	add_child(_wave)

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
	if fraction < safe_fraction:
		# mer retirée : la vague se reforme au large, à droite
		var t: float = fraction / safe_fraction
		_wave.center_x = 1650.0
		_wave.height = lerpf(20.0, 90.0, t)
		_wave.collapse = 0.0
	else:
		# la vague BALAYE la passerelle de droite à gauche, en déferlant
		var danger: float = (fraction - safe_fraction) / (1.0 - safe_fraction)
		_wave.center_x = lerpf(1650.0, -420.0, danger)
		_wave.height = 310.0 * sin(minf(danger * 1.25, 1.0) * PI * 0.72 + 0.35)
		_wave.collapse = 0.5 + 0.5 * danger


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
	# chaque traversée accélère l'océan : la partie se corse toute seule
	wave_cycle = maxf(wave_cycle * 0.92, 1.3)
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
		Fx.splash(crossing, crossing._player.position + Vector2(32.0, 40.0))
		crossing.lose_life()

	func update(delta: float) -> void:
		var crossing: RockCrossing = machine.owner_node as RockCrossing
		_time_left -= delta
		if _time_left <= 0.0:
			crossing._player.modulate = Color.WHITE
			machine.transition_to(&"wait")
