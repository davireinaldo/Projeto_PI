extends RefCounted

# Funções de interface reutilizadas por todas as telas:
# tema, rótulos, botões, painéis, ícone de moeda, emblema de patente e barras.

const ACCENT := Color(0.1, 0.95, 0.9)
const HOT := Color(1.0, 0.25, 0.55)
const GOLD := Color(1.0, 0.82, 0.2)
const PANEL_BG := Color(0.05, 0.06, 0.1, 0.82)

static var _font: Font
static var _theme: Theme

# Fonte do jogo: Russo One (assets/fonts, licença OFL), igual em qualquer PC.
# Símbolos que ela não tem (como a seta →) vêm de uma fonte do sistema.
static func font() -> Font:
	if _font == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Sans-Serif"])
		fallback.font_weight = 700
		var f := FontVariation.new()
		f.base_font = load("res://assets/fonts/RussoOne-Regular.ttf")
		f.fallbacks = [fallback]
		_font = f
	return _font

static func style(bg: Color, border: Color, radius: int = 10, bw: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

static func theme() -> Theme:
	if _theme == null:
		var t := Theme.new()
		t.default_font = font()
		t.default_font_size = 18
		t.set_stylebox("normal", "Button", style(Color(0.06, 0.08, 0.13, 0.88), Color(0.25, 0.3, 0.4)))
		t.set_stylebox("hover", "Button", style(Color(0.1, 0.14, 0.2, 0.95), ACCENT))
		t.set_stylebox("focus", "Button", style(Color(0.1, 0.18, 0.24, 0.95), ACCENT, 10, 3))
		t.set_stylebox("pressed", "Button", style(Color(0.05, 0.4, 0.42, 0.95), ACCENT, 10, 3))
		t.set_stylebox("disabled", "Button", style(Color(0.06, 0.07, 0.1, 0.7), Color(0.18, 0.2, 0.25)))
		t.set_color("font_color", "Button", Color(0.92, 0.95, 1.0))
		t.set_color("font_hover_color", "Button", Color.WHITE)
		t.set_color("font_focus_color", "Button", Color.WHITE)
		t.set_color("font_pressed_color", "Button", Color.WHITE)
		t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.58))
		t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
		t.set_constant("outline_size", "Label", 4)
		t.set_stylebox("panel", "Panel", style(PANEL_BG, Color(0.2, 0.25, 0.35), 12))
		_theme = t
	return _theme

# Raiz de interface 480x720 que deixa os cliques passarem para o jogo.
static func root(parent: Node, layer: int = 10) -> Control:
	var cl := CanvasLayer.new()
	cl.layer = layer
	parent.add_child(cl)
	var c := Control.new()
	c.theme = theme()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(c)
	return c

static func label(parent: Control, text: String, pos: Vector2, size: int = 18, color: Color = Color.WHITE,
		width: float = 0.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0.0:
		l.size = Vector2(width, 0)
	parent.add_child(l)
	return l

static func button(parent: Control, text: String, rect: Rect2, cb: Callable, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func(): AudioManager.play("ui_click", 0.0, 0.0))
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): AudioManager.play("ui_move", -4.0, 0.0))
	parent.add_child(b)
	return b

static func panel(parent: Control, rect: Rect2, bg: Color = PANEL_BG, border: Color = Color(0.2, 0.25, 0.35)) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", style(bg, border, 12))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

# Liga os botões em coluna para navegar com setas cima/baixo.
static func chain_vertical(buttons: Array) -> void:
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		var prev: Button = buttons[(i - 1 + buttons.size()) % buttons.size()]
		var next: Button = buttons[(i + 1) % buttons.size()]
		b.focus_neighbor_top = b.get_path_to(prev)
		b.focus_neighbor_bottom = b.get_path_to(next)
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)

static func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]

# Liga/desliga a tela cheia (no navegador também; precisa vir de um clique ou tecla).
static func toggle_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_fullscreen() else DisplayServer.WINDOW_MODE_FULLSCREEN)

static func go(tree: SceneTree, scene: String) -> void:
	tree.paused = false
	GameManager.stop_run()
	AudioManager.quiet_ui()
	tree.change_scene_to_file(scene)

# ---------- desenhos ----------

static func draw_coin(ci: CanvasItem, pos: Vector2, r: float = 9.0) -> void:
	ci.draw_circle(pos + Vector2(1, 2), r, Color(0, 0, 0, 0.3))
	ci.draw_circle(pos, r, Color(0.85, 0.6, 0.05))
	ci.draw_circle(pos, r * 0.78, GOLD)
	ci.draw_rect(Rect2(pos + Vector2(-r * 0.12, -r * 0.45), Vector2(r * 0.24, r * 0.9)), Color(0.85, 0.6, 0.05))
	ci.draw_circle(pos + Vector2(-r * 0.35, -r * 0.35), r * 0.15, Color(1, 1, 0.85))

static func draw_bar(ci: CanvasItem, rect: Rect2, frac: float, color: Color) -> void:
	ci.draw_rect(rect, Color(1, 1, 1, 0.1))
	ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clamp(frac, 0.0, 1.0), rect.size.y)), color)
	ci.draw_rect(rect, Color(1, 1, 1, 0.25), false, 1.0)

static func draw_rank_badge(ci: CanvasItem, c: Vector2, r: float, index: int, dim: bool = false) -> void:
	var rank: Dictionary = GameManager.ranks[index]
	var col: Color = rank["color"]
	if dim:
		col = col.darkened(0.65)
	var shield := PackedVector2Array([
		c + Vector2(-r * 0.8, -r), c + Vector2(r * 0.8, -r), c + Vector2(r * 0.85, r * 0.15),
		c + Vector2(0, r), c + Vector2(-r * 0.85, r * 0.15)])
	if index == GameManager.ranks.size() - 1 and not dim:
		ci.draw_circle(c, r * 1.25, Color(col.r, col.g, col.b, 0.2))
	ci.draw_colored_polygon(shield, col.darkened(0.35))
	var inner := PackedVector2Array()
	for p in shield:
		inner.append(c + (p - c) * 0.78)
	ci.draw_colored_polygon(inner, col)
	ci.draw_polyline(shield + PackedVector2Array([shield[0]]), col.lightened(0.4), max(1.5, r * 0.06), true)
	var ink := col.darkened(0.55)
	if index <= 2:
		for i in range(index + 1):
			var y := c.y - r * 0.35 + i * r * 0.32
			ci.draw_polyline(PackedVector2Array([Vector2(c.x - r * 0.45, y), Vector2(c.x, y + r * 0.25), Vector2(c.x + r * 0.45, y)]),
				ink, max(2.0, r * 0.12), true)
	elif index == 3:
		_star(ci, c + Vector2(0, -r * 0.05), r * 0.45, ink)
	elif index == 4:
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.55), c + Vector2(r * 0.4, -r * 0.1),
			c + Vector2(0, r * 0.5), c + Vector2(-r * 0.4, -r * 0.1)]), ink)
	else:
		_star(ci, c + Vector2(0, -r * 0.05), r * 0.5, Color(1, 1, 1))
		_star(ci, c + Vector2(-r * 0.45, -r * 0.6), r * 0.18, Color(1, 1, 1))
		_star(ci, c + Vector2(r * 0.45, -r * 0.6), r * 0.18, Color(1, 1, 1))

static func _star(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var a := i * PI / 5.0 - PI / 2.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, color)
