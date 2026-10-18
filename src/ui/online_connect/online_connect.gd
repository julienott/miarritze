extends Control
## Mise en relation (SPEC §9.2) : attend la map choisie par l'hôte, échange les
## choix de combattants par la signalisation (« hello »), ouvre le lien
## WebRTC, mesure le RTT (délai d'entrée), puis lance le combat.

const PING_COUNT: int = 4
const POLL_SECONDS: float = 1.0

var _label: Label
var _poll_t: float = 0.0
var _connecting: bool = false
var _linked: bool = false
var _hello_sent: bool = false
var _pings: Array[float] = []
var _ping_sent_at: float = 0.0
var _done: bool = false
var _spin: float = 0.0
var _lauburu: Sprite2D


func _ready() -> void:
	UiKit.backdrop(self, "bg_menu", 0.5)
	var opp: Dictionary = OnlineMode.current.get("opponent", {})
	var who: String = str(opp.get("pseudo", "ton copain"))
	_label = UiKit.label(("Connexion à %s…" if OnlineMode.is_host() else "%s choisit la map…") % who, 8, UiKit.C_LINEN)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	if ResourceLoader.exists("res://assets/ui/icon_lauburu.png"):
		_lauburu = Sprite2D.new()
		_lauburu.texture = load("res://assets/ui/icon_lauburu.png")
		_lauburu.position = Vector2(get_viewport_rect().size.x * 0.5, 80)
		_lauburu.scale = Vector2(2, 2)
		add_child(_lauburu)
	var cancel: Button = UiKit.button("Annuler", OnlineMode.leave, 80)
	cancel.position = Vector2(4, 4)
	add_child(cancel)
	cancel.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _done:
		get_viewport().set_input_as_handled()
		OnlineMode.leave()


func _process(delta: float) -> void:
	_spin += delta
	if _lauburu != null:
		_lauburu.rotation = snappedf(_spin * 4.0, PI / 8.0)
	if _done:
		return
	if not _connecting:
		_poll_t += delta
		if _poll_t >= POLL_SECONDS:
			_poll_t = 0.0
			Api.call_api(HTTPClient.METHOD_POST, "/presence", {"status": "busy"}, _on_presence)
		return
	if _linked and _pings.size() >= PING_COUNT and not OnlineMode.their_pick.is_empty():
		_start_fight()


func _on_presence(ok: bool, _c: int, data: Variant) -> void:
	if not ok or not data is Dictionary or _connecting:
		return
	var m: Variant = (data as Dictionary).get("match")
	if not m is Dictionary:
		_label.text = "Ton copain est parti…"
		get_tree().create_timer(2.0).timeout.connect(OnlineMode.leave)
		_done = true
		return
	var md: Dictionary = m
	if str(md.get("state", "")) == "signaling" and md.get("stage") != null:
		OnlineMode.current = md
		_label.text = "Map : %s — on relie vos appareils…" % str(Roster.STAGE_NAMES.get(str(md["stage"]), md["stage"]))
		_connect()


func _connect() -> void:
	_connecting = true
	OnlineMode.signaling = Signaling.new()
	OnlineMode.signaling.setup(int(OnlineMode.current.get("match_id", 0)))
	Api.add_child(OnlineMode.signaling)
	OnlineMode.signaling.message_received.connect(func(payload: Dictionary) -> void:
		if str(payload.get("kind", "")) == "hello":
			OnlineMode.their_pick = payload.get("pick", {}))
	OnlineMode.signaling.send({"kind": "hello", "pick": OnlineMode.my_pick})
	Api.call_api(HTTPClient.METHOD_GET, "/net/config", {}, func(ok: bool, _c: int, data: Variant) -> void:
		var ice: Array = (data as Dictionary).get("ice_servers", []) if ok and data is Dictionary else []
		OnlineMode.link = P2PLink.new()
		Api.add_child(OnlineMode.link)
		OnlineMode.link.connected.connect(_on_linked)
		OnlineMode.link.failed.connect(_on_failed)
		OnlineMode.link.ctrl_received.connect(_on_ctrl)
		OnlineMode.link.ctrl_received.connect(OnlineMode.handle_ctrl)
		OnlineMode.link.start(OnlineMode.is_host(), OnlineMode.signaling, ice), false)


func _on_linked() -> void:
	_linked = true
	_label.text = "Reliés ! Mesure de la connexion…"
	_send_ping()


func _send_ping() -> void:
	_ping_sent_at = Time.get_ticks_msec()
	OnlineMode.link.send_ctrl({"t": "ping"})


func _on_ctrl(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"ping":
			OnlineMode.link.send_ctrl({"t": "pong"})
		"pong":
			_pings.append(Time.get_ticks_msec() - _ping_sent_at)
			if _pings.size() < PING_COUNT:
				_send_ping()


func _on_failed(_reason: String) -> void:
	_done = true
	_label.text = "Impossible de relier vos deux appareils.\nEssayez sur le même Wi-Fi, ou réessayez."
	get_tree().create_timer(4.0).timeout.connect(OnlineMode.leave)


func _start_fight() -> void:
	_done = true
	var rtt: float = 0.0
	for p: float in _pings:
		rtt += p
	rtt /= maxf(_pings.size(), 1)
	OnlineMode.my_pick["delay"] = RollbackSession.delay_for_rtt(rtt)
	InputHub.set_solo()
	if bool(OnlineMode.qa.get("bot", false)):
		InputHub.set_sources(0, [BotSource.new()])
	SceneRouter.goto(&"fight", OnlineMode.fight_params())
