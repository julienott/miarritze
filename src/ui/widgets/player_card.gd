class_name PlayerCard
extends Control
## Carte de joueur (SPEC §3.1) : bannière basque, combattant favori dans
## son costume, pseudo, titre, emote. Utilisée au profil, au salon et au VS.

const CARD_SIZE: Vector2 = Vector2(96, 120)

var data: Dictionary = {}
var locked: bool = false        # aperçu d'un costume pas encore gagné (profil)
var _font: Font


static func create(profile: Dictionary) -> PlayerCard:
	var c: PlayerCard = PlayerCard.new()
	c.data = profile
	return c


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/press_start_2p.ttf")
	refresh()


func refresh() -> void:
	for c: Node in get_children():
		c.queue_free()
	var banner_path: String = "res://assets/ui/banner_%d.png" % int(data.get("banner", 0))
	if ResourceLoader.exists(banner_path):
		var b: TextureRect = TextureRect.new()
		b.texture = load(banner_path)
		b.position = Vector2(16, 4)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(b)
	var fighter: String = str(data.get("fighter", "louis"))
	var view: FighterView = UiKit.fighter_preview(fighter, int(data.get("costume", 0)), "idle")
	var cell: int = int(FighterDb.load_json(fighter).get("cell", 128))
	view.position = Vector2(48, 112 if cell == 128 else 116)
	view.scale = Vector2(0.75, 0.75) if cell > 128 else Vector2.ONE
	if locked:
		view.modulate = Color(0.35, 0.35, 0.42)
	add_child(view)
	add_child(_emote_bubble())
	queue_redraw()


## Emote du joueur : bulle en haut à droite, devant le combattant.
func _emote_bubble() -> Control:
	var emote: String = Profiles.EMOTES[clampi(int(data.get("emote", 0)), 0, Profiles.EMOTES.size() - 1)]
	var font: Font = load("res://assets/fonts/press_start_2p.ttf")
	var w: float = font.get_string_size(emote, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 6.0
	var bubble: Control = Control.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.position = Vector2(CARD_SIZE.x - w + 4.0, -5.0)   # dépasse du coin : ne cache pas le visage
	bubble.size = Vector2(w, 12.0)
	bubble.draw.connect(func() -> void:
		bubble.draw_rect(Rect2(Vector2.ZERO, bubble.size), Color8(58, 38, 52))
		bubble.draw_rect(Rect2(Vector2(1, 1), bubble.size - Vector2(2, 2)), Color8(247, 241, 227))
		# Petite queue de bulle vers la tête.
		bubble.draw_rect(Rect2(Vector2(4, 11), Vector2(3, 2)), Color8(58, 38, 52))
		bubble.draw_string(font, Vector2(3, 10), emote, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(58, 38, 52)))
	return bubble


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, CARD_SIZE), Color8(108, 72, 46))
	draw_rect(Rect2(Vector2(2, 2), CARD_SIZE - Vector2(4, 4)), Color8(150, 104, 62))
	draw_rect(Rect2(Vector2(4, 30), Vector2(CARD_SIZE.x - 8, 66)), Color8(64, 150, 210))
	for p: Vector2 in [Vector2(3, 3), Vector2(CARD_SIZE.x - 5, 3), Vector2(3, CARD_SIZE.y - 5), Vector2(CARD_SIZE.x - 5, CARD_SIZE.y - 5)]:
		draw_rect(Rect2(p, Vector2(2, 2)), Color8(244, 198, 62))
	var pseudo: String = str(data.get("pseudo", "?"))
	_center_text(pseudo, 104, Color8(247, 241, 227))
	if locked:
		_center_text("verrouillé", 70, Color8(244, 198, 62))
	var title_id: String = str(data.get("title", ""))
	if title_id != "" and Profiles.TITLES.has(title_id):
		_center_text(str(Profiles.TITLES[title_id][0]), 114, Color8(244, 198, 62), 8)


func _center_text(text: String, y: float, color: Color, fs: int = 8) -> void:
	var t: String = text
	while _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > CARD_SIZE.x - 6 and t.length() > 3:
		t = t.substr(0, t.length() - 2) + "…"
	var w: float = _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2((CARD_SIZE.x - w) * 0.5 + 1, y + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(58, 38, 52))
	draw_string(_font, Vector2((CARD_SIZE.x - w) * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
