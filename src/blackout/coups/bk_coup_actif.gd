class_name BkCoupActif
extends RefCounted
## Un coup spécial lancé (GDD-BLACKOUT.md §4), base des familles (src/blackout/coups/familles/) : le
## moteur (BkCoups) crée une instance de la famille du coup, lui demande s'il est `possible` (sinon la
## recharge n'est pas consommée), le `demarre`, puis le fait vivre (`maj`) et le dessine (`dessine`)
## jusqu'à ce que `maj` rende faux. Une famille est réutilisable : tout ce qui change d'un coup à
## l'autre vient des données (data/blackout/coups.json : portee, duree, effets, params).

var moteur: BkCoups
var game: BkGame
var lanceur: BkActor
var coup: Dictionary = {}
## Direction du lancer : direction de marche (regard), ou choisie par l'IA.
var dir: Vector2 = Vector2.RIGHT
## Secondes depuis le départ.
var t: float = 0.0


func init(p_moteur: BkCoups, p_lanceur: BkActor, p_coup: Dictionary, p_dir: Vector2) -> void:
	moteur = p_moteur
	game = p_moteur.game
	lanceur = p_lanceur
	coup = p_coup
	dir = p_dir.normalized() if p_dir.length() > 0.01 else Vector2.from_angle(p_lanceur.look)


## Paramètre propre à la famille (coups.json → params).
func param(cle: String, defaut: Variant = null) -> Variant:
	return (coup.get("params", {}) as Dictionary).get(cle, defaut)


func duree() -> float:
	return float(coup.get("duree", 0.0))


func portee_px() -> float:
	return float(coup.get("portee", 0.0)) * game.map.tile


## Le coup peut-il partir maintenant ? Faux : rien ne se passe et la recharge n'est pas consommée.
func possible() -> bool:
	return true


## Pourquoi il ne part pas (message du joueur local), si `possible` est faux.
func raison() -> String:
	return ""


func demarre() -> void:
	pass


## Une image de jeu ; faux quand le coup est fini.
func maj(_dt: float) -> bool:
	return false


## Dessin dans le monde (calque non assombri). `vue` : {chasseur (le joueur local est le chasseur),
## fantome (spectateur), local (BkActor)}.
func dessine(_ci: CanvasItem, _vue: Dictionary) -> void:
	pass


## IA : faut-il lancer maintenant ? `ctx` : {menace (chassé en danger), cible_probable (chasseur)}.
## Peut choisir `dir`.
func ia_utile(_ctx: Dictionary) -> bool:
	return false


## Fin forcée (fin de round) : remettre le lanceur dans un état normal.
func interrompt() -> void:
	pass
