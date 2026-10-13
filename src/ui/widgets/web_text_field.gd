class_name WebTextField
extends Node
## Champ texte HTML natif posé par-dessus un LineEdit (web tactile seulement).
## Sur iOS, Safari n'ouvre le clavier que si le focus est pris pendant le geste
## lui-même : le clavier virtuel de Godot n'y arrive pas. On place donc un vrai
## <input> au même endroit ; le doigt le touche directement et le texte est
## recopié dans le LineEdit (qui reste la source pour le reste de l'écran).

## Taille de police CSS minimale : en dessous de 16 px, iOS zoome sur le champ.
const CSS_FONT_PX: int = 16

static var _next_id: int = 0

var _edit: LineEdit
var _id: String = ""
var _el: JavaScriptObject
var _cb_input: JavaScriptObject
var _cb_key: JavaScriptObject
var _last_css: String = ""


## Branche un champ natif sur `edit` si on tourne dans un navigateur tactile.
static func attach(edit: LineEdit) -> void:
	if not OS.has_feature("web") or not DisplayServer.is_touchscreen_available():
		return
	edit.virtual_keyboard_enabled = false
	edit.add_child(WebTextField.new())


func _ready() -> void:
	# Doit tourner pendant la pause (overlay portrait) pour masquer le champ.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_edit = get_parent() as LineEdit
	_next_id += 1
	_id = "godot-text-%d" % _next_id
	JavaScriptBridge.eval("""(function(){
		var i = document.createElement('input');
		i.id = '%s'; i.type = 'text'; i.maxLength = %d;
		i.placeholder = %s;
		i.setAttribute('autocomplete', 'off'); i.setAttribute('autocorrect', 'off');
		i.setAttribute('autocapitalize', 'off'); i.spellcheck = false;
		i.enterKeyHint = 'done';
		i.style.cssText = 'position:fixed;z-index:20;box-sizing:border-box;margin:0;padding:0 6px;'
			+ 'border:2px solid #3a2634;border-radius:0;outline:none;background:#f5efe3;color:#3a2634;'
			+ 'font:%dpx monospace;display:none;';
		document.body.appendChild(i);
	})();""" % [_id, _edit.max_length if _edit.max_length > 0 else 64,
		JSON.stringify(_edit.placeholder_text), CSS_FONT_PX], true)
	var doc: JavaScriptObject = JavaScriptBridge.get_interface("document")
	_el = doc.getElementById(_id)
	_el.value = _edit.text
	_cb_input = JavaScriptBridge.create_callback(_on_input)
	_cb_key = JavaScriptBridge.create_callback(_on_key)
	_el.addEventListener("input", _cb_input)
	_el.addEventListener("keydown", _cb_key)


func _on_input(_args: Array) -> void:
	_edit.text = str(_el.value)
	_edit.text_changed.emit(_edit.text)


func _on_key(args: Array) -> void:
	var ev: JavaScriptObject = args[0]
	if str(ev.key) == "Enter":
		ev.preventDefault()
		_el.blur()
		_edit.text_submitted.emit(_edit.text)


func _process(_delta: float) -> void:
	if _el == null:
		return
	var css: String = "none"
	if _edit.is_visible_in_tree() and not get_tree().paused:
		# Le viewport logique remplit toute la fenêtre (aspect expand) :
		# on passe par des fractions, converties en CSS côté navigateur.
		var view: Vector2 = get_viewport().get_visible_rect().size
		var r: Rect2 = _edit.get_global_rect()
		var clip: Rect2 = _clip_rect()
		if clip.encloses(r):
			css = "%.5f,%.5f,%.5f,%.5f" % [r.position.x / view.x, r.position.y / view.y,
				r.size.x / view.x, r.size.y / view.y]
	# La taille de fenêtre entre dans la clé : le clavier iOS redimensionne la page.
	var key: String = "%s|%s" % [css, DisplayServer.window_get_size()]
	if key == _last_css:
		return
	_last_css = key
	if css == "none":
		_el.style.display = "none"
		return
	JavaScriptBridge.eval("""(function(){
		var c = document.querySelector('canvas').getBoundingClientRect();
		var f = [%s]; var i = document.getElementById('%s');
		i.style.left = (c.left + f[0] * c.width) + 'px';
		i.style.top = (c.top + f[1] * c.height) + 'px';
		i.style.width = (f[2] * c.width) + 'px';
		i.style.height = Math.max(f[3] * c.height, 32) + 'px';
		i.style.display = 'block';
	})();""" % [css, _id], true)


## Zone visible du plus proche ScrollContainer (sinon tout l'écran).
func _clip_rect() -> Rect2:
	var n: Node = _edit.get_parent()
	while n != null:
		if n is ScrollContainer:
			return (n as ScrollContainer).get_global_rect()
		n = n.get_parent()
	return Rect2(Vector2(-1e6, -1e6), Vector2(2e6, 2e6))


func _exit_tree() -> void:
	if _id != "":
		JavaScriptBridge.eval("var e = document.getElementById('%s'); if (e) e.remove();" % _id, true)
	_el = null
