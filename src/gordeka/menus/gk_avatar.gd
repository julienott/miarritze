class_name GkAvatar
extends Control
## Avatar d'un perso pour les menus, le versus et le podium : le vrai perso du jeu (GkActor + GkPerso,
## planches animées, tenue à la couleur du joueur), debout sur son ombre, pieds en bas au centre du
## contrôle. `anime` faux : image figée (vignettes de la grille, animées seulement au focus).
## Un perso sans planches montre son profil validé (modele.png), sans recoloration.

## Repère de l'acteur (px du monde) : de la tête au bas de l'ombre, et du pivot au bas de l'ombre.
const HAUT_LOCAL: float = 97.0
const SOUS_PIVOT: float = 24.0

## Hauteur de l'avatar à l'écran, ombre comprise (px).
var hauteur: float = 240.0
var anime: bool = true:
	set(v):
		anime = v
		_maj_process()
var regard_gauche: bool = false
var actor: GkActor
var _pivot: Node2D
var _images: int = 0
var _perso_id: String = "louis"
var _couleur: Color = Color.WHITE


static func cree(perso_id: String, couleur: Color, h: float, p_anime: bool = true) -> GkAvatar:
	var a: GkAvatar = GkAvatar.new()
	a.hauteur = h
	a.anime = p_anime
	a._perso_id = perso_id
	a._couleur = couleur
	a.custom_minimum_size = Vector2(h * 0.6, h)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return a


func _ready() -> void:
	_pivot = Node2D.new()
	add_child(_pivot)
	_construire()


## Change de perso et de couleur (le perso est recréé, sa couleur suit).
func regler(perso_id: String, couleur: Color) -> void:
	var autre: bool = perso_id != _perso_id
	_perso_id = perso_id
	_couleur = couleur
	if actor == null:
		return
	if autre:
		_construire()
	else:
		actor.color = couleur
		_images = 0           # une image de plus pour reteindre un avatar figé
		_maj_process()


func _construire() -> void:
	if actor != null:
		actor.queue_free()
	actor = GkActor.new()
	actor.character = _perso_id
	actor.setup(0, "", _couleur, true)
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


## Joue une emote (geste du perso et bulle au-dessus de la tête, comme en jeu).
func emote(i: int) -> void:
	if actor == null or i < 0 or i >= GkGame.EMOTES.size():
		return
	actor.emote = i
	actor.emote_t = GkRules.f("emote_duration")
	actor.play_once(GkGame.EMOTES[i])
	if actor.perso != null:
		actor.perso.set_process(true)


func _maj_process() -> void:
	if actor != null and actor.perso != null:
		# Deux images pour poser la planche, puis figé si l'avatar n'est pas animé.
		actor.perso.set_process(anime or _images < 2 or actor.emote_t > 0.0)


func _process(dt: float) -> void:
	if actor == null:
		return
	_images += 1
	if _images <= 3:
		_maj_process()
	actor.look = PI if regard_gauche else 0.0
	var k: float = hauteur / HAUT_LOCAL
	_pivot.scale = Vector2(k, k)
	_pivot.position = Vector2(size.x * 0.5, size.y - SOUS_PIVOT * k)
	if actor.emote_t > 0.0:
		actor.emote_t = maxf(0.0, actor.emote_t - dt)
		if actor.emote_t <= 0.0:
			_maj_process()
	queue_redraw()


func _draw() -> void:
	if actor == null or actor.emote < 0 or actor.emote_t <= 0.0:
		return
	# Bulle d'emote au-dessus de la tête, qui rebondit en entrant (comme GkHud._emote_bubble).
	var age: float = GkRules.f("emote_duration") - actor.emote_t
	var k: float = clampf(age / 0.18, 0.0, 1.0) * clampf(actor.emote_t / 0.15, 0.0, 1.0)
	var r: float = hauteur * 0.17 * (k + sin(k * PI) * 0.18)
	if r < 3.0:
		return
	var tete: Vector2 = Vector2(size.x * 0.5 + hauteur * 0.12, size.y - hauteur * 0.9)
	GkDraw.emote_bubble(self, tete + Vector2(0.5, -1).normalized() * (r + 10.0 * k), tete, actor.emote, r)
