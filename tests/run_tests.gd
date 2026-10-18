extends SceneTree
## Tests headless de la sim (SPEC §14.1). Mini-framework maison.
## godot --headless --path . --script res://tests/run_tests.gd [-- --only=nom]

var _failures: int = 0
var _passed: int = 0
var _only: String = ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
	var tests: Array[Callable] = [
		test_lint_sim, test_data_valid, test_save_load_identity, test_determinism,
		test_rollback, test_frame_data, test_chip_never_kills, test_training_ko, test_combo_forced_knockdown,
		test_timer_and_draw, test_wave_return_once, test_throw_and_tech, test_full_match_ends,
		test_inputs_to_moves, test_fuzz_roster, test_reflect_projectile, test_ai_contact_normals,
		test_netcode_lossy, test_netcode_desync_detected, test_netcode_final_checksum,
	]
	for t: Callable in tests:
		if _only != "" and not t.get_method().contains(_only):
			continue
		var before: int = _failures
		var start: int = Time.get_ticks_msec()
		t.call()
		var status: String = "OK " if _failures == before else "ÉCHEC"
		if _failures == before:
			_passed += 1
		print("[%s] %s (%d ms)" % [status, t.get_method(), Time.get_ticks_msec() - start])
	print("\n%d réussis, %d échecs" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, message: String) -> void:
	if not cond:
		_failures += 1
		printerr("    ✗ " + message)


# ------------------------------------------------------------------ outils

func make_sim(a: String = "louis", b: String = "maia", options: Dictionary = {}) -> FightSim:
	var sim: FightSim = FightSim.new()
	var opts: Dictionary = {"seed": 1234, "rounds": 3}
	opts.merge(options, true)
	sim.setup(FighterDb.get_def(a), FighterDb.get_def(b), opts)
	return sim


## Entrées pseudo-aléatoires « réalistes » : maintien de quelques frames.
func random_inputs(seed_value: int, count: int) -> PackedInt32Array:
	var rng: XRng = XRng.new(seed_value)
	var out: PackedInt32Array = []
	var current: int = 0
	for i: int in count:
		if rng.below(6) == 0:
			current = rng.below(256)
			if current & 3 == 3:
				current &= ~1
			if current & 12 == 12:
				current &= ~4
		out.append(current)
	return out


func skip_intro(sim: FightSim) -> void:
	while sim.phase == SimConst.PH_INTRO:
		sim.step(0, 0)


# ------------------------------------------------------------------ tests

func test_lint_sim() -> void:
	var forbidden: PackedStringArray = ["float", "randf", "randi", "Time.", "OS.", "Engine.",
		"Node", "signal "]
	for dir_path: String in ["res://src/fight/sim", "res://src/fight/ai"]:
		var dir: DirAccess = DirAccess.open(dir_path)
		check(dir != null, "dossier %s introuvable" % dir_path)
		if dir == null:
			continue
		for file_name: String in dir.get_files():
			if not file_name.ends_with(".gd"):
				continue
			var text: String = FileAccess.get_file_as_string(dir_path + "/" + file_name)
			var line_no: int = 0
			for line: String in text.split("\n"):
				line_no += 1
				var code: String = line.split("#")[0]
				for word: String in forbidden:
					if code.contains(word):
						check(false, "%s:%d contient « %s »" % [file_name, line_no, word])


func test_data_valid() -> void:
	for id: String in FighterDb.list_ids():
		var def: FighterDef = FighterDb.get_def(id)
		check(def != null, "%s : data.json illisible" % id)
		if def == null:
			continue
		for name: String in ["punch_1", "kick", "sweep", "uppercut", "throw", "jump_punch"]:
			check(def.move(name) >= 0, "%s : coup %s manquant" % [id, name])
		for mv: MoveDef in def.moves:
			if mv.damage > 0 and not mv.is_throw and mv.spawn_projectile < 0:
				check(not mv.hitboxes.is_empty(), "%s/%s : pas de hitbox" % [id, mv.name])
		check(def.anim_frames.size() == SimConst.ANIMS.size(), "%s : liste d'anims incomplète" % id)


