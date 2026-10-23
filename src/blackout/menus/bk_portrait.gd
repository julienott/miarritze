class_name BkPortrait
extends Control
## Portrait d'un perso (GDD §8.1 : buste de trois-quarts, 64×64), pour le versus, le podium et les
## listes : première image de l'élément `portrait` de son set (profil en repli, BkPerso), agrandie d'un
## nombre entier de fois, pixels nets, centrée. Aucune couleur de joueur (GDD §7.1).

var perso_id: String = "louis"


static func cree(p_id: String, taille: float) -> BkPortrait:
	var p: BkPortrait = BkPortrait.new()
	p.perso_id = p_id
	p.custom_minimum_size = Vector2(taille, taille)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return p


func _draw() -> void:
	var d: Dictionary = BkPerso.portrait(perso_id)
	var cell: Vector2 = d["cell"]
	var k: float = maxf(1.0, floorf(minf(size.x, size.y) / cell.x))
	var dst: Rect2 = Rect2(((size - cell * k) * 0.5).round(), cell * k)
	draw_texture_rect_region(d["tex"], dst, Rect2(Vector2.ZERO, cell))
