extends Control
## Résultats d'un match (SPEC §10.5) : le vainqueur en `win`, l'autre en
## `ko`, les stats du match ; Revanche / Changer de combattant / Menu.


func _ready() -> void:
	var params: Dictionary = SceneRouter.params
	var result: Dictionary = params.get("result", {})
	var fight: Dictionary = params.get("fight", {})
	UiKit.backdrop(self, "bg_beach", 0.35)
	AudioManager.play_music(&"victory")
	var w: float = get_viewport_rect().size.x
	var winner: int = int(result.get("winner", -1))
	for p: int in 2:
		var id: String = str(fight.get("p%d" % (p + 1), "louis"))
		var anim: String = "win" if winner == p else ("ko" if winner >= 0 else "idle")
		var view: FighterView = UiKit.fighter_preview(id, int(fight.get("c%d" % (p + 1), 0)), anim, 1 if p == 0 else -1)
		view.position = Vector2(w * (0.22 if p == 0 else 0.78), 196)
		add_child(view)
	var head_text: String = "ÉGALITÉ !"
	if winner >= 0:
		var vs_cpu: bool = int((fight.get("ai", [0, 0]) as Array)[1]) > 0
		if vs_cpu:
			head_text = "TU GAGNES !" if winner == 0 else "L'ORDI GAGNE !"
		elif str(fight.get("p1", "")) == str(fight.get("p2", "")):
			head_text = "J%d GAGNE !" % (winner + 1)   # miroir : le nom ne dit pas qui
		else:
			head_text = "%s GAGNE !" % Roster.display_name(str(fight.get("p%d" % (winner + 1), ""))).to_upper()
	var head: Label = UiKit.title(head_text)
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 10
	add_child(head)
	var rounds: Array = result.get("rounds", [0, 0])
	var stats: Label = UiKit.label("Rounds %d - %d\n%s%s" % [int(rounds[0]), int(rounds[1]),
		"PARFAIT !\n" if bool(result.get("perfect", false)) else "",
		"Finish réussi !" if int(result.get("finisher", 0)) != 0 else ""], 8, UiKit.C_GOLD)
	var unlocks: Array = params.get("unlocks", [])
	if not unlocks.is_empty():
		stats.text += "\nDébloqué : " + ", ".join(unlocks)
	stats.set_anchors_preset(Control.PRESET_TOP_WIDE)
	stats.position.y = 34
	add_child(stats)
	if str(params.get("mode", "")) == "online":
		_online_buttons(params)
		return
	UiKit.menu_column(self, [
		UiKit.button("Revanche", VersusMode.rematch),
		UiKit.button("Changer de combattant", func() -> void:
			SceneRouter.goto(&"fighter_select", {"mode": "versus"}), 150),
		UiKit.button("Menu", func() -> void: SceneRouter.goto(&"main_menu")),
	], 80)


# ------------------------------------------------------------------ en ligne

var _rematch_label: Label
var _my_vote: bool = false


func _online_buttons(params: Dictionary) -> void:
	var extra: String = "Classement mis à jour !" if bool(params.get("rated", false)) else \
		("Match nul technique : pas de points" if bool(params.get("desync", false)) else "")
	_rematch_label = UiKit.label(extra, 8, UiKit.C_LINEN)
	_rematch_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_rematch_label.position.y = 60
	add_child(_rematch_label)
	UiKit.menu_column(self, [
		UiKit.button("Revanche ?", _vote_rematch),
		UiKit.button("Retour au salon", OnlineMode.leave),
	], 84)
	if OnlineMode.link != null and is_instance_valid(OnlineMode.link):
		OnlineMode.link.ctrl_received.connect(_on_ctrl)
		OnlineMode.link.failed.connect(func(_r: String) -> void: _rematch_label.text = "Ton copain est parti")
	if OnlineMode.rematch_votes.get("them", false):
		_rematch_label.text = "Ton copain veut une revanche !"
	if bool(OnlineMode.qa.get("rematch", false)):
		_vote_rematch()


func _on_ctrl(d: Dictionary) -> void:
	if str(d.get("t", "")) == "rematch":
		_rematch_label.text = "Ton copain veut une revanche !"
		_try_rematch.call_deferred()


func _vote_rematch() -> void:
	if _my_vote:
		return
	_my_vote = true
	OnlineMode.rematch_votes["me"] = true
	OnlineMode.link.send_ctrl({"t": "rematch"})
	_rematch_label.text = "En attente de ton copain…"
	_try_rematch()


## Les deux doivent accepter ; la graine avance de 1 des deux côtés.
func _try_rematch() -> void:
	if not (OnlineMode.rematch_votes.get("me", false) and OnlineMode.rematch_votes.get("them", false)):
		return
	OnlineMode.rematch_votes = {}
	# Revanche = nouveau match serveur (compté), même map, nouvelle graine.
	_rematch_label.text = "Revanche !"
	Api.call_api(HTTPClient.METHOD_POST, "/match/rematch", {"match_id": int(OnlineMode.current.get("match_id", 0))},
		func(ok: bool, _c: int, data: Variant) -> void:
			if not ok or not data is Dictionary or not (data as Dictionary).get("match") is Dictionary:
				_rematch_label.text = "Revanche impossible"
				return
			var m: Dictionary = (data as Dictionary)["match"]
			OnlineMode.current["match_id"] = int(m.get("match_id", 0))
			OnlineMode.current["seed"] = int(m.get("seed", 1))
			SceneRouter.goto(&"fight", OnlineMode.fight_params()))
