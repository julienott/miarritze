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
	UiKit.menu_column(self, [
		UiKit.button("Revanche", VersusMode.rematch),
		UiKit.button("Changer de combattant", func() -> void:
			SceneRouter.goto(&"fighter_select", {"mode": "versus"}), 150),
		UiKit.button("Menu", func() -> void: SceneRouter.goto(&"main_menu")),
	], 80)
