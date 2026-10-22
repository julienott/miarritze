class_name SafeArea
extends RefCounted
## Marges de zone sûre en px logiques (encoche et barre d'accueil iPhone,
## SPEC §7.3) : rien d'essentiel dans les bords non sûrs.


## Renvoie Vector4(gauche, haut, droite, bas) en px logiques.
static func margins(vp: Viewport) -> Vector4:
	var view: Vector2 = vp.get_visible_rect().size
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or safe.size.x <= 0 or safe.size.x >= int(win.x):
		return Vector4.ZERO
	var k: float = view.x / win.x
	return Vector4(maxf(0.0, safe.position.x * k), maxf(0.0, safe.position.y * k),
		maxf(0.0, (win.x - safe.end.x) * k), maxf(0.0, (win.y - safe.end.y) * k))
