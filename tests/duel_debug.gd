extends SceneTree
func _initialize() -> void:
	var sim: FightSim = FightSim.new()
	sim.setup(FighterDb.get_def("kaio"), FighterDb.get_def("patxi"), {"seed": 1, "ai": [92, 62]})
	var t0: int = Time.get_ticks_msec()
	for n: int in 6000:
		sim.step(0, 0)
		if n % 500 == 0:
			print("f%d ph%d r%d t%d hp %d/%d st %d/%d proj %d ms %d" % [n, sim.phase, sim.round_num, sim.timer, sim.f[0].health, sim.f[1].health, sim.f[0].state, sim.f[1].state, sim.projectiles.size(), Time.get_ticks_msec() - t0])
		if sim.is_over():
			print("fin ", n, " winner ", sim.winner)
			break
	quit()
