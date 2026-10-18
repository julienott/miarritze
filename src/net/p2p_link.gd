class_name P2PLink
extends Node
## Lien pair-à-pair WebRTC (SPEC §9.2) : deux data channels négociés
## (« input » non fiable et non ordonné, « ctrl » fiable). L'hôte (player_id
## le plus petit) crée l'offre ; ICE envoyés par lots toutes les 300 ms ;
## échec au bout de 20 s. Chaque essai porte un numéro (« a ») : les messages
## d'un essai précédent sont ignorés ; le 2e essai peut forcer le relais TURN.

signal connected
signal failed(reason: String)
signal ctrl_received(data: Dictionary)

const CONNECT_TIMEOUT: float = 20.0
const ICE_BATCH: float = 0.3
## L'hôte renvoie offre + candidats tant que l'invité n'a pas répondu (essai rattrapé en retard).
const RESEND_SECONDS: float = 3.0

var host: bool = false
var pc: WebRTCPeerConnection
var ch_input: WebRTCDataChannel
var ch_ctrl: WebRTCDataChannel
var signaling: Signaling
var is_connected: bool = false
var attempt: int = 1
## Types de candidats vus (h = direct, s = via STUN, r = relais) : diagnostic d'échec.
var _local_types: Dictionary = {}
var _remote_types: Dictionary = {}
var _offer_sdp: String = ""
var _all_ice: Array = []
var _resend_t: float = 0.0

var _pending_ice: Array = []
var _ice_t: float = 0.0
var _elapsed: float = 0.0
var _gave_up: bool = false
var _remote_set: bool = false
var _early_ice: Array = []
var _disc_t: float = 0.0


func start(p_host: bool, p_signaling: Signaling, ice_servers: Array, p_attempt: int = 1, relay_only: bool = false) -> void:
	host = p_host
	signaling = p_signaling
	attempt = p_attempt
	signaling.message_received.connect(_on_signal)
	pc = WebRTCPeerConnection.new()
	var cfg: Dictionary = {"iceServers": ice_servers}
	if relay_only:
		cfg["iceTransportPolicy"] = "relay"
	var err: Error = pc.initialize(cfg)
	if err != OK:
		_fail("webrtc_init")
		return
	ch_input = pc.create_data_channel("input", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	ch_ctrl = pc.create_data_channel("ctrl", {"negotiated": true, "id": 2})
	pc.session_description_created.connect(func(type: String, sdp: String) -> void:
		pc.set_local_description(type, sdp)
		if type == "offer":
			_offer_sdp = sdp
		signaling.send({"kind": type, "sdp": sdp, "a": attempt}))
	pc.ice_candidate_created.connect(func(media: String, index: int, cname: String) -> void:
		_note_type(_local_types, cname)
		_all_ice.append([media, index, cname])
		_pending_ice.append([media, index, cname]))
	if host:
		pc.create_offer()


func _on_signal(payload: Dictionary) -> void:
	if pc == null or _gave_up or int(payload.get("a", 1)) != attempt:
		return
	var kind: String = str(payload.get("kind", ""))
	match kind:
		"offer", "answer":
			if _remote_set:
				return     # offre renvoyée en double : déjà prise
			pc.set_remote_description(kind, str(payload.get("sdp", "")))
			_remote_set = true
			for c: Variant in _early_ice:
				var arr: Array = c
				pc.add_ice_candidate(str(arr[0]), int(arr[1]), str(arr[2]))
			_early_ice.clear()
		"ice":
			for c: Variant in payload.get("list", []):
				var arr: Array = c
				_note_type(_remote_types, str(arr[2]))
				if _remote_set:
					pc.add_ice_candidate(str(arr[0]), int(arr[1]), str(arr[2]))
				else:
					_early_ice.append(arr)


func _process(delta: float) -> void:
	if pc == null:
		return
	pc.poll()
	_ice_t += delta
	if _ice_t >= ICE_BATCH and not _pending_ice.is_empty():
		_ice_t = 0.0
		signaling.send({"kind": "ice", "list": _pending_ice.duplicate(), "a": attempt})
		_pending_ice.clear()
	if not is_connected:
		_elapsed += delta
		_resend_t += delta
		if host and not _remote_set and _offer_sdp != "" and _resend_t >= RESEND_SECONDS:
			_resend_t = 0.0
			signaling.send({"kind": "offer", "sdp": _offer_sdp, "a": attempt})
			if not _all_ice.is_empty():
				signaling.send({"kind": "ice", "list": _all_ice.duplicate(), "a": attempt})
		if ch_input != null and ch_ctrl != null \
				and ch_input.get_ready_state() == WebRTCDataChannel.STATE_OPEN \
				and ch_ctrl.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			is_connected = true
			signaling.active = false     # plus de polling une fois reliés
			connected.emit()
		elif _elapsed > CONNECT_TIMEOUT and not _gave_up:
			_fail("timeout")
		return
	while ch_ctrl.get_available_packet_count() > 0:
		var raw: PackedByteArray = ch_ctrl.get_packet()
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			ctrl_received.emit(parsed)
	var cs: int = pc.get_connection_state()
	if cs == WebRTCPeerConnection.STATE_FAILED or cs == WebRTCPeerConnection.STATE_CLOSED:
		_fail("disconnected")
	elif cs == WebRTCPeerConnection.STATE_DISCONNECTED:
		# Souvent passager en 4G : on laisse 5 s à la connexion pour revenir.
		_disc_t += delta
		if _disc_t > 5.0:
			_fail("disconnected")
	else:
		_disc_t = 0.0


func send_input(bytes: PackedByteArray) -> void:
	if is_connected and ch_input.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		ch_input.put_packet(bytes)


func poll_inputs() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if ch_input == null:
		return out
	while ch_input.get_available_packet_count() > 0:
		out.append(ch_input.get_packet())
	return out


func send_ctrl(data: Dictionary) -> void:
	if ch_ctrl != null and ch_ctrl.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		ch_ctrl.put_packet(JSON.stringify(data).to_utf8_buffer())


func close() -> void:
	if pc != null:
		pc.close()
	is_connected = false


func _note_type(into: Dictionary, cand: String) -> void:
	for t: String in ["host", "srflx", "prflx", "relay"]:
		if cand.contains(" typ %s" % t):
			into[t.substr(0, 1)] = true


func _types(d: Dictionary) -> String:
	var k: Array = d.keys()
	k.sort()
	return "".join(k) if not k.is_empty() else "0"


func _fail(reason: String) -> void:
	if _gave_up:
		return
	_gave_up = true
	# ex. timeout_a1_lhs_rh : essai 1, chez moi direct+STUN, chez l'autre direct seulement.
	reason = "%s_a%d_l%s_r%s" % [reason, attempt, _types(_local_types), _types(_remote_types)]
	var browser: String = ""
	if OS.has_feature("web"):
		browser = str(JavaScriptBridge.eval("navigator.userAgent.substring(0, 60)", true))
	Api.call_api(HTTPClient.METHOD_POST, "/net/report", {"kind": reason, "browser": browser},
		func(_ok: bool, _c: int, _d: Variant) -> void: pass, false)
	failed.emit(reason)