func test_save_load_identity() -> void:
	var sim: FightSim = make_sim()
	var inputs: PackedInt32Array = random_inputs(7, 600)
	for i: int in 300:
		sim.step(inputs[i], inputs[599 - i])
	var bytes: PackedByteArray = sim.save_state()
	check(bytes.size() < 1024, "état sérialisé trop gros : %d octets" % bytes.size())
	var other: FightSim = make_sim()
	other.load_state(bytes)
	check(other.save_state() == bytes, "load/save n'est pas l'identité binaire")
	for i: int in range(300, 600):
		sim.step(inputs[i], inputs[599 - i])
		other.step(inputs[i], inputs[599 - i])
	check(sim.checksum() == other.checksum(), "divergence après rechargement")


func test_determinism() -> void:
	for pair: Array in [["louis", "maia"], ["maia", "louis"], ["louis", "louis"]]:
		var a: FightSim = make_sim(pair[0], pair[1], {"seed": 99})
		var b: FightSim = make_sim(pair[0], pair[1], {"seed": 99})
		var in1: PackedInt32Array = random_inputs(11, 3600)
		var in2: PackedInt32Array = random_inputs(23, 3600)
		var diverged: int = -1
		for i: int in 3600:
			a.step(in1[i], in2[i])
			b.step(in1[i], in2[i])
			if a.checksum() != b.checksum():
				diverged = i
				break
		check(diverged < 0, "%s/%s : divergence à la frame %d" % [pair[0], pair[1], diverged])
		check(a.f[0].health < a.f[0].max_health or a.f[1].health < a.f[1].max_health
			or a.round_num > 1, "%s/%s : aucun coup n'a touché en 3600 frames (test peu probant)" % pair)


## Sim B reçoit les entrées de J2 en retard (1 à 8 frames), prédit la
## dernière entrée connue, puis fait un rollback à chaque correction.
func test_rollback() -> void:
	var total: int = 2400
	var in1: PackedInt32Array = random_inputs(31, total)
	var in2: PackedInt32Array = random_inputs(47, total)
	var a: FightSim = make_sim("louis", "maia", {"seed": 5})
	for i: int in total:
		a.step(in1[i], in2[i])
	var b: FightSim = make_sim("louis", "maia", {"seed": 5})
	var rng: XRng = XRng.new(77)
	var states: Array[PackedByteArray] = []     # état AVANT la frame i
	var used2: PackedInt32Array = []            # entrée J2 utilisée à la frame i
	var known: int = 0                          # entrées J2 confirmées [0, known)
	var rollbacks: int = 0
	for i: int in total:
		# De nouvelles entrées distantes arrivent (en retard de 1 à 8 frames).
		var arrive_up_to: int = maxi(known, i - 1 - rng.below(8))
		if arrive_up_to > known:
			var first_wrong: int = -1
			for k: int in range(known, arrive_up_to):
				if used2[k] != in2[k] and first_wrong < 0:
					first_wrong = k
			known = arrive_up_to
			if first_wrong >= 0:
				rollbacks += 1
				b.load_state(states[first_wrong])
				for k: int in range(first_wrong, i):
					var guess: int = in2[k] if k < known else in2[known - 1]
					states[k] = b.save_state()
					used2[k] = guess
					b.step(in1[k], guess)
		var predicted: int = in2[i] if i < known else (in2[known - 1] if known > 0 else 0)
		states.append(b.save_state())
		used2.append(predicted)
		b.step(in1[i], predicted)
	# Toutes les entrées arrivent : correction finale.
	var first_bad: int = -1
	for k: int in range(known, total):
		if used2[k] != in2[k]:
			first_bad = k
			break
	if first_bad >= 0:
		b.load_state(states[first_bad])
		for k: int in range(first_bad, total):
			b.step(in1[k], in2[k])
	check(rollbacks > 50, "trop peu de rollbacks pour être probant (%d)" % rollbacks)
	check(a.checksum() == b.checksum(), "état final différent après rollbacks")


