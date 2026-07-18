class_name StateMachine
extends RefCounted
## FSM générique réutilisable (cf. CLAUDE.md §5.2).
##
## Créée en code par la scène propriétaire, qui relaie update() depuis
## _physics_process et les gestes depuis TouchInput.

signal state_changed(previous: StringName, current: StringName)

## Scène propriétaire, accessible aux états (typiquement l'épreuve).
var owner_node: Node

var _states: Dictionary = {}
var _current: State = null
var current_name: StringName = &""


func _init(p_owner: Node) -> void:
	owner_node = p_owner


func add_state(state_name: StringName, state: State) -> void:
	state.machine = self
	_states[state_name] = state


func transition_to(state_name: StringName) -> void:
	assert(_states.has(state_name), "État inconnu : %s" % state_name)
	var previous: StringName = current_name
	if _current != null:
		_current.exit()
	current_name = state_name
	_current = _states[state_name]
	_current.enter(previous)
	state_changed.emit(previous, current_name)


func update(delta: float) -> void:
	if _current != null:
		_current.update(delta)


func handle_tap(position: Vector2) -> void:
	if _current != null:
		_current.handle_tap(position)
