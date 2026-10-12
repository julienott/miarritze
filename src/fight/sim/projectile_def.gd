class_name ProjectileDef
extends RefCounted
## Données d'un projectile ou d'un piège posé au sol (entières).

var name: String = ""
var anim: String = ""
var speed: int = 1024          # sous-px / frame, vers l'avant
var vy: int = 0
var gravity: int = 0
var returns: bool = false      # boomerang : fait demi-tour à mi-vie
var damage: int = 60
var hitstun: int = 16
var blockstun: int = 10
var hit_level: int = 0
var knockdown: bool = false
var launch_vx: int = 0
var launch_vy: int = 0
var hitbox: PackedInt32Array = PackedInt32Array([-8 * 256, -6 * 256, 16 * 256, 12 * 256])
var life: int = 90
var hits: int = 1
var rehit_interval: int = 20
var hitstop: int = 6
var meter_gain: int = 3
var chip_permille: int = 150
var trap: bool = false         # reste posé (gâteau, drapeau, flaque)
var slow_on_hit: int = 0
var stun_on_hit: int = 0
var pull_on_hit: int = 0       # ramène la victime vers le lanceur
var heavy: bool = false        # gagne les chocs contre les projectiles légers
var ground: bool = false       # se déplace au sol (onde basse)