func test_frame_data() -> void:
	for id: String in ["louis", "maia"]:
		var def: FighterDef = FighterDb.get_def(id)
		for mv: MoveDef in def.moves:
			if mv.is_throw or mv.air_ok or mv.is_super:
				continue
			var sim: FightSim = make_sim(id, "louis")
			skip_intro(sim)
			sim.f[1].x = SimConst.WALL_R
			sim._start_move(0, mv.index, 0)
			var first_active: int = -1
			for t: int in mv.total + 2:
				if not MoveRunner.hitboxes(def, sim.f[0]).is_empty() and first_active < 0:
					first_active = sim.f[0].move_t
				sim.step(0, 0)
				if sim.f[0].state != SimConst.ST_MOVE:
					break
			if mv.damage > 0 and mv.spawn_projectile < 0:
				check(first_active == mv.startup, "%s/%s : sort à %d au lieu de %d"
					% [id, mv.name, first_active, mv.startup])


func test_chip_never_kills() -> void:
	var sim: FightSim = make_sim()
	skip_intro(sim)
	sim.f[1].health = 2
	sim.f[1].set_state(SimConst.ST_BLOCK, SimConst.A_BLOCK)
	for i: int in 3:
		sim._apply_damage(0, 400, 10, 10, 0, SimConst.LVL_MID, false, 0, 0, 4, 0, 150, 0, 0, 0, 0, 0, sim.f[0].x, sim.f[0].y)
		sim.f[1].set_state(SimConst.ST_BLOCK, SimConst.A_BLOCK)
	check(sim.f[1].health == 1, "le chip a tué ou n'a rien fait (vie %d)" % sim.f[1].health)


func test_training_ko() -> void:
	# Entraînement : le mannequin ne tombe jamais ; tutoriel (training_ko) : il tombe K.O.
	var sim: FightSim = make_sim("louis", "hondar", {"training": true, "rounds": 1})
	skip_intro(sim)
	sim.f[1].health = 5
	sim._apply_damage(0, 50, 10, 10, 0, SimConst.LVL_MID, false, 0, 0, 4, 0, 150, 0, 0, 0, 0, 0, sim.f[0].x, sim.f[0].y)
	for i: int in 120:
		sim.step(0, 0)
	check(sim.f[1].health > 0, "entraînement : le mannequin est tombé")
	sim.training_ko = true
	sim.f[1].health = 5
	sim._apply_damage(0, 50, 10, 10, 0, SimConst.LVL_MID, false, 0, 0, 4, 0, 150, 0, 0, 0, 0, 0, sim.f[0].x, sim.f[0].y)
	for i: int in 120:
		sim.step(0, 0)
	check(sim.f[1].health == 0 and sim.f[1].state == SimConst.ST_KO, "tutoriel : pas de K.O. (vie %d)" % sim.f[1].health)
	check(sim.phase == SimConst.PH_FIGHT, "tutoriel : le K.O. a terminé le round")


func test_combo_forced_knockdown() -> void:
	var sim: FightSim = make_sim()
	skip_intro(sim)
	for i: int in 6:
		sim._apply_damage(0, 10, 30, 10, 0, SimConst.LVL_MID, false, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, sim.f[0].x, sim.f[0].y)
	check(sim.f[1].state == SimConst.ST_AIR_HIT, "pas de chute forcée au 6e coup (état %d)" % sim.f[1].state)
	check(sim.f[1].combo_hits == 6, "compteur de combo %d" % sim.f[1].combo_hits)
	# Le scaling descend jusqu'à 40 %.
	var sim2: FightSim = make_sim()
	skip_intro(sim2)
	sim2.f[1].combo_hits = 10
	var before: int = sim2.f[1].health
	sim2._apply_damage(0, 100, 10, 10, 0, SimConst.LVL_MID, false, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, sim2.f[0].x, sim2.f[0].y)
	check(before - sim2.f[1].health == 40, "scaling minimal attendu 40, obtenu %d" % (before - sim2.f[1].health))


