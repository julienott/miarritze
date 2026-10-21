extends SceneTree
## Mesure du décor posé (QA) : pour chaque instance d'objet en image, taille dessinée vs perso,
## emprise (polygones de collision) vs base dessinée de l'image, ligne de tri, source du masque,
## sondes physiques (cercle du perso qui avance vers l'objet depuis les 4 côtés).
## godot --headless --path . --script res://tests/decor/mesure_decor.gd -- --map=port_pecheurs --out=/abs/mesures.json

const GAME: String = "res://src/gordeka/gk_game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var map_id: String = "port_pecheurs"
	var out_path: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_id = a.trim_prefix("--map=")
		elif a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
	GkGame.config["map"] = map_id
	GkGame.config["visite"] = "chasse"
	var game: GkGame = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	for i: int in 3:
		await physics_frame
	var m: GkMap = game.map
	var d: GkDecor = m.decor
	var space: PhysicsDirectSpaceState2D = m.get_world_2d().direct_space_state
	var r: float = GkRules.px("body_radius")
	var res: Array = []
	for idx: int in d.instances.size():
		var inst: Dictionary = d.instances[idx]
		var row: Dictionary = {"i": idx, "id": inst["id"], "rect": [inst["rect"].position.x, inst["rect"].position.y,
			inst["rect"].size.x, inst["rect"].size.y], "zone": str(m.zones[inst["zone"]]["name"]) if int(inst["zone"]) >= 0 else "-",
			"miroir": inst.get("miroir", false), "provisoire": inst.get("provisoire", false)}
		var foot: Rect2 = Rect2(Vector2((inst["rect"] as Rect2i).position) * m.tile, Vector2((inst["rect"] as Rect2i).size) * m.tile)
		row["foot"] = [foot.position.x, foot.position.y, foot.size.x, foot.size.y]
		var sp: Sprite2D = inst.get("sprite")
		if sp == null:
			res.append(row)
			continue
		var drawn: Vector2 = sp.texture.get_size() * sp.scale
		var holder: Node2D = inst["holder"]
		var top_left: Vector2 = holder.position + sp.position - drawn * 0.5
		row["drawn"] = [snappedf(drawn.x, 0.1), snappedf(drawn.y, 0.1)]
		row["top_left"] = [snappedf(top_left.x, 0.1), snappedf(top_left.y, 0.1)]
		row["h_perso"] = snappedf(drawn.y / GkPerso.HEIGHT_PX, 0.01)
		row["fill_w"] = snappedf(drawn.x / foot.size.x, 0.01)
		row["img_bottom"] = snappedf(top_left.y + drawn.y, 0.1)
		row["source"] = inst.get("shape_source", "")
		row["info"] = inst.get("shape_info", {})
		row["blocks_view"] = inst.get("blocks_view", null)
		if not inst.has("polys"):
			res.append(row)
			continue
		row["sort_y"] = snappedf(float(inst["sort_y"]), 0.1)
		var bb: Rect2 = Rect2()
		var first: bool = true
		var area: float = 0.0
		for poly: PackedVector2Array in inst["polys"]:
			area += absf(GkDecor._area(poly))
			for p: Vector2 in poly:
				if first:
					bb = Rect2(p, Vector2.ZERO)
					first = false
				else:
					bb = bb.expand(p)
		row["poly_bb"] = [snappedf(bb.position.x, 0.1), snappedf(bb.position.y, 0.1), snappedf(bb.size.x, 0.1), snappedf(bb.size.y, 0.1)]
		row["poly_area_cases"] = snappedf(area / (m.tile * m.tile), 0.01)
		# Grille des IA vs emprise (#606) : cases de l'objet (et voisines) bloquées pour l'A* sans emprise
		# dedans (« vide bloqué » : l'IA contourne du vide), ou marchables avec l'emprise dedans (« plein
		# marchable » : l'IA fonce dans l'objet). Case rétrécie de 0,1 case par bord.
		var vide_bloque: int = 0
		var plein_marchable: int = 0
		var ir: Rect2i = (inst["rect"] as Rect2i).grow(1)
		for cy: int in range(ir.position.y, ir.end.y):
			for cx: int in range(ir.position.x, ir.end.x):
				var cc: Vector2i = Vector2i(cx, cy)
				var inner: Rect2 = Rect2(Vector2(cc) * m.tile, Vector2(m.tile, m.tile)).grow(-0.1 * m.tile)
				var box: PackedVector2Array = PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y),
					inner.end, Vector2(inner.position.x, inner.end.y)])
				var hit: bool = false
				for poly: PackedVector2Array in inst["polys"]:
					if not Geometry2D.intersect_polygons(poly, box).is_empty():
						hit = true
						break
				var own: bool = (inst["cells"] as Array).has(cc)
				if own and not hit and not m.walkable(cc) and m.at(cc) != "H":
					vide_bloque += 1
				elif hit and m.walkable(cc):
					plein_marchable += 1
		row["cases_vide_bloque"] = vide_bloque
		row["cases_plein_marchable"] = plein_marchable
		# Base dessinée : pour chaque colonne (pas de 4 px), le pixel opaque le plus bas de l'image,
		# comparé au bas de l'emprise dans cette colonne.
		var img: Image = GkDecor._read_image(sp.texture.resource_path)
		var gaps: Array = []
		var air_cols: int = 0
		var no_poly_cols: int = 0
		var cols: int = 0
		if img:
			img.convert(Image.FORMAT_RGBA8)
			var iw: int = img.get_width()
			var ih: int = img.get_height()
			var x: float = 2.0
			while x < drawn.x:
				var ix: int = clampi(int(x / drawn.x * iw), 0, iw - 1)
				if bool(inst.get("miroir", false)):
					ix = iw - 1 - ix
				var by: int = -1
				for y: int in range(ih - 1, -1, -1):
					if img.get_pixel(ix, y).a > 0.5:
						by = y
						break
				if by >= 0:
					cols += 1
					var gy: float = top_left.y + (by + 1) * drawn.y / ih
					var gx: float = top_left.x + x
					# bas de l'emprise dans la colonne
					var pb: float = -1.0
					var yy: float = gy + 40.0
					while yy > top_left.y:
						var inside: bool = false
						for poly: PackedVector2Array in inst["polys"]:
							if Geometry2D.is_point_in_polygon(Vector2(gx, yy), poly):
								inside = true
								break
						if inside:
							pb = yy
							break
						yy -= 1.0
					if pb < 0.0:
						no_poly_cols += 1
					else:
						gaps.append(gy - pb)
						if pb > gy + 3.0:
							air_cols += 1
				x += 4.0
		gaps.sort()
		row["cols"] = cols
		row["cols_sans_emprise"] = no_poly_cols
		row["cols_emprise_sous_base"] = air_cols
		if not gaps.is_empty():
			row["ecart_base_med"] = snappedf(float(gaps[gaps.size() / 2]), 0.1)
			row["ecart_base_min"] = snappedf(float(gaps[0]), 0.1)
			row["ecart_base_max"] = snappedf(float(gaps[-1]), 0.1)
		# Sondes : cercle du perso, du dehors vers le centre de l'emprise, 4 côtés.
		var c: Vector2 = bb.get_center()
		var shape: CircleShape2D = CircleShape2D.new()
		shape.radius = r
		var probes: Dictionary = {}
		for dir: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0)]:
			var start: Vector2 = c - dir * (maxf(drawn.x, drawn.y) + 2.0 * r)
			# départ hors de toute collision : on recule tant que le départ touche
			var q: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
			q.shape = shape
			q.collision_mask = GkMap.LAYER_MOVE
			var motion: Vector2 = c - start
			# de devant (dir = haut) : on part du bas
			q.transform = Transform2D(0.0, start)
			q.motion = motion
			var fr: PackedFloat32Array = space.cast_motion(q)
			var stop: Vector2 = start + motion * (fr[0] if fr.size() > 0 else 1.0)
			var key: String = {Vector2(0, -1): "devant", Vector2(0, 1): "derriere", Vector2(1, 0): "gauche", Vector2(-1, 0): "droite"}[dir]
			# devant : bord bas de l'emprise que touche le cercle
			var touch: Vector2 = stop + dir * r
			probes[key] = [snappedf(touch.x, 0.1), snappedf(touch.y, 0.1)]
		row["sondes"] = probes
		# Masquage : perso derrière (pieds 0.25 case au-dessus du bord arrière), au centre.
		var behind: Vector2 = Vector2(c.x, bb.position.y - r)
		row["masque_derriere"] = d.masking(behind, game.mask_height(r)) == idx
		var front: Vector2 = Vector2(c.x, bb.end.y + r)
		row["masque_devant"] = d.masking(front, game.mask_height(r)) >= 0
		# Vue du chasseur : 3 cases devant l'emprise, regard vers le haut ; chassé derrière, à côté.
		var h: GkActor = game.hunter
		h.position = Vector2(c.x, bb.end.y + 3.0 * m.tile)
		h.look = -PI * 0.5
		row["vu_derriere"] = snappedf(game.sight_fraction(h, behind, r), 0.01)
		row["vu_cote"] = snappedf(game.sight_fraction(h, Vector2(bb.position.x - r - 2.0, c.y), r), 0.01)
		res.append(row)
	var txt: String = JSON.stringify(res, " ")
	if out_path != "":
		var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(txt)
		f.close()
	print("[mesure] %d instances" % res.size())
	quit()
