extends Control
## Écran de démarrage : fond + titre "Miarritze", puis bascule vers
## l'orientation_gate après un court délai. Rien d'autre en Phase 0.

## Durée d'affichage du titre avant de basculer, en secondes.
@export var splash_duration: float = 1.5


func _ready() -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(splash_duration)
	timer.timeout.connect(_on_splash_timer_timeout)


func _on_splash_timer_timeout() -> void:
	SceneRouter.goto_orientation_gate()
