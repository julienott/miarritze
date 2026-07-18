class_name LouisSprite
extends AnimatedSprite2D
## Louis animé, construit depuis assets/sprites/louis.png (grille 16x24).
## Origine = coin haut-gauche, échelle x4 (frame affichée : 64x96).
## Les pieds touchent le bas utile de la frame à FEET_Y pixels du haut.

const FRAME_W: int = 16
const FRAME_H: int = 24
const SCALE: float = 4.0
## Position des pieds dans la frame (en px écran, déjà scalé x4).
const FEET_Y: float = 88.0

## nom : [rangée, nb frames, fps, boucle]
const _ANIMS: Dictionary = {
	&"idle": [0, 2, 2.5, true],
	&"run": [1, 6, 12.0, true],
	&"jump": [2, 1, 1.0, false],
	&"fall": [3, 1, 1.0, false],
	&"hit": [4, 1, 1.0, false],
	&"surf": [5, 1, 1.0, false],
	&"fish": [6, 2, 2.0, true],
	&"throw": [7, 2, 8.0, false],
	&"climb": [8, 2, 6.0, true],
	&"win": [9, 2, 3.0, true],
}


func _ready() -> void:
	var sheet: Texture2D = load("res://assets/sprites/louis.png")
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim_name: StringName in _ANIMS:
		var spec: Array = _ANIMS[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, spec[2])
		frames.set_animation_loop(anim_name, spec[3])
		for i: int in int(spec[1]):
			var atlas: AtlasTexture = AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(i * FRAME_W, int(spec[0]) * FRAME_H, FRAME_W, FRAME_H)
			frames.add_frame(anim_name, atlas)
	sprite_frames = frames
	centered = false
	scale = Vector2(SCALE, SCALE)
	play(&"idle")