func test_timer_and_draw() -> void:
	var sim: FightSim = make_sim("louis", "louis", {"rounds": 1, "finishers": false})
	skip_intro(sim)
	for i: int in SimConst.ROUND_FRAMES + 2:
		sim.step(0, 0)
	check(sim.phase == SimConst.PH_KO, "le chrono n'a pas fini le round (phase %d)" % sim.phase)
	check(sim.f[0].rounds == 1 and sim.f[1].rounds == 1, "égalité parfaite : les deux marquent")
	for i: int in SimConst.KO_PAUSE_FRAMES + 2:
		sim.step(0, 0)
	check(sim.is_over() and sim.winner == -1, "match nul attendu (winner %d)" % sim.winner)
	# Au chrono, le % de vie départage.
	var sim2: FightSim = make_sim("louis", "maia", {"rounds": 1, "finishers": false})
	skip_intro(sim2)
	sim2.f[1].health = 900
	for i: int in SimConst.ROUND_FRAMES + 2:
		sim2.step(0, 0)
	check(sim2.round_winner == 0, "le pourcentage de vie doit départager (gagnant %d)" % sim2.round_winner)


func test_wave_return_once() -> void:
	var sim: FightSim = make_sim()
	skip_intro(sim)
	sim.f[1].health = 200
	sim.step(0, 0)
	check(sim.f[1].meter == SimConst.METER_MAX and sim.f[1].wave_used == 1, "Retour de vague non déclenché")
	sim.f[1].meter = 0
	sim.f[1].health = 100
	sim.step(0, 0)
	check(sim.f[1].meter == 0, "Retour de vague déclenché deux fois")


func test_throw_and_tech() -> void:
	var sim: FightSim = make_sim()
	skip_intro(sim)
	sim.f[0].x = 280 * SimConst.SUB
	sim.f[1].x = 316 * SimConst.SUB
	sim.step(SimConst.RIGHT, 0)
	sim.step(SimConst.RIGHT | SimConst.PUNCH, 0)
	for i: int in 50:
		sim.step(0, 0)
	check(sim.f[1].health < sim.f[1].max_health, "la projection n'a pas touché")
	var sim2: FightSim = make_sim()
	skip_intro(sim2)
	sim2.f[0].x = 280 * SimConst.SUB
	sim2.f[1].x = 316 * SimConst.SUB
	sim2.step(SimConst.RIGHT, 0)
	sim2.step(SimConst.RIGHT | SimConst.PUNCH, 0)
	for i: int in 5:
		sim2.step(0, 0)
	sim2.step(0, SimConst.PUNCH)
	for i: int in 50:
		sim2.step(0, 0)
	check(sim2.f[1].health == sim2.f[1].max_health, "la tech n'a pas annulé la projection")


func test_full_match_ends() -> void:
	var sim: FightSim = make_sim("louis", "maia", {"seed": 3})
	var in1: PackedInt32Array = random_inputs(5, 30000)
	var frames: int = 0
	while not sim.is_over() and frames < 30000:
		sim.step(in1[frames], 0)
		frames += 1
	check(sim.is_over(), "le match ne se termine pas")
	check(sim.winner == 0 or sim.winner == -1, "J1 (actif) devrait gagner contre un J2 inerte")


