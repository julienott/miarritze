class_name SpriteUtil
## Petits constructeurs de sprites pixel art (échelle x4, origine haut-gauche).

const SCALE: float = 4.0


static func sprite(path: String) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.texture = load("res://assets/sprites/%s.png" % path)
	s.centered = false
	s.scale = Vector2(SCALE, SCALE)
	return s


static func animated(names: Array, fps: float, loop: bool = true) -> AnimatedSprite2D:
	var s: AnimatedSprite2D = AnimatedSprite2D.new()
	var frames: SpriteFrames = SpriteFrames.new()
	frames.set_animation_speed(&"default", fps)
	frames.set_animation_loop(&"default", loop)
	for n: String in names:
		frames.add_frame(&"default", load("res://assets/sprites/%s.png" % n))
	s.sprite_frames = frames
	s.centered = false
	s.scale = Vector2(SCALE, SCALE)
	s.play(&"default")
	return s


## Taille affichée (px écran) d'un sprite non centré, échelle comprise.
static func display_size(s: Node2D) -> Vector2:
	if s is Sprite2D:
		return (s as Sprite2D).texture.get_size() * s.scale
	if s is AnimatedSprite2D:
		var anim: AnimatedSprite2D = s
		return anim.sprite_frames.get_frame_texture(&"default", 0).get_size() * s.scale
	return Vector2.ZERO
