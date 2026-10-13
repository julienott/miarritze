class_name VersusMode
extends RefCounted
## Versus local (SPEC §3.3) : J1 et J2 sur le même appareil.

static var last: Dictionary = {}


static func on_fight_end(result: Dictionary) -> void:
	# Le profil actif est J1 sur cet appareil.
	var unlocks: Array[String] = Profiles.record_fight(str(last.get("p1", "louis")),
		int(result.get("winner", -1)) == 0, str(last.get("stage", "")),
		int(result.get("finisher", 0)) != 0 and int(result.get("winner", -1)) == 0,
		bool(result.get("perfect", false)) and int(result.get("winner", -1)) == 0)
	SceneRouter.goto(&"results", {"mode": "versus", "result": result, "fight": last, "unlocks": unlocks})


static func rematch() -> void:
	if int((last.get("ai", [0, 0]) as Array)[1]) > 0:
		InputHub.set_solo()
	else:
		InputHub.set_versus()
	SceneRouter.goto(&"fight", last)
