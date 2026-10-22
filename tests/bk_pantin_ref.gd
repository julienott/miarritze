extends SceneTree
## Rend des poses du pantin (GkPantin) sur le canevas du mannequin, pour comparer au rendu de
## référence de pixelforge (mannequin/<gabarit>/reference/<anim>_<NN>.png).
##   godot --path . -s tests/gk_pantin_ref.gd -- --out=/abs/dossier [--gabarit=humain] walk:0 walk:6 found:5
## (fenêtré : le rendu passe par le GPU).

var _jobs: Array = []
var _out: String = "/tmp"
var _gabarit: String = "humain"
var _vp: SubViewport
var _pantin: GkPantin
var _wait: int = 0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--gabarit="):
			_gabarit = a.trim_prefix("--gabarit=")
		elif a.contains(":"):
			_jobs.append(a)
	var rig: Dictionary = GkPantin.load_rig(_gabarit)
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(rig["canvas"][0]), int(rig["canvas"][1]))
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_pantin = GkPantin.new()
	_vp.add_child(_pantin)
	_pantin.setup(_gabarit)
	_next()


func _next() -> void:
	if _jobs.is_empty():
		quit()
		return
	var j: PackedStringArray = str(_jobs[0]).split(":")
	_pantin.play(j[0])
	_pantin.pose(int(j[1]))
	_wait = 3


func _process(_dt: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var j: PackedStringArray = str(_jobs.pop_front()).split(":")
			_vp.get_texture().get_image().save_png("%s/%s_%02d.png" % [_out, j[0], int(j[1])])
			_next()
	return false
