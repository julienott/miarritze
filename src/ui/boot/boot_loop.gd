class_name BootLoop
extends RefCounted
## QA « session longue » (SPEC §14.3) : combats IA contre IA en boucle,
## combattants et stages au hasard, pour surveiller la mémoire WASM.

static var count: int = 0


static func next_fight(_result: Dictionary = {}) -> void:
	count += 1
	var ids: PackedStringArray = Roster.FIGHTERS
	var p1: String = ids[randi() % ids.size()]
	var p2: String = ids[randi() % ids.size()]
	var stage: String = Roster.STAGES[randi() % Roster.STAGES.size()]
	print("autoloop: combat %d — %s vs %s à %s" % [count, p1, p2, stage])
	SceneRouter.goto(&"fight", {"p1": p1, "p2": p2, "stage": stage, "ai": [70, 70],
		"seed": randi(), "on_end": BootLoop.next_fight, "rounds": 1})
