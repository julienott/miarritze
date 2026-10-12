extends SceneTree
## Équilibrage par simulation (SPEC §14.4) : tous les duels du roster,
## N matchs chacun en IA Expert contre IA Expert, headless et accéléré.
## Sortie : tests/out/balance.csv + taux de victoire par personnage.
## godot --headless --path . --script res://tests/balance_sim.gd -- --n=20 [--boss]

const MAX_FRAMES: int = 20000


func _initialize() -> void:
	var n: int = 20
	var ids: PackedStringArray = Roster.FIGHTERS.duplicate()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			n = int(arg.trim_prefix("--n="))
		elif arg == "--boss":
			ids.append(Roster.BOSS)
	var count: int = ids.size()
	var wins: Array = []
	for i: int in count:
		var row: PackedInt32Array = []
		row.resize(count)
		wins.append(row)
	var total_wins: PackedInt32Array = []
	total_wins.resize(count)
	var total_games: PackedInt32Array = []
	total_games.resize(count)
	var start: int = Time.get_ticks_msec()
	var games: int = 0
	var frames_sum: int = 0
	for i: int in count:
		for j: int in range(i + 1, count):
			for k: int in n:
				# Côtés alternés pour annuler l'avantage éventuel de J1.
				var a: int = i if k % 2 == 0 else j
				var b: int = j if k % 2 == 0 else i
				var sim: FightSim = FightSim.new()
				sim.setup(FighterDb.get_def(ids[a]), FighterDb.get_def(ids[b]),
					{"seed": 1000 + i * 977 + j * 131 + k, "rounds": 3, "ai": [80, 80], "finishers": false})
				var frames: int = 0
				while not sim.is_over() and frames < MAX_FRAMES:
					sim.step(0, 0)
					frames += 1
				frames_sum += frames
				games += 1
				total_games[a] += 1
				total_games[b] += 1
				if sim.winner == 0:
					(wins[a] as PackedInt32Array)[b] += 1
					total_wins[a] += 1
				elif sim.winner == 1:
					(wins[b] as PackedInt32Array)[a] += 1
					total_wins[b] += 1
	var lines: PackedStringArray = ["id," + ",".join(ids) + ",total"]
	for i: int in count:
		var cells: PackedStringArray = [ids[i]]
		for j: int in count:
			cells.append("" if i == j else str((wins[i] as PackedInt32Array)[j]))
		cells.append("%.1f" % (100.0 * total_wins[i] / maxi(total_games[i], 1)))
		lines.append(",".join(cells))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
	var f: FileAccess = FileAccess.open("res://tests/out/balance.csv", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("%d matchs en %.1f s, %d frames en moyenne" % [games, (Time.get_ticks_msec() - start) / 1000.0, frames_sum / maxi(games, 1)])
	for i: int in count:
		print("%-12s %5.1f %%" % [ids[i], 100.0 * total_wins[i] / maxi(total_games[i], 1)])
	quit()
