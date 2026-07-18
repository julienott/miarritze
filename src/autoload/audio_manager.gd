extends Node
## AudioManager — musique par épreuve, SFX, volumes.
##
## Chaque épreuve a son thème chiptune (cf. DESIGN.md §7) ; les SFX sont
## joués par nom depuis assets/audio/sfx.
## STUB Phase 0 : API publique seulement, aucun asset audio encore.

## Volume musique (0..1), réglable au playtest.
@export_range(0.0, 1.0) var music_volume: float = 0.8

## Volume SFX (0..1), réglable au playtest.
@export_range(0.0, 1.0) var sfx_volume: float = 1.0


## Lance (ou relance) le thème musical associé à une épreuve.
func play_music(_challenge: StringName) -> void:
	pass


## Joue un bruitage par nom (ex. &"jump", &"coin", &"splash").
func sfx(_name: StringName) -> void:
	pass
