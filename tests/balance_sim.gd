extends SceneTree
## Équilibrage par simulation (SPEC §14.4) : duels IA contre IA, headless,
## même niveau d'IA des deux côtés, côtés alternés, graines différentes.
## Mesure par paire (victoires, durée, distance) et par combattant (dégâts,
## touches, gardes, spéciaux, dégâts par coup).
##
## godot --headless --path . --script res://tests/balance_sim.gd -- \
##     [--n=20] [--ai=80] [--seed=1000] [--ids=a,b,c] [--boss] \
##     [--shard=0/1] [--out=res://tests/out/balance_shard_0.json]
## Sans --out : écrit aussi tests/out/balance.csv (heatmap). Le lancement
## parallèle et la synthèse sont faits par tools/balance/matrix.py.

const MAX_FRAMES: int = 20000
## Écart (px) entre les boîtes de poussée sous lequel les deux combattants
## sont « au contact » (portée des coups normaux).
const CLOSE_GAP_PX: int = 16

var _fighters: Dictionary = {}


func _initialize() -> void:
	var n: int = 20
	var ai: int = AiBrain.SKILL_EXPERT
	var base_seed: int = 1000
	var shard: int = 0
	var shards: int = 1
	var out_path: String = ""
	var ids: PackedStringArray = Roster.FIGHTERS.duplicate()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			n = int(arg.trim_prefix("--n="))
		elif arg.begins_with("--ai="):
			ai = int(arg.trim_prefix("--ai="))
		elif arg.begins_with("--seed="):
			base_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--ids="):
			ids = arg.trim_prefix("--ids=").split(",")
		elif arg == "--boss":
			ids.append(Roster.BOSS)
		elif arg.begins_with("--shard="):
			var parts: PackedStringArray = arg.trim_prefix("--shard=").split("/")
			shard = int(parts[0])
			shards = maxi(1, int(parts[1]))
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var start: int = Time.get_ticks_msec()
	var pairs: Array = []
	var pair_index: int = 0
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			if pair_index % shards == shard:
				pairs.append(_run_pair(ids[i], ids[j], n, ai, base_seed + i * 977 + j * 131))
			pair_index += 1
	var result: Dictionary = {"ai": ai, "n": n, "ids": ids, "pairs": pairs, "fighters": _fighters}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
	if out_path == "":
		out_path = "res://tests/out/balance.json"
		_write_csv(ids, pairs)
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " "))
	f.close()
	print("%d paires en %.1f s -> %s" % [pairs.size(), (Time.get_ticks_msec() - start) / 1000.0, out_path])
	quit()


func _stats(id: String) -> Dictionary:
	if not _fighters.has(id):
		_fighters[id] = {"games": 0, "wins": 0, "frames": 0, "dmg": 0, "hits": 0, "hits_taken": 0,
			"blocked": 0, "blocks": 0, "specials": 0, "supers": 0, "proj": 0,
			"throws": 0, "knockdowns": 0, "move_dmg": {}, "move_use": {}}
	return _fighters[id]


func _add(dict: Dictionary, key: String, value: int) -> void:
	dict[key] = int(dict.get(key, 0)) + value


