class_name RollbackSession
extends RefCounted
## Session de combat en ligne : délai d'entrée + rollback (SPEC §8.6).
##
## - L'entrée locale de la frame f est jouée à f + delay.
## - L'entrée distante inconnue est prédite (= dernière entrée connue).
## - À l'arrivée d'une entrée différente de la prédiction : load_state(f)
##   puis resimulation jusqu'au présent (8 frames max) ; au-delà, la sim
##   locale attend (stall).
## - Paquet d'entrée (canal non fiable) : [u8 1][u8 époque][u32 frame][u8 n][n × u8][u32 ack],
##   les 8 dernières entrées locales à chaque tick (redondance).
## - Checksum toutes les 60 frames confirmées : [u8 2][u8 époque][u32 frame][u32 checksum].

const MAX_ROLLBACK: int = 8
const HISTORY: int = 64
const CHECK_EVERY: int = 60

var sim: FightSim
var local_slot: int = 0
var delay: int = 2
## Époque (octet) : distingue les paquets d'une revanche de ceux de la partie précédente.
var epoch: int = 0

## Frame suivante à simuler.
var frame: int = 0
var local_inputs: Dictionary = {}     # frame -> masque
var remote_inputs: Dictionary = {}    # frame -> masque (reçu)
var used_remote: Dictionary = {}      # frame -> masque utilisé (prédit ou reçu)
var states: Dictionary = {}           # frame -> état AVANT la frame
var last_remote: int = -1             # plus grande frame distante contiguë reçue
var remote_ack: int = -1
var rollbacks: int = 0
var stalled: bool = false
var desync: bool = false
var desync_frame: int = -1
var _local_checks: Dictionary = {}
var _remote_checks: Dictionary = {}
var _last_checked: int = -1
var max_rollback_seen: int = 0
## Événements de la sim produits par chaque tick simulé (y compris pendant
## une resimulation) : la vue les déduplique par (frame, type, acteur).
var events_out: Array[PackedInt32Array] = []


func setup(p_sim: FightSim, p_local_slot: int, p_delay: int, p_epoch: int = 0) -> void:
	sim = p_sim
	epoch = p_epoch & 0xFF
	local_slot = p_local_slot
	delay = clampi(p_delay, 1, 4)
	for f: int in delay:
		local_inputs[f] = 0
	frame = 0


## Délai adapté au RTT mesuré : clamp(ceil(RTT/2 / 16,7 ms), 1, 4).
static func delay_for_rtt(rtt_ms: float) -> int:
	return clampi(ceili(rtt_ms * 0.5 / 16.7), 1, 4)


## Un tick : entrée locale échantillonnée → paquet à envoyer (ou vide si stall).
func tick(local_mask: int) -> PackedByteArray:
	_scan_end()
	stalled = frame - (last_remote + 1) >= MAX_ROLLBACK
	if stalled:
		return _input_packet()
	local_inputs[frame + delay] = local_mask & 0xFF
	_advance()
	return _input_packet()


func _advance() -> void:
	states[frame] = sim.save_state()
	var remote: int = _remote_for(frame)
	used_remote[frame] = remote
	_step(frame, remote)
	frame += 1
	states.erase(frame - HISTORY)
	local_inputs.erase(frame - HISTORY)
	used_remote.erase(frame - HISTORY)
	remote_inputs.erase(frame - HISTORY)


func _step(f: int, remote: int) -> void:
	var local: int = int(local_inputs.get(f, 0))
	if local_slot == 0:
		sim.step(local, remote)
	else:
		sim.step(remote, local)
	events_out.append_array(sim.events)


func take_events() -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = events_out
	events_out = []
	return out


func _remote_for(f: int) -> int:
	if remote_inputs.has(f):
		return remote_inputs[f]
	# Prédiction : dernière entrée distante connue.
	return int(remote_inputs.get(last_remote, 0)) if last_remote >= 0 else 0


