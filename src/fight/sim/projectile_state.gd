class_name ProjectileState
extends RefCounted
## Projectile ou piège en vol (entiers uniquement).

const FIELDS: PackedStringArray = [
	"id", "owner", "def", "x", "y", "vx", "vy", "facing", "life", "age",
	"hits_left", "last_hit", "returning", "bonus",
]

var id: int = 0
var owner: int = 0
var def: int = 0
var x: int = 0
var y: int = 0
var vx: int = 0
var vy: int = 0
var facing: int = 1
var life: int = 0
var age: int = 0
var hits_left: int = 1
var last_hit: int = -100
var returning: int = 0
var bonus: int = 0


func write(buf: StreamPeerBuffer) -> void:
	for field: String in FIELDS:
		buf.put_32(int(get(field)))


func read(buf: StreamPeerBuffer) -> void:
	for field: String in FIELDS:
		set(field, buf.get_32())