## Entrées → coups : uppercut (Arrière-bas + P et Bas puis Haut + P),
## spéciaux SPÉCIAL + direction, manip classique avec bonus.
func test_inputs_to_moves() -> void:
	var cases: Array = [
		["uppercut DB+P", [[SimConst.DOWN | SimConst.LEFT, 3], [SimConst.DOWN | SimConst.LEFT | SimConst.PUNCH, 1]], "uppercut", 0],
		["uppercut D,U+P", [[SimConst.DOWN, 3], [SimConst.UP | SimConst.PUNCH, 1]], "uppercut", 0],
		["balayette", [[SimConst.DOWN, 2], [SimConst.DOWN | SimConst.KICK, 1]], "sweep", 0],
		["pied haut", [[SimConst.RIGHT | SimConst.KICK, 1]], "kick_high", 0],
		["spécial neutre", [[SimConst.SPECIAL, 1]], "sp_neutral", 0],
		["spécial avant", [[SimConst.RIGHT | SimConst.SPECIAL, 1]], "sp_forward", 0],
		["spécial bas", [[SimConst.DOWN | SimConst.SPECIAL, 1]], "sp_down", 0],
		["spécial haut", [[SimConst.UP | SimConst.SPECIAL, 1]], "sp_up", 0],
		["classique ↓↘→+P", [[SimConst.DOWN, 2], [SimConst.DOWN | SimConst.RIGHT, 2], [SimConst.RIGHT, 2], [SimConst.RIGHT | SimConst.PUNCH, 1]], "sp_neutral", SimConst.CLASSIC_BONUS_PCT],
	]
	for c: Array in cases:
		var sim: FightSim = make_sim("louis", "maia")
		skip_intro(sim)
		var hit_name: String = ""
		var bonus: int = -1
		for step: Array in c[1]:
			for i: int in int(step[1]):
				sim.step(int(step[0]), 0)
				if sim.f[0].state == SimConst.ST_MOVE and hit_name == "":
					hit_name = sim.defs[0].moves[sim.f[0].move].name
					bonus = sim.f[0].move_bonus
		check(hit_name == c[2], "%s : attendu %s, obtenu « %s »" % [c[0], c[2], hit_name])
		check(bonus == c[3], "%s : bonus %d au lieu de %d" % [c[0], bonus, c[3]])


## Chaque combattant contre chacun : entrées aléatoires + IA, sans erreur,
## et la sim reste déterministe (deux passes identiques).
## L'IA au contact utilise ses coups normaux, quelle que soit la largeur de
## sa boîte de poussée (Karramarro : 54 px ; seuils réglés pour 2 × 22 px).
func test_ai_contact_normals() -> void:
	for id: String in ["louis", "karramarro", "mattin"]:
		var sim: FightSim = make_sim(id, Roster.DUMMY, {"seed": 7, "ai": [AiBrain.SKILL_EXPERT, AiBrain.DUMMY_IDLE]})
		var def: FighterDef = sim.defs[0]
		var normals: int = 0
		var prev: int = -1
		for i: int in 1500:
			sim.step(0, 0)
			var mi: int = sim.f[0].move if sim.f[0].state == SimConst.ST_MOVE else -1
			if mi >= 0 and mi != prev and not def.moves[mi].is_special and not def.moves[mi].air_ok:
				normals += 1
			prev = mi
		check(normals >= 5, "%s : l'IA ne frappe pas au contact (%d coups normaux)" % [id, normals])


func test_fuzz_roster() -> void:
	var ids: PackedStringArray = Roster.FIGHTERS.duplicate()
	ids.append(Roster.BOSS)
	ids.append(Roster.DUMMY)
	for a: String in ids:
		for b: String in [ids[(ids.find(a) + 1) % ids.size()], ids[(ids.find(a) + 5) % ids.size()]]:
			var sums: Array[int] = []
			for pass_i: int in 2:
				var sim: FightSim = make_sim(a, b, {"seed": 42, "ai": [0, 60]})
				var inputs: PackedInt32Array = random_inputs(a.length() * 31 + b.length(), 1500)
				for i: int in 1500:
					sim.step(inputs[i], 0)
				sums.append(sim.checksum())
			check(sums[0] == sums[1], "%s vs %s : non déterministe" % [a, b])


func test_reflect_projectile() -> void:
	var sim: FightSim = make_sim("ramuntxo", "louis")
	skip_intro(sim)
	sim.f[0].x = 200 * SimConst.SUB
	sim.f[1].x = 330 * SimConst.SUB
	sim._start_move(1, sim.defs[1].m_sp[0], 0)
	var reflected: bool = false
	for i: int in 60:
		if i == 18:
			sim._start_move(0, sim.defs[0].m_sp[3], 0)
		sim.step(0, 0)
		for pr: ProjectileState in sim.projectiles:
			if pr.owner == 0 and pr.src == 1:
				reflected = true
	check(reflected, "la poêle n'a pas renvoyé l'espadrille")


