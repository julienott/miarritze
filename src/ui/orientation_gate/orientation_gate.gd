extends Control
## Orientation gate : affiche "Tourne ton appareil" tant que le viewport
## est en portrait ; laisse passer en paysage. Rien d'autre en Phase 0.
##
## En Phase 1, `passed` déclenchera la navigation vers pseudo_entry.

## Émis quand l'appareil est (ou revient) en paysage.
signal passed

@onready var _rotate_message: Label = %RotateMessage
@onready var _ready_message: Label = %ReadyMessage


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
	_ready_message.visible = not portrait
	if not portrait:
		passed.emit()
