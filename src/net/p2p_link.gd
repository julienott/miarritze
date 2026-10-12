class_name P2PLink
extends Node
## Lien pair-à-pair WebRTC (SPEC §9.2) : deux data channels négociés
## (« input » non fiable et non ordonné, « ctrl » fiable). L'hôte (player_id
## le plus petit) crée l'offre ; ICE envoyés par lots toutes les 300 ms ;
## échec au bout de 15 s.

signal connected
signal failed(reason: String)
signal ctrl_received(data: Dictionary)

const CONNECT_TIMEOUT: float = 15.0
const ICE_BATCH: float = 0.3

var host: bool = false
var pc: WebRTCPeerConnection
var ch_input: WebRTCDataChannel
var ch_ctrl: WebRTCDataChannel
var signaling: Signaling
var is_connected: bool = false

var _pending_ice: Array = []
var _ice_t: float = 0.0
var _elapsed: float = 0.0
var _gave_up: bool = false
var _remote_set: bool = false
var _early_ice: Array = []
var _disc_t: float = 0.0


func start(p_host: bool, p_signaling: Signaling, ice_servers: Array) -> void:
	host = p_host
	signaling = p_signaling
	signaling.message_received.connect(_on_signal)
	pc = WebRTCPeerConnection.new()
	var err: Error = pc.initialize({"iceServers": ice_servers})
	if err != OK:
		_fail("webrtc_init")
		return
	ch_input = pc.create_data_channel("input", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	ch_ctrl = pc.create_data_channel("ctrl", {"negotiated": true, "id": 2})
	pc.session_description_created.connect(func(type: String, sdp: String) -> void:
		pc.set_local_description(type, sdp)
		signaling.send({"kind": type, "sdp": sdp}))
	pc.ice_candidate_created.connect(func(media: String, index: int, cname: String) -> void:
		_pending_ice.append([media, index, cname]))
	if host:
		pc.create_offer()


func _on_signal(payload: Dictionary) -> void:
	var kind: String = str(payload.get("kind", ""))
	match kind:
		"offer", "answer":
			pc.set_remote_description(kind, str(payload.get("sdp", "")))
			_remote_set = true
			for c: Variant in _early_ice:
				var arr: Array = c
				pc.add_ice_candidate(str(arr[0]), int(arr[1]), str(arr[2]))
			_early_ice.clear()
		"ice":
			for c: Variant in payload.get("list", []):
				var arr: Array = c
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
		signaling.send({"kind": "ice", "list": _pending_ice.duplicate()})
		_pending_ice.clear()
	if not is_connected:
		_elapsed += delta
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


func _fail(reason: String) -> void:
	if _gave_up:
		return
	_gave_up = true
	var browser: String = ""
	if OS.has_feature("web"):
		browser = str(JavaScriptBridge.eval("navigator.userAgent.substring(0, 60)", true))
	Api.call_api(HTTPClient.METHOD_POST, "/net/report", {"kind": reason, "browser": browser},
		func(_ok: bool, _c: int, _d: Variant) -> void: pass, false)
	failed.emit(reason)