## Deux sessions rollback reliées par un réseau simulé (latence 1–6 ticks,
## 15 % de pertes, désordre) : les deux sims doivent rester identiques.
func _run_net(loss_permille: int, frames: int, corrupt: bool) -> Array:
	var sa: FightSim = make_sim("louis", "maia", {"seed": 77})
	var sb: FightSim = make_sim("louis", "maia", {"seed": 77})
	var ra: RollbackSession = RollbackSession.new()
	var rb: RollbackSession = RollbackSession.new()
	ra.setup(sa, 0, 2, 77)
	rb.setup(sb, 1, 2, 77)
	var rng: XRng = XRng.new(4242)
	var in_a: PackedInt32Array = random_inputs(3, frames + 20)
	var in_b: PackedInt32Array = random_inputs(9, frames + 20)
	var wire: Array = []   # [tick d'arrivée, destinataire 0/1, paquet]
	var t: int = 0
	var guard: int = 0
	while (ra.frame < frames or rb.frame < frames) and guard < frames * 4:
		guard += 1
		t += 1
		if corrupt and t == 300:
			sb.f[0].health -= 1   # désynchronisation volontaire
		var pa: PackedByteArray = ra.tick(in_a[mini(ra.frame, frames)]) if ra.frame < frames else ra._input_packet()
		var pb: PackedByteArray = rb.tick(in_b[mini(rb.frame, frames)]) if rb.frame < frames else rb._input_packet()
		var outgoing: Array = [[1, pa], [0, pb]]
		for c: PackedByteArray in ra.take_check_packets():
			outgoing.append([1, c])
		for c: PackedByteArray in rb.take_check_packets():
			outgoing.append([0, c])
		for o: Array in outgoing:
			if rng.chance(loss_permille) and (o[1] as PackedByteArray)[0] == 1:
				continue
			wire.append([t + 1 + rng.below(6), o[0], o[1]])
		var keep: Array = []
		for w: Array in wire:
			if int(w[0]) <= t:
				(ra if int(w[1]) == 0 else rb).receive(w[2])
			else:
				keep.append(w)
		wire = keep
	# Vidange : tout finit par arriver (redondance).
	for i: int in 40:
		for w: Array in wire:
			(ra if int(w[1]) == 0 else rb).receive(w[2])
		wire.clear()
		var pa2: PackedByteArray = ra._input_packet()
		var pb2: PackedByteArray = rb._input_packet()
		rb.receive(pa2)
		ra.receive(pb2)
	return [sa, sb, ra, rb]


func test_netcode_lossy() -> void:
	var r: Array = _run_net(150, 900, false)
	var sa: FightSim = r[0]
	var sb: FightSim = r[1]
	var ra: RollbackSession = r[2]
	check(sa.frame == sb.frame, "frames différentes (%d / %d)" % [sa.frame, sb.frame])
	check(sa.checksum() == sb.checksum(), "états différents après réseau à pertes")
	check(ra.rollbacks > 10, "trop peu de rollbacks (%d)" % ra.rollbacks)
	check(ra.max_rollback_seen <= RollbackSession.MAX_ROLLBACK, "rollback de plus de 8 frames (%d)" % ra.max_rollback_seen)
	check(not ra.desync and not (r[3] as RollbackSession).desync, "fausse désynchronisation détectée")


## Match complet en ligne : les deux sessions s'accordent sur la frame et le
## checksum de fin, même si elles continuent à tourner ensuite.
func test_netcode_final_checksum() -> void:
	var r: Array = _run_net(100, 30000, false)
	var ra: RollbackSession = r[2]
	var rb: RollbackSession = r[3]
	check(ra.final_frame >= 0 and rb.final_frame >= 0, "fin de match non détectée")
	check(ra.final_frame == rb.final_frame and ra.final_checksum == rb.final_checksum,
		"checksums finaux différents (%d/%d, %d/%d)" % [ra.final_frame, rb.final_frame, ra.final_checksum, rb.final_checksum])


func test_netcode_desync_detected() -> void:
	var r: Array = _run_net(0, 700, true)
	check((r[2] as RollbackSession).desync or (r[3] as RollbackSession).desync, "désynchronisation non détectée par les checksums")
