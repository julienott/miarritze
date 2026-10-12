class_name MoveDef
extends RefCounted
## Données d'un coup (frame data §4.8), entières, immuables pendant un match.
## Construit par FighterDb depuis data.json ; distances en sous-pixels.

var name: String = ""
var index: int = 0
var anim: int = 0              # index dans SimConst.ANIMS
var startup: int = 4           # frames avant la première frame active
var active: int = 2
var recovery: int = 8
var damage: int = 0
var hitstun: int = 12
var blockstun: int = 8
var pushback: int = 6 * 256
var hit_level: int = 0         # SimConst.LVL_*
var knockdown: bool = false
var launch_vx: int = 0         # vitesse imposée à la victime (vers l'arrière d'elle)
var launch_vy: int = 0         # négatif = vers le haut
var hitstop: int = 4
var meter_gain: int = 4
var chip_permille: int = 0
## Boîtes [x, y, w, h] relatives au pied, x vers l'avant.
var hitboxes: Array[PackedInt32Array] = []
## Nombre de touches possibles pendant la fenêtre active (multi-hit).
var hits: int = 1
var rehit_interval: int = 0
## Annulations : enchaînement d'auto-combo et spéciaux.
var chain_next: int = -1
var cancel_specials: bool = false
var is_special: bool = false
var is_super: bool = false
var is_throw: bool = false
var air_ok: bool = false
## Mouvement propre : [frame, vx, vy] (vx vers l'avant). vy = 0 garde la vitesse.
var velocity: Array[PackedInt32Array] = []
## Projectile : frame de sortie, index du projectile, décalage (sous-px).
var spawn_frame: int = -1
var spawn_projectile: int = -1
var spawn_x: int = 0
var spawn_y: int = 0
## Invulnérabilité (frames du coup, incluses). -1 = aucune.
var invuln_from: int = -1
var invuln_to: int = -1
## Super-armure : nombre de coups encaissés sans interruption.
var armor: int = 0
## Effets spéciaux.
var teleport_frame: int = -1   # passe derrière l'adversaire
var pull_on_hit: int = 0       # ramène la victime vers l'attaquant (sous-px)
var steal_meter: int = 0
var counter_move: int = -1     # contre : si touché pendant la fenêtre active
var reflects: bool = false     # renvoie les projectiles adverses
var stun_on_hit: int = 0       # étourdissement (frames, la victime ne bouge plus)
var slow_on_hit: int = 0       # ralentissement (frames)
var ground_bounce: bool = false
## Classique (manip) : séquence de directions relatives (pavé num.) + bouton.
var classic_dirs: PackedInt32Array = []
var classic_button: int = 0
var pushback_self: int = 0     # recul de l'attaquant au contact
var total: int = 14


func finalize() -> void:
	total = startup + active + recovery


func is_active_frame(frame: int) -> bool:
	return frame >= startup and frame < startup + active
