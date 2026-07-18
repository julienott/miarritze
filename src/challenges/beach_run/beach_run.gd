extends ChallengeBase
## Grande Plage — épreuve PLACEHOLDER Phase 1 : tape pour marquer.
## Valide la chaîne complète jouer → scorer → poster → classement.
## La vraie course sur le sable arrive en Phase 2.

## Points gagnés par tap (placeholder).
@export var points_per_tap: int = 10


func _on_begin() -> void:
	pass


func _on_tapped(_position: Vector2) -> void:
	add_score(points_per_tap)
