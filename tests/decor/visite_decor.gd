extends SceneTree
## Visite de debug automatisée (fenêtre) : pour chaque objet du décor (une pose par id, taille et miroir),
## le perso posé là où il s'arrête en marchant vers l'objet (devant, derrière, gauche, droite), captures
## recadrées avec et sans les formes (F). Mode chassé : le joueur lui-même. Mode chasseur : le chasseur
## est devant l'objet et regarde vers lui, un chassé figurant derrière ; on note s'il est vu.
## godot --path . --script res://tests/decor/visite_decor.gd -- --role=chasse|chasseur --out=/abs/dir [--map=port_pecheurs] [--only=id,id]

const GAME: String = "res://src/gordeka/gk_game.tscn"

var game: GkGame
var out: String = ""
var role: String = "chasse"
var only: PackedStringArray = []
var log_rows: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i: int in n:
		await process_frame


func _run() -> void:
	var map_id: String = "port_pecheurs"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_id = a.trim_prefix("--map=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--role="):
			role = a.trim_prefix("--role=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(out)
	GkGame.config["map"] = map_id
	GkGame.config["visite"] = role
	GkGame.config["players"] = 2
	game = (load(GAME) as PackedScene).instantiate()
	game._figurants = role == "chasseur"
	root.add_child(game)
	await _wait(90)
	game._camera.position_smoothing_enabled = false
	var m: GkMap = game.map
	var d: GkDecor = m.decor
	var r: float = GkRules.px("body_radius")
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = r
	var space: PhysicsDirectSpaceState2D = m.get_world_2d().direct_space_state
	var done: Dictionary = {}
	var other: GkActor = game.actors[1]
	for idx: int in d.instances.size():
		var inst: Dictionary = d.instances[idx]
		var id: String = str(inst["id"])
		if not only.is_empty() and not only.has(id):
			continue
		var sp: Sprite2D = inst.get("sprite")
		if sp == null:
			continue
		var key: String = "%s|%s|%s" % [id, (inst["rect"] as Rect2i).size, inst.get("miroir", false)]
		if done.has(key):
			continue
		done[key] = true
		var tag: String = "%s_%d_%d" % [id, (inst["rect"] as Rect2i).position.x, (inst["rect"] as Rect2i).position.y]
		var drawn: Vector2 = sp.texture.get_size() * sp.scale
		var holder: Node2D = inst["holder"]
		var top_left: Vector2 = holder.position + sp.position - drawn * 0.5
		var img_rect: Rect2 = Rect2(top_left, drawn)
		var bb: Rect2 = Rect2((inst["rect"] as Rect2i).position * int(m.tile), (inst["rect"] as Rect2i).size * int(m.tile))
		if inst.has("polys"):
			var first: bool = true
			for poly: PackedVector2Array in inst["polys"]:
				for p: Vector2 in poly:
					if first:
						bb = Rect2(p, Vector2.ZERO)
						first = false
					else:
						bb = bb.expand(p)
		var c: Vector2 = bb.get_center()
		var poses: Dictionary = {}
		for dn: String in ["devant", "derriere", "gauche", "droite"]:
			var dir: Vector2 = {"devant": Vector2(0, -1), "derriere": Vector2(0, 1), "gauche": Vector2(1, 0), "droite": Vector2(-1, 0)}[dn]
			var start: Vector2 = c - dir * (maxf(bb.size.x, bb.size.y) * 0.5 + 3.0 * r)
			var q: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
			q.shape = shape
			q.collision_mask = GkMap.LAYER_MOVE
			q.transform = Transform2D(0.0, start)
			q.motion = c - start
			var fr: PackedFloat32Array = space.cast_motion(q)
			var f: float = fr[0] if fr.size() > 0 else 1.0
			# Départ déjà bloqué (objet collé à un mur) : on garde le départ.
			poses[dn] = start + (c - start) * f
		var view: Rect2 = img_rect.merge(bb).grow(r * 3.0)
		for p: Vector2 in poses.values():
			view = view.expand(p + Vector2(-r * 2, -GkPerso.HEIGHT_PX - 10)).expand(p + Vector2(r * 2, r * 2))
		var row: Dictionary = {"tag": tag, "id": id, "poses": {}}
		if role == "chasse":
			for dn: String in poses:
				game.local.position = poses[dn]
				game.local.look = PI * 0.5
				await _wait(40)
				m.formes.visible = true
				await _wait(2)
				_shot(view, "%s__%s_F.png" % [tag, dn])
				if dn == "derriere" or dn == "devant":
					m.formes.visible = false
					await _wait(2)
					_shot(view, "%s__%s.png" % [tag, dn])
				row["poses"][dn] = [snappedf(poses[dn].x, 0.1), snappedf(poses[dn].y, 0.1),
					d.masking(poses[dn], GkGame.mask_height(r)) == idx, snappedf(float(inst.get("fade", 1.0)), 0.01)]
		else:
			# Chasseur 2,5 cases devant l'emprise, regard vers le haut ; chassé figurant derrière.
			var hpos: Vector2 = Vector2(c.x, bb.end.y + 2.5 * m.tile)
			game.local.position = hpos
			game.local.look = -PI * 0.5
			other.position = poses["derriere"]
			other.visible = true
			await _wait(60)
			m.formes.visible = false
			var v2: Rect2 = view.expand(hpos + Vector2(0, r * 2))
			_shot(v2, "%s__chasseur_cache_derriere.png" % tag)
			row["poses"]["chassé derrière vu"] = bool(game._seen.get(other.id, false))
			# Chassé à côté (gauche) : doit être vu.
			other.position = poses["gauche"]
			await _wait(40)
			row["poses"]["chassé à gauche vu"] = bool(game._seen.get(other.id, false))
			_shot(v2, "%s__chasseur_cote.png" % tag)
			# Le chasseur lui-même derrière l'objet (tri).
			other.position = Vector2(-100000, -100000)
			game.local.position = poses["derriere"]
			await _wait(30)
			_shot(view, "%s__chasseur_lui_derriere.png" % tag)
		log_rows.append(row)
		print("[visite] ", tag)
	var f2: FileAccess = FileAccess.open(out.path_join("_visite_%s.json" % role), FileAccess.WRITE)
	f2.store_string(JSON.stringify(log_rows, " "))
	f2.close()
	quit()


func _shot(world: Rect2, name: String) -> void:
	var img: Image = root.get_texture().get_image()
	var xf: Transform2D = root.get_canvas_transform()
	var a: Vector2 = xf * world.position
	var b: Vector2 = xf * world.end
	var rr: Rect2i = Rect2i(Vector2i(a), Vector2i(b - a)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if rr.size.x > 4 and rr.size.y > 4:
		img = img.get_region(rr)
	img.save_png(out.path_join(name))