## Paquet reçu de l'adversaire (entrées ou checksum).
func receive(bytes: PackedByteArray) -> void:
	if bytes.size() < 1:
		return
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = bytes
	var type: int = buf.get_u8()
	if bytes.size() < 2 or buf.get_u8() != epoch:
		return
	if type == 1:
		var start: int = buf.get_u32()
		var n: int = buf.get_u8()
		var first_wrong: int = -1
		for i: int in n:
			var f: int = start + i
			var mask: int = buf.get_u8()
			if remote_inputs.has(f) or f < frame - HISTORY + 1:
				continue
			remote_inputs[f] = mask
			if f < frame and int(used_remote.get(f, -1)) != mask and (first_wrong < 0 or f < first_wrong):
				first_wrong = f
		remote_ack = maxi(remote_ack, buf.get_u32())
		while remote_inputs.has(last_remote + 1):
			last_remote += 1
		if first_wrong >= 0:
			_rollback(first_wrong)
		_check_confirmed()
	elif type == 2:
		var cf: int = buf.get_u32()
		_remote_checks[cf] = buf.get_u32()
		_compare(cf)


func _rollback(from_frame: int) -> void:
	if not states.has(from_frame):
		return
	rollbacks += 1
	max_rollback_seen = maxi(max_rollback_seen, frame - from_frame)
	var target: int = frame
	sim.load_state(states[from_frame])
	frame = from_frame
	while frame < target:
		states[frame] = sim.save_state()
		var remote: int = _remote_for(frame)
		used_remote[frame] = remote
		_step(frame, remote)
		frame += 1


## Frame confirmée = toutes les entrées des deux joueurs connues.
func confirmed_frame() -> int:
	return mini(frame - 1, last_remote)


func _check_confirmed() -> void:
	_scan_end()
	var cf: int = confirmed_frame()
	var next_check: int = (_last_checked / CHECK_EVERY + 1) * CHECK_EVERY if _last_checked >= 0 else CHECK_EVERY
	while next_check <= cf and states.has(next_check + 1):
		# Checksum de l'état à la fin de la frame `next_check`.
		_local_checks[next_check] = Fnv.hash32(states[next_check + 1])
		_last_checked = next_check
		for k: int in 3:   # canal non fiable : 3 envois
			pending_checks.append(next_check)
		_compare(next_check)
		next_check += CHECK_EVERY


var pending_checks: Array[int] = []
## Fin de match déterministe : première frame CONFIRMÉE où la sim est en
## phase terminée, et checksum de l'état juste après (rapporté au serveur).
var final_frame: int = -1
var final_checksum: int = -1
var _scanned: int = -1


func _scan_end() -> void:
	var cf: int = confirmed_frame()
	while _scanned < cf and final_frame < 0:
		# L'état « après la frame » n'existe qu'une fois la frame suivante
		# entamée : on attend plutôt que de sauter la frame.
		if not states.has(_scanned + 2):
			break
		_scanned += 1
		var after: PackedByteArray = states[_scanned + 1]
		if FightSim.phase_of_state(after) == SimConst.PH_END:
			final_frame = _scanned
			final_checksum = Fnv.hash32(after)


## Paquets de checksum à envoyer (canal d'entrées, redondants une fois).
func take_check_packets() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for cf: int in pending_checks:
		var buf: StreamPeerBuffer = StreamPeerBuffer.new()
		buf.put_u8(2)
		buf.put_u8(epoch)
		buf.put_u32(cf)
		buf.put_u32(int(_local_checks[cf]))
		out.append(buf.data_array)
	pending_checks.clear()
	return out


func _compare(cf: int) -> void:
	if _local_checks.has(cf) and _remote_checks.has(cf) and int(_local_checks[cf]) != int(_remote_checks[cf]):
		if not desync:
			desync = true
			desync_frame = cf


func _input_packet() -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	var last: int = frame + delay - 1
	var first: int = maxi(0, last - 7)
	buf.put_u8(1)
	buf.put_u8(epoch)
	buf.put_u32(first)
	buf.put_u8(last - first + 1)
	for f: int in range(first, last + 1):
		buf.put_u8(int(local_inputs.get(f, 0)))
	buf.put_u32(maxi(last_remote, 0))
	return buf.data_array
