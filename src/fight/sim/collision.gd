class_name Collision
extends RefCounted
## Boîtes AABB en sous-pixels. Une boîte locale [x, y, w, h] est relative au
## pied, x vers l'avant ; `world()` la place selon la position et l'orientation.


static func world(box: PackedInt32Array, px: int, py: int, facing: int) -> PackedInt32Array:
	var bx: int = px + box[0] if facing > 0 else px - box[0] - box[2]
	return PackedInt32Array([bx, py + box[1], box[2], box[3]])


static func overlap(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] \
		and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


## Centre horizontal d'une boîte monde.
static func center_x(box: PackedInt32Array) -> int:
	return box[0] + box[2] / 2
