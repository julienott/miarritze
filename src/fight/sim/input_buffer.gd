class_name InputBuffer
extends RefCounted
## Historique des entrées d'un joueur (32 frames) : fronts montants, buffer
## de 8 frames, double tape, manipulations « à l'ancienne » (SPEC §8.3).
## Les entrées sont stockées en directions ABSOLUES ; la conversion
## avant/arrière se fait à la lecture avec l'orientation courante.

const SIZE: int = 32

var history: PackedInt32Array = PackedInt32Array()
var head: int = 0                       # nombre total d'entrées poussées
## Frame (head) du dernier appui consommé, par bouton (bits 4..7).
var consumed: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


func _init() -> void:
	history.resize(SIZE)


func push(mask: int) -> void:
	history[head % SIZE] = mask
	head += 1


## Masque d'il y a `ago` frames (0 = la plus récente).
func at(ago: int) -> int:
	if ago >= head or ago >= SIZE:
		return 0
	return history[(head - 1 - ago) % SIZE]


func current() -> int:
	return at(0)


func held(bit: int) -> bool:
	return (at(0) & bit) != 0


## Vrai si `bit` a été pressé (front montant) dans les `window` dernières
## frames et que cet appui n'a pas encore été consommé.
func pressed(bit: int, window: int = SimConst.INPUT_BUFFER) -> bool:
	return press_age(bit, window) >= 0


## Âge (0 = cette frame) de l'appui non consommé le plus récent, -1 sinon.
func press_age(bit: int, window: int) -> int:
	var slot: int = _slot(bit)
	for ago: int in mini(window, SIZE - 1):
		if ago >= head:
			break
		if (at(ago) & bit) != 0 and (at(ago + 1) & bit) == 0:
			var frame_id: int = head - ago
			if slot >= 0 and frame_id <= consumed[slot]:
				return -1
			return ago
	return -1


## Marque l'appui le plus récent de `bit` comme utilisé.
func consume(bit: int) -> void:
	var slot: int = _slot(bit)
	if slot >= 0:
		consumed[slot] = head


## Direction relative façon pavé numérique (5 = neutre, 6 = avant…).
static func numpad(mask: int, facing: int) -> int:
	var fwd: int = SimConst.RIGHT if facing > 0 else SimConst.LEFT
	var back: int = SimConst.LEFT if facing > 0 else SimConst.RIGHT
	var h: int = 0
	if (mask & fwd) != 0 and (mask & back) == 0:
		h = 1
	elif (mask & back) != 0 and (mask & fwd) == 0:
		h = -1
	var v: int = 0
	if (mask & SimConst.UP) != 0 and (mask & SimConst.DOWN) == 0:
		v = 1
	elif (mask & SimConst.DOWN) != 0 and (mask & SimConst.UP) == 0:
		v = -1
	return 5 + h + v * 3


func dir_now(facing: int) -> int:
	return numpad(at(0), facing)


## Double appui sur avant (course) : avant pressé maintenant, relâché puis
## pressé une première fois dans la fenêtre.
func double_tap_forward(facing: int) -> bool:
	var fwd: int = SimConst.RIGHT if facing > 0 else SimConst.LEFT
	if (at(0) & fwd) == 0 or (at(1) & fwd) != 0:
		return false
	var released: bool = false
	for ago: int in range(1, mini(SimConst.DOUBLE_TAP_WINDOW, SIZE - 1)):
		var on: bool = (at(ago) & fwd) != 0
		if not on:
			released = true
		elif released:
			return true
	return false


## Manipulation classique : la suite `dirs` (pavé num.) apparaît dans
## l'ordre dans les MOTION_WINDOW dernières frames, la dernière direction
## étant tenue au plus tard 4 frames avant maintenant.
func motion(dirs: PackedInt32Array, facing: int) -> bool:
	if dirs.is_empty():
		return false
	var want: int = dirs.size() - 1
	var window: int = mini(SimConst.MOTION_WINDOW, SIZE - 1)
	for ago: int in window:
		if ago >= head:
			break
		var d: int = numpad(at(ago), facing)
		if d == dirs[want]:
			want -= 1
			if want < 0:
				return true
		elif want == dirs.size() - 1 and ago > 4:
			return false
	return false


func write(buf: StreamPeerBuffer) -> void:
	for i: int in SIZE:
		buf.put_u8(history[i] & 0xFF)
	buf.put_32(head)
	for i: int in 4:
		buf.put_32(consumed[i])


func read(buf: StreamPeerBuffer) -> void:
	for i: int in SIZE:
		history[i] = buf.get_u8()
	head = buf.get_32()
	for i: int in 4:
		consumed[i] = buf.get_32()


static func _slot(bit: int) -> int:
	match bit:
		SimConst.PUNCH:
			return 0
		SimConst.KICK:
			return 1
		SimConst.SPECIAL:
			return 2
		SimConst.GUARD:
			return 3
	return -1
