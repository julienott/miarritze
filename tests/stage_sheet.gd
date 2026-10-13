extends Node
## Planche des décors en conditions de combat : chaque stage, caméra à
## gauche / centre / droite, en 16:9 (384), iPhone 19,5:9 (468) et iPad 4:3 (288),
## avec deux combattants pour l'échelle. Sortie : tests/out/stages/<stage>.png
## Usage : godot --path . res://tests/stage_sheet.tscn [-- --only=phare_sommet]

const WIDTHS: Array[int] = [384, 468, 288]
const H: int = 216


func _ready() -> void:
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var stages: Array = Roster.STAGES.duplicate()
	for v: String in ["grande_plage_soir", "cote_basques_crepuscule"]:
		stages.append(v)
	for id: String in stages:
		if only != "" and id != only:
			continue
		var rows: Array[Image] = []
		for w: int in WIDTHS:
			for pos: int in 3:
				rows.append(await _render(id, w, pos))
		var sheet: Image = Image.create(468 * 3 + 8, (H + 4) * 3, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.1, 0.1, 0.1))
		for i: int in rows.size():
			var col: int = i % 3
			var row: int = i / 3
			sheet.blit_rect(rows[i], Rect2i(0, 0, rows[i].get_width(), H), Vector2i(col * 472, row * (H + 4)))
		sheet.save_png(ProjectSettings.globalize_path("res://tests/out/stages/%s.png" % id))
		print("planche ", id)
	get_tree().quit()


func _render(id: String, w: int, pos: int) -> Image:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(w, H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(vp)
	var stage: StageView = StageView.new()
	stage.setup(id)
	vp.add_child(stage)
	var half: float = w * 0.5
	var cx: float = [half, 288.0, StageView.WORLD_W - half][pos]
	var cam: Camera2D = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	cam.position = Vector2(cx, H * 0.5)
	vp.add_child(cam)
	cam.make_current()
	for k: int in 2:
		var fv: FighterView = UiKit.fighter_preview(["louis", "maia"][k], 0, "idle", 1 if k == 0 else -1)
		fv.position = Vector2(cx + (-60 if k == 0 else 60), 196)
		vp.add_child(fv)
	stage.update_scroll(cx - half)
	for i: int in 4:
		await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img
