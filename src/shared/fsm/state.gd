class_name State
extends RefCounted
## État de base de la FSM générique (cf. CLAUDE.md §5.2).
##
## Chaque épreuve définit ses propres états en étendant cette classe
## (classes internes de son script). L'état accède à sa machine via
## `machine` et à la scène propriétaire via `machine.owner_node`.

var machine: StateMachine


## Appelé à l'entrée dans l'état. `previous` = nom de l'état quitté.
func enter(_previous: StringName) -> void:
	pass


## Appelé à la sortie de l'état.
func exit() -> void:
	pass


## Appelé chaque frame physique par la scène propriétaire.
func update(_delta: float) -> void:
	pass


## Geste tap relayé par la scène propriétaire (position écran).
func handle_tap(_position: Vector2) -> void:
	pass
