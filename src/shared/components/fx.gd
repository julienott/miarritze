class_name Fx
## Particules « game feel » : petites rafales one-shot de gros pixels.

static func burst(parent: Node, at: Vector2, color: Color, count: int = 10,
		speed: float = 160.0, up: bool = true) -> void:
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.position = at
	particles.emitting = true
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	particles.direction = Vector2(0, -1) if up else Vector2(0, 1)
	particles.spread = 70.0
	particles.gravity = Vector2(0, 500.0)
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 5.0
	particles.color = color
	parent.add_child(particles)
	particles.finished.connect(particles.queue_free)


static func splash(parent: Node, at: Vector2) -> void:
	burst(parent, at, Color(0.87, 0.96, 0.94), 14, 220.0)


static func sand_puff(parent: Node, at: Vector2) -> void:
	burst(parent, at, Color(0.84, 0.66, 0.38), 8, 110.0)


static func stars(parent: Node, at: Vector2) -> void:
	burst(parent, at, Color(0.95, 0.78, 0.24), 12, 260.0)
