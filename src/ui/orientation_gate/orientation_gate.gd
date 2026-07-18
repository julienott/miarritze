extends Control
## Orientation gate : affiche "Tourne ton appareil" tant que le viewport
## est en portrait ; en paysage, route vers la suite (pseudo_entry, ou
## directement le hub si une session existe déjà).

## Émis quand l'appareil est (ou revient) en paysage.
signal passed

## Délai avant routage, pour laisser la rotation se stabiliser.
@export var pass_delay: float = 0.3

var _routed: bool = false

@onready var _rotate_message: Label = %RotateMessage


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_gate()


func _on_viewport_size_changed() -> void:
	_update_gate()


func _is_portrait() -> bool:
	var size: Vector2 = get_viewport_rect().size
	return size.y > size.x


func _update_gate() -> void:
	var portrait: bool = _is_portrait()
	_rotate_message.visible = portrait
	if not portrait and not _routed:
		_routed = true
		passed.emit()
		get_tree().create_timer(pass_delay).timeout.connect(_route_forward)


func _route_forward() -> void:
	if GameState.has_session():
		SceneRouter.goto_hub()
	else:
		SceneRouter.goto_pseudo_entry()
