class_name PortraitView
extends Sprite2D
## Portrait indexé d'un combattant (vignette de tête ou portrait RD),
## colorisé par le shader de palette selon le costume.

const SHADER: Shader = preload("res://src/fight/view/fighter_palette.gdshader")


static func create(fighter_id: String, costume: int = 0, kind: String = "portrait_small") -> PortraitView:
	var p: PortraitView = PortraitView.new()
	var path: String = "res://assets/fighters/%s/%s.png" % [fighter_id, kind]
	if not ResourceLoader.exists(path):
		path = "res://assets/fighters/louis/portrait_small.png"
	p.texture = load(path)
	p.centered = false
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("palette", load("res://assets/fighters/%s/palettes.png" % fighter_id))
	mat.set_shader_parameter("costume", costume)
	p.material = mat
	return p
