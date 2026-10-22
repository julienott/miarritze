class_name BkMapChunk
extends Node2D
## Un morceau du dessin de la carte (une zone, ou les murs entre zones) : dessiné une fois,
## et Godot ne l'affiche que s'il est à l'écran.

var map: BkMap
var zone: int = -1
var items: Array = []


func _draw() -> void:
	map.draw_chunk(self, zone, items)
