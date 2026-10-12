class_name FinisherFx
extends Node2D
## Finishs « BUKATU ! » comiques et non violents (SPEC §4.5, §5.1), en
## procédural : accessoires dessinés + teinte/déplacement de la vue du
## perdant. Purement visuel : la sim reste en état FINISHED.

const DURATION: float = 4.2

var kind: String = "bucket"
var text: String = "PLOUF !"
var loser: FighterView
var winner: FighterView
var vfx: VfxPool
var _t: float = 0.0
var _base: Vector2
var _said: bool = false


func start(p_kind: String, p_text: String, p_winner: FighterView, p_loser: FighterView, p_vfx: VfxPool) -> void:
	kind = p_kind
	text = p_text
	winner = p_winner
	loser = p_loser
	vfx = p_vfx
	z_index = 30
	_base = loser.position


func _process(delta: float) -> void:
	_t += delta
	var k: float = clampf(_t / DURATION, 0.0, 1.0)
	_base = loser.position - loser.visual_offset
	match kind:
		"bucket", "big_ball", "chocolate":
			if _t > 1.0:
				var c: Color = Color8(64, 150, 210) if kind == "bucket" else (Color8(120, 80, 40) if kind == "chocolate" else Color8(247, 241, 227))
				loser.set_tint(c, minf((_t - 1.0) * 1.5, 0.55))
				if kind != "big_ball":
					loser.visual_offset.x = sin(_t * 9.0) * 6.0
				else:
					loser.visual_scale = Vector2(1.25, maxf(0.55, 1.0 - (_t - 1.0)))
		"wave":
			if _t > 0.8:
				loser.visual_offset = Vector2((_t - 0.8) * 120.0 * _away(), -sin(minf(_t - 0.8, 1.5) * 2.0) * 30.0)
		"net":
			loser.set_tint(Color8(196, 148, 92), 0.25 if _t > 0.6 else 0.0)
		"statue":
			loser.set_gray(minf(_t * 0.8, 1.0))
		"dance":
			loser.visual_offset = Vector2(sin(_t * 8.0) * 14.0, -absf(sin(_t * 8.0)) * 10.0)
			loser.visual_scale = Vector2(1.0 if sin(_t * 4.0) > 0 else -1.0, 1.0)
		"fish":
			if _t > 1.4:
				loser.visual_offset.x = (_t - 1.4) * 160.0 * _away()
		"feathers":
			loser.visual_offset.y = -absf(sin(_t * 6.0)) * 6.0
		"pinch":
			loser.visual_offset = Vector2(sin(_t * 30.0) * 2.0, -absf(sin(_t * 3.0)) * 20.0)
		"sandcastle":
			loser.set_tint(Color8(238, 202, 128), minf(_t, 1.0) * 0.9)
			if _t > 2.4:
				loser.modulate.a = maxf(0.0, 1.0 - (_t - 2.4))
		"goalpost":
			loser.visual_scale = Vector2(maxf(0.4, 1.0 - _t * 0.3), 1.0 + minf(_t * 0.3, 0.6))
			loser.set_tint(Color8(247, 241, 227), minf(_t, 0.8))
		"moth":
			var s: float = maxf(0.2, 1.0 - _t * 0.3)
			loser.visual_scale = Vector2(s, s)
			loser.visual_offset = Vector2(sin(_t * 7.0) * 10.0, -_t * 26.0)
			loser.set_tint(Color8(160, 112, 176), minf(_t * 0.5, 0.6))
	if not _said and k > 0.55:
		_said = true
		vfx.word(_base + Vector2(0, -120), text, UiKit.C_GOLD)
	queue_redraw()
	if _t > DURATION + 1.0:
		set_process(false)


func _away() -> float:
	return 1.0 if loser.position.x >= winner.position.x else -1.0


