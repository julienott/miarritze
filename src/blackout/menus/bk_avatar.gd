class_name BkAvatar
extends Control
## Avatar d'un perso pour les menus, le versus et le podium : le vrai perso du jeu (BkActor + BkPerso,
## planches px32 ou silhouette de repli), debout sur son ombre, pieds en bas au centre du contrôle,
## agrandi d'un nombre entier de fois (pixels nets). `anime` faux : image figée (vignettes de la
## grille, animées seulement au focus). Aucune couleur de joueur (GDD §7.1).

## Repère de l'acteur (px du monde) : de la tête au bas de l'ombre, et du pivot au bas de l'ombre.
const HAUT_LOCAL: float = 36.0
const SOUS_PIVOT: float = 7.0

## Hauteur de l'avatar à l'écran, ombre comprise (px).
var hauteur: float = 240.0
var anime: bool = true:
	set(v):
		anime = v
		_maj_process()
var regard_gauche: bool = false
var actor: BkActor
var _pivot: Node2D
var _images: int = 0
var _perso_id: String = "louis"


static func cree(perso_id: String, h: float, p_anime: bool = true) -> BkAvatar:
	var a: BkAvatar = BkAvatar.new()
	a.hauteur = h
	a.anime = p_anime
	a._perso_id = perso_id
	a.custom_minimum_size = Vector2(h * 0.6, h)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return a


func _ready() -> void:
	_pivot = Node2D.new()
	_pivot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_pivot)
	_construire()


## Change de perso (le perso est recréé).
func regler(perso_id: String) -> void:
	if perso_id == _perso_id and actor != null:
		return
	_perso_id = perso_id
	if actor != null:
		_construire()


func _construire() -> void:
	if actor != null:
		actor.queue_free()
	actor = BkActor.new()
	actor.character = _perso_id
	actor.setup(0, "", true)
	# Pas un corps du monde : rien ne le touche, il ne touche rien.
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.look = PI if regard_gauche else 0.0
	_pivot.add_child(actor)
	_images = 0
	_maj_process()


## Pose de fin (« victory », « sad ») tenue en boucle, ou "" pour l'attente.
func pose(nom: String) -> void:
	if actor != null:
		actor.end_pose = nom


func _maj_process() -> void:
	if actor != null and actor.perso != null:
		# Deux images pour poser la planche, puis figé si l'avatar n'est pas animé.
		actor.perso.set_process(anime or _images < 2)


func _process(_dt: float) -> void:
	if actor == null:
		return
	_images += 1
	if _images <= 3:
		_maj_process()
	actor.look = PI if regard_gauche else 0.0
	var k: float = maxf(1.0, floorf(hauteur / HAUT_LOCAL))
	_pivot.scale = Vector2(k, k)
	_pivot.position = Vector2(size.x * 0.5, size.y - SOUS_PIVOT * k).round()