## Joue n matchs a contre b, côtés alternés (k pair : a en J1).
func _run_pair(a: String, b: String, n: int, ai: int, seed_base: int) -> Dictionary:
	var pair: Dictionary = {"a": a, "b": b, "games": 0, "wins_a": 0, "wins_b": 0, "draws": 0,
		"frames": 0, "fight_frames": 0, "timeouts": 0, "rounds": 0, "close": 0, "dist": 0}
	var defs: Array = [FighterDb.get_def(a), FighterDb.get_def(b)]
	for k: int in n:
		var swap: bool = k % 2 == 1
		var side: Array = [b, a] if swap else [a, b]
		var sim: FightSim = FightSim.new()
		sim.setup(defs[1] if swap else defs[0], defs[0] if swap else defs[1],
			{"seed": seed_base + k, "rounds": 3, "ai": [ai, ai], "finishers": false})
		var st: Array = [_stats(side[0]), _stats(side[1])]
		var prev: Array = [sim.f[0].health, sim.f[1].health]  # Array : passé par référence
		var frames: int = 0
		while not sim.is_over() and frames < MAX_FRAMES:
			sim.step(0, 0)
			frames += 1
			_record(sim, st, prev, pair)
		pair["games"] += 1
		pair["frames"] += frames
		for p: int in 2:
			st[p]["games"] += 1
			st[p]["frames"] += frames
		if sim.winner < 0:
			pair["draws"] += 1
		else:
			st[sim.winner]["wins"] += 1
			if side[sim.winner] == a:
				pair["wins_a"] += 1
			else:
				pair["wins_b"] += 1
	return pair


## Lit les événements et les variations de vie du dernier tick.
func _record(sim: FightSim, st: Array, prev: Array, pair: Dictionary) -> void:
	var proj_hit: PackedInt32Array = PackedInt32Array([0, 0])
	for ev: PackedInt32Array in sim.events:
		var type: int = ev[1]
		var actor: int = ev[2]
		match type:
			FxEvents.HIT:
				st[1 - actor]["hits"] += 1
				st[actor]["hits_taken"] += 1
			FxEvents.BLOCK:
				st[actor]["blocks"] += 1
				st[1 - actor]["blocked"] += 1
			FxEvents.SPECIAL_START:
				st[actor]["specials"] += 1
				_add(st[actor]["move_use"], sim.defs[actor].moves[ev[5]].name, 1)
			FxEvents.SUPER_START:
				st[actor]["supers"] += 1
				_add(st[actor]["move_use"], "super", 1)
			FxEvents.PROJ_SPAWN:
				st[actor]["proj"] += 1
			FxEvents.PROJ_HIT:
				proj_hit[actor] = 1
			FxEvents.THROW:
				st[actor]["throws"] += 1
			FxEvents.KNOCKDOWN:
				st[1 - actor]["knockdowns"] += 1
			FxEvents.TIME_OVER:
				pair["timeouts"] += 1
			FxEvents.ROUND_END:
				pair["rounds"] += 1
	for v: int in 2:
		var hp: int = sim.f[v].health
		var lost: int = prev[v] - hp
		prev[v] = hp
		if lost <= 0:
			continue
		var a: int = 1 - v
		st[a]["dmg"] += lost
		var src: String = "?"
		if proj_hit[a] != 0:
			src = "projectile"
		elif sim.f[a].move >= 0:
			src = sim.defs[a].moves[sim.f[a].move].name
		_add(st[a]["move_dmg"], src, lost)
	if sim.phase == SimConst.PH_FIGHT:
		pair["fight_frames"] += 1
		var dist: int = absi(sim.f[0].x - sim.f[1].x) / SimConst.SUB
		pair["dist"] += dist
		if dist - (sim.defs[0].push_front + sim.defs[1].push_front) / SimConst.SUB < CLOSE_GAP_PX:
			pair["close"] += 1


func _write_csv(ids: PackedStringArray, pairs: Array) -> void:
	var wins: Dictionary = {}
	for pr: Dictionary in pairs:
		wins[pr["a"] + ">" + pr["b"]] = pr["wins_a"]
		wins[pr["b"] + ">" + pr["a"]] = pr["wins_b"]
	var lines: PackedStringArray = ["id," + ",".join(ids) + ",total"]
	for i: String in ids:
		var cells: PackedStringArray = [i]
		for j: String in ids:
			cells.append("" if i == j else str(wins.get(i + ">" + j, 0)))
		var s: Dictionary = _stats(i)
		cells.append("%.1f" % (100.0 * s["wins"] / maxi(s["games"], 1)))
		lines.append(",".join(cells))
	var f: FileAccess = FileAccess.open("res://tests/out/balance.csv", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