func _draw() -> void:
	var head: Vector2 = loser.position + Vector2(0, -110)
	match kind:
		"bucket":
			var y: float = minf(head.y, -60.0 + _t * 220.0)
			var tilt: bool = _t > 1.0
			var r: Rect2 = Rect2(head.x - 12, y - 16, 24, 18)
			draw_rect(r.grow(1), UiKit.C_OUTLINE)
			draw_rect(r, Color8(140, 150, 162))
			if tilt:
				for i: int in 10:
					var dx: float = sin(i * 2.3 + _t * 5.0) * 18.0
					draw_rect(Rect2(head.x + dx, head.y + fmod(_t * 120.0 + i * 13.0, 90.0), 2, 3), Color8(196, 232, 230))
		"big_ball":
			var by: float = minf(head.y + 10.0, -80.0 + _t * 260.0)
			draw_circle(Vector2(head.x, by), 28, UiKit.C_OUTLINE)
			draw_circle(Vector2(head.x, by), 26, Color8(247, 241, 227))
			draw_arc(Vector2(head.x, by), 18, 0.4, 2.6, 8, Color8(206, 52, 52), 2.0)
		"wave":
			var front: float = -60.0 + _t * 240.0
			var poly: PackedVector2Array = [Vector2(front - 400, 200), Vector2(front, 200), Vector2(front - 20, 120),
				Vector2(front - 60, 100), Vector2(front - 400, 110)]
			if _away() < 0:
				for i: int in poly.size():
					poly[i].x = 576.0 - poly[i].x
			draw_colored_polygon(poly, Color(0.25, 0.7, 0.74, 0.85))
		"net":
			if _t > 0.5:
				var top: float = minf(head.y - 6.0, head.y - 120.0 + _t * 200.0)
				var r2: Rect2 = Rect2(loser.position.x - 24, top, 48, loser.position.y - top)
				for i: int in 7:
					draw_line(Vector2(r2.position.x + i * 8, r2.position.y), Vector2(r2.position.x + i * 8, r2.end.y), Color8(108, 72, 46), 1.0)
				for j: int in int(r2.size.y / 8.0):
					draw_line(Vector2(r2.position.x, r2.position.y + j * 8), Vector2(r2.end.x, r2.position.y + j * 8), Color8(108, 72, 46), 1.0)
				if _t > 1.6:
					_gull(head + Vector2(0, -8))
		"statue":
			draw_rect(Rect2(loser.position.x - 26, loser.position.y - 4, 52, 8), UiKit.C_OUTLINE)
			draw_rect(Rect2(loser.position.x - 25, loser.position.y - 3, 50, 6), Color8(164, 156, 152))
		"fish":
			var fx: float = winner.position.x + (loser.position.x - winner.position.x) * 0.5
			_fish(Vector2(fx, head.y + 30))
		"feathers":
			for i: int in 12:
				var p: Vector2 = loser.position + Vector2(sin(i * 1.7) * 30.0, -40.0 - fmod(_t * 40.0 + i * 17.0, 90.0))
				draw_rect(Rect2(p, Vector2(3, 2)), Color8(247, 241, 227))
		"pinch":
			draw_circle(head + Vector2(10, 18), 5, Color8(238, 140, 58))
		"chocolate":
			var level: float = minf(_t * 50.0, 60.0)
			draw_rect(Rect2(head.x - 14, head.y, 28, level), Color(0.47, 0.31, 0.16, 0.75))
		"goalpost":
			pass
		"moth":
			draw_circle(winner.position + Vector2(0, -130), 8, Color(1.0, 0.95, 0.6, 0.6))


func _gull(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(-6, -4), Vector2(12, 6)), Color8(247, 241, 227))
	draw_rect(Rect2(p + Vector2(4, -6), Vector2(4, 3)), Color8(244, 198, 62))
	draw_rect(Rect2(p + Vector2(-6, -4), Vector2(12, 6)), UiKit.C_OUTLINE, false, 1.0)


func _fish(p: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(-10, 0), p + Vector2(0, -5), p + Vector2(10, 0), p + Vector2(0, 5)]), Color8(140, 150, 162))
	draw_colored_polygon(PackedVector2Array([p + Vector2(10, 0), p + Vector2(16, -5), p + Vector2(16, 5)]), Color8(140, 150, 162))
	draw_rect(Rect2(p + Vector2(-6, -1), Vector2(2, 2)), UiKit.C_OUTLINE)
