class_name Signaling
extends Node
## Signalisation WebRTC par polling HTTP (SPEC §9.1) : dépose les messages
## pour l'adversaire (POST /signal) et relève les siens (GET /signal,
## toutes les 250 ms pendant la mise en relation seulement).

signal message_received(payload: Dictionary)

const POLL_SECONDS: float = 0.25

var match_id: int = 0
var _after: int = 0
var _timer: float = 0.0
var _busy: bool = false
var active: bool = true


func setup(p_match_id: int) -> void:
	match_id = p_match_id
	_after = 0


func send(payload: Dictionary) -> void:
	Api.call_api(HTTPClient.METHOD_POST, "/signal", {"match_id": match_id, "payload": payload},
		func(_ok: bool, _c: int, _d: Variant) -> void: pass)


func _process(delta: float) -> void:
	if not active or match_id <= 0 or _busy:
		return
	_timer += delta
	if _timer < POLL_SECONDS:
		return
	_timer = 0.0
	_busy = true
	Api.call_api(HTTPClient.METHOD_GET, "/signal", {"match_id": match_id, "after": _after},
		func(ok: bool, _c: int, data: Variant) -> void:
			_busy = false
			if not ok or not data is Dictionary:
				return
			for m: Variant in (data as Dictionary).get("messages", []):
				var msg: Dictionary = m
				_after = maxi(_after, int(msg.get("id", 0)))
				if msg.get("payload") is Dictionary:
					message_received.emit(msg["payload"]))
