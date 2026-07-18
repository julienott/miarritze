class_name RockCrossing
extends ChallengeBase
## Rocher de la Vierge — traversée-timing façon Frogger (cf. DESIGN.md §4.4).
## Les vagues déferlent par cycles télégraphiés ; on tape pour avancer de
## plateforme en plateforme quand le passage est dégagé. Se faire balayer
## renvoie en arrière — jamais punitif au point de tout perdre.
## FSM : Wait, Step, Swept.

const _PLATFORM_COUNT: int = 8
const _PLATFORM_Y: float = 480.0
const _PLATFORM_SIZE: Vector2 = Vector2(96, 40)
const _FIRST_X: float = 90.0
const _SPACING_X: float = 140.0
const _PLAYER_SIZE: Vector2 = Vector2(44, 60)

@export var wave_cycle: float = 2.4          # durée d'un cycle complet (s)
@export var safe_fraction: float = 0.45      # part du cycle où le passage est dégagé
@export var step_duration: float = 0.22      # durée du bond d'une plateforme à l'autre
@export var swept_penalty_steps: int = 2     # recul quand on est balayé
@export var swept_stun: float = 0.8
@export var crossing_points: int = 100       # traversée complète
@export var step_points: int = 5             # chaque pas en avant

var _fsm: StateMachine
var _player: ColorRect
var _wave_overlay: ColorRect
var _cycle_time: float = 0.0
var _position_index: int = 0
var _crossings: int = 0


func _on_begin() -> void:
	for i: int in _PLATFORM_COUNT:
		var platform: ColorRect = ColorRect.new()
		platform.position = Vector2(_platform_x(i) - _PLATFORM_SIZE.x * 0.5, _PLATFORM_Y)
		platform.size = _PLATFORM_SIZE
		platform.color = Color(0.45, 0.42, 0.4)
		add_child(platform)

	_wave_overlay = ColorRect.new()
	_wave_overlay.position = Vector2(0.0, 300.0)
	_wave_overlay.size = Vector2(1280.0, 420.0)
	_wave_overlay.color = Color(0.7, 0.85, 0.95, 0.0)
	add_child(_wave_overlay)

	_player = ColorRect.new()
	_player.size = _PLAYER_SIZE
	_player.color = Color(0.85, 0.25, 0.2)
	add_child(_player)
	_place_player_at(0)

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


## Le passage est-il dégagé (fenêtre sûre du cycle) ?
func is_safe() -> bool:
	return _cycle_time < wave_cycle * safe_fraction


## La vague est télégraphiée : l'opacité monte AVANT qu'elle ne frappe,
## et l'écume est bien visible pendant la phase dangereuse.
func _update_wave_visual() -> void:
	var fraction: float = _cycle_time / wave_cycle
	var alpha: float
	if fraction < safe_fraction:
		# Phase sûre : l'eau se retire (transparence descend vers 0).
		alpha = lerpf(0.35, 0.0, fraction / safe_fraction)
	else:
		# La vague monte, frappe, puis commence à refluer.
		var danger: float = (fraction - safe_fraction) / (1.0 - safe_fraction)
		alpha = 0.15 + 0.55 * sin(danger * PI)
	_wave_overlay.color.a = alpha


func _platform_x(index: int) -> float:
	return _FIRST_X + index * _SPACING_X


func _place_player_at(index: int) -> void:
	_position_index = index
	_player.position = Vector2(_platform_x(index) - _PLAYER_SIZE.x * 0.5,
		_PLATFORM_Y - _PLAYER_SIZE.y)


func player_target(index: int) -> Vector2:
	return Vector2(_platform_x(index) - _PLAYER_SIZE.x * 0.5, _PLATFORM_Y - _PLAYER_SIZE.y)


func _complete_crossing() -> void:
	_crossings += 1
	add_score(crossing_points)
	AudioManager.sfx(&"crossed")
	_place_player_at(0)


# --- États ---

class WaitState extends State:
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
		AudioManager.sfx(&"step")

	func update(delta: float) -> void:
		var crossing: RockCrossing = machine.owner_node as RockCrossing
		_elapsed += delta
		var t: float = clampf(_elapsed / crossing.step_duration, 0.0, 1.0)
		var arc: float = -60.0 * sin(t * PI)   # petit bond
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
		crossing._player.color = Color(0.6, 0.6, 0.6)
		AudioManager.sfx(&"splash")

	func update(delta: float) -> void:
		var crossing: RockCrossing = machine.owner_node as RockCrossing
		_time_left -= delta
		if _time_left <= 0.0:
			crossing._player.color = Color(0.85, 0.25, 0.2)
			machine.transition_to(&"wait")
