class_name VersusMode
extends RefCounted
## Versus local (SPEC §3.3) : J1 et J2 sur le même appareil.

static var last: Dictionary = {}


static func on_fight_end(result: Dictionary) -> void:
	SceneRouter.goto(&"results", {"mode": "versus", "result": result, "fight": last})


static func rematch() -> void:
	InputHub.set_versus()
	SceneRouter.goto(&"fight", last)
